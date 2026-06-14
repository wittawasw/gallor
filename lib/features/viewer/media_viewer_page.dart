part of '../../main.dart';

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
