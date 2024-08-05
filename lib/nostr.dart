// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:core';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:dart_ndk/domain_layer/repositories/cache_manager.dart';
import 'package:dart_ndk/dart_ndk.dart';
import 'package:dart_ndk/data_layer/repositories/cache_manager/mem_cache_manager.dart';
import 'package:dart_ndk/domain_layer/entities/pubkey_mapping.dart';
import 'package:dart_ndk/domain_layer/repositories/event_signer.dart';
import 'package:dart_ndk/shared/nips/nip01/helpers.dart';
import 'package:dart_ndk/domain_layer/entities/contact_list.dart';
import 'package:dart_ndk/shared/nips/nip09/deletion.dart';
import 'package:dart_ndk/domain_layer/entities/relay_info.dart';
import 'package:dart_ndk/shared/nips/nip25/reactions.dart';
import 'package:dart_ndk/domain_layer/entities/read_write_marker.dart';
import 'package:dart_ndk/domain_layer/entities/read_write.dart';
import 'package:dart_ndk/domain_layer/entities/relay.dart';
import 'package:dart_ndk/request.dart';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'event_filter.dart';
import 'domain_layer/entities/relay_set.dart';
import 'domain_layer/entities/user_relay_list.dart';
import 'data_layer/repositories/verifiers/acinq_event_verifier.dart';
import 'domain_layer/entities/nip_01_event.dart';
import 'domain_layer/repositories/event_verifier.dart';
import 'domain_layer/entities/filter.dart';
import 'domain_layer/entities/metadata.dart';
import 'domain_layer/entities/nip_51_list.dart';
import 'domain_layer/entities/nip_65.dart';
import 'shared/helpers/relay_helper.dart';

class Nostr {
  late CacheManager cacheManager;

  late RelayManager relayManager;

  Nostr({RelayManager? relayManager, CacheManager? cacheManager}) {
    this.cacheManager = cacheManager ?? MemCacheManager();
    this.relayManager =
        relayManager ?? RelayManager(cacheManager: cacheManager);
  }
  // ====================================================================================================================

  Future<Nip01Event> broadcastReaction(
      String eventId, Iterable<String> relays, EventSigner signer,
      {String reaction = "+"}) async {
    Nip01Event event = Nip01Event(
        pubKey: signer.getPublicKey(),
        kind: Reaction.KIND,
        tags: [
          ["e", eventId]
        ],
        content: reaction,
        createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000);
    await relayManager.broadcastEvent(event, relays, signer);
    return event;
  }

  Future<Nip01Event> broadcastDeletion(
      String eventId, Iterable<String> relays, EventSigner signer) async {
    Nip01Event event = Nip01Event(
        pubKey: signer.getPublicKey(),
        kind: Deletion.KIND,
        tags: [
          ["e", eventId]
        ],
        content: "delete",
        createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000);
    await relayManager.broadcastEvent(event, relays, signer);
    return event;
  }

  // if cached contact list is older that now minus this duration that we should go refresh it,
  // otherwise we risk adding/removing contacts to a list that is out of date and thus loosing contacts other client has added/removed since.
  static const Duration REFRESH_CONTACT_LIST_DURATION = Duration(minutes: 10);

  Future<ContactList> ensureUpToDateContactListOrEmpty(
      EventSigner signer) async {
    ContactList? contactList =
        cacheManager.loadContactList(signer.getPublicKey());
    int sometimeAgo = DateTime.now()
            .subtract(REFRESH_CONTACT_LIST_DURATION)
            .millisecondsSinceEpoch ~/
        1000;
    bool refresh = contactList == null ||
        contactList.loadedTimestamp == null ||
        contactList.loadedTimestamp! < sometimeAgo;
    if (refresh) {
      contactList =
          await loadContactList(signer.getPublicKey(), forceRefresh: true);
    }
    contactList ??= ContactList(pubKey: signer.getPublicKey(), contacts: []);
    return contactList;
  }

  Future<ContactList> broadcastAddContact(
      String add, Iterable<String> relays, EventSigner signer) async {
    ContactList contactList = await ensureUpToDateContactListOrEmpty(signer);
    if (!contactList.contacts.contains(add)) {
      contactList.contacts.add(add);
      contactList.loadedTimestamp = Helpers.now;
      contactList.createdAt = Helpers.now;
      await relayManager.broadcastEvent(contactList.toEvent(), relays, signer);
      await cacheManager.saveContactList(contactList);
    }
    return contactList;
  }

