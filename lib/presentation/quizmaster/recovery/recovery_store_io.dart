import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/data/session_recovery.dart';
import '../../../core/data/session_recovery_store_io.dart';

Future<SessionRecoveryStore> createRecoveryStore() async =>
    FileSessionRecoveryStore(
      Directory(
        p.join((await getApplicationSupportDirectory()).path, 'recovery'),
      ),
    );
