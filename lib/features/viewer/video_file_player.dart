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
              IconButton(
                color: Colors.white,
                iconSize: 48,
                icon: Icon(
                  vc.value.isPlaying ? Icons.pause_circle : Icons.play_circle,
                ),
                onPressed: _togglePlayback,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
