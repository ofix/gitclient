import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'github_repo.dart';
import 'zip_stream_parser.dart';

class SyncWorkerIsolate {
  final int id;
  late final Isolate _isolate;
  late final SendPort _commandPort;

  final _eventPort = ReceivePort();
  final _readyPort = ReceivePort();
  StreamSubscription<dynamic>? _readySub;
  bool _busy = false;
  Completer<void>? _taskCompleter;
  void Function(SyncEvent)? _currentOnEvent;
  final _readyCompleter = Completer<SendPort>();

  SyncWorkerIsolate(this.id);

  bool get isIdle => !_busy;

  Future<void> spawn() async {
    // 保存subscription，后续cancel
    _readySub = _readyPort.listen((msg) {
      if (msg is SendPort && !_readyCompleter.isCompleted) {
        _readyCompleter.complete(msg);
      }
    });

    _isolate = await Isolate.spawn(
      _workerEntry,
      WorkerInit(eventPort: _eventPort.sendPort, readyPort: _readyPort.sendPort),
      debugName: 'sync-worker-$id',
    );
    // 监听isolate意外退出
    _isolate.addOnExitListener(_eventPort.sendPort);

    _commandPort = await _readyCompleter.future;
    _eventPort.listen(_onEvent);
  }

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
    } else if (event == null) {
      // isolate退出事件
      if (_busy) {
        _busy = false;
        _currentOnEvent = null;
        _taskCompleter?.completeError(Exception('worker $id isolate terminated unexpectedly'));
        _taskCompleter = null;
      }
    }
  }

  Future<void> shutdown() async {
    try {
      _commandPort.send(const ShutdownCommand());
    } catch (_) {}
    // 优雅等待窗口，给worker释放资源
    await Future.delayed(const Duration(milliseconds: 150));
    _isolate.kill(priority: Isolate.immediate);

    _readySub?.cancel();
    _eventPort.close();
    _readyPort.close();
  }
}

const _httpTimeout = Duration(seconds: 30);

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
  final resp = await client.get(url, headers: _headers(task.token)).timeout(_httpTimeout);
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
  try {
    final resp = await client.get(url, headers: _headers(task.token)).timeout(_httpTimeout);
    if (resp.statusCode != 200) return SyncStrategy.zipStream;
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final tree = (data['tree'] as List?) ?? [];
    final blobCount = tree.where((e) => e['type'] == 'blob').length;
    if (data['truncated'] == true || blobCount > 5000) {
      return SyncStrategy.zipStream;
    }
    return SyncStrategy.compareIncremental;
  } catch (_) {
    return SyncStrategy.zipStream;
  }
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
  final resp = await client.get(url, headers: _headers(task.token)).timeout(_httpTimeout);
  if (resp.statusCode != 200) {
    await _runZipStream(client, task, targetSha, eventPort, repoKey);
    return;
  }
  final data = jsonDecode(resp.body) as Map<String, dynamic>;
  final files = (data['files'] as List?) ?? [];

  final changedPaths = <String>[];
  final removedPaths = <String>[];

  for (final f in files) {
    final status = f['status'] as String? ?? 'modified';
    final filename = f['filename'] as String;
    final oldFilename = f['previous_filename'] as String?;

    if (status == 'removed') {
      removedPaths.add(filename);
      continue;
    }
    if (status == 'renamed') {
      // 重命名：旧文件删除，新文件下载
      if (oldFilename != null) removedPaths.add(oldFilename);
      changedPaths.add(filename);
      continue;
    }
    // added / modified
    changedPaths.add(filename);
  }

  // 处理删除
  for (final delPath in removedPaths) {
    final local = p.join(task.localRootDir, delPath);
    final f = File(local);
    if (await f.exists()) await f.delete();
  }

  int ready = 0;
  int bytes = 0;
  final total = changedPaths.length;

  for (final path in changedPaths) {
    final rawUrl = Uri.parse(
      'https://raw.githubusercontent.com/${task.owner}/${task.repo}/$targetSha/$path',
    );
    final r = await client
        .send(http.Request('GET', rawUrl)..headers.addAll(_headers(task.token, raw: true)))
        .timeout(_httpTimeout);
    if (r.statusCode != 200) continue;

    final localPath = p.join(task.localRootDir, path);
    final file = File(localPath);
    await file.parent.create(recursive: true);
    final sink = file.openWrite();
    try {
      await sink.addStream(r.stream);
    } finally {
      await sink.close();
    }
    ready++;
    bytes += r.contentLength ?? 0;
    eventPort.send(
      ProgressEvent(repoKey, totalFiles: total, readyFiles: ready, downloadedBytes: bytes),
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
  // 注意：codeload.github.com 仅公开仓库可用；私有仓库此url会404
  final url = Uri.parse('https://codeload.github.com/${task.owner}/${task.repo}/zip/$targetSha');
  final req = http.Request('GET', url);
  // codeload 不要带 Authorization，私有仓库不支持这个链路
  final resp = await client.send(req).timeout(_httpTimeout);
  final totalBytes = resp.contentLength;

  int ready = 0;
  int bytes = 0;
  final parser = ZipStreamParser(
    localRootDir: task.localRootDir,
    onFileReady: (path, localPath, offset) {
      ready++;
      eventPort.send(FileReadyEvent(repoKey, path, localPath, offset));
    },
    onError: (err) {
      eventPort.send(TaskFailedEvent(repoKey, err.toString()));
    },
  );

  try {
    await for (final chunk in resp.stream) {
      bytes += chunk.length;
      await parser.feed(Uint8List.fromList(chunk));
      eventPort.send(
        ProgressEvent(
          repoKey,
          totalFiles: -1,
          readyFiles: ready,
          downloadedBytes: bytes,
          totalBytes: totalBytes,
        ),
      );
    }
    await parser.finish();
  } catch (e) {
    // 流异常，parser兜底释放打开文件句柄
    await parser.abort();
    rethrow;
  }
}
