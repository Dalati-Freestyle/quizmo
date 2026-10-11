import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/core/net/session_uri.dart';

void main() {
  test(
    'internet TV URL preserves HTTPS, port and room but removes view arguments',
    () {
      final launch = Uri.parse(
        'https://quiz.example.com:8443/rooms/secret/tv?theme=light#/tv',
      );
      expect(
        sessionUri(launch).toString(),
        'https://quiz.example.com:8443/rooms/secret',
      );
      expect(
        sessionSocketUri(launch).toString(),
        'wss://quiz.example.com:8443/rooms/secret/ws',
      );
    },
  );
  test('LAN spectator uses the same origin and root websocket', () {
    final launch = Uri.parse('http://192.168.1.2:8080/tv');
    expect(sessionUri(launch).toString(), 'http://192.168.1.2:8080');
    expect(sessionSocketUri(launch).toString(), 'ws://192.168.1.2:8080/ws');
    expect(isInternetSession(launch), isFalse);
  });
}
