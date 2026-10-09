import 'key_id.dart';
import 'key_kind.dart';

final class ThresholdMeta {

  const ThresholdMeta({
    required this.schemeId,
    required this.t,
    required this.n,
    required this.participantIndex,
    required this.ceremonyId,
    this.rosterHashHex,
  });

  factory ThresholdMeta.fromJson(Map<String, dynamic> json) {
    return ThresholdMeta(
      schemeId: json['schemeId'] as String,
      t: json['t'] as int,
      n: json['n'] as int,
      participantIndex: json['participantIndex'] as int,
      ceremonyId: json['ceremonyId'] as String,
      rosterHashHex: json['rosterHashHex'] as String?,
    );
  }
  final String schemeId;
  final int t;
  final int n;

  /// The participant's **1-based** Shamir evaluation index, in `1..n`.
  ///
  /// 1-based, because that is what `pqthreshold.Share.index` is: it is
  /// validated `1..n` on construction there. A 0-based value here would name a
  /// different participant than the share it describes. Note that
  /// `pqthreshold`'s experimental `MlDsaShare.mithrilPartyId` is the *other*
  /// convention (0-based); see [`../../doc/UPSTREAM.md`](../../doc/UPSTREAM.md)
  /// UT-4.
  ///
  /// Not validated by this constructor, because it is `const`. Callers go
  /// through [PqKeystore.putShare](pq_keystore.dart), which validates.
  final int participantIndex;
  final String ceremonyId;
  final String? rosterHashHex;

  /// Checks that this metadata is internally consistent.
  ///
  /// Returns `null` when it is, otherwise a message naming the first problem
  /// found. Enforced by `PqKeystore.putShare`, so an inconsistent share record
  /// is refused before it is written rather than at reconstruction time.
  ///
  /// The bounds mirror `pqthreshold`'s own construction-time validation:
  /// `t >= 1`, `n >= 1`, `t <= n`, `participantIndex` in `1..n`, and a
  /// non-empty ceremony id.
  String? validate() {
    if (t < 1) {
      return 'threshold t must be at least 1, got $t';
    }
    if (n < 1) {
      return 'participant count n must be at least 1, got $n';
    }
    if (t > n) {
      return 'threshold t ($t) must not exceed participant count n ($n)';
    }
    if (participantIndex < 1 || participantIndex > n) {
      return 'participantIndex $participantIndex is out of range '
          '1..$n; pqthreshold.Share.index is 1-based';
    }
    if (ceremonyId.isEmpty) {
      return 'ceremonyId must not be empty';
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'schemeId': schemeId,
        't': t,
        'n': n,
        'participantIndex': participantIndex,
        'ceremonyId': ceremonyId,
        if (rosterHashHex != null) 'rosterHashHex': rosterHashHex,
      };
}

final class KeyMetadata {

  const KeyMetadata({
    required this.id,
    required this.kind,
    required this.algorithm,
    required this.createdAt,
    this.purpose,
    this.version = 1,
    this.rotatedFrom,
    this.threshold,
    this.tags = const {},
  });

  factory KeyMetadata.fromJson(Map<String, dynamic> json) {
    return KeyMetadata(
      id: KeyId(json['id'] as String),
      kind: KeyKind.values.byName(json['kind'] as String),
      algorithm: json['algorithm'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      purpose: json['purpose'] as String?,
      version: json['version'] as int? ?? 1,
      rotatedFrom: json['rotatedFrom'] != null ? KeyId(json['rotatedFrom'] as String) : null,
      threshold: json['threshold'] != null
          ? ThresholdMeta.fromJson(Map<String, dynamic>.from(json['threshold'] as Map))
          : null,
      tags: json['tags'] != null ? Map<String, String>.from(json['tags'] as Map) : {},
    );
  }
  final KeyId id;
  final KeyKind kind;
  final String algorithm;
  final DateTime createdAt;
  final String? purpose;
  final int version;
  final KeyId? rotatedFrom;
  final ThresholdMeta? threshold;
  final Map<String, String> tags;

  Map<String, dynamic> toJson() => {
        'id': id.value,
        'kind': kind.name,
        'algorithm': algorithm,
        'createdAt': createdAt.toIso8601String(),
        if (purpose != null) 'purpose': purpose,
        'version': version,
        if (rotatedFrom != null) 'rotatedFrom': rotatedFrom!.value,
        if (threshold != null) 'threshold': threshold!.toJson(),
        if (tags.isNotEmpty) 'tags': tags,
      };
}