  Future<ContactList> broadcastAddFollowedTag(
      String toAdd, Iterable<String> relays, EventSigner signer) async {
    ContactList contactList = await ensureUpToDateContactListOrEmpty(signer);
    if (!contactList.followedTags.contains(toAdd)) {
      contactList.followedTags.add(toAdd);
      contactList.loadedTimestamp = Helpers.now;
      contactList.createdAt = Helpers.now;
      await relayManager.broadcastEvent(contactList.toEvent(), relays, signer);
      await cacheManager.saveContactList(contactList);
    }
    return contactList;
  }

  Future<ContactList> broadcastAddFollowedCommunity(
      String toAdd, Iterable<String> relays, EventSigner signer) async {
    ContactList contactList = await ensureUpToDateContactListOrEmpty(signer);
    if (!contactList.followedCommunities.contains(toAdd)) {
      contactList.followedCommunities.add(toAdd);
      contactList.loadedTimestamp = Helpers.now;
      contactList.createdAt = Helpers.now;
      await relayManager.broadcastEvent(contactList.toEvent(), relays, signer);
      await cacheManager.saveContactList(contactList);
    }
    return contactList;
  }

  Future<ContactList> broadcastAddFollowedEvent(
      String toAdd, Iterable<String> relays, EventSigner signer) async {
    ContactList contactList = await ensureUpToDateContactListOrEmpty(signer);
    if (!contactList.followedEvents.contains(toAdd)) {
      contactList.followedEvents.add(toAdd);
      contactList.loadedTimestamp = Helpers.now;
      contactList.createdAt = Helpers.now;
      await relayManager.broadcastEvent(contactList.toEvent(), relays, signer);
      await cacheManager.saveContactList(contactList);
    }
    return contactList;
  }

  Future<ContactList?> broadcastRemoveContact(
      String toRemove, Iterable<String> relays, EventSigner signer) async {
    ContactList? contactList = await ensureUpToDateContactListOrEmpty(signer);
    if (contactList.contacts.contains(toRemove)) {
      contactList.contacts.remove(toRemove);
      contactList.loadedTimestamp = Helpers.now;
      contactList.createdAt = Helpers.now;
      await relayManager.broadcastEvent(contactList.toEvent(), relays, signer);
      await cacheManager.saveContactList(contactList);
    }
    return contactList;
  }

  Future<ContactList?> broadcastRemoveFollowedTag(
      String toRemove, Iterable<String> relays, EventSigner signer) async {
    ContactList? contactList = await ensureUpToDateContactListOrEmpty(signer);
    if (contactList.followedTags.contains(toRemove)) {
      contactList.followedTags.remove(toRemove);
      contactList.loadedTimestamp = Helpers.now;
      contactList.createdAt = Helpers.now;
      await relayManager.broadcastEvent(contactList.toEvent(), relays, signer);
      await cacheManager.saveContactList(contactList);
    }
    return contactList;
  }

  Future<ContactList?> broadcastRemoveFollowedCommunity(
      String toRemove, Iterable<String> relays, EventSigner signer) async {
    ContactList? contactList = await ensureUpToDateContactListOrEmpty(signer);
    if (contactList.followedCommunities.contains(toRemove)) {
      contactList.followedCommunities.remove(toRemove);
      contactList.loadedTimestamp = Helpers.now;
      contactList.createdAt = Helpers.now;
      await relayManager.broadcastEvent(contactList.toEvent(), relays, signer);
      await cacheManager.saveContactList(contactList);
    }
    return contactList;
  }

  Future<ContactList?> broadcastRemoveFollowedEvent(
      String toRemove, Iterable<String> relays, EventSigner signer) async {
    ContactList? contactList = await ensureUpToDateContactListOrEmpty(signer);
    if (contactList.followedEvents.contains(toRemove)) {
      contactList.followedEvents.remove(toRemove);
      contactList.loadedTimestamp = Helpers.now;
      contactList.createdAt = Helpers.now;
      await relayManager.broadcastEvent(contactList.toEvent(), relays, signer);
      await cacheManager.saveContactList(contactList);
    }
    return contactList;
  }

  // if cached user relay list is older that now minus this duration that we should go refresh it,
  // otherwise we risk adding/removing relays to a list that is out of date and thus loosing relays other client has added/removed since.
  static const Duration REFRESH_USER_RELAY_DURATION = Duration(minutes: 10);

