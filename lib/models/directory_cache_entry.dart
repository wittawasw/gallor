part of '../main.dart';

class DirectoryCacheEntry {
  final List<FileSystemEntity> entries;
  final Map<String, MediaPreview> previews;

  DirectoryCacheEntry({
    required List<FileSystemEntity> entries,
    required Map<String, MediaPreview> previews,
  }) : entries = List<FileSystemEntity>.of(entries),
       previews = Map<String, MediaPreview>.of(previews);

  factory DirectoryCacheEntry.fromJson(Map<String, dynamic> json) {
    final rawEntries = json['entries'];
    final rawPreviews = json['previews'];
    return DirectoryCacheEntry(
      entries: rawEntries is List
          ? rawEntries
                .whereType<Map>()
                .map((e) => fileSystemEntityFromJson(Map.from(e)))
                .whereType<FileSystemEntity>()
                .toList()
          : const <FileSystemEntity>[],
      previews: rawPreviews is Map
          ? rawPreviews.map(
              (key, value) => MapEntry(
                key.toString(),
                MediaPreview.fromJson(Map<String, dynamic>.from(value as Map)),
              ),
            )
          : const <String, MediaPreview>{},
    );
  }

  Map<String, dynamic> toJson() => {
    'entries': entries.map(fileSystemEntityToJson).toList(),
    'previews': previews.map((key, value) => MapEntry(key, value.toJson())),
  };
}
