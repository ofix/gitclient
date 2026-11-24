import 'package:material_ui/material_ui.dart';

import '../services/local_repo_downloader.dart';
import 'settings_page.dart';

class FileManagerPage extends StatefulWidget {
  const FileManagerPage({super.key});

  @override
  State<FileManagerPage> createState() => _FileManagerPageState();
}

class _FileManagerPageState extends State<FileManagerPage> {
  final LocalRepoDownloader _downloader = LocalRepoDownloader.instance;

  List<FileItem> fileList = [];
  bool isLoading = false;
  double downloadProgress = -1;

  @override
  void initState() {
    super.initState();
    _downloader.loadBaseUrl().then((_) => _fetchRootDirectory());
  }

  Future<void> _fetchRootDirectory() async {
    setState(() => isLoading = true);
    try {
      fileList = await _downloader.fetchDirectory('.');
    } catch (e) {
      _showMessage(e.toString());
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _toggleExpand(FileItem item) async {
    if (item.isDir) {
      if (!item.isExpanded && item.children.isEmpty) {
        try {
          item.children = await _downloader.fetchDirectory(item.path);
        } catch (e) {
          _showMessage('加载子目录失败: $e');
          return;
        }
      }
      setState(() => item.isExpanded = !item.isExpanded);
    }
  }

  Future<void> _startDownload() async {
    final selectedPaths = _getCheckedPaths(fileList);
    if (selectedPaths.isEmpty) {
      _showMessage('请先勾选需要下载的内容');
      return;
    }

    setState(() => downloadProgress = 0);

    try {
      final savePath = await _downloader.downloadZip(selectedPaths, (progress) {
        if (mounted) setState(() => downloadProgress = progress);
      });

      if (mounted) {
        setState(() => downloadProgress = -1);
        _showMessage('下载成功！\n路径: $savePath');
      }
    } catch (e) {
      if (mounted) {
        setState(() => downloadProgress = -1);
        _showMessage(e.toString());
      }
    }
  }

  List<String> _getCheckedPaths(List<FileItem> items) {
    List<String> paths = [];
    for (var item in items) {
      if (item.isChecked) paths.add(item.path);
      if (item.children.isNotEmpty) paths.addAll(_getCheckedPaths(item.children));
    }
    return paths;
  }

  void _showMessage(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('源码提取器'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: '服务器设置',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsPage()),
              );
              // 返回后刷新目录，防止用户修改了地址
              _fetchRootDirectory();
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
            onPressed: _fetchRootDirectory,
          ),
        ],
      ),
      body: Stack(
        children: [
          // 顶部显示当前服务器地址提示
          if (_downloader.currentBaseUrl.isNotEmpty)
            Container(
              width: double.infinity,
              color: Colors.blue.shade50,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                '当前服务: ${_downloader.currentBaseUrl}',
                style: TextStyle(fontSize: 12, color: Colors.blue.shade700),
              ),
            ),

          // 主体列表
          Padding(
            padding: const EdgeInsets.only(top: 36), // 为顶部提示留出空间
            child: isLoading && fileList.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _buildTree(fileList),
          ),

          // 下载进度遮罩 (使用 Material 的 LinearProgressIndicator)
          if (downloadProgress >= 0) _buildProgressOverlay(),
        ],
      ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget _buildTree(List<FileItem> items) {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: items.length,
      itemBuilder: (context, index) => _buildNode(items[index]),
    );
  }

  Widget _buildNode(FileItem item) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          margin: const EdgeInsets.only(bottom: 8),
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            leading: item.isDir
                ? IconButton(
                    icon: Icon(
                      item.isExpanded ? Icons.expand_more : Icons.chevron_right,
                      color: Colors.grey,
                    ),
                    onPressed: () => _toggleExpand(item),
                  )
                : const Icon(Icons.insert_drive_file_outlined, color: Colors.grey),
            title: Text(
              item.name,
              style: const TextStyle(fontSize: 16),
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Checkbox(
              value: item.isChecked,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(4)),
              ),
              onChanged: (val) => setState(() => item.isChecked = val ?? false),
            ),
            onTap: () => item.isDir ? _toggleExpand(item) : null,
          ),
        ),
        if (item.isDir && item.isExpanded && item.children.isNotEmpty)
          Padding(padding: const EdgeInsets.only(left: 20), child: _buildTree(item.children)),
      ],
    );
  }

  Widget _buildProgressOverlay() {
    return Container(
      color: Colors.black54,
      child: Center(
        child: Card(
          margin: const EdgeInsets.all(32),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '正在打包下载...',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                LinearProgressIndicator(value: downloadProgress),
                const SizedBox(height: 8),
                Text('${(downloadProgress * 100).toStringAsFixed(1)}%'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return BottomAppBar(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SizedBox(
          width: double.infinity,
          height: 50,
          child: FilledButton.icon(
            onPressed: downloadProgress >= 0 ? null : _startDownload,
            icon: const Icon(Icons.download),
            label: const Text('打包下载', style: TextStyle(fontSize: 16)),
          ),
        ),
      ),
    );
  }
}