  Future<UserRelayList?> ensureUpToDateUserRelayList(EventSigner signer) async {
    UserRelayList? userRelayList =
        cacheManager.loadUserRelayList(signer.getPublicKey());
    int sometimeAgo = DateTime.now()
            .subtract(REFRESH_USER_RELAY_DURATION)
            .millisecondsSinceEpoch ~/
        1000;
    bool refresh =
        userRelayList == null || userRelayList.refreshedTimestamp < sometimeAgo;
    if (refresh) {
      userRelayList = await getSingleUserRelayList(signer.getPublicKey(),
          forceRefresh: true);
    }
    return userRelayList;
  }

  Future<UserRelayList> broadcastAddNip65Relay(
      String relayUrl,
      ReadWriteMarker marker,
      Iterable<String> broadcastRelays,
      EventSigner signer) async {
    UserRelayList? userRelayList = await ensureUpToDateUserRelayList(signer);
    if (userRelayList == null) {
      int now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      userRelayList = UserRelayList(
          pubKey: signer.getPublicKey(),
          relays: {
            for (String url in broadcastRelays) url: ReadWriteMarker.readWrite
          },
          createdAt: now,
          refreshedTimestamp: now);
    }
    userRelayList.relays[relayUrl] = marker;
    await Future.wait([
      relayManager.broadcastEvent(
          userRelayList.toNip65().toEvent(), broadcastRelays, signer),
      cacheManager.saveUserRelayList(userRelayList)
    ]);
    return userRelayList;
  }

  Future<UserRelayList?> broadcastRemoveNip65Relay(String relayUrl,
      Iterable<String> broadcastRelays, EventSigner signer) async {
    UserRelayList? userRelayList = await ensureUpToDateUserRelayList(signer);
    if (userRelayList == null) {
      int now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      userRelayList = UserRelayList(
          pubKey: signer.getPublicKey(),
          relays: {
            for (String url in broadcastRelays) url: ReadWriteMarker.readWrite
          },
          createdAt: now,
          refreshedTimestamp: now);
    }
    if (userRelayList.relays.keys.contains(relayUrl)) {
      userRelayList.relays.remove(relayUrl);
      userRelayList.refreshedTimestamp = Helpers.now;
      await Future.wait([
        relayManager.broadcastEvent(
            userRelayList.toNip65().toEvent(), broadcastRelays, signer),
        cacheManager.saveUserRelayList(userRelayList)
      ]);
    }
    return userRelayList;
  }

  Future<UserRelayList?> broadcastUpdateNip65RelayMarker(
      String relayUrl,
      ReadWriteMarker marker,
      Iterable<String> broadcastRelays,
      EventSigner signer) async {
    UserRelayList? userRelayList = await ensureUpToDateUserRelayList(signer);
    if (userRelayList == null) {
      int now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      userRelayList = UserRelayList(
          pubKey: signer.getPublicKey(),
          relays: {
            for (String url in broadcastRelays) url: ReadWriteMarker.readWrite
          },
          createdAt: now,
          refreshedTimestamp: now);
    }
    String? url;
    if (userRelayList.relays.keys.contains(relayUrl)) {
      url = relayUrl;
    } else {
      String? cleanUrl = cleanRelayUrl(relayUrl);
      if (cleanUrl != null && userRelayList.relays.keys.contains(cleanUrl)) {
        url = cleanUrl;
      } else if (userRelayList.relays.keys.contains("$relayUrl/")) {
        url = "$relayUrl/";
      }
    }
    if (url != null) {
      userRelayList.relays[url] = marker;
      userRelayList.refreshedTimestamp = Helpers.now;
      await relayManager.broadcastEvent(
          userRelayList.toNip65().toEvent(), broadcastRelays, signer);
      await cacheManager.saveUserRelayList(userRelayList);
    }
    return userRelayList;
  }

