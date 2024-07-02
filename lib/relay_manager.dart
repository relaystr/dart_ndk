// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:core';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:dart_ndk/cache_manager.dart';
import 'package:dart_ndk/mem_cache_manager.dart';
import 'package:dart_ndk/models/pubkey_mapping.dart';
import 'package:dart_ndk/nips/nip01/event_signer.dart';
import 'package:dart_ndk/nips/nip01/helpers.dart';
import 'package:dart_ndk/nips/nip02/contact_list.dart';
import 'package:dart_ndk/nips/nip11/relay_info.dart';
import 'package:dart_ndk/nips/nip65/read_write_marker.dart';
import 'package:dart_ndk/read_write.dart';
import 'package:dart_ndk/relay.dart';
import 'package:dart_ndk/request.dart';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'event_filter.dart';
import 'models/relay_set.dart';
import 'models/user_relay_list.dart';
import 'nips/nip01/acinq_event_verifier.dart';
import 'nips/nip01/event.dart';
import 'nips/nip01/event_verifier.dart';
import 'nips/nip01/filter.dart';
import 'nips/nip65/nip65.dart';

class RelayManager {
  static const int DEFAULT_WEB_SOCKET_CONNECT_TIMEOUT = 3;
  static const int DEFAULT_STREAM_IDLE_TIMEOUT = 5;
  static const int DEFAULT_BEST_RELAYS_MIN_COUNT = 2;
  static const int FAIL_RELAY_CONNECT_TRY_AFTER_SECONDS = 60;
  static const int WEB_SOCKET_PING_INTERVAL_SECONDS = 3;

  /// Bootstrap relays from these to start looking for NIP65/NIP03 events
  static const List<String> DEFAULT_BOOTSTRAP_RELAYS = [
    // "wss://purplepag.es",
    "wss://relay.damus.io",
    "wss://nos.lol",
    "wss://nostr.wine",
    "wss://offchain.pub",
    "wss://relay.mostr.pub"
  ];

  List<String> bootstrapRelays = DEFAULT_BOOTSTRAP_RELAYS;

  CacheManager cacheManager = MemCacheManager();

  EventVerifier eventVerifier = AcinqSecp256k1EventVerifier();

  /// Global relay registry by url
  Map<String, Relay> relays = {};

  /// Global webSocket registry by url
  Map<String, WebSocketChannel> webSockets = {};

  final Map<String,NostrRequest> nostrRequests = {};

  List<String> blockedRelays = [];

  int get blockedRelaysCount => blockedRelays.length;

  List<EventFilter> eventFilters = [];

  bool allowReconnectRelays = true;

  // HttpClient? httpClient;

  RelayManager(/*{bool? isWeb}*/) {
    // if (isWeb==null || !isWeb) {
    //   httpClient = HttpClient();
    //   httpClient!.idleTimeout = const Duration(seconds: 3600);
    //   httpClient!.connectionTimeout = const Duration(seconds: 5);
    // }
  }
  // ====================================================================================================================

  /// This will initialize the manager with bootstrap relays.
  /// If you don't give any, will use some predefined
  Future<void> connect(
      {Iterable<String> urls = DEFAULT_BOOTSTRAP_RELAYS}) async {
    bootstrapRelays = [];
    for (String url in urls) {
      String? clean = Relay.clean(url);
      if (clean != null) {
        bootstrapRelays.add(clean);
      }
    }
    if (bootstrapRelays.isEmpty) {
      bootstrapRelays = DEFAULT_BOOTSTRAP_RELAYS;
    }
    await Future.wait(urls.map((url) => reconnectRelay(url, force: true)).toList());
  }

  void send(String url, dynamic data) {
    // webSocket!.sendMessage(jsonEncode(["EVENT", event.toJson()]));
    webSockets[url]!.sink.add(data);
  }

  Future<void> closeSocket(url) async {
    return webSockets[url]?.sink.close().timeout(const Duration(seconds:3), onTimeout: () {
      print("timeout while trying to close socket $url");
    });
  }

  Future<void> closeAllSockets() async {
    try {
      await Future.wait(webSockets.keys.map((url) => closeSocket(url)));
    } catch (e) {
      print(e);
    }
  }

