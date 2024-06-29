import 'package:collection/collection.dart';

class RelayStats {
  int connections = 0;
  int connectionErrors = 0;
  Map<int, int> eventsRead = {}; // kind as keys, count as values
  Map<int, int> eventsWritten = {}; // kind as keys, count as values
  Map<int, int> dataReadBytes = {}; // kind as keys, bytes amount as values
  Map<int, int> dataWrittenBytes = {}; // kind as keys, bytes amount as values

  int getTotalEventsRead() {
    return eventsRead.values.sum;
  }

  int getTotalBytesRead() {
    return dataReadBytes.values.sum;
  }
}
