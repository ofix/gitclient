import 'package:material_ui/material_ui.dart';

import 'services/local_archive_service.dart';
import 'pages/local_repos_page.dart';
import 'pages/login_page.dart';
import 'pages/repo_search_page.dart';
import 'pages/repo_detail_page.dart';
import 'services/github_auth_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LocalArchiveService.instance.init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Github Client',
      theme: ThemeData(useMaterial3: true),
      darkTheme: ThemeData.dark(useMaterial3: true),

      // 官方标准：material_ui 自带全套 delegates
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],

      // ✅ 删除 builder + MaterialUiCompatibilityBridge
      // 只有项目混了旧 flutter/material 的组件才需要 bridge
      routes: {
        '/local': (ctx) => const LocalReposPage(),
        '/login': (ctx) => const LoginPage(),
        '/search': (ctx) => const SearchPage(),
        '/detail': (ctx) {
          final args = ModalRoute.of(ctx)!.settings.arguments as Map;
          return RepoDetailPage(owner: args['owner'], repoName: args['repoName']);
        },
      },
      home: const GatePage(),
    );
  }
}

class GatePage extends StatefulWidget {
  const GatePage({super.key});

  @override
  State<GatePage> createState() => _GatePageState();
}

class _GatePageState extends State<GatePage> {
  bool ready = false;
  bool signedIn = false;

  @override
  void initState() {
    super.initState();
    check();
  }

  Future<void> check() async {
    final ok = await GithubAuthService.instance.hasCredential();
    if (!mounted) return;
    setState(() {
      signedIn = ok;
      ready = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return signedIn ? const LocalReposPage() : const LoginPage();
  }
}
