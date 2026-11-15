import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:path/path.dart' as p;

class CodeViewPage extends StatefulWidget {
  final String filePath;
  const CodeViewPage({super.key, required this.filePath});

  @override
  State<CodeViewPage> createState() => _CodeViewPageState();
}

class _CodeViewPageState extends State<CodeViewPage> {
  late final WebViewController controller;
  String? html;
  bool tooBig = false;
  bool binary = false;

  @override
  void initState() {
    super.initState();
    controller = WebViewController()..setJavaScriptMode(JavaScriptMode.unrestricted);
    loadFile();
  }

  Future<void> loadFile() async {
    final f = File(widget.filePath);
    if (!await f.exists()) return;

    final ext = p.extension(widget.filePath).toLowerCase();
    const binaryExt = {'.png', '.jpg', '.jpeg', '.gif', '.webp', '.zip', '.pdf'};
    if (binaryExt.contains(ext)) {
      setState(() => binary = true);
      return;
    }

    final stat = await f.stat();
    const maxBytes = 512 * 1024;
    if (stat.size > maxBytes) {
      setState(() => tooBig = true);
      return;
    }

    String raw = await f.readAsString();
    raw = raw.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

    String lang = '';
    final map = <String, String>{
      '.dart': 'dart',
      '.js': 'javascript',
      '.ts': 'typescript',
      '.py': 'python',
      '.go': 'go',
      '.rs': 'rust',
      '.cpp': 'cpp',
      '.c': 'c',
      '.h': 'cpp',
      '.java': 'java',
      '.sh': 'bash',
      '.sql': 'sql',
      '.json': 'json',
      '.yaml': 'yaml',
      '.yml': 'yaml',
      '.md': 'markdown',
    };
    if (map.containsKey(ext)) lang = map[ext]!;

    html =
        '''
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1.0">
<link rel="stylesheet" href="asset:///assets/highlight/github-dark.min.css">
<style>
body { margin: 0; padding: 8px; font-size:14px; }
pre { margin:0; white-space: pre; }
code.hljs { padding: 12px; }
</style>
</head>
<body>
<pre><code class="hljs $lang">$raw</code></pre>
<script src="asset:///assets/highlight/highlight.min.js"></script>
<script>hljs.highlightAll();</script>
</body>
</html>
''';
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(p.basename(widget.filePath))),
      body: binary
          ? const Center(child: Text('⚠️ 二进制文件，无法预览'))
          : tooBig
          ? const Center(child: Text('⚠️ 文件超过 512KB，拒绝加载，防止 OOM'))
          : html == null
          ? const Center(child: CircularProgressIndicator())
          : WebViewWidget(controller: controller..loadHtmlString(html!)),
    );
  }
}
