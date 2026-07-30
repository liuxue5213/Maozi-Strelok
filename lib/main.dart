import 'package:flutter/material.dart';

import 'services/database_service.dart';
import 'ui/app_state.dart';
import 'ui/home_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BallisticsApp());
}

class BallisticsApp extends StatelessWidget {
  const BallisticsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ballistics Calculator',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF1B5E20),
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF1B5E20),
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      home: const Splash(),
    );
  }
}

class Splash extends StatefulWidget {
  const Splash({super.key});

  @override
  State<Splash> createState() => _SplashState();
}

class _SplashState extends State<Splash> {
  late final Future<AppState> _load;

  @override
  void initState() {
    super.initState();
    _load = _loadState();
  }

  Future<AppState> _loadState() async {
    final db = DatabaseService();
    await db.load();
    final state = AppState(db);
    await state.loadSettings();
    return state;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppState>(
      future: _load,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const MaterialApp(
            home: Scaffold(
              body: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('加载武器数据库…'),
                  ],
                ),
              ),
            ),
          );
        }
        return ListenableBuilder(
          listenable: snap.data!,
          builder: (context, _) => MaterialApp(
            title: 'Ballistics Calculator',
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              colorSchemeSeed: const Color(0xFF1B5E20),
              useMaterial3: true,
              brightness: Brightness.light,
            ),
            darkTheme: ThemeData(
              colorSchemeSeed: const Color(0xFF1B5E20),
              useMaterial3: true,
              brightness: Brightness.dark,
            ),
            home: HomePage(state: snap.data!),
          ),
        );
      },
    );
  }
}
