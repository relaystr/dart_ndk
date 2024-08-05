import 'dart:async';

import '../domain_layer/entities/nip_01_event.dart';
import '../domain_layer/usecases/relay_jit_manager/relay_jit.dart';
import 'ndk_request.dart';

class RequestState {
  StreamController<Nip01Event> controller =
      StreamController<Nip01Event>.broadcast();

  Stream<Nip01Event> get stream => controller.stream;

  NdkRequest requestConfig;

  get id => requestConfig.id;

  //! our requests tracking obj
  Map<String, dynamic> requests = {};

  // string is the relay url
  Map<String, RelayJit> activeRelaySubscriptions = {};

  RequestState(this.requestConfig);
}
