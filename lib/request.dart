import 'dart:async';

import 'package:dart_ndk/dart_ndk.dart';
import 'package:dart_ndk/nips/nip01/event.dart';

import 'nips/nip01/filter.dart';

class RelayRequest {
  String url;
  bool receivedEOSE=false;
  List<Filter> filters;

  RelayRequest(this.url, this.filters);
}

// Requests made to several relays, identified by same id
class NostrRequest {
  String id;

  Map<String, RelayRequest> requests = {};

  StreamController<Nip01Event> controller = StreamController<Nip01Event>();
  bool closeOnEOSE;
  int? timeout;
  Function(NostrRequest)? onTimeout;

  Stream<Nip01Event> get stream => timeout != null
      ? controller.stream.timeout(Duration(seconds: timeout!), onTimeout: (sink) {
          if (onTimeout != null) {
            onTimeout!.call(this);
          }
        })
      : controller.stream;

  NostrRequest.query(
    this.id, {
    this.closeOnEOSE = true,
    this.timeout = RelayManager.DEFAULT_STREAM_IDLE_TIMEOUT + 1,
    this.onTimeout,
  });

  NostrRequest.subscription(this.id, {this.closeOnEOSE = false});


  bool get didAllRequestsReceivedEOSE => !requests.values.any((element) => !element.receivedEOSE);
  bool get shouldClose => closeOnEOSE && (requests.isEmpty || didAllRequestsReceivedEOSE);

  void addRequest(String url, List<Filter> filters) {
    if (!requests.containsKey(url)) {
      requests[url] = RelayRequest(url, filters);
    }
  }
}
