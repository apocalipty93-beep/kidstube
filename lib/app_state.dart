import 'dart:convert';
import 'dart:math' as math;
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
  String family = ''; // код семьи из Telegram-бота ('' = общий каталог)
  List<String> catStop = []; // стоп-слова из Telegram-бота
  Set<String> catBlocked = {}; // видео, заблокированные через бота
  List<String> watched = []; // недавно просмотренные (уходят в конец ленты)
  final String _seed = DateTime.now().microsecondsSinceEpoch.toString();
  List<String> extraWords = [];
  // Время просмотра, сон, любимое
  int limit = 0; // минут в день, 0 = без лимита
  String bed = ''; // 'HH:MM' — с этого времени до 07:00 приложение закрыто
  String childName = '';
  Set<String> favs = {};
  int extraUntil = 0; // миллисекунды: родитель продлил просмотр до этого момента
  int? catLimit; // значения из Telegram-бота главнее локальных
  String catBed = '';
  String catName = '';
  String usageDay = '';
  int usageSec = 0;
  Map<String, int> usageBy = {};
  String pin = '';
  bool autoNext = true;
  bool loading = false;
  String? error;
  DateTime? lastRefresh;

  List<String> get words => [...kStopWords, ...extraWords, ...catStop];

  int _hash(String s) {
    var h = 2166136261;
    for (final u in s.codeUnits) {
      h ^= u;
      h = (h * 16777619) & 0xFFFFFFFF;
    }
    return h;
  }

  void markWatched(String id) {
    watched.remove(id);
    watched.add(id);
    if (watched.length > 600) watched.removeRange(0, watched.length - 600);
    _p.setStringList('watched', watched);
  }

  // Порядок ленты новый при каждом запуске; непросмотренное раньше просмотренного; каналы чередуются.
  List<Video> _mix(List<Video> list) {
    final seen = watched.toSet();
    final by = <String, List<Video>>{};
    for (final v in list) {
      by.putIfAbsent(v.channelId, () => []).add(v);
    }
    final order = by.keys.toList()
      ..sort((a, b) => _hash(a + _seed).compareTo(_hash(b + _seed)));
    for (final l in by.values) {
      l.sort((a, b) {
        final wa = seen.contains(a.id) ? 1 : 0;
        final wb = seen.contains(b.id) ? 1 : 0;
        if (wa != wb) return wa - wb;
        return _hash(a.id + _seed).compareTo(_hash(b.id + _seed));
      });
    }
    final out = <Video>[];
    var i = 0;
    var added = true;
    while (added) {
      added = false;
      for (final k in order) {
        final l = by[k]!;
        if (i < l.length) {
          out.add(l[i]);
          added = true;
        }
      }
      i++;
    }
    return out;
  }

  List<Video> get visible {
    final on = channels.where((c) => c.enabled).map((c) => c.id).toSet();
    final w = words;
    final mixed = _mix(videos
        .where((v) =>
            on.contains(v.channelId) &&
            !blockedVideos.contains(v.id) &&
            !catBlocked.contains(v.id) &&
            !isBlockedText(v.title, w))
        .toList());
    if (favs.isEmpty) return mixed;
    return [
      ...mixed.where((v) => favs.contains(v.id)),
      ...mixed.where((v) => !favs.contains(v.id)),
    ];
  }

  // ---------- время просмотра, сон, любимое ----------
  String _dayKey([DateTime? d]) {
    final t = d ?? DateTime.now();
    return '${t.year}-${t.month}-${t.day}';
  }

  void _rollUsage() {
    if (usageDay != _dayKey()) {
      usageDay = _dayKey();
      usageSec = 0;
      usageBy = {};
    }
  }

  int get usedSeconds {
    _rollUsage();
    return usageSec;
  }

  int _tickN = 0;
  void addWatch(int sec, String chId) {
    _rollUsage();
    usageSec += sec;
    if (chId.isNotEmpty) usageBy[chId] = (usageBy[chId] ?? 0) + sec;
    _tickN++;
    if (_tickN % 10 == 0) _saveTime();
  }

  int get effLimit => catLimit ?? limit;
  String get effBed => catBed.isNotEmpty ? catBed : bed;
  String get effName => catName.isNotEmpty ? catName : childName;

  int _parseHm(String s) {
    final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(s);
    if (m == null) return -1;
    return int.parse(m.group(1)!) * 60 + int.parse(m.group(2)!);
  }

  /// null — можно смотреть; 'limit' — лимит на день исчерпан; 'bed' — время сна.
  String? lockReason([DateTime? now]) {
    final d = now ?? DateTime.now();
    if (extraUntil > d.millisecondsSinceEpoch) return null;
    final lim = effLimit;
    if (lim > 0 && usedSeconds >= lim * 60) return 'limit';
    final b = _parseHm(effBed);
    if (b > 7 * 60) {
      final m = d.hour * 60 + d.minute;
      if (m >= b || m < 7 * 60) return 'bed';
    }
    return null;
  }

  Future<void> extend(int minutes) async {
    extraUntil = DateTime.now().millisecondsSinceEpoch + minutes * 60000;
    await _saveTime();
    notifyListeners();
  }

  Future<void> setLimit(int n) async {
    limit = n;
    extraUntil = 0;
    await _saveTime();
    notifyListeners();
  }

  Future<void> setBed(String s) async {
    bed = s;
    extraUntil = 0;
    await _saveTime();
    notifyListeners();
  }

  Future<void> setChildName(String s) async {
    childName = s;
    await _saveTime();
    notifyListeners();
  }

  bool isFav(String id) => favs.contains(id);

  Future<bool> toggleFav(String id) async {
    final on = !favs.contains(id);
    if (on) {
      favs.add(id);
    } else {
      favs.remove(id);
    }
    await _saveTime();
    notifyListeners();
    return on;
  }

  Future<void> _saveTime() async {
    await _p.setInt('limit', limit);
    await _p.setString('bed', bed);
    await _p.setString('childName', childName);
    await _p.setStringList('favs', favs.toList());
    await _p.setInt('extraUntil', extraUntil);
    await _p.setString('usageDay', usageDay);
    await _p.setInt('usageSec', usageSec);
    await _p.setString('usageBy', jsonEncode(usageBy));
    if (catLimit == null) {
      await _p.remove('catLimit');
    } else {
      await _p.setInt('catLimit', catLimit!);
    }
    await _p.setString('catBed', catBed);
    await _p.setString('catName', catName);
  }

  /// Топ каналов по времени за сегодня: «Название 12 мин».
  List<String> topToday() {
    _rollUsage();
    final e = usageBy.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final out = <String>[];
    for (final x in e.take(3)) {
      final ch = channels.where((c) => c.id == x.key);
      out.add('${ch.isEmpty ? '?' : ch.first.title} ${math.max(1, (x.value / 60).round())} мин');
    }
    return out;
  }

  Future<void> init() async {
    _p = await SharedPreferences.getInstance();
    pin = _p.getString('pin') ?? '';
    autoNext = _p.getBool('autoNext') ?? true;
    blockedVideos = (_p.getStringList('blockedVideos') ?? []).toSet();
    extraWords = _p.getStringList('extraWords') ?? [];
    seedsSeen = (_p.getStringList('seedsSeen') ?? []).toSet();
    catStop = _p.getStringList('catStop') ?? [];
    catBlocked = (_p.getStringList('catBlocked') ?? []).toSet();
    watched = _p.getStringList('watched') ?? [];
    family = _p.getString('family') ?? '';
    limit = _p.getInt('limit') ?? 0;
    bed = _p.getString('bed') ?? '';
    childName = _p.getString('childName') ?? '';
    favs = (_p.getStringList('favs') ?? []).toSet();
    extraUntil = _p.getInt('extraUntil') ?? 0;
    usageDay = _p.getString('usageDay') ?? '';
    usageSec = _p.getInt('usageSec') ?? 0;
    try {
      final ub = _p.getString('usageBy');
      if (ub != null) {
        usageBy = (jsonDecode(ub) as Map<String, dynamic>).map((k, v) => MapEntry(k, (v as num).toInt()));
      }
    } catch (_) {
      usageBy = {};
    }
    catLimit = _p.getInt('catLimit');
    catBed = _p.getString('catBed') ?? '';
    catName = _p.getString('catName') ?? '';
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
  String catalogUrlFor(String code) {
    if (kCatalogUrl.isEmpty) return '';
    if (code.isEmpty || code == 'main') return kCatalogUrl;
    return kCatalogUrl.replaceFirst(RegExp(r'data/catalog\.json$'), 'data/families/$code/catalog.json');
  }

  /// Проверяет, что семья с таким кодом существует. Возвращает текст ошибки или null.
  Future<String?> checkFamily(String raw) async {
    final code = raw.trim().toLowerCase();
    if (code != 'main' && !RegExp(r'^[a-z0-9]{4,12}$').hasMatch(code)) {
      return 'Код — это 6 букв и цифр из Telegram';
    }
    final u = catalogUrlFor(code);
    if (u.isEmpty) return 'Каталог не настроен';
    try {
      final r = await http
          .get(Uri.parse('$u?t=${DateTime.now().millisecondsSinceEpoch}'))
          .timeout(const Duration(seconds: 20));
      if (r.statusCode == 200) return null;
    } catch (_) {}
    return 'Такого кода нет. Напишите боту /start и возьмите код из ответа';
  }

  /// Переключает на каталог другой семьи: прежние каналы из каталога убираем, стартовые остаются.
  Future<void> setFamily(String raw) async {
    final code = raw.trim().toLowerCase();
    family = code == 'main' ? '' : code;
    final seedHandles = kSeeds.map((s) => s.handle.toLowerCase()).toSet();
    channels.removeWhere((c) => !(c.custom || (!c.fromCat && seedHandles.contains(c.handle.toLowerCase()))));
    for (final c in channels) {
      if (!c.custom) c.enabled = true;
    }
    catStop = [];
    catBlocked = {};
    videos = [];
    lastRefresh = null;
    await _p.setString('family', family);
    await _save();
    notifyListeners();
    await syncCatalog();
    await refresh();
  }

  Future<bool> syncCatalog() async {
    final catUrl = catalogUrlFor(family);
    if (catUrl.isEmpty) return false;
    try {
      final stamp = DateTime.now().millisecondsSinceEpoch ~/ 300000;
      final r = await http
          .get(Uri.parse('$catUrl?t=$stamp'))
          .timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) return false;
      final body = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      final list = (body['channels'] as List?) ?? [];
      var changed = false;
      final sw = ((body['stopWords'] as List?) ?? []).map((x) => x.toString().toLowerCase()).toList();
      final bv = ((body['blockedVideos'] as List?) ?? []).map((x) => x.toString()).toSet();
      if (sw.join('|') != catStop.join('|')) {
        catStop = sw;
        changed = true;
      }
      if (bv.length != catBlocked.length || !bv.containsAll(catBlocked)) {
        catBlocked = bv;
        changed = true;
      }
      final limRaw = body['limitMinutes'];
      final lim = limRaw is num ? limRaw.toInt() : null;
      final bedRaw = body['bedtime'];
      final bedV = bedRaw is String ? bedRaw : '';
      final nmRaw = body['childName'];
      final nmV = nmRaw is String ? nmRaw : '';
      if (lim != catLimit) {
        catLimit = lim;
        changed = true;
      }
      if (bedV != catBed) {
        catBed = bedV;
        changed = true;
      }
      if (nmV != catName) {
        catName = nmV;
        changed = true;
      }
      if (changed) await _saveTime();
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
          final en = e['enabled'];
          if (en is bool && ex.enabled != en) {
            ex.enabled = en;
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
          enabled: e['enabled'] != false,
          fromCat: true,
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
    await _p.setStringList('catStop', catStop);
    await _p.setStringList('catBlocked', catBlocked.toList());
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
          return await Yt.fetchChannel(c, w);
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
