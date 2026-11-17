import 'package:flutter/material.dart';
import 'app_state.dart';

Future<String?> _pinDialog(BuildContext context, String title) {
  final c = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        obscureText: true,
        keyboardType: TextInputType.number,
        maxLength: 4,
        decoration: const InputDecoration(counterText: ''),
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text),
            child: const Text('ОК')),
      ],
    ),
  );
}

/// Возвращает true, если родитель ввёл верный PIN
/// (при первом входе предлагает придумать PIN).
Future<bool> askPin(BuildContext context) async {
  if (app.pin.isEmpty) {
    final p = await _pinDialog(context, 'Придумайте PIN для родителей (4 цифры)');
    if (p == null || p.length != 4) return false;
    await app.setPin(p);
    return true;
  }
  final p = await _pinDialog(context, 'PIN для родителей');
  if (p == app.pin) return true;
  if (p != null && context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Неверный PIN')));
  }
  return false;
}

Future<void> changePin(BuildContext context) async {
  final p = await _pinDialog(context, 'Новый PIN (4 цифры)');
  if (p != null && p.length == 4) await app.setPin(p);
}
