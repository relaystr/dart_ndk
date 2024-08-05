import 'package:dart_ndk/domain_layer/entities/nip_01_event.dart';

abstract class EventSigner {
  Future<void> sign(Nip01Event event);

  String getPublicKey();

  Future<String?> decrypt(String msg, String destPubKey, {String? id});

  Future<String?> encrypt(String msg, String destPubKey, {String? id});

  bool canSign();
}
