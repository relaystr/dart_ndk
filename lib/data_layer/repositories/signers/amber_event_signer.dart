import 'dart:convert';

import 'package:dart_ndk/domain_layer/entities/nip_01_event.dart';

import '../../../shared/nips/nip19/nip19.dart';
import '../../../domain_layer/repositories/event_signer.dart';
import '../../data_sources/amber_flutter.dart';

class AmberEventSigner implements EventSigner {
  final AmberFlutterDS amberFlutterDS;

  final String publicKey;

  AmberEventSigner(this.publicKey, this.amberFlutterDS);

  @override
  Future<void> sign(Nip01Event event) async {
    final npub = publicKey.startsWith('npub')
        ? publicKey
        : Nip19.encodePubKey(publicKey);
    Map<dynamic, dynamic> map = await amberFlutterDS.amber.signEvent(
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
    Map<dynamic, dynamic> map = await amberFlutterDS.amber.nip04Decrypt(
        ciphertext: msg, currentUser: npub, pubKey: destPubKey, id: id);
    return map['signature'];
  }

  @override
  Future<String?> encrypt(String msg, String destPubKey, {String? id}) async {
    final npub = publicKey.startsWith('npub')
        ? publicKey
        : Nip19.encodePubKey(publicKey);
    Map<dynamic, dynamic> map = await amberFlutterDS.amber.nip04Encrypt(
        plaintext: msg, currentUser: npub, pubKey: destPubKey, id: id);
    return map['signature'];
  }

  @override
  bool canSign() {
    return publicKey.isNotEmpty;
  }
}
