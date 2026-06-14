import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const GalleryServerApp());
}

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
  final Set<String> selected = <String>{};
  HttpServer? server;
  String? serverUrl;
  bool loading = true;
  bool refreshingThumbs = false;

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
    currentDir = root;
    await _refresh();
  }

  Future<void> _refresh() async {
    final dir = currentDir;
    if (dir == null) return;
    final list = (await dir.list().toList())
        .where((e) => basename(e.path) != thumbsDirName)
        .toList();
    list.sort((a, b) {
      final ad = a is Directory ? 0 : 1;
      final bd = b is Directory ? 0 : 1;
      if (ad != bd) return ad.compareTo(bd);
      return a.path.toLowerCase().compareTo(b.path.toLowerCase());
    });
    final generated = await ensureMediaPreviews(dir, list.whereType<File>());
    if (!mounted) return;
    selected.removeWhere((p) => !list.any((e) => e.path == p));
    setState(() {
      entries = list;
      previews
        ..clear()
        ..addEntries(generated.map((p) => MapEntry(p.sourcePath, p)));
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
      await _refresh();
    } finally {
      if (mounted) setState(() => refreshingThumbs = false);
    }
  }

  List<File> get mediaFiles => entries
      .whereType<File>()
      .where((f) => isImage(f.path) || isVideo(f.path))
      .toList();

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
    await Directory('${currentDir!.path}/$safe').create(recursive: true);
    await _refresh();
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
    for (final p in paths) {
      final type = await FileSystemEntity.type(p);
      if (type == FileSystemEntityType.directory) {
        await Directory(p).delete(recursive: true);
      } else if (type == FileSystemEntityType.file) {
        final thumb = File(
          '${File(p).parent.path}/$thumbsDirName/${basename(p)}',
        );
        if (await thumb.exists()) await thumb.delete();
        await File(p).delete();
      }
    }
    selected.clear();
    await _refresh();
  }

  Future<void> _goUp() async {
    if (rootDir == null || currentDir == null) return;
    if (currentDir!.path == rootDir!.path) return;
    currentDir = currentDir!.parent;
    selected.clear();
    await _refresh();
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
        try {
          await handleHttpRequest(req, currentDir!, _refresh);
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
    ).then((_) => _refresh());
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
                      : ListView.builder(
                          itemCount: entries.length,
                          itemBuilder: (context, i) {
                            final e = entries[i];
                            final name = basename(e.path);
                            final isDir = e is Directory;
                            final isMedia =
                                e is File &&
                                (isImage(e.path) || isVideo(e.path));
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
                                      onChanged: (_) => setState(() {
                                        checked
                                            ? selected.remove(e.path)
                                            : selected.add(e.path);
                                      }),
                                    ),
                                    if (isMedia)
                                      MediaPreviewTile(preview: preview)
                                    else
                                      Icon(
                                        isDir
                                            ? Icons.folder
                                            : Icons.insert_drive_file,
                                      ),
                                  ],
                                ),
                              ),
                              title: Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                isDir
                                    ? 'Directory'
                                    : isVideo(e.path)
                                    ? videoSubtitle(preview)
                                    : isImage(e.path)
                                    ? imageSubtitle(preview)
                                    : 'File',
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => _deletePaths([e.path]),
                              ),
                              onTap: () async {
                                if (selected.isNotEmpty) {
                                  setState(
                                    () => checked
                                        ? selected.remove(e.path)
                                        : selected.add(e.path),
                                  );
                                  return;
                                }
                                if (isDir) {
                                  currentDir = e;
                                  selected.clear();
                                  await _refresh();
                                } else if (isMedia) {
                                  _openViewer(e);
                                }
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
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
    await c?.dispose();
    final nc = VideoPlayerController.file(widget.file);
    c = nc;
    setState(() => ready = false);
    await nc.initialize();
    if (!mounted) return;
    setState(() => ready = true);
  }

  @override
  void dispose() {
    c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vc = c;
    if (!ready || vc == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(
            aspectRatio: vc.value.aspectRatio,
            child: VideoPlayer(vc),
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

class MediaPreview {
  final String sourcePath;
  final String thumbPath;
  final int? width;
  final int? height;
  final Duration? duration;

  const MediaPreview({
    required this.sourcePath,
    required this.thumbPath,
    this.width,
    this.height,
    this.duration,
  });
}

class MediaPreviewTile extends StatelessWidget {
  final MediaPreview? preview;

  const MediaPreviewTile({super.key, required this.preview});

  @override
  Widget build(BuildContext context) {
    final p = preview;
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Container(
        width: 40,
        height: 40,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: p == null
            ? const Icon(Icons.image, size: 20)
            : Image.file(
                File(p.thumbPath),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const Icon(Icons.broken_image),
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
      final thumb = File('${thumbs.path}/${basename(file.path)}');
      if (!await thumb.exists()) {
        if (isVideo(file.path)) {
          await createVideoThumb(file, thumb);
        } else {
          await createImageThumb(file, thumb);
        }
      }
      final metadata = isVideo(file.path)
          ? await readVideoMetadata(file)
          : await readImageMetadata(file);
      result.add(
        MediaPreview(
          sourcePath: file.path,
          thumbPath: thumb.path,
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
  final bytes = await VideoThumbnail.thumbnailData(
    video: source.path,
    imageFormat: ImageFormat.JPEG,
    maxWidth: 320,
    quality: 75,
  );
  if (bytes == null || bytes.isEmpty) return;
  await target.writeAsBytes(bytes, flush: true);
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
  Future<void> Function() onUploaded,
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
    await onUploaded();
    req.response.headers.contentType = ContentType.html;
    req.response.write(
      '<p>Uploaded $saved file(s).</p><p><a href="/">Back</a></p>',
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

Future<int> parseAndSaveMultipart(
  Uint8List body,
  String boundary,
  Directory dir,
) async {
  final marker = ascii.encode('--$boundary');
  final parts = splitBytes(body, marker);
  var count = 0;
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
    await File('${dir.path}/$filename').writeAsBytes(data, flush: true);
    count++;
  }
  return count;
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
