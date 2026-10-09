/// The kind of key material a record holds.
///
/// This is descriptive metadata, covered by the record's authenticated data. The
/// keystore does not interpret it: it never parses key bytes and never performs
/// any cryptographic operation on them. Recording the kind lets an application
/// inventory what it is holding without decrypting anything.
///
/// The name describes the material, not its protection. A value says nothing
/// about how the record is sealed.
enum KeyKind {
  /// An ML-KEM (FIPS 203) decapsulation key.
  mlKemSecret,

  /// An ML-DSA (FIPS 204) signing key.
  mlDsaSecret,

  /// An SLH-DSA (FIPS 205) signing key.
  slhDsaSecret,

  /// An X25519 key-agreement key (RFC 7748).
  classicalX25519,

  /// An Ed25519 signing key (RFC 8032).
  classicalEd25519,

  /// A NIST P-256 ECDSA signing key (FIPS 186-4).
  classicalEcdsaP256,

  /// A hybrid keyset combining post-quantum and classical material.
  hybridKeyset,

  /// One participant's private share in a threshold scheme.
  ///
  /// Stored individually. Reconstruction is never implicit and lives in
  /// `pqthreshold`, which this package does not depend on for that behaviour.
  thresholdShare,

  /// A threshold scheme's joint public key. Not secret.
  thresholdPublic,

  /// Deterministic namespace-generation material. The convention is pqdga's.
  dgaMaterial,

  /// A transport identity key.
  transportIdentity,

  /// A short-lived session ephemeral.
  sessionEphemeral,

  /// An opaque sealed blob whose structure this package does not know.
  ///
  /// The correct choice when wrapping something already protected — for example
  /// a `pqforge`-wrapped key kept verbatim — since a more specific [kind] would
  /// be a claim this package cannot check.
  wrappedBlob;

  /// Whether this is threshold material, secret or public.
  bool get isThreshold =>
      this == KeyKind.thresholdShare || this == KeyKind.thresholdPublic;
}