  bool isWebSocketOpen(String url) {
    WebSocketChannel? webSocket = webSockets[Relay.clean(url)];
    // return webSocket != null && webSocket.socketState.status == SocketStatus.connected;
    //&& webSocket.ready== WebSocket.open
    return webSocket != null  && webSocket.closeCode==null;
  }

  // bool isWebSocketConnecting(String url) {
  //   var webSocket = webSockets[Relay.clean(url)];
  //   return webSocket != null && webSocket.socketState.status == SocketStatus.connecting;
  // }

  bool isRelayConnecting(String url) {
    Relay? relay = relays[url];
    return relay != null && relay.connecting;
  }

  // Future<bool> awaitForSocketConnected(String url) async {
  //   await for (final state in webSockets[url]!.socketHandlerStateStream) {
  //     print('> $url ${state.status}');
  //     if (state.status == SocketStatus.connected) {
  //       return true;
  //     }
  //   };
  //   return false;
  // }

  /// Connect a new relay
  Future<bool> connectRelay(String dirtyUrl,
      {int connectTimeout = DEFAULT_WEB_SOCKET_CONNECT_TIMEOUT}) async {
    String? url = Relay.clean(dirtyUrl);
    if (url == null) {
      return false;
    }
    if (blockedRelays.contains(url)) {
      return false;
    }
    try {
      if (relays[url] == null) {
        relays[url] = Relay(url);
      }
      relays[url]!.tryingToConnect();
      if (url.startsWith("wss://brb.io")) {
        relays[url]!.failedToConnect();
        relays[url]!.stats.connectionErrors++;
        return false;
      }
      // var connectionOptions = SocketConnectionOptions(
      //   timeoutConnectionMs: connectTimeout*1000,
      //   skipPingMessages: true,
      //   pingRestrictionForce: true,
      //   reconnectionDelay: const Duration(seconds:5),
      // );
      // webSockets[url] = IWebSocketHandler<String, String>.createClient(
      //   url,
      //   SocketSimpleTextProcessor(),
      //   connectionOptions: connectionOptions
      // );
      final wsUrl = Uri.parse(url);
      webSockets[url] = WebSocketChannel.connect(wsUrl);
      await webSockets[url]!.ready;

      // webSockets[url] = await WebSocket.connect(url, customClient: httpClient)
      //     .timeout(Duration(seconds: connectTimeout))
      //     .catchError((error) {
      //   return Future<WebSocket>.error(error);
      // });
      // webSockets[url]!.logEventStream.listen((event) {
      //   if (event.socketLogEventType != SocketLogEventType.fromServerMessage) {
      //     print("${event.socketLogEventType.value} -> ${event.data}");
      //   }
      // });

      startListeningToSocket(url);
      // webSockets[url]!.socketHandlerStateStream.listen((stateEvent) {
      //   print('> $url ${stateEvent.status}');
      // });

      // bool connected = await webSockets[url]!.connect();

      // await for (final state in webSockets[url]!.socketHandlerStateStream) {
      //   print('> $url ${state.status}');
      //   if (state.status == SocketStatus.connected) {
      //     break;
      //   }
      // };

      // if (connected) {
      developer.log("connected to relay: $url");
      relays[url]!.succeededToConnect();
      relays[url]!.stats.connections++;
      getRelayInfo(url);
      return true;
      // }
    } catch (e) {
      print("!! could not connect to $url -> $e");
      webSockets.remove(url);
    }
    relays[url]!.failedToConnect();
    relays[url]!.stats.connectionErrors++;
    return false;
  }

  void startListeningToSocket(String url) {
    webSockets[url]!.stream.asBroadcastStream().listen((message) {
      _handleIncommingMessage(message, url);
    }
        , onError: (error) async {
          /// todo: handle this better, should clean subscription stuff
          relays[url]!.stats.connectionErrors++;
          print("onError $url on listen $error");
          throw Exception("Error in socket");
        }, onDone: () {
          if (allowReconnectRelays) {
            print("onDone $url on listen (close: ${webSockets[url]!.closeCode} ${webSockets[url]!.closeReason}), trying to reconnect");
            if (isWebSocketOpen(url)) {
              print("closing $url webSocket");
              webSockets[url]!.sink.close();
              print("closed $url. Reconnecting");
              reconnectRelay(url);
            } else {
              reconnectRelay(url);
            }
          }
          /// todo: handle this better, should clean subscription stuff
        });
    // webSockets[url]!.incomingMessagesStream.listen((message) {
    //   _handleIncommingMessage(message, url);
    // }
    // , onError: (error) async {
    //   /// todo: handle this better, should clean subscription stuff
    //   print("onError $url on listen $error");
    //   throw Exception("Error in socket");
    // }, onDone: () {
    //   print("onDone $url on listen, trying to reconnect");
    //   relays[url]!.stats.connectionErrors++;
    //   if (isWebSocketOpen(url)) {
    //     print("closing $url webSocket");
    //     webSockets[url]!.close();
    //     print("closed $url. Reconnecting");
    //     reconnectRelay(url);
    //   } else {
    //     reconnectRelay(url);
    //   }
    //   /// todo: handle this better, should clean subscription stuff
    // });
  }

