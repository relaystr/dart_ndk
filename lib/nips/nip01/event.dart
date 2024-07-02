import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dart_ndk/nips/nip01/bip340.dart';

class Nip01Event {
  static const int TEXT_NODE_KIND = 1;

  /// Creates a new Nostr event.
  ///
  /// [pubKey] is the author's public key.
  /// [kind] is the event kind.
  /// [tags] is a JSON object of event tags.
  /// [content] is an arbitrary string.
  ///
  /// Nostr event `id` and `created_at` fields are calculated automatically.
  ///
  Nip01Event({
    required this.pubKey,
    required this.kind,
    required this.tags,
    required this.content,
    int createdAt = 0,
  }) {
    this.createdAt = (createdAt == 0)
        ? DateTime.now().millisecondsSinceEpoch ~/ 1000
        : createdAt;
    id = _calculateId(pubKey, this.createdAt, kind, tags, content);
  }

  Nip01Event._(
    this.id,
    this.pubKey,
    this.createdAt,
    this.kind,
    this.tags,
    this.content,
    this.sig,
  );

  factory Nip01Event.fromJson(Map<dynamic, dynamic> data) {
    final id = data['id'] as String;
    final pubKey = data['pubkey'] as String;
    final createdAt = data['created_at'] as int;
    final kind = data['kind'] as int;
    final tags = data['tags'];
    final content = data['content'] as String;
    final sig = data['sig'] as String;

    return Nip01Event._(id, pubKey, createdAt, kind, tags, content, sig);
  }

  /// The event ID is a 32-byte SHA256 hash of the serialised event data.
  String id = '';

  /// The event author's public key.
  final String pubKey;

  /// Event creation timestamp in Unix time.
  late int createdAt;

  /// Event kind identifier (e.g. text_note, set_metadata, etc).
  final int kind;

  /// A JSON array of event tags.
  List<dynamic> tags; // Modified by proof-of-work

  /// Event content.
  String content;

  /// 64-byte Schnorr signature of [Nip01Event.id].
  String sig = '';

  bool? validSig;

  /// Relay that an event was received from
  List<String> sources = [];

  /// Returns the Event object as a JSON object
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'pubkey': pubKey,
      'created_at': createdAt,
      'kind': kind,
      'tags': tags,
      'content': content,
      'sig': sig
    };
  }

  void sign(String privateKey) {
    sig = Bip340.sign(id, privateKey);
  }

  bool get isIdValid {
    // Validate event data
    if (id != _calculateId(pubKey, createdAt, kind, tags, content)) {
      return false;
    }
    return true;
  }

  // Individual events with the same "id" are equivalent
  @override
  bool operator ==(other) => other is Nip01Event && id == other.id;
  @override
  int get hashCode => id.hashCode;

  static int _secondsSinceEpoch() {
    final secondsSinceEpoch = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return secondsSinceEpoch;
  }

  static String _calculateId(String publicKey, int createdAt, int kind,
      List<dynamic> tags, String content) {
    final jsonData =
        json.encode([0, publicKey, createdAt, kind, tags, content]);
    final bytes = utf8.encode(jsonData);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  String? getEId() {
    for (var tag in tags) {
      if (tag.length > 1) {
        var key = tag[0];
        var value = tag[1];

        if (key == "e") {
          return value as String;
        }
      }
    }
    return null;
  }

  static List<String> getTags(List<dynamic> list, String tag) {
    List<String> tags = [];
    for (var e in list) {
      if (e.length > 1) {
        var key = e[0];
        var value = e[1];

        if (key == tag) {
          tags.add(value.toString().trim().toLowerCase());
        }
      }
    }
    return tags;
  }

  List<String> get tTags {
    return getTags(tags, "t");
  }

  List<String> get pTags {
    return getTags(tags, "p");
  }

  String? getDtag() {
    for (var tag in tags) {
      if (tag.length > 1) {
        var key = tag[0];
        var value = tag[1];

        if (key == "d") {
          return value as String;
        }
      }
    }
    return null;
  }

  @override
  String toString() {
    return 'Nip01Event{pubKey: $pubKey, createdAt: $createdAt, kind: $kind, tags: $tags, content: $content, sources: $sources}';
  }
}
