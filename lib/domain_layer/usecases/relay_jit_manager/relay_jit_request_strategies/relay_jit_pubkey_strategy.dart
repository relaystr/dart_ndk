import 'package:dart_ndk/domain_layer/repositories/cache_manager.dart';
import 'package:dart_ndk/shared/logger/logger.dart';
import 'package:dart_ndk/shared/nips/nip01/client_msg.dart';
import 'package:dart_ndk/domain_layer/entities/nip_01_event.dart';
import 'package:dart_ndk/domain_layer/entities/filter.dart';
import 'package:dart_ndk/domain_layer/entities/nip_65.dart';
import 'package:dart_ndk/domain_layer/entities/read_write_marker.dart';
import 'package:dart_ndk/shared/nips/nip65/relay_ranking.dart';
import 'package:dart_ndk/domain_layer/usecases/relay_jit_manager/relay_jit.dart';
import 'package:dart_ndk/domain_layer/usecases/jit_engine.dart';
import 'package:dart_ndk/domain_layer/usecases/relay_jit_manager/relay_jit_request_strategies/relay_jit_blast_all_strategy.dart';

import '../../../../presentation_layer/request_state.dart';
import '../../../entities/connection_source.dart';

/// Strategy Description:
///
/// 1.) look for connected relays that cover the pubkey
///
/// 2.) if pubkey match, split and send out the splitted (only that pubkey) request; decrease desiredCoverage for pubkey
///
/// 3.) add the original request id to subscriptionHolder
///
/// 4.) continue search
///
/// 5.) for not covered pubkeys look for relays in nip65 data, while boosting already connected relays
///
/// 6.) case=> if no relay is found, blast the request to all connected relays
///
/// 7.) case=> good relay found add to connected, and send out the request
///

class RelayJitPubkeyStrategy with Logger {
  static handleRequest({
    required RequestState requestState,

    // specific filter (only one for this request)
    required Filter filter,
    required List<RelayJit> connectedRelays,

    /// used to get the nip65 data if its necessary to look for not covered pubkeys
    required CacheManager cacheManager,
    required int desiredCoverage,
    required bool closeOnEOSE,
    required ReadWriteMarker direction,
    required List<String> ignoreRelays,

    // on message async funciton
    required Function(Nip01Event, RequestState) onMessage,
  }) {
    List<String> combindedPubkeys = [
      ...?filter.authors,
      ...?filter.pTags
    ]; // not perfect but probably fine, request got split earlier

    // init coveragePubkeys
    List<CoveragePubkey> coveragePubkeys = [];

    for (var pubkey in combindedPubkeys) {
      coveragePubkeys
          .add(CoveragePubkey(pubkey, desiredCoverage, desiredCoverage));
    }

    // look for connected relays that cover the pubkey
    for (var connectedRelay in connectedRelays) {
      var coveredPubkeysForRelay = <String>[];

      for (var coveragePubkey in coveragePubkeys) {
        if (JitEngine.doesRelayCoverPubkey(
            connectedRelay, coveragePubkey.pubkey, direction)) {
          coveredPubkeysForRelay.add(coveragePubkey.pubkey);
          coveragePubkey.missingCoverage--;
        }
      }

      connectedRelay.touched++;
      if (coveredPubkeysForRelay.isEmpty) {
        continue;
      }
      connectedRelay.touchUseful++;

      /// create splitFilter that only contains the pubkeys for the relay
      Filter splitFilter = _splitFilter(filter, coveredPubkeysForRelay);

      _sendRequestToSocket(connectedRelay, requestState, [splitFilter]);

      // clear out fully covered pubkeys
      _removeFullyCoveredPubkeys(coveragePubkeys);
    }

    if (coveragePubkeys.isEmpty) {
      // we are done
      // all pubkeys are covered by already connected relays
      return;
    }

    _findRelaysForUnresolvedPubkeys(
      requestState: requestState,
      filter: filter,
      coveragePubkeys: coveragePubkeys,
      connectedRelays: connectedRelays,
      cacheManager: cacheManager,
      desiredCoverage: desiredCoverage,
      direction: direction,
      ignoreRelays: ignoreRelays,
      closeOnEOSE: closeOnEOSE,
      onMessage: onMessage,
    );

    _removeFullyCoveredPubkeys(coveragePubkeys);

    if (coveragePubkeys.isEmpty) {
      // we are done
      return;
    }

    Filter notFoundFilter = _splitFilter(filter,
        coveragePubkeys.map((e) => e.pubkey).toList()); // split the filter
    //  send out not found request to all connected relays
    RelayJitBlastAllStrategy.handleRequest(
      requestState: requestState,
      filter: notFoundFilter,
      connectedRelays: connectedRelays,
      closeOnEOSE: closeOnEOSE,
    );
  }

