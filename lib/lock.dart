import 'dart:async';
import 'package:flutter/material.dart';
import 'app_state.dart';
import 'pin.dart';

/// Экран отдыха: лимит времени исчерпан или время сна. Закрыть можно только по PIN родителей.
class LockScreen extends StatefulWidget {
  const LockScreen({super.key});
  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 2), (_) {
      if (app.lockReason() == null && mounted) Navigator.of(context).pop();
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  Future<void> _parent() async {
    final ok = await askPin(context);
    if (!ok || !mounted) return;
    final choice = await showModalBottomSheet<int>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.add_alarm),
              title: const Text('Продлить на 15 минут'),
              onTap: () => Navigator.pop(ctx, 15),
            ),
            ListTile(
              leading: const Icon(Icons.add_alarm),
              title: const Text('Продлить на 30 минут'),
              onTap: () => Navigator.pop(ctx, 30),
            ),
          ],
        ),
      ),
    );
    if (choice != null) {
      await app.extend(choice);
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bed = app.lockReason() == 'bed';
    final nm = app.effName;
    final title = bed
        ? 'Пора спать${nm.isEmpty ? '' : ', $nm'}!'
        : 'Мультики на сегодня всё${nm.isEmpty ? '' : ', $nm'}!';
    final sub = bed
        ? 'Сладких снов. Завтра будут новые мультики.'
        : 'Давай поиграем во что-нибудь другое. Завтра снова посмотрим.';
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF1C2541),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(bed ? '🌙' : '⏰', style: const TextStyle(fontSize: 96)),
                  const SizedBox(height: 16),
                  Text(title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 30,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  Text(sub,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70, fontSize: 17)),
                  const SizedBox(height: 32),
                  IconButton.filledTonal(
                    iconSize: 36,
                    icon: const Icon(Icons.settings),
                    tooltip: 'Для родителей',
                    onPressed: _parent,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
