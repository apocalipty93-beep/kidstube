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

  Future<void> _connectFamily(BuildContext context) async {
    final c = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Код семьи'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('1. Откройте в Telegram @$kBotName\n2. Нажмите Start\n3. Введите код из ответа бота\nПотерялся код: команда /newcode'),
          const SizedBox(height: 12),
          TextField(
            controller: c,
            autofocus: true,
            autocorrect: false,
            textCapitalization: TextCapitalization.none,
            decoration: const InputDecoration(hintText: 'например k7x2q-a9mwe'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Подключить')),
        ],
      ),
    );
    if (code == null || code.trim().isEmpty) return;
    final err = await app.checkFamily(code);
    if (!context.mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Код принят')));
    await app.setFamily(code);
  }

  Widget _head(BuildContext context, String text, {String? hint}) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          if (hint != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(hint, style: Theme.of(context).textTheme.bodySmall),
            ),
        ]),
      );

  String _info(Channel c) {
    final n = app.videos.where((v) => v.channelId == c.id).length;
    final parts = <String>[c.lang == 'ru' ? 'русский' : 'English'];
    if (!c.resolved) {
      parts.add('не найден на YouTube');
    } else if (app.videos.isNotEmpty && n == 0) {
      parts.add('нет видео: владелец запретил встраивание');
    } else if (n > 0) {
      parts.add('$n видео');
    }
    return parts.join(' • ');
  }

  Future<void> _pickLimit(BuildContext context) async {
    const opts = [0, 20, 30, 45, 60, 90];
    final v = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Сколько можно смотреть в день'),
        children: [
          for (final o in opts)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, o),
              child: Text(o == 0 ? 'Без лимита' : '$o мин'),
            ),
        ],
      ),
    );
    if (v != null) await app.setLimit(v);
  }

  Future<void> _pickBed(BuildContext context) async {
    const opts = ['', '20:00', '21:00', '22:00'];
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Время сна'),
        children: [
          for (final o in opts)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, o),
              child: Text(o.isEmpty ? 'Выкл' : o),
            ),
        ],
      ),
    );
    if (v != null) await app.setBed(v);
  }

  Future<void> _editName(BuildContext context) async {
    final c = TextEditingController(text: app.childName);
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Имя ребёнка'),
        content: TextField(
          controller: c,
          autofocus: true,
          maxLength: 20,
          decoration: const InputDecoration(hintText: 'например Мирана'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Сохранить')),
        ],
      ),
    );
    if (res != null) await app.setChildName(res.trim());
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        if (app.family.isEmpty && !app.famChosen) {
          // Сначала спрашиваем «Ваша семья», настройки показываем только после ввода кода.
          return Scaffold(
            appBar: AppBar(title: const Text('Для родителей')),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.family_restroom, size: 64),
                    const SizedBox(height: 16),
                    const Text('Ваша семья',
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    const Text(
                        'Введите код семьи из Telegram-бота. Без кода настройки не открываются.',
                        textAlign: TextAlign.center),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      icon: const Icon(Icons.vpn_key),
                      label: const Text('Ввести код семьи'),
                      onPressed: () => _connectFamily(context),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        final enabledN = app.channels.where((c) => c.enabled).length;
        return Scaffold(
          appBar: AppBar(title: const Text('Для родителей')),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              _head(context, 'Семья и Telegram',
                  hint: 'Новые каналы предлагает бот @$kBotName, вы одобряете их в Telegram. У каждой семьи свой список.'),
              ListTile(
                leading: const Icon(Icons.family_restroom),
                title: Text(app.family.isEmpty ? 'Основной каталог (без кода)' : 'Ваша семья: ${app.family.length > 5 ? '${app.family.substring(0, 5)}-${app.family.substring(5)}' : app.family}'),
                subtitle: const Text('Нажмите, чтобы ввести код из Telegram'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _connectFamily(context),
              ),
              _head(context, 'Каналы: включено $enabledN из ${app.channels.length}'),
              for (final cat in kCats.entries) ...[
                if (app.channels.any((c) => (c.cat.isEmpty ? 'cartoons' : c.cat) == cat.key))
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                    child: Text(
                      '${cat.value.toUpperCase()} • ${app.channels.where((c) => (c.cat.isEmpty ? 'cartoons' : c.cat) == cat.key).length}',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                for (final c in app.channels.where((c) => (c.cat.isEmpty ? 'cartoons' : c.cat) == cat.key))
                  SwitchListTile(
                    title: Text(c.title),
                    subtitle: Text(_info(c)),
                    value: c.enabled && c.resolved,
                    onChanged: c.resolved ? (v) => app.setChannelEnabled(c, v) : null,
                    secondary: c.thumb.isNotEmpty
                        ? CircleAvatar(backgroundImage: NetworkImage(c.thumb))
                        : CircleAvatar(child: Text(c.title.isEmpty ? '?' : c.title[0])),
                  ),
              ],
              ListTile(
                leading: const Icon(Icons.add),
                title: const Text('Добавить канал вручную'),
                subtitle: const Text('Быстрее через бота: /search запрос'),
                onTap: () => _addChannel(context),
              ),
              _head(context, 'Время и сон',
                  hint: (app.catLimit != null || app.catBed.isNotEmpty)
                      ? 'Часть значений задана в Telegram (/limit, /bedtime) и главнее настроек здесь.'
                      : 'Когда время вышло или наступил сон, приложение закрывается экраном отдыха. Продлить можно по PIN. Из Telegram: /limit и /bedtime.'),
              ListTile(
                leading: const Icon(Icons.timer_outlined),
                title: const Text('Сколько можно смотреть в день'),
                subtitle: Text(app.limit == 0 ? 'Без лимита' : '${app.limit} мин'),
                onTap: () => _pickLimit(context),
              ),
              ListTile(
                leading: const Icon(Icons.bedtime_outlined),
                title: const Text('Время сна (до 07:00 приложение закрыто)'),
                subtitle: Text(app.bed.isEmpty ? 'Выкл' : 'с ${app.bed}'),
                onTap: () => _pickBed(context),
              ),
              ListTile(
                leading: const Icon(Icons.child_care),
                title: const Text('Имя ребёнка'),
                subtitle: Text(app.childName.isEmpty ? 'не задано (показывается на экране отдыха)' : app.childName),
                onTap: () => _editName(context),
              ),
              ListTile(
                leading: const Icon(Icons.insights_outlined),
                title: Text('Сегодня просмотрено: ${(app.usedSeconds / 60).round()} мин'),
                subtitle: Text(app.topToday().isEmpty ? 'пока ничего' : app.topToday().join(' · ')),
                trailing: app.favs.isEmpty ? null : Text('❤️ ${app.favs.length}'),
              ),
              _head(context, 'Безопасность'),
              ListTile(
                leading: const Icon(Icons.text_fields),
                title: const Text('Свои стоп-слова'),
                subtitle: Text('Встроенных: ${kStopWords.length}, своих: ${app.extraWords.length}'),
                onTap: () => _editWords(context),
              ),
              ListTile(
                leading: const Icon(Icons.block),
                title: Text('Заблокированные видео: ${app.blockedVideos.length}'),
                trailing: app.blockedVideos.isEmpty
                    ? null
                    : TextButton(onPressed: app.clearBlocked, child: const Text('Сбросить')),
              ),
              ListTile(
                leading: const Icon(Icons.pin_outlined),
                title: const Text('PIN родителей'),
                subtitle: const Text('Сменить'),
                onTap: () => changePin(context),
              ),
              _head(context, 'Просмотр'),
              SwitchListTile(
                title: const Text('Сразу включать следующее видео'),
                value: app.autoNext,
                onChanged: app.setAutoNext,
              ),
              ListTile(
                leading: app.loading
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh),
                title: const Text('Обновить ленту'),
                subtitle: Text(app.error ?? '${app.videos.length} видео в ленте'),
                onTap: app.loading ? null : app.refresh,
              ),
            ],
          ),
        );
      },
    );
  }
}
