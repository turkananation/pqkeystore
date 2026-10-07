import 'dart:io';

import 'backend.dart';
import 'fallback_keystore_backend.dart';
import 'file_keystore_backend.dart';
import 'memory_keystore_backend.dart';
import 'platform_keystore_backend.dart';
import 'platform_options.dart';

enum BackendType {
  memory,
  file,
  platform,

  /// Secure platform storage with an opt-in file fallback in `path`, used
  /// only while the OS facility is unavailable (ADR-0010).
  platformWithFileFallback,
}

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
