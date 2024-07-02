import 'package:dart_ndk/nips/nip01/event.dart';
import 'package:dart_ndk/nips/nip11/relay_info.dart';
import 'package:dart_ndk/relay_stats.dart';

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

  static RegExp RELAY_URL_REGEX = RegExp(
      r'^(wss?:\/\/)([0-9]{1,3}(?:\.[0-9]{1,3}){3}|[^:]+):?([0-9]{1,5})?$');

  static String? cleanUrl(String adr) {
    if (adr.endsWith("/")) {
      adr = adr.substring(0, adr.length - 1);
    }
    if (adr.contains("%")) {
      adr = Uri.decodeComponent(adr);
    }
    adr = adr.trim();
    if (!adr.contains(RELAY_URL_REGEX)) {
      return null;
    }
    return adr;
  }

  void incStatsByNewEvent(Nip01Event event, int bytes) {
    int eventsRead = stats.eventsRead[event.kind] ?? 0;
    stats.eventsRead[event.kind] = eventsRead + 1;
    int bytesRead = stats.dataReadBytes[event.kind] ?? 0;
    stats.dataReadBytes[event.kind] = bytesRead + bytes;
  }
}