  Future<Nip51Set> broadcastAddNip51SetRelay(String relayUrl, String name,
      Iterable<String> broadcastRelays, EventSigner signer,
      {bool private = false}) async {
    if (private && !signer.canSign()) {
      throw Exception(
          "cannot broadcast private nip51 list without a signer that can sign");
    }
    Nip51Set? list =
        await getSingleNip51RelaySet(name, signer, forceRefresh: true);
    list ??= Nip51Set(
        name: name,
        pubKey: signer.getPublicKey(),
        createdAt: Helpers.now,
        elements: []);
    list.addRelay(relayUrl, private);
    list.createdAt = Helpers.now;
    Nip01Event event = await list.toEvent(signer);
    print(event);
    await Future.wait([
      relayManager.broadcastEvent(event, broadcastRelays, signer),
    ]);
    List<Nip01Event>? events = cacheManager.loadEvents(
        pubKeys: [signer.getPublicKey()], kinds: [Nip51List.RELAY_SET]);
    events = events.where((event) {
      if (event.getDtag() != null && event.getDtag() == name) {
        return true;
      }
      return false;
    }).toList();
    for (var event in events) {
      cacheManager.removeEvent(event.id);
    }

    await cacheManager.saveEvent(event);
    return list;
  }

  Future<Nip51Set?> broadcastRemoveNip51SetRelay(String relayUrl, String name,
      Iterable<String> broadcastRelays, EventSigner signer,
      {List<String>? defaultRelaysIfEmpty, bool private = false}) async {
    if (private && !signer.canSign()) {
      throw Exception(
          "cannot broadcast private nip51 list without a signer that can sign");
    }
    Nip51Set? relaySet = await getSingleNip51RelaySet(
      name,
      signer,
      forceRefresh: true,
    );
    if ((relaySet == null || relaySet.allRelays.isEmpty) &&
        defaultRelaysIfEmpty != null &&
        defaultRelaysIfEmpty.isNotEmpty) {
      relaySet = Nip51Set(
          name: name,
          pubKey: signer.getPublicKey(),
          createdAt: Helpers.now,
          elements: []);
      relaySet.privateRelays = defaultRelaysIfEmpty;
    }
    if (relaySet != null) {
      relaySet.removeRelay(relayUrl);
      relaySet.createdAt = Helpers.now;
      Nip01Event event = await relaySet.toEvent(signer);
      await Future.wait([
        relayManager.broadcastEvent(event, broadcastRelays, signer),
      ]);
      List<Nip01Event>? events = cacheManager.loadEvents(
          pubKeys: [signer.getPublicKey()], kinds: [Nip51List.RELAY_SET]);
      events = events.where((event) {
        if (event.getDtag() != null && event.getDtag() == name) {
          return true;
        }
        return false;
      }).toList();
      for (var event in events) {
        cacheManager.removeEvent(event.id);
      }
      await cacheManager.saveEvent(event);
    }
    return relaySet;
  }

  Future<Nip51List> broadcastAddNip51ListRelay(int kind, String relayUrl,
      Iterable<String> broadcastRelays, EventSigner signer,
      {bool private = false}) async {
    if (private && !signer.canSign()) {
      throw Exception(
          "cannot broadcast private nip51 list without a signer that can sign");
    }
    Nip51List? list =
        await getSingleNip51List(kind, signer, forceRefresh: true);
    list ??= Nip51List(
        kind: kind,
        pubKey: signer.getPublicKey(),
        createdAt: Helpers.now,
        elements: []);
    list.addRelay(relayUrl, private);
    list.createdAt = Helpers.now;
    Nip01Event event = await list.toEvent(signer);
    print(event);
    await Future.wait([
      relayManager.broadcastEvent(event, broadcastRelays, signer),
    ]);
    List<Nip01Event>? events = cacheManager
        .loadEvents(pubKeys: [signer.getPublicKey()], kinds: [kind]);
    for (var event in events) {
      cacheManager.removeEvent(event.id);
    }
    await cacheManager.saveEvent(event);
    return list;
  }

  Future<Nip51List?> broadcastRemoveNip51Relay(int kind, String relayUrl,
      Iterable<String> broadcastRelays, EventSigner signer,
      {List<String>? defaultRelaysIfEmpty}) async {
    if (!signer.canSign()) {
      throw Exception(
          "cannot broadcast private nip51 list without a signer that can sign");
    }
    Nip51List? list = await getSingleNip51List(
      kind,
      signer,
      forceRefresh: true,
    );
    if ((list == null || list.allRelays.isEmpty) &&
        defaultRelaysIfEmpty != null &&
        defaultRelaysIfEmpty.isNotEmpty) {
      list = Nip51List(
          kind: kind,
          pubKey: signer.getPublicKey(),
          createdAt: Helpers.now,
          elements: []);
      list.privateRelays = defaultRelaysIfEmpty;
    }
    if (list != null && list.allRelays.isNotEmpty) {
      list.removeRelay(relayUrl);
      list.createdAt = Helpers.now;
      Nip01Event event = await list.toEvent(signer);
      await Future.wait([
        relayManager.broadcastEvent(event, broadcastRelays, signer),
      ]);
      List<Nip01Event>? events = cacheManager
          .loadEvents(pubKeys: [signer.getPublicKey()], kinds: [kind]);
      for (var event in events) {
        cacheManager.removeEvent(event.id);
      }
      await cacheManager.saveEvent(event);
    }
    return list;
  }

