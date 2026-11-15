class LocalRepo {
  final String id;
  final String owner;
  final String name;
  final String ref;
  final String downloadedAt;
  final String rootDir;

  LocalRepo({
    required this.id,
    required this.owner,
    required this.name,
    required this.ref,
    required this.downloadedAt,
    required this.rootDir,
  });

  String get displayName => '$owner/$name';

  Map<String, dynamic> toJson() => {
    'id': id,
    'owner': owner,
    'name': name,
    'ref': ref,
    'downloadedAt': downloadedAt,
    'rootDir': rootDir,
  };

  factory LocalRepo.fromJson(Map<String, dynamic> json) => LocalRepo(
    id: json['id'],
    owner: json['owner'],
    name: json['name'],
    ref: json['ref'],
    downloadedAt: json['downloadedAt'],
    rootDir: json['rootDir'],
  );
}
