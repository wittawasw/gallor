part of '../main.dart';

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

String pdfSubtitle(MediaPreview? preview) {
  final pages = preview?.pageCount;
  final size = preview?.width == null || preview?.height == null
      ? null
      : '${preview!.width}x${preview.height}';
  return [
    'PDF',
    if (pages != null) '$pages page${pages == 1 ? '' : 's'}',
    ?size,
  ].join(' ');
}

String formatDuration(Duration duration) {
  String two(int n) => n.toString().padLeft(2, '0');
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);
  if (hours > 0) return '$hours:${two(minutes)}:${two(seconds)}';
  return '$minutes:${two(seconds)}';
}
