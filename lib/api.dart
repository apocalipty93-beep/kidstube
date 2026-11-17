import 'dart:convert';
import 'package:http/http.dart' as http;
import 'config.dart';
import 'models.dart';

class Yt {
  static const _base = 'https://www.googleapis.com/youtube/v3';

  static Future<Map<String, dynamic>> _get(
      String path, Map<String, String> q) async {
    final uri = Uri.parse('$_base/$path')
        .replace(queryParameters: {...q, 'key': kApiKey});
    final r = await http.get(uri).timeout(const Duration(seconds: 25));
    if (r.statusCode != 200) {
      String msg = 'HTTP ${r.statusCode}';
      try {
        final e = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
        final m = (e['error'] as Map<String, dynamic>?)?['message'];
        if (m is String) msg = '$msg: $m';
      } catch (_) {}
      throw Exception(msg);
    }
    return jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  }

  /// Ищет канал по @handle (1 единица квоты).
  static Future<Channel?> resolveHandle(String handle,
      {String lang = 'ru', bool custom = false}) async {
    final h = handle.startsWith('@') ? handle : '@$handle';
    final j = await _get(
        'channels', {'part': 'snippet,contentDetails', 'forHandle': h});
    final items = (j['items'] as List?) ?? [];
    if (items.isEmpty) return null;
    final it = items.first as Map<String, dynamic>;
    final id = it['id'] as String;
    final sn = (it['snippet'] as Map<String, dynamic>?) ?? {};
    final cd = (it['contentDetails'] as Map<String, dynamic>?) ?? {};
    final rp = (cd['relatedPlaylists'] as Map<String, dynamic>?) ?? {};
    final uploads = (rp['uploads'] as String?) ?? 'UU${id.substring(2)}';
    final ths = (sn['thumbnails'] as Map<String, dynamic>?) ?? {};
    final th = (ths['medium'] ?? ths['default']) as Map<String, dynamic>?;
    return Channel(
      id: id,
      title: (sn['title'] as String?) ?? handle,
      handle: handle.replaceFirst('@', ''),
      lang: lang,
      uploads: uploads,
      thumb: (th?['url'] as String?) ?? '',
      custom: custom,
    );
  }

  /// Аватарки каналов одним запросом (1 единица квоты).
  static Future<Map<String, String>> channelThumbs(List<String> ids) async {
    final out = <String, String>{};
    if (ids.isEmpty) return out;
    final j = await _get('channels', {'part': 'snippet', 'id': ids.join(','), 'maxResults': '50'});
    for (final raw in (j['items'] as List?) ?? []) {
      final it = raw as Map<String, dynamic>;
      final sn = (it['snippet'] as Map<String, dynamic>?) ?? {};
      final ths = (sn['thumbnails'] as Map<String, dynamic>?) ?? {};
      final th = (ths['medium'] ?? ths['default']) as Map<String, dynamic>?;
      final url = th?['url'] as String?;
      if (url != null) out[it['id'] as String] = url;
    }
    return out;
  }

  static int _parseDuration(String iso) {
    final m = RegExp(r'^PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?$').firstMatch(iso);
    if (m == null) return 0;
    final h = int.tryParse(m.group(1) ?? '') ?? 0;
    final mi = int.tryParse(m.group(2) ?? '') ?? 0;
    final s = int.tryParse(m.group(3) ?? '') ?? 0;
    return h * 3600 + mi * 60 + s;
  }

  /// Видео, которые владелец разрешил встраивать, через поиск по каналу (100 ед. квоты).
  static Future<List<Video>> fetchEmbeddable(Channel c, List<String> words) async {
    final sj = await _get('search', {
      'part': 'snippet',
      'channelId': c.id,
      'type': 'video',
      'videoEmbeddable': 'true',
      'safeSearch': 'strict',
      'maxResults': '50',
      'order': 'viewCount',
    });
    final ids = <String>[];
    final titles = <String, String>{};
    final dates = <String, DateTime>{};
    for (final raw in (sj['items'] as List?) ?? []) {
      final it = raw as Map<String, dynamic>;
      final id = (it['id'] as Map<String, dynamic>?)?['videoId'] as String?;
      final sn = (it['snippet'] as Map<String, dynamic>?) ?? {};
      final title = (sn['title'] as String?) ?? '';
      if (id == null || isBlockedText(title, words)) continue;
      ids.add(id);
      titles[id] = title;
      dates[id] = DateTime.tryParse((sn['publishedAt'] as String?) ?? '') ??
          DateTime(2000);
    }
    if (ids.isEmpty) return [];
    final vj = await _get('videos', {
      'part': 'contentDetails,status',
      'id': ids.join(','),
      'maxResults': '50',
    });
    final out = <Video>[];
    for (final raw in (vj['items'] as List?) ?? []) {
      final it = raw as Map<String, dynamic>;
      final id = it['id'] as String;
      final st = (it['status'] as Map<String, dynamic>?) ?? {};
      final cd = (it['contentDetails'] as Map<String, dynamic>?) ?? {};
      if (st['embeddable'] != true || st['privacyStatus'] != 'public') continue;
      final secs = _parseDuration((cd['duration'] as String?) ?? '');
      if (secs < 30) continue;
      out.add(Video(
        id: id,
        title: titles[id] ?? '',
        channelId: c.id,
        channelTitle: c.title,
        lang: c.lang,
        seconds: secs,
        published: dates[id] ?? DateTime(2000),
      ));
    }
    return out;
  }

