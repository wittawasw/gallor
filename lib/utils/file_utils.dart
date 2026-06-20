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

String? decodeLegacyUtf8FileName(String name) {
  if (name.codeUnits.any((unit) => unit > 0xff)) return null;
  try {
    final decoded = utf8.decode(latin1.encode(name));
    return decoded == name ? null : decoded;
  } on FormatException {
    return null;
  }
}

Future<void> repairLegacyUtf8FileNames(Directory dir) async {
  final entities = await dir.list().toList();
  final thumbs = Directory('${dir.path}/$thumbsDirName');
  for (final entity in entities) {
    final oldName = basename(entity.path);
    if (oldName == thumbsDirName) continue;
    final repairedName = decodeLegacyUtf8FileName(oldName);
    if (repairedName == null || repairedName.isEmpty) continue;

    final repairedPath = '${dir.path}/$repairedName';
    if (await FileSystemEntity.type(repairedPath) !=
        FileSystemEntityType.notFound) {
      continue;
    }

    try {
      if (entity is File) {
        await entity.rename(repairedPath);
        final oldThumb = File('${thumbs.path}/$oldName');
        final repairedThumb = File('${thumbs.path}/$repairedName');
        if (await oldThumb.exists() && !await repairedThumb.exists()) {
          await oldThumb.rename(repairedThumb.path);
        }
      } else if (entity is Directory) {
        await entity.rename(repairedPath);
      }
    } on FileSystemException {
      // Keep refresh working if an entry changes while it is being repaired.
    }
  }
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
