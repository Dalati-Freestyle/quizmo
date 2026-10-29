import '../../../core/data/session_recovery.dart';

Future<SessionRecoveryStore> createRecoveryStore() => Future.error(
  UnsupportedError('Recovery storage is unavailable on this platform.'),
);
