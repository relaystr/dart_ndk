import 'package:dart_ndk/dart_ndk.dart';
import 'package:dart_ndk/shared/nips/nip01/bip340.dart';
import 'package:dart_ndk/domain_layer/entities/nip_01_event.dart';
import 'package:dart_ndk/domain_layer/entities/metadata.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hex/hex.dart';

void main() {
  group('Bip340', () {
    test('sign and verify', () {
      final keyPair = Bip340.generatePrivateKey();
      const message = 'Hello, World!';
      // message to HEX
      final messageHex = HEX.encode(message.codeUnits);
      final signature = Bip340.sign(messageHex, keyPair.privateKey!);
      expect(Bip340.verify(messageHex, signature, keyPair.publicKey), isTrue);
    });

    test('getPublicKey', () {
      final keyPair = Bip340.generatePrivateKey();
      expect(
          Bip340.getPublicKey(keyPair.privateKey!), equals(keyPair.publicKey));
    });
  });
  group('Metadata', () {
    test('to/from json/event', () {
      final Map<String, dynamic> data = <String, dynamic>{};
      data['name'] = "name";
      data['display_name'] = "display name";
      data['picture'] = "https://bla.com/picture.jpg";
      data['banner'] = "https://bla.com/banner.jpg";
      data['website'] = "https://bla.com";
      data['about'] = "about...";
      data['nip05'] = "bla@bla.com";
      data['lud16'] = "bla@bla.com";
      data['lud06'] = "bla@bla.com";

      Metadata metadata = Metadata.fromJson(data);
      metadata.pubKey = "pubKey1";
      Map<String, dynamic> toJson = <String, dynamic>{};
      toJson = metadata.toJson();
      expect(data, toJson);

      Nip01Event event = metadata.toEvent();
      Metadata metadataFromEvent = Metadata.fromEvent(event);
      expect(metadata, metadataFromEvent);
    });
  });
}
