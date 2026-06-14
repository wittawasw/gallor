part of '../../main.dart';

class PdfFileViewer extends StatefulWidget {
  final File file;
  const PdfFileViewer({super.key, required this.file});

  @override
  State<PdfFileViewer> createState() => _PdfFileViewerState();
}

class _PdfFileViewerState extends State<PdfFileViewer> {
  late PdfControllerPinch controller;

  @override
  void initState() {
    super.initState();
    controller = _createController();
  }

  @override
  void didUpdateWidget(covariant PdfFileViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file.path == widget.file.path) return;
    controller.dispose();
    controller = _createController();
  }

  PdfControllerPinch _createController() {
    return PdfControllerPinch(document: PdfDocument.openFile(widget.file.path));
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PdfViewPinch(controller: controller);
  }
}
