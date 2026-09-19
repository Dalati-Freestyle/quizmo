# Bundled web player

`bundle.zip` in this folder holds the Flutter Web build that the embedded host
serves at `/`, so a guest only needs the LAN address shown on the quizmaster
dashboard — no app install, no separate web server.

Regenerate it whenever the player UI changes:

```console
dart run tool/bundle_web_client.dart
```

Then rebuild the host app (`flutter build apk`, `flutter run`, …) so the updated
archive is embedded.

The zip is a build artifact and is not tracked in version control. When it is
missing the host still starts — it just serves a placeholder page at `/` and
logs a warning.

