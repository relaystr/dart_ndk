import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class Nip05 {

  String pubKey;
  String nip05;
  bool valid;
  int updatedAt;

  Nip05({required this.pubKey, required this.nip05, required this.valid, required this.updatedAt});

  bool needsUpdate(Duration duration) => updatedAt < (DateTime.now().subtract(duration).millisecondsSinceEpoch ~/ 1000);

  static Future<bool> check(String nip05Address, String pubkey) async {
    var name = "_";
    var address = nip05Address;
    var strs = nip05Address.split("@");
    if (strs.length > 1) {
      name = strs[0];
      address = strs[1];
    }

    var url = "https://$address/.well-known/nostr.json?name=$name";
    try {
      Uri uri = Uri.parse(url).replace(scheme: 'https');

      var response = await http.get(uri);

      final data = jsonDecode(
          utf8.decode(response.bodyBytes)) as Map;
      if (data["names"] != null) {
        var dataPubkey = data["names"][name];
        if (dataPubkey != null && dataPubkey == pubkey) {
          return true;
        }
      }
        } catch (e) {
      if (kDebugMode) {
        print(e);
      }
    }
    return false;
  }
}
