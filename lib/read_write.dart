import 'package:dart_ndk/nips/nip65/read_write_marker.dart';

enum RelayDirection {
  inbox,
  outbox;

  bool matchesMarker(ReadWriteMarker marker) {
    return this == RelayDirection.inbox && marker.isRead ||
        this == RelayDirection.outbox && marker.isWrite;
  }
}
