import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void mockLanDiscoveryUnavailable() {
  const channel = MethodChannel('com.haberey/nsd');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
    channel,
    (_) async => throw PlatformException(code: 'operationNotSupported'),
  );
  addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
}