  // looks in nip65 data for not covered pubkeys
  // the result is relay candidates
  // connects to these candidates and sends out the request
  static void _findRelaysForUnresolvedPubkeys(
      {required RequestState requestState,
      required Filter filter,
      required List<CoveragePubkey> coveragePubkeys,
      required List<RelayJit> connectedRelays,
      required CacheManager cacheManager,
      required int desiredCoverage,
      required ReadWriteMarker direction,
      required List<String> ignoreRelays,
      required bool closeOnEOSE,
      required Function(Nip01Event, RequestState) onMessage}) {
    /// ### resolve not covered pubkeys ###
    // look in nip65 data for not covered pubkeys
    List<Nip65> nip65Data = _getNip65Data(
        coveragePubkeys.map((e) => e.pubkey).toList(), cacheManager);

    // by finding the best relays to connect and send out the request
    RelayRankingResult relayRanking = rankRelays(
      direction: direction,
      searchingPubkeys: coveragePubkeys,
      eventData: nip65Data,
      boostRelays: connectedRelays.map((e) => e.url).toList(),
      ignoreRelays: ignoreRelays,
    );

    // update coveragePubkeys to the not found ones
    // this is need so early on so the not found pubkeys can be blasted to all connected relays
    coveragePubkeys = relayRanking.notCoveredPubkeys;

    // connect to the new found relays and send out the request
    for (var relayCandidate in relayRanking.ranking) {
      if (relayCandidate.score <= 0) {
        continue;
      }
      // check if the relayCandidate is already connected
      bool alreadyConnected = connectedRelays
          .any((element) => element.url == relayCandidate.relayUrl);

      if (!alreadyConnected) {
        RelayJit newRelay = RelayJit(
          url: relayCandidate.relayUrl,
          onMessage: onMessage,
        );

        // add the relay to the connected relays
        connectedRelays.add(newRelay);

        newRelay
            .connect(connectionSource: ConnectionSource.PUBKEY_STRATEGY)
            .then((success) => {
                  if (success)
                    {
                      // add the pubkeys to the relay
                      newRelay.addPubkeysToAssignedPubkeys(
                          relayCandidate.coveredPubkeys
                              .map((e) => e.pubkey)
                              .toList(),
                          direction),

                      // send out the request
                      _sendRequestToSocket(newRelay, requestState, [
                        _splitFilter(
                            filter,
                            relayCandidate.coveredPubkeys
                                .map((e) => e.pubkey)
                                .toList())
                      ])
                    },
                  if (!success)
                    {
                      Logger.log.w(
                          "Could not connect to relay: ${newRelay.url} - errorHandling"),
                      _connectionErrorHandling(
                        errorRelay: newRelay,
                        requestState: requestState,
                        filter: filter,
                        connectedRelays: connectedRelays,
                        cacheManager: cacheManager,
                        desiredCoverage: desiredCoverage,
                        direction: direction,
                        ignoreRelays: ignoreRelays,
                        closeOnEOSE: closeOnEOSE,
                        onMessage: onMessage,
                      ),
                    }
                });
      }

      if (alreadyConnected) {
        RelayJit connectedRelay = connectedRelays
            .firstWhere((element) => element.url == relayCandidate.relayUrl);

        connectedRelay.addPubkeysToAssignedPubkeys(
            relayCandidate.coveredPubkeys.map((e) => e.pubkey).toList(),
            direction);
        _sendRequestToSocket(connectedRelay, requestState, [
          _splitFilter(filter,
              relayCandidate.coveredPubkeys.map((e) => e.pubkey).toList())
        ]);
      }
    }
  }