  List<Relay> getConnectedRelays(Iterable<String> urls) {
    return urls
        .where((url) => isRelayConnected(url))
        .map((url) => relays[url]!)
        .toList();
  }

  bool doRelayRequest(String id, RelayRequest request) {
    if (isWebSocketOpen(request.url) && (!blockedRelays.contains(request.url))) {
      try {
        List<dynamic> list = ["REQ", id];
        list.addAll(request.filters.map((filter) => filter.toMap()));

        // webSockets[request.url]!.sendMessage(jsonEncode(list));
        send(request.url,jsonEncode(list));

        return true;
      } catch (e) {
        print(e);
      }
    } else {
      print("COULD NOT SEND REQUEST TO ${request.url} since socket seems to be not open");

      reconnectRelay(request.url);
    }
    return false;
  }

  Future<void> broadcastEvent(Nip01Event event, Iterable<String> relays,
      EventSigner signer) async {
    await signer.sign(event);
    await Future.wait(relays.map((url) => broadcastSignedEvent(event, url)));
  }

  Future<void> broadcastSignedEvent(Nip01Event event, String url) async {
    if (isWebSocketOpen(url) && (!blockedRelays.contains(url))) {
      try {
        print("BROADCASTING to $url : kind: ${event.kind} author: ${event
            .pubKey}");
        var webSocket = webSockets[url];
        if (webSocket!=null) {
          send(url,jsonEncode(["EVENT", event.toJson()]));
        }
      } catch (e) {
        print("ERROR BROADCASTING $url -> $e");
      }
    }
  }

  // =====================================================================================

  _handleIncommingMessage(dynamic message, String url) {
    List<dynamic> eventJson = json.decode(message);

    if (eventJson[0] == 'OK') {
      //nip 20 used to notify clients if an EVENT was successful
      // log("OK: ${eventJson[1]}");
      return;
    }

    if (eventJson[0] == 'NOTICE') {
      print("!!!!!!!!!!!!!!!!!!!!!!! NOTICE from $url: ${eventJson[1]}");
      reconnectRelay(url,force: true);
      return;
    }

    if (eventJson[0] == 'EVENT') {
      var id = eventJson[1];
      if (nostrRequests[id] == null) {
        if (kDebugMode) {
          // Nip01Event event = Nip01Event.fromJson(eventJson[2]);
          // print("RECEIVED EVENT ${id} for unknown request kind: ${event.kind}");
        }
        return;
      }

      Nip01Event event = Nip01Event.fromJson(eventJson[2]);
      if (!filterEvent(event)) {
        return;
      }
      // check signature is valid
      if (!event.isIdValid) {
        if (kDebugMode) {
          print("RECEIVED $id INVALID EVENT $event");
        }
        return;
      }
      eventVerifier.verify(event).then((validSig) {
        if (validSig) {
          event.sources.add(url);
          event.validSig = true;
          if (relays[url] != null) {
            relays[url]!
                .incStatsByNewEvent(event, message
                .toString()
                .codeUnits
                .length);
          }
          NostrRequest? nostrRequest = nostrRequests[id];
          if (nostrRequest != null) {
            try {
              nostrRequest.controller.add(event);
              // if (!nostrRequest.controller.isClosed && nostrRequest.shouldClose) {
              //   nostrRequest.controller.close();
              //   nostrRequests.remove(id);
              // }
            } catch(e) {
              print("COULD NOT ADD event $event TO CONTROLLER on $url for requests ${nostrRequest.requests}");
            }
          }
        } else {
          if (kDebugMode) {
            print("INVALID EVENT SIGNATURE: $event");
          }
        }
      });
      return;
    }
    if (eventJson[0] == 'EOSE') {
      String id = eventJson[1];
      NostrRequest? nostrRequest = nostrRequests[id];
      if (nostrRequest!=null && nostrRequest.closeOnEOSE) {

        // print("RECEIVED EOSE from $url, remaining requests from :${nostrRequest.requests.keys} kind:${nostrRequest.requests.values.first.filters.first.kinds}");
        RelayRequest? request = nostrRequest.requests[url];
        if (request!=null) {
          request.receivedEOSE = true;
          nostrRequest.requests.remove(url);
          if (isWebSocketOpen(url)) {
            // webSockets[url]!.sendMessage(
            //     jsonEncode(["CLOSE", nostrRequest.id]));
            send(url,jsonEncode(["CLOSE", nostrRequest.id]));
          }
        }
        if (nostrRequest.requests.isEmpty &&
            !nostrRequest.controller.isClosed) {
          Future.delayed(Duration(seconds:(nostrRequest.timeout??5)*10), () {
            closeNostrRequest(nostrRequest);
            // nostrRequests.remove(id);
          });
        }
      }
      return;
    }
    // if (eventJson[0] == 'AUTH') {
    //   log("AUTH: ${eventJson[1]}");
    //   // nip 42 used to send authentication challenges
    //   return;
    // }
    //
    // if (eventJson[0] == 'COUNT') {
    //   log("COUNT: ${eventJson[1]}");
    //   // nip 45 used to send requested event counts to clients
    //   return;
    // }
  }

