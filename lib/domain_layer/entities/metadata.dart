import 'dart:convert';

import 'package:dart_ndk/domain_layer/entities/nip_01_event.dart';
import 'package:dart_ndk/shared/nips/nip01/helpers.dart';

class Metadata {
  static const int KIND = 0;

  late String pubKey;
  String? name;
  String? displayName;
  String? picture;
  String? banner;
  String? website;
  String? about;
  String? nip05;
  String? lud16;
  String? lud06;
  int? updatedAt;
  int? refreshedTimestamp;

  Metadata(
      {this.pubKey = "",
      this.name,
      this.displayName,
      this.picture,
      this.banner,
      this.website,
      this.about,
      this.nip05,
      this.lud16,
      this.lud06,
      this.updatedAt,
      this.refreshedTimestamp});

  Metadata.fromJson(Map<String, dynamic> json) {
    name = json['name'];
    displayName = json['display_name'];
    picture = json['picture'];
    banner = json['banner'];
    website = json['website'];
    about = json['about'];
    try {
      nip05 = json['nip05'];
    } catch (e) {
      // sometimes people put maps in here
    }
    lud16 = json['lud16'];
    lud06 = json['lud06'];
  }

  String? get cleanNip05 {
    if (nip05 != null) {
      if (nip05!.startsWith("_@")) {
        return nip05!.trim().toLowerCase().replaceAll("_@", "@");
      }
      return nip05!.trim().toLowerCase();
    }
    return null;
  }

  Map<String, dynamic> toFullJson() {
    var data = toJson();
    data['pub_key'] = pubKey;
    return data;
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['name'] = name;
    data['display_name'] = displayName;
    data['picture'] = picture;
    data['banner'] = banner;
    data['website'] = website;
    data['about'] = about;
    data['nip05'] = nip05;
    data['lud16'] = lud16;
    data['lud06'] = lud06;
    return data;
  }

  static Metadata fromEvent(Nip01Event event) {
    Metadata metadata = Metadata();
    if (Helpers.isNotBlank(event.content)) {
      Map<String, dynamic> json = jsonDecode(event.content);
      metadata = Metadata.fromJson(json);
    }
    metadata.pubKey = event.pubKey;
    metadata.updatedAt = event.createdAt;
    return metadata;
  }

  Nip01Event toEvent() {
    return Nip01Event(
        pubKey: pubKey,
        content: jsonEncode(toJson()),
        kind: KIND,
        tags: [],
        createdAt: updatedAt ?? 0);
  }

  String getName() {
    if (displayName != null && Helpers.isNotBlank(displayName)) {
      return displayName!;
    }
    if (name != null && Helpers.isNotBlank(name)) {
      return name!;
    }
    return pubKey;
  }

  bool matchesSearch(String str) {
    str = str.trim().toLowerCase();
    String d = displayName != null ? displayName!.toLowerCase() : "";
    String n = name != null ? name!.toLowerCase() : "";
    String str2 = " $str";
    return d.startsWith(str) ||
        d.contains(str2) ||
        n.startsWith(str) ||
        n.contains(str2);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Metadata &&
          runtimeType == other.runtimeType &&
          pubKey == other.pubKey;

  @override
  int get hashCode => pubKey.hashCode;
}
