import 'dart:async';

import 'github_repo.dart';
import 'state_store.dart';
import 'worker_pool.dart';

class SyncResult {
  final String repoKey;
  final String? resolvedSha;
  final bool success;
  final String? error;
  SyncResult({required this.repoKey, this.resolvedSha, required this.success, this.error});
}

class GitHubSyncCoordinator {
  final SyncWorkerPool _pool;
  final LocalStateStore _store;
  final _progressController = StreamController<SyncProgress>.broadcast();
  Stream<SyncProgress> get progressStream => _progressController.stream;

  // 内存快照：UI随时读最新状态
  final Map<String, SyncProgress> _repoSnapshot = {};

  GitHubSyncCoordinator({required String storePath, int? maxConcurrency})
    : _pool = SyncWorkerPool(maxConcurrency: maxConcurrency),
      _store = LocalStateStore(storePath);

  Future<void> init() => _pool.init();

  /// 【触发式】启动同步，立刻返回，UI靠progressStream监听进度
  /// 返回Future，可选await拿最终结果；重复调用会自动去重
  Future<SyncResult> triggerSync({
    required String owner,
    required String repo,
    required String branch,
    required String localRootDir,
    String? token,
    Duration? timeout,
  }) {
    return syncRepository(
      owner: owner,
      repo: repo,
      branch: branch,
      localRootDir: localRootDir,
      token: token,
      timeout: timeout,
    );
  }

  /// 【等待式】发起同步并阻塞等待完成，适合脚本/后台任务
  Future<SyncResult> syncRepository({
    required String owner,
    required String repo,
    required String branch,
    required String localRootDir,
    String? token,
    Duration? timeout,
  }) async {
    final repoKey = '$owner/$repo@$branch';
    final baseSha = await _store.readLastSha(owner, repo, branch);
    final task = SyncTask(
      owner: owner,
      repo: repo,
      branch: branch,
      baseSha: baseSha,
      localRootDir: localRootDir,
      token: token,
    );

    String? resolvedSha;
    String? error;
    bool taskOk = false;

    try {
      await _pool
          .submit(task, (event) {
            if (event is TaskCompletedEvent) {
              resolvedSha = event.resolvedTargetSha;
              taskOk = true;
            } else if (event is TaskFailedEvent) {
              error = event.message;
            }
            _forwardAsProgress(event);
          })
          .timeout(timeout ?? const Duration(minutes: 10));
    } catch (e, st) {
      error = 'coordinator error: $e\n$st';
      final snapshot = SyncProgress(
        repoKey: repoKey,
        phase: 'failed',
        totalFiles: 0,
        readyFiles: 0,
        downloadedBytes: 0,
        error: error,
      );
      _repoSnapshot[repoKey] = snapshot;
      _progressController.add(snapshot);
    }

    if (taskOk && resolvedSha != null) {
      await _store.writeLastSha(owner, repo, branch, resolvedSha!);
    }

    return SyncResult(
      repoKey: repoKey,
      resolvedSha: resolvedSha,
      success: taskOk && error == null,
      error: error,
    );
  }

  void _forwardAsProgress(SyncEvent event) {
    late SyncProgress snapshot;
    if (event is ProgressEvent) {
      snapshot = SyncProgress(
        repoKey: event.repoKey,
        phase: "stream",
        totalFiles: event.totalFiles,
        readyFiles: event.readyFiles,
        downloadedBytes: event.downloadedBytes,
        totalBytes: event.totalBytes,
        latestReadyFile: event.latestReadyFile,
      );
    } else if (event is PhaseChangedEvent) {
      snapshot = SyncProgress(
        repoKey: event.repoKey,
        phase: event.phase,
        totalFiles: 0,
        readyFiles: 0,
        downloadedBytes: 0,
      );
    } else if (event is TaskCompletedEvent) {
      snapshot = SyncProgress(
        repoKey: event.repoKey,
        phase: 'done',
        totalFiles: 0,
        readyFiles: 0,
        downloadedBytes: 0,
        isCompleted: true,
      );
    } else if (event is TaskFailedEvent) {
      snapshot = SyncProgress(
        repoKey: event.repoKey,
        phase: 'failed',
        totalFiles: 0,
        readyFiles: 0,
        downloadedBytes: 0,
        error: event.message,
      );
    } else {
      return;
    }
    _repoSnapshot[event.repoKey] = snapshot;
    _progressController.add(snapshot);
  }

  /// UI查询快照：拿到仓库当前最新进度，不用订阅stream
  SyncProgress? getSnapshot(String repoKey) => _repoSnapshot[repoKey];

  /// 清空快照（切换页面时调用）
  void clearSnapshot(String repoKey) => _repoSnapshot.remove(repoKey);
  void clearAllSnapshot() => _repoSnapshot.clear();

  Future<void> dispose() async {
    await _pool.shutdown();
    await _progressController.close();
    _repoSnapshot.clear();
  }
}
