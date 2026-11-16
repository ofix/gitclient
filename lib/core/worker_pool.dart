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
  final _workers = <SyncWorkerIsolate>[];
  final _queue = Queue<_QueuedJob>();
  int _nextId = 0;
  bool _initialized = false;

  SyncWorkerPool({int? maxConcurrency}) : maxConcurrency = maxConcurrency ?? _defaultConcurrency();

  static int _defaultConcurrency() {
    final cores = Platform.numberOfProcessors;
    // 移动端保守：最多 2；桌面端取 cores ~/ 2，最多 4
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
    final idle = _workers.where((w) => w.isIdle).firstOrNull;
    if (idle != null) {
      return _runOn(idle, task, onEvent);
    }
    final completer = Completer<void>();
    _queue.add(_QueuedJob(task, onEvent, completer));
    return completer.future;
  }

  Future<void> _runOn(SyncWorkerIsolate w, SyncTask task, void Function(SyncEvent) onEvent) async {
    try {
      await w.runTask(task, onEvent);
    } finally {
      _drainQueue();
    }
  }

  void _drainQueue() {
    while (_queue.isNotEmpty) {
      final idle = _workers.where((w) => w.isIdle).firstOrNull;
      if (idle == null) return;
      final job = _queue.removeFirst();
      idle.runTask(job.task, job.onEvent).whenComplete(job.completer.complete);
    }
  }

  Future<void> shutdown() async {
    for (final w in _workers) {
      w.shutdown();
    }
    _workers.clear();
    _initialized = false;
  }
}
