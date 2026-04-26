import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';

Future<String> readPickedFileContents(PlatformFile file) async {
  if (file.bytes != null) {
    return utf8.decode(file.bytes!, allowMalformed: true);
  }
  final path = file.path;
  if (path != null) {
    return File(path).readAsString(encoding: utf8);
  }
  throw const FormatException('Could not read file.');
}

