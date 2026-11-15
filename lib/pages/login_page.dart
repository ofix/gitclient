import 'package:material_ui/material_ui.dart';

import '../services/github_auth_service.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool loading = false;
  String? error;

  Future<void> _doOAuthLogin() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      await GithubAuthService.instance.login();
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/local');
      }
    } on AuthCancelledException {
      setState(() {
        error = "授权已取消";
      });
    } catch (e) {
      setState(() {
        error = "授权失败：$e";
      });
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('GitHub OAuth 授权')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("通过 GitHub 网页授权登录"),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: loading ? null : _doOAuthLogin,
                child: loading ? const CircularProgressIndicator() : const Text("跳转 GitHub 授权"),
              ),
              if (error != null) ...[
                const SizedBox(height: 16),
                Text(error!, style: const TextStyle(color: Colors.red)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
