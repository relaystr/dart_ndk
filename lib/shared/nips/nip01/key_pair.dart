class KeyPair {
  /// [privateKey] is a 32-bytes hex-encoded string
  String? privateKey;

  /// [publicKey] is a 32-bytes hex-encoded string
  final String publicKey;

  /// [privateKeyBech32] is a human readable private key e.g. nsec
  String? privateKeyBech32;

  /// [publicKeyBech32] is a human readable public key e.g. npub
  String? publicKeyBech32;

  KeyPair(this.privateKey, this.publicKey, this.privateKeyBech32, this.publicKeyBech32);

  KeyPair.justPublicKey(this.publicKey);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is KeyPair &&
          runtimeType == other.runtimeType &&
          publicKey == other.publicKey;

  @override
  int get hashCode => publicKey.hashCode;
}
