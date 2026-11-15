class LocalRepo {
  final String id;
  final String owner;
  final String name;
  final String ref;
  final String refType; // branch / tag / commit
  final String? localCommitSha;
  final String? remoteLatestSha;
  final String? lastSyncAt;
  final String downloadedAt;
  final String rootDir;

  LocalRepo({
    required this.id,
    required this.owner,
    required this.name,
    required this.ref,
    required this.refType,
    this.localCommitSha,
    this.remoteLatestSha,
    this.lastSyncAt,
    required this.downloadedAt,
    required this.rootDir,
  });

  LocalRepo copyWith({
    String? id,
    String? owner,
    String? name,
    String? ref,
    String? refType,
    String? localCommitSha,
    String? remoteLatestSha,
    String? lastSyncAt,
    String? downloadedAt,
    String? rootDir,
  }) {
    return LocalRepo(
      id: id ?? this.id,
      owner: owner ?? this.owner,
      name: name ?? this.name,
      ref: ref ?? this.ref,
      refType: refType ?? this.refType,
      localCommitSha: localCommitSha ?? this.localCommitSha,
      remoteLatestSha: remoteLatestSha ?? this.remoteLatestSha,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      downloadedAt: downloadedAt ?? this.downloadedAt,
      rootDir: rootDir ?? this.rootDir,
    );
  }

  bool get isStale {
    if (refType != 'branch') return false;
    if (remoteLatestSha == null || localCommitSha == null) return false;
    return localCommitSha != remoteLatestSha;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'owner': owner,
      'name': name,
      'ref': ref,
      'refType': refType,
      'localCommitSha': localCommitSha,
      'remoteLatestSha': remoteLatestSha,
      'lastSyncAt': lastSyncAt,
      'downloadedAt': downloadedAt,
      'rootDir': rootDir,
    };
  }

  factory LocalRepo.fromJson(Map<String, dynamic> json) {
    return LocalRepo(
      id: json['id'] as String,
      owner: json['owner'] as String,
      name: json['name'] as String,
      ref: json['ref'] as String,
      refType: json['refType'] as String? ?? 'branch',
      localCommitSha: json['localCommitSha'] as String?,
      remoteLatestSha: json['remoteLatestSha'] as String?,
      lastSyncAt: json['lastSyncAt'] as String?,
      downloadedAt: json['downloadedAt'] as String,
      rootDir: json['rootDir'] as String,
    );
  }
}
