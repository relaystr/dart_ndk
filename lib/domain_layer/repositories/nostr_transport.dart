import 'dart:async';

abstract class NostrTransport {
  late Future<void> ready;
  Future<void> close();
  void send(dynamic data);
  StreamSubscription listen(
    void Function(dynamic) onData, {
    Function? onError,
    void Function()? onDone,
  });
}
