import 'package:dart_ndk/domain_layer/entities/nip_01_event.dart';
import 'package:dart_ndk/domain_layer/entities/relay_info.dart';
import 'package:dart_ndk/domain_layer/entities/relay_stats.dart';

class Relay {
  String url;
  bool connecting = false;
  int? lastConnectTry;
  int? lastSuccessfulConnect;
  RelayInfo? info;
  RelayStats stats = RelayStats();

  Relay(this.url);

  bool supportsNip(int nip) {
    return info != null && info!.nips.contains(nip);
  }

  void tryingToConnect() {
    lastConnectTry = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    connecting = true;
  }

  void succeededToConnect() {
    lastSuccessfulConnect = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    connecting = false;
  }

  void failedToConnect() {
    connecting = false;
  }

  bool wasLastConnectTryLongerThanSeconds(int seconds) {
    return lastConnectTry == null ||
        lastConnectTry! <
            DateTime.now()
                    .add(Duration(seconds: -seconds))
                    .millisecondsSinceEpoch ~/
                1000;
  }

  void incStatsByNewEvent(Nip01Event event, int bytes) {
    int eventsRead = stats.eventsRead[event.kind] ?? 0;
    stats.eventsRead[event.kind] = eventsRead + 1;
    int bytesRead = stats.dataReadBytes[event.kind] ?? 0;
    stats.dataReadBytes[event.kind] = bytesRead + bytes;
  }
}
