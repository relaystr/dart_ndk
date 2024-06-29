import 'package:dart_ndk/nips/nip01/event.dart';

abstract class EventSigner {
  Future<void> sign(Nip01Event event);

  String getPublicKey();

  Future<String?> decrypt(String msg, String destPubKey, {String? id});

  Future<String?> encrypt(String msg, String destPubKey, {String? id});

  bool canSign();
}