  Future<Nip51List?> broadcastRemoveNip51ListElement(
      int kind,
      String tag,
      String value,
      Iterable<String> broadcastRelays,
      EventSigner signer) async {
    if (!signer.canSign()) {
      throw Exception(
          "cannot broadcast private nip51 list without a signer that can sign");
    }
    Nip51List? list =
        await getSingleNip51List(kind, signer, forceRefresh: true, timeout: 2);
    if (list == null || list.elements.isEmpty) {
      list = Nip51List(
          kind: kind,
          pubKey: signer.getPublicKey(),
          createdAt: Helpers.now,
          elements: []);
    }
    if (list.elements.isNotEmpty) {
      list.removeElement(tag, value);
      list.createdAt = Helpers.now;
      Nip01Event event = await list.toEvent(signer);
      await Future.wait([
        relayManager.broadcastEvent(event, broadcastRelays, signer),
      ]);
      List<Nip01Event>? events = cacheManager
          .loadEvents(pubKeys: [signer.getPublicKey()], kinds: [kind]);
      for (var event in events) {
        cacheManager.removeEvent(event.id);
      }
      await cacheManager.saveEvent(event);
    }
    return list;
  }

  Future<Nip51List> broadcastAddNip51ListElement(int kind, String tag,
      String value, Iterable<String> broadcastRelays, EventSigner signer,
      {bool private = false}) async {
    if (private && !signer.canSign()) {
      throw Exception(
          "cannot broadcast private nip51 list without a signer that can sign");
    }
    Nip51List? list =
        await getSingleNip51List(kind, signer, forceRefresh: true, timeout: 2);
    list ??= Nip51List(
        kind: kind,
        pubKey: signer.getPublicKey(),
        createdAt: Helpers.now,
        elements: []);
    list.addElement(tag, value, private);
    list.createdAt = Helpers.now;
    Nip01Event event = await list.toEvent(signer);
    print(event);
    await Future.wait([
      relayManager.broadcastEvent(event, broadcastRelays, signer),
    ]);
    List<Nip01Event>? events = cacheManager
        .loadEvents(pubKeys: [signer.getPublicKey()], kinds: [kind]);
    for (var event in events) {
      cacheManager.removeEvent(event.id);
    }
    await cacheManager.saveEvent(event);
    return list;
  }

  //*******************************************************************************************************************************/

  Future<Nip01Event?> getSingleMetadataEvent(EventSigner signer) async {
    Nip01Event? loaded;
    await for (final event in (await relayManager.requestRelays(
            relayManager.bootstrapRelays,
            timeout: RelayManager.DEFAULT_STREAM_IDLE_TIMEOUT,
            Filter(
                kinds: [Metadata.KIND],
                authors: [signer.getPublicKey()],
                limit: 1)))
        .stream) {
      if (loaded == null || loaded.createdAt < event.createdAt) {
        loaded = event;
      }
    }
    return loaded;
  }

  Future<Metadata> broadcastMetadata(Metadata metadata,
      Iterable<String> broadcastRelays, EventSigner signer) async {
    Nip01Event? event = await getSingleMetadataEvent(signer);
    if (event != null) {
      Map<String, dynamic> map = json.decode(event.content);
      map.addAll(metadata.toJson());
      event = Nip01Event(
          pubKey: event.pubKey,
          kind: event.kind,
          tags: event.tags,
          content: json.encode(map),
          createdAt: Helpers.now);
    } else {
      event = metadata.toEvent();
    }
    await relayManager.broadcastEvent(event, broadcastRelays, signer);

    metadata.updatedAt = Helpers.now;
    metadata.refreshedTimestamp = Helpers.now;
    await cacheManager.saveMetadata(metadata);

    return metadata;
  }

