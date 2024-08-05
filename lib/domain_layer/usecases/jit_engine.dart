import 'dart:async';

import 'package:dart_ndk/domain_layer/repositories/cache_manager.dart';
import 'package:dart_ndk/presentation_layer/global_state.dart';
import 'package:dart_ndk/presentation_layer/request_state.dart';

import 'package:dart_ndk/shared/logger/logger.dart';

import 'package:dart_ndk/domain_layer/entities/nip_01_event.dart';
import 'package:dart_ndk/domain_layer/entities/read_write_marker.dart';
import 'package:dart_ndk/domain_layer/usecases/relay_jit_manager/relay_jit.dart';
import 'package:dart_ndk/domain_layer/usecases/relay_jit_manager/relay_jit_request_strategies/relay_jit_blast_all_strategy.dart';
import 'package:dart_ndk/domain_layer/usecases/relay_jit_manager/relay_jit_request_strategies/relay_jit_pubkey_strategy.dart';

import 'dart:developer' as developer;

import '../../shared/helpers/relay_helper.dart';
import '../entities/connection_source.dart';
import '../repositories/event_signer.dart';
import '../repositories/event_verifier.dart';

class JitEngine with Logger {
  EventVerifier eventVerifier;
  EventSigner eventSigner;
  CacheManager cache;
  List<String> ignoreRelays;
  List<String> seedRelays;

  GlobalState globalState;

  final Completer<void> _seedRelaysCompleter = Completer<void>();
  get seedRelaysConnected => _seedRelaysCompleter.future;

  JitEngine({
    required this.eventVerifier,
    required this.eventSigner,
    required this.cache,
    required this.ignoreRelays,
    required this.seedRelays,
    required this.globalState,
  }) {
    _connectSeedRelays(cleanRelayUrls(seedRelays));
  }

  _connectSeedRelays(List<String> seedRelays) async {
    List<Future> futures = [];
    // init seed relays
    for (var seedRelay in seedRelays) {
      var relay = RelayJit(
        url: seedRelay,
        onMessage: onMessage,
      );
      var future = relay
          .connect(connectionSource: ConnectionSource.SEED)
          .then((success) => {
                if (success) {globalState.connectedRelays.add(relay)}
              });
      futures.add(future);
    }
    // wait for all futures to complete
    Future.wait(futures).whenComplete(() {
      _seedRelaysCompleter.complete();
    });
  }

  /// If you request anything from the nostr network put it here and
  /// the relay jit manager will try to find the right relay and use it
  /// if no relay is found the request will be blasted to all connected relays (on start seed Relays)
  void handleRequest(
    RequestState requestState,
  ) async {
    await seedRelaysConnected;

    final ndkRequest = requestState.requestConfig;

    //clean ignore relays
    List<String> cleanIgnoreRelays = cleanRelayUrls(ignoreRelays);

    /// ["REQ", <subscription_id>, <filters1>, <filters2>, ...]
    /// user can provide multiple filters
    for (var filter in ndkRequest.filters) {
      // filter different types of filters/requests because each requires a different strategy

      if ((filter.authors != null && filter.authors!.isNotEmpty)) {
        RelayJitPubkeyStrategy.handleRequest(
          requestState: requestState,
          cacheManager: cache,
          filter: filter,
          connectedRelays: this.globalState.connectedRelays,
          desiredCoverage: ndkRequest.desiredCoverage,
          closeOnEOSE: ndkRequest.closeOnEOSE,
          direction: ReadWriteMarker
              .writeOnly, // the author should write on the persons write relays
          ignoreRelays: cleanIgnoreRelays,
          onMessage: onMessage,
        );
        continue;
      }

      if (filter.pTags?.isNotEmpty != null && filter.pTags!.isNotEmpty) {
        RelayJitPubkeyStrategy.handleRequest(
          requestState: requestState,
          cacheManager: cache,
          filter: filter,
          connectedRelays: this.globalState.connectedRelays,
          desiredCoverage: ndkRequest.desiredCoverage,
          closeOnEOSE: ndkRequest.closeOnEOSE,
          direction: ReadWriteMarker
              .readOnly, // others should mention on the persons read relays
          ignoreRelays: cleanIgnoreRelays,
          onMessage: onMessage,
        );
        continue;
      }

      if (filter.search != null) {
        throw UnimplementedError("search filter not implemented yet");
      }

      if (filter.ids != null) {
        throw UnimplementedError("ids filter not implemented yet");
      }

      /// unknown filter strategy, blast to all connected relays
      RelayJitBlastAllStrategy.handleRequest(
        requestState: requestState,
        filter: filter,
        connectedRelays: this.globalState.connectedRelays,
        closeOnEOSE: requestState.requestConfig.closeOnEOSE,
      );
    }
  }

  handleEventPublish(Nip01Event nostrEvent) async {
    await seedRelaysConnected;
    throw UnimplementedError();
  }

  // close a relay subscription, the relay connection will be kept open and closed automatically (garbage collected)
  //todo: this could be moved to the request object
  handleCloseSubscription(String id) async {
    await seedRelaysConnected;
    throw UnimplementedError();
  }

  static doesRelayCoverPubkey(
    RelayJit relay,
    String pubkey,
    ReadWriteMarker direction,
  ) {
    for (RelayJitAssignedPubkey assignedPubkey in relay.assignedPubkeys) {
      if (assignedPubkey.pubkey == pubkey) {
        switch (direction) {
          case ReadWriteMarker.readOnly:
            return assignedPubkey.direction.isRead;
          case ReadWriteMarker.writeOnly:
            return assignedPubkey.direction.isWrite;
          case ReadWriteMarker.readWrite:
            return assignedPubkey.direction == ReadWriteMarker.readWrite;
          default:
            return false;
        }
      }
    }
    return false;
  }

  /// verify event and add to response stream
  void onMessage(Nip01Event event, RequestState requestState) async {
    // verify event
    bool validSig = await eventVerifier.verify(event);

    if (!validSig) {
      Logger.log.w("🔑⛔ Invalid signature on event: $event");
      return;
    }
    event.validSig = validSig;

    // add to response stream
    requestState.controller.add(event);
  }

  static void onEoseReceivedFromRelay(RequestState requestState) async {
    // check if all subscriptions received EOSE (async) at the current time

    for (var sub in requestState.activeRelaySubscriptions.values) {
      await sub.activeSubscriptions[requestState.id]?.eoseReceived;
    }
    requestState.controller.close();
  }

  /// addRelayActiveSubscription to request
  static void addRelayActiveSubscription(
      RelayJit relay, RequestState requestState) {
    requestState.activeRelaySubscriptions[relay.url] = relay;
  }
}
