import 'package:dart_ndk/nips/nip01/event.dart';
import 'package:dart_ndk/nips/nip01/helpers.dart';

import '../nip04/nip04.dart';
import 'bip340.dart';
import 'event_signer.dart';

class Bip340EventSigner implements EventSigner {
  String? privateKey;
  String publicKey;

  Bip340EventSigner(this.privateKey, this.publicKey);

  @override
  Future<void> sign(Nip01Event event) async {
    if (Helpers.isNotBlank(privateKey)) {
      event.sig = Bip340.sign(event.id, privateKey!);
    }
  }

  @override
  String getPublicKey() {
    return publicKey;
  }

  Future<String?> decrypt(String msg, String destPubKey, {String? id}) async {
    return Nip04.decrypt(privateKey!, destPubKey, msg);
  }

  Future<String?> encrypt(String msg, String destPubKey, {String? id}) async {
    return Nip04.encrypt(privateKey!, destPubKey, msg);
  }

  @override
  bool canSign() {
    return Helpers.isNotBlank(privateKey);
  }

  @override
  String? getPrivateKey() {
    return privateKey;
  }
}
