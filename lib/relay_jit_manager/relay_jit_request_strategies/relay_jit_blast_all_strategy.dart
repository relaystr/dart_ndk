import 'package:dart_ndk/nips/nip01/client_msg.dart';
import 'package:dart_ndk/nips/nip01/filter.dart';
import 'package:dart_ndk/relay_jit_manager/relay_jit.dart';
import 'package:dart_ndk/relay_jit_manager/request_jit.dart';

/// Strategy Description:
///
/// blast the request to all connected relays without adding the pubkey to the relay
///
class RelayJitBlastAllStrategy {
  static handleRequest({
    required NostrRequestJit originalRequest,
    required Filter filter,
    required List<RelayJit> connectedRelays,
    required bool closeOnEOSE,
  }) {
    for (var connectedRelay in connectedRelays) {
      // todo: do not overwrite the subscription if it already exists
      // link the request id to the relay
      connectedRelay.activeSubscriptions[originalRequest.id] =
          RelayActiveSubscription(
              originalRequest.id, [filter], originalRequest);
      // link back
      originalRequest.addRelayActiveSubscription(connectedRelay);

      var clientMsg = ClientMsg(
        ClientMsgType.REQ,
        id: originalRequest.id,
        filters: [filter],
      );
      connectedRelay.send(clientMsg);
    }
  }
}
