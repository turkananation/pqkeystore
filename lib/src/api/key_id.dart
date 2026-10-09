import 'package:meta/meta.dart';

/// The identifier a record is stored and looked up under.
///
/// An id is an opaque, application-chosen label. The keystore never interprets
/// its contents, and never derives a filesystem name from it directly — file
/// backends store records as `hex(SHA-256(UTF-8 ID)).pqks` and read the real id
/// back out of the record's own header, so an id cannot escape the store
/// directory whatever it contains.
///
/// ## Comparison
///
/// Equality and hashing use the exact string. No Unicode normalisation and no
/// case folding are applied, because either would make two ids that the
/// application considers distinct collide in the store. A caller that needs
/// case-insensitive behaviour should normalise before constructing the id.
@immutable
final class KeyId {
  /// Creates an id from [value].
  const KeyId(this.value);

  /// The raw id text.
  final String value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is KeyId &&
          runtimeType == other.runtimeType &&
          value == other.value;

  @override
  int get hashCode => value.hashCode;

  /// A shortened form for logs.
  ///
  /// Ids longer than eight characters are truncated. `toString` is for
  /// diagnostics; it is lossy and must not be parsed.
  @override
  String toString() {
    if (value.length > 8) {
      return 'KeyId(${value.substring(0, 8)}...)';
    }
    return 'KeyId($value)';
  }
}
