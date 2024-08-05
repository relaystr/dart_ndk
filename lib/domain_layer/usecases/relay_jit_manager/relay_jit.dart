import 'dart:async';
import 'dart:convert';

import 'package:dart_ndk/shared/logger/logger.dart';
import 'package:dart_ndk/shared/nips/nip01/client_msg.dart';
import 'package:dart_ndk/domain_layer/entities/nip_01_event.dart';
import 'package:dart_ndk/domain_layer/entities/filter.dart';
import 'package:dart_ndk/domain_layer/entities/read_write_marker.dart';
import 'package:dart_ndk/domain_layer/entities/relay.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../../presentation_layer/request_state.dart';
import '../../entities/connection_source.dart';
import '../../../shared/helpers/relay_helper.dart';
import '../jit_engine.dart';

///
/// url is a unique identifier for the relay
/// therefore it gets cleaned (e.g. remove / at the end wss://myrelay.com/ => wss://myrelay.com)
/// throws an exception if the url is invalid
///
class RelayJit extends Relay with Logger {
  /// used to lookup if this relay is suitable for a given request
  List<RelayJitAssignedPubkey> assignedPubkeys = [];

  /// all active subscriptions on this relay, id is the subscription id
  Map<String, RelayActiveSubscription> activeSubscriptions = {};

  /// gets incremented on every touch => search if it has a pubkey assigned
  int touched = 1;

  /// gets incremented when there is a pubkey match
  int touchUseful = 0;

  double get relayUsefulness => touchUseful / touched;

  WebSocketChannel? _channel;

  ConnectionSource connectionSource = ConnectionSource.UNKNOWN;

  Function(Nip01Event, RequestState) onMessage;

  RelayJit({
    required String url,
    required this.onMessage,
  }) : super(url) {
    String? cleanUrl = cleanRelayUrl(url);
    if (cleanUrl == null) {
      throw Exception("invalid url $url => $cleanUrl");
    }
    super.url = cleanUrl;
  }

  /// returns true if the connection was successful
  Future<bool> connect({required ConnectionSource connectionSource}) async {
    if (_channel != null) {
      Logger.log.w("Relay already connected");
      return Future.value(true);
    }
    this.connectionSource = connectionSource;
    tryingToConnect();

    _channel = WebSocketChannel.connect(Uri.parse(url));

    // ready check
    bool r = await isReady();
    if (!r) {
      Logger.log.w("Relay not ready");
      failedToConnect();
      return false;
    }

    _listen();
    Logger.log.d("🔗 Relay connected: $url");
    succeededToConnect();
    return true;
  }

  _listen() {
    _channel!.stream.listen((event) {
      Logger.log.t("📥 Received message on $url: $event");
      if (event is! String) {
        Logger.log.w("Received message is not a string: $event");
        return;
      }
      List<dynamic> eventJson = jsonDecode(event);

      switch (eventJson[0]) {
        case 'EVENT':
          _handleIncomingEvent(eventJson);
          break;
        case 'OK':
          //["OK", <event_id>, <true|false>, <message>]
          Logger.log.i("OK received: $eventJson");
          Logger.log.f("OK not implemented! ");
          break;
        case 'EOSE':
          //["EOSE", <subscription_id>]
          Logger.log.t("⏹ EOSE received, $eventJson");
          _handleIncomingEose(eventJson);
          break;

        case 'CLOSED':
          //["CLOSED", <subscription_id>, <message>]
          Logger.log.i("CLOSED received: $eventJson");
          Logger.log.f("CLOSED not implemented!");
          break;

        case 'NOTICE':
          //["NOTICE", <message>]
          Logger.log.i("NOTICE received: $eventJson");
          Logger.log.f("NOTICE not implemented!");
          break;

        default:
          Logger.log.w("Unknown message type: ${eventJson[0]}: $eventJson");
      }
    });
  }

  void _handleIncomingEvent(List<dynamic> eventJson) {
    Nip01Event msg = Nip01Event.fromJson(eventJson[2]);
    String msgId = eventJson[1];
    if (hasActiveSubscription(msgId)) {
      msg.sources.add(url);

      onMessage(msg, activeSubscriptions[msgId]!.requestState);
    }
  }

  void _handleIncomingEose(List<dynamic> eventJson) {
    String eoseId = eventJson[1];
    if (!hasActiveSubscription(eoseId)) {
      return;
    }
    RelayActiveSubscription sub = activeSubscriptions[eoseId]!;
    sub.onEose();

    final requestState = activeSubscriptions[eoseId]!.requestState;
    // channel back so the request can be closed
    JitEngine.onEoseReceivedFromRelay(requestState);
    if (!sub.requestState.requestConfig.closeOnEOSE) {
      return;
    }

    closeSubscription(eoseId);
  }

  Future<void> closeSubscription(String id) async {
    if (!hasActiveSubscription(id)) {
      return;
    }
    activeSubscriptions.remove(id);
    ClientMsg closeMsg = ClientMsg("CLOSE", id: id, filters: []);
    await send(closeMsg);
  }

  Future<dynamic> disconnect() {
    if (_channel == null) {
      return Future.value(false);
    }
    return _channel!.sink.close();
  }

  Future<bool> isReady() async {
    if (_channel == null) {
      return false;
    }
    try {
      // usually connection errors are thrown here
      await _channel!.ready;
    } catch (e) {
      Logger.log.e("Error on ready check: $e");
      return false;
    }

    return _channel!.closeCode == null;
  }

  Future<void> send(ClientMsg msg) async {
    bool rdy = await isReady();
    if (!rdy) {
      throw Exception("Websocket not ready, unable to send message $url");
    }

    dynamic msgToSend = msg.toJson();
    String encodedMsg = jsonEncode(msgToSend);
    _channel!.sink.add(encodedMsg);
    Logger.log.d("🔼 send message to $url: $msgToSend");
    // link relay to request
  }

  // check if active relay subscriptions does already exist
  bool hasActiveSubscription(String id) {
    return activeSubscriptions.containsKey(id);
  }

  void addPubkeysToAssignedPubkeys(
      List<String> pubkeys, ReadWriteMarker direction) {
    for (var pubkey in pubkeys) {
      assignedPubkeys.add(RelayJitAssignedPubkey(pubkey, direction));
    }
  }
}

class RelayJitAssignedPubkey {
  final String pubkey;
  final ReadWriteMarker direction;

  RelayJitAssignedPubkey(this.pubkey, this.direction);
}

class RelayActiveSubscription {
  final String id; // id of the original request
  final RequestState requestState;
  List<Filter> filters; // list of split filters

  bool get closeOnEose => requestState.requestConfig.closeOnEOSE;
  final Completer<void> _eoseReceived = Completer();

  /// completes when EOSE is received
  Future<void> get eoseReceived => _eoseReceived.future;

  void onEose() {
    if (_eoseReceived.isCompleted) {
      return;
    }
    _eoseReceived.complete();
  }

  RelayActiveSubscription(this.id, this.filters, this.requestState);
}
