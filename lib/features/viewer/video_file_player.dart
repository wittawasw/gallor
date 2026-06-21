part of '../../main.dart';

class VideoFilePlayer extends StatefulWidget {
  final File file;
  const VideoFilePlayer({super.key, required this.file});

  @override
  State<VideoFilePlayer> createState() => _VideoFilePlayerState();
}

class _VideoFilePlayerState extends State<VideoFilePlayer> {
  VideoPlayerController? c;
  bool ready = false;
  Object? loadError;
  int loadToken = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant VideoFilePlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file.path != widget.file.path) _load();
  }

  Future<void> _load() async {
    final token = ++loadToken;
    final old = c;
    old?.removeListener(_onVideoChanged);
    c = null;
    if (mounted) {
      setState(() {
        ready = false;
        loadError = null;
      });
    }
    await old?.dispose();

    final nc = VideoPlayerController.file(widget.file);
    nc.addListener(_onVideoChanged);
    if (!mounted || token != loadToken) {
      nc.removeListener(_onVideoChanged);
      await nc.dispose();
      return;
    }
    c = nc;

    try {
      await nc.initialize();
      await nc.setLooping(true);
      if (!mounted || token != loadToken) return;
      setState(() => ready = true);
    } catch (e) {
      nc.removeListener(_onVideoChanged);
      await nc.dispose();
      if (!mounted || token != loadToken) return;
      c = null;
      setState(() => loadError = e);
    }
  }

  void _onVideoChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _togglePlayback() async {
    final vc = c;
    if (!ready || vc == null) return;
    vc.value.isPlaying ? await vc.pause() : await vc.play();
    if (mounted) setState(() {});
  }

  Future<void> _seekBy(Duration offset) async {
    final vc = c;
    if (!ready || vc == null) return;
    final duration = vc.value.duration;
    final target = vc.value.position + offset;
    await vc.seekTo(
      target < Duration.zero
          ? Duration.zero
          : target > duration
          ? duration
          : target,
    );
  }

  Widget _seekButton({
    required Duration offset,
    required IconData icon,
    required String label,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          color: Colors.white,
          icon: Icon(icon),
          tooltip: label,
          onPressed: () => _seekBy(offset),
        ),
        Text(label, style: const TextStyle(color: Colors.white)),
      ],
    );
  }

  @override
  void dispose() {
    loadToken++;
    c?.removeListener(_onVideoChanged);
    c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vc = c;
    if (loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Could not load video',
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: Colors.white),
          ),
        ),
      );
    }
    if (!ready || vc == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final duration = vc.value.duration;
    final showHours = duration.inHours > 0;
    final position = vc.value.position > duration
        ? duration
        : vc.value.position;
    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _togglePlayback,
              child: Center(
                child: AspectRatio(
                  aspectRatio: vc.value.aspectRatio,
                  child: VideoPlayer(vc),
                ),
              ),
            ),
          ),
          VideoProgressIndicator(
            vc,
            allowScrubbing: true,
            padding: const EdgeInsets.all(12),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _seekButton(
                offset: const Duration(minutes: -1),
                icon: Icons.keyboard_double_arrow_left,
                label: '-1m',
              ),
              _seekButton(
                offset: const Duration(seconds: -10),
                icon: Icons.replay_10,
                label: '-10s',
              ),
              IconButton(
                color: Colors.white,
                iconSize: 48,
                icon: Icon(
                  vc.value.isPlaying ? Icons.pause_circle : Icons.play_circle,
                ),
                onPressed: _togglePlayback,
              ),
              _seekButton(
                offset: const Duration(seconds: 10),
                icon: Icons.forward_10,
                label: '+10s',
              ),
              _seekButton(
                offset: const Duration(minutes: 1),
                icon: Icons.keyboard_double_arrow_right,
                label: '+1m',
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '${formatPlaybackTime(position, showHours: showHours)} / '
              '${formatPlaybackTime(duration, showHours: showHours)}',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
