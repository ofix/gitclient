import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'github_repo.dart';
import 'worker_isolate.dart';

class _QueuedJob {
  final SyncTask task;
  final void Function(SyncEvent) onEvent;
  final Completer<void> completer;
  _QueuedJob(this.task, this.onEvent, this.completer);
}

class SyncWorkerPool {
  final int maxConcurrency;
  final List<SyncWorkerIsolate> _workers = [];
  final Queue<_QueuedJob> _queue = Queue<_QueuedJob>();

  // 排重：正在运行 / 已经排队的 repoKey
  final Set<String> _runningRepos = {};
  // 保存repoKey -> 对应的future，用于重复提交时复用
  final Map<String, Future<void>> _repoPendingFutures = {};

  int _nextId = 0;
  bool _initialized = false;

  SyncWorkerPool({int? maxConcurrency}) : maxConcurrency = maxConcurrency ?? _defaultConcurrency();

  static int _defaultConcurrency() {
    final cores = Platform.numberOfProcessors;
    if (Platform.isAndroid || Platform.isIOS) {
      return cores >= 4 ? 2 : 1;
    }
    final n = cores ~/ 2;
    return n.clamp(1, 4);
  }

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    for (var i = 0; i < maxConcurrency; i++) {
      final w = SyncWorkerIsolate(_nextId++);
      await w.spawn();
      _workers.add(w);
    }
  }

  Future<void> submit(SyncTask task, void Function(SyncEvent) onEvent) {
    final repoKey = '${task.owner}/${task.repo}@${task.branch}';

    // 已经有这个repo在跑/排队：直接返回之前的future，不再新增任务
    if (_repoPendingFutures.containsKey(repoKey)) {
      return _repoPendingFutures[repoKey]!;
    }

    final completer = Completer<void>();
    final future = completer.future;
    _repoPendingFutures[repoKey] = future;
    _runningRepos.add(repoKey);

    final idle = _workers.where((w) => w.isIdle).firstOrNull;
    if (idle != null) {
      _runOn(idle, task, onEvent, repoKey, completer);
    } else {
      _queue.add(_QueuedJob(task, onEvent, completer));
    }
    return future;
  }

  Future<void> _runOn(
    SyncWorkerIsolate w,
    SyncTask task,
    void Function(SyncEvent) onEvent,
    String repoKey,
    Completer<void> completer,
  ) async {
    try {
      await w.runTask(task, onEvent);
      completer.complete();
    } catch (e, st) {
      completer.completeError(e, st);
    } finally {
      // 清理排重标记
      _runningRepos.remove(repoKey);
      _repoPendingFutures.remove(repoKey);
      _drainQueue();
    }
  }

  void _drainQueue() {
    while (_queue.isNotEmpty) {
      final idle = _workers.where((w) => w.isIdle).firstOrNull;
      if (idle == null) return;

      final job = _queue.removeFirst();
      final repoKey = '${job.task.owner}/${job.task.repo}@${job.task.branch}';
      _runOn(idle, job.task, job.onEvent, repoKey, job.completer);
    }
  }

  Future<void> shutdown() async {
    // 排队任务全部失败
    while (_queue.isNotEmpty) {
      final j = _queue.removeFirst();
      j.completer.completeError(Exception('pool shutdown'));
    }
    // 清空排重表
    _runningRepos.clear();
    _repoPendingFutures.clear();
    // 等待所有worker关闭
    await Future.wait(_workers.map((w) => w.shutdown()));
    _workers.clear();
    _initialized = false;
  }

  // 监控接口
  int get runningCount => _workers.where((w) => !w.isIdle).length;
  int get pendingCount => _queue.length;
  bool get isIdle => runningCount == 0 && _queue.isEmpty;
  Set<String> get activeRepos => Set.unmodifiable(_runningRepos);
}
