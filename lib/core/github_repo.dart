import 'dart:isolate';
import 'dart:typed_data';

/// 文件同步状态
enum FileSyncStatus { pending, downloading, ready, failed, skipped }

/// 同步策略
enum SyncStrategy { compareIncremental, zipStream }

/// 文件元数据条目
class FileEntry {
  final String path;
  final String? blobSha;
  final int size;
  FileSyncStatus status;
  String? localPath;

  FileEntry({
    required this.path,
    this.blobSha,
    this.size = 0,
    this.status = FileSyncStatus.pending,
    this.localPath,
  });
}

/// 同步任务（主 isolate → worker isolate）
class SyncTask {
  final String owner;
  final String repo;
  final String branch;
  final String? baseSha; // null 表示首次同步
  final String localRootDir;
  final String? token;

  SyncTask({
    required this.owner,
    required this.repo,
    required this.branch,
    this.baseSha,
    required this.localRootDir,
    this.token,
  });
}

/// worker 初始化参数
class WorkerInit {
  final SendPort eventPort;
  final SendPort readyPort;
  WorkerInit({required this.eventPort, required this.readyPort});
}

/// 关闭命令
class ShutdownCommand {
  const ShutdownCommand();
}

/// 进度快照（供 UI 消费）
class SyncProgress {
  final String repoKey;
  final String phase; // metadata | compare | zip-stream | done
  final int totalFiles;
  final int readyFiles;
  final int downloadedBytes;
  final int? totalBytes;
  final FileEntry? latestReadyFile;
  final bool isCompleted;
  final String? error;

  SyncProgress({
    required this.repoKey,
    required this.phase,
    required this.totalFiles,
    required this.readyFiles,
    required this.downloadedBytes,
    this.totalBytes,
    this.latestReadyFile,
    this.isCompleted = false,
    this.error,
  });
}

/// worker → 主 isolate 的事件
sealed class SyncEvent {
  final String repoKey;
  SyncEvent(this.repoKey);
}

class PhaseChangedEvent extends SyncEvent {
  final String phase;
  PhaseChangedEvent(super.repoKey, this.phase);
}

class FileReadyEvent extends SyncEvent {
  final String path;
  final String localPath;
  final int cumulativeOffset;
  FileReadyEvent(super.repoKey, this.path, this.localPath, this.cumulativeOffset);
}

class ProgressEvent extends SyncEvent {
  final int totalFiles;
  final int readyFiles;
  final int downloadedBytes;
  final int? totalBytes;
  final FileEntry? latestReadyFile;
  ProgressEvent(
    super.repoKey, {
    required this.totalFiles,
    required this.readyFiles,
    required this.downloadedBytes,
    this.totalBytes,
    this.latestReadyFile,
  });
}

class TaskCompletedEvent extends SyncEvent {
  final String resolvedTargetSha;
  TaskCompletedEvent(super.repoKey, this.resolvedTargetSha);
}

class TaskFailedEvent extends SyncEvent {
  final String message;
  TaskFailedEvent(super.repoKey, this.message);
}

/// 流水线内部：Chunk 消息（接收 → 解压，同一 isolate 内直接调用，保留结构便于未来拆分）
class ChunkMessage {
  final Uint8List bytes;
  final int offset;
  final int sequence;
  ChunkMessage(this.bytes, this.offset, this.sequence);
}
