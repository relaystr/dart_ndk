import 'package:amberflutter/amberflutter.dart';
import 'package:dart_ndk/dart_ndk.dart';
import 'package:dart_ndk/data_layer/data_sources/amber_flutter.dart';
import 'package:dart_ndk/presentation_layer/api.dart';

//? how a user might use the api
class Example {
  OurApi globalNDKobj = OurApi(
    NdkConfig(
      eventVerifier: Bip340EventVerifier(),
      eventSigner:
          AmberEventSigner("somePubkey", AmberFlutterDS(Amberflutter())),
      cache: MemCacheManager(),
      engine: NdkEngine.JIT,
    ),
  );

  main() async {
    //! advanced usecase
    dynamic imposterFilter = {"pretend this is a valid filter", "some data"};

    var myRequest = NdkRequest.query(
      "myrequest",
      filters: imposterFilter,
    );

    final myResponse = await globalNDKobj.requestNostrEvent(myRequest);
    final stream = myResponse.stream;
  }
}
