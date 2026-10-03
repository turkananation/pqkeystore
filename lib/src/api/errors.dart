import 'key_id.dart';

sealed class PqKeystoreError implements Exception {
  const PqKeystoreError();
}

final class NotFound extends PqKeystoreError {
  const NotFound(this.id);
  final KeyId id;
  @override
  String toString() => 'PqKeystoreError.NotFound($id)';
}

final class PlatformError extends PqKeystoreError {
  const PlatformError(this.message, {this.code});
  final String message;
  final String? code;
  @override
  String toString() => 'PqKeystoreError.PlatformError($message, code: $code)';
}

final class CryptoError extends PqKeystoreError {
  const CryptoError(this.message);
  final String message;
  @override
  String toString() => 'PqKeystoreError.CryptoError($message)';
}

final class FormatError extends PqKeystoreError {
  const FormatError(this.message);
  final String message;
  @override
  String toString() => 'PqKeystoreError.FormatError($message)';
}

final class Cancelled extends PqKeystoreError {
  const Cancelled();
  @override
  String toString() => 'PqKeystoreError.Cancelled()';
}

final class PolicyError extends PqKeystoreError {
  const PolicyError(this.message);
  final String message;
  @override
  String toString() => 'PqKeystoreError.PolicyError($message)';
}

sealed class KsResult<T> {
  const KsResult();

  R when<R>({
    required R Function(T) success,
    required R Function(PqKeystoreError) failure,
  });
}

final class KsSuccess<T> extends KsResult<T> {
  const KsSuccess(this.value);
  final T value;

  @override
  R when<R>({
    required R Function(T) success,
    required R Function(PqKeystoreError) failure,
  }) {
    return success(value);
  }
}

final class KsFailure<T> extends KsResult<T> {
  const KsFailure(this.error);
  final PqKeystoreError error;

  @override
  R when<R>({
    required R Function(T) success,
    required R Function(PqKeystoreError) failure,
  }) {
    return failure(error);
  }
}
