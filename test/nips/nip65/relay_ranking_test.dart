import 'dart:math';

import 'dart:developer' as developer;

import 'package:collection/collection.dart';
import 'package:dart_ndk/nips/nip01/event.dart';
import 'package:dart_ndk/nips/nip65/nip65.dart';
import 'package:dart_ndk/nips/nip65/read_write_marker.dart';
import 'package:dart_ndk/nips/nip65/relay_ranking.dart';
import 'package:dart_ndk/relay_jit_manager/relay_jit_request_strategies/relay_jit_pubkey_strategy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('relayRanking', () {
    List<Nip65> nip65Data = [];
    List<CoveragePubkey> searchingPubkeys = [];

    // 0-9 have good nip65 data
    // 10-19 have no nip65 data
    // 20-29 have random nip65 data
    for (var i = 0; i < 30; i++) {
      searchingPubkeys.add(CoveragePubkey('pubkeyUser$i', 2, 2));
    }

    for (var i = 0; i < 10; i++) {
      final event = Nip01Event(
        createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        pubKey: 'pubkeyUser$i',
        kind: Nip65.KIND,
        content: "",
        tags: [
          ['r', 'wss://relayA.read', 'read'],
          ['r', 'wss://relayB.write', 'write'],
          ['r', 'wss://relayC.readwrite'],
          ['invalid'],
        ],
      );
      final nip65 = Nip65.fromEvent(event);
      nip65Data.add(nip65);
    }

    // add random nip65 events
    for (var i = 20; i < 30; i++) {
      final event = Nip01Event(
        createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        pubKey: 'pubkeyUser$i',
        kind: Nip65.KIND,
        content: "",
        tags: getRandomTags(),
      );
      final nip65 = Nip65.fromEvent(event);
      nip65Data.add(nip65);
    }

    test('basic scoring test - readOnly', () {
      final result = rankRelays(
        searchingPubkeys: searchingPubkeys,
        direction: ReadWriteMarker.readOnly,
        eventData: nip65Data,
      );

      expect(result.notCoveredPubkeys.length, greaterThanOrEqualTo(10));
      expect(result.ranking.length, greaterThanOrEqualTo(10));

      // check that covered pubkeys are in the result
      for (var i = 0; i < 10; i++) {
        int foundPubkey = 0;
        result.ranking.forEach((element) {
          bool found = element.coveredPubkeys.contains(searchingPubkeys[i]);
          if (found) {
            foundPubkey++;
          }
        });
        expect(foundPubkey, 2);
      }

      // check that the notCoveredPubkeys are the ones that have no data
      for (var i = 10; i < 20; i++) {
        expect(result.notCoveredPubkeys.contains(searchingPubkeys[i]), true);
      }
    });
  });
}

final _random = Random();
String getRandomString(int length) => String.fromCharCodes(
    Iterable.generate(length, (_) => _random.nextInt(26) + 97));

String getRandomReadWrite() {
  final options = ['read', 'write', 'readwrite'];
  return options[_random.nextInt(options.length)];
}

getRandomTags() {
  final tags = [
    [
      'r',
      'wss://relay-${getRandomString(3)}.${getRandomReadWrite()}',
      getRandomReadWrite()
    ],
    [
      'r',
      'wss://relay-${getRandomString(3)}.${getRandomReadWrite()}',
      getRandomReadWrite()
    ],
    ['r', 'wss://relay-${getRandomString(3)}.${getRandomReadWrite()}'],
  ];
  return tags;
}
