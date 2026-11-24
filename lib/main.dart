import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_state.dart';
import 'home.dart';
import 'lock.dart';

final GlobalKey<NavigatorState> navKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await app.init();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const KidsApp());
}

class KidsApp extends StatefulWidget {
  const KidsApp({super.key});
  @override
  State<KidsApp> createState() => _KidsAppState();
}

class _KidsAppState extends State<KidsApp> {
  Timer? _t;
  bool _locked = false;

  @override
  void initState() {
    super.initState();
    // Раз в секунду проверяем лимит времени и время сна; при необходимости поверх всего открываем экран отдыха.
    _t = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (_locked || app.lockReason() == null) return;
      final nav = navKey.currentState;
      if (nav == null) return;
      _locked = true;
      await nav.push(MaterialPageRoute(builder: (_) => const LockScreen()));
      _locked = false;
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navKey,
      title: 'Мультики',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFF7043),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFFFF8F0),
      ),
      home: const HomeScreen(),
    );
  }
}
