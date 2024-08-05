import 'package:dart_ndk/domain_layer/usecases/relay_jit_manager/relay_jit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:developer' as developer;

void main() async {
  group("test creating RelayJit", skip: true, () {
    test('cleanUrl relayJit constructor', () async {
      RelayJit relayJit = RelayJit("wss://myrelay.com/");
      expect(relayJit.url, "wss://myrelay.com");
    });

    test('cleanUrl throws exception', () async {
      expect(() => RelayJit("myInvalidDomain"), throwsException);
    });
  });
}
