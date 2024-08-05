import 'package:collection/collection.dart';
import 'package:dart_ndk/domain_layer/entities/pubkey_mapping.dart';
import 'package:dart_ndk/domain_layer/entities/read_write.dart';
import 'package:dart_ndk/request.dart';

import 'filter.dart';

class RelaySet {
  String get id => buildId(name, pubKey);

  Iterable<String> get urls => relaysMap.keys;

  late String name;

  late String pubKey;

  int relayMinCountPerPubkey;

  RelayDirection direction;

  // relay url -> covered pubKeys
  Map<String, List<PubkeyMapping>> relaysMap = {};

  bool fallbackToBootstrapRelays = true;

  List<NotCoveredPubKey> notCoveredPubkeys = [];

  RelaySet(
      {required this.name,
      required this.pubKey,
      this.relayMinCountPerPubkey = 0,
      required this.relaysMap,
      this.notCoveredPubkeys = const [],
      required this.direction,
      this.fallbackToBootstrapRelays = true});

  static buildId(String name, String pubKey) {
    return "$name,$pubKey";
  }

  static const int MAX_AUTHORS_PER_REQUEST = 100;

  void splitIntoRequests(Filter filter, NostrRequest groupRequest) {
    for (var entry in relaysMap.entries) {
      String url = entry.key;
      List<PubkeyMapping> pubKeyMappings = entry.value;
      if (pubKeyMappings.isEmpty) {
        groupRequest.addRequest(url, [filter]);
      } else if (filter.authors != null &&
          filter.authors!.isNotEmpty &&
          direction == RelayDirection.outbox) {
        List<String> pubKeysForRelay = [];
        for (String pubKey in filter.authors!) {
          if (pubKeyMappings.any((pubKeyMapping) =>
              pubKey == pubKeyMapping.pubKey ||
              notCoveredPubkeys.any((element) => element.pubKey == pubKey))) {
            pubKeysForRelay.add(pubKey);
          }
        }
        if (pubKeysForRelay.isNotEmpty) {
          groupRequest.addRequest(url,
              sliceFilterAuthors(filter.cloneWithAuthors(pubKeysForRelay)));
        }
      } else if (filter.pTags != null &&
          filter.pTags!.isNotEmpty &&
          direction == RelayDirection.inbox) {
        List<String> pubKeysForRelay = [];
        for (String pubKey in filter.pTags!) {
          if (pubKeyMappings.any((pubKeyMapping) =>
              pubKey == pubKeyMapping.pubKey ||
              notCoveredPubkeys.any((element) => element.pubKey == pubKey))) {
            pubKeysForRelay.add(pubKey);
          }
        }
        if (pubKeysForRelay.isNotEmpty) {
          groupRequest.addRequest(
              url, sliceFilterAuthors(filter.cloneWithPTags(pubKeysForRelay)));
        }
      } else if (filter.eTags != null && direction == RelayDirection.inbox) {
        groupRequest.addRequest(url, [filter]);
      } else {
        /// TODO ????
      }
    }
  }

  static List<Filter> sliceFilterAuthors(Filter filter) {
    if (filter.authors != null &&
        filter.authors!.length > MAX_AUTHORS_PER_REQUEST) {
      return filter.authors!
          .slices(MAX_AUTHORS_PER_REQUEST)
          .map((slice) => filter.cloneWithAuthors(slice))
          .toList();
    } else {
      return [filter];
    }
  }

  void addMoreRelays(Map<String, List<PubkeyMapping>> more) {
    more.forEach((key, value) {
      if (!relaysMap.keys.contains(key)) {
        relaysMap[key] = value;
      }
    });
  }
}

class NotCoveredPubKey {
  String pubKey;
  int coverage;

  NotCoveredPubKey(this.pubKey, this.coverage);
}
