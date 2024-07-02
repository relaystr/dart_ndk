import 'dart:developer';

import 'package:dart_ndk/cache_manager.dart';
import 'package:dart_ndk/mem_cache_manager.dart';
import 'package:dart_ndk/nips/nip01/bip340.dart';
import 'package:dart_ndk/nips/nip01/bip340_event_verifier.dart';
import 'package:dart_ndk/nips/nip01/event.dart';
import 'package:dart_ndk/nips/nip01/event_verifier.dart';
import 'package:dart_ndk/nips/nip01/filter.dart';
import 'package:dart_ndk/nips/nip01/key_pair.dart';
import 'package:dart_ndk/nips/nip65/nip65.dart';
import 'package:dart_ndk/nips/nip65/read_write_marker.dart';
import 'package:dart_ndk/relay_jit_manager/relay_jit.dart';
import 'package:dart_ndk/relay_jit_manager/relay_jit_manager.dart';
import 'package:dart_ndk/relay_jit_manager/request_jit.dart';
import 'package:dart_ndk/request.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../mocks/mock_event_verifier.dart';
import '../../mocks/mock_relay.dart';

void main() async {
  KeyPair key1 = Bip340.generatePrivateKey();
  KeyPair key2 = Bip340.generatePrivateKey();
  KeyPair key3 = Bip340.generatePrivateKey();
  KeyPair key4 = Bip340.generatePrivateKey();

  Map<KeyPair, String> keyNames = {
    key1: "key1",
    key2: "key2",
    key3: "key3",
    key4: "key4",
  };

  Nip01Event textNote(KeyPair key2) {
    return Nip01Event(
        kind: Nip01Event.TEXT_NODE_KIND,
        pubKey: key2.publicKey,
        content: "some note from key ${keyNames[key2]}",
        tags: [],
        createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000);
  }

  Map<KeyPair, Nip01Event> key1TextNotes = {key1: textNote(key1)};
  Map<KeyPair, Nip01Event> key2TextNotes = {key2: textNote(key2)};
  Map<KeyPair, Nip01Event> key3TextNotes = {key3: textNote(key3)};
  Map<KeyPair, Nip01Event> key4TextNotes = {key4: textNote(key4)};

  MockRelay relay1 = MockRelay(name: "relay 1", explicitPort: 5001);
  MockRelay relay2 = MockRelay(name: "relay 2", explicitPort: 5002);

  MockRelay relay21 = MockRelay(name: "relay 1", explicitPort: 5003);
  MockRelay relay22 = MockRelay(name: "relay 2", explicitPort: 5004);
  MockRelay relay23 = MockRelay(name: "relay 3", explicitPort: 5005);
  MockRelay relay24 = MockRelay(name: "relay 4", explicitPort: 5006);

  group('connection tests', () {
    test('Connect to relay', () async {
      await relay1.startServer();

      RelayJit relayJit = RelayJit(relay1.url);
      var result =
          await relayJit.connect(connectionSource: ConnectionSource.UNKNOWN);

      expect(result, true);

      //await Future.delayed(Duration(seconds: 5));
      await relay1.stopServer();
    });

    test('Try to connect to dead relay', () async {
      RelayJit relayJit = RelayJit(relay2.url);
      var result =
          await relayJit.connect(connectionSource: ConnectionSource.UNKNOWN);

      expect(result, false);
    });
  });

  group("Calculate best relays (internal MOCKs)", () {
    Map<String, String> relayNames = {
      relay21.url: relay21.name,
      relay22.url: relay22.name,
      relay23.url: relay23.name,
      relay24.url: relay24.name,
    };
    Nip65 nip65ForKey1 = Nip65.fromMap(key1.publicKey, {
      relay21.url: ReadWriteMarker.readWrite,
      relay22.url: ReadWriteMarker.readWrite,
      relay23.url: ReadWriteMarker.readWrite,
      relay24.url: ReadWriteMarker.readWrite,
    });
    Nip65 nip65ForKey2 = Nip65.fromMap(key2.publicKey, {
      relay21.url: ReadWriteMarker.readWrite,
      relay22.url: ReadWriteMarker.readWrite,
    });
    Nip65 nip65ForKey3 =
        Nip65.fromMap(key3.publicKey, {relay21.url: ReadWriteMarker.readWrite});
    Nip65 nip65ForKey4 =
        Nip65.fromMap(key4.publicKey, {relay24.url: ReadWriteMarker.readWrite});

    Map<KeyPair, Nip65> nip65s = {
      key1: nip65ForKey1,
      key2: nip65ForKey2,
      key3: nip65ForKey3,
      key4: nip65ForKey4,
    };

    startServers() async {
      // r1 -> k1, k2, k3
      // r2 -> k1, k2
      // r3 -> k1
      // r4 -> k1,k4
      await Future.wait([
        relay21.startServer(
            nip65s: nip65s,
            textNotes: {}
              ..addAll(key1TextNotes)
              ..addAll(key2TextNotes)
              ..addAll(key3TextNotes)),
        relay22.startServer(
            nip65s: nip65s,
            textNotes: {}
              ..addAll(key1TextNotes)
              ..addAll(key2TextNotes)),
        relay23.startServer(
            nip65s: nip65s, textNotes: {}..addAll(key1TextNotes)),
        relay24.startServer(textNotes: key4TextNotes..addAll(key1TextNotes))
      ]);
    }

    stopServers() async {
      await Future.wait([
        relay21.stopServer(),
        relay22.stopServer(),
        relay23.stopServer(),
        relay24.stopServer(),
      ]);
    }

    test('query events from one seed relay', () async {
      await startServers();

      CacheManager cacheManager = MemCacheManager();
      RelayJitManager manager = RelayJitManager(
        seedRelays: [relay21.url, relay22.url, relay23.url, relay24.url],
        cacheManager: cacheManager,
      );

      EventVerifier eventVerifier = MockEventVerifier();
      NostrRequestJit request = NostrRequestJit.query("debug-get-events",
          eventVerifier: eventVerifier,
          filters: [
            Filter(
                kinds: [Nip01Event.TEXT_NODE_KIND], authors: [key4.publicKey]),
          ]);
      manager.handleRequest(request);

      //todo: implement EOSE
      request.responseStream.listen((event) {
        expectAsync1((event) {
          expect(event, key4TextNotes[key4]);
        })(event);
      });

      await Future.delayed(const Duration(seconds: 1));

      await stopServers();
    });

    test('query with inbox/outbox', () async {
      await startServers();
      CacheManager cacheManager = MemCacheManager();
      RelayJitManager manager = RelayJitManager(
        seedRelays: [],
        cacheManager: cacheManager,
      );
      EventVerifier eventVerifier = MockEventVerifier();

      // save nip65 data
      await cacheManager
          .saveEvents(nip65s.values.map((e) => e.toEvent()).toList());

      NostrRequestJit myquery = NostrRequestJit.query(
        "id",
        eventVerifier: eventVerifier,
        filters: [
          Filter(kinds: [
            Nip01Event.TEXT_NODE_KIND
          ], authors: [
            key1.publicKey,
            key2.publicKey,
            key3.publicKey,
            key4.publicKey,
          ]),
        ],
        desiredCoverage: 1,
      );
      manager.handleRequest(
        myquery,
      );

      List<Nip01Event> responses = [];
      myquery.responseStream.listen((event) {
        responses.add(event);
      });
      await Future.delayed(const Duration(seconds: 2));

      expect(responses.length, 4);
      // expect that all responses are there
      expect(responses.contains(key1TextNotes[key1]), true);
      expect(responses.contains(key2TextNotes[key2]), true);
      expect(responses.contains(key3TextNotes[key3]), true);
      expect(responses.contains(key4TextNotes[key4]), true);
    });
  });
}