  Relay? getRelay(String url) {
    Relay? r = relays[url];
    r ??= relays[Relay.clean(url)];
    return r;
  }

  bool _doesRelaySupportNip(String url, int nip) {
    Relay? relay = relays[Relay.clean(url)];
    return relay != null && relay.supportsNip(nip);
  }
  // =====================================================================================

  Future<NostrRequest> doNostrRequest(NostrRequest nostrRequest, Filter filter,
      RelaySet relaySet,
      {bool splitRequestsByPubKeyMappings=true}) async {
    if (splitRequestsByPubKeyMappings) {
      relaySet.splitIntoRequests(filter,nostrRequest);

      print(
          "request for ${filter.authors != null
              ? filter.authors!.length
              : 0} authors with kinds: ${filter
              .kinds} made requests to ${nostrRequest.requests
              .length} relays");

      if (nostrRequest.requests.isEmpty && relaySet.fallbackToBootstrapRelays) {
        print(
            "making fallback requests to ${bootstrapRelays
                .length} bootstrap relays for ${filter.authors != null ? filter
                .authors!.length : 0} authors with kinds: ${filter.kinds}");
        for (var url in bootstrapRelays) {
          nostrRequest.addRequest(url, RelaySet.sliceFilterAuthors(filter));
        }
      }
    } else {
      for (var url in relaySet.urls) {
        nostrRequest.addRequest(url, RelaySet.sliceFilterAuthors(filter));
      }
    }
    nostrRequests[nostrRequest.id] = nostrRequest;
    Map<int?,int> kindsMap = {};
    nostrRequests.forEach((key, request) {
      int? kind;
      if (request.requests.isNotEmpty && request.requests.values.first.filters.first.kinds!=null && request.requests.values.first.filters.first.kinds!.isNotEmpty) {
        kind = request.requests.values.first.filters.first.kinds!.first;
      }
      int? count = kindsMap[kind];
      count ??= 0;
      count++;
      kindsMap[kind] = count;
    });
    print(
        "----------------NOSTR REQUESTS: ${nostrRequests.length} || $kindsMap");
    for(MapEntry<String,RelayRequest> entry in nostrRequest.requests.entries) {
      doRelayRequest(nostrRequest.id, entry.value);
    }
    return nostrRequest;
  }

  Future<NostrRequest> subscription(Filter filter, RelaySet relaySet,
      {bool splitRequestsByPubKeyMappings = true}) async {
    return doNostrRequest(
        NostrRequest.subscription(Helpers.getRandomString(10)), filter, relaySet, splitRequestsByPubKeyMappings: splitRequestsByPubKeyMappings);
  }

