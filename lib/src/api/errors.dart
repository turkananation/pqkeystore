import 'key_id.dart';

/// The sealed set of failures the keystore reports.
///
/// Every public operation returns a [KsResult] rather than throwing, so a caller
/// handles failure by pattern-matching the error type instead of catching
/// `Exception`. That makes the failure modes visible in the signature rather
/// than at a catch site.
///
/// The subtypes are:
///
/// - [NotFound] — no record exists for the requested id.
/// - [PlatformError] — the OS storage facility refused or was unavailable;
///   carries a [PlatformError.code] when the native side supplied one.
/// - [CryptoError] — wrapping or unwrapping failed.
/// - [FormatError] — stored bytes were malformed, truncated, or failed an
///   identity check.
/// - [Cancelled] — the user dismissed an authentication or unlock prompt.
/// - [PolicyError] — the request violated a documented rule of this package.
///
/// [NotFound] deliberately does not distinguish "never existed" from "deleted":
/// reporting which would leak the existence of a record to an attacker who can
/// probe ids.
sealed class PqKeystoreError implements Exception {
  /// Const constructor so the hierarchy stays usable in const contexts.
  const PqKeystoreError();
}

/// No record exists for [id].
///
/// Also returned for a record that was deleted. The two are intentionally
/// indistinguishable.
final class NotFound extends PqKeystoreError {
  /// Creates a not-found error for [id].
  const NotFound(this.id);

  /// The id that was looked up.
  final KeyId id;

  @override
  String toString() => 'PqKeystoreError.NotFound($id)';
}

/// The operating system's storage facility refused the operation.
///
/// [code] carries the native side's stable error code when one was supplied —
/// for example `UNSUPPORTED_OPTION` or `LOCKED`. A null [code] means the failure
/// originated in the Dart layer rather than in the platform channel.
final class PlatformError extends PqKeystoreError {
  /// Creates a platform error with a human-readable [message] and an optional
  /// native [code].
  const PlatformError(this.message, {this.code});

  /// Human-readable description of what the platform refused.
  final String message;

  /// Stable machine-readable code from the native side, when available.
  final String? code;

  @override
  String toString() => 'PqKeystoreError.PlatformError($message, code: $code)';
}

/// Wrapping or unwrapping failed.
///
/// This covers a wrong passphrase, a failed authentication tag, and an
/// invalidated platform key. It does not cover a malformed record, which is a
/// [FormatError] — the two are kept distinct so a caller can tell "you typed the
/// wrong passphrase" from "this store is corrupt".
final class CryptoError extends PqKeystoreError {
  /// Creates a crypto error with a human-readable [message].
  const CryptoError(this.message);

  /// Human-readable description of the cryptographic failure.
  final String message;

  @override
  String toString() => 'PqKeystoreError.CryptoError($message)';
}

/// Stored bytes were malformed, truncated, or failed an identity check.
///
/// Returned before the crypto adapter is invoked when a record's metadata does
/// not match its authenticated data, so a tampered record never reaches
/// unwrapping.
final class FormatError extends PqKeystoreError {
  /// Creates a format error with a human-readable [message].
  const FormatError(this.message);

  /// Human-readable description of what was malformed.
  final String message;

  @override
  String toString() => 'PqKeystoreError.FormatError($message)';
}

/// The user dismissed an authentication or unlock prompt.
///
/// Distinct from [CryptoError] because retrying is reasonable: the operation was
/// declined, not refused.
final class Cancelled extends PqKeystoreError {
  /// Creates a cancellation error.
  const Cancelled();

  @override
  String toString() => 'PqKeystoreError.Cancelled()';
}

/// The request violated a documented rule of this package.
///
/// Returned for unsupported unlock combinations, invalid metadata, and misuse of
/// the API. It never indicates a hardware or storage failure — those are
/// [PlatformError].
final class PolicyError extends PqKeystoreError {
  /// Creates a policy error with a human-readable [message].
  const PolicyError(this.message);

  /// Human-readable description of the rule that was violated.
  final String message;

  @override
  String toString() => 'PqKeystoreError.PolicyError($message)';
}

/// The result of an operation: either a [KsSuccess] carrying a [T], or a
/// [KsFailure] carrying a [PqKeystoreError].
///
/// Use [when] to destructure exhaustively:
///
/// ```dart
/// final outcome = await keystore.use(id, unlock, (key) => sign(key));
/// return outcome.when(
///   success: (signature) => signature,
///   failure: (error) => throw error,
/// );
/// ```
sealed class KsResult<T> {
  /// Const constructor so concrete results can be const.
  const KsResult();

  /// Collapses this result into a single value of type [R].
  ///
  /// Exactly one of [success] or [failure] is invoked. This is the preferred way
  /// to consume a result, because it makes both branches mandatory at the call
  /// site.
  R when<R>({
    required R Function(T) success,
    required R Function(PqKeystoreError) failure,
  });
}

/// A successful result carrying [value].
final class KsSuccess<T> extends KsResult<T> {
  /// Creates a success carrying [value].
  const KsSuccess(this.value);

  /// The operation's result.
  final T value;

  @override
  R when<R>({
    required R Function(T) success,
    required R Function(PqKeystoreError) failure,
  }) {
    return success(value);
  }
}

/// A failed result carrying [error].
final class KsFailure<T> extends KsResult<T> {
  /// Creates a failure carrying [error].
  const KsFailure(this.error);

  /// Why the operation failed.
  final PqKeystoreError error;

  @override
  R when<R>({
    required R Function(T) success,
    required R Function(PqKeystoreError) failure,
  }) {
    return failure(error);
  }
}
