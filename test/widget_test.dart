import 'package:flutter_test/flutter_test.dart';
import 'package:gallor/main.dart';

void main() {
  test('sanitizes unsafe filenames', () {
    expect(sanitizeFileName('a/b:c*?"<>|.jpg'), 'a_b_c______.jpg');
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
