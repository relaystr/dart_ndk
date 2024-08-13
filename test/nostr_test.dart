// ignore_for_file: avoid_print

import 'package:dart_ndk/dart_ndk.dart';
import 'package:dart_ndk/shared/nips/nip01/bip340.dart';
import 'package:dart_ndk/shared/nips/nip01/key_pair.dart';
import 'package:flutter_test/flutter_test.dart';

import 'mocks/mock_event_verifier.dart';
import 'mocks/mock_relay.dart';

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
        createdAt: DateTime
            .now()
            .millisecondsSinceEpoch ~/ 1000);
  }

  Map<KeyPair, Nip01Event> key1TextNotes = {key1: textNote(key1)};
  Map<KeyPair, Nip01Event> key2TextNotes = {key2: textNote(key2)};
  Map<KeyPair, Nip01Event> key3TextNotes = {key3: textNote(key3)};
  Map<KeyPair, Nip01Event> key4TextNotes = {key4: textNote(key4)};

  group('Nostr', () {
    test('simple request engine LISTS', timeout: const Timeout(Duration(seconds: 3)), () async {
      MockRelay relay1 = MockRelay(name: "relay 1");
      await relay1.startServer(textNotes: key1TextNotes);

      OurApi nostr = OurApi(
        NdkConfig(
            eventVerifier: MockEventVerifier(),
            eventSigner: Bip340EventSigner(key1.privateKey, key1.publicKey),
            cache: MemCacheManager(),
            engine: NdkEngine.LISTS,
            bootstrapRelays: [relay1.url]),
      );

      final response = await nostr.requestNostrEvent(
          NdkRequest.query("random-id", filters: [
            Filter(kinds: [Nip01Event.TEXT_NODE_KIND], authors: [key1.publicKey])
          ]));

      expect(response.stream, emitsInAnyOrder(key1TextNotes.values));

      await relay1.stopServer();
    });
  });
}
