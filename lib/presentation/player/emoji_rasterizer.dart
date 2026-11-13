/// Turns emoji into PNG images for the protocol PDF.
///
/// The embedded PDF fonts have no emoji glyphs. In the browser the system's
/// emoji font is always available, even without internet, so the web player
/// draws each emoji on an HTML canvas. Other platforms return `null` and the
/// PDF keeps the plain characters.
library;

export 'emoji_rasterizer_stub.dart'
    if (dart.library.js_interop) 'emoji_rasterizer_web.dart';
