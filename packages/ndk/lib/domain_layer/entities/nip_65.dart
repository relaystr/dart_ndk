import '../../shared/helpers/relay_helper.dart';
import 'nip_01_event.dart';
import 'read_write_marker.dart';

class Nip65 {
  static const int KIND = 10002;

  late String pubKey;

  Map<String, ReadWriteMarker> relays = {};

  Nip65.fromMap(this.pubKey, Map<String, ReadWriteMarker> map) {
    relays = map;
  } // Pub keys -> markers

  int createdAt = DateTime.now().millisecondsSinceEpoch ~/ 1000;

  // Nip65(this.relays);

  Map<String, ReadWriteMarker> relaysMap() {
    return relays;
  }

  Nip65.fromEvent(Nip01Event event) {
    pubKey = event.pubKey;
    createdAt = event.createdAt;
    for (var tag in event.tags) {
      final length = tag.length;
      if (length <= 1) continue;
      final name = tag[0];

      // clean the url so it can be used as a unique identifier
      var cleanUrl = cleanRelayUrl(tag[1]);
      if (cleanUrl == null) continue;

      final url = cleanUrl;
      if (name != "r") continue;
      ReadWriteMarker? marker = ReadWriteMarker.readWrite;
      if (length > 2) {
        var operType = tag[2];
        switch (operType) {
          case "read":
            marker = ReadWriteMarker.readOnly;
            break;
          case "write":
            marker = ReadWriteMarker.writeOnly;
            break;
        }
      }
      relays[url] = marker;
    }
  }

  Nip01Event toEvent() {
    return Nip01Event(
      pubKey: pubKey,
      kind: Nip65.KIND,
      tags: relays.entries.map((entry) {
        ReadWriteMarker marker = entry.value;
        List<String> list = ["r", entry.key];
        if (marker == ReadWriteMarker.readOnly) {
          list.add("read");
        }
        if (marker == ReadWriteMarker.writeOnly) {
          list.add("write");
        }
        return list;
      }).toList(),
      content: "",
      createdAt: createdAt,
    );
  }

  @override
  // coverage:ignore-start
  String toString() {
    return 'Nip65{urls: $relays}';
  }
  // coverage:ignore-end
}
