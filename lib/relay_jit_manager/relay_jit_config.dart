class RelayJitConfig {
  static const int DEFAULT_WEB_SOCKET_CONNECT_TIMEOUT = 3;
  static const int DEFAULT_STREAM_IDLE_TIMEOUT = 5;
  static const int DEFAULT_BEST_RELAYS_MIN_COUNT = 2;
  static const int FAIL_RELAY_CONNECT_TRY_AFTER_SECONDS = 60;
  static const int WEB_SOCKET_PING_INTERVAL_SECONDS = 3;
  static const List<String> SEED_RELAYS = [
    'wss://relay.camelus.app',
    'wss://relay.snort.social',
    'wss://relay.damus.io',
    'wss://nostr.lu.ke',
    'wss://relay.mostr.pub'
  ];
}
