import 'package:dart_ndk/shared/nips/nip01/client_msg.dart';
import 'package:dart_ndk/domain_layer/entities/filter.dart';
import 'package:dart_ndk/domain_layer/usecases/relay_jit_manager/relay_jit.dart';

import '../../../../presentation_layer/request_state.dart';
import '../../jit_engine.dart';

/// Strategy Description:
///
/// blast the request to all connected relays without adding the pubkey to the relay
///
class RelayJitBlastAllStrategy {
  static handleRequest({
    required RequestState requestState,
    required Filter filter,
    required List<RelayJit> connectedRelays,
    required bool closeOnEOSE,
  }) {
    for (var connectedRelay in connectedRelays) {
      // todo: do not overwrite the subscription if it already exists
      // link the request id to the relay
      connectedRelay.activeSubscriptions[requestState.id] =
          RelayActiveSubscription(requestState.id, [filter], requestState);

      // link back
      JitEngine.addRelayActiveSubscription(connectedRelay, requestState);

      var clientMsg = ClientMsg(
        ClientMsgType.REQ,
        id: requestState.id,
        filters: [filter],
      );
      connectedRelay.send(clientMsg);
    }
  }
}
