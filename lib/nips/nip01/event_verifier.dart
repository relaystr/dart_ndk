import 'package:dart_ndk/nips/nip01/event.dart';

abstract class EventVerifier {
  Future<bool> verify(Nip01Event event);
}
