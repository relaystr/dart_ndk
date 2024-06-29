import 'dart:async';

import 'package:dart_ndk/bridges/rust/api/simple.dart';
import 'package:dart_ndk/bridges/rust/frb_generated.dart';
import 'package:dart_ndk/nips/nip01/event.dart';
import 'package:dart_ndk/nips/nip01/event_verifier.dart';

class RustEventVerifier implements EventVerifier {
  Completer<bool> isInitialized = Completer<bool>();

  RustEventVerifier() {
    init();
  }

  Future<bool> init() async {
    await RustLib.init();
    isInitialized.complete(true);
    return true;
  }

  @override
  Future<bool> verify(Nip01Event event) async {
    await isInitialized.future;

    //todo: check if id is correct

    // check signature

    final pubKey = event.pubKey;
    final id = event.id;
    final sig = event.sig;

    final result = await verifyEvent(id: id, pubkey: pubKey, sig: sig);

    return result;
  }
}
