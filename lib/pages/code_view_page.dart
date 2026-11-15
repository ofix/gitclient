import 'dart:io';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:path/path.dart' as p;

import '../widgets/el_appbar.dart';

class CodeViewPage extends StatefulWidget {
  final String filePath;
  const CodeViewPage({super.key, required this.filePath});

  @override
  State<CodeViewPage> createState() => _CodeViewPageState();
}

class _CodeViewPageState extends State<CodeViewPage> {
  late final WebViewController controller;
  bool tooBig = false;
  bool binary = false;
  bool _assetReady = false;

  String? selectedTheme;
  List<String> themeList = [];

  String? _hljsCoreJs;
  final Map<String, String> _themeCssMap = {};

  String? _rawSource;
  String? _lang;

  @override
  void initState() {
    super.initState();
    controller = WebViewController()..setJavaScriptMode(JavaScriptMode.unrestricted);
    _loadAllAssets().then((_) {
      if (themeList.isNotEmpty) {
        selectedTheme = themeList.first;
      }
      setState(() {
        _assetReady = true;
      });
      loadFile();
    });
  }

  Future<void> _loadAllAssets() async {
    // 替换掉旧的 AssetManifest.json 读取
    final assetManifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final allAssets = assetManifest.listAssets();

    _hljsCoreJs = await rootBundle.loadString('assets/highlight/highlight.min.js');

    const stylesPrefix = 'assets/highlight/styles/';
    final themes = <String>[];

    for (final assetKey in allAssets) {
      if (assetKey.startsWith(stylesPrefix) && assetKey.endsWith('.min.css')) {
        final fileName = p.basename(assetKey);
        final themeName = fileName.replaceAll('.min.css', '');
        final cssText = await rootBundle.loadString(assetKey);
        _themeCssMap[themeName] = cssText;
        themes.add(themeName);
      }
    }

    themes.sort();
    setState(() {
      themeList = themes;
    });
  }

  String _escapeStyleContent(String raw) {
    return raw.replaceAll('</style>', r'<\/style>');
  }

  Future<void> loadFile() async {
    if (!_assetReady || _hljsCoreJs == null) return;
    final f = File(widget.filePath);
    if (!await f.exists()) return;

    final ext = p.extension(widget.filePath).toLowerCase();
    const binaryExt = {
      '.png',
      '.jpg',
      '.jpeg',
      '.gif',
      '.webp',
      '.zip',
      '.pdf',
      '.bmp',
      '.mp4',
      '.mp3',
      '.ico',
    };
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
    // raw = raw
    //     .replaceAll('&', '&amp;')
    //     .replaceAll('<', '&lt;')
    //     .replaceAll('>', '&gt;')
    //     .replaceAll('"', '&quot;')
    //     .replaceAll("'", '&#039;');

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

    _rawSource = raw;
    _lang = lang;

    await _rebuildAndLoadHtml();
  }

  Future<void> _rebuildAndLoadHtml() async {
    if (_rawSource == null || _hljsCoreJs == null) return; // 确保 _hljsCoreJs 不为空

    var css = _themeCssMap[selectedTheme] ?? '';
    final escapedCss = _escapeStyleContent(css);

    // 1. 用 HtmlEscape 处理源码，防止破坏 HTML 结构
    final escapedSource = const HtmlEscape().convert(_rawSource!);

    // 2. 用 jsonEncode 安全地把 JS 代码转成合法的 JS 字符串字面量
    // 这样即使 highlight.js 内部有单引号、双引号、换行符，也不会报错
    final safeJs = jsonEncode(_hljsCoreJs!);

    final html =
        '''
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1.0">
<style>
$escapedCss
</style>
<style>
body { margin: 0; padding: 8px; font-size:14px; background: transparent; }
pre { margin: 0; overflow-x: hidden; } /* 隐藏横向滚动 */
code { 
  padding: 12px; 
  display: block; 
  white-space: pre-wrap; /* 关键：保留空格，但允许自动换行 */
  word-break: break-all; /* 关键：遇到长单词（如长 URL）强制断行 */
}
</style>
</head>
<body>
<pre><code class="hljs language-${_lang ?? ''}">$escapedSource</code></pre>
<script>
  // 动态执行 highlight.js 核心代码
  const scriptStr = $safeJs;
  const scriptEl = document.createElement('script');
  scriptEl.textContent = scriptStr;
  document.head.appendChild(scriptEl);

  // 注入后立即执行高亮，用 setTimeout 确保浏览器有足够时间解析 DOM
  setTimeout(function() {
    if (window.hljs) {
      // 如果带有 language-xxx 类名，可以直接 highlightAll
      hljs.highlightAll();
    }
  }, 100);
</script>
</body>
</html>
''';
    await controller.loadHtmlString(html);
  }

  Future<void> _applyTheme(String themeName) async {
    setState(() {
      selectedTheme = themeName;
    });
    await _rebuildAndLoadHtml();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: ElAppBar(
        title: Text(p.basename(widget.filePath)),
        actions: [
          if (themeList.isNotEmpty)
            DropdownButton<String>(
              value: selectedTheme,
              dropdownColor: Colors.grey.shade900,
              items: themeList
                  .map(
                    (name) => DropdownMenuItem(
                      value: name,
                      child: Text(name, style: const TextStyle(color: Colors.white)),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                if (v == null) return;
                _applyTheme(v);
              },
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: binary
          ? const Center(child: Text('⚠️ 二进制文件，无法预览'))
          : tooBig
          ? const Center(child: Text('⚠️ 文件超过 512KB，拒绝加载，防止 OOM'))
          : WebViewWidget(controller: controller),
    );
  }
}
