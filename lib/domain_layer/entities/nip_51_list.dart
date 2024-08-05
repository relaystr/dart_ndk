import 'dart:convert';

import 'package:dart_ndk/domain_layer/repositories/event_signer.dart';
import 'package:dart_ndk/shared/nips/nip01/helpers.dart';
import 'package:flutter/foundation.dart';

import 'nip_01_event.dart';

class Nip51List {
  static const int MUTE = 10000;
  static const int PIN = 10001;
  static const int BOOKMARKS = 10003;
  static const int COMMUNITIES = 10004;
  static const int PUBLIC_CHATS = 10005;
  static const int BLOCKED_RELAYS = 10006;
  static const int SEARCH_RELAYS = 10007;
  static const int INTERESTS = 10015;
  static const int EMOJIS = 10030;

  static const int FOLLOW_SET = 30000;
  static const int RELAY_SET = 30002;
  static const int BOOKMARKS_SET = 30003;
  static const int CURATION_SET = 30004;
  static const int INTERESTS_SET = 30015;
  static const int EMOJIS_SET = 30030;

  static const String RELAY = "relay";
  static const String PUB_KEY = "p";
  static const String HASHTAG = "t";
  static const String WORD = "word";
  static const String THREAD = "e";
  static const String RESOURCE = "r";
  static const String EMOJI = "emoji";
  static const String A = "a";

  static const List<String> POSSIBLE_TAGS = [
    RELAY,
    PUB_KEY,
    HASHTAG,
    WORD,
    THREAD,
    RESOURCE,
    EMOJI,
    A
  ];

  late String id;
  late String pubKey;
  late int kind;

  List<Nip51ListElement> elements = [];

  List<Nip51ListElement> byTag(String tag) =>
      elements.where((element) => element.tag == tag).toList();

  List<Nip51ListElement> get relays => byTag(RELAY);
  List<Nip51ListElement> get pubKeys => byTag(PUB_KEY);
  List<Nip51ListElement> get hashtags => byTag(HASHTAG);
  List<Nip51ListElement> get words => byTag(WORD);
  List<Nip51ListElement> get threads => byTag(THREAD);

  List<String> get publicRelays =>
      relays.where((element) => !element.private).map((e) => e.value).toList();
  List<String> get privateRelays =>
      relays.where((element) => !element.private).map((e) => e.value).toList();

  set privateRelays(List<String> list) {
    elements.removeWhere((element) => element.tag == RELAY && element.private);
    elements.addAll(list
        .map((url) => Nip51ListElement(tag: RELAY, value: url, private: true)));
  }

  set publicRelays(List<String> list) {
    elements.removeWhere((element) => element.tag == RELAY && !element.private);
    elements.addAll(list.map(
        (url) => Nip51ListElement(tag: RELAY, value: url, private: false)));
  }

  late int createdAt;

  @override
  // coverage:ignore-start
  String toString() {
    return 'Nip51List { $kind}';
  }
  // coverage:ignore-end

  String get displayTitle {
    if (kind == Nip51List.SEARCH_RELAYS) {
      return "Search";
    }
    if (kind == Nip51List.BLOCKED_RELAYS) {
      return "Blocked";
    }
    if (kind == Nip51List.MUTE) {
      return "Mute";
    }
    return "kind $kind";
  }

  List<String> get allRelays => relays.map((e) => e.value).toList();

  Nip51List(
      {required this.pubKey,
      required this.kind,
      required this.createdAt,
      required this.elements});

  static Future<Nip51List> fromEvent(
      Nip01Event event, EventSigner? signer) async {
    // if (event.kind == Nip51List.SEARCH_RELAYS || event.kind == Nip51List.BLOCKED_RELAYS) {
    //   privateRelays = [];
    //   publicRelays = [];
    // }
    Nip51List list = Nip51List(
        pubKey: event.pubKey,
        kind: event.kind,
        createdAt: event.createdAt,
        elements: []);
    list.id = event.id;

    list.parseTags(event.tags, private: false);

    if (Helpers.isNotBlank(event.content) &&
        signer != null &&
        signer.canSign()) {
      try {
        var json = await signer.decrypt(event.content, signer.getPublicKey());
        List<dynamic> tags = jsonDecode(json ?? '');
        list.parseTags(tags, private: true);
      } catch (e) {
        if (kDebugMode) {
          print(e);
        }
      }
    }
    return list;
  }

