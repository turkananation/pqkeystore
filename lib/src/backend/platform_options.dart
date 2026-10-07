// Copyright 2024–2026 Yardenah / Turkana Nation. MIT license.
//
// Storage-policy options for PlatformKeystoreBackend.
//
// Every non-default option is an *enforcement request*: the native side must
// either enforce it or fail with UNSUPPORTED_OPTION. Nothing is silently
// ignored. See doc/PLATFORM_CONTRACT.md §5 for the per-platform matrix.

import '../api/errors.dart';
import 'platform_contract.dart';

/// When the OS should allow access to a stored record.
enum PlatformAccessibility {
  /// The platform's documented default. Requests no extra enforcement and is
  /// accepted on every platform. See doc/PLATFORM.md for what each OS does.
  platformDefault,

  /// Only while the device is unlocked.
  ///
  /// Apple: `kSecAttrAccessibleWhenUnlocked[ThisDeviceOnly]`.
  /// Android (API 28+, secure lock screen): `setUnlockedDeviceRequired`.
  /// Windows/Linux: unsupported.
  whenUnlocked,

  /// After the first unlock following a reboot.
  ///
  /// Apple: `kSecAttrAccessibleAfterFirstUnlock[ThisDeviceOnly]`.
  /// Android (file-based encryption + secure lock screen): credential-
  /// encrypted storage. Windows/Linux: unsupported.
  afterFirstUnlock;

  /// Channel wire value.
  String get wireName => switch (this) {
    PlatformAccessibility.platformDefault =>
      PlatformContract.accessibilityPlatformDefault,
    PlatformAccessibility.whenUnlocked =>
      PlatformContract.accessibilityWhenUnlocked,
    PlatformAccessibility.afterFirstUnlock =>
      PlatformContract.accessibilityAfterFirstUnlock,
  };
}

/// Storage-policy options applied when a record is written.
final class PlatformStoreOptions {
  /// Creates options. The defaults request no extra enforcement and are
  /// accepted on all five platforms.
  const PlatformStoreOptions({
    this.requireUserPresence = false,
    this.requireBiometric = false,
    this.accessibility = PlatformAccessibility.platformDefault,
    this.synchronizable = false,
  });

  /// Require device-owner authentication (biometric or passcode) to read.
  final bool requireUserPresence;

  /// Require biometric authentication, invalidated if enrollment changes.
  final bool requireBiometric;

  /// When the record may be accessed.
  final PlatformAccessibility accessibility;

  /// Allow OS cloud synchronization (Apple iCloud Keychain only).
  ///
  /// Mutually exclusive with [requireUserPresence] and [requireBiometric].
  final bool synchronizable;

  /// Capability names (see [PlatformContract.capabilities]) these options
  /// require the native side to enforce.
  Set<String> get requiredCapabilities => {
    if (requireUserPresence) PlatformContract.capRequireUserPresence,
    if (requireBiometric) PlatformContract.capRequireBiometric,
    if (accessibility == PlatformAccessibility.whenUnlocked)
      PlatformContract.capAccessibilityWhenUnlocked,
    if (accessibility == PlatformAccessibility.afterFirstUnlock)
      PlatformContract.capAccessibilityAfterFirstUnlock,
    if (synchronizable) PlatformContract.capSynchronizable,
  };

  /// Validates platform-independent option rules.
  ///
  /// Throws [PlatformError] with [PlatformErrorCode.unsupportedOption].
  void validateCombination() {
    if (synchronizable && (requireUserPresence || requireBiometric)) {
      throw const PlatformError(
        'synchronizable cannot be combined with user presence or biometric '
        'access control',
        code: PlatformErrorCode.unsupportedOption,
      );
    }
  }

  /// Wire representation. All four keys are always present.
  Map<String, Object> toChannelMap() => {
    PlatformContract.optRequireUserPresence: requireUserPresence,
    PlatformContract.optRequireBiometric: requireBiometric,
    PlatformContract.optAccessibility: accessibility.wireName,
    PlatformContract.optSynchronizable: synchronizable,
  };

  @override
  String toString() => 'PlatformStoreOptions($requiredCapabilities)';
}
