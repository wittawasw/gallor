part of '../../main.dart';

class MediaPage extends StatelessWidget {
  final File file;
  const MediaPage({super.key, required this.file});

  @override
  Widget build(BuildContext context) {
    if (isPdf(file.path)) return PdfFileViewer(file: file);
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
