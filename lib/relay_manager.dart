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
import 'package:dart_ndk/nips/nip09/deletion.dart';
import 'package:dart_ndk/nips/nip11/relay_info.dart';
import 'package:dart_ndk/nips/nip25/reactions.dart';
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
import 'nips/nip01/metadata.dart';
import 'nips/nip51/nip51.dart';
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

  final Map<String, NostrRequest> nostrRequests = {};

  List<String> blockedRelays = [];

  int get blockedRelaysCount => blockedRelays.length;

  List<EventFilter> eventFilters = [];

  bool allowReconnectRelays = true;

  HttpClient? httpClient;

  RelayManager({bool? isWeb}) {
    if (isWeb == null || !isWeb) {
      httpClient = HttpClient();
      httpClient!.idleTimeout = const Duration(seconds: 3600);
      httpClient!.connectionTimeout = const Duration(seconds: 5);
    }
  }
  // ====================================================================================================================

  /// This will initialize the manager with bootstrap relays.
  /// If you don't give any, will use some predefined
  Future<void> connect(
      {Iterable<String> urls = DEFAULT_BOOTSTRAP_RELAYS}) async {
    bootstrapRelays = [];
    for (String url in urls) {
      String? clean = Relay.cleanUrl(url);
      if (clean != null) {
        bootstrapRelays.add(clean);
      }
    }
    if (bootstrapRelays.isEmpty) {
      bootstrapRelays = DEFAULT_BOOTSTRAP_RELAYS;
    }
    await Future.wait(
        urls.map((url) => reconnectRelay(url, force: true)).toList());
  }

  void send(String url, dynamic data) {
    // webSocket!.sendMessage(jsonEncode(["EVENT", event.toJson()]));
    webSockets[url]!.sink.add(data);
  }

  Future<void> closeSocket(url) async {
    return webSockets[url]?.sink.close().timeout(const Duration(seconds: 3),
        onTimeout: () {
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
    WebSocketChannel? webSocket = webSockets[Relay.cleanUrl(url)];
    // return webSocket != null && webSocket.socketState.status == SocketStatus.connected;
    //&& webSocket.ready== WebSocket.open
    return webSocket != null && webSocket.closeCode == null;
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
    String? url = Relay.cleanUrl(dirtyUrl);
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
    }, onError: (error) async {
      /// todo: handle this better, should clean subscription stuff
      relays[url]!.stats.connectionErrors++;
      print("onError $url on listen $error");
      throw Exception("Error in socket");
    }, onDone: () {
      if (allowReconnectRelays) {
        print(
            "onDone $url on listen (close: ${webSockets[url]!.closeCode} ${webSockets[url]!.closeReason}), trying to reconnect");
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

  Future<NostrRequest> subscription(Filter filter, RelaySet relaySet,
      {bool splitRequestsByPubKeyMappings = true}) async {
    return doNostrRequest(
        NostrRequest.subscription(Helpers.getRandomString(10),
            eventVerifier: eventVerifier),
        filter,
        relaySet,
        splitRequestsByPubKeyMappings: splitRequestsByPubKeyMappings);
  }

  Future<NostrRequest> query(
    Filter filter,
    RelaySet relaySet, {
    int idleTimeout = DEFAULT_STREAM_IDLE_TIMEOUT,
    bool splitRequestsByPubKeyMappings = true,
  }) async {
    return doNostrRequest(
        NostrRequest.query(Helpers.getRandomString(10),
            eventVerifier: eventVerifier,
            timeout: idleTimeout, onTimeout: (request) {
          closeNostrRequest(request);
        }),
        filter,
        relaySet,
        splitRequestsByPubKeyMappings: splitRequestsByPubKeyMappings);
  }

  Future<void> closeNostrRequest(NostrRequest request) async {
    return closeNostrRequestById(request.id);
  }

  Future<void> closeNostrRequestById(String id) async {
    NostrRequest? nostrRequest = nostrRequests[id];
    if (nostrRequest != null) {
      for (var url in nostrRequest.requests.keys) {
        if (isWebSocketOpen(url)) {
          try {
            // webSockets[url]!.sendMessage(jsonEncode(["CLOSE", nostrRequest.id]));
            send(url, jsonEncode(["CLOSE", nostrRequest.id]));
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
      Map<int?, int> kindsMap = {};
      nostrRequests.forEach((key, request) {
        int? kind;
        if (request.requests.isNotEmpty &&
            request.requests.values.first.filters.first.kinds != null &&
            request.requests.values.first.filters.first.kinds!.isNotEmpty) {
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

  bool doRequest(String id, RelayRequest request) {
    if (isWebSocketOpen(request.url) &&
        (!blockedRelays.contains(request.url))) {
      try {
        List<dynamic> list = ["REQ", id];
        list.addAll(request.filters.map((filter) => filter.toMap()));

        // webSockets[request.url]!.sendMessage(jsonEncode(list));
        send(request.url, jsonEncode(list));

        return true;
      } catch (e) {
        print(e);
      }
    } else {
      print(
          "COULD NOT SEND REQUEST TO ${request.url} since socket seems to be not open");

      reconnectRelay(request.url);
    }
    return false;
  }

  Future<void> broadcastEvent(
      Nip01Event event, Iterable<String> relays, EventSigner signer) async {
    await signer.sign(event);
    await Future.wait(relays.map((url) => broadcastSignedEvent(event, url)));
  }

  Future<void> broadcastSignedEvent(Nip01Event event, String url) async {
    if (isWebSocketOpen(url) && (!blockedRelays.contains(url))) {
      try {
        print(
            "BROADCASTING to $url : kind: ${event.kind} author: ${event.pubKey}");
        var webSocket = webSockets[url];
        if (webSocket != null) {
          send(url, jsonEncode(["EVENT", event.toJson()]));
        }
      } catch (e) {
        print("ERROR BROADCASTING $url -> $e");
      }
    }
  }

  Future<Nip01Event> broadcastReaction(
      String eventId, Iterable<String> relays, EventSigner signer,
      {String reaction = "+"}) async {
    Nip01Event event = Nip01Event(
        pubKey: signer.getPublicKey(),
        kind: Reaction.KIND,
        tags: [
          ["e", eventId]
        ],
        content: reaction,
        createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000);
    await broadcastEvent(event, relays, signer);
    return event;
  }

  Future<Nip01Event> broadcastDeletion(
      String eventId, Iterable<String> relays, EventSigner signer) async {
    Nip01Event event = Nip01Event(
        pubKey: signer.getPublicKey(),
        kind: Deletion.KIND,
        tags: [
          ["e", eventId]
        ],
        content: "delete",
        createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000);
    await broadcastEvent(event, relays, signer);
    return event;
  }

  // if cached contact list is older that now minus this duration that we should go refresh it,
  // otherwise we risk adding/removing contacts to a list that is out of date and thus loosing contacts other client has added/removed since.
  static const Duration REFRESH_CONTACT_LIST_DURATION = Duration(minutes: 10);

  Future<ContactList> ensureUpToDateContactListOrEmpty(
      EventSigner signer) async {
    ContactList? contactList =
        cacheManager.loadContactList(signer.getPublicKey());
    int sometimeAgo = DateTime.now()
            .subtract(REFRESH_CONTACT_LIST_DURATION)
            .millisecondsSinceEpoch ~/
        1000;
    bool refresh = contactList == null ||
        contactList.loadedTimestamp == null ||
        contactList.loadedTimestamp! < sometimeAgo;
    if (refresh) {
      contactList =
          await loadContactList(signer.getPublicKey(), forceRefresh: true);
    }
    contactList ??= ContactList(pubKey: signer.getPublicKey(), contacts: []);
    return contactList;
  }

  Future<ContactList> broadcastAddContact(
      String add, Iterable<String> relays, EventSigner signer) async {
    ContactList contactList = await ensureUpToDateContactListOrEmpty(signer);
    if (!contactList.contacts.contains(add)) {
      contactList.contacts.add(add);
      contactList.loadedTimestamp = Helpers.now;
      contactList.createdAt = Helpers.now;
      await broadcastEvent(contactList.toEvent(), relays, signer);
      await cacheManager.saveContactList(contactList);
    }
    return contactList;
  }

  Future<ContactList> broadcastAddFollowedTag(
      String toAdd, Iterable<String> relays, EventSigner signer) async {
    ContactList contactList = await ensureUpToDateContactListOrEmpty(signer);
    if (!contactList.followedTags.contains(toAdd)) {
      contactList.followedTags.add(toAdd);
      contactList.loadedTimestamp = Helpers.now;
      contactList.createdAt = Helpers.now;
      await broadcastEvent(contactList.toEvent(), relays, signer);
      await cacheManager.saveContactList(contactList);
    }
    return contactList;
  }

  Future<ContactList> broadcastAddFollowedCommunity(
      String toAdd, Iterable<String> relays, EventSigner signer) async {
    ContactList contactList = await ensureUpToDateContactListOrEmpty(signer);
    if (!contactList.followedCommunities.contains(toAdd)) {
      contactList.followedCommunities.add(toAdd);
      contactList.loadedTimestamp = Helpers.now;
      contactList.createdAt = Helpers.now;
      await broadcastEvent(contactList.toEvent(), relays, signer);
      await cacheManager.saveContactList(contactList);
    }
    return contactList;
  }

  Future<ContactList> broadcastAddFollowedEvent(
      String toAdd, Iterable<String> relays, EventSigner signer) async {
    ContactList contactList = await ensureUpToDateContactListOrEmpty(signer);
    if (!contactList.followedEvents.contains(toAdd)) {
      contactList.followedEvents.add(toAdd);
      contactList.loadedTimestamp = Helpers.now;
      contactList.createdAt = Helpers.now;
      await broadcastEvent(contactList.toEvent(), relays, signer);
      await cacheManager.saveContactList(contactList);
    }
    return contactList;
  }

  Future<ContactList?> broadcastRemoveContact(
      String toRemove, Iterable<String> relays, EventSigner signer) async {
    ContactList? contactList = await ensureUpToDateContactListOrEmpty(signer);
    if (contactList.contacts.contains(toRemove)) {
      contactList.contacts.remove(toRemove);
      contactList.loadedTimestamp = Helpers.now;
      contactList.createdAt = Helpers.now;
      await broadcastEvent(contactList.toEvent(), relays, signer);
      await cacheManager.saveContactList(contactList);
    }
    return contactList;
  }

  Future<ContactList?> broadcastRemoveFollowedTag(
      String toRemove, Iterable<String> relays, EventSigner signer) async {
    ContactList? contactList = await ensureUpToDateContactListOrEmpty(signer);
    if (contactList.followedTags.contains(toRemove)) {
      contactList.followedTags.remove(toRemove);
      contactList.loadedTimestamp = Helpers.now;
      contactList.createdAt = Helpers.now;
      await broadcastEvent(contactList.toEvent(), relays, signer);
      await cacheManager.saveContactList(contactList);
    }
    return contactList;
  }

  Future<ContactList?> broadcastRemoveFollowedCommunity(
      String toRemove, Iterable<String> relays, EventSigner signer) async {
    ContactList? contactList = await ensureUpToDateContactListOrEmpty(signer);
    if (contactList.followedCommunities.contains(toRemove)) {
      contactList.followedCommunities.remove(toRemove);
      contactList.loadedTimestamp = Helpers.now;
      contactList.createdAt = Helpers.now;
      await broadcastEvent(contactList.toEvent(), relays, signer);
      await cacheManager.saveContactList(contactList);
    }
    return contactList;
  }

  Future<ContactList?> broadcastRemoveFollowedEvent(
      String toRemove, Iterable<String> relays, EventSigner signer) async {
    ContactList? contactList = await ensureUpToDateContactListOrEmpty(signer);
    if (contactList.followedEvents.contains(toRemove)) {
      contactList.followedEvents.remove(toRemove);
      contactList.loadedTimestamp = Helpers.now;
      contactList.createdAt = Helpers.now;
      await broadcastEvent(contactList.toEvent(), relays, signer);
      await cacheManager.saveContactList(contactList);
    }
    return contactList;
  }

  // if cached user relay list is older that now minus this duration that we should go refresh it,
  // otherwise we risk adding/removing relays to a list that is out of date and thus loosing relays other client has added/removed since.
  static const Duration REFRESH_USER_RELAY_DURATION = Duration(minutes: 10);

  Future<UserRelayList?> ensureUpToDateUserRelayList(EventSigner signer) async {
    UserRelayList? userRelayList =
        cacheManager.loadUserRelayList(signer.getPublicKey());
    int sometimeAgo = DateTime.now()
            .subtract(REFRESH_USER_RELAY_DURATION)
            .millisecondsSinceEpoch ~/
        1000;
    bool refresh =
        userRelayList == null || userRelayList.refreshedTimestamp < sometimeAgo;
    if (refresh) {
      userRelayList = await getSingleUserRelayList(signer.getPublicKey(),
          forceRefresh: true);
    }
    return userRelayList;
  }

  Future<UserRelayList> broadcastAddNip65Relay(
      String relayUrl,
      ReadWriteMarker marker,
      Iterable<String> broadcastRelays,
      EventSigner signer) async {
    UserRelayList? userRelayList = await ensureUpToDateUserRelayList(signer);
    if (userRelayList == null) {
      int now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      userRelayList = UserRelayList(
          pubKey: signer.getPublicKey(),
          relays: {
            for (String url in broadcastRelays) url: ReadWriteMarker.readWrite
          },
          createdAt: now,
          refreshedTimestamp: now);
    }
    userRelayList.relays[relayUrl] = marker;
    await Future.wait([
      broadcastEvent(
          userRelayList.toNip65().toEvent(), broadcastRelays, signer),
      cacheManager.saveUserRelayList(userRelayList)
    ]);
    return userRelayList;
  }

  Future<UserRelayList?> broadcastRemoveNip65Relay(String relayUrl,
      Iterable<String> broadcastRelays, EventSigner signer) async {
    UserRelayList? userRelayList = await ensureUpToDateUserRelayList(signer);
    if (userRelayList == null) {
      int now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      userRelayList = UserRelayList(
          pubKey: signer.getPublicKey(),
          relays: {
            for (String url in broadcastRelays) url: ReadWriteMarker.readWrite
          },
          createdAt: now,
          refreshedTimestamp: now);
    }
    if (userRelayList.relays.keys.contains(relayUrl)) {
      userRelayList.relays.remove(relayUrl);
      userRelayList.refreshedTimestamp = Helpers.now;
      await Future.wait([
        broadcastEvent(
            userRelayList.toNip65().toEvent(), broadcastRelays, signer),
        cacheManager.saveUserRelayList(userRelayList)
      ]);
    }
    return userRelayList;
  }

  Future<UserRelayList?> broadcastUpdateNip65RelayMarker(
      String relayUrl,
      ReadWriteMarker marker,
      Iterable<String> broadcastRelays,
      EventSigner signer) async {
    UserRelayList? userRelayList = await ensureUpToDateUserRelayList(signer);
    if (userRelayList == null) {
      int now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      userRelayList = UserRelayList(
          pubKey: signer.getPublicKey(),
          relays: {
            for (String url in broadcastRelays) url: ReadWriteMarker.readWrite
          },
          createdAt: now,
          refreshedTimestamp: now);
    }
    String? url;
    if (userRelayList.relays.keys.contains(relayUrl)) {
      url = relayUrl;
    } else {
      String? cleanUrl = Relay.cleanUrl(relayUrl);
      if (cleanUrl != null && userRelayList.relays.keys.contains(cleanUrl)) {
        url = cleanUrl;
      } else if (userRelayList.relays.keys.contains("$relayUrl/")) {
        url = "$relayUrl/";
      }
    }
    if (url != null) {
      userRelayList.relays[url] = marker;
      userRelayList.refreshedTimestamp = Helpers.now;
      await broadcastEvent(
          userRelayList.toNip65().toEvent(), broadcastRelays, signer);
      await cacheManager.saveUserRelayList(userRelayList);
    }
    return userRelayList;
  }

  Future<Nip51Set> broadcastAddNip51SetRelay(String relayUrl, String name,
      Iterable<String> broadcastRelays, EventSigner signer,
      {bool private = false}) async {
    if (private && !signer.canSign()) {
      throw Exception(
          "cannot broadcast private nip51 list without a signer that can sign");
    }
    Nip51Set? list =
        await getSingleNip51RelaySet(name, signer, forceRefresh: true);
    list ??= Nip51Set(
        name: name,
        pubKey: signer.getPublicKey(),
        createdAt: Helpers.now,
        elements: []);
    list.addRelay(relayUrl, private);
    list.createdAt = Helpers.now;
    Nip01Event event = await list.toEvent(signer);
    print(event);
    await Future.wait([
      broadcastEvent(event, broadcastRelays, signer),
    ]);
    List<Nip01Event>? events = cacheManager.loadEvents(
        pubKeys: [signer.getPublicKey()], kinds: [Nip51List.RELAY_SET]);
    events = events.where((event) {
      if (event.getDtag() != null && event.getDtag() == name) {
        return true;
      }
      return false;
    }).toList();
    for (var event in events) {
      cacheManager.removeEvent(event.id);
    }

    await cacheManager.saveEvent(event);
    return list;
  }

  Future<Nip51Set?> broadcastRemoveNip51SetRelay(String relayUrl, String name,
      Iterable<String> broadcastRelays, EventSigner signer,
      {List<String>? defaultRelaysIfEmpty, bool private = false}) async {
    if (private && !signer.canSign()) {
      throw Exception(
          "cannot broadcast private nip51 list without a signer that can sign");
    }
    Nip51Set? relaySet = await getSingleNip51RelaySet(
      name,
      signer,
      forceRefresh: true,
    );
    if ((relaySet == null || relaySet.allRelays.isEmpty) &&
        defaultRelaysIfEmpty != null &&
        defaultRelaysIfEmpty.isNotEmpty) {
      relaySet = Nip51Set(
          name: name,
          pubKey: signer.getPublicKey(),
          createdAt: Helpers.now,
          elements: []);
      relaySet.privateRelays = defaultRelaysIfEmpty;
    }
    if (relaySet != null) {
      relaySet.removeRelay(relayUrl);
      relaySet.createdAt = Helpers.now;
      Nip01Event event = await relaySet.toEvent(signer);
      await Future.wait([
        broadcastEvent(event, broadcastRelays, signer),
      ]);
      List<Nip01Event>? events = cacheManager.loadEvents(
          pubKeys: [signer.getPublicKey()], kinds: [Nip51List.RELAY_SET]);
      events = events.where((event) {
        if (event.getDtag() != null && event.getDtag() == name) {
          return true;
        }
        return false;
      }).toList();
      for (var event in events) {
        cacheManager.removeEvent(event.id);
      }
      await cacheManager.saveEvent(event);
    }
    return relaySet;
  }

  Future<Nip51List> broadcastAddNip51ListRelay(int kind, String relayUrl,
      Iterable<String> broadcastRelays, EventSigner signer,
      {bool private = false}) async {
    if (private && !signer.canSign()) {
      throw Exception(
          "cannot broadcast private nip51 list without a signer that can sign");
    }
    Nip51List? list =
        await getSingleNip51List(kind, signer, forceRefresh: true);
    list ??= Nip51List(
        kind: kind,
        pubKey: signer.getPublicKey(),
        createdAt: Helpers.now,
        elements: []);
    list.addRelay(relayUrl, private);
    list.createdAt = Helpers.now;
    Nip01Event event = await list.toEvent(signer);
    print(event);
    await Future.wait([
      broadcastEvent(event, broadcastRelays, signer),
    ]);
    List<Nip01Event>? events = cacheManager
        .loadEvents(pubKeys: [signer.getPublicKey()], kinds: [kind]);
    for (var event in events) {
      cacheManager.removeEvent(event.id);
    }
    await cacheManager.saveEvent(event);
    return list;
  }

  Future<Nip51List?> broadcastRemoveNip51Relay(int kind, String relayUrl,
      Iterable<String> broadcastRelays, EventSigner signer,
      {List<String>? defaultRelaysIfEmpty}) async {
    if (!signer.canSign()) {
      throw Exception(
          "cannot broadcast private nip51 list without a signer that can sign");
    }
    Nip51List? list = await getSingleNip51List(
      kind,
      signer,
      forceRefresh: true,
    );
    if ((list == null || list.allRelays.isEmpty) &&
        defaultRelaysIfEmpty != null &&
        defaultRelaysIfEmpty.isNotEmpty) {
      list = Nip51List(
          kind: kind,
          pubKey: signer.getPublicKey(),
          createdAt: Helpers.now,
          elements: []);
      list.privateRelays = defaultRelaysIfEmpty;
    }
    if (list != null && list.allRelays.isNotEmpty) {
      list.removeRelay(relayUrl);
      list.createdAt = Helpers.now;
      Nip01Event event = await list.toEvent(signer);
      await Future.wait([
        broadcastEvent(event, broadcastRelays, signer),
      ]);
      List<Nip01Event>? events = cacheManager
          .loadEvents(pubKeys: [signer.getPublicKey()], kinds: [kind]);
      for (var event in events) {
        cacheManager.removeEvent(event.id);
      }
      await cacheManager.saveEvent(event);
    }
    return list;
  }

  Future<Nip51List?> broadcastRemoveNip51ListElement(
      int kind,
      String tag,
      String value,
      Iterable<String> broadcastRelays,
      EventSigner signer) async {
    if (!signer.canSign()) {
      throw Exception(
          "cannot broadcast private nip51 list without a signer that can sign");
    }
    Nip51List? list =
        await getSingleNip51List(kind, signer, forceRefresh: true, timeout: 2);
    if (list == null || list.elements.isEmpty) {
      list = Nip51List(
          kind: kind,
          pubKey: signer.getPublicKey(),
          createdAt: Helpers.now,
          elements: []);
    }
    if (list.elements.isNotEmpty) {
      list.removeElement(tag, value);
      list.createdAt = Helpers.now;
      Nip01Event event = await list.toEvent(signer);
      await Future.wait([
        broadcastEvent(event, broadcastRelays, signer),
      ]);
      List<Nip01Event>? events = cacheManager
          .loadEvents(pubKeys: [signer.getPublicKey()], kinds: [kind]);
      for (var event in events) {
        cacheManager.removeEvent(event.id);
      }
      await cacheManager.saveEvent(event);
    }
    return list;
  }

  Future<Nip51List> broadcastAddNip51ListElement(int kind, String tag,
      String value, Iterable<String> broadcastRelays, EventSigner signer,
      {bool private = false}) async {
    if (private && !signer.canSign()) {
      throw Exception(
          "cannot broadcast private nip51 list without a signer that can sign");
    }
    Nip51List? list =
        await getSingleNip51List(kind, signer, forceRefresh: true, timeout: 2);
    list ??= Nip51List(
        kind: kind,
        pubKey: signer.getPublicKey(),
        createdAt: Helpers.now,
        elements: []);
    list.addElement(tag, value, private);
    list.createdAt = Helpers.now;
    Nip01Event event = await list.toEvent(signer);
    print(event);
    await Future.wait([
      broadcastEvent(event, broadcastRelays, signer),
    ]);
    List<Nip01Event>? events = cacheManager
        .loadEvents(pubKeys: [signer.getPublicKey()], kinds: [kind]);
    for (var event in events) {
      cacheManager.removeEvent(event.id);
    }
    await cacheManager.saveEvent(event);
    return list;
  }

  //*******************************************************************************************************************************/

  Future<Nip01Event?> getSingleMetadataEvent(EventSigner signer) async {
    Nip01Event? loaded;
    await for (final event in (await requestRelays(
            bootstrapRelays,
            timeout: DEFAULT_STREAM_IDLE_TIMEOUT,
            Filter(
                kinds: [Metadata.KIND],
                authors: [signer.getPublicKey()],
                limit: 1)))
        .stream) {
      if (loaded == null || loaded.createdAt < event.createdAt) {
        loaded = event;
      }
    }
    return loaded;
  }

  Future<Metadata> broadcastMetadata(Metadata metadata,
      Iterable<String> broadcastRelays, EventSigner signer) async {
    Nip01Event? event = await getSingleMetadataEvent(signer);
    if (event != null) {
      Map<String, dynamic> map = json.decode(event.content);
      map.addAll(metadata.toJson());
      event = Nip01Event(
          pubKey: event.pubKey,
          kind: event.kind,
          tags: event.tags,
          content: json.encode(map),
          createdAt: Helpers.now);
    } else {
      event = metadata.toEvent();
    }
    await broadcastEvent(event, broadcastRelays, signer);

    metadata.updatedAt = Helpers.now;
    metadata.refreshedTimestamp = Helpers.now;
    await cacheManager.saveMetadata(metadata);

    return metadata;
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
      reconnectRelay(url, force: true);
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
                .incStatsByNewEvent(event, message.toString().codeUnits.length);
          }
          NostrRequest? nostrRequest = nostrRequests[id];
          if (nostrRequest != null) {
            try {
              nostrRequest.controller.add(event);
              // if (!nostrRequest.controller.isClosed && nostrRequest.shouldClose) {
              //   nostrRequest.controller.close();
              //   nostrRequests.remove(id);
              // }
            } catch (e) {
              print(
                  "COULD NOT ADD event $event TO CONTROLLER on $url for requests ${nostrRequest.requests}");
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
      if (nostrRequest != null && nostrRequest.closeOnEOSE) {
        // print("RECEIVED EOSE from $url, remaining requests from :${nostrRequest.requests.keys} kind:${nostrRequest.requests.values.first.filters.first.kinds}");
        RelayRequest? request = nostrRequest.requests[url];
        if (request != null) {
          request.receivedEOSE = true;
          nostrRequest.requests.remove(url);
          if (isWebSocketOpen(url)) {
            // webSockets[url]!.sendMessage(
            //     jsonEncode(["CLOSE", nostrRequest.id]));
            send(url, jsonEncode(["CLOSE", nostrRequest.id]));
          }
        }
        if (nostrRequest.requests.isEmpty &&
            !nostrRequest.controller.isClosed) {
          Future.delayed(Duration(seconds: (nostrRequest.timeout ?? 5) * 10),
              () {
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
    r ??= relays[Relay.cleanUrl(url)];
    return r;
  }

  bool _doesRelaySupportNip(String url, int nip) {
    Relay? relay = relays[Relay.cleanUrl(url)];
    return relay != null && relay.supportsNip(nip);
  }

  Future<NostrRequest> doNostrRequest(
      NostrRequest nostrRequest, Filter filter, RelaySet relaySet,
      {bool splitRequestsByPubKeyMappings = true}) async {
    if (splitRequestsByPubKeyMappings) {
      relaySet.splitIntoRequests(filter, nostrRequest);

      print(
          "request for ${filter.authors != null ? filter.authors!.length : 0} authors with kinds: ${filter.kinds} made requests to ${nostrRequest.requests.length} relays");

      if (nostrRequest.requests.isEmpty && relaySet.fallbackToBootstrapRelays) {
        print(
            "making fallback requests to ${bootstrapRelays.length} bootstrap relays for ${filter.authors != null ? filter.authors!.length : 0} authors with kinds: ${filter.kinds}");
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
    Map<int?, int> kindsMap = {};
    nostrRequests.forEach((key, request) {
      int? kind;
      if (request.requests.isNotEmpty &&
          request.requests.values.first.filters.first.kinds != null &&
          request.requests.values.first.filters.first.kinds!.isNotEmpty) {
        kind = request.requests.values.first.filters.first.kinds!.first;
      }
      int? count = kindsMap[kind];
      count ??= 0;
      count++;
      kindsMap[kind] = count;
    });
    print(
        "----------------NOSTR REQUESTS: ${nostrRequests.length} || $kindsMap");
    for (MapEntry<String, RelayRequest> entry
        in nostrRequest.requests.entries) {
      doRequest(nostrRequest.id, entry.value);
    }
    return nostrRequest;
  }

  Future<NostrRequest> requestRelays(Iterable<String> urls, Filter filter,
      {int timeout = DEFAULT_STREAM_IDLE_TIMEOUT,
      bool closeOnEOSE = true,
      Function()? onTimeout}) async {
    String id = Helpers.getRandomString(10);
    NostrRequest nostrRequest = closeOnEOSE
        ? NostrRequest.query(id, eventVerifier: eventVerifier, timeout: timeout,
            onTimeout: (request) {
            closeNostrRequest(request);
            if (onTimeout != null) {
              onTimeout();
            }
          })
        : NostrRequest.subscription(id, eventVerifier: eventVerifier);

    for (var url in urls) {
      nostrRequest.addRequest(url, RelaySet.sliceFilterAuthors(filter));
    }
    nostrRequests[nostrRequest.id] = nostrRequest;

    List<String> notSent = [];
    Map<int?, int> kindsMap = {};
    nostrRequests.forEach((key, request) {
      int? kind;
      if (request.requests.isNotEmpty &&
          request.requests.values.first.filters.first.kinds != null &&
          request.requests.values.first.filters.first.kinds!.isNotEmpty) {
        kind = request.requests.values.first.filters.first.kinds!.first;
      }
      int? count = kindsMap[kind];
      count ??= 0;
      count++;
      kindsMap[kind] = count;
    });
    print(
        "----------------NOSTR REQUESTS: ${nostrRequests.length} || $kindsMap");
    for (MapEntry<String, RelayRequest> entry
        in nostrRequest.requests.entries) {
      if (!doRequest(nostrRequest.id, entry.value)) {
        notSent.add(entry.key);
      }
    }
    for (var url in notSent) {
      nostrRequest.requests.remove(url);
    }

    return nostrRequest;
  }

  RelaySet? getRelaySet(String name, String pubKey) {
    return cacheManager.loadRelaySet(name, pubKey);
  }

  Future<void> saveRelaySet(RelaySet relaySet) async {
    return cacheManager.saveRelaySet(relaySet);
  }

  /// relay -> list of pubKey mappings
  Future<RelaySet> calculateRelaySet(
      {required String name,
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
            .map((pubKey) => PubkeyMapping(
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
  Future<RelaySet> _relaysByPopularity(
      {required String name,
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
      if (blockedRelays.contains(Relay.cleanUrl(url))) {
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
      {Function(String stepName, int count, int total)? onProgress,
      bool forceRefresh = false}) async {
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
                    kinds: [Nip65.KIND, ContactList.KIND])))
            .stream) {
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

  Future<List<Metadata>> loadMissingMetadatas(
      List<String> pubKeys, RelaySet relaySet,
      {bool splitRequestsByPubKeyMappings = true,
      Function(Metadata)? onLoad}) async {
    List<String> missingPubKeys = [];
    for (var pubKey in pubKeys) {
      Metadata? userMetadata = cacheManager.loadMetadata(pubKey);
      if (userMetadata == null) {
        // TODO check if not too old (time passed since last refreshed timestamp)
        missingPubKeys.add(pubKey);
      }
    }
    Map<String, Metadata> metadatas = {};

    if (missingPubKeys.isNotEmpty) {
      print("loading missing user metadatas ${missingPubKeys.length}");
      try {
        await for (final event in (await query(
                idleTimeout: 1,
                splitRequestsByPubKeyMappings: splitRequestsByPubKeyMappings,
                Filter(authors: missingPubKeys, kinds: [Metadata.KIND]),
                relaySet))
            .stream
            .timeout(const Duration(seconds: 5), onTimeout: (sink) {
          print("timeout metadatas.length:${metadatas.length}");
        })) {
          if (metadatas[event.pubKey] == null ||
              metadatas[event.pubKey]!.updatedAt! < event.createdAt) {
            metadatas[event.pubKey] = Metadata.fromEvent(event);
            metadatas[event.pubKey]!.refreshedTimestamp = Helpers.now;
            await cacheManager.saveMetadata(metadatas[event.pubKey]!);
            if (onLoad != null) {
              onLoad(metadatas[event.pubKey]!);
            }
          }
        }
      } catch (e) {
        print(e);
      }
      // if (metadatas.isNotEmpty) {
      //   await cacheManager.saveMetadatas(metadatas.values
      //       // .map((metadata) => DbMetadata.fromMetadata(metadata))
      //       .toList());
      // }
      print("Loaded ${metadatas.length} user metadatas ");
    }
    return metadatas.values.toList();
  }

  Future<ContactList?> loadContactList(String pubKey,
      {bool forceRefresh = false,
      int idleTimeout = DEFAULT_STREAM_IDLE_TIMEOUT}) async {
    ContactList? contactList = cacheManager.loadContactList(pubKey);
    if (contactList == null || forceRefresh) {
      ContactList? loadedContactList;
      try {
        await for (final event in (await requestRelays(
                bootstrapRelays,
                timeout: idleTimeout,
                Filter(kinds: [ContactList.KIND], authors: [pubKey], limit: 1)))
            .stream) {
          if (loadedContactList == null ||
              loadedContactList.createdAt < event.createdAt) {
            loadedContactList = ContactList.fromEvent(event);
          }
        }
      } catch (e) {
        print(e);
        // probably timeout;
      }
      if (loadedContactList != null &&
          (contactList == null ||
              contactList.createdAt < loadedContactList.createdAt)) {
        loadedContactList.loadedTimestamp =
            DateTime.now().millisecondsSinceEpoch ~/ 1000;
        await cacheManager.saveContactList(loadedContactList);
        contactList = loadedContactList;
      }
    }
    return contactList;
  }

  Future<Metadata?> getSingleMetadata(String pubKey,
      {bool forceRefresh = false,
      int idleTimeout = DEFAULT_STREAM_IDLE_TIMEOUT}) async {
    Metadata? metadata = cacheManager.loadMetadata(pubKey);
    if (metadata == null || forceRefresh) {
      Metadata? loadedMetadata;
      try {
        await for (final event in (await requestRelays(
                bootstrapRelays,
                timeout: idleTimeout,
                Filter(kinds: [Metadata.KIND], authors: [pubKey], limit: 1)))
            .stream) {
          if (loadedMetadata == null ||
              loadedMetadata.updatedAt == null ||
              loadedMetadata.updatedAt! < event.createdAt) {
            loadedMetadata = Metadata.fromEvent(event);
          }
        }
      } catch (e) {
        // probably timeout;
      }
      if (loadedMetadata != null &&
          (metadata == null ||
              loadedMetadata.updatedAt == null ||
              metadata.updatedAt == null ||
              loadedMetadata.updatedAt! < metadata.updatedAt! ||
              forceRefresh)) {
        loadedMetadata.refreshedTimestamp = Helpers.now;
        await cacheManager.saveMetadata(loadedMetadata);
        metadata = loadedMetadata;
      }
    }
    return metadata;
  }

  _buildPubKeysMapFromRelayLists(
      List<String> pubKeys, RelayDirection direction) async {
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
        int now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        await cacheManager.saveUserRelayList(UserRelayList(
            pubKey: pubKey,
            relays: {},
            createdAt: now,
            refreshedTimestamp: now));
      }
    }
    print(
        "Have lists of relays for $foundCount/${pubKeys.length} pubKeys ${foundCount < pubKeys.length ? "(missing ${pubKeys.length - foundCount})" : ""}");

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

  _handleRelayUrlForPubKey(
      String pubKey,
      RelayDirection direction,
      String url,
      ReadWriteMarker marker,
      Map<String, Set<PubkeyMapping>> pubKeysByRelayUrl) {
    String? cleanUrl = Relay.cleanUrl(url);
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
        "CONNECTED ${connected.where((element) => element).length} , ${connected.where((element) => !element).length} FAILED took ${duration.inMilliseconds} ms");
  }

  Future<bool> reconnectRelay(String url, {bool force = false}) async {
    Relay? relay = getRelay(url);
    if (allowReconnectRelays) {
      WebSocketChannel? webSocket = webSockets[Relay.cleanUrl(url)];
      if (webSocket != null) {
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

  Future<UserRelayList?> getSingleUserRelayList(String pubKey,
      {bool forceRefresh = false}) async {
    UserRelayList? userRelayList = cacheManager.loadUserRelayList(pubKey);
    if (userRelayList == null || forceRefresh) {
      await loadMissingRelayListsFromNip65OrNip02([pubKey],
          forceRefresh: forceRefresh);
      userRelayList = cacheManager.loadUserRelayList(pubKey);
    }
    return userRelayList;
  }

  Future<Nip51List?> getCachedNip51List(int kind, EventSigner signer) async {
    List<Nip01Event>? events = cacheManager
        .loadEvents(pubKeys: [signer.getPublicKey()], kinds: [kind]);
    events.sort(
      (a, b) => b.createdAt.compareTo(a.createdAt),
    );
    return events.isNotEmpty
        ? await Nip51List.fromEvent(events.first, signer)
        : null;
  }

  Future<Nip51List?> getSingleNip51List(int kind, EventSigner signer,
      {bool forceRefresh = false, int timeout = 5}) async {
    Nip51List? list =
        !forceRefresh ? await getCachedNip51List(kind, signer) : null;
    if (list == null) {
      Nip51List? refreshedList;
      await for (final event in (await requestRelays(
              bootstrapRelays.toList(),
              Filter(
                authors: [signer.getPublicKey()],
                kinds: [kind],
              ),
              timeout: timeout))
          .stream) {
        if (refreshedList == null ||
            refreshedList.createdAt <= event.createdAt) {
          refreshedList = await Nip51List.fromEvent(event, signer);
          // if (Helpers.isNotBlank(event.content)) {
          //   Nip51List? decryptedList = await Nip51List.fromEvent(event, signer);
          //   refreshedList = decryptedList;
          // }
          await cacheManager.saveEvent(event);
        }
      }
      return refreshedList;
    }
    return list;
  }

  Future<Nip51Set?> getCachedNip51RelaySet(
      String name, EventSigner signer) async {
    List<Nip01Event>? events = cacheManager.loadEvents(
        pubKeys: [signer.getPublicKey()], kinds: [Nip51List.RELAY_SET]);
    events = events.where((event) {
      if (event.getDtag() != null && event.getDtag() == name) {
        return true;
      }
      return false;
    }).toList();
    events.sort(
      (a, b) => b.createdAt.compareTo(a.createdAt),
    );
    return events.isNotEmpty
        ? await Nip51Set.fromEvent(events.first, signer)
        : null;
  }

  Future<Nip51Set?> getSingleNip51RelaySet(String name, EventSigner signer,
      {bool forceRefresh = false}) async {
    Nip51Set? relaySet = await getCachedNip51RelaySet(name, signer);
    if (relaySet == null || forceRefresh) {
      Nip51Set? newRelaySet;
      await for (final event in (await requestRelays(
              bootstrapRelays.toList(),
              Filter(
                authors: [signer.getPublicKey()],
                kinds: [Nip51List.RELAY_SET],
                dTags: [name],
              ),
              timeout: 5))
          .stream) {
        if (newRelaySet == null || newRelaySet.createdAt < event.createdAt) {
          if (event.getDtag() != null && event.getDtag() == name) {
            newRelaySet = await Nip51Set.fromEvent(event, signer);
            await cacheManager.saveEvent(event);
          } else if (Helpers.isNotBlank(event.content)) {
            Nip51Set? decryptedRelaySet =
                await Nip51Set.fromEvent(event, signer);
            if (decryptedRelaySet != null && decryptedRelaySet.name == name) {
              newRelaySet = decryptedRelaySet;
              await cacheManager.saveEvent(event);
            }
          }
        }
      }
      return newRelaySet;
    }
    return relaySet;
  }

  Future<List<Nip51Set>?> getNip51RelaySets(int kind, EventSigner signer,
      {bool forceRefresh = false}) async {
    Nip51Set? relaySet; //getCachedNip51RelaySets(signer);
    if (relaySet == null || forceRefresh) {
      Map<String, Nip51Set> newRelaySets = {};
      await for (final event in (await requestRelays(
              bootstrapRelays.toList(),
              Filter(
                authors: [signer.getPublicKey()],
                kinds: [kind],
              ),
              timeout: 5))
          .stream) {
        if (event.getDtag() != null) {
          Nip51Set? newRelaySet = newRelaySets[event.getDtag()];
          if (newRelaySet == null || newRelaySet.createdAt < event.createdAt) {
            if (event.getDtag() != null) {
              newRelaySet = await Nip51Set.fromEvent(event, signer);
            }
            if (newRelaySet != null) {
              await cacheManager.saveEvent(event);
              newRelaySets[newRelaySet.name] = newRelaySet;
            }
          }
        }
      }
      return newRelaySets.values.toList();
    }
    return [];
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
