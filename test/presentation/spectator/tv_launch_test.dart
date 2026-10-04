/// Launch URL detection of the TV screen.
library;

import 'package:flutter/material.dart' show Brightness;
import 'package:flutter_test/flutter_test.dart';
import 'package:quizmo/presentation/spectator/tv_launch.dart';

void main() {
  group('isTvLaunchUri', () {
    test('accepts the path, hash route and query spellings', () {
      for (final url in [
        'http://192.168.1.42:8080/tv',
        'http://192.168.1.42:8080/tv/',
        'http://192.168.1.42:8080/#/tv',
        'http://192.168.1.42:8080/?view=tv',
        'http://192.168.1.42:8080/tv?theme=light',
      ]) {
        expect(isTvLaunchUri(Uri.parse(url)), isTrue, reason: url);
      }
    });

    test('keeps the normal player and host entry points untouched', () {
      for (final url in [
        'http://192.168.1.42:8080/',
        'http://192.168.1.42:8080/join',
        'http://192.168.1.42:8080/#/',
        'http://192.168.1.42:8080/?host=tv',
        'http://192.168.1.42:8080/tvs',
      ]) {
        expect(isTvLaunchUri(Uri.parse(url)), isFalse, reason: url);
      }
    });
  });

  test('tvBrightnessFor defaults to dark and honours ?theme=light', () {
    expect(tvBrightnessFor(Uri.parse('http://h/tv')), Brightness.dark);
    expect(
      tvBrightnessFor(Uri.parse('http://h/tv?theme=light')),
      Brightness.light,
    );
  });
}

