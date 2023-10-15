import 'dart:math';

import 'package:dart_ndk/nips/nip01/event.dart';
import 'package:dart_ndk/nips/nip65/nip65.dart';
import 'package:dart_ndk/nips/nip65/read_write_marker.dart';
import 'package:dart_ndk/pubkey_mapping.dart';
import 'package:dart_ndk/relay.dart';
import 'package:dart_ndk/relay_ranking.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final List<Nip01Event> exampleEventData = [
    Nip01Event(
        pubKey: "alice",
        kind: Nip65.kind,
        tags: [
          ["r", "wss://example1.com"],
          ["r", "wss://example2.com"],
          ["r", "wss://alice.example.com", "write"],
        ],
        content: ""),
    Nip01Event(
        pubKey: "bob",
        kind: Nip65.kind,
        tags: [
          ["r", "wss://example2.com"],
          ["r", "wss://example3.com"],
          ["r", "wss://bob.example.com", "write"],
        ],
        content: ""),
    Nip01Event(
        pubKey: "carol",
        kind: Nip65.kind,
        tags: [
          ["r", "wss://example3.com"],
          ["r", "wss://example4.com"],
          ["r", "wss://carol.example.com", "write"],
        ],
        content: ""),
    Nip01Event(
        pubKey: "dave",
        kind: Nip65.kind,
        tags: [
          ["r", "wss://example4.com"],
          ["r", "wss://example5.com"],
          ["r", "wss://dave.example.com", "write"],
        ],
        content: ""),
    Nip01Event(
        pubKey: "singleRelay",
        kind: Nip65.kind,
        tags: [
          ["r", "wss://singleRelay.example"],
        ],
        content: ""),
    Nip01Event(
        pubKey: "erin",
        kind: Nip65.kind,
        tags: [
          ["r", "wss://example5.com"],
          ["r", "wss://example6.com"],
          ["r", "wss://popular.example"],
        ],
        content: ""),
    Nip01Event(
        pubKey: "frank",
        kind: Nip65.kind,
        tags: [
          ["r", "wss://example6.com"],
          ["r", "wss://example7.com"],
          ["r", "wss://popular.example"],
        ],
        content: ""),
    Nip01Event(
        pubKey: "grace",
        kind: Nip65.kind,
        tags: [
          ["r", "wss://example7.com"],
          ["r", "wss://example8.com"],
          ["r", "wss://popular.example"],
        ],
        content: ""),
    Nip01Event(
        pubKey: "heidi",
        kind: Nip65.kind,
        tags: [
          ["r", "wss://example8.com"],
          ["r", "wss://example9.com"],
          ["r", "wss://popular.example"],
        ],
        content: ""),
  ];

  group('relay ranking basic tests', () {
    test('RelayRankingPubkey equality', () async {
      var obj1 =
          PubkeyMapping(pubKey: "alice", rwMarker: ReadWriteMarker.readWrite);
      var obj2 =
          PubkeyMapping(pubKey: "alice", rwMarker: ReadWriteMarker.readWrite);

      expect(obj1, equals(obj2));
    });

    test('Rank relays with empty connectedRelays list', () async {
      final pubkeys = ['alice', 'bob', 'carol'];
      final result = rankRelays(
        pubkeys: pubkeys,
        direction: ReadWriteMarker.readWrite,
        eventData: exampleEventData,
        connectedRelays: [],
        pubkeyCoverage: 2,
        rankingScoringConfig: RelayRankingScoringConfig(),
      );

      expect(result, isA<RelayRankingResult>());
      expect(result.ranking, isNotEmpty);
      expect(result.notCoveredPubkeys, isEmpty);
      expect(result.ranking.length, equals(4));
    });

    test('not covered pubkeys', () async {
      final pubkeys = ['alice', 'bob', 'carol', 'unknown'];
      final result = rankRelays(
        pubkeys: pubkeys,
        direction: ReadWriteMarker.readWrite,
        eventData: exampleEventData,
        connectedRelays: [],
        pubkeyCoverage: 2,
        rankingScoringConfig: RelayRankingScoringConfig(),
      );
      expect(result.notCoveredPubkeys.length, equals(1));
      expect(result.notCoveredPubkeys[0].pubkey, equals('unknown'));
      expect(result.notCoveredPubkeys[0].desiredCoverage, equals(2));
      expect(result.notCoveredPubkeys[0].missingCoverage, equals(2));
    });

    test('partial coverage', () async {
      final pubkeys = ['singleRelay'];
      final result = rankRelays(
        pubkeys: pubkeys,
        direction: ReadWriteMarker.readWrite,
        eventData: exampleEventData,
        connectedRelays: [],
        pubkeyCoverage: 2,
      );

      expect(result.notCoveredPubkeys.length, equals(1));
      expect(result.notCoveredPubkeys[0].desiredCoverage, equals(2));
      expect(result.notCoveredPubkeys[0].missingCoverage, equals(1));
    });

    test('results contain covered pubkeys', () async {
      final pubkeys = ['alice', 'bob', 'carol'];
      final result = rankRelays(
        pubkeys: pubkeys,
        direction: ReadWriteMarker.readWrite,
        eventData: exampleEventData,
        connectedRelays: [],
        pubkeyCoverage: 2,
      );

      final example1 = result.ranking.firstWhere((element) {
        return element.relay.url == 'wss://example1.com';
      });
      final example2 = result.ranking.firstWhere((element) {
        return element.relay.url == 'wss://example2.com';
      });
      final example3 = result.ranking.firstWhere((element) {
        return element.relay.url == 'wss://example3.com';
      });

      expect(
        example1.coveredPubkeys,
        contains(
          PubkeyMapping(pubKey: 'alice', rwMarker: ReadWriteMarker.readWrite),
        ),
      );
      expect(
        example1.coveredPubkeys,
        contains(
          PubkeyMapping(pubKey: 'alice', rwMarker: ReadWriteMarker.readWrite),
        ),
      );

      expect(
        example2.coveredPubkeys,
        contains(
          PubkeyMapping(pubKey: 'bob', rwMarker: ReadWriteMarker.readWrite),
        ),
      );
      expect(
        example3.coveredPubkeys,
        contains(
          PubkeyMapping(pubKey: 'bob', rwMarker: ReadWriteMarker.readWrite),
        ),
      );

      expect(
        example3.coveredPubkeys,
        contains(
          PubkeyMapping(pubKey: 'carol', rwMarker: ReadWriteMarker.readWrite),
        ),
      );
    });
  });

  group('read write direction', () {
    test('write only', () async {
      final pubkeys = ['alice', 'bob', 'carol'];
      final result = rankRelays(
        pubkeys: pubkeys,
        direction: ReadWriteMarker.writeOnly,
        eventData: exampleEventData,
        connectedRelays: [],
        pubkeyCoverage: 2,
      );

      // check that all directions are write
      for (var element in result.ranking) {
        for (var rankingPubkey in element.coveredPubkeys) {
          rankingPubkey.rwMarker == ReadWriteMarker.writeOnly;
        }
      }
    });

    test('read only', () async {
      final pubkeys = ['alice', 'bob', 'carol'];
      final result = rankRelays(
        pubkeys: pubkeys,
        direction: ReadWriteMarker.readOnly,
        eventData: exampleEventData,
        connectedRelays: [],
        pubkeyCoverage: 2,
      );

      // check that all directions are read
      for (var element in result.ranking) {
        for (var rankingPubkey in element.coveredPubkeys) {
          rankingPubkey.rwMarker == ReadWriteMarker.readOnly;
        }
      }
    });

    test('read/write', () async {
      final pubkeys = ['alice', 'bob', 'carol'];
      final result = rankRelays(
        pubkeys: pubkeys,
        direction: ReadWriteMarker.readWrite,
        eventData: exampleEventData,
        connectedRelays: [],
        pubkeyCoverage: 2,
      );

      // check that all directions are read/write
      for (var element in result.ranking) {
        for (var rankingPubkey in element.coveredPubkeys) {
          rankingPubkey.rwMarker == ReadWriteMarker.readWrite;
        }
      }
    });
  });

  group('exceptions', () {
    test('empty pubkeys', () async {
      expect(
        () => rankRelays(
          pubkeys: [],
          direction: ReadWriteMarker.readWrite,
          eventData: exampleEventData,
          connectedRelays: [],
          pubkeyCoverage: 2,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
    test('empty event data', () async {
      expect(
        () => rankRelays(
          pubkeys: ["something"],
          direction: ReadWriteMarker.readWrite,
          eventData: [],
          connectedRelays: [],
          pubkeyCoverage: 2,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
    test('coverage < 1', () async {
      expect(
        () => rankRelays(
          pubkeys: ["something"],
          direction: ReadWriteMarker.readWrite,
          eventData: exampleEventData,
          connectedRelays: [],
          pubkeyCoverage: 0,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('scoring', () {
    test('consistency', () async {
      final pubkeys = ['alice', 'bob', 'carol', 'dave'];
      final result = rankRelays(
        pubkeys: pubkeys,
        direction: ReadWriteMarker.readWrite,
        eventData: exampleEventData,
        connectedRelays: [],
        pubkeyCoverage: 2,
        rankingScoringConfig: const RelayRankingScoringConfig(),
      );

      final example1 = result.ranking.firstWhere((element) {
        return element.relay.url == 'wss://example1.com';
      });
      final example2 = result.ranking.firstWhere((element) {
        return element.relay.url == 'wss://example2.com';
      });
      final example3 = result.ranking.firstWhere((element) {
        return element.relay.url == 'wss://example3.com';
      });
      final example5 = result.ranking.firstWhere((element) {
        return element.relay.url == 'wss://example5.com';
      });

      expect(example2.score, equals(example3.score));
      expect(example1.score, equals(example5.score));
      expect(example1.score, lessThan(example2.score));
    });
  });

  group('scoring', () {
    test('consistency', () async {
      final pubkeys = ['alice', 'bob', 'carol', 'dave'];
      final result = rankRelays(
        pubkeys: pubkeys,
        direction: ReadWriteMarker.readWrite,
        eventData: exampleEventData,
        connectedRelays: [],
        pubkeyCoverage: 2,
        rankingScoringConfig: const RelayRankingScoringConfig(),
      );

      final example1 = result.ranking.firstWhere((element) {
        return element.relay.url == 'wss://example1.com';
      });
      final example2 = result.ranking.firstWhere((element) {
        return element.relay.url == 'wss://example2.com';
      });
      final example3 = result.ranking.firstWhere((element) {
        return element.relay.url == 'wss://example3.com';
      });
      final example5 = result.ranking.firstWhere((element) {
        return element.relay.url == 'wss://example5.com';
      });

      expect(example2.score, equals(example3.score));
      expect(example1.score, equals(example5.score));
      expect(example1.score, lessThan(example2.score));
    });

    // todo: discuss if this is the desired behavior or if readOnly means readOnly!!! in that context
    test(
      'prio readWriteRelays',
      () async {
        final pubkeys = ['alice', 'bob', 'carol', 'dave'];
        final result = rankRelays(
          pubkeys: pubkeys,
          direction: ReadWriteMarker.writeOnly,
          eventData: exampleEventData,
          connectedRelays: [],
          pubkeyCoverage: 2,
          rankingScoringConfig: const RelayRankingScoringConfig(),
        );

        final example1 = result.ranking.firstWhere((element) {
          return element.relay.url == 'wss://example1.com';
        });
        final example2 = result.ranking.firstWhere((element) {
          return element.relay.url == 'wss://example2.com';
        });

        final aliceWriteRelay = result.ranking.firstWhere((element) {
          return element.relay.url == 'wss://alice.example.com';
        });

        final bobWriteRelay = result.ranking.firstWhere((element) {
          return element.relay.url == 'wss://bob.example.com';
        });

        expect(bobWriteRelay.score, lessThan(example2.score));
        expect(aliceWriteRelay.score, lessThan(example1.score));
      },
      skip: true,
    );

    test('highest score', () async {
      final pubkeys = [
        'erin',
        'frank',
        'grace',
        'heidi',
      ];
      final result = rankRelays(
        pubkeys: pubkeys,
        direction: ReadWriteMarker.readWrite,
        eventData: exampleEventData,
        connectedRelays: [],
        pubkeyCoverage: 2,
        rankingScoringConfig: const RelayRankingScoringConfig(),
      );

      // get the highest score
      final highestScoreRelay = result.ranking.first;

      expect(highestScoreRelay.relay.url, equals("wss://popular.example"));
    });

    test('boost connected relays', () async {
      final pubkeys = [
        'erin',
        'frank',
        'grace',
        'heidi',
      ];
      final result = rankRelays(
        pubkeys: pubkeys,
        direction: ReadWriteMarker.readWrite,
        eventData: exampleEventData,
        connectedRelays: [
          Relay("wss://example1.com"),
          Relay("wss://example2.com"),
          Relay("wss://example5.com"),
          Relay("wss://example6.com"),
        ],
        pubkeyCoverage: 2,
        rankingScoringConfig: const RelayRankingScoringConfig(),
      );

      final example6 = result.ranking.firstWhere((element) {
        return element.relay.url == 'wss://example6.com';
      });

      final example7 = result.ranking.firstWhere((element) {
        return element.relay.url == 'wss://example7.com';
      });
      final example8 = result.ranking.firstWhere((element) {
        return element.relay.url == 'wss://example8.com';
      });

      expect(
        example7.score,
        equals(example8.score),
      );
      expect(
        example6.score,
        greaterThan(example7.score),
      );
      expect(
        example6.coveredPubkeys.length,
        equals(example7.coveredPubkeys.length),
      );
    });
  });
}
