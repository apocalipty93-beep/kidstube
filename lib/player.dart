import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';
import 'app_state.dart';
import 'models.dart';
import 'pin.dart';
import 'widgets.dart';

class PlayerScreen extends StatefulWidget {
  final Video video;
  final List<Video> all;
  const PlayerScreen({super.key, required this.video, required this.all});
  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final YoutubePlayerController _c;
  StreamSubscription<YoutubePlayerValue>? _sub;
  late Video _cur;
  PlayerState _last = PlayerState.unknown;
  bool _fs = false;
  final GlobalKey _playerKey = GlobalKey();
  Timer? _watchTimer;

  @override
  void initState() {
    super.initState();
    _cur = widget.video;
    app.markWatched(_cur.id);
    _c = YoutubePlayerController.fromVideoId(
      videoId: _cur.id,
      autoPlay: true,
      params: YoutubePlayerParams(
        showControls: true,
        showFullscreenButton: false, // свой полноэкранный режим (кнопка под видео)
        strictRelatedVideos: true, // после ролика — только видео этого же канала
        enableCaption: false,
        playsInline: true,
        origin: 'https://www.youtube-nocookie.com', // фикс ошибки 152
      ),
    );
    // Считаем время просмотра; когда лимит вышел — ставим на паузу (поверх откроется экран отдыха).
    _watchTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (app.lockReason() != null) {
        _c.pauseVideo();
        return;
      }
      if (_c.value.playerState == PlayerState.playing) {
        app.addWatch(1, _cur.channelId);
      }
    });
    _sub = _c.listen((v) {
      if (v.playerState == PlayerState.ended && _last != PlayerState.ended) {
        _playNext();
      }
      _last = v.playerState;
    });
  }

  List<Video> get _queue {
    final same =
        widget.all.where((v) => v.channelId == _cur.channelId).toList();
    return same.isEmpty ? widget.all : same;
  }

  void _play(Video v) {
    app.markWatched(v.id);
    setState(() => _cur = v);
    _c.loadVideoById(videoId: v.id);
  }

  void _playNext() {
    if (!app.autoNext) return;
    final q = _queue;
    if (q.isEmpty) return;
    final i = q.indexWhere((v) => v.id == _cur.id);
    final next = q[(i + 1) % q.length];
    if (next.id != _cur.id) _play(next);
  }

  void _setFs(bool on) {
    setState(() => _fs = on);
    SystemChrome.setPreferredOrientations(on
        ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
        : DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(
        on ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
  }

  Widget _roundBtn(IconData icon, String tip, VoidCallback onTap) => Material(
        color: Colors.black54,
        shape: const CircleBorder(),
        child: IconButton(
          icon: Icon(icon, color: Colors.white, size: 30),
          tooltip: tip,
          onPressed: onTap,
        ),
      );

  Future<void> _parentMenu() async {
    final ok = await askPin(context);
    if (!ok || !mounted) return;
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.block),
              title: const Text('Заблокировать это видео'),
              onTap: () => Navigator.pop(ctx, 'video'),
            ),
            ListTile(
              leading: const Icon(Icons.tv_off),
              title: Text('Отключить канал «${_cur.channelTitle}»'),
              onTap: () => Navigator.pop(ctx, 'channel'),
            ),
          ],
        ),
      ),
    );
    if (choice == 'video') {
      await app.blockVideo(_cur.id);
      if (mounted) Navigator.pop(context);
    } else if (choice == 'channel') {
      final ch = app.channels.where((c) => c.id == _cur.channelId);
      if (ch.isNotEmpty) await app.setChannelEnabled(ch.first, false);
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    _watchTimer?.cancel();
    _sub?.cancel();
    _c.close();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sameCh = _queue.where((v) => v.id != _cur.id).toList();
    final others =
        widget.all.where((v) => v.channelId != _cur.channelId).toList();
    final related = <Video>[];
    for (var i = 0; i < sameCh.length || i < others.length; i++) {
      if (i < sameCh.length) related.add(sameCh[i]);
      if (i < others.length) related.add(others[i]);
    }
    final player = KeyedSubtree(
      key: _playerKey,
      child: YoutubePlayer(controller: _c, aspectRatio: 16 / 9),
    );

    // Полный экран: чёрный фон, крестик слева сверху, системная «назад» тоже выходит.
    if (_fs) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) => _setFs(false),
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              Center(child: player),
              Positioned(
                top: 12,
                left: 12,
                child: SafeArea(
                  child: _roundBtn(
                      Icons.fullscreen_exit, 'Выйти', () => _setFs(false)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final t = Theme.of(context).textTheme;
    final info = Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_cur.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                Text(_cur.channelTitle, style: t.bodySmall),
              ],
            ),
          ),
          IconButton.filledTonal(
            icon: Icon(app.isFav(_cur.id) ? Icons.favorite : Icons.favorite_border,
                color: Colors.redAccent),
            iconSize: 32,
            tooltip: 'Любимое',
            onPressed: () async {
              await app.toggleFav(_cur.id);
              if (mounted) setState(() {});
            },
          ),
          IconButton.filledTonal(
            icon: const Icon(Icons.fullscreen),
            iconSize: 32,
            tooltip: 'На весь экран',
            onPressed: () => _setFs(true),
          ),
        ],
      ),
    );
    final list = ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: related.length,
      separatorBuilder: (_, __) => const SizedBox(height: 14),
      itemBuilder: (context, i) =>
          VideoCard(video: related[i], onTap: () => _play(related[i])),
    );

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFF8F0),
        title: Text(_cur.channelTitle,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.lock_outline),
            tooltip: 'Для родителей',
            onPressed: _parentMenu,
          ),
        ],
      ),
      body: LayoutBuilder(builder: (context, box) {
        final wide = box.maxWidth > 700 && box.maxWidth > box.maxHeight;
        if (wide) {
          return Row(
            children: [
              Expanded(
                flex: 3,
                child: SingleChildScrollView(
                  child: Column(children: [player, info]),
                ),
              ),
              Expanded(flex: 2, child: list),
            ],
          );
        }
        return Column(
          children: [player, info, Expanded(child: list)],
        );
      }),
    );
  }
}