  /// Загрузки канала; если проигрываемых мало — добавляем разрешённые через поиск.
  static Future<List<Video>> fetchChannel(Channel c, List<String> words) async {
    final list = await fetchVideos(c, words);
    if (list.length >= 10) return list;
    try {
      final extra = await fetchEmbeddable(c, words);
      final have = list.map((v) => v.id).toSet();
      return [...list, ...extra.where((v) => !have.contains(v.id))];
    } catch (_) {
      return list;
    }
  }

  /// Последние видео канала: 1 + 1 единица квоты.
  static Future<List<Video>> fetchVideos(Channel c, List<String> words,
      {int max = 30}) async {
    // До 3 страниц загрузок канала (до 150 видео), чтобы лента была разнообразной.
    final upItems = <dynamic>[];
    String? token;
    for (var page = 0; page < 3; page++) {
      final r = await _get('playlistItems', {
        'part': 'snippet,contentDetails',
        'playlistId': c.uploads.isEmpty ? 'UU${c.id.substring(2)}' : c.uploads,
        'maxResults': '50',
        if (token != null) 'pageToken': token,
      });
      upItems.addAll((r['items'] as List?) ?? []);
      token = r['nextPageToken'] as String?;
      if (token == null) break;
    }
    final pl = <String, dynamic>{'items': upItems};
    final ids = <String>[];
    final titles = <String, String>{};
    final dates = <String, DateTime>{};
    for (final raw in (pl['items'] as List?) ?? []) {
      final it = raw as Map<String, dynamic>;
      final sn = (it['snippet'] as Map<String, dynamic>?) ?? {};
      final cd = (it['contentDetails'] as Map<String, dynamic>?) ?? {};
      final id = cd['videoId'] as String?;
      if (id == null) continue;
      final title = (sn['title'] as String?) ?? '';
      if (title == 'Private video' || title == 'Deleted video') continue;
      if (isBlockedText(title, words)) continue;
      ids.add(id);
      titles[id] = title;
      final d = (cd['videoPublishedAt'] as String?) ??
          (sn['publishedAt'] as String?);
      dates[id] = DateTime.tryParse(d ?? '') ?? DateTime(2000);
    }
    if (ids.isEmpty) return [];

    final vItems = <dynamic>[];
    for (var i = 0; i < ids.length; i += 50) {
      final end = i + 50 > ids.length ? ids.length : i + 50;
      final vj = await _get('videos', {
        'part': 'contentDetails,status',
        'id': ids.sublist(i, end).join(','),
        'maxResults': '50',
      });
      vItems.addAll((vj['items'] as List?) ?? []);
    }
    final out = <Video>[];
    for (final raw in vItems) {
      final it = raw as Map<String, dynamic>;
      final id = it['id'] as String;
      final st = (it['status'] as Map<String, dynamic>?) ?? {};
      final cd = (it['contentDetails'] as Map<String, dynamic>?) ?? {};
      if (st['embeddable'] != true) continue;
      if (st['privacyStatus'] != 'public') continue;
      final secs = _parseDuration((cd['duration'] as String?) ?? '');
      if (secs < 30) continue; // шортсы, трансляции, анонсы
      out.add(Video(
        id: id,
        title: titles[id] ?? '',
        channelId: c.id,
        channelTitle: c.title,
        lang: c.lang,
        seconds: secs,
        published: dates[id] ?? DateTime(2000),
      ));
    }
    return out;
  }
}
