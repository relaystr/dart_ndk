import 'package:dart_ndk/domain_layer/entities/nip_01_event.dart';

abstract class EventFilter {
  bool filter(Nip01Event event);
}
