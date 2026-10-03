import 'dart:io';

import 'backend.dart';
import 'file_keystore_backend.dart';
import 'memory_keystore_backend.dart';
import 'platform_keystore_backend.dart';

enum BackendType {
  memory,
  file,
  platform,
}

PqKeystoreBackend createBackend(BackendType type, {String? path}) {
  switch (type) {
    case BackendType.memory:
      return MemoryKeystoreBackend();
    case BackendType.file:
      if (path == null) {
        throw ArgumentError('Path must be provided for FileKeystoreBackend');
      }
      return FileKeystoreBackend(Directory(path));
    case BackendType.platform:
      return PlatformKeystoreBackend();
  }
}
