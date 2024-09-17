import 'dart:convert';

import '../../../shared/logger/logger.dart';
import '../../../shared/nips/nip01/helpers.dart';
import '../../entities/filter.dart';
import '../../entities/metadata.dart';
import '../../entities/nip_01_event.dart';
import '../../entities/nip_51_list.dart';
import '../../entities/relay_set.dart';
import '../../repositories/cache_manager.dart';
import '../../repositories/event_signer.dart';
import '../relay_manager.dart';
import '../requests/requests.dart';

class Lists {
  Requests requests;
  CacheManager cacheManager;
  RelayManager relayManager;

  Lists({
    required this.requests,
    required this.cacheManager,
    required this.relayManager,
  });

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
      await for (final event in requests.query(
        filters: [
          Filter(
            authors: [signer.getPublicKey()],
            kinds: [kind],
          )
        ],
      ).stream) {
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
      await for (final event in requests.query(filters: [
        Filter(
          authors: [signer.getPublicKey()],
          kinds: [Nip51List.RELAY_SET],
          dTags: [name],
        )
      ], cacheRead: !forceRefresh).stream) {
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
      await for (final event in requests.query(filters: [
        Filter(
          authors: [signer.getPublicKey()],
          kinds: [kind],
        )
      ], cacheRead: !forceRefresh).stream) {
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

  Future<Nip51Set> broadcastAddNip51SetRelay(
      String relayUrl, String name, Iterable<String> broadcastRelays, EventSigner eventSigner,
      {bool private = false}) async {
    if (private && !eventSigner.canSign()) {
      throw Exception(
          "cannot broadcast private nip51 list without a signer that can sign");
    }
    Nip51Set? list = await getSingleNip51RelaySet(name, eventSigner,
        forceRefresh: true);
    list ??= Nip51Set(
        name: name,
        pubKey: eventSigner.getPublicKey(),
        createdAt: Helpers.now,
        elements: []);
    list.addRelay(relayUrl, private);
    list.createdAt = Helpers.now;
    Nip01Event event = await list.toEvent(eventSigner);
    //print(event);
    await Future.wait([
      relayManager.broadcastEvent(event, broadcastRelays, eventSigner),
    ]);
    List<Nip01Event>? events = cacheManager.loadEvents(
        pubKeys: [eventSigner.getPublicKey()],
        kinds: [Nip51List.RELAY_SET]);
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

  Future<Nip51Set?> broadcastRemoveNip51SetRelay(
      String relayUrl, String name, Iterable<String> broadcastRelays, EventSigner eventSigner,
      {List<String>? defaultRelaysIfEmpty, bool private = false}) async {
    if (private && !eventSigner.canSign()) {
      throw Exception(
          "cannot broadcast private nip51 list without a signer that can sign");
    }
    Nip51Set? relaySet = await getSingleNip51RelaySet(
      name,
      eventSigner,
      forceRefresh: true,
    );
    if ((relaySet == null || relaySet.allRelays.isEmpty) &&
        defaultRelaysIfEmpty != null &&
        defaultRelaysIfEmpty.isNotEmpty) {
      relaySet = Nip51Set(
          name: name,
          pubKey: eventSigner.getPublicKey(),
          createdAt: Helpers.now,
          elements: []);
      relaySet.privateRelays = defaultRelaysIfEmpty;
    }
    if (relaySet != null) {
      relaySet.removeRelay(relayUrl);
      relaySet.createdAt = Helpers.now;
      Nip01Event event = await relaySet.toEvent(eventSigner);
      await Future.wait([
        relayManager.broadcastEvent(event, broadcastRelays, eventSigner),
      ]);
      List<Nip01Event>? events = cacheManager.loadEvents(
          pubKeys: [eventSigner.getPublicKey()],
          kinds: [Nip51List.RELAY_SET]);
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

  Future<Nip51List> broadcastAddNip51ListRelay(
      int kind, String relayUrl, Iterable<String> broadcastRelays, EventSigner eventSigner,
      {bool private = false}) async {
    if (private && !eventSigner!.canSign()) {
      throw Exception(
          "cannot broadcast private nip51 list without a signer that can sign");
    }
    Nip51List? list =
    await getSingleNip51List(kind, eventSigner, forceRefresh: true);
    list ??= Nip51List(
        kind: kind,
        pubKey: eventSigner.getPublicKey(),
        createdAt: Helpers.now,
        elements: []);
    list.addRelay(relayUrl, private);
    list.createdAt = Helpers.now;
    Nip01Event event = await list.toEvent(eventSigner);
    // print(event);
    await Future.wait([
      relayManager.broadcastEvent(event, broadcastRelays, eventSigner),
    ]);
    List<Nip01Event>? events = cacheManager.loadEvents(
        pubKeys: [eventSigner.getPublicKey()], kinds: [kind]);
    for (var event in events) {
      cacheManager.removeEvent(event.id);
    }
    await cacheManager.saveEvent(event);
    return list;
  }

  Future<Nip51List?> broadcastRemoveNip51Relay(
      int kind, String relayUrl, Iterable<String> broadcastRelays, EventSigner eventSigner,
      {List<String>? defaultRelaysIfEmpty}) async {
    if (!eventSigner.canSign()) {
      throw Exception(
          "cannot broadcast private nip51 list without a signer that can sign");
    }
    Nip51List? list = await getSingleNip51List(
      kind,
      eventSigner,
      forceRefresh: true,
    );
    if ((list == null || list.allRelays.isEmpty) &&
        defaultRelaysIfEmpty != null &&
        defaultRelaysIfEmpty.isNotEmpty) {
      list = Nip51List(
          kind: kind,
          pubKey: eventSigner.getPublicKey(),
          createdAt: Helpers.now,
          elements: []);
      list.privateRelays = defaultRelaysIfEmpty;
    }
    if (list != null && list.allRelays.isNotEmpty) {
      list.removeRelay(relayUrl);
      list.createdAt = Helpers.now;
      Nip01Event event = await list.toEvent(eventSigner);
      await Future.wait([
        relayManager.broadcastEvent(event, broadcastRelays, eventSigner),
      ]);
      List<Nip01Event>? events = cacheManager.loadEvents(
          pubKeys: [eventSigner.getPublicKey()], kinds: [kind]);
      for (var event in events) {
        cacheManager.removeEvent(event.id);
      }
      await cacheManager.saveEvent(event);
    }
    return list;
  }

  Future<Nip51List?> broadcastRemoveNip51ListElement(int kind, String tag,
      String value, Iterable<String> broadcastRelays, EventSigner eventSigner) async {
    if (!eventSigner.canSign()) {
      throw Exception(
          "cannot broadcast private nip51 list without a signer that can sign");
    }
    Nip51List? list = await getSingleNip51List(kind, eventSigner,
        forceRefresh: true, timeout: 2);
    if (list == null || list.elements.isEmpty) {
      list = Nip51List(
          kind: kind,
          pubKey: eventSigner.getPublicKey(),
          createdAt: Helpers.now,
          elements: []);
    }
    if (list.elements.isNotEmpty) {
      list.removeElement(tag, value);
      list.createdAt = Helpers.now;
      Nip01Event event = await list.toEvent(eventSigner);
      await Future.wait([
        relayManager.broadcastEvent(event, broadcastRelays, eventSigner),
      ]);
      List<Nip01Event>? events = cacheManager.loadEvents(
          pubKeys: [eventSigner.getPublicKey()], kinds: [kind]);
      for (var event in events) {
        cacheManager.removeEvent(event.id);
      }
      await cacheManager.saveEvent(event);
    }
    return list;
  }

  Future<Nip51List> broadcastAddNip51ListElement(
      int kind, String tag, String value, Iterable<String> broadcastRelays,
      EventSigner eventSigner,
      {bool private = false}) async {
    if (private && !eventSigner.canSign()) {
      throw Exception(
          "cannot broadcast private nip51 list without a signer that can sign");
    }
    Nip51List? list = await getSingleNip51List(kind, eventSigner,
        forceRefresh: true, timeout: 2);
    list ??= Nip51List(
        kind: kind,
        pubKey: eventSigner.getPublicKey(),
        createdAt: Helpers.now,
        elements: []);
    list.addElement(tag, value, private);
    list.createdAt = Helpers.now;
    Nip01Event event = await list.toEvent(eventSigner);
    // print(event);
    await Future.wait([
      relayManager.broadcastEvent(event, broadcastRelays, eventSigner),
    ]);
    List<Nip01Event>? events = cacheManager.loadEvents(
        pubKeys: [eventSigner.getPublicKey()], kinds: [kind]);
    for (var event in events) {
      cacheManager.removeEvent(event.id);
    }
    await cacheManager.saveEvent(event);
    return list;
  }

}