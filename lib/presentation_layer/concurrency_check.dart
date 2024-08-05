import 'dart:convert';
import 'package:crypto/crypto.dart';

import '../domain_layer/entities/filter.dart';
import 'global_state.dart';
import 'request_state.dart';

class ConcurrencyCheck {
  GlobalState globalState;

  ConcurrencyCheck(this.globalState);

  /// checks if the request is already served (based on filters) and if so adds the stream.
  /// returns true if the response stream got replaced
  check(RequestState requestState) {
    final hash = _hashFilters(requestState.requestConfig.filters);

    // check if its not already served
    if (!globalState.inFlightRequests.containsKey(hash)) {
      // add to running requests
      globalState.inFlightRequests[hash] = requestState;

      // register listener so inFlight entry gets removed
      requestState.controller.done.then(
        (value) => globalState.inFlightRequests.remove(hash),
      );

      return false;
    }

    // add already running stream to duplicate request
    requestState.controller
        .addStream(globalState.inFlightRequests[hash]!.stream);

    return true;
  }

  String _hashFilters(List<Filter> filters) {
    final jsonString = json.encode(filters);
    final bytes = utf8.encode(jsonString);
    final hash = sha256.convert(bytes);
    return hash.toString();
  }
}
