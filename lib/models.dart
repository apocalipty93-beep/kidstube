class Channel {
  String id;
  String title;
  String handle;
  String lang;
  String cat;
  String uploads;
  String thumb;
  bool enabled;
  bool custom;
  bool fromCat;

  Channel({
    required this.id,
    required this.title,
    required this.handle,
    required this.lang,
    this.cat = 'cartoons',
    this.uploads = '',
    this.thumb = '',
    this.enabled = true,
    this.custom = false,
    this.fromCat = false,
  });

  bool get resolved => id.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'handle': handle,
        'lang': lang,
        'cat': cat,
        'uploads': uploads,
        'thumb': thumb,
        'enabled': enabled,
        'custom': custom,
        'fromCat': fromCat,
      };

  factory Channel.fromJson(Map<String, dynamic> j) => Channel(
        id: (j['id'] as String?) ?? '',
        title: (j['title'] as String?) ?? '',
        handle: (j['handle'] as String?) ?? '',
        lang: (j['lang'] as String?) ?? 'ru',
        cat: (j['cat'] as String?) ?? '',
        uploads: (j['uploads'] as String?) ?? '',
        thumb: (j['thumb'] as String?) ?? '',
        enabled: (j['enabled'] as bool?) ?? true,
        custom: (j['custom'] as bool?) ?? false,
        fromCat: (j['fromCat'] as bool?) ?? false,
      );
}

class Video {
  final String id;
  final String title;
  final String channelId;
  final String channelTitle;
  final String lang;
  final int seconds;
  final DateTime published;

  Video({
    required this.id,
    required this.title,
    required this.channelId,
    required this.channelTitle,
    required this.lang,
    required this.seconds,
    required this.published,
  });

  String get thumb => 'https://i.ytimg.com/vi/$id/mqdefault.jpg';

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'channelId': channelId,
        'channelTitle': channelTitle,
        'lang': lang,
        'seconds': seconds,
        'published': published.millisecondsSinceEpoch,
      };

  factory Video.fromJson(Map<String, dynamic> j) => Video(
        id: j['id'] as String,
        title: (j['title'] as String?) ?? '',
        channelId: (j['channelId'] as String?) ?? '',
        channelTitle: (j['channelTitle'] as String?) ?? '',
        lang: (j['lang'] as String?) ?? 'ru',
        seconds: (j['seconds'] as int?) ?? 0,
        published: DateTime.fromMillisecondsSinceEpoch(
            (j['published'] as int?) ?? 0),
      );
}

String fmtDur(int s) {
  String two(int n) => n.toString().padLeft(2, '0');
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final sec = s % 60;
  return h > 0 ? '$h:${two(m)}:${two(sec)}' : '$m:${two(sec)}';
}

bool isBlockedText(String text, List<String> words) {
  final t = text.toLowerCase();
  for (final w in words) {
    final x = w.trim().toLowerCase();
    if (x.isNotEmpty && t.contains(x)) return true;
  }
  return false;
}
