import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'github_repo.dart';
import 'zip_stream_parser.dart';

class SyncWorkerIsolate {
  final int id;
  late final Isolate _isolate;
  late final SendPort _commandPort;
  final _eventPort = ReceivePort();
  final _readyPort = ReceivePort(); // 新增：接收 worker 回传的命令端口
  bool _busy = false;
  Completer<void>? _taskCompleter;
  void Function(SyncEvent)? _currentOnEvent;
  final _readyCompleter = Completer<SendPort>();

  SyncWorkerIsolate(this.id);

  bool get isIdle => !_busy;

  Future<void> spawn() async {
    // 先监听 readyPort，worker 启动后会往这里发它自己的命令端口
    _readyPort.listen((msg) {
      if (msg is SendPort && !_readyCompleter.isCompleted) {
        _readyCompleter.complete(msg);
      }
    });

    _isolate = await Isolate.spawn(
      _workerEntry,
      WorkerInit(
        eventPort: _eventPort.sendPort,
        readyPort: _readyPort.sendPort, // 传 SendPort，不是 Completer
      ),
      debugName: 'sync-worker-$id',
    );

    _commandPort = await _readyCompleter.future;
    _eventPort.listen(_onEvent);
  }

  // ↓↓↓ 这个方法必须存在，签名要和 pool 里的调用一致 ↓↓↓
  Future<void> runTask(SyncTask task, void Function(SyncEvent) onEvent) {
    if (_busy) throw StateError('worker $id busy');
    _busy = true;
    _currentOnEvent = onEvent;
    _taskCompleter = Completer<void>();
    _commandPort.send(task);
    return _taskCompleter!.future;
  }

  void _onEvent(dynamic event) {
    if (event is SyncEvent) {
      _currentOnEvent?.call(event);
      if (event is TaskCompletedEvent || event is TaskFailedEvent) {
        _busy = false;
        _currentOnEvent = null;
        _taskCompleter?.complete();
        _taskCompleter = null;
      }
    }
  }

  void shutdown() {
    try {
      _commandPort.send(const ShutdownCommand());
    } catch (_) {}
    _isolate.kill(priority: Isolate.immediate);
    _eventPort.close();
    _readyPort.close();
  }
}

/// worker isolate 入口：长期存活，循环处理任务
void _workerEntry(WorkerInit init) async {
  final commandPort = ReceivePort();
  init.readyPort.send(commandPort.sendPort);
  final client = http.Client();

  await for (final command in commandPort) {
    if (command is ShutdownCommand) break;
    if (command is SyncTask) {
      final repoKey = '${command.owner}/${command.repo}@${command.branch}';
      try {
        final targetSha = await _resolveLatestSha(client, command);
        if (command.baseSha == null || command.baseSha == targetSha) {
          await _runZipStream(client, command, targetSha, init.eventPort, repoKey);
        } else {
          final strategy = await _decideStrategy(client, command, targetSha);
          if (strategy == SyncStrategy.compareIncremental) {
            await _runCompare(client, command, targetSha, init.eventPort, repoKey);
          } else {
            await _runZipStream(client, command, targetSha, init.eventPort, repoKey);
          }
        }
        init.eventPort.send(TaskCompletedEvent(repoKey, targetSha));
      } catch (e) {
        init.eventPort.send(TaskFailedEvent(repoKey, e.toString()));
      }
    }
  }
  client.close();
}

Map<String, String> _headers(String? token, {bool raw = false}) {
  final h = <String, String>{
    'Accept': raw ? 'application/vnd.github.raw' : 'application/vnd.github.v3+json',
  };
  if (token != null) h['Authorization'] = 'Bearer $token';
  return h;
}

Future<String> _resolveLatestSha(http.Client client, SyncTask task) async {
  final url = Uri.parse(
    'https://api.github.com/repos/${task.owner}/${task.repo}/commits/${task.branch}',
  );
  final resp = await client.get(url, headers: _headers(task.token));
  if (resp.statusCode != 200) {
    throw Exception('resolve latest sha failed: ${resp.statusCode}');
  }
  final data = jsonDecode(resp.body) as Map<String, dynamic>;
  return data['sha'] as String;
}

Future<SyncStrategy> _decideStrategy(http.Client client, SyncTask task, String targetSha) async {
  final url = Uri.parse(
    'https://api.github.com/repos/${task.owner}/${task.repo}/git/trees/$targetSha?recursive=1',
  );
  final resp = await client.get(url, headers: _headers(task.token));
  if (resp.statusCode != 200) return SyncStrategy.zipStream;
  final data = jsonDecode(resp.body) as Map<String, dynamic>;
  final tree = (data['tree'] as List?) ?? [];
  final blobCount = tree.where((e) => e['type'] == 'blob').length;
  if (data['truncated'] == true || blobCount > 5000) {
    return SyncStrategy.zipStream;
  }
  return SyncStrategy.compareIncremental;
}

Future<void> _runCompare(
  http.Client client,
  SyncTask task,
  String targetSha,
  SendPort eventPort,
  String repoKey,
) async {
  eventPort.send(PhaseChangedEvent(repoKey, 'compare'));
  final url = Uri.parse(
    'https://api.github.com/repos/${task.owner}/${task.repo}/compare/${task.baseSha}...$targetSha',
  );
  final resp = await client.get(url, headers: _headers(task.token));
  if (resp.statusCode != 200) {
    await _runZipStream(client, task, targetSha, eventPort, repoKey);
    return;
  }
  final data = jsonDecode(resp.body) as Map<String, dynamic>;
  final files = (data['files'] as List?) ?? [];
  final changed = <String>[];
  for (final f in files) {
    final status = f['status'] as String? ?? 'modified';
    if (status == 'removed') continue;
    changed.add(f['filename'] as String);
  }

  int ready = 0;
  int bytes = 0;
  for (final path in changed) {
    final rawUrl = Uri.parse(
      'https://raw.githubusercontent.com/${task.owner}/${task.repo}/$targetSha/$path',
    );
    final r = await client.get(rawUrl, headers: _headers(task.token, raw: true));
    if (r.statusCode != 200) continue;
    final file = File('${task.localRootDir}/$path');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(r.bodyBytes);
    ready++;
    bytes += r.bodyBytes.length;
    eventPort.send(
      ProgressEvent(repoKey, totalFiles: changed.length, readyFiles: ready, downloadedBytes: bytes),
    );
  }
}

Future<void> _runZipStream(
  http.Client client,
  SyncTask task,
  String targetSha,
  SendPort eventPort,
  String repoKey,
) async {
  eventPort.send(PhaseChangedEvent(repoKey, 'zip-stream'));
  final url = Uri.parse('https://codeload.github.com/${task.owner}/${task.repo}/zip/$targetSha');
  final req = http.Request('GET', url);
  if (task.token != null) {
    req.headers['Authorization'] = 'Bearer ${task.token}';
  }
  final resp = await client.send(req);
  final totalBytes = resp.contentLength;

  int ready = 0;
  int bytes = 0;
  final parser = ZipStreamParser(
    localRootDir: task.localRootDir,
    onFileReady: (path, localPath, offset) {
      ready++;
      eventPort.send(FileReadyEvent(repoKey, path, localPath, offset));
      eventPort.send(
        ProgressEvent(
          repoKey,
          totalFiles: -1,
          readyFiles: ready,
          downloadedBytes: bytes,
          totalBytes: totalBytes,
        ),
      );
    },
  );

  await for (final chunk in resp.stream) {
    bytes += chunk.length;
    await parser.feed(Uint8List.fromList(chunk));
  }
  await parser.finish();
}