  Future<NostrRequest> query(Filter filter, RelaySet relaySet,
      {int idleTimeout = RelayManager.DEFAULT_STREAM_IDLE_TIMEOUT, bool splitRequestsByPubKeyMappings = true,}) async {
    return doNostrRequest(
        NostrRequest.query(Helpers.getRandomString(10), timeout: idleTimeout, onTimeout: (request) {
          closeNostrRequest(request);
        }), filter, relaySet, splitRequestsByPubKeyMappings: splitRequestsByPubKeyMappings);
  }
  Future<void> closeNostrRequest(NostrRequest request) async {
    return closeNostrRequestById(request.id);
  }

  Future<void> closeNostrRequestById(String id) async {
    NostrRequest? nostrRequest = nostrRequests[id];
    if (nostrRequest!=null) {
      for (var url in nostrRequest.requests.keys) {
        if (isWebSocketOpen(url)) {
          try {
            // webSockets[url]!.sendMessage(jsonEncode(["CLOSE", nostrRequest.id]));
            send(url,jsonEncode(["CLOSE", nostrRequest.id]));
          } catch (e) {
            print(e);
          }
        }
      }
      try {
        nostrRequest.controller.close();
      } catch (e) {
        print(e);
      }
      nostrRequests.remove(id);

      /***********************************/
      Map<int?,int> kindsMap = {};
      nostrRequests.forEach((key, request) {
        int? kind;
        if (request.requests.isNotEmpty && request.requests.values.first.filters.first.kinds!=null && request.requests.values.first.filters.first.kinds!.isNotEmpty) {
          kind = request.requests.values.first.filters.first.kinds!.first;
        }
        int? count = kindsMap[kind];
        count ??= 0;
        count++;
        kindsMap[kind] = count;
      });
      print(
          "----------------NOSTR REQUESTS CLOSE SOME: ${nostrRequests.length} || $kindsMap");
      /***********************************/
    }
  }

  Future<NostrRequest> requestRelays(Iterable<String> urls, Filter filter,
      {int timeout = DEFAULT_STREAM_IDLE_TIMEOUT, bool closeOnEOSE = true, Function()? onTimeout}) async {
    String id = Helpers.getRandomString(10);
    NostrRequest nostrRequest = closeOnEOSE?
    NostrRequest.query(id, timeout: timeout, onTimeout: (request) {
      closeNostrRequest(request);
      if (onTimeout!=null) {
        onTimeout();
      }
    }) :
    NostrRequest.subscription(id,);

    for (var url in urls) {
      nostrRequest.addRequest(url, RelaySet.sliceFilterAuthors(filter));
    }
    nostrRequests[nostrRequest.id] = nostrRequest;

    List<String> notSent = [];
    Map<int?,int> kindsMap = {};
    nostrRequests.forEach((key, request) {
      int? kind;
      if (request.requests.isNotEmpty && request.requests.values.first.filters.first.kinds!=null && request.requests.values.first.filters.first.kinds!.isNotEmpty) {
        kind = request.requests.values.first.filters.first.kinds!.first;
      }
      int? count = kindsMap[kind];
      count ??= 0;
      count++;
      kindsMap[kind] = count;
    });
    print(
        "----------------NOSTR REQUESTS: ${nostrRequests.length} || $kindsMap");
    for(MapEntry<String,RelayRequest> entry in nostrRequest.requests.entries) {
      if (!doRelayRequest(nostrRequest.id, entry.value)) {
        notSent.add(entry.key);
      }
    }
    for (var url in notSent) {
      nostrRequest.requests.remove(url);
    }

    return nostrRequest;
  }

  /// relay -> list of pubKey mappings
  Future<RelaySet> calculateRelaySet({required String name,
    required String ownerPubKey,
    required List<String> pubKeys,
    required RelayDirection direction,
    required int relayMinCountPerPubKey,
    Function(String, int, int)? onProgress}) async {
    RelaySet byScore = await _relaysByPopularity(
        name: name,
        ownerPubKey: ownerPubKey,
        pubKeys: pubKeys,
        direction: direction,
        relayMinCountPerPubKey: relayMinCountPerPubKey,
        onProgress: onProgress);

    /// try by score
    if (byScore.relaysMap.isNotEmpty) {
      return byScore;
    }

    /// if everything fails just return a map of all currently registered connected relays for each pubKeys
    return RelaySet(
        name: name,
        pubKey: ownerPubKey,
        relayMinCountPerPubkey: relayMinCountPerPubKey,
        direction: direction,
        relaysMap: _allConnectedRelays(pubKeys),
        notCoveredPubkeys: []);
  }

