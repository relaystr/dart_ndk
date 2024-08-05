import '../config/bootstrap_relays.dart';
import '../domain_layer/repositories/cache_manager.dart';
import '../domain_layer/repositories/event_signer.dart';
import '../domain_layer/repositories/event_verifier.dart';

class NdkConfig {
  EventVerifier eventVerifier;

  EventSigner eventSigner;

  /// db to cache nostr data
  CacheManager cache;

  /// nostr network engine to use (choose inbox/outbox mode)
  NdkEngine engine;

  /// relays are not considers for inbox/outbox
  List<String> ignoreRelays;

  /// initial relays to use and discover for inbox/outbox
  List<String> bootstrapRelays;

  NdkConfig({
    required this.eventVerifier,
    required this.eventSigner,
    required this.cache,
    this.engine = NdkEngine.LISTS,
    this.ignoreRelays = const [],
    this.bootstrapRelays = DEFAULT_BOOTSTRAP_RELAYS,
  });
}

// ignore: constant_identifier_names
enum NdkEngine { LISTS, JIT }
