import 'package:dart_ndk/relay_info.dart';
import 'package:dart_ndk/relay_stats.dart';

class Relay {
  String url;
  bool connecting = false;
  RelayInfo? info;
  RelayStats? stats;

  Relay(this.url);

  @override
  bool operator ==(covariant Relay other) {
    return url == other.url;
  }

  @override
  int get hashCode => url.hashCode;

  bool supportsNip(int nip) {
    return info != null && info!.nips.contains(nip);
  }
}
