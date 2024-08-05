import 'package:dart_ndk/domain_layer/entities/read_write_marker.dart';

/// maps the direction for a pubkey read, write, both
class PubkeyMapping {
  String pubKey;

  ReadWriteMarker rwMarker;

  PubkeyMapping({
    required this.pubKey,
    required this.rwMarker,
  });

  // coverage:ignore-start
  @override
  String toString() {
    String result = '$pubKey ';
    if (rwMarker == ReadWriteMarker.readOnly) {
      result += "(read)";
    }
    if (rwMarker == ReadWriteMarker.writeOnly) {
      result += "(write)";
    }
    return result;
  }
  // coverage:ignore-end

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PubkeyMapping &&
          runtimeType == other.runtimeType &&
          pubKey == other.pubKey;

  @override
  int get hashCode => pubKey.hashCode;
}
