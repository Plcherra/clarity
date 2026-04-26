import 'dart:convert';

import 'package:file_picker/file_picker.dart';

/// Web / non-IO: bytes only.
Future<String> readPickedFileContents(PlatformFile file) async {
  final b = file.bytes;
  if (b == null) {
    throw const FormatException('Could not read CSV data from this picker.');
  }
  return utf8.decode(b, allowMalformed: true);
}

