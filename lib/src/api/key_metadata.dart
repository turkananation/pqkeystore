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
  final int participantIndex;
  final String ceremonyId;
  final String? rosterHashHex;

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
