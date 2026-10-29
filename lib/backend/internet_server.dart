import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'handlers/static_handlers.dart';
import 'web_client_bundle.dart';

final class _Room {
  _Room(this.host);
  final WebSocketChannel host;
  final guests = <String, WebSocketChannel>{};
  final subscriptions = <StreamSubscription<dynamic>>[];
  final created = DateTime.now();
  DateTime heartbeat = DateTime.now();
  int nextGuest = 0;
}

/// Same-origin room relay. The dedicated host socket is the room capability:
/// guests cannot acquire it or address another guest's identity.
final class InternetServer {
  InternetServer({
    required this.publicOrigin,
    required this.webClient,
    this.maxRooms = 128,
    this.maxGuests = 128,
    this.roomLifetime = const Duration(hours: 12),
  });

  final Uri publicOrigin;
  final WebClientBundle webClient;
  final int maxRooms;
  final int maxGuests;
  final Duration roomLifetime;
  final _rooms = <String, _Room>{};
  HttpServer? _server;
  Timer? _reaper;
  int _pendingHosts = 0;
  int _httpCount = 0;
  DateTime _httpWindow = DateTime.now();
  final _upgradeWindows = <String, ({DateTime start, int hosts, int guests})>{};

  bool _allowUpgrade(Request request, {required bool host}) {
    // Deliberately ignore forwarded IP headers: accepting an untrusted one
    // would let clients bypass quotas. A proxy should enforce per-user limits.
    final peer =
        request.context['shelf.io.connection_info'] as HttpConnectionInfo?;
    final address = peer?.remoteAddress.address ?? 'unknown';
    final now = DateTime.now();
    var window = _upgradeWindows[address];
    if (window == null ||
        now.difference(window.start) >= const Duration(minutes: 1)) {
      if (_upgradeWindows.length >= 4096) {
        _upgradeWindows.removeWhere(
          (_, value) =>
              now.difference(value.start) >= const Duration(minutes: 1),
        );
        if (!_upgradeWindows.containsKey(address) &&
            _upgradeWindows.length >= 4096) {
          return false;
        }
      }
      window = (start: now, hosts: 0, guests: 0);
    }
    if (host && window.hosts >= 20 || !host && window.guests >= 300) {
      return false;
    }
    _upgradeWindows[address] = (
      start: window.start,
      hosts: window.hosts + (host ? 1 : 0),
      guests: window.guests + (host ? 0 : 1),
    );
    return true;
  }

  int get roomCount => _rooms.length;

  Future<int> start({int port = 8080, String address = '127.0.0.1'}) async {
    if (!['https', 'http'].contains(publicOrigin.scheme) ||
        publicOrigin.userInfo.isNotEmpty ||
        publicOrigin.path.isNotEmpty && publicOrigin.path != '/' ||
        publicOrigin.hasQuery ||
        publicOrigin.hasFragment ||
        publicOrigin.host.isEmpty ||
        (publicOrigin.scheme == 'http' &&
            !['localhost', '127.0.0.1'].contains(publicOrigin.host))) {
      throw ArgumentError(
        'PUBLIC_ORIGIN must be an HTTPS origin (HTTP only on localhost).',
      );
    }
    if (await webClient.prepare() == 0 ||
        await webClient.read('index.html') == null) {
      throw StateError(
        'Missing web build. Run dart run tool/bundle_web_client.dart first.',
      );
    }
    final static = createWebClientHandler(webClient);
    _server = await shelf_io.serve(
      (request) async {
        final now = DateTime.now();
        if (now.difference(_httpWindow) >= const Duration(seconds: 1)) {
          _httpWindow = now;
          _httpCount = 0;
        }
        if (++_httpCount > 1000) {
          return Response(429, headers: {'retry-after': '1'});
        }
        final origin = request.headers['origin'];
        if (origin != null && origin != publicOrigin.origin) {
          return Response.forbidden('Origin rejected');
        }
        Response response;
        final path = request.url.path;
        if (path == 'api/health' && request.method == 'GET') {
          response = Response.ok(
            '{"service":"quizmo-relay"}',
            headers: {'content-type': 'application/json'},
          );
        } else if (path == 'relay/host' && request.method == 'GET') {
          if (origin != publicOrigin.origin) {
            return Response.forbidden('Origin required');
          }
          if (_rooms.length + _pendingHosts >= maxRooms) return Response(503);
          if (!_allowUpgrade(request, host: true)) {
            return Response(429, headers: {'retry-after': '60'});
          }
          _pendingHosts++;
          try {
            response = await webSocketHandler(
              (channel, _) => _hostConnected(channel),
            )(request);
          } finally {
            _pendingHosts--;
          }
        } else if (request.url.pathSegments case ['rooms', final id, 'status']
            when request.method == 'GET') {
          response = Response(
            _rooms.containsKey(id) ? 200 : 410,
            body: '{"service":"quizmo-room","open":${_rooms.containsKey(id)}}',
            headers: {'content-type': 'application/json'},
          );
        } else if (request.url.pathSegments case ['rooms', final id, 'ws']
            when request.method == 'GET') {
          final room = _rooms[id];
          if (room == null) return Response.notFound('Room unavailable');
          if (room.guests.length >= maxGuests) return Response(503);
          if (!_allowUpgrade(request, host: false)) {
            return Response(429, headers: {'retry-after': '60'});
          }
          response = await webSocketHandler(
            (channel, _) => _guestConnected(id, room, channel),
          )(request);
        } else if (path.startsWith('api/') ||
            path.startsWith('relay/') ||
            path.endsWith('/ws')) {
          response = Response.notFound('Not found');
        } else {
          response = await static(request);
        }
        return response.change(
          headers: {
            'x-content-type-options': 'nosniff',
            'referrer-policy': 'no-referrer',
            'x-frame-options': 'DENY',
            'permissions-policy': 'camera=(), microphone=(), geolocation=()',
            'cross-origin-resource-policy': 'same-origin',
            if (path == 'index.html' ||
                path.isEmpty ||
                path.startsWith('rooms/'))
              'cache-control': 'no-store',
          },
        );
      },
      address,
      port,
    );
    _reaper = Timer.periodic(const Duration(seconds: 15), (_) {
      final now = DateTime.now();
      for (final entry in _rooms.entries.toList()) {
        if (now.difference(entry.value.heartbeat) >
                const Duration(seconds: 60) ||
            now.difference(entry.value.created) > roomLifetime) {
          unawaited(_closeRoom(entry.key));
        }
      }
    });
    return _server!.port;
  }

