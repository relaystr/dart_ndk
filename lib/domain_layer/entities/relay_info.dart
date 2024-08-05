import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class RelayInfo {

  final String name;

  final String description;

  /// Nostr public key of the relay admin
  final String pubKey;

  /// Alternative contact of the relay admin
  final String contact;

  /// Supported NIPS
  final List<dynamic> nips;

  /// Software description
  final String software;

  /// Relay icon
  final String icon;

  /// Relay software version identifier
  final String version;

  RelayInfo._(this.name, this.description, this.pubKey, this.contact, this.nips,
      this.software, this.version, this.icon);

  factory RelayInfo.fromJson(Map<dynamic, dynamic> json, String url) {
    final String name = json["name"] ?? '';
    final String description = json["description"] ?? "";
    final String pubKey = json["pubkey"] ?? "";
    final String contact = json["contact"] ?? "";
    String icon;
    if (json["icon"]!=null) {
      icon = json["icon"];
    } else {
      icon = "$url${url.endsWith("/")?"":"/"}favicon.ico";
    }
    final List<dynamic> nips = json["supported_nips"] ?? [];
    final String software = json["software"] ?? "";
    final String version = json["version"] ?? "";
    return RelayInfo._(
        name, description, pubKey, contact, nips, software, version, icon);
  }

  static Future<RelayInfo?> get(String url) async {
    Uri uri = Uri.parse(url).replace(scheme: 'https');
    try {
      final response = await http.get(uri,
        headers: {'Accept': 'application/nostr+json'},
      );
      final decodedResponse = jsonDecode(
          utf8.decode(response.bodyBytes)) as Map;
      return RelayInfo.fromJson(decodedResponse, uri.toString());
    } catch (e) {
      if (kDebugMode) {
        print(e);
      }
      return null;
    }
  }
}