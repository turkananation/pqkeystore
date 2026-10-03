import 'dart:convert';
import 'dart:typed_data';
import 'key_metadata.dart';

final class SealedRecord {
  const SealedRecord({
    required this.metadata,
    required this.wrapAlg,
    required this.ciphertext,
    required this.aad,
    this.nonce,
    this.kdfParams,
  });
  static const int formatVersion = 1;
  static final List<int> _magic = [0x50, 0x51, 0x4B, 0x53]; // 'PQKS'

  final KeyMetadata metadata;
  final String wrapAlg;
  final Uint8List ciphertext;
  final Uint8List aad;
  final Uint8List? nonce;
  final Map<String, dynamic>? kdfParams;

  Uint8List encode() {
    final builder = BytesBuilder();
    builder.add(_magic);

    // version uint32 BE
    builder.add(_encodeUint32(formatVersion));

    // length-prefixed wrapAlg
    final wrapAlgBytes = utf8.encode(wrapAlg);
    builder.add(_encodeUint32(wrapAlgBytes.length));
    builder.add(wrapAlgBytes);

    // length-prefixed metadata
    final metadataBytes = utf8.encode(jsonEncode(metadata.toJson()));
    builder.add(_encodeUint32(metadataBytes.length));
    builder.add(metadataBytes);

    // length-prefixed aad
    builder.add(_encodeUint32(aad.length));
    builder.add(aad);

    // length-prefixed nonce
    if (nonce != null) {
      builder.add(_encodeUint32(nonce!.length));
      builder.add(nonce!);
    } else {
      builder.add(_encodeUint32(0));
    }

    // length-prefixed kdfParams
    if (kdfParams != null) {
      final kdfBytes = utf8.encode(jsonEncode(kdfParams));
      builder.add(_encodeUint32(kdfBytes.length));
      builder.add(kdfBytes);
    } else {
      builder.add(_encodeUint32(0));
    }

    // length-prefixed ciphertext
    builder.add(_encodeUint32(ciphertext.length));
    builder.add(ciphertext);

    return builder.toBytes();
  }

  static SealedRecord decode(Uint8List bytes) {
    if (bytes.length < 8) {
      throw const FormatException('Invalid PQKS format: too short');
    }

    for (int i = 0; i < 4; i++) {
      if (bytes[i] != _magic[i]) {
        throw const FormatException('Invalid PQKS magic bytes');
      }
    }

    final byteData = ByteData.sublistView(bytes);
    final version = byteData.getUint32(4, Endian.big);
    if (version != formatVersion) {
      throw FormatException('Unsupported PQKS version: $version');
    }

    int offset = 8;

    Uint8List readField() {
      if (offset + 4 > bytes.length) {
        throw const FormatException('Unexpected EOF');
      }
      final length = byteData.getUint32(offset, Endian.big);
      offset += 4;
      if (offset + length > bytes.length) {
        throw const FormatException('Unexpected EOF');
      }
      final field = bytes.sublist(offset, offset + length);
      offset += length;
      return field;
    }

    final wrapAlgBytes = readField();
    final wrapAlg = utf8.decode(wrapAlgBytes);

    final metadataBytes = readField();
    final metadataJson =
        jsonDecode(utf8.decode(metadataBytes)) as Map<String, dynamic>;
    final metadata = KeyMetadata.fromJson(metadataJson);

    final aad = readField();

    final nonceBytes = readField();
    final nonce = nonceBytes.isEmpty ? null : nonceBytes;

    final kdfBytes = readField();
    final kdfParams = kdfBytes.isEmpty
        ? null
        : jsonDecode(utf8.decode(kdfBytes)) as Map<String, dynamic>;

    final ciphertext = readField();

    return SealedRecord(
      metadata: metadata,
      wrapAlg: wrapAlg,
      ciphertext: ciphertext,
      aad: aad,
      nonce: nonce,
      kdfParams: kdfParams,
    );
  }

  static Uint8List _encodeUint32(int value) {
    final bd = ByteData(4);
    bd.setUint32(0, value, Endian.big);
    return bd.buffer.asUint8List();
  }
}
