import 'dart:math';

import 'package:dart_ndk/domain_layer/entities/nip_65.dart';
import 'package:dart_ndk/domain_layer/entities/read_write_marker.dart';

import 'package:dart_ndk/domain_layer/usecases/relay_jit_manager/relay_jit_request_strategies/relay_jit_pubkey_strategy.dart';

RelayRankingResult rankRelays({
  required List<CoveragePubkey> searchingPubkeys,
  required ReadWriteMarker direction,
  required List<Nip65> eventData,
  // usually to boost already connected relays
  List<String> boostRelays = const [],
  // aka banned relays
  List<String> ignoreRelays = const [],
  // on found value
  int foundBoost = 1,
  // boost value
  int boost = 10,
}) {
  // string is the relay url
  Map<String, TestRelayHit> relayHits = {};

  // string is the pubkey
  Map<String, CoveragePubkey> searchingPubkeysMap = {
    for (var e in searchingPubkeys) e.pubkey: e,
  };

  // count for each event data (pubkey)

  for (var event in eventData) {
    // not interested in this pubkey
    if (searchingPubkeys.any((element) => element.pubkey == event.pubKey) ==
        false) {
      continue;
    }

    for (var relay in event.relays.keys) {
      if (ignoreRelays.contains(relay)) {
        continue;
      }
      // check for direction
      if (!event.relays[relay]!.isPartialMatch(direction)) {
        continue;
      }
      // check if a new relay is needed
      if (searchingPubkeysMap[event.pubKey]!.missingCoverage <= 0) {
        continue;
      }

      // check if relay is already in relayHits
      if (relayHits.containsKey(relay)) {
        relayHits[relay]!.hitPubkeys.add(event.pubKey);
        relayHits[relay]!.score += foundBoost;
      } else {
        relayHits[relay] = TestRelayHit(
          score: foundBoost,
          hitPubkeys: [event.pubKey],
        );
      }
      // decrease missing coverage
      searchingPubkeysMap[event.pubKey]!.missingCoverage -= 1;
    }
  }

  // boost already connected relays
  for (var relay in boostRelays) {
    if (relayHits.containsKey(relay)) {
      relayHits[relay]!.score += boost;
    }
  }

  // assemble result
  List<RelayRanking> ranking = [];
  List<CoveragePubkey> notCoveredPubkeys = [];

  // not covered pubkeys
  for (var pubkey in searchingPubkeysMap.entries) {
    if (pubkey.value.missingCoverage > 0) {
      notCoveredPubkeys.add(pubkey.value);
    }
  }

  // populate ranking
  for (var relayHit in relayHits.entries) {
    if (relayHit.value.score > 0) {
      ranking.add(
        RelayRanking(
          relayUrl: relayHit.key,
          score: relayHit.value.score,
          coveredPubkeys: searchingPubkeys
              .where((element) =>
                  relayHit.value.hitPubkeys.contains(element.pubkey))
              .toList(),
        ),
      );
    }
  }

  return RelayRankingResult(
    ranking: ranking,
    notCoveredPubkeys: notCoveredPubkeys,
  );
}

class TestRelayHit {
  int score = 0;
  List<String> hitPubkeys = [];
  TestRelayHit({required this.score, required this.hitPubkeys});
}

class RelayRankingResult {
  final List<RelayRanking> ranking;
  final List<CoveragePubkey> notCoveredPubkeys;

  RelayRankingResult({
    required this.ranking,
    required this.notCoveredPubkeys,
  });
}

class RelayRanking {
  final String relayUrl;
  int score;
  final List<CoveragePubkey> coveredPubkeys;

  RelayRanking({
    required this.relayUrl,
    required this.score,
    required this.coveredPubkeys,
  });
}
