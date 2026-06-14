part of '../main.dart';

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
