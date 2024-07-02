// ignore_for_file: avoid_print
import 'package:dart_ndk/nips/nip01/bip340.dart';
import 'package:dart_ndk/nips/nip01/event.dart';
import 'package:dart_ndk/nips/nip01/key_pair.dart';
import 'package:dart_ndk/nips/nip65/read_write_marker.dart';
import 'package:dart_ndk/relay_jit_manager/relay_jit.dart';
import 'package:dart_ndk/relay_jit_manager/relay_jit_manager.dart';
import 'package:flutter_test/flutter_test.dart';

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

  group('check doesRelayCoverPubkey()', () {
    // setup
    RelayJitManager relayJitManager = RelayJitManager();

    RelayJit relayReadOnly = RelayJit('wss://relay.camelus.app');
    relayReadOnly.assignedPubkeys
        .add(RelayJitAssignedPubkey(key1.publicKey, ReadWriteMarker.readOnly));

    RelayJit relayWriteOnly = RelayJit('wss://relay.camelus.app');
    relayWriteOnly.assignedPubkeys
        .add(RelayJitAssignedPubkey(key1.publicKey, ReadWriteMarker.writeOnly));

    RelayJit relayReadWrite = RelayJit('wss://relay.camelus.app');
    relayReadWrite.assignedPubkeys
        .add(RelayJitAssignedPubkey(key1.publicKey, ReadWriteMarker.readWrite));

    RelayJit relayUnassigend = RelayJit('wss://relay.camelus.app');

    relayJitManager.connectedRelays.add(relayReadOnly);
    relayJitManager.connectedRelays.add(relayWriteOnly);
    relayJitManager.connectedRelays.add(relayReadWrite);
    relayJitManager.connectedRelays.add(relayUnassigend);
    test('test readOnly relay', () {
      // check
      final resultRequestRo = RelayJitManager.doesRelayCoverPubkey(
          relayReadOnly, key1.publicKey, ReadWriteMarker.readOnly);

      final resultRequestWo = RelayJitManager.doesRelayCoverPubkey(
          relayReadOnly, key1.publicKey, ReadWriteMarker.writeOnly);

      final resultRequestRW = RelayJitManager.doesRelayCoverPubkey(
          relayReadOnly, key1.publicKey, ReadWriteMarker.readWrite);

      expect(resultRequestRo, true);
      expect(resultRequestWo, false);
      expect(resultRequestRW, false);
    });

    test('test writeOnly relay', () {
      // check
      final resultRequestRo = RelayJitManager.doesRelayCoverPubkey(
          relayWriteOnly, key1.publicKey, ReadWriteMarker.readOnly);

      final resultRequestWo = RelayJitManager.doesRelayCoverPubkey(
          relayWriteOnly, key1.publicKey, ReadWriteMarker.writeOnly);

      final resultRequestRW = RelayJitManager.doesRelayCoverPubkey(
          relayWriteOnly, key1.publicKey, ReadWriteMarker.readWrite);

      expect(resultRequestRo, false);
      expect(resultRequestWo, true);
      expect(resultRequestRW, false);
    });

    test('test readWrite relay', () {
      // check
      final resultRequestRo = RelayJitManager.doesRelayCoverPubkey(
          relayReadWrite, key1.publicKey, ReadWriteMarker.readOnly);

      final resultRequestWo = RelayJitManager.doesRelayCoverPubkey(
          relayReadWrite, key1.publicKey, ReadWriteMarker.writeOnly);

      final resultRequestRW = RelayJitManager.doesRelayCoverPubkey(
          relayReadWrite, key1.publicKey, ReadWriteMarker.readWrite);

      expect(resultRequestRo, true);
      expect(resultRequestWo, true);
      expect(resultRequestRW, true);
    });
    test('relay without assignments', () {
      // check
      final resultRequestRo = RelayJitManager.doesRelayCoverPubkey(
          relayUnassigend, key1.publicKey, ReadWriteMarker.readOnly);

      final resultRequestWo = RelayJitManager.doesRelayCoverPubkey(
          relayUnassigend, key1.publicKey, ReadWriteMarker.writeOnly);

      final resultRequestRW = RelayJitManager.doesRelayCoverPubkey(
          relayUnassigend, key1.publicKey, ReadWriteMarker.readWrite);

      expect(resultRequestRo, false);
      expect(resultRequestWo, false);
      expect(resultRequestRW, false);
    });
  });
}
