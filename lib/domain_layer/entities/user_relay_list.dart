import 'package:dart_ndk/domain_layer/entities/nip_01_event.dart';
import 'package:dart_ndk/domain_layer/entities/contact_list.dart';
import 'package:dart_ndk/domain_layer/entities/read_write_marker.dart';

import 'nip_65.dart';

class UserRelayList {
  String pubKey;
  int createdAt;
  int refreshedTimestamp;

  Map<String, ReadWriteMarker> relays;

  UserRelayList(
      {required this.pubKey,
      required this.relays,
      required this.createdAt,
      required this.refreshedTimestamp});

  Iterable<String> get urls => relays.keys;

  Iterable<String> get readUrls => relays.entries
      .where((entry) => entry.value.isRead)
      .map((entry) => entry.key);

  static UserRelayList fromNip65(Nip65 nip65) {
    return UserRelayList(
        pubKey: nip65.pubKey,
        relays: {
          for (var entry in nip65.relays.entries) entry.key: entry.value
        },
        createdAt: nip65.createdAt,
        refreshedTimestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000);
  }

  Nip65 toNip65() {
    return Nip65.fromMap(pubKey, relays);
  }

  static UserRelayList fromNip02EventContent(Nip01Event event) {
    return UserRelayList(
        pubKey: event.pubKey,
        relays: ContactList.relaysFromContent(event),
        createdAt: event.createdAt,
        refreshedTimestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000);
  }
}
