part of '../main.dart';

final videoThumbnailer = FcNativeVideoThumbnail();

const thumbsDirName = '.thumbs';

Future<List<MediaPreview>> ensureMediaPreviews(
  Directory dir,
  Iterable<File> files,
) async {
  final media = files.where((f) => isMediaFile(f.path)).toList();
  if (media.isEmpty) return const <MediaPreview>[];

  final thumbs = Directory('${dir.path}/$thumbsDirName');
  if (!await thumbs.exists()) await thumbs.create(recursive: true);

  final result = <MediaPreview>[];
  for (final file in media) {
    try {
      final video = isVideo(file.path);
      final pdf = isPdf(file.path);
      final thumb = File('${thumbs.path}/${basename(file.path)}');
      if (!await thumb.exists()) {
        if (video) {
          await createVideoThumb(file, thumb);
        } else if (pdf) {
          await createPdfThumb(file, thumb);
        } else {
          await createImageThumb(file, thumb);
        }
      }
      final hasThumb = await thumb.exists();
      final metadata = video
          ? await readVideoMetadata(file)
          : pdf
          ? await readPdfMetadata(file)
          : await readImageMetadata(file);
      result.add(
        MediaPreview(
          sourcePath: file.path,
          isVideo: video,
          isPdf: pdf,
          thumbPath: hasThumb ? thumb.path : null,
          width: metadata.width,
          height: metadata.height,
          duration: metadata.duration,
          pageCount: metadata.pageCount,
        ),
      );
    } catch (_) {
      continue;
    }
  }
  return result;
}

Future<void> createPdfThumb(File source, File target) async {
  PdfDocument? document;
  PdfPage? page;
  try {
    document = await PdfDocument.openFile(source.path);
    if (document.pagesCount < 1) return;
    page = await document.getPage(1);
    final scale = 320 / page.width;
    final pageImage = await page.render(
      width: 320,
      height: page.height * scale,
      format: PdfPageImageFormat.png,
      backgroundColor: '#FFFFFF',
    );
    if (pageImage == null) return;
    await target.writeAsBytes(pageImage.bytes, flush: true);
  } catch (_) {
    if (await target.exists()) await target.delete();
  } finally {
    await page?.close();
    await document?.close();
  }
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

Future<MediaMetadata> readPdfMetadata(File file) async {
  PdfDocument? document;
  PdfPage? page;
  try {
    document = await PdfDocument.openFile(file.path);
    if (document.pagesCount < 1) {
      return MediaMetadata(pageCount: document.pagesCount);
    }
    page = await document.getPage(1);
    return MediaMetadata(
      width: page.width.round(),
      height: page.height.round(),
      pageCount: document.pagesCount,
    );
  } finally {
    await page?.close();
    await document?.close();
  }
}
