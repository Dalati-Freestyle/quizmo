import 'package:shelf/shelf.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

Handler createSocketUpgradeHandler(
  void Function(WebSocketChannel, String?) onConnected,
) => webSocketHandler(onConnected);
