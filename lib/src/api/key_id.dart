import 'package:meta/meta.dart';

@immutable
final class KeyId {
  const KeyId(this.value);

  final String value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is KeyId &&
          runtimeType == other.runtimeType &&
          value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() {
    if (value.length > 8) {
      return 'KeyId(${value.substring(0, 8)}...)';
    }
    return 'KeyId($value)';
  }
}
