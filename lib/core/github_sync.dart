export 'github_repo.dart';
export 'coordinator.dart';

// 调用示例
// import 'package:flutter/material.dart';
// import 'github_sync.dart';

// final coordinator = GitHubSyncCoordinator(
//   storePath: '/path/to/cache/sync_state.json',
//   maxConcurrency: null, // 动态默认
// );
// await coordinator.init();

// coordinator.progressStream.listen((p) {
//   // p.repoKey 区分不同仓库；p.phase、p.readyFiles、p.totalFiles 驱动 UI
// });

// // 并发提交多个仓库，线程池自动限流
// final results = await Future.wait([
//   coordinator.syncRepository(
//     owner: 'flutter', repo: 'flutter', branch: 'master',
//     localRootDir: '/cache/flutter', token: token,
//   ),
//   coordinator.syncRepository(
//     owner: 'dart-lang', repo: 'sdk', branch: 'main',
//     localRootDir: '/cache/dart-sdk', token: token,
//   ),
// ]);
