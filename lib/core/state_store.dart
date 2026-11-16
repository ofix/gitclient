import 'dart:convert';
import 'dart:io';

/// 记录每个 (owner, repo, branch) 上次同步的 SHA
class LocalStateStore {
  final String storePath;

  LocalStateStore(this.storePath);

  String _key(String owner, String repo, String branch) => '$owner/$repo/$branch';

  Future<Map<String, dynamic>> _readAll() async {
    final f = File(storePath);
    if (!await f.exists()) return {};
    try {
      return jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  Future<void> _writeAll(Map<String, dynamic> data) async {
    final f = File(storePath);
    await f.parent.create(recursive: true);
    await f.writeAsString(jsonEncode(data));
  }

  Future<String?> readLastSha(String owner, String repo, String branch) async {
    final all = await _readAll();
    return all[_key(owner, repo, branch)] as String?;
  }

  Future<void> writeLastSha(String owner, String repo, String branch, String sha) async {
    final all = await _readAll();
    all[_key(owner, repo, branch)] = sha;
    await _writeAll(all);
  }
}
