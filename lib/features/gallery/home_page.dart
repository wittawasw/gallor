part of '../../main.dart';

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
    await repairLegacyUtf8FileNames(dir);
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

  List<File> get mediaFiles =>
      entries.whereType<File>().where((f) => isMediaFile(f.path)).toList();

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
    final isMedia = e is File && isMediaFile(e.path);
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
    if (isPdf(e.path)) return pdfSubtitle(preview);
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
        final isMedia = e is File && isMediaFile(e.path);
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
          padding: const EdgeInsets.all(4),
          sliver: SliverGrid.builder(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 120,
              mainAxisExtent: 120,
              crossAxisSpacing: 4,
              mainAxisSpacing: 4,
            ),
            itemCount: files.length,
            itemBuilder: (context, i) {
              final e = files[i];
              final isMedia = isMediaFile(e.path);
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
                    padding: const EdgeInsets.all(2),
                    child: isMedia
                        ? MediaPreviewTile(
                            preview: preview,
                            size: double.infinity,
                          )
                        : Center(
                            child: Icon(
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
