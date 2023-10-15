import 'package:dart_ndk/nips/nip01/event.dart';
import 'package:dart_ndk/nips/nip65/nip65.dart';
import 'package:dart_ndk/nips/nip65/read_write_marker.dart';
import 'package:dart_ndk/pubkey_mapping.dart';
import 'package:dart_ndk/relay.dart';

///
/// pubkeys: the list of pubkeys where you want relays to
/// direction: the read/write direction to rank for
/// eventData: this list should contain nip65 events as well as kind3 events and tagHint events
/// connectedRelays: the list of relays that are already connected (they will be ranked higher)
/// pubkeyCoverage: the minimum coverage for each pubkey
/// rankingConfig: if you want to modify, boost certain scores
///
RelayRankingResult rankRelays({
  required List<String> pubkeys,
  required ReadWriteMarker direction,
  required List<Nip01Event> eventData,
  List<Relay> connectedRelays = const [],
  int pubkeyCoverage = 2,
  RelayRankingScoringConfig rankingScoringConfig =
      const RelayRankingScoringConfig(),
}) {
  if (pubkeys.isEmpty) {
    throw ArgumentError('pubkeys cannot be empty');
  }

  if (pubkeyCoverage < 1) {
    throw ArgumentError('pubkeyCoverage cannot be less than 1');
  }

  if (eventData.isEmpty) {
    throw ArgumentError('eventData cannot be empty');
  }

  final List<NotCoveredPubkey> notCoveredPubkeys = [];

  Map<String, int> pubkeysCoverage = {};
  // initialize pubkeysCoverage
  for (String pubkey in pubkeys) {
    pubkeysCoverage[pubkey] = pubkeyCoverage;
  }

  // extract all relays

  List<RelayRanking> relayRanking = [];

  List<Nip01Event> cleanedEventData = _keepOnlyLatestEventsForPubkey(eventData);

  for (Nip01Event event in cleanedEventData) {
    if (event.kind != Nip65.kind) continue;

    for (dynamic relayTag in event.tags) {
      if (relayTag[0] != 'r') continue;
      if (relayTag[1] == null) continue;

      // check if relay is already in list by url
      int index = relayRanking.indexWhere(
        (element) => element.relay.url == relayTag[1],
      );
      if (index != -1) {
        // relay is already in list, add pubkey to coveredPubkeys
        relayRanking[index].coveredPubkeys.add(
              PubkeyMapping(
                pubKey: event.pubKey,
                rwMarker: _extractDirectionFromString(
                    _nullIfOutOfBounds(relayTag, 2)),
              ),
            );
        continue;
      }

      // relay is not in list, add it
      relayRanking.add(
        RelayRanking(
          relay: Relay(relayTag[1] as String),
          score: -1,
          coveredPubkeys: [
            PubkeyMapping(
              pubKey: event.pubKey,
              rwMarker:
                  _extractDirectionFromString(_nullIfOutOfBounds(relayTag, 2)),
            ),
          ],
        ),
      );
    }
  }

  // relayRanking is now populated but all scores are -1
  // now we calculate the score for each relay

  for (RelayRanking relayRank in relayRanking) {
    // count how many pubkeys are covered by this relay that i am looking for
    int coveredPubkeysCount = 0;
    for (PubkeyMapping relayRankingPubkey in relayRank.coveredPubkeys) {
      if (pubkeys.contains(relayRankingPubkey.pubKey)) {
        coveredPubkeysCount += 1;
      }
    }

    relayRank.score = coveredPubkeysCount * rankingScoringConfig.nip05Score;

    // boost if relay already connected
    if (connectedRelays.contains(relayRank.relay)) {
      relayRank.score += rankingScoringConfig.connectedRelaysScore;
    }
  }

  // sort relayRanking by score
  relayRanking.sort((a, b) => b.score.compareTo(a.score));

  final List<RelayRanking> finalRanking = [];

  // iterate over all pubkeys
  for (MapEntry<String, int> pubkeyCoverage in pubkeysCoverage.entries) {
    final String myPubkey = pubkeyCoverage.key;
    int myCoverage = pubkeyCoverage.value;
    final ReadWriteMarker myDirection = direction;

    // iterate over all found nip65 relays sorted by score
    for (RelayRanking relayRank in relayRanking) {
      // stop searching if desired coverage is reached
      if (myCoverage == 0) break;

      // check if relayRank contains myPubkey
      if (relayRank.coveredPubkeys
          .contains(PubkeyMapping(pubKey: myPubkey, rwMarker: myDirection))) {
        // relayRank already contains myPubkey, add it to finalRanking
        myCoverage -= 1;
        // add relayRank to finalRanking if it is not already in there
        if (!finalRanking.contains(relayRank)) {
          finalRanking.add(relayRank);
        }
      }
    }

    // check if desired coverage is reached
    if (myCoverage > 0) {
      // desired coverage is not reached, add to notCoveredPubkeys
      notCoveredPubkeys.add(
        NotCoveredPubkey(
          pubkey: myPubkey,
          desiredCoverage: pubkeyCoverage.value,
          missingCoverage: myCoverage,
        ),
      );
    }
  }

  return RelayRankingResult(
    ranking: finalRanking,
    notCoveredPubkeys: notCoveredPubkeys,
  );
}

ReadWriteMarker _extractDirectionFromString(String? marker) {
  switch (marker) {
    case 'read':
      return ReadWriteMarker.readOnly;
    case 'write':
      return ReadWriteMarker.writeOnly;
    default:
      return ReadWriteMarker.readWrite;
  }
}

List<Nip01Event> _keepOnlyLatestEventsForPubkey(List<Nip01Event> events) {
  // sort events by timestamp
  events.sort((a, b) => a.createdAt.compareTo(b.createdAt));

  // keep only latest event for each pubkey
  List<Nip01Event> latestEvents = [];
  for (Nip01Event event in events) {
    int index =
        latestEvents.indexWhere((element) => element.pubKey == event.pubKey);
    if (index == -1) {
      // event not found, add it
      latestEvents.add(event);
    } else {
      // event found, replace it
      latestEvents[index] = event;
    }
  }

  return latestEvents;
}

dynamic _nullIfOutOfBounds(List<dynamic> list, int index) {
  try {
    return list[index];
  } catch (e) {
    return null;
  }
}

class RelayRankingScoringConfig {
  final int connectedRelaysScore;
  final int nip65Score;
  final int nip05Score;
  final int kind03Score;
  final int lastFetchedScore;
  final int tagHintScore;

  const RelayRankingScoringConfig({
    this.connectedRelaysScore = 60,
    this.nip65Score = 50,
    this.nip05Score = 40,
    this.kind03Score = 30,
    this.lastFetchedScore = 20,
    this.tagHintScore = 10,
  });
}

class RelayRankingResult {
  final List<RelayRanking> ranking;
  final List<NotCoveredPubkey> notCoveredPubkeys;

  RelayRankingResult({
    required this.ranking,
    required this.notCoveredPubkeys,
  });
}

class NotCoveredPubkey {
  final String pubkey;
  final int missingCoverage;
  final int desiredCoverage;

  NotCoveredPubkey({
    required this.pubkey,
    required this.desiredCoverage,
    required this.missingCoverage,
  });
}

class RelayRanking {
  final Relay relay;
  int score;
  final List<PubkeyMapping> coveredPubkeys;

  // overwrite == operator
  @override
  bool operator ==(covariant RelayRanking other) {
    return relay == other.relay;
  }

  @override
  int get hashCode => relay.hashCode;

  RelayRanking({
    required this.relay,
    required this.score,
    required this.coveredPubkeys,
  });
}
