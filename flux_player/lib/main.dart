import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

const navy = Color(0xFF0B1026);
const cardColor = Color(0xFF19223D);
const accent = Color(0xFFFF636B);
const bridge = MethodChannel('flux/native');
const events = EventChannel('flux/events');

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Flux Download & Play',
    theme: ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: navy,
      colorScheme: ColorScheme.fromSeed(seedColor: accent, brightness: Brightness.dark),
      cardTheme: const CardThemeData(color: cardColor),
      useMaterial3: true,
    ),
    home: const DownloadsPage(),
  ));
}

String humanSize(int b) {
  if (b <= 0) return '0 B';
  final i = (math.log(b) / math.log(1024)).floor().clamp(0, 4);
  return '${(b / math.pow(1024, i)).toStringAsFixed(i == 0 ? 0 : 1)} ${['B','KB','MB','GB','TB'][i]}';
}

String timecode(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

class DownloadItem {
  DownloadItem(Map raw)
      : id = '${raw['id'] ?? ''}',
        name = '${raw['name'] ?? ''}',
        url = '${raw['url'] ?? ''}',
        status = '${raw['status'] ?? 'queued'}',
        path = '${raw['path'] ?? ''}',
        error = '${raw['error'] ?? ''}',
        received = (raw['downloaded'] as num?)?.toInt() ?? 0,
        total = (raw['total'] as num?)?.toInt() ?? 0,
        parts = (raw['parts'] as num?)?.toInt() ?? 1;
  final String id, name, url, status, path, error;
  final int received, total, parts;
  bool get done => status == 'completed';
  bool get active => status == 'running' || status == 'queued';
  double get fraction => total == 0 ? 0 : (received / total).clamp(0.0, 1.0);
}

class DownloadsPage extends StatefulWidget {
  const DownloadsPage({super.key});
  @override
  State<DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends State<DownloadsPage> {
  List<DownloadItem> items = [];
  StreamSubscription<dynamic>? subscription;
  String filter = 'All';
  String? problem;

  @override
  void initState() {
    super.initState();
    reload();
    subscription = events.receiveBroadcastStream().listen(
      (_) => reload(),
      onError: (Object e) { if (mounted) setState(() => problem = '$e'); },
    );
  }

  Future<void> reload() async {
    try {
      final data = await bridge.invokeMethod<List<dynamic>>('list') ?? [];
      if (mounted) setState(() {
        items = data.map((d) => DownloadItem(d as Map)).toList().reversed.toList();
      });
    } catch (e) {
      if (mounted) setState(() => problem = '$e');
    }
  }

  Future<void> action(String name, String id) async {
    try { await bridge.invokeMethod<void>(name, {'id': id}); await reload(); }
    catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  void play(String source, String name) => Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => CinemaPage(source: source, title: name)),
  );

  Future<void> addDownload() async {
    final url = TextEditingController();
    final name = TextEditingController();
    var connections = 8;
    await showModalBottomSheet<void>(
      context: context, isScrollControlled: true, backgroundColor: cardColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) => Padding(
        padding: EdgeInsets.fromLTRB(20, 22, 20, MediaQuery.viewInsetsOf(ctx).bottom + 24),
        child: SingleChildScrollView(child: Column(
          mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('New direct download', style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(controller: url, autofocus: true, keyboardType: TextInputType.url,
              decoration: const InputDecoration(labelText: 'HTTP / HTTPS link', prefixIcon: Icon(Icons.link), border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: name, decoration: const InputDecoration(labelText: 'File name (optional)', border: OutlineInputBorder())),
            const SizedBox(height: 16),
            Text('Connections: $connections'),
            Slider(min: 1, max: 16, divisions: 15, value: connections.toDouble(),
              activeColor: accent, label: '$connections',
              onChanged: (v) => setLocal(() => connections = v.toInt())),
            const Text('Multiple parts are used only when the server supports HTTP Range.',
              style: TextStyle(color: Colors.white60, fontSize: 12)),
            const SizedBox(height: 14),
            SizedBox(width: double.infinity, child: FilledButton.icon(
              icon: const Icon(Icons.file_download), label: const Text('Download'),
              onPressed: () async {
                final u = Uri.tryParse(url.text.trim());
                if (u == null || !(u.isScheme('http') || u.isScheme('https')) || u.host.isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Enter a valid direct link')));
                  return;
                }
                try {
                  await bridge.invokeMethod<void>('enqueue', {
                    'url': u.toString(), 'name': name.text.trim(), 'parts': connections,
                  });
                  if (ctx.mounted) Navigator.pop(ctx);
                  await reload();
                } catch (e) {
                  if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('$e')));
                }
              },
            )),
          ],
        )),
      )),
    );
    url.dispose(); name.dispose();
  }

  Future<void> networkVideo() async {
    final input = TextEditingController();
    final value = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Stream a video URL'),
      content: TextField(controller: input, keyboardType: TextInputType.url,
        decoration: const InputDecoration(hintText: 'https://example.com/video.mkv')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, input.text.trim()), child: const Text('Play')),
      ],
    ));
    input.dispose();
    if (value != null && value.isNotEmpty && mounted) play(value, 'Network video');
  }

  @override
  void dispose() { subscription?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final filtered = items.where((e) => switch (filter) {
      'Active' => e.active, 'Completed' => e.done,
      'Paused' => e.status == 'paused' || e.status == 'failed',
      _ => true,
    }).toList();
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(onPressed: addDownload,
        backgroundColor: accent, foregroundColor: navy,
        label: const Text('Add link'), icon: const Icon(Icons.add_link)),
      body: SafeArea(child: RefreshIndicator(
        onRefresh: reload,
        child: ListView(padding: const EdgeInsets.fromLTRB(18, 22, 18, 105), children: [
          Row(children: [
            Container(padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: accent.withValues(alpha: .17), borderRadius: BorderRadius.circular(14)),
              child: const Icon(Icons.bolt, color: accent, size: 30)),
            const SizedBox(width: 12),
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('FLUX', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: 3)),
              Text('DOWNLOAD & PLAY', style: TextStyle(fontSize: 10, color: Colors.white54, letterSpacing: 2)),
            ])),
            IconButton(tooltip: 'Stream video', icon: const Icon(Icons.ondemand_video), onPressed: networkVideo),
          ]),
          const SizedBox(height: 28),
          Container(padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: const LinearGradient(colors: [Color(0xFF303965), cardColor]),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Your download hub', style: TextStyle(color: Colors.white70)),
              const SizedBox(height: 8),
              Text('${items.length} files', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800)),
              const SizedBox(height: 16),
              Row(children: [
                const Icon(Icons.downloading, color: accent),
                Text(' ${items.where((e) => e.active).length} active'),
                const Spacer(),
                const Icon(Icons.check_circle_outline, color: Colors.greenAccent),
                Text(' ${items.where((e) => e.done).length} completed'),
              ]),
            ]),
          ),
          if (problem != null) Padding(padding: const EdgeInsets.only(top: 12),
            child: Text(problem!, style: const TextStyle(color: accent))),
          const SizedBox(height: 18),
          SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
            for (final t in ['All','Active','Completed','Paused'])
              Padding(padding: const EdgeInsets.only(right: 7),
                child: ChoiceChip(label: Text(t), selected: filter == t,
                  showCheckmark: false,
                  selectedColor: accent.withValues(alpha: .25),
                  onSelected: (_) => setState(() => filter = t))),
          ])),
          const SizedBox(height: 18),
          if (filtered.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 70),
            child: Column(children: [
              Icon(Icons.download_for_offline_outlined, size: 75, color: Colors.white24),
              SizedBox(height: 12),
              Text('No downloads here', style: TextStyle(color: Colors.white54)),
            ])),
          for (final item in filtered) Card(
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            child: Padding(padding: const EdgeInsets.all(15), child: Column(children: [
              Row(children: [
                Container(padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: accent.withValues(alpha: .13), borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.video_file_outlined, color: accent)),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('${item.status.toUpperCase()} • ${item.parts} connections',
                    style: const TextStyle(fontSize: 11, color: Colors.white60)),
                ])),
                PopupMenuButton<String>(
                  onSelected: (value) => action(value, item.id),
                  itemBuilder: (_) => [
                    if (item.active) const PopupMenuItem(value: 'pause', child: Text('Pause')),
                    if (item.status == 'paused' || item.status == 'failed')
                      const PopupMenuItem(value: 'resume', child: Text('Resume')),
                    const PopupMenuItem(value: 'cancel', child: Text('Delete task')),
                  ],
                ),
              ]),
              const SizedBox(height: 14),
              ClipRRect(borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(value: item.total == 0 ? null : item.fraction,
                  minHeight: 6, color: item.done ? Colors.greenAccent : accent,
                  backgroundColor: Colors.white12)),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: Text('${humanSize(item.received)} / ${item.total == 0 ? 'unknown' : humanSize(item.total)}',
                  style: const TextStyle(fontSize: 12, color: Colors.white70))),
                Text('${(item.fraction * 100).toStringAsFixed(0)}%'),
              ]),
              if (item.error.isNotEmpty) Text(item.error, style: const TextStyle(color: accent, fontSize: 12)),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                if (item.active) TextButton.icon(onPressed: () => action('pause', item.id),
                  icon: const Icon(Icons.pause), label: const Text('Pause')),
                if (item.status == 'paused' || item.status == 'failed')
                  TextButton.icon(onPressed: () => action('resume', item.id),
                    icon: const Icon(Icons.refresh), label: const Text('Resume')),
                TextButton.icon(
                  onPressed: () => play(item.done && item.path.isNotEmpty ? item.path : item.url, item.name),
                  icon: const Icon(Icons.play_arrow),
                  label: Text(item.done ? 'Open' : 'Stream')),
              ]),
            ])),
          ),
        ]),
      )),
    );
  }
}

