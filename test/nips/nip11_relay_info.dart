import 'package:dart_ndk/domain_layer/entities/relay_info.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('relay info', () {
    test('from json', () {
      final Map<String, dynamic> data = <String, dynamic>{};
      data['name'] = "name";
      data['description'] = "description";
      data['pubkey'] = "admin pubKey";
      data['contact'] = "bla@bla.com";
      data['supported_nips'] = [1, 50];
      data["payments_url"] = "https://my-relay/payments";
      data["fees"] = {
        "admission": [
          {"amount": 1000000, "unit": "msats"}
        ],
        "subscription": [
          {"amount": 5000000, "unit": "msats", "period": 2592000}
        ],
        "publication": [
          {
            "kinds": [4],
            "amount": 100,
            "unit": "msats"
          }
        ],
      };
      data['icon'] = "https://bla.com/favicon.ico";
      data['software'] = "https://github.com/bla";
      data['version'] = "1.0";
      RelayInfo info = RelayInfo.fromJson(data, "wss://bla.com");

      expect(data['name'], info.name);
      expect(data['description'], info.description);
      expect(data['pubkey'], info.pubKey);
      expect(data['contact'], info.contact);
      expect(data['supported_nips'], info.nips);
      expect(data['icon'], info.icon);
      expect(data['software'], info.software);
      expect(data['version'], info.version);
    });
  });
}
