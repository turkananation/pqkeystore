import 'dart:typed_data';

sealed class UnlockMethod {
  const UnlockMethod();
}

final class PassphraseUnlock extends UnlockMethod {
  const PassphraseUnlock(this.passphrase);
  final Uint8List passphrase;

  @override
  String toString() => 'PassphraseUnlock(...)';
}

final class PlatformUnlock extends UnlockMethod {
  const PlatformUnlock();

  @override
  String toString() => 'PlatformUnlock()';
}

final class PassphraseThenPlatform extends UnlockMethod {
  const PassphraseThenPlatform(this.passphrase);
  final Uint8List passphrase;

  @override
  String toString() => 'PassphraseThenPlatform(...)';
}
