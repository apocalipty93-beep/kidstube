import 'package:flutter/material.dart';
import 'api.dart';
import 'app_state.dart';
import 'config.dart';
import 'models.dart';
import 'pin.dart';

class ParentScreen extends StatelessWidget {
  const ParentScreen({super.key});

  String? _parseHandle(String input) {
    final s = input.trim();
    if (s.isEmpty) return null;
    final at = s.indexOf('@');
    if (at >= 0) {
      final rest = s.substring(at + 1);
      final end = rest.indexOf(RegExp(r'[/?#\s]'));
      final h = end >= 0 ? rest.substring(0, end) : rest;
      return h.isEmpty ? null : h;
    }
    if (s.contains('/')) return null; // ссылки без @ не поддерживаем
    return s;
  }

  Future<void> _addChannel(BuildContext context) async {
    final c = TextEditingController();
    final input = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Добавить канал'),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: const InputDecoration(
              hintText: '@handle или ссылка youtube.com/@handle'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Отмена')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, c.text),
              child: const Text('Найти')),
        ],
      ),
    );
    if (input == null) return;
    final h = _parseHandle(input);
    if (h == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Нужен @handle канала, например @Bluey')));
      }
      return;
    }
    Channel? found;
    try {
      found = await Yt.resolveHandle(h, custom: true);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Ошибка: $e')));
      }
      return;
    }
    if (found == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Канал не найден')));
      }
      return;
    }
    final Channel ch = found;
    if (!context.mounted) return;
    final lang = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Найден: ${ch.title}'),
        content: const Text('Добавить в белый список? Выберите язык канала.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Отмена')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, 'ru'),
              child: const Text('Русский')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, 'en'),
              child: const Text('English')),
        ],
      ),
    );
    if (lang == null) return;
    ch.lang = lang;
    await app.addChannel(ch);
    await app.refresh();
  }

  Future<void> _editWords(BuildContext context) async {
    final c = TextEditingController(text: app.extraWords.join(', '));
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Свои стоп-слова'),
        content: TextField(
          controller: c,
          maxLines: 4,
          decoration: const InputDecoration(
              hintText: 'через запятую: слово1, слово2'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Отмена')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, c.text),
              child: const Text('Сохранить')),
        ],
      ),
    );
    if (res == null) return;
    await app.setExtraWords(res
        .split(',')
        .map((e) => e.trim().toLowerCase())
        .where((e) => e.isNotEmpty)
        .toList());
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(title: const Text('Для родителей')),
          body: ListView(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text('Разрешённые каналы',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              for (final c in app.channels)
                SwitchListTile(
                  title: Text(c.title),
                  subtitle: Text(c.resolved
                      ? '@${c.handle} • ${c.lang == 'ru' ? 'русский' : 'English'} • ${kCats[c.cat] ?? 'Мультики'}'
                      : '@${c.handle} — не найден на YouTube'),
                  value: c.enabled && c.resolved,
                  onChanged: c.resolved
                      ? (v) => app.setChannelEnabled(c, v)
                      : null,
                  secondary: c.custom || !c.resolved
                      ? IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => app.removeChannel(c),
                        )
                      : null,
                ),
              ListTile(
                leading: const Icon(Icons.add),
                title: const Text('Добавить канал'),
                onTap: () => _addChannel(context),
              ),
              const Divider(),
              SwitchListTile(
                title: const Text('Автоматически включать следующее видео'),
                value: app.autoNext,
                onChanged: app.setAutoNext,
              ),
              ListTile(
                leading: const Icon(Icons.text_fields),
                title: const Text('Свои стоп-слова'),
                subtitle: Text(
                    'Встроенных: ${kStopWords.length}, своих: ${app.extraWords.length}'),
                onTap: () => _editWords(context),
              ),
              ListTile(
                leading: const Icon(Icons.block),
                title: Text('Заблокированные видео: ${app.blockedVideos.length}'),
                trailing: app.blockedVideos.isEmpty
                    ? null
                    : TextButton(
                        onPressed: app.clearBlocked,
                        child: const Text('Сбросить')),
              ),
              ListTile(
                leading: const Icon(Icons.pin_outlined),
                title: const Text('Сменить PIN'),
                onTap: () => changePin(context),
              ),
              ListTile(
                leading: app.loading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh),
                title: const Text('Обновить ленту сейчас'),
                subtitle: app.error == null ? null : Text(app.error!),
                onTap: app.loading ? null : app.refresh,
              ),
            ],
          ),
        );
      },
    );
  }
}
