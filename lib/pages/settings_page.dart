import 'package:material_ui/material_ui.dart';

import '../services/local_repo_downloader.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _urlController;
  final _downloader = LocalRepoDownloader.instance;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: _downloader.currentBaseUrl);
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  void _saveConfig() {
    if (_formKey.currentState!.validate()) {
      _downloader.setBaseUrl(_urlController.text.trim()).then((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('服务器地址已保存'), behavior: SnackBarBehavior.floating),
        );
        Navigator.pop(context);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('服务器设置')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('后端服务地址', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _urlController,
                        decoration: const InputDecoration(
                          labelText: 'Base URL',
                          hintText: '例如: http://192.168.1.100:8080',
                          prefixIcon: Icon(Icons.link),
                          border: OutlineInputBorder(),
                          helperText: 'Android模拟器默认: http://10.0.2.2:8080',
                        ),
                        keyboardType: TextInputType.url,
                        validator: (value) {
                          if (value == null || value.isEmpty) return '请输入服务器地址';
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _saveConfig,
                icon: const Icon(Icons.save),
                label: const Text('保存配置'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
