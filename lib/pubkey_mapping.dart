import 'package:dart_ndk/nips/nip65/read_write_marker.dart';

/// maps the direction for a pubkey read, write, both
class PubkeyMapping {
  String pubKey;

  ReadWriteMarker rwMarker;

  PubkeyMapping({
    required this.pubKey,
    required this.rwMarker,
  });

  // overwrite == operator
  @override
  bool operator ==(covariant PubkeyMapping other) {
    return pubKey == other.pubKey && rwMarker == other.rwMarker;
  }

  @override
  int get hashCode => pubKey.hashCode ^ rwMarker.hashCode;

  bool isRead() {
    return rwMarker.isRead;
  }

  bool isWrite() {
    return rwMarker.isWrite;
  }
}