  Map<String, List<PubkeyMapping>> _allConnectedRelays(List<String> pubKeys) {
    Map<String, List<PubkeyMapping>> map = {};
    for (var relay in relays.keys) {
      if (isWebSocketOpen(relay)) {
        map[relay] = pubKeys
            .map((pubKey) =>
            PubkeyMapping(
                pubKey: pubKey, rwMarker: ReadWriteMarker.readWrite))
            .toList();
      }
    }
    return map;
  }

  /// - get missing relay lists for pubKeys from nip65 or nip02 (todo nip05)
  /// - construct a map of relays and pubKeys that use it in some marker direction (write for outbox feed)
  /// - sort this map by descending amount of pubKeys per relay
  /// - starting from the top relay (biggest count of pubKeys) iterate down and:
  ///   - check if relay is connected or can connect
  ///   - for each pubKey mapped for given relay check if you already have minimum amount of relay coverage (use auxiliary map to remember this)
  ///     - if not add this relay to list of best relays
  Future<RelaySet> _relaysByPopularity({required String name,
    required String ownerPubKey,
    required List<String> pubKeys,
    required RelayDirection direction,
    required int relayMinCountPerPubKey,
    Function(String stepName, int count, int total)? onProgress}) async {
    await loadMissingRelayListsFromNip65OrNip02(pubKeys,
        onProgress: onProgress);

    Map<String, Set<PubkeyMapping>> pubKeysByRelayUrl =
    await _buildPubKeysMapFromRelayLists(pubKeys, direction);

    Map<String, Set<String>> minimumRelaysCoverageByPubkey = {};
    Map<String, List<PubkeyMapping>> bestRelays = {};
    if (onProgress != null) {
      if (kDebugMode) {
        print("Calculating best relays...");
      }
      onProgress.call("Calculating best relays",
          minimumRelaysCoverageByPubkey.length, pubKeysByRelayUrl.length);
    }
    Map<String, int> notCoveredPubkeys = {};
    for (var pubKey in pubKeys) {
      notCoveredPubkeys[pubKey] = relayMinCountPerPubKey;
    }
    for (String url in pubKeysByRelayUrl.keys) {
      if (blockedRelays.contains(Relay.clean(url))) {
        continue;
      }
      if (!pubKeysByRelayUrl[url]!.any((pub_key) =>
      minimumRelaysCoverageByPubkey[pub_key.pubKey] == null ||
          minimumRelaysCoverageByPubkey[pub_key.pubKey]!.length <
              relayMinCountPerPubKey)) {
        continue;
      }
      bool connectable = await reconnectRelay(url);
      if (kDebugMode) {
        print("tried to reconnect to $url = $connectable");
      }
      if (!connectable) {
        continue;
      }
      if (bestRelays[url] == null) {
        bestRelays[url] = [];
      }

      for (PubkeyMapping pubKey in pubKeysByRelayUrl[url]!) {
        Set<String>? relays = minimumRelaysCoverageByPubkey[pubKey.pubKey];
        if (relays == null) {
          relays = {};
          minimumRelaysCoverageByPubkey[pubKey.pubKey] = relays;
        }
        relays.add(url);
        if (!bestRelays[url]!.contains(pubKey)) {
          // if (kDebugMode) {
          //   print("Adding $url to bestRelays since $pubKey was needed");
          // }
          bestRelays[url]!.add(pubKey);
          int count =
              notCoveredPubkeys[pubKey.pubKey] ?? relayMinCountPerPubKey;
          notCoveredPubkeys[pubKey.pubKey] = count - 1;
        }
      }
      if (onProgress != null) {
        // print(
        //     "Calculating best relays minimumRelaysCoverageByPubkey.length:${minimumRelaysCoverageByPubkey
        //         .length} pubKeysByRelayUrl.length: ${pubKeys.length}");
        onProgress.call("Calculating best relays",
            minimumRelaysCoverageByPubkey.length, pubKeys.length);
      }
    }

    notCoveredPubkeys.removeWhere((key, value) => value <= 0);

    return RelaySet(
        name: name,
        pubKey: ownerPubKey,
        relayMinCountPerPubkey: relayMinCountPerPubKey,
        direction: direction,
        relaysMap: bestRelays,
        notCoveredPubkeys: notCoveredPubkeys.entries
            .map(
              (entry) => NotCoveredPubKey(entry.key, entry.value),
        )
            .toList());
  }

