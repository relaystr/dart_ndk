import 'dart:async';

import 'package:dart_ndk/logger/logger.dart';
import 'package:dart_ndk/nips/nip01/event.dart';
import 'package:dart_ndk/nips/nip01/event_verifier.dart';
import 'package:dart_ndk/nips/nip01/filter.dart';
import 'package:dart_ndk/relay_jit_manager/relay_jit.dart';
import 'package:dart_ndk/relay_jit_manager/relay_jit_config.dart';

///
///! currently a partial copy of request.dart, need to discuss how to resolve this
///

class NostrRequestJit with Logger {
  String id;
  EventVerifier eventVerifier;

  List<Filter> filters;

  StreamController<Nip01Event> responseController =
      StreamController<Nip01Event>();

  Stream<Nip01Event> get _responseStream =>
      responseController.stream.asBroadcastStream();

  /// If true, the request will be closed when all requests received EOSE
  bool closeOnEOSE;

  ///
  int? timeout;

  final int desiredCoverage;

  // string is the relay url
  Map<String, RelayJit> _activeRelaySubscriptions = {};

  Function(NostrRequestJit)? onTimeout;

  Stream<Nip01Event> get responseStream => timeout != null
      ? _responseStream.timeout(Duration(seconds: timeout!), onTimeout: (sink) {
          if (onTimeout != null) {
            onTimeout!.call(this);
          }
        })
      : _responseStream;

  Future<List<Nip01Event>> get responseList async {
    if (!closeOnEOSE) {
      throw Exception("Cannot get responseList for a subscription");
    }

    if (timeout != null) {
      return _responseStream
          .timeout(Duration(seconds: timeout!), onTimeout: (sink) {
            if (onTimeout != null) {
              onTimeout!.call(this);
            }
          })
          .asBroadcastStream()
          .toList();
    }

    return responseController.stream.asBroadcastStream().toList();
  }

  NostrRequestJit.query(
    this.id, {
    required this.eventVerifier,
    required this.filters,
    this.closeOnEOSE = true,
    this.timeout = RelayJitConfig.DEFAULT_STREAM_IDLE_TIMEOUT,
    this.desiredCoverage = 2,
    this.onTimeout,
  });

  NostrRequestJit.subscription(
    this.id, {
    required this.eventVerifier,
    required this.filters,
    this.closeOnEOSE = false,
    this.desiredCoverage = 2,
  });

  /// verify event and add to response stream
  void onMessage(Nip01Event event) async {
    // verify event
    bool validSig = await eventVerifier.verify(event);

    if (!validSig) {
      Logger.log.w("🔑⛔ Invalid signature on event: $event");
      return;
    }
    event.validSig = validSig;

    // add to response stream
    responseController.add(event);
  }

  void onEoseReceivedFromRelay(RelayJit relay) async {
    // check if all subscriptions received EOSE (async) at the current time

    for (var sub in _activeRelaySubscriptions.values) {
      await sub.activeSubscriptions[id]?.eoseReceived;
    }
    responseController.close();
  }

  void addRelayActiveSubscription(RelayJit relay) {
    _activeRelaySubscriptions[relay.url] = relay;
  }
}
