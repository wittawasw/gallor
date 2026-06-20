part of '../main.dart';

Future<void> handleHttpRequest(
  HttpRequest req,
  Directory uploadDir,
  Future<void> Function(List<File> files) onUploaded,
) async {
  req.response.headers.set('Access-Control-Allow-Origin', '*');
  if (req.method == 'GET') {
    req.response.headers.contentType = ContentType.html;
    req.response.write(uploadPage(uploadDir.path));
    await req.response.close();
    return;
  }

  if (req.method == 'POST' && req.uri.path == '/upload') {
    final contentType = req.headers.contentType;
    final boundary = contentType?.parameters['boundary'];
    if (boundary == null) {
      req.response.statusCode = 400;
      req.response.write('Missing multipart boundary');
      await req.response.close();
      return;
    }

    final bytes = await collectBytes(req);
    final saved = await parseAndSaveMultipart(bytes, boundary, uploadDir);
    await onUploaded(saved);
    req.response.headers.contentType = ContentType.html;
    req.response.write(
      '<p>Uploaded ${saved.length} file(s).</p><p><a href="/">Back</a></p>',
    );
    await req.response.close();
    return;
  }

  req.response.statusCode = 404;
  req.response.write('Not found');
  await req.response.close();
}

String uploadPage(String path) =>
    '''
<!doctype html>
<html>
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Upload</title></head>
<body style="font-family:sans-serif;padding:24px">
<h3>Upload to phone</h3>
<p>Directory: ${htmlEscape.convert(path)}</p>
<form method="post" action="/upload" enctype="multipart/form-data">
<input type="file" name="files" multiple accept="image/*,video/*,application/pdf,.pdf"><br><br>
<button type="submit">Upload</button>
</form>
</body>
</html>
''';

Future<Uint8List> collectBytes(Stream<List<int>> stream) async {
  final builder = BytesBuilder(copy: false);
  await for (final chunk in stream) {
    builder.add(chunk);
  }
  return builder.takeBytes();
}

Future<List<File>> parseAndSaveMultipart(
  Uint8List body,
  String boundary,
  Directory dir,
) async {
  final marker = ascii.encode('--$boundary');
  final parts = splitBytes(body, marker);
  final saved = <File>[];
  for (final part in parts) {
    if (part.length < 10) continue;
    final headerEnd = indexOfBytes(part, Uint8List.fromList([13, 10, 13, 10]));
    if (headerEnd < 0) continue;

    final header = latin1.decode(
      part.sublist(0, headerEnd),
      allowInvalid: true,
    );
    final rawName = multipartFileName(header);
    if (rawName == null || rawName.isEmpty) continue;

    var data = part.sublist(headerEnd + 4);
    while (data.isNotEmpty &&
        (data.last == 10 || data.last == 13 || data.last == 45)) {
      data = data.sublist(0, data.length - 1);
    }
    if (data.isEmpty) continue;

    final filename = uniqueFileName(dir, sanitizeFileName(rawName));
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(data, flush: true);
    saved.add(file);
  }
  return saved;
}

String? multipartFileName(String header) {
  final encodedMatch = RegExp(
    r"filename\*=UTF-8''([^;\r\n]+)",
    caseSensitive: false,
  ).firstMatch(header);
  if (encodedMatch != null) {
    try {
      return Uri.decodeComponent(encodedMatch.group(1)!);
    } on FormatException {
      // Fall back to the regular filename parameter.
    }
  }

  final filenameMatch = RegExp(r'filename="([^"]*)"').firstMatch(header);
  final filename = filenameMatch?.group(1);
  if (filename == null) return null;

  try {
    return utf8.decode(filename.codeUnits);
  } on FormatException {
    return filename;
  }
}

List<Uint8List> splitBytes(Uint8List data, List<int> marker) {
  final result = <Uint8List>[];
  var start = 0;
  while (true) {
    final idx = indexOfBytes(data, Uint8List.fromList(marker), start);
    if (idx < 0) {
      if (start < data.length) result.add(data.sublist(start));
      break;
    }
    if (idx > start) result.add(data.sublist(start, idx));
    start = idx + marker.length;
  }
  return result;
}

Future<String?> getLocalIp() async {
  final interfaces = await NetworkInterface.list(
    type: InternetAddressType.IPv4,
    includeLoopback: false,
  );
  for (final i in interfaces) {
    for (final a in i.addresses) {
      if (a.address.startsWith('192.168.') ||
          a.address.startsWith('10.') ||
          a.address.startsWith('172.')) {
        return a.address;
      }
    }
  }
  if (interfaces.isNotEmpty && interfaces.first.addresses.isNotEmpty) {
    return interfaces.first.addresses.first.address;
  }
  return null;
}
