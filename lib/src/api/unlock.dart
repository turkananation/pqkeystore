import 'dart:typed_data';

/// How a stored record is unlocked.
///
/// A sealed hierarchy, so a `switch` over it is checked for exhaustiveness at
/// compile time and a new unlock method becomes a compile error everywhere it is
/// handled:
///
/// ```dart
/// final label = switch (unlock) {
///   PassphraseUnlock() => 'passphrase',
///   PassphraseThenPlatform() => 'passphrase + device',
///   PlatformUnlock() => 'device',
/// };
/// ```
sealed class UnlockMethod {
  /// Const constructor so the subclasses can be const.
  const UnlockMethod();
}

/// Unlocked with a passphrase held by the application.
///
/// The passphrase is caller-supplied secret material. The caller remains
/// responsible for its lifetime; the keystore wipes the buffers it derives from
/// it, but it cannot wipe the caller's `Uint8List`.
final class PassphraseUnlock extends UnlockMethod {
  /// Unlocks with [passphrase].
  const PassphraseUnlock(this.passphrase);

  /// The passphrase bytes.
  ///
  /// Treated as secret by this package: never logged, and wiped from any
  /// derived buffer.
  final Uint8List passphrase;

  /// Never prints the passphrase.
  @override
  String toString() => 'PassphraseUnlock(...)';
}

/// Unlocked by the operating system alone.
///
/// No passphrase is involved; the OS decides whether to release the record, for
/// example by requiring user presence or device unlock.
///
/// **Not accepted in format version 1.** `PqKeystore.put` rejects it with a
/// `PolicyError`, because the shipped provider cannot honour a device-only
/// unlock and silently treating it as no protection would be worse than
/// refusing. It is part of the API so callers can express the intent and get a
/// clear error rather than an accidental downgrade.
final class PlatformUnlock extends UnlockMethod {
  /// Requests an OS-mediated unlock.
  const PlatformUnlock();

  @override
  String toString() => 'PlatformUnlock()';
}

/// Unlocked with a passphrase **and** by the operating system.
///
/// Two independent factors: a passphrase the application supplies, and a device
/// gate the OS enforces.
///
/// Like [PlatformUnlock], the shipped provider treats this as passphrase-only
/// in format version 1. The difference is deliberate — this one asks for *more*
/// protection than it receives, so a record written under it must not be
/// mistaken for one protected by two factors.
final class PassphraseThenPlatform extends UnlockMethod {
  /// Unlocks with [passphrase] and an OS-mediated check.
  const PassphraseThenPlatform(this.passphrase);

  /// The passphrase bytes.
  ///
  /// Treated as secret by this package: never logged, and wiped from any
  /// derived buffer.
  final Uint8List passphrase;

  /// Never prints the passphrase.
  @override
  String toString() => 'PassphraseThenPlatform(...)';
}
