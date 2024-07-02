import 'package:dart_ndk/nips/nip01/event.dart';
import 'package:dart_ndk/nips/nip01/event_verifier.dart';

class MockEventVerifier implements EventVerifier {
  bool _result = true;

  /// If [result] is false, [verify] will always return false. Default is true.
  MockEventVerifier({bool result = true}) {
    _result = result;
  }

  @override
  Future<bool> verify(Nip01Event event) async {
    return _result;
  }
}
