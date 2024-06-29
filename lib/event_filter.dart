import 'package:dart_ndk/nips/nip01/event.dart';

abstract class EventFilter {
  bool filter(Nip01Event event);
}