  void parseTags(List tags, {required bool private}) {
    for (var tag in tags) {
      if (tag is! List<dynamic>) continue;
      final length = tag.length;
      if (length <= 1) continue;
      final tagName = tag[0];
      final value = tag[1];
      if (POSSIBLE_TAGS.contains(tagName)) {
        elements.add(
            Nip51ListElement(tag: tagName, value: value, private: private));
      }
    }
  }

  Future<Nip01Event> toEvent(EventSigner? signer) async {
    String content = "";
    List<Nip51ListElement> privateElements =
        elements.where((element) => element.private).toList();
    if (privateElements.isNotEmpty && signer != null) {
      String json = jsonEncode(privateElements
          .map((element) => [element.tag, element.value])
          .toList());
      content = await signer.encrypt(json, signer.getPublicKey()) ?? '';
    }
    Nip01Event event = Nip01Event(
      pubKey: pubKey,
      kind: kind,
      tags: elements
          .where((element) => !element.private)
          .map((element) => [element.tag, element.value])
          .toList(),
      content: content,
      createdAt: createdAt,
    );
    return event;
  }

  void addRelay(String relayUrl, bool private) {
    elements
        .add(Nip51ListElement(tag: RELAY, value: relayUrl, private: private));
  }

  void addElement(String tag, String value, bool private) {
    elements.add(Nip51ListElement(tag: tag, value: value, private: private));
  }

  void removeRelay(String relayUrl) {
    elements.removeWhere(
        (element) => element.tag == RELAY && element.value == relayUrl);
  }

  void removeElement(String tag, String value) {
    elements
        .removeWhere((element) => element.tag == tag && element.value == value);
  }
}

class Nip51ListElement {
  bool private;
  String tag;
  String value;

  Nip51ListElement(
      {required this.tag, required this.value, required this.private});
}

class Nip51Set extends Nip51List {
  late String name;
  String? title;
  String? description;
  String? image;

  @override
  // coverage:ignore-start
  String toString() {
    return 'Nip51Set { $name}';
  }
  // coverage:ignore-end

  Nip51Set(
      {required String pubKey,
      required this.name,
      required int createdAt,
      required List<Nip51ListElement> elements,
      this.title})
      : super(
            pubKey: pubKey,
            kind: Nip51List.RELAY_SET,
            elements: elements,
            createdAt: createdAt);

  static Future<Nip51Set?> fromEvent(
      Nip01Event event, EventSigner? signer) async {
    String? name = event.getDtag();
    if (name == null || event.kind != Nip51List.RELAY_SET) {
      return null;
    }
    Nip51Set set = Nip51Set(
        pubKey: event.pubKey,
        name: name,
        createdAt: event.createdAt,
        elements: []);
    set.id = event.id;
    if (Helpers.isNotBlank(event.content) &&
        signer != null &&
        signer.canSign()) {
      try {
        var json = await signer.decrypt(event.content, signer.getPublicKey());
        List<dynamic> tags = jsonDecode(json ?? '');
        set.parseTags(tags, private: true);
        set.parseSetTags(tags);
      } catch (e) {
        set.name = "<invalid encrypted content>";
        if (kDebugMode) {
          print(e);
        }
      }
    } else {
      set.parseTags(event.tags, private: false);
      set.parseSetTags(event.tags);
    }
    return set;
  }

  @override
  Future<Nip01Event> toEvent(EventSigner? signer) async {
    Nip01Event event = await super.toEvent(signer);
    List<dynamic> tags = [
      ["d", name]
    ];
    if (Helpers.isNotBlank(image)) {
      tags.add(["description", description]);
    }
    if (Helpers.isNotBlank(image)) {
      tags.add(["image", image]);
    }
    tags.addAll(event.tags);
    event.tags = tags;
    return event;
  }

  void parseSetTags(List tags) {
    for (var tag in tags) {
      if (tag is! List<dynamic>) continue;
      final length = tag.length;
      if (length <= 1) continue;
      final tagName = tag[0];
      final value = tag[1];
      if (tagName == "d") {
        name = value;
        continue;
      }
      if (tagName == "title") {
        title = value;
        continue;
      }
      if (tagName == "description") {
        description = value;
        continue;
      }
      if (tagName == "image") {
        image = value;
        continue;
      }
    }
  }
}
