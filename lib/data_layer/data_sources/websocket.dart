import 'dart:async';

import 'package:web_socket_channel/web_socket_channel.dart';

class WebsocketDS {
  final WebSocketChannel webSocketChannel;

  WebsocketDS(this.webSocketChannel);

  StreamSubscription<dynamic> listen(
    void Function(dynamic) onData, {
    Function? onError,
    void Function()? onDone,
  }) {
    return webSocketChannel.stream
        .listen(onData, onDone: onDone, onError: onError);
  }

  void send(dynamic data) {
    return webSocketChannel.sink.add(data);
  }

  Future<void> ready() {
    return webSocketChannel.ready;
  }

  Future<void> close() {
    return webSocketChannel.sink.close();
  }
}