  static List<Nip65> _getNip65Data(
      List<String> pubkeys, CacheManager cacheManager) {
    List<Nip01Event> events =
        cacheManager.loadEvents(kinds: [Nip65.KIND], pubKeys: pubkeys);

    List<Nip65> nip65Data = [];
    for (var event in events) {
      nip65Data.add(Nip65.fromEvent(event));
    }
    return nip65Data;
  }

  // adds the relay to ignoreRelays and retries the request for assigned pubkeys to this relay
  static void _connectionErrorHandling(
      {required RelayJit errorRelay,
      required RequestState requestState,
      required Filter filter,
      required List<RelayJit> connectedRelays,
      required CacheManager cacheManager,
      required int desiredCoverage,
      required bool closeOnEOSE,
      required ReadWriteMarker direction,
      required List<String> ignoreRelays,
      required Function(Nip01Event, RequestState) onMessage}) {
    // cleanup
    connectedRelays.remove(errorRelay);

    // add to ignoreRelays
    ignoreRelays.add(errorRelay.url);

    List<CoveragePubkey> unresolvedPubkeysOfRelay = errorRelay.assignedPubkeys
        .map((e) => CoveragePubkey(e.pubkey, 1, 1))
        .toList();

    _findRelaysForUnresolvedPubkeys(
      requestState: requestState,
      filter: filter,
      coveragePubkeys: unresolvedPubkeysOfRelay,
      connectedRelays: connectedRelays,
      cacheManager: cacheManager,
      desiredCoverage: desiredCoverage,
      direction: direction,
      ignoreRelays: ignoreRelays,
      closeOnEOSE: closeOnEOSE,
      onMessage: onMessage,
    );
  }
}

_removeFullyCoveredPubkeys(List<CoveragePubkey> coveragePubkeys) {
  coveragePubkeys.removeWhere((element) => element.missingCoverage == 0);
}

void _sendRequestToSocket(
    RelayJit connectedRelay, RequestState requestState, List<Filter> filters) {
  // check if the subscription already exists and if its need to be modified
  if (connectedRelay.hasActiveSubscription(requestState.id)) {
    // modify the existing subscription

    // add the filters to the existing subscription
    // to concat the filters is probably not the best way to do it but should be fine
    connectedRelay.activeSubscriptions[requestState.id]!.filters
        .addAll(filters);

    // send out the updated request
    connectedRelay.send(ClientMsg(
      ClientMsgType.REQ,
      id: requestState.id,
      filters: connectedRelay.activeSubscriptions[requestState.id]!.filters,
    ));

    return;
  }
  // create a new subscription

  // todo: do not overwrite the subscription if it already exists
  // link the request id to the relay
  connectedRelay.activeSubscriptions[requestState.id] = RelayActiveSubscription(
    requestState.id,
    filters,
    requestState,
  );

  // link back
  JitEngine.addRelayActiveSubscription(connectedRelay, requestState);

  // send out the request
  connectedRelay.send(ClientMsg(
    ClientMsgType.REQ,
    id: requestState.id,
    filters: filters,
  ));
}

Filter _splitFilter(Filter filter, List<String> pubkeysToInclude) {
  if (filter.authors != null && filter.authors!.isNotEmpty) {
    return filter.cloneWithAuthors(pubkeysToInclude);
  } else if (filter.pTags != null && filter.pTags!.isNotEmpty) {
    return filter.cloneWithPTags(pubkeysToInclude);
  } else {
    throw Exception("filter does not contain authors or pTags");
  }
}

class CoveragePubkey {
  final String pubkey;
  int desiredCoverage;
  int missingCoverage;

  CoveragePubkey(this.pubkey, this.desiredCoverage, this.missingCoverage);
}
