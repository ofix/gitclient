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

  GitHubSyncCoordinator({required String storePath, int? maxConcurrency})
    : _pool = SyncWorkerPool(maxConcurrency: maxConcurrency),
      _store = LocalStateStore(storePath);

  Future<void> init() => _pool.init();

  /// 同步一个仓库分支到最新提交
  Future<SyncResult> syncRepository({
    required String owner,
    required String repo,
    required String branch,
    required String localRootDir,
    String? token,
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
    await _pool.submit(task, (event) {
      if (event is TaskCompletedEvent) {
        resolvedSha = event.resolvedTargetSha;
      } else if (event is TaskFailedEvent) {
        error = event.message;
      }
      _forwardAsProgress(event);
    });

    if (resolvedSha != null) {
      await _store.writeLastSha(owner, repo, branch, resolvedSha!);
    }
    return SyncResult(
      repoKey: repoKey,
      resolvedSha: resolvedSha,
      success: error == null,
      error: error,
    );
  }

  void _forwardAsProgress(SyncEvent event) {
    if (event is ProgressEvent) {
      _progressController.add(
        SyncProgress(
          repoKey: event.repoKey,
          phase: 'stream',
          totalFiles: event.totalFiles,
          readyFiles: event.readyFiles,
          downloadedBytes: event.downloadedBytes,
          totalBytes: event.totalBytes,
          latestReadyFile: event.latestReadyFile,
        ),
      );
    } else if (event is PhaseChangedEvent) {
      _progressController.add(
        SyncProgress(
          repoKey: event.repoKey,
          phase: event.phase,
          totalFiles: 0,
          readyFiles: 0,
          downloadedBytes: 0,
        ),
      );
    } else if (event is TaskCompletedEvent) {
      _progressController.add(
        SyncProgress(
          repoKey: event.repoKey,
          phase: 'done',
          totalFiles: 0,
          readyFiles: 0,
          downloadedBytes: 0,
          isCompleted: true,
        ),
      );
    } else if (event is TaskFailedEvent) {
      _progressController.add(
        SyncProgress(
          repoKey: event.repoKey,
          phase: 'failed',
          totalFiles: 0,
          readyFiles: 0,
          downloadedBytes: 0,
          error: event.message,
        ),
      );
    }
  }

  Future<void> dispose() async {
    await _pool.shutdown();
    await _progressController.close();
  }
}
