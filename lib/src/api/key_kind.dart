enum KeyKind {
  mlKemSecret,
  mlDsaSecret,
  slhDsaSecret,
  classicalX25519,
  classicalEd25519,
  classicalEcdsaP256,
  hybridKeyset,
  thresholdShare,
  thresholdPublic,
  dgaMaterial,
  transportIdentity,
  sessionEphemeral,
  wrappedBlob;

  bool get isThreshold => this == KeyKind.thresholdShare || this == KeyKind.thresholdPublic;
}
