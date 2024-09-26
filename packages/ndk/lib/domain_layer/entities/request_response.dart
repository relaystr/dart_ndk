import 'dart:async';

import 'nip_01_event.dart';

/// Represents a response from a Nostr Development Kit (NDK) request.
class NdkResponse {
  /// The unique identifier for the request that generated this response.
  String requestId;

  /// A stream of [Nip01Event] objects returned by the request.
  ///
  /// This stream can be listened to for real-time processing of events
  /// as they arrive from the nostr request.
  final Stream<Nip01Event> stream;

  /// A future that resolves to a list of all [Nip01Event] objects
  /// once the request is complete (EOSE rcv).
  Future<List<Nip01Event>> get future => stream.toList();

  NdkResponse(this.requestId, this.stream);
}