  String _id() => base64UrlEncode(
    List<int>.generate(24, (_) => Random.secure().nextInt(256)),
  ).replaceAll('=', '');
  void _send(WebSocketChannel channel, Map<String, Object?> data) =>
      channel.sink.add(jsonEncode(data));

  void _hostConnected(WebSocketChannel host) {
    if (_rooms.length >= maxRooms) {
      host.sink.close(3013);
      return;
    }
    final id = _id();
    final room = _Room(host);
    _rooms[id] = room;
    _send(host, {'type': 'room', 'room': id});
    int frames = 0;
    var window = DateTime.now();
    room.subscriptions.add(
      host.stream.listen(
        (dynamic frame) {
          if (DateTime.now().difference(window) >= const Duration(seconds: 1)) {
            frames = 0;
            window = DateTime.now();
          }
          if (frame is! String ||
              frame.length > 64 * 1024 * 1024 ||
              ++frames > 2048) {
            unawaited(_closeRoom(id));
            return;
          }
          try {
            final json = jsonDecode(frame);
            switch (json) {
              case {'type': 'ping'}:
                room.heartbeat = DateTime.now();
                _send(host, {'type': 'pong'});
              case {
                'type': 'frame',
                'id': final String guest,
                'data': final String data,
              }:
                room.guests[guest]?.sink.add(data);
              case {'type': 'close', 'id': final String guest}:
                room.guests[guest]?.sink.close(1000);
              default:
                unawaited(_closeRoom(id));
            }
          } on Object {
            unawaited(_closeRoom(id));
          }
        },
        onDone: () => unawaited(_closeRoom(id)),
        onError: (Object _) => unawaited(_closeRoom(id)),
      ),
    );
  }

  void _guestConnected(String roomId, _Room room, WebSocketChannel channel) {
    if (_rooms[roomId] != room || room.guests.length >= maxGuests) {
      channel.sink.close(3013);
      return;
    }
    final id = '${room.nextGuest++}';
    room.guests[id] = channel;
    _send(room.host, {'type': 'open', 'id': id});
    var frames = 0;
    var window = DateTime.now();
    void disconnected() {
      if (room.guests.remove(id) != null && _rooms[roomId] == room) {
        _send(room.host, {'type': 'close', 'id': id});
      }
    }

    late final StreamSubscription<dynamic> subscription;
    subscription = channel.stream.listen(
      (dynamic frame) {
        if (DateTime.now().difference(window) >= const Duration(seconds: 1)) {
          frames = 0;
          window = DateTime.now();
        }
        if (frame is! String ||
            frame.length > 65536 ||
            utf8.encode(frame).length > 65536 ||
            ++frames > 60) {
          channel.sink.close(3008, 'Message limit');
          return;
        }
        // Never interpret guest envelopes as relay control messages.
        _send(room.host, {'type': 'frame', 'id': id, 'data': frame});
      },
      onDone: () {
        disconnected();
        room.subscriptions.remove(subscription);
      },
      onError: (Object _) {
        disconnected();
        channel.sink.close();
      },
    );
    room.subscriptions.add(subscription);
  }

  Future<void> _closeRoom(String id) async {
    final room = _rooms.remove(id);
    if (room == null) return;
    for (final subscription in room.subscriptions.toList()) {
      await subscription.cancel();
    }
    for (final guest in room.guests.values) {
      await guest.sink.close(3001, 'Host disconnected');
    }
    await room.host.sink.close(3001);
  }

  Future<void> close() async {
    _reaper?.cancel();
    for (final id in _rooms.keys.toList()) {
      await _closeRoom(id);
    }
    await _server?.close(force: true);
    _server = null;
    _upgradeWindows.clear();
  }
}
