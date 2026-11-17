import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'api.dart';
import 'config.dart';
import 'models.dart';

class AppState extends ChangeNotifier {
  late SharedPreferences _p;
  List<Channel> channels = [];
  List<Video> videos = [];
  Set<String> blockedVideos = {};
  Set<String> seedsSeen = {};
  List<String> extraWords = [];
  String pin = '';
  bool autoNext = true;
  bool loading = false;
  String? error;
  DateTime? lastRefresh;

  List<String> get words => [...kStopWords, ...extraWords];

  List<Video> get visible {
    final on = channels.where((c) => c.enabled).map((c) => c.id).toSet();
    final w = words;
    return videos
        .where((v) =>
            on.contains(v.channelId) &&
            !blockedVideos.contains(v.id) &&
            !isBlockedText(v.title, w))
        .toList();
  }

  Future<void> init() async {
    _p = await SharedPreferences.getInstance();
    pin = _p.getString('pin') ?? '';
    autoNext = _p.getBool('autoNext') ?? true;
    blockedVideos = (_p.getStringList('blockedVideos') ?? []).toSet();
    extraWords = _p.getStringList('extraWords') ?? [];
    seedsSeen = (_p.getStringList('seedsSeen') ?? []).toSet();
    try {
      final ch = _p.getString('channels');
      if (ch != null) {
        channels = (jsonDecode(ch) as List)
            .map((e) => Channel.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      final vs = _p.getString('videos');
      if (vs != null) {
        videos = (jsonDecode(vs) as List)
            .map((e) => Video.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {
      channels = [];
      videos = [];
    }
    final lr = _p.getInt('lastRefresh');
    if (lr != null) lastRefresh = DateTime.fromMillisecondsSinceEpoch(lr);
    _addSeeds();
    notifyListeners();
    final changed = await syncCatalog();
    final stale = lastRefresh == null ||
        DateTime.now().difference(lastRefresh!) > const Duration(hours: 6);
    if (changed || channels.isEmpty || videos.isEmpty || stale) {
      await refresh();
    }
  }

  String _catOfSeed(String handle) {
    final h = handle.toLowerCase();
    for (final s in kSeeds) {
      if (s.handle.toLowerCase() == h) return s.cat;
    }
    return 'cartoons';
  }

  // Стартовые каналы добавляются один раз; новые из обновления приложения — тоже.
  void _addSeeds() {
    if (seedsSeen.isEmpty) {
      seedsSeen = channels.map((c) => c.handle.toLowerCase()).toSet();
    }
    for (final s in kSeeds) {
      final k = s.handle.toLowerCase();
      if (seedsSeen.contains(k)) continue;
      seedsSeen.add(k);
      channels.add(Channel(
          id: '', title: s.name, handle: s.handle, lang: s.lang, cat: s.cat));
    }
    for (final c in channels) {
      if (c.cat.isEmpty) c.cat = _catOfSeed(c.handle);
    }
  }

  // Каталог от Telegram-бота: одобренные каналы добавляются, заблокированные убираются.
  Future<bool> syncCatalog() async {
    if (kCatalogUrl.isEmpty) return false;
    try {
      final stamp = DateTime.now().millisecondsSinceEpoch ~/ 300000;
      final r = await http
          .get(Uri.parse('$kCatalogUrl?t=$stamp'))
          .timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) return false;
      final list = (jsonDecode(utf8.decode(r.bodyBytes))['channels'] as List?) ?? [];
      var changed = false;
      for (final raw in list) {
        final e = raw as Map<String, dynamic>;
        final id = (e['id'] as String?) ?? '';
        if (id.isEmpty) continue;
        final handle = ((e['handle'] as String?) ?? '').toLowerCase();
        Channel? ex;
        for (final c in channels) {
          if (c.id == id || (!c.resolved && handle.isNotEmpty && c.handle.toLowerCase() == handle)) {
            ex = c;
          }
        }
        final status = e['status'];
        if (status == 'blocked') {
          if (ex != null) {
            channels.remove(ex);
            videos.removeWhere((v) => v.channelId == id);
            changed = true;
          }
          continue;
        }
        if (status != 'approved') continue;
        final cat = (e['cat'] as String?) ?? 'cartoons';
        if (ex != null) {
          if (!ex.resolved) {
            ex.id = id;
            ex.uploads = 'UU${id.substring(2)}';
            changed = true;
          }
          if (ex.cat != cat) {
            ex.cat = cat;
            changed = true;
          }
          continue;
        }
        channels.add(Channel(
          id: id,
          title: (e['title'] as String?) ?? id,
          handle: (e['handle'] as String?) ?? '',
          lang: (e['lang'] as String?) ?? 'ru',
          cat: cat,
          uploads: 'UU${id.substring(2)}',
          thumb: (e['thumb'] as String?) ?? '',
        ));
        changed = true;
      }
      if (changed) {
        await _save();
        notifyListeners();
      }
      return changed;
    } catch (_) {
      return false;
    }
  }

  Future<void> _save() async {
    await _p.setString(
        'channels', jsonEncode(channels.map((c) => c.toJson()).toList()));
    await _p.setString(
        'videos', jsonEncode(videos.map((v) => v.toJson()).toList()));
    await _p.setStringList('blockedVideos', blockedVideos.toList());
    await _p.setStringList('extraWords', extraWords);
    await _p.setStringList('seedsSeen', seedsSeen.toList());
    await _p.setBool('autoNext', autoNext);
    if (lastRefresh != null) {
      await _p.setInt('lastRefresh', lastRefresh!.millisecondsSinceEpoch);
    }
  }

  Future<void> refresh() async {
    if (loading) return;
    if (kApiKey.isEmpty) {
      error = 'В приложение не вшит ключ YouTube API (YT_API_KEY).';
      notifyListeners();
      return;
    }
    loading = true;
    error = null;
    notifyListeners();
    String? firstErr;
    try {
      _addSeeds();
      await syncCatalog();
      await Future.wait(channels.where((c) => !c.resolved).map((c) async {
        try {
          final r = await Yt.resolveHandle(c.handle, lang: c.lang);
          if (r != null) {
            c.id = r.id;
            c.title = r.title;
            c.uploads = r.uploads;
            c.thumb = r.thumb;
          }
        } catch (e) {
          firstErr ??= e.toString();
        }
      }));
      final noThumb =
          channels.where((c) => c.resolved && c.thumb.isEmpty).toList();
      if (noThumb.isNotEmpty) {
        try {
          final m = await Yt.channelThumbs(noThumb.map((c) => c.id).toList());
          for (final c in noThumb) {
            c.thumb = m[c.id] ?? '';
          }
        } catch (_) {}
      }
      final w = words;
      final results = await Future.wait(
          channels.where((c) => c.resolved && c.enabled).map((c) async {
        try {
          return await Yt.fetchVideos(c, w);
        } catch (e) {
          firstErr ??= e.toString();
          return <Video>[];
        }
      }));
      final lists = results.map((l) {
        l.sort((a, b) => b.published.compareTo(a.published));
        return l;
      }).toList();
      // Перемешиваем каналы по кругу, чтобы лента была разнообразной.
      final merged = <Video>[];
      var i = 0;
      var added = true;
      while (added) {
        added = false;
        for (final l in lists) {
          if (i < l.length) {
            merged.add(l[i]);
            added = true;
          }
        }
        i++;
      }
      if (merged.isNotEmpty) {
        videos = merged;
        lastRefresh = DateTime.now();
      } else if (firstErr != null) {
        error = 'Не удалось загрузить: $firstErr';
      }
      await _save();
    } catch (e) {
      error = 'Ошибка: $e';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> blockVideo(String id) async {
    blockedVideos.add(id);
    await _save();
    notifyListeners();
  }

  Future<void> clearBlocked() async {
    blockedVideos.clear();
    await _save();
    notifyListeners();
  }

  Future<void> setChannelEnabled(Channel c, bool on) async {
    c.enabled = on;
    await _save();
    notifyListeners();
  }

  Future<void> removeChannel(Channel c) async {
    channels.remove(c);
    videos.removeWhere((v) => v.channelId == c.id);
    await _save();
    notifyListeners();
  }

  Future<void> addChannel(Channel c) async {
    if (channels.any((x) => x.resolved && x.id == c.id)) return;
    channels.add(c);
    await _save();
    notifyListeners();
  }

  Future<void> setExtraWords(List<String> w) async {
    extraWords = w;
    await _save();
    notifyListeners();
  }

  Future<void> setPin(String v) async {
    pin = v;
    await _p.setString('pin', v);
    notifyListeners();
  }

  Future<void> setAutoNext(bool v) async {
    autoNext = v;
    await _save();
    notifyListeners();
  }
}

final AppState app = AppState();
