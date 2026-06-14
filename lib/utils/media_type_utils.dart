part of '../main.dart';

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

bool isPdf(String path) => path.toLowerCase().endsWith('.pdf');

bool isMediaFile(String path) => isImage(path) || isVideo(path) || isPdf(path);
