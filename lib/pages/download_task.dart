import 'package:dio/dio.dart';

enum DownloadStatus { idle, downloading, paused, done, failed }

class DownloadTaskItem {
  final String repoId;
  final String owner;
  final String repoName;
  final String branch;

  DownloadStatus status;
  int receivedBytes;
  int? totalBytes;
  CancelToken cancelToken;

  DownloadTaskItem({
    required this.repoId,
    required this.owner,
    required this.repoName,
    required this.branch,
    this.status = DownloadStatus.idle,
    this.receivedBytes = 0,
    this.totalBytes,
    required this.cancelToken,
  });
}
