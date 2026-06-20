import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gallor/main.dart';

void main() {
  test('sanitizes unsafe filenames', () {
    expect(sanitizeFileName('a/b:c*?"<>|.jpg'), 'a_b_c______.jpg');
    expect(sanitizeFileName('วันหยุด.jpg'), 'วันหยุด.jpg');
  });

  test('decodes Unicode multipart filenames', () {
    final thaiName = 'วันหยุด.jpg';
    final utf8AsLatin1 = latin1.decode(utf8.encode(thaiName));

    expect(
      multipartFileName(
        'Content-Disposition: form-data; name="files"; '
        'filename="$utf8AsLatin1"',
      ),
      thaiName,
    );
    expect(
      multipartFileName(
        "Content-Disposition: form-data; name=\"files\"; "
        "filename*=UTF-8''%E0%B8%A7%E0%B8%B1%E0%B8%99%E0%B8%AB%E0%B8%A2%E0%B8%B8%E0%B8%94.jpg",
      ),
      thaiName,
    );
    expect(
      multipartFileName(
        'Content-Disposition: form-data; name="files"; '
        'filename="café.jpg"',
      ),
      'café.jpg',
    );
  });

  test('repairs legacy UTF-8 filenames conservatively', () {
    final thaiName = 'วันหยุด.jpg';
    final mojibake = latin1.decode(utf8.encode(thaiName));

    expect(decodeLegacyUtf8FileName(mojibake), thaiName);
    expect(decodeLegacyUtf8FileName('café.jpg'), isNull);
    expect(decodeLegacyUtf8FileName('photo.jpg'), isNull);
  });

  test('refresh repair renames files and cached thumbnails', () async {
    final dir = await Directory.systemTemp.createTemp('gallor_unicode_');
    try {
      final thaiName = 'วันหยุด.jpg';
      final mojibake = latin1.decode(utf8.encode(thaiName));
      final thumbs = await Directory('${dir.path}/$thumbsDirName').create();
      await File('${dir.path}/$mojibake').writeAsString('image');
      await File('${thumbs.path}/$mojibake').writeAsString('thumb');

      await repairLegacyUtf8FileNames(dir);

      expect(await File('${dir.path}/$thaiName').exists(), isTrue);
      expect(await File('${thumbs.path}/$thaiName').exists(), isTrue);
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('formats paths and durations', () {
    expect(shortPath('/tmp/vault/photos', '/tmp/vault'), 'Vault/photos');
    expect(formatDuration(const Duration(minutes: 3, seconds: 7)), '3:07');
    expect(
      formatDuration(const Duration(hours: 1, minutes: 2, seconds: 3)),
      '1:02:03',
    );
  });
}