  Future<void> loadMissingRelayListsFromNip65OrNip02(List<String> pubKeys,
      {Function(String stepName, int count, int total)? onProgress,
      bool forceRefresh = false}) async {
    List<String> missingPubKeys = [];
    for (var pubKey in pubKeys) {
      UserRelayList? userRelayList = cacheManager.loadUserRelayList(pubKey);
      if (userRelayList == null || forceRefresh) {
        // TODO check if not too old (time passed since last refreshed timestamp)
        missingPubKeys.add(pubKey);
      }
    }
    Map<String, UserRelayList> fromNip65s = {};
    Map<String, UserRelayList> fromNip02Contacts = {};
    Set<ContactList> contactLists = {};
    Set<String> found = {};

    if (missingPubKeys.isNotEmpty) {
      print("loading missing relay lists ${missingPubKeys.length}");
      if (onProgress != null) {
        onProgress.call(
            "loading missing relay lists", 0, missingPubKeys.length);
      }
      try {
        await for (final event in (await relayManager.requestRelays(
                timeout: missingPubKeys.length > 1 ? 10 : 3,
                relayManager.bootstrapRelays,
                Filter(
                    authors: missingPubKeys,
                    kinds: [Nip65.KIND, ContactList.KIND])))
            .stream) {
          switch (event.kind) {
            case Nip65.KIND:
              Nip65 nip65 = Nip65.fromEvent(event);
              if (nip65.relays.isNotEmpty) {
                UserRelayList fromNip65 = UserRelayList.fromNip65(nip65);
                if (fromNip65s[event.pubKey] == null ||
                    fromNip65s[event.pubKey]!.createdAt < event.createdAt) {
                  fromNip65s[event.pubKey] = fromNip65;
                }
                if (onProgress != null) {
                  found.add(event.pubKey);
                  onProgress.call("loading missing relay lists", found.length,
                      missingPubKeys.length);
                }
              }
            case ContactList.KIND:
              ContactList contactList = ContactList.fromEvent(event);
              contactLists.add(contactList);
              if (event.content.isNotEmpty) {
                if (fromNip02Contacts[event.pubKey] == null ||
                    fromNip02Contacts[event.pubKey]!.createdAt <
                        event.createdAt) {
                  fromNip02Contacts[event.pubKey] =
                      UserRelayList.fromNip02EventContent(event);
                }
                if (onProgress != null) {
                  found.add(event.pubKey);
                  onProgress.call("loading missing relay lists", found.length,
                      missingPubKeys.length);
                }
              }
          }
        }
      } catch (e) {
        print(e);
      }
      Set<UserRelayList> relayLists = Set.of(fromNip65s.values);
      // Only add kind3 contents relays if there is no Nip65 for given pubKey.
      // This is because kind3 contents relay should be deprecated, and if we have a nip65 list should be considered more up-to-date.
      for (MapEntry<String, UserRelayList> entry in fromNip02Contacts.entries) {
        if (!fromNip65s.containsKey(entry.key)) {
          relayLists.add(entry.value);
        }
      }
      await cacheManager.saveUserRelayLists(relayLists.toList());

      // also save to cache any fresher contact list
      List<ContactList> contactListsSave = [];
      for (ContactList contactList in contactLists) {
        ContactList? existing =
            cacheManager.loadContactList(contactList.pubKey);
        if (existing == null || existing.createdAt < contactList.createdAt) {
          contactListsSave.add(contactList);
        }
      }
      await cacheManager.saveContactLists(contactListsSave);

      if (onProgress != null) {
        onProgress.call(
            "loading missing relay lists", found.length, missingPubKeys.length);
      }
    }
    print("Loaded ${found.length} relay lists ");
  }