  Future<void> loadMissingRelayListsFromNip65OrNip02(List<String> pubKeys,
      {Function(String stepName, int count, int total)? onProgress, bool forceRefresh = false}) async {
    List<String> missingPubKeys = [];
    for (var pubKey in pubKeys) {
      UserRelayList? userRelayList = cacheManager.loadUserRelayList(pubKey);
      if (userRelayList == null || forceRefresh) {
        // TODO check if not too old (time passed since last refreshed timestamp)
        missingPubKeys.add(pubKey);
      }
    }
    Map<String, UserRelayList> fromNip65s = {};
    Map<String, UserRelayList> fromNip02Contacts = {};
    Set<ContactList> contactLists = {};
    Set<String> found = {};

    if (missingPubKeys.isNotEmpty) {
      print("loading missing relay lists ${missingPubKeys.length}");
      if (onProgress != null) {
        onProgress.call(
            "loading missing relay lists", 0, missingPubKeys.length);
      }
      try {
        await for (final event in (await requestRelays(
            timeout: missingPubKeys.length > 1 ? 10 : 3,
            bootstrapRelays,
            Filter(
                authors: missingPubKeys,
                kinds: [Nip65.KIND, ContactList.KIND]))).stream) {
          switch (event.kind) {
            case Nip65.KIND:
              Nip65 nip65 = Nip65.fromEvent(event);
              if (nip65.relays.isNotEmpty) {
                UserRelayList fromNip65 = UserRelayList.fromNip65(nip65);
                if (fromNip65s[event.pubKey] == null ||
                    fromNip65s[event.pubKey]!.createdAt < event.createdAt) {
                  fromNip65s[event.pubKey] = fromNip65;
                }
                if (onProgress != null) {
                  found.add(event.pubKey);
                  onProgress.call("loading missing relay lists", found.length,
                      missingPubKeys.length);
                }
              }
            case ContactList.KIND:
              ContactList contactList = ContactList.fromEvent(event);
              contactLists.add(contactList);
              if (event.content.isNotEmpty) {
                if (fromNip02Contacts[event.pubKey] == null ||
                    fromNip02Contacts[event.pubKey]!.createdAt <
                        event.createdAt) {
                  fromNip02Contacts[event.pubKey] =
                      UserRelayList.fromNip02EventContent(event);
                }
                if (onProgress != null) {
                  found.add(event.pubKey);
                  onProgress.call("loading missing relay lists", found.length,
                      missingPubKeys.length);
                }
              }
          }
        }
      } catch (e) {
        print(e);
      }
      Set<UserRelayList> relayLists = Set.of(fromNip65s.values);
      // Only add kind3 contents relays if there is no Nip65 for given pubKey.
      // This is because kind3 contents relay should be deprecated, and if we have a nip65 list should be considered more up-to-date.
      for (MapEntry<String, UserRelayList> entry in fromNip02Contacts.entries) {
        if (!fromNip65s.containsKey(entry.key)) {
          relayLists.add(entry.value);
        }
      }
      await cacheManager.saveUserRelayLists(relayLists.toList());

      // also save to cache any fresher contact list
      List<ContactList> contactListsSave = [];
      for (ContactList contactList in contactLists) {
        ContactList? existing =
        cacheManager.loadContactList(contactList.pubKey);
        if (existing == null || existing.createdAt < contactList.createdAt) {
          contactListsSave.add(contactList);
        }
      }
      await cacheManager.saveContactLists(contactListsSave);

      if (onProgress != null) {
        onProgress.call(
            "loading missing relay lists", found.length, missingPubKeys.length);
      }
    }
    print("Loaded ${found.length} relay lists ");
  }

