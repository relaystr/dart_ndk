import 'dart:convert';

import 'package:amberflutter/amberflutter.dart';
import 'package:dart_ndk/nips/nip01/event.dart';

import '../nip19/nip19.dart';
import 'event_signer.dart';

class AmberEventSigner implements EventSigner {
  final amber = Amberflutter();

  final String publicKey;

  AmberEventSigner(this.publicKey);

  @override
  Future<void> sign(Nip01Event event) async {
    final npub = publicKey.startsWith('npub')
        ? publicKey
        : Nip19.encodePubKey(publicKey);
    Map<dynamic, dynamic> map = await amber.signEvent(
        currentUser: npub, eventJson: jsonEncode(event.toJson()), id: event.id);
    if (map != null) {
      event.sig = map['signature'];
    }
  }

  @override
  String getPublicKey() {
    return publicKey;
  }

  @override
  Future<String?> decrypt(String msg, String destPubKey, {String? id}) async {
    final npub = publicKey.startsWith('npub')
        ? publicKey
        : Nip19.encodePubKey(publicKey);
    Map<dynamic, dynamic> map = await amber.nip04Decrypt(
        ciphertext: msg, currentUser: npub, pubKey: destPubKey, id: id);
    return map['signature'];
  }

  @override
  Future<String?> encrypt(String msg, String destPubKey, {String? id}) async {
    final npub = publicKey.startsWith('npub')
        ? publicKey
        : Nip19.encodePubKey(publicKey);
    Map<dynamic, dynamic> map = await amber.nip04Encrypt(
        plaintext: msg, currentUser: npub, pubKey: destPubKey, id: id);
    return map['signature'];
  }

  @override
  bool canSign() {
    return publicKey.isNotEmpty;
  }
}
