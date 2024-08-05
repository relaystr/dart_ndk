import 'dart:io';

import 'package:dart_ndk/data_layer/repositories/verifiers/bip340_event_verifier.dart';
import 'package:dart_ndk/domain_layer/entities/nip_01_event.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../../dart_ndk_platform_interface.dart';

class AcinqSecp256k1EventVerifier extends Bip340EventVerifier {
  static const platform = MethodChannel('flutter.native/helper');

  @override
  Future<bool> verify(Nip01Event event) async {
    if (kIsWeb) {
      /// TODO implement JS binding for fast verification with some JS lib
      return true;
    }
    if (Platform.isAndroid) {
      bool? result;
      try {
        result = await DartNdkPlatform.instance
            .verifySignature(event.sig, event.id, event.pubKey);
      } catch (e) {
        if (kDebugMode) {
          print(e);
        }
      }
      if (result != null) {
        return result;
      }
    }
    return await super.verify(event);
  }
}
