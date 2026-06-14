part of '../main.dart';

class MediaPreview {
  final String sourcePath;
  final String? thumbPath;
  final bool isVideo;
  final bool isPdf;
  final int? width;
  final int? height;
  final Duration? duration;
  final int? pageCount;

  const MediaPreview({
    required this.sourcePath,
    required this.isVideo,
    this.isPdf = false,
    this.thumbPath,
    this.width,
    this.height,
    this.duration,
    this.pageCount,
  });

  factory MediaPreview.fromJson(Map<String, dynamic> json) => MediaPreview(
    sourcePath: json['sourcePath']?.toString() ?? '',
    isVideo: json['isVideo'] == true,
    isPdf: json['isPdf'] == true,
    thumbPath: json['thumbPath']?.toString(),
    width: json['width'] is int ? json['width'] as int : null,
    height: json['height'] is int ? json['height'] as int : null,
    duration: json['durationMs'] is int
        ? Duration(milliseconds: json['durationMs'] as int)
        : null,
    pageCount: json['pageCount'] is int ? json['pageCount'] as int : null,
  );

  Map<String, dynamic> toJson() => {
    'sourcePath': sourcePath,
    'thumbPath': thumbPath,
    'isVideo': isVideo,
    'isPdf': isPdf,
    'width': width,
    'height': height,
    'durationMs': duration?.inMilliseconds,
    'pageCount': pageCount,
  };
}
