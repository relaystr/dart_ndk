import '../domain_layer/entities/relay.dart';
import '../domain_layer/usecases/relay_jit_manager/relay_jit.dart';
import 'request_state.dart';

class GlobalState {
  /// used by concurrency check
  final Map<String, RequestState> inFlightRequests = {};

  /// used by RelayJitManager
  List<RelayJit> connectedRelays = [];
}
