import 'dart:io';

import 'backend.dart';
import 'fallback_keystore_backend.dart';
import 'file_keystore_backend.dart';
import 'memory_keystore_backend.dart';
import 'platform_keystore_backend.dart';
import 'platform_options.dart';

/// Which storage implementation a keystore uses.
enum BackendType {
  /// In-process storage. Test-only: nothing survives the process, and it is not
  /// protected by anything.
  memory,

  /// One file per record in an application-chosen directory. Portable, and the
  /// protection is whatever the directory and the file modes provide.
  file,

  /// The operating system's own facility — AndroidKeyStore, the Apple keychain,
  /// DPAPI, or the Secret Service. Protection is the OS's, not this package's.
  platform,

  /// Secure platform storage with an opt-in file fallback in `path`, used
  /// only while the OS facility is unavailable (ADR-0010).
  platformWithFileFallback,
}

/// Creates the backend for [type].
///
/// [path] is required for [BackendType.file] and for the fallback variant.
/// [platformOptions] applies only to the platform backends.
///
/// Throws [ArgumentError] when [path] is required and missing. It does not fall
/// back to a weaker backend: silently substituting storage would mean the
/// application believes it has hardware-backed custody when it does not.
PqKeystoreBackend createBackend(
  BackendType type, {
  String? path,
  PlatformStoreOptions platformOptions = const PlatformStoreOptions(),
}) {
  switch (type) {
    case BackendType.memory:
      return MemoryKeystoreBackend();
    case BackendType.file:
      if (path == null) {
        throw ArgumentError('Path must be provided for FileKeystoreBackend');
      }
      return FileKeystoreBackend(Directory(path));
    case BackendType.platform:
      return PlatformKeystoreBackend(options: platformOptions);
    case BackendType.platformWithFileFallback:
      if (path == null) {
        throw ArgumentError('Path must be provided for the file fallback');
      }
      return FallbackKeystoreBackend(
        secure: PlatformKeystoreBackend(options: platformOptions),
        fallback: FileKeystoreBackend(Directory(path)),
      );
  }
}
