import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:fc_native_video_thumbnail/fc_native_video_thumbnail.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const GalleryServerApp());
}

final videoThumbnailer = FcNativeVideoThumbnail();

enum GalleryViewMode { list, cards }

class GalleryServerApp extends StatelessWidget {
  const GalleryServerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Gallery Server MVP',
      theme: ThemeData(useMaterial3: true),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Directory? rootDir;
  Directory? currentDir;
  List<FileSystemEntity> entries = [];
  final Map<String, MediaPreview> previews = <String, MediaPreview>{};
  final Map<String, DirectoryCacheEntry> directoryCache =
      <String, DirectoryCacheEntry>{};
  final Set<String> selected = <String>{};
  HttpServer? server;
  String? serverUrl;
  bool loading = true;
  bool refreshingThumbs = false;
  GalleryViewMode viewMode = GalleryViewMode.list;
  int directoryLoadRequest = 0;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    server?.close(force: true);
    super.dispose();
  }

  Future<void> _init() async {
    final docs = await getApplicationDocumentsDirectory();
    final root = Directory('${docs.path}/vault');
    if (!await root.exists()) await root.create(recursive: true);
    rootDir = root;
    await _loadViewMode(docs);
    await _loadDirectoryCache(docs);
    await _openDirectory(root);
  }

  Future<void> _loadViewMode(Directory docs) async {
    final file = File('${docs.path}/gallery_settings.json');
    if (!await file.exists()) return;
    try {
      final data = jsonDecode(await file.readAsString());
      viewMode = data['viewMode'] == 'cards'
          ? GalleryViewMode.cards
          : GalleryViewMode.list;
    } catch (_) {}
  }

  Future<void> _saveViewMode() async {
    final docs = await getApplicationDocumentsDirectory();
    final file = File('${docs.path}/gallery_settings.json');
    await file.writeAsString(jsonEncode({'viewMode': viewMode.name}));
  }

  Future<void> _loadDirectoryCache(Directory docs) async {
    final file = File('${docs.path}/gallery_cache.json');
    if (!await file.exists()) return;
    try {
      final data = jsonDecode(await file.readAsString());
      final dirs = data['directories'];
      if (dirs is! Map) return;
      directoryCache
        ..clear()
        ..addEntries(
          dirs.entries
              .where((entry) => entry.key is String && entry.value is Map)
              .map(
                (entry) => MapEntry(
                  entry.key as String,
                  DirectoryCacheEntry.fromJson(
                    Map<String, dynamic>.from(entry.value as Map),
                  ),
                ),
              ),
        );
    } catch (_) {}
  }

  Future<void> _saveDirectoryCache() async {
    final docs = await getApplicationDocumentsDirectory();
    final file = File('${docs.path}/gallery_cache.json');
    final data = {
      'directories': {
        for (final entry in directoryCache.entries)
          entry.key: entry.value.toJson(),
      },
    };
    await file.writeAsString(jsonEncode(data));
  }

  void _persistDirectoryCache() {
    unawaited(_saveDirectoryCache());
  }

  void _toggleViewMode() {
    setState(() {
      viewMode = viewMode == GalleryViewMode.list
          ? GalleryViewMode.cards
          : GalleryViewMode.list;
    });
    unawaited(_saveViewMode());
  }

  Future<void> _refresh() async {
    final dir = currentDir;
    if (dir == null) return;
    directoryCache.remove(dir.path);
    await _openDirectory(dir, force: true);
  }

  Future<void> _openDirectory(Directory dir, {bool force = false}) async {
    final request = ++directoryLoadRequest;
    currentDir = dir;
    selected.clear();
    if (!force) {
      final cached = directoryCache[dir.path];
      if (cached != null) {
        _showDirectoryCache(cached);
        return;
      }
    }
    if (!mounted) return;
    setState(() {
      entries = [];
      previews.clear();
      loading = true;
    });
    final scannedEntries = (await dir.list().toList())
        .where((e) => basename(e.path) != thumbsDirName)
        .toList();
    if (!mounted || request != directoryLoadRequest) return;
    sortEntries(scannedEntries);
    final generated = await ensureMediaPreviews(
      dir,
      scannedEntries.whereType<File>(),
    );
    if (!mounted || request != directoryLoadRequest) return;
    final scannedPreviews = {
      for (final preview in generated) preview.sourcePath: preview,
    };
    final cache = DirectoryCacheEntry(
      entries: scannedEntries,
      previews: scannedPreviews,
    );
    directoryCache[dir.path] = cache;
    _persistDirectoryCache();
    _showDirectoryCache(cache);
  }

  void _showDirectoryCache(DirectoryCacheEntry cache) {
    selected.removeWhere((p) => !cache.entries.any((e) => e.path == p));
    setState(() {
      entries = List<FileSystemEntity>.of(cache.entries);
      previews
        ..clear()
        ..addAll(cache.previews);
      loading = false;
    });
  }

  Future<void> _rebuildThumbs() async {
    final dir = currentDir;
    if (dir == null || refreshingThumbs) return;
    setState(() => refreshingThumbs = true);
    try {
      final thumbs = Directory('${dir.path}/$thumbsDirName');
      if (await thumbs.exists()) await thumbs.delete(recursive: true);
      directoryCache.remove(dir.path);
      _persistDirectoryCache();
      await _openDirectory(dir, force: true);
    } finally {
      if (mounted) setState(() => refreshingThumbs = false);
    }
  }

  List<File> get mediaFiles => entries
      .whereType<File>()
      .where((f) => isImage(f.path) || isVideo(f.path))
      .toList();

  void _addEntriesToCache(Directory dir, List<FileSystemEntity> newEntries) {
    if (newEntries.isEmpty) return;
    final cache = _cacheForMutation(dir);
    if (cache == null) return;
    final paths = newEntries.map((e) => e.path).toSet();
    cache.entries.removeWhere((e) => paths.contains(e.path));
    cache.entries.addAll(newEntries);
    sortEntries(cache.entries);
    _persistDirectoryCache();
    if (currentDir?.path == dir.path && mounted) _showDirectoryCache(cache);
  }

  Future<void> _addFilesToCache(Directory dir, List<File> files) async {
    if (files.isEmpty) return;
    final generated = await ensureMediaPreviews(dir, files);
    final cache = _cacheForMutation(dir);
    if (cache == null) return;
    final paths = files.map((f) => f.path).toSet();
    cache.entries.removeWhere((e) => paths.contains(e.path));
    cache.entries.addAll(files);
    sortEntries(cache.entries);
    for (final preview in generated) {
      cache.previews[preview.sourcePath] = preview;
    }
    _persistDirectoryCache();
    if (currentDir?.path == dir.path && mounted) _showDirectoryCache(cache);
  }

  DirectoryCacheEntry? _cacheForMutation(Directory dir) {
    final cached = directoryCache[dir.path];
    if (cached != null) return cached;
    if (currentDir?.path != dir.path) return null;
    return directoryCache[dir.path] = DirectoryCacheEntry(
      entries: entries,
      previews: previews,
    );
  }

  void _removeEntriesFromCache(Directory dir, List<String> paths) {
    if (paths.isEmpty) return;
    final cache = directoryCache[dir.path];
    if (cache == null) return;
    final deleted = paths.toSet();
    cache.entries.removeWhere((e) => deleted.contains(e.path));
    for (final path in deleted) {
      cache.previews.remove(path);
    }
    _persistDirectoryCache();
    if (currentDir?.path == dir.path && mounted) _showDirectoryCache(cache);
  }

  void _removeDirectoryCaches(String deletedPath) {
    final prefix = '$deletedPath/';
    directoryCache.removeWhere(
      (path, _) => path == deletedPath || path.startsWith(prefix),
    );
    _persistDirectoryCache();
  }

  Future<void> _createDirectory() async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) {
        final c = TextEditingController();
        return AlertDialog(
          title: const Text('Create directory'),
          content: TextField(
            controller: c,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Folder name'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, c.text.trim()),
              child: const Text('Create'),
            ),
          ],
        );
      },
    );
    if (name == null || name.isEmpty) return;
    final safe = sanitizeFileName(name);
    final created = await Directory(
      '${currentDir!.path}/$safe',
    ).create(recursive: true);
    _addEntriesToCache(currentDir!, [created]);
  }

  Future<void> _deletePaths(List<String> paths) async {
    if (paths.isEmpty) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete?'),
        content: Text('Delete ${paths.length} item(s)?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    final deleted = <String>[];
    for (final p in paths) {
      final type = await FileSystemEntity.type(p);
      if (type == FileSystemEntityType.directory) {
        await Directory(p).delete(recursive: true);
        _removeDirectoryCaches(p);
        deleted.add(p);
      } else if (type == FileSystemEntityType.file) {
        final thumb = File(
          '${File(p).parent.path}/$thumbsDirName/${basename(p)}',
        );
        if (await thumb.exists()) await thumb.delete();
        await File(p).delete();
        deleted.add(p);
      }
    }
    selected.clear();
    _removeEntriesFromCache(currentDir!, deleted);
  }

  Future<void> _goUp() async {
    if (rootDir == null || currentDir == null) return;
    if (currentDir!.path == rootDir!.path) return;
    await _openDirectory(currentDir!.parent);
  }

  Future<void> _toggleServer() async {
    if (server != null) {
      await server!.close(force: true);
      setState(() {
        server = null;
        serverUrl = null;
      });
      return;
    }

    final s = await HttpServer.bind(
      InternetAddress.anyIPv4,
      8080,
      shared: true,
    );
    server = s;
    final ip = await getLocalIp() ?? '127.0.0.1';
    setState(() => serverUrl = 'http://$ip:8080');

    unawaited(() async {
      await for (final req in s) {
        final uploadDir = currentDir!;
        try {
          await handleHttpRequest(req, uploadDir, (files) async {
            await _addFilesToCache(uploadDir, files);
          });
        } catch (e) {
          req.response.statusCode = 500;
          req.response.write('Error: $e');
          await req.response.close();
        }
      }
    }());
  }

  void _openViewer(File file) {
    final files = mediaFiles;
    final index = files.indexWhere((f) => f.path == file.path);
    if (index < 0) return;
    unawaited(
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MediaViewerPage(
            files: files,
            initialIndex: index,
            onDelete: (f) async {
              await _deletePaths([f.path]);
              return mediaFiles;
            },
          ),
        ),
      ),
    );
  }

  void _toggleSelected(String path) {
    setState(() {
      selected.contains(path) ? selected.remove(path) : selected.add(path);
    });
  }

  Future<void> _openEntry(FileSystemEntity e) async {
    final isDir = e is Directory;
    final isMedia = e is File && (isImage(e.path) || isVideo(e.path));
    final checked = selected.contains(e.path);
    if (selected.isNotEmpty) {
      _toggleSelected(e.path);
      return;
    }
    if (isDir) {
      await _openDirectory(e);
    } else if (isMedia) {
      _openViewer(e);
    } else if (checked) {
      _toggleSelected(e.path);
    }
  }

  String _entrySubtitle(FileSystemEntity e, MediaPreview? preview) {
    if (e is Directory) return 'Directory';
    if (isVideo(e.path)) return videoSubtitle(preview);
    if (isImage(e.path)) return imageSubtitle(preview);
    return 'File';
  }

  @override
  Widget build(BuildContext context) {
    final dir = currentDir;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          dir == null ? 'Gallery' : shortPath(dir.path, rootDir?.path),
        ),
        actions: [
          IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh)),
          IconButton(
            tooltip: viewMode == GalleryViewMode.list
                ? 'Card view'
                : 'List view',
            onPressed: _toggleViewMode,
            icon: Icon(
              viewMode == GalleryViewMode.list
                  ? Icons.grid_view
                  : Icons.view_list,
            ),
          ),
          IconButton(
            tooltip: 'Rebuild thumbnails',
            onPressed: refreshingThumbs ? null : _rebuildThumbs,
            icon: refreshingThumbs
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.photo_size_select_actual),
          ),
          IconButton(
            onPressed: _createDirectory,
            icon: const Icon(Icons.create_new_folder),
          ),
          IconButton(
            onPressed: selected.isEmpty
                ? null
                : () => _deletePaths(selected.toList()),
            icon: const Icon(Icons.delete),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    children: [
                      FilledButton.tonal(
                        onPressed: _goUp,
                        child: const Text('Up'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _toggleServer,
                        child: Text(
                          server == null
                              ? 'Start upload server'
                              : 'Stop server',
                        ),
                      ),
                    ],
                  ),
                ),
                if (serverUrl != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: SelectableText('Upload URL: $serverUrl'),
                  ),
                const Divider(height: 1),
                Expanded(
                  child: entries.isEmpty
                      ? const Center(child: Text('Empty'))
                      : viewMode == GalleryViewMode.list
                      ? _buildListView()
                      : _buildCardView(),
                ),
              ],
            ),
    );
  }

  Widget _buildListView() {
    return ListView.builder(
      itemCount: entries.length,
      itemBuilder: (context, i) {
        final e = entries[i];
        final name = basename(e.path);
        final isDir = e is Directory;
        final isMedia = e is File && (isImage(e.path) || isVideo(e.path));
        final preview = previews[e.path];
        final checked = selected.contains(e.path);
        return ListTile(
          leading: SizedBox(
            width: 96,
            height: 56,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Checkbox(
                  value: checked,
                  onChanged: (_) => _toggleSelected(e.path),
                ),
                if (isMedia)
                  MediaPreviewTile(preview: preview)
                else
                  Icon(isDir ? Icons.folder : Icons.insert_drive_file),
              ],
            ),
          ),
          title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(_entrySubtitle(e, preview)),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _deletePaths([e.path]),
          ),
          onTap: () => unawaited(_openEntry(e)),
        );
      },
    );
  }

  Widget _buildCardView() {
    final dirs = entries.whereType<Directory>().toList();
    final files = entries.whereType<File>().toList();
    return CustomScrollView(
      slivers: [
        if (dirs.isNotEmpty)
          SliverList.builder(
            itemCount: dirs.length,
            itemBuilder: (context, i) {
              final e = dirs[i];
              final name = basename(e.path);
              final checked = selected.contains(e.path);
              return ListTile(
                leading: const Icon(Icons.folder),
                title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                selected: checked,
                onLongPress: () => _toggleSelected(e.path),
                onTap: () => unawaited(_openEntry(e)),
              );
            },
          ),
        SliverPadding(
          padding: const EdgeInsets.all(8),
          sliver: SliverGrid.builder(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 108,
              mainAxisExtent: 108,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: files.length,
            itemBuilder: (context, i) {
              final e = files[i];
              final isMedia = isImage(e.path) || isVideo(e.path);
              final preview = previews[e.path];
              final checked = selected.contains(e.path);
              final colorScheme = Theme.of(context).colorScheme;
              return InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => unawaited(_openEntry(e)),
                onLongPress: () => _toggleSelected(e.path),
                child: Card(
                  color: checked ? colorScheme.primaryContainer : null,
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Center(
                      child: isMedia
                          ? MediaPreviewTile(preview: preview, size: 76)
                          : Icon(
                              Icons.insert_drive_file,
                              size: 56,
                              color: checked
                                  ? colorScheme.onPrimaryContainer
                                  : null,
                            ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class MediaViewerPage extends StatefulWidget {
  final List<File> files;
  final int initialIndex;
  final Future<List<File>> Function(File file) onDelete;

  const MediaViewerPage({
    super.key,
    required this.files,
    required this.initialIndex,
    required this.onDelete,
  });

  @override
  State<MediaViewerPage> createState() => _MediaViewerPageState();
}

class _MediaViewerPageState extends State<MediaViewerPage> {
  late PageController controller;
  late List<File> files;
  late int index;

  @override
  void initState() {
    super.initState();
    files = List.of(widget.files);
    index = widget.initialIndex;
    controller = PageController(initialPage: index);
  }

  Future<void> _deleteCurrent() async {
    if (files.isEmpty) return;
    final file = files[index];
    final nextFiles = await widget.onDelete(file);
    if (!mounted) return;
    setState(() {
      files = nextFiles;
      if (files.isEmpty) {
        Navigator.pop(context);
        return;
      }
      if (index >= files.length) index = files.length - 1;
      controller = PageController(initialPage: index);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (files.isEmpty) return const Scaffold(body: SizedBox());
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        foregroundColor: Colors.white,
        backgroundColor: Colors.black,
        title: Text(
          '${index + 1}/${files.length}',
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          IconButton(onPressed: _deleteCurrent, icon: const Icon(Icons.delete)),
        ],
      ),
      body: PageView.builder(
        controller: controller,
        itemCount: files.length,
        onPageChanged: (i) => setState(() => index = i),
        itemBuilder: (context, i) => MediaPage(file: files[i]),
      ),
    );
  }
}

class MediaPage extends StatelessWidget {
  final File file;
  const MediaPage({super.key, required this.file});

  @override
  Widget build(BuildContext context) {
    if (isVideo(file.path)) return VideoFilePlayer(file: file);
    return Center(
      child: InteractiveViewer(
        minScale: 0.5,
        maxScale: 5,
        child: Image.file(file, fit: BoxFit.contain),
      ),
    );
  }
}

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
            child: Center(
              child: AspectRatio(
                aspectRatio: vc.value.aspectRatio,
                child: VideoPlayer(vc),
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
                onPressed: () async {
                  vc.value.isPlaying ? await vc.pause() : await vc.play();
                  setState(() {});
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

const thumbsDirName = '.thumbs';

class DirectoryCacheEntry {
  final List<FileSystemEntity> entries;
  final Map<String, MediaPreview> previews;

  DirectoryCacheEntry({
    required List<FileSystemEntity> entries,
    required Map<String, MediaPreview> previews,
  }) : entries = List<FileSystemEntity>.of(entries),
       previews = Map<String, MediaPreview>.of(previews);

  factory DirectoryCacheEntry.fromJson(Map<String, dynamic> json) {
    final rawEntries = json['entries'];
    final rawPreviews = json['previews'];
    return DirectoryCacheEntry(
      entries: rawEntries is List
          ? rawEntries
                .whereType<Map>()
                .map((e) => fileSystemEntityFromJson(Map.from(e)))
                .whereType<FileSystemEntity>()
                .toList()
          : const <FileSystemEntity>[],
      previews: rawPreviews is Map
          ? rawPreviews.map(
              (key, value) => MapEntry(
                key.toString(),
                MediaPreview.fromJson(Map<String, dynamic>.from(value as Map)),
              ),
            )
          : const <String, MediaPreview>{},
    );
  }

  Map<String, dynamic> toJson() => {
    'entries': entries.map(fileSystemEntityToJson).toList(),
    'previews': previews.map((key, value) => MapEntry(key, value.toJson())),
  };
}

class MediaPreview {
  final String sourcePath;
  final String? thumbPath;
  final bool isVideo;
  final int? width;
  final int? height;
  final Duration? duration;

  const MediaPreview({
    required this.sourcePath,
    required this.isVideo,
    this.thumbPath,
    this.width,
    this.height,
    this.duration,
  });

  factory MediaPreview.fromJson(Map<String, dynamic> json) => MediaPreview(
    sourcePath: json['sourcePath']?.toString() ?? '',
    isVideo: json['isVideo'] == true,
    thumbPath: json['thumbPath']?.toString(),
    width: json['width'] is int ? json['width'] as int : null,
    height: json['height'] is int ? json['height'] as int : null,
    duration: json['durationMs'] is int
        ? Duration(milliseconds: json['durationMs'] as int)
        : null,
  );

  Map<String, dynamic> toJson() => {
    'sourcePath': sourcePath,
    'thumbPath': thumbPath,
    'isVideo': isVideo,
    'width': width,
    'height': height,
    'durationMs': duration?.inMilliseconds,
  };
}

class MediaPreviewTile extends StatelessWidget {
  final MediaPreview? preview;
  final double size;

  const MediaPreviewTile({super.key, required this.preview, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final p = preview;
    final thumbPath = p?.thumbPath;
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Container(
        width: size,
        height: size,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: p == null
            ? const Icon(Icons.image, size: 20)
            : thumbPath == null
            ? const Icon(Icons.movie, size: 20)
            : Stack(
                fit: StackFit.expand,
                children: [
                  Image.file(
                    File(thumbPath),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const Icon(Icons.broken_image),
                  ),
                  if (p.isVideo)
                    const Center(
                      child: Icon(
                        Icons.play_circle_fill,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

Future<List<MediaPreview>> ensureMediaPreviews(
  Directory dir,
  Iterable<File> files,
) async {
  final media = files.where((f) => isImage(f.path) || isVideo(f.path)).toList();
  if (media.isEmpty) return const <MediaPreview>[];

  final thumbs = Directory('${dir.path}/$thumbsDirName');
  if (!await thumbs.exists()) await thumbs.create(recursive: true);

  final result = <MediaPreview>[];
  for (final file in media) {
    try {
      final video = isVideo(file.path);
      final thumb = File('${thumbs.path}/${basename(file.path)}');
      if (!await thumb.exists()) {
        if (video) {
          await createVideoThumb(file, thumb);
        } else {
          await createImageThumb(file, thumb);
        }
      }
      final hasThumb = await thumb.exists();
      final metadata = video
          ? await readVideoMetadata(file)
          : await readImageMetadata(file);
      result.add(
        MediaPreview(
          sourcePath: file.path,
          isVideo: video,
          thumbPath: hasThumb ? thumb.path : null,
          width: metadata.width,
          height: metadata.height,
          duration: metadata.duration,
        ),
      );
    } catch (_) {
      continue;
    }
  }
  return result;
}

Future<void> createVideoThumb(File source, File target) async {
  try {
    final created = await videoThumbnailer.saveThumbnailToFile(
      srcFile: source.path,
      destFile: target.path,
      width: 320,
      height: 320,
      format: 'jpeg',
      quality: 75,
    );
    if (!created && await target.exists()) await target.delete();
  } catch (_) {
    if (await target.exists()) await target.delete();
  }
}

Future<void> createImageThumb(File source, File target) async {
  final bytes = await source.readAsBytes();
  final codec = await ui.instantiateImageCodec(bytes, targetWidth: 320);
  final frame = await codec.getNextFrame();
  final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
  if (data == null) return;
  await target.writeAsBytes(data.buffer.asUint8List(), flush: true);
}

Future<MediaMetadata> readImageMetadata(File file) async {
  final bytes = await file.readAsBytes();
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  return MediaMetadata(width: frame.image.width, height: frame.image.height);
}

Future<MediaMetadata> readVideoMetadata(File file) async {
  final controller = VideoPlayerController.file(file);
  try {
    await controller.initialize();
    final value = controller.value;
    return MediaMetadata(
      width: value.size.width.round(),
      height: value.size.height.round(),
      duration: value.duration,
    );
  } finally {
    await controller.dispose();
  }
}

class MediaMetadata {
  final int? width;
  final int? height;
  final Duration? duration;

  const MediaMetadata({this.width, this.height, this.duration});
}

String imageSubtitle(MediaPreview? preview) {
  if (preview?.width == null || preview?.height == null) return 'Photo';
  return 'Photo ${preview!.width}x${preview.height}';
}

String videoSubtitle(MediaPreview? preview) {
  final size = preview?.width == null || preview?.height == null
      ? null
      : '${preview!.width}x${preview.height}';
  final duration = preview?.duration == null
      ? null
      : formatDuration(preview!.duration!);
  return ['Video', ?duration, ?size].join(' ');
}

String formatDuration(Duration duration) {
  String two(int n) => n.toString().padLeft(2, '0');
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);
  if (hours > 0) return '$hours:${two(minutes)}:${two(seconds)}';
  return '$minutes:${two(seconds)}';
}

Future<void> handleHttpRequest(
  HttpRequest req,
  Directory uploadDir,
  Future<void> Function(List<File> files) onUploaded,
) async {
  req.response.headers.set('Access-Control-Allow-Origin', '*');
  if (req.method == 'GET') {
    req.response.headers.contentType = ContentType.html;
    req.response.write(uploadPage(uploadDir.path));
    await req.response.close();
    return;
  }

  if (req.method == 'POST' && req.uri.path == '/upload') {
    final contentType = req.headers.contentType;
    final boundary = contentType?.parameters['boundary'];
    if (boundary == null) {
      req.response.statusCode = 400;
      req.response.write('Missing multipart boundary');
      await req.response.close();
      return;
    }

    final bytes = await collectBytes(req);
    final saved = await parseAndSaveMultipart(bytes, boundary, uploadDir);
    await onUploaded(saved);
    req.response.headers.contentType = ContentType.html;
    req.response.write(
      '<p>Uploaded ${saved.length} file(s).</p><p><a href="/">Back</a></p>',
    );
    await req.response.close();
    return;
  }

  req.response.statusCode = 404;
  req.response.write('Not found');
  await req.response.close();
}

String uploadPage(String path) =>
    '''
<!doctype html>
<html>
<head><meta name="viewport" content="width=device-width, initial-scale=1"><title>Upload</title></head>
<body style="font-family:sans-serif;padding:24px">
<h3>Upload to phone</h3>
<p>Directory: ${htmlEscape.convert(path)}</p>
<form method="post" action="/upload" enctype="multipart/form-data">
<input type="file" name="files" multiple accept="image/*,video/*"><br><br>
<button type="submit">Upload</button>
</form>
</body>
</html>
''';

Future<Uint8List> collectBytes(Stream<List<int>> stream) async {
  final builder = BytesBuilder(copy: false);
  await for (final chunk in stream) {
    builder.add(chunk);
  }
  return builder.takeBytes();
}

Future<List<File>> parseAndSaveMultipart(
  Uint8List body,
  String boundary,
  Directory dir,
) async {
  final marker = ascii.encode('--$boundary');
  final parts = splitBytes(body, marker);
  final saved = <File>[];
  for (final part in parts) {
    if (part.length < 10) continue;
    final headerEnd = indexOfBytes(part, Uint8List.fromList([13, 10, 13, 10]));
    if (headerEnd < 0) continue;

    final header = latin1.decode(
      part.sublist(0, headerEnd),
      allowInvalid: true,
    );
    final filenameMatch = RegExp(r'filename="([^"]*)"').firstMatch(header);
    final rawName = filenameMatch?.group(1);
    if (rawName == null || rawName.isEmpty) continue;

    var data = part.sublist(headerEnd + 4);
    while (data.isNotEmpty &&
        (data.last == 10 || data.last == 13 || data.last == 45)) {
      data = data.sublist(0, data.length - 1);
    }
    if (data.isEmpty) continue;

    final filename = uniqueFileName(dir, sanitizeFileName(rawName));
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(data, flush: true);
    saved.add(file);
  }
  return saved;
}

List<Uint8List> splitBytes(Uint8List data, List<int> marker) {
  final result = <Uint8List>[];
  var start = 0;
  while (true) {
    final idx = indexOfBytes(data, Uint8List.fromList(marker), start);
    if (idx < 0) {
      if (start < data.length) result.add(data.sublist(start));
      break;
    }
    if (idx > start) result.add(data.sublist(start, idx));
    start = idx + marker.length;
  }
  return result;
}

int indexOfBytes(Uint8List data, Uint8List pattern, [int start = 0]) {
  outer:
  for (var i = start; i <= data.length - pattern.length; i++) {
    for (var j = 0; j < pattern.length; j++) {
      if (data[i + j] != pattern[j]) continue outer;
    }
    return i;
  }
  return -1;
}

String uniqueFileName(Directory dir, String name) {
  final dot = name.lastIndexOf('.');
  final base = dot > 0 ? name.substring(0, dot) : name;
  final ext = dot > 0 ? name.substring(dot) : '';
  var candidate = name;
  var n = 1;
  while (File('${dir.path}/$candidate').existsSync()) {
    candidate = '${base}_$n$ext';
    n++;
  }
  return candidate;
}

void sortEntries(List<FileSystemEntity> entries) {
  entries.sort((a, b) {
    final ad = a is Directory ? 0 : 1;
    final bd = b is Directory ? 0 : 1;
    if (ad != bd) return ad.compareTo(bd);
    return a.path.toLowerCase().compareTo(b.path.toLowerCase());
  });
}

Map<String, dynamic> fileSystemEntityToJson(FileSystemEntity entity) => {
  'path': entity.path,
  'type': entity is Directory ? 'directory' : 'file',
};

FileSystemEntity? fileSystemEntityFromJson(Map<dynamic, dynamic> json) {
  final path = json['path']?.toString();
  final type = json['type']?.toString();
  if (path == null || path.isEmpty) return null;
  if (type == 'directory') return Directory(path);
  if (type == 'file') return File(path);
  return null;
}

String sanitizeFileName(String name) {
  return name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
}

String basename(String path) {
  final normalized = path.replaceAll('\\', '/');
  return normalized.substring(normalized.lastIndexOf('/') + 1);
}

String shortPath(String path, String? root) {
  if (root == null) return basename(path);
  if (path == root) return 'Vault';
  return 'Vault/${path.substring(root.length).replaceFirst(RegExp(r'^/+'), '')}';
}

bool isImage(String path) {
  final p = path.toLowerCase();
  return p.endsWith('.jpg') ||
      p.endsWith('.jpeg') ||
      p.endsWith('.png') ||
      p.endsWith('.gif') ||
      p.endsWith('.webp') ||
      p.endsWith('.bmp');
}

bool isVideo(String path) {
  final p = path.toLowerCase();
  return p.endsWith('.mp4') ||
      p.endsWith('.mov') ||
      p.endsWith('.m4v') ||
      p.endsWith('.webm') ||
      p.endsWith('.mkv') ||
      p.endsWith('.avi');
}

Future<String?> getLocalIp() async {
  final interfaces = await NetworkInterface.list(
    type: InternetAddressType.IPv4,
    includeLoopback: false,
  );
  for (final i in interfaces) {
    for (final a in i.addresses) {
      if (a.address.startsWith('192.168.') ||
          a.address.startsWith('10.') ||
          a.address.startsWith('172.')) {
        return a.address;
      }
    }
  }
  if (interfaces.isNotEmpty && interfaces.first.addresses.isNotEmpty) {
    return interfaces.first.addresses.first.address;
  }
  return null;
}
