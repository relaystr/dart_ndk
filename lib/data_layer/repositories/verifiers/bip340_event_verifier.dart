import 'package:bip340/bip340.dart' as bip340;
import 'package:dart_ndk/domain_layer/entities/nip_01_event.dart';
import 'package:dart_ndk/domain_layer/repositories/event_verifier.dart';

class Bip340EventVerifier implements EventVerifier {
  @override
  Future<bool> verify(Nip01Event event) async {
    return bip340.verify(event.pubKey, event.id, event.sig);
  }
}
