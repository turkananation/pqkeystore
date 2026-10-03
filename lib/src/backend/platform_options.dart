final class PlatformStoreOptions {

  const PlatformStoreOptions({
    this.requireUserPresence = false,
    this.requireBiometric = false,
    this.accessibleWhenUnlocked = true,
    this.synchronizable = false,
  });
  final bool requireUserPresence;
  final bool requireBiometric;
  final bool accessibleWhenUnlocked;
  final bool synchronizable;

  Map<String, dynamic> toChannelMap() {
    return {
      'requireUserPresence': requireUserPresence,
      'requireBiometric': requireBiometric,
      'accessibleWhenUnlocked': accessibleWhenUnlocked,
      'synchronizable': synchronizable,
    };
  }
}
