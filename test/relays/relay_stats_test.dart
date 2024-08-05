import 'package:dart_ndk/domain_layer/entities/relay_stats.dart';
import 'package:flutter_test/flutter_test.dart';

void main() async {
  test('stats', () async {
    RelayStats stats = RelayStats();
    expect(0, stats.getTotalEventsRead());
    expect(0, stats.getTotalBytesRead());
  });
}
