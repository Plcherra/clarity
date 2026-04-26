import 'package:file_picker/file_picker.dart';

import 'file_reader_impl.dart'
    if (dart.library.io) 'file_reader_impl_io.dart'
    as impl;

Future<String> readPickedFileContents(PlatformFile file) =>
    impl.readPickedFileContents(file);