class CinemaPage extends StatefulWidget {
  const CinemaPage({super.key, required this.source, required this.title});
  final String source, title;
  @override
  State<CinemaPage> createState() => _CinemaPageState();
}

class _CinemaPageState extends State<CinemaPage> {
  late final Player player;
  late final VideoController video;
  final subs = <StreamSubscription<dynamic>>[];
  Duration position = Duration.zero, duration = Duration.zero;
  bool playing = false, buffering = false, controls = true, locked = false, fill = false;
  bool brightnessSide = false;
  double volume = .5, brightness = .5, rate = 1;
  String? error;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    player = Player();
    video = VideoController(player);
    subs.add(player.stream.position.listen((v) { if (mounted) setState(() => position = v); }));
    subs.add(player.stream.duration.listen((v) { if (mounted) setState(() => duration = v); }));
    subs.add(player.stream.playing.listen((v) { if (mounted) setState(() => playing = v); }));
    subs.add(player.stream.buffering.listen((v) { if (mounted) setState(() => buffering = v); }));
    subs.add(player.stream.error.listen((v) { if (mounted) setState(() => error = v); }));
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    bridge.invokeMethod<double>('getVolume').then((v) { if (mounted && v != null) volume = v; });
    player.open(Media(widget.source)).catchError((Object e) {
      if (mounted) setState(() => error = '$e');
    });
    autoHide();
  }

  void autoHide() {
    timer?.cancel();
    if (controls && !locked) {
      timer = Timer(const Duration(seconds: 5), () {
        if (mounted) setState(() => controls = false);
      });
    }
  }

  void toggleControls() {
    setState(() => controls = !controls);
    autoHide();
  }

  Future<void> seekBy(int seconds) async {
    var dest = position + Duration(seconds: seconds);
    if (dest.isNegative) dest = Duration.zero;
    if (duration > Duration.zero && dest > duration) dest = duration;
    await player.seek(dest);
    autoHide();
  }

  void gestureVolumeBrightness(double dy) {
    if (brightnessSide) {
      brightness = (brightness - dy / 280).clamp(.03, 1.0);
      bridge.invokeMethod<void>('brightness', {'value': brightness});
    } else {
      volume = (volume - dy / 280).clamp(0.0, 1.0);
      bridge.invokeMethod<void>('volume', {'value': volume});
    }
  }

  Future<void> externalTrack(bool audio) async {
    final input = TextEditingController();
    final value = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      title: Text(audio ? 'External audio URL' : 'External subtitle URL'),
      content: TextField(controller: input, decoration: const InputDecoration(hintText: 'https://... or file:///...')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, input.text.trim()), child: const Text('Load')),
      ],
    ));
    input.dispose();
    if (value == null || value.isEmpty) return;
    try {
      if (audio) {
        await player.setAudioTrack(AudioTrack.uri(value));
      } else {
        await player.setSubtitleTrack(SubtitleTrack.uri(value));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  void selectTracks(bool audio) {
    final List<dynamic> tracks = audio ? player.state.tracks.audio : player.state.tracks.subtitle;
    showModalBottomSheet<void>(context: context, backgroundColor: cardColor, showDragHandle: true,
      builder: (ctx) => SafeArea(child: ListView(shrinkWrap: true, children: [
        ListTile(title: Text(audio ? 'Choose audio' : 'Choose subtitles')),
        ListTile(title: const Text('Auto'), onTap: () async {
          if (audio) { await player.setAudioTrack(AudioTrack.auto()); }
          else { await player.setSubtitleTrack(SubtitleTrack.auto()); }
          if (ctx.mounted) Navigator.pop(ctx);
        }),
        if (!audio) ListTile(title: const Text('Off'), onTap: () async {
          await player.setSubtitleTrack(SubtitleTrack.no());
          if (ctx.mounted) Navigator.pop(ctx);
        }),
        for (int i = 0; i < tracks.length; i++)
          ListTile(
            title: Text('${tracks[i].title ?? 'Track ${i + 1}'}'),
            subtitle: Text('${tracks[i].language ?? 'Undetermined language'}'),
            onTap: () async {
              if (audio) { await player.setAudioTrack(tracks[i] as AudioTrack); }
              else { await player.setSubtitleTrack(tracks[i] as SubtitleTrack); }
              if (ctx.mounted) Navigator.pop(ctx);
            },
          ),
        ListTile(leading: const Icon(Icons.add_link),
          title: Text(audio ? 'Add external audio' : 'Add external subtitles'),
          onTap: () { Navigator.pop(ctx); externalTrack(audio); }),
      ])));
  }

  void chooseRate() {
    showModalBottomSheet<void>(context: context, backgroundColor: cardColor,
      builder: (ctx) => SafeArea(child: Padding(
        padding: const EdgeInsets.all(24),
        child: Wrap(spacing: 12, runSpacing: 10, children: [
          for (final v in <double>[.5, .75, 1, 1.25, 1.5, 1.75, 2])
            ChoiceChip(label: Text('${v}x'), selected: rate == v, onSelected: (_) {
              player.setRate(v);
              setState(() => rate = v);
              Navigator.pop(ctx);
            }),
        ]),
      )));
  }

  @override
  void dispose() {
    timer?.cancel();
    for (final s in subs) { s.cancel(); }
    player.dispose();
    bridge.invokeMethod<void>('resetBrightness');
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final max = math.max(1, duration.inMilliseconds);
    final pos = position.inMilliseconds.clamp(0, max).toDouble();
    return Scaffold(backgroundColor: Colors.black, body: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: toggleControls,
      onDoubleTapDown: (d) => seekBy(
        d.localPosition.dx < MediaQuery.sizeOf(context).width / 2 ? -10 : 10),
      onVerticalDragStart: (d) => brightnessSide =
        d.localPosition.dx < MediaQuery.sizeOf(context).width / 2,
      onVerticalDragUpdate: (d) { if (!locked) gestureVolumeBrightness(d.delta.dy); },
      child: Stack(children: [
        Center(child: Video(controller: video, controls: NoVideoControls,
          fit: fill ? BoxFit.cover : BoxFit.contain)),
        if (buffering) const Center(child: CircularProgressIndicator(color: accent)),
        if (error != null) Positioned(top: 85, left: 20, right: 20,
          child: Text(error!, style: const TextStyle(color: accent))),
        if (controls) ...[
          Positioned(top: 0, left: 0, right: 0,
            child: SafeArea(child: Container(color: Colors.black54,
              child: Row(children: [
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back)),
                Expanded(child: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
                IconButton(onPressed: () => setState(() => locked = !locked),
                  icon: Icon(locked ? Icons.lock : Icons.lock_open)),
              ])))),
          if (!locked) ...[
            Center(child: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(onPressed: () => seekBy(-10), icon: const Icon(Icons.replay_10, size: 40)),
              const SizedBox(width: 22),
              IconButton(onPressed: () => player.playOrPause(),
                icon: Icon(playing ? Icons.pause_circle : Icons.play_circle, size: 62)),
              const SizedBox(width: 22),
              IconButton(onPressed: () => seekBy(10), icon: const Icon(Icons.forward_10, size: 40)),
            ])),
            Positioned(bottom: 8, left: 12, right: 12,
              child: SafeArea(top: false, child: Column(children: [
                Row(children: [
                  Text(timecode(position), style: const TextStyle(fontSize: 12)),
                  Expanded(child: Slider(
                    value: pos, max: max.toDouble(), activeColor: accent,
                    onChanged: (v) => player.seek(Duration(milliseconds: v.toInt())))),
                  Text(timecode(duration), style: const TextStyle(fontSize: 12)),
                ]),
                Row(children: [
                  TextButton.icon(onPressed: () => selectTracks(true),
                    icon: const Icon(Icons.audiotrack), label: const Text('Audio')),
                  TextButton.icon(onPressed: () => selectTracks(false),
                    icon: const Icon(Icons.subtitles), label: const Text('Subtitles')),
                  TextButton(onPressed: chooseRate, child: Text('${rate}x')),
                  const Spacer(),
                  IconButton(tooltip: 'Fill / fit', onPressed: () => setState(() => fill = !fill),
                    icon: Icon(fill ? Icons.fit_screen : Icons.aspect_ratio)),
                ]),
              ]))),
          ],
        ],
      ]),
    ));
  }
}
