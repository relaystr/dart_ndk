// ignore_for_file: avoid_print

import 'package:dart_ndk/data_layer/repositories/cache_manager/db_cache_manager.dart';
import 'package:dart_ndk/data_layer/models/db/db_contact_list.dart';
import 'package:dart_ndk/data_layer/models/db/db_event.dart';
import 'package:dart_ndk/data_layer/models/db/db_metadata.dart';
import 'package:dart_ndk/data_layer/models/db/db_nip05.dart';
import 'package:dart_ndk/data_layer/models/db/db_relay_set.dart';
import 'package:dart_ndk/data_layer/models/db/db_user_relay_list.dart';
import 'package:dart_ndk/domain_layer/entities/nip_01_event.dart';
import 'package:dart_ndk/shared/nips/nip01/helpers.dart';
import 'package:dart_ndk/domain_layer/entities/read_write_marker.dart';
import 'package:dart_ndk/domain_layer/entities/read_write.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart' as isar;

void main() async {
  await isar.Isar.initialize(
      "./libisar.so"); //initializeIsarCore(download: true);

  test('DbContactList', () async {
    DbCacheManager cacheManager = DbCacheManager();
    await cacheManager.init();
    // int now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    String contact1 = "contact1";
    String pubKey1 = "pubKey1";
    DbContactList userContacts =
        DbContactList(pubKey: pubKey1, contacts: [contact1]);
    await cacheManager.saveContactList(userContacts);

    DbContactList? loadedUserContacts =
        cacheManager.loadContactList(pubKey1) as DbContactList?;
    expect(loadedUserContacts!.pubKey, userContacts.pubKey);
    expect(loadedUserContacts.contacts, userContacts.contacts);
  });

  test('DbUserRelayList', () async {
    DbCacheManager cacheManager = DbCacheManager();
    await cacheManager.init();
    int now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    String pubKey1 = "pubKey1";
    DbUserRelayList userRelayList = DbUserRelayList(
        pubKey: pubKey1,
        items: [DbRelayListItem("wss://bla.com", ReadWriteMarker.readWrite)],
        createdAt: now,
        refreshedTimestamp: now);
    await cacheManager.saveUserRelayList(userRelayList);

    DbUserRelayList? loadedUserRelayList =
        cacheManager.loadUserRelayList(pubKey1) as DbUserRelayList?;
    expect(loadedUserRelayList!.id, userRelayList.id);
    expect(loadedUserRelayList.items.length, userRelayList.items.length);
    for (var i = 0; i < userRelayList.items.length; i++) {
      expect(loadedUserRelayList.items[i].url, userRelayList.items[i].url);
      expect(
          loadedUserRelayList.items[i].marker, userRelayList.items[i].marker);
    }
  });
  test('DbNip05', () async {
    DbCacheManager cacheManager = DbCacheManager();
    await cacheManager.init();
    // int now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    String pubKey1 = "pubKey1";
    DbNip05 nip05 = DbNip05(
        pubKey: pubKey1,
        nip05: "bla@bla.com",
        updatedAt: Helpers.now,
        valid: true);
    await cacheManager.saveNip05(nip05);

    DbNip05? loadedNip05 = cacheManager.loadNip05(pubKey1) as DbNip05?;
    expect(loadedNip05!.id, nip05.id);
    expect(loadedNip05.nip05, nip05.nip05);
    expect(loadedNip05.updatedAt, nip05.updatedAt);
    expect(loadedNip05.valid, nip05.valid);
  });
  test('DbRelaySet', () async {
    DbCacheManager cacheManager = DbCacheManager();
    await cacheManager.init();
    // int now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    String pubKey1 = "pubKey1";
    String pubKey2 = "pubKey2";
    DbRelaySet relaySet = DbRelaySet(
        name: "feed",
        pubKey: pubKey1,
        relayMinCountPerPubkey: 2,
        items: [
          DbRelaySetItem("wss://bla.com", [
            DbPubkeyMapping(
                pubKey: pubKey2, marker: ReadWriteMarker.readWrite.name)
          ])
        ],
        // notCoveredPubkeys: [],
        direction: RelayDirection.outbox);
    await cacheManager.saveRelaySet(relaySet);

    DbRelaySet? loadedRelaySet = cacheManager.loadRelaySet(
        relaySet.name, relaySet.pubKey) as DbRelaySet?;
    expect(loadedRelaySet!.id, relaySet.id);
    expect(loadedRelaySet.items.length, relaySet.items.length);
    for (var i = 0; i < relaySet.items.length; i++) {
      expect(loadedRelaySet.items[i].url, relaySet.items[i].url);
      expect(loadedRelaySet.items[i].pubKeyMappings.length,
          relaySet.items[i].pubKeyMappings.length);
      expect(loadedRelaySet.relayMinCountPerPubkey,
          relaySet.relayMinCountPerPubkey);
      expect(loadedRelaySet.direction, relaySet.direction);
    }
  });
  test('DbMetadata', () async {
    DbCacheManager cacheManager = DbCacheManager();
    await cacheManager.init();
    int now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    String pubKey1 = "pubKey1";
    DbMetadata metadata = DbMetadata(
        pubKey: pubKey1,
        name: "name",
        about: "about",
        banner: "https://cdn.picture.com/banner.jpg",
        displayName: "displayName",
        lud06: "lud06",
        lud16: "lud16",
        nip05: "nip05@domain.com",
        picture: "https://cdn.picture.com/cat.jpg",
        updatedAt: now,
        website: "https://website.com");
    await cacheManager.saveMetadata(metadata);

    DbMetadata? loaded = cacheManager.loadMetadata(pubKey1) as DbMetadata?;
    expect(loaded!.id, metadata.id);
    expect(loaded.pubKey, metadata.pubKey);
    expect(loaded.name, metadata.name);
    expect(loaded.about, metadata.about);
    expect(loaded.displayName, metadata.displayName);
    expect(loaded.lud06, metadata.lud06);
    expect(loaded.lud16, metadata.lud16);
    expect(loaded.nip05, metadata.nip05);
    expect(loaded.picture, metadata.picture);
    expect(loaded.updatedAt, metadata.updatedAt);
    expect(loaded.website, metadata.website);
  });
  test('DbEvent', () async {
    DbCacheManager cacheManager = DbCacheManager();
    await cacheManager.init();
    int now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    String pubKey1 = "pubKey1";
    String pubKey2 = "pubKey2";
    String pubKey3 = "pubKey3";
    DbEvent event11 = DbEvent(
        pubKey: pubKey1,
        content: "content 11",
        kind: 1,
        tags: ["tag1", "tag2"],
        createdAt: now,
        sig: 'signature',
        validSig: true,
        sources: ["wss://relay1.com", "wss://relay2.com"]);
    DbEvent event12 = DbEvent(
        pubKey: pubKey1,
        content: "content 12",
        kind: 2,
        tags: [],
        createdAt: now,
        sig: '',
        validSig: null,
        sources: []);
    DbEvent event21 = DbEvent(
        pubKey: pubKey2,
        content: "content 21",
        kind: 1,
        tags: [],
        createdAt: now,
        sig: '',
        validSig: null,
        sources: []);
    DbEvent event22 = DbEvent(
        pubKey: pubKey2,
        content: "content 22",
        kind: 2,
        tags: [],
        createdAt: now,
        sig: '',
        validSig: null,
        sources: []);
    DbEvent event33 = DbEvent(
        pubKey: pubKey3,
        content: "content 33",
        kind: 3,
        tags: [],
        createdAt: now,
        sig: '',
        validSig: null,
        sources: []);
    cacheManager.removeAllEventsByPubKey(pubKey1);
    cacheManager.removeAllEventsByPubKey(pubKey2);
    cacheManager.removeAllEventsByPubKey(pubKey3);
    await cacheManager
        .saveEvents([event11, event12, event21, event22, event33]);

    Nip01Event? loadedEvent1 = cacheManager.loadEvent(event11.id) as DbEvent?;
    expect(loadedEvent1!.id, event11.id);
    expect(loadedEvent1.content, event11.content);
    expect(loadedEvent1.pubKey, event11.pubKey);
    expect(loadedEvent1.kind, event11.kind);
    expect(loadedEvent1.createdAt, event11.createdAt);
    expect(loadedEvent1.sig, event11.sig);
    expect(loadedEvent1.validSig, event11.validSig);
    expect(loadedEvent1.tags, event11.tags);
    expect(loadedEvent1.sources, event11.sources);

    List<Nip01Event>? loadedEventsKind1 = cacheManager.loadEvents(kinds: [1]);
    expect(loadedEventsKind1.length, 2);
    expect(loadedEventsKind1.contains(event11), true);
    expect(loadedEventsKind1.contains(event21), true);

    List<Nip01Event>? loadedEventsPubkey2 =
        cacheManager.loadEvents(pubKeys: [pubKey2]);
    expect(loadedEventsPubkey2.length, 2);
    expect(loadedEventsPubkey2.contains(event21), true);
    expect(loadedEventsPubkey2.contains(event22), true);

    List<Nip01Event>? loadedEventsPubkey1AndKind1 =
        cacheManager.loadEvents(pubKeys: [pubKey1], kinds: [1]);
    expect(loadedEventsPubkey1AndKind1.length, 1);
    expect(loadedEventsPubkey1AndKind1.contains(event11), true);

    List<Nip01Event>? loadedEventsPubkey2AndKind2 =
        cacheManager.loadEvents(pubKeys: [pubKey2], kinds: [2]);
    expect(loadedEventsPubkey2AndKind2.length, 1);
    expect(loadedEventsPubkey2AndKind2.contains(event22), true);

    List<Nip01Event>? loadedEventsPubkey1AndPubkey2 =
        cacheManager.loadEvents(pubKeys: [pubKey1, pubKey2]);
    expect(loadedEventsPubkey1AndPubkey2.length, 4);
    expect(loadedEventsPubkey1AndPubkey2.contains(event11), true);
    expect(loadedEventsPubkey1AndPubkey2.contains(event12), true);
    expect(loadedEventsPubkey1AndPubkey2.contains(event21), true);
    expect(loadedEventsPubkey1AndPubkey2.contains(event22), true);

    List<Nip01Event>? loadedEventsKind1AndKind2 =
        cacheManager.loadEvents(kinds: [1, 2]);
    expect(loadedEventsKind1AndKind2.length, 4);
    expect(loadedEventsKind1AndKind2.contains(event11), true);
    expect(loadedEventsKind1AndKind2.contains(event12), true);
    expect(loadedEventsKind1AndKind2.contains(event21), true);
    expect(loadedEventsKind1AndKind2.contains(event22), true);

    List<Nip01Event>? loadedEventsKind1AndKind3 =
        cacheManager.loadEvents(kinds: [1, 3]);
    expect(loadedEventsKind1AndKind3.length, 3);
    expect(loadedEventsKind1AndKind3.contains(event11), true);
    expect(loadedEventsKind1AndKind3.contains(event21), true);
    expect(loadedEventsKind1AndKind3.contains(event33), true);
  });

  test('DbEvent by pTags', () async {
    DbCacheManager cacheManager = DbCacheManager();
    await cacheManager.init();
    int now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    String pubKey1 = "pubKey1";
    String pubKey2 = "pubKey2";
    DbEvent event11 = DbEvent(
        pubKey: pubKey1,
        content: "content 11",
        kind: 1,
        tags: [
          ["p", pubKey1],
          ["e", "1w18t12ts281y81"],
          ["bla"]
        ],
        createdAt: now,
        sig: 'signature',
        validSig: true,
        sources: ["wss://relay1.com", "wss://relay2.com"]);
    DbEvent event12 = DbEvent(
        pubKey: pubKey2,
        content: "content 12",
        kind: 2,
        tags: [
          ["dupa"],
          ["e", "1w18t12ts281y81"],
          ["p", pubKey2]
        ],
        createdAt: now,
        sig: '',
        validSig: null,
        sources: []);
    cacheManager.removeAllEventsByPubKey(pubKey1);
    cacheManager.removeAllEventsByPubKey(pubKey2);
    await cacheManager.saveEvents([event11, event12]);

    List<Nip01Event>? loadedEventsPubkey1 =
        cacheManager.loadEvents(pTag: pubKey1);
    expect(loadedEventsPubkey1.length, 1);
    expect(loadedEventsPubkey1.first.pTags, event11.pTags);
    List<Nip01Event>? loadedEventsPubkey2 =
        cacheManager.loadEvents(pTag: pubKey2);
    expect(loadedEventsPubkey2.length, 1);
    expect(loadedEventsPubkey2.first.pTags, event12.pTags);
  });
}
