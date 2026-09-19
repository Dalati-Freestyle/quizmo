/// Platform-aware file transfer for standalone quiz documents.
library;

export 'quiz_file_transfer_stub.dart'
    if (dart.library.html) 'quiz_file_transfer_web.dart'
    if (dart.library.io) 'quiz_file_transfer_io.dart';
