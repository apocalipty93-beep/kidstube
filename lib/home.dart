import 'package:flutter/material.dart';
import 'app_state.dart';
import 'config.dart';
import 'models.dart';
import 'parent.dart';
import 'pin.dart';
import 'player.dart';
import 'widgets.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _filter = 'all'; // all | ru | en | cat:<id> | ch:<id>
  bool _searching = false;
  final _q = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  List<Video> _apply(List<Video> all) {
    var l = all;
    if (_filter == 'ru' || _filter == 'en') {
      l = l.where((v) => v.lang == _filter).toList();
    } else if (_filter.startsWith('cat:')) {
      final cid = _filter.substring(4);
      final on = app.channels
          .where((c) => c.cat == cid && c.enabled && c.resolved)
          .map((c) => c.id)
          .toSet();
      l = l.where((v) => on.contains(v.channelId)).toList();
    } else if (_filter.startsWith('ch:')) {
      final id = _filter.substring(3);
      l = l.where((v) => v.channelId == id).toList();
    }
    final q = _q.text.trim().toLowerCase();
    if (_searching && q.isNotEmpty) {
      l = l.where((v) => v.title.toLowerCase().contains(q)).toList();
    }
    return l;
  }

  Future<void> _openParent() async {
    final ok = await askPin(context);
    if (ok && mounted) {
      await Navigator.push(
          context, MaterialPageRoute(builder: (_) => const ParentScreen()));
    }
  }

  Widget _avatar(Channel c) {
    final sel = _filter == 'ch:${c.id}';
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(40),
        onTap: () => setState(() => _filter = sel ? 'all' : 'ch:${c.id}'),
        child: SizedBox(
          width: 76,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: sel ? cs.primary : Colors.transparent, width: 3),
                ),
                child: CircleAvatar(
                  radius: 27,
                  backgroundColor: cs.primaryContainer,
                  backgroundImage:
                      c.thumb.isNotEmpty ? NetworkImage(c.thumb) : null,
                  child: c.thumb.isEmpty
                      ? Text(c.title.isEmpty ? '?' : c.title.substring(0, 1))
                      : null,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                c.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: sel ? FontWeight.bold : FontWeight.normal),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(String key, String label) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: _filter == key,
        onSelected: (_) => setState(() => _filter = key),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final all = app.visible;
        if (_filter.startsWith('cat:') &&
            !app.channels.any((c) =>
                c.cat == _filter.substring(4) && c.enabled && c.resolved)) {
          _filter = 'all';
        }
        final list = _apply(all);
        final chById = {for (final c in app.channels) c.id: c};
        final present = <String>{
          for (final v in all) chById[v.channelId]?.cat ?? 'cartoons'
        };
        final hasVid = {for (final v in all) v.channelId};
        final chs = app.channels
            .where((c) => c.enabled && c.resolved && hasVid.contains(c.id));
        return Scaffold(
          appBar: AppBar(
            backgroundColor: const Color(0xFFFFF8F0),
            title: _searching
                ? TextField(
                    controller: _q,
                    autofocus: true,
                    decoration: const InputDecoration(
                        hintText: 'Поиск мультиков', border: InputBorder.none),
                    onChanged: (_) => setState(() {}),
                  )
                : const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.smart_display_rounded, color: Color(0xFFFF7043)),
                      SizedBox(width: 8),
                      Text('Мультики',
                          style: TextStyle(fontWeight: FontWeight.w800)),
                    ],
                  ),
            actions: [
              IconButton(
                icon: Icon(_searching ? Icons.close : Icons.search),
                onPressed: () => setState(() {
                  _searching = !_searching;
                  _q.clear();
                }),
              ),
              IconButton(
                icon: const Icon(Icons.lock_outline),
                tooltip: 'Для родителей',
                onPressed: _openParent,
              ),
            ],
          ),
          body: Column(
            children: [
              SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  children: [
                    _chip('all', 'Все'),
                    _chip('ru', 'Русские'),
                    _chip('en', 'English'),
                    for (final e in kCats.entries)
                      if (present.contains(e.key)) _chip('cat:${e.key}', e.value),
                  ],
                ),
              ),
              SizedBox(
                height: 104,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  children: [for (final c in chs) _avatar(c)],
                ),
              ),
              Expanded(child: _body(list, all.isEmpty)),
            ],
          ),
        );
      },
    );
  }

  Widget _body(List<Video> list, bool nothingAtAll) {
    if (app.loading && nothingAtAll) {
      return const Center(child: CircularProgressIndicator());
    }
    if (nothingAtAll) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(app.error ?? 'Пока нет мультиков. Потяните вниз или нажмите «Обновить».',
                  textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                  onPressed: app.refresh, child: const Text('Обновить')),
            ],
          ),
        ),
      );
    }
    if (list.isEmpty) {
      return const Center(child: Text('Ничего не найдено'));
    }
    return LayoutBuilder(builder: (context, box) {
      const pad = 12.0;
      const gap = 12.0;
      final cols = (box.maxWidth / 380).floor().clamp(1, 4);
      final itemW = (box.maxWidth - pad * 2 - gap * (cols - 1)) / cols;
      final ts = MediaQuery.textScalerOf(context);
      final textH = ts.scale(16) * 1.4 * 2 + ts.scale(12) * 1.4 + 16;
      return RefreshIndicator(
        onRefresh: app.refresh,
        child: GridView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(pad),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisSpacing: gap,
            crossAxisSpacing: gap,
            mainAxisExtent: itemW * 9 / 16 + textH,
          ),
          itemCount: list.length,
          itemBuilder: (context, i) => VideoCard(
            video: list[i],
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PlayerScreen(video: list[i], all: list),
              ),
            ),
          ),
        ),
      );
    });
  }
}
