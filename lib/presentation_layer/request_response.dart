import 'dart:async';

import '../domain_layer/entities/nip_01_event.dart';

class RequestResponse {
  final Stream<Nip01Event> stream;

  //! not sure if we can always inject a stream
  RequestResponse(this.stream);
}
