import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:fc_native_video_thumbnail/fc_native_video_thumbnail.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';
import 'package:video_player/video_player.dart';

part 'app/gallery_server_app.dart';
part 'features/gallery/gallery_view_mode.dart';
part 'features/gallery/home_page.dart';
part 'features/gallery/widgets/media_preview_tile.dart';
part 'features/viewer/media_viewer_page.dart';
part 'features/viewer/media_page.dart';
part 'features/viewer/pdf_file_viewer.dart';
part 'features/viewer/video_file_player.dart';
part 'models/directory_cache_entry.dart';
part 'models/media_metadata.dart';
part 'models/media_preview.dart';
part 'services/media_preview_service.dart';
part 'services/upload_server_service.dart';
part 'utils/byte_utils.dart';
part 'utils/file_utils.dart';
part 'utils/media_type_utils.dart';
part 'utils/subtitle_utils.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const GalleryServerApp());
}