  _buildPubKeysMapFromRelayLists(List<String> pubKeys,
      RelayDirection direction) async {
    Map<String, Set<PubkeyMapping>> pubKeysByRelayUrl = {};
    int foundCount = 0;
    for (String pubKey in pubKeys) {
      UserRelayList? userRelayList = cacheManager.loadUserRelayList(pubKey);
      if (userRelayList != null) {
        if (userRelayList.relays.isNotEmpty) {
          foundCount++;
        }
        for (var entry in userRelayList.relays.entries) {
          _handleRelayUrlForPubKey(
              pubKey, direction, entry.key, entry.value, pubKeysByRelayUrl);
        }
      } else {
        int now = DateTime
            .now()
            .millisecondsSinceEpoch ~/ 1000;
        await cacheManager.saveUserRelayList(UserRelayList(
            pubKey: pubKey,
            relays: {},
            createdAt: now,
            refreshedTimestamp: now));
      }
    }
    print(
        "Have lists of relays for $foundCount/${pubKeys
            .length} pubKeys ${foundCount < pubKeys.length ? "(missing ${pubKeys
            .length - foundCount})" : ""}");

    /// sort by pubKeys count for each relay descending
    List<MapEntry<String, Set<PubkeyMapping>>> sortedEntries =
    pubKeysByRelayUrl.entries.toList()

    /// todo: use more stuff to improve sorting
      ..sort((a, b) {
        int rr = b.value.length.compareTo(a.value.length);
        if (rr == 0) {
          // if amount of pubKeys is equal check for webSocket connected, and prioritize connected
          bool aC = isWebSocketOpen(a.key);
          bool bC = isWebSocketOpen(b.key);
          if (aC != bC) {
            return aC ? -1 : 1;
          }
          return 0;
        }
        return rr;
      });

    return Map<String, Set<PubkeyMapping>>.fromEntries(sortedEntries);
  }

  _handleRelayUrlForPubKey(String pubKey,
      RelayDirection direction,
      String url,
      ReadWriteMarker marker,
      Map<String, Set<PubkeyMapping>> pubKeysByRelayUrl) {
    String? cleanUrl = Relay.clean(url);
    if (cleanUrl != null) {
      if (direction.matchesMarker(marker)) {
        Set<PubkeyMapping>? set = pubKeysByRelayUrl[cleanUrl];
        if (set == null) {
          pubKeysByRelayUrl[cleanUrl] = {};
        }
        pubKeysByRelayUrl[cleanUrl]!
            .add(PubkeyMapping(pubKey: pubKey, rwMarker: marker));
      }
    }
  }

  bool isRelayConnected(String url) {
    Relay? relay = relays[url];
    return relay != null && isWebSocketOpen(url);
  }

  Future<void> reconnectRelays(Iterable<String> urls) async {
    final startTime = DateTime.now();
    print("connecting ${urls.length} relays in parallel");
    List<bool> connected = await Future.wait(urls.map((url) {
      return reconnectRelay(url, force: true);
    }));
    final endTime = DateTime.now();
    final duration = endTime.difference(startTime);
    print(
        "CONNECTED ${connected
            .where((element) => element)
            .length} , ${connected
            .where((element) => !element)
            .length} FAILED took ${duration.inMilliseconds} ms");
  }

  Future<bool> reconnectRelay(String url, {bool force = false}) async {
    Relay? relay = getRelay(url);
    if (allowReconnectRelays) {
      WebSocketChannel? webSocket = webSockets[Relay.clean(url)];
      if (webSocket!=null) {
        await webSocket.ready;
      }
      if (!isWebSocketOpen(url)) {
        if (relay != null &&
            !force &&
            !relay.wasLastConnectTryLongerThanSeconds(
                FAIL_RELAY_CONNECT_TRY_AFTER_SECONDS)) {
          // don't try too often
          return false;
        }

        if (!await connectRelay(url)) {
          // could not connect
          return false;
        }
        if (!isWebSocketOpen(url)) {
          // web socket is not open
          return false;
        }
      }
    }
    return true;
  }

  Future<RelayInfo?> getRelayInfo(String url) async {
    if (relays[url] != null) {
      relays[url]!.info ??= await RelayInfo.get(url);
      return relays[url]!.info;
    }
    return null;
  }

  bool filterEvent(Nip01Event event) {
    for (var filter in eventFilters) {
      if (!filter.filter(event)) {
        return false;
      }
    }
    return true;
  }
}