  Future<List<Metadata>> loadMissingMetadatas(
      List<String> pubKeys, RelaySet relaySet,
      {bool splitRequestsByPubKeyMappings = true,
      Function(Metadata)? onLoad}) async {
    List<String> missingPubKeys = [];
    for (var pubKey in pubKeys) {
      Metadata? userMetadata = cacheManager.loadMetadata(pubKey);
      if (userMetadata == null) {
        // TODO check if not too old (time passed since last refreshed timestamp)
        missingPubKeys.add(pubKey);
      }
    }
    Map<String, Metadata> metadatas = {};

    if (missingPubKeys.isNotEmpty) {
      print("loading missing user metadatas ${missingPubKeys.length}");
      try {
        await for (final event in (await relayManager.query(
                idleTimeout: 1,
                splitRequestsByPubKeyMappings: splitRequestsByPubKeyMappings,
                Filter(authors: missingPubKeys, kinds: [Metadata.KIND]),
                relaySet))
            .stream
            .timeout(const Duration(seconds: 5), onTimeout: (sink) {
          print("timeout metadatas.length:${metadatas.length}");
        })) {
          if (metadatas[event.pubKey] == null ||
              metadatas[event.pubKey]!.updatedAt! < event.createdAt) {
            metadatas[event.pubKey] = Metadata.fromEvent(event);
            metadatas[event.pubKey]!.refreshedTimestamp = Helpers.now;
            await cacheManager.saveMetadata(metadatas[event.pubKey]!);
            if (onLoad != null) {
              onLoad(metadatas[event.pubKey]!);
            }
          }
        }
      } catch (e) {
        print(e);
      }
      // if (metadatas.isNotEmpty) {
      //   await cacheManager.saveMetadatas(metadatas.values
      //       // .map((metadata) => DbMetadata.fromMetadata(metadata))
      //       .toList());
      // }
      print("Loaded ${metadatas.length} user metadatas ");
    }
    return metadatas.values.toList();
  }

  Future<ContactList?> loadContactList(String pubKey,
      {bool forceRefresh = false,
      int idleTimeout = RelayManager.DEFAULT_STREAM_IDLE_TIMEOUT}) async {
    ContactList? contactList = cacheManager.loadContactList(pubKey);
    if (contactList == null || forceRefresh) {
      ContactList? loadedContactList;
      try {
        await for (final event in (await relayManager.requestRelays(
                relayManager.bootstrapRelays,
                timeout: idleTimeout,
                Filter(kinds: [ContactList.KIND], authors: [pubKey], limit: 1)))
            .stream) {
          if (loadedContactList == null ||
              loadedContactList.createdAt < event.createdAt) {
            loadedContactList = ContactList.fromEvent(event);
          }
        }
      } catch (e) {
        print(e);
        // probably timeout;
      }
      if (loadedContactList != null &&
          (contactList == null ||
              contactList.createdAt < loadedContactList.createdAt)) {
        loadedContactList.loadedTimestamp =
            DateTime.now().millisecondsSinceEpoch ~/ 1000;
        await cacheManager.saveContactList(loadedContactList);
        contactList = loadedContactList;
      }
    }
    return contactList;
  }

  Future<Metadata?> getSingleMetadata(String pubKey,
      {bool forceRefresh = false,
      int idleTimeout = RelayManager.DEFAULT_STREAM_IDLE_TIMEOUT}) async {
    Metadata? metadata = cacheManager.loadMetadata(pubKey);
    if (metadata == null || forceRefresh) {
      Metadata? loadedMetadata;
      try {
        await for (final event in (await relayManager.requestRelays(
                relayManager.bootstrapRelays,
                timeout: idleTimeout,
                Filter(kinds: [Metadata.KIND], authors: [pubKey], limit: 1)))
            .stream) {
          if (loadedMetadata == null ||
              loadedMetadata.updatedAt == null ||
              loadedMetadata.updatedAt! < event.createdAt) {
            loadedMetadata = Metadata.fromEvent(event);
          }
        }
      } catch (e) {
        // probably timeout;
      }
      if (loadedMetadata != null &&
          (metadata == null ||
              loadedMetadata.updatedAt == null ||
              metadata.updatedAt == null ||
              loadedMetadata.updatedAt! < metadata.updatedAt! ||
              forceRefresh)) {
        loadedMetadata.refreshedTimestamp = Helpers.now;
        await cacheManager.saveMetadata(loadedMetadata);
        metadata = loadedMetadata;
      }
    }
    return metadata;
  }

  Future<UserRelayList?> getSingleUserRelayList(String pubKey,
      {bool forceRefresh = false}) async {
    UserRelayList? userRelayList = cacheManager.loadUserRelayList(pubKey);
    if (userRelayList == null || forceRefresh) {
      await loadMissingRelayListsFromNip65OrNip02([pubKey],
          forceRefresh: forceRefresh);
      userRelayList = cacheManager.loadUserRelayList(pubKey);
    }
    return userRelayList;
  }

  Future<Nip51List?> getCachedNip51List(int kind, EventSigner signer) async {
    List<Nip01Event>? events = cacheManager
        .loadEvents(pubKeys: [signer.getPublicKey()], kinds: [kind]);
    events.sort(
      (a, b) => b.createdAt.compareTo(a.createdAt),
    );
    return events.isNotEmpty
        ? await Nip51List.fromEvent(events.first, signer)
        : null;
  }

  Future<Nip51List?> getSingleNip51List(int kind, EventSigner signer,
      {bool forceRefresh = false, int timeout = 5}) async {
    Nip51List? list =
        !forceRefresh ? await getCachedNip51List(kind, signer) : null;
    if (list == null) {
      Nip51List? refreshedList;
      await for (final event in (await relayManager.requestRelays(
              relayManager.bootstrapRelays.toList(),
              Filter(
                authors: [signer.getPublicKey()],
                kinds: [kind],
              ),
              timeout: timeout))
          .stream) {
        if (refreshedList == null ||
            refreshedList.createdAt <= event.createdAt) {
          refreshedList = await Nip51List.fromEvent(event, signer);
          // if (Helpers.isNotBlank(event.content)) {
          //   Nip51List? decryptedList = await Nip51List.fromEvent(event, signer);
          //   refreshedList = decryptedList;
          // }
          await cacheManager.saveEvent(event);
        }
      }
      return refreshedList;
    }
    return list;
  }

  Future<Nip51Set?> getCachedNip51RelaySet(
      String name, EventSigner signer) async {
    List<Nip01Event>? events = cacheManager.loadEvents(
        pubKeys: [signer.getPublicKey()], kinds: [Nip51List.RELAY_SET]);
    events = events.where((event) {
      if (event.getDtag() != null && event.getDtag() == name) {
        return true;
      }
      return false;
    }).toList();
    events.sort(
      (a, b) => b.createdAt.compareTo(a.createdAt),
    );
    return events.isNotEmpty
        ? await Nip51Set.fromEvent(events.first, signer)
        : null;
  }

  Future<Nip51Set?> getSingleNip51RelaySet(String name, EventSigner signer,
      {bool forceRefresh = false}) async {
    Nip51Set? relaySet = await getCachedNip51RelaySet(name, signer);
    if (relaySet == null || forceRefresh) {
      Nip51Set? newRelaySet;
      await for (final event in (await relayManager.requestRelays(
              relayManager.bootstrapRelays.toList(),
              Filter(
                authors: [signer.getPublicKey()],
                kinds: [Nip51List.RELAY_SET],
                dTags: [name],
              ),
              timeout: 5))
          .stream) {
        if (newRelaySet == null || newRelaySet.createdAt < event.createdAt) {
          if (event.getDtag() != null && event.getDtag() == name) {
            newRelaySet = await Nip51Set.fromEvent(event, signer);
            await cacheManager.saveEvent(event);
          } else if (Helpers.isNotBlank(event.content)) {
            Nip51Set? decryptedRelaySet =
                await Nip51Set.fromEvent(event, signer);
            if (decryptedRelaySet != null && decryptedRelaySet.name == name) {
              newRelaySet = decryptedRelaySet;
              await cacheManager.saveEvent(event);
            }
          }
        }
      }
      return newRelaySet;
    }
    return relaySet;
  }

  Future<List<Nip51Set>?> getNip51RelaySets(int kind, EventSigner signer,
      {bool forceRefresh = false}) async {
    Nip51Set? relaySet; //getCachedNip51RelaySets(signer);
    if (relaySet == null || forceRefresh) {
      Map<String, Nip51Set> newRelaySets = {};
      await for (final event in (await relayManager.requestRelays(
              relayManager.bootstrapRelays.toList(),
              Filter(
                authors: [signer.getPublicKey()],
                kinds: [kind],
              ),
              timeout: 5))
          .stream) {
        if (event.getDtag() != null) {
          Nip51Set? newRelaySet = newRelaySets[event.getDtag()];
          if (newRelaySet == null || newRelaySet.createdAt < event.createdAt) {
            if (event.getDtag() != null) {
              newRelaySet = await Nip51Set.fromEvent(event, signer);
            }
            if (newRelaySet != null) {
              await cacheManager.saveEvent(event);
              newRelaySets[newRelaySet.name] = newRelaySet;
            }
          }
        }
      }
      return newRelaySets.values.toList();
    }
    return [];
  }
}
