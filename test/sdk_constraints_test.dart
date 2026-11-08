// Copyright 2024–2026 Yardenah / Turkana Nation. MIT license.
//
// The example must not claim a Dart or Flutter older than the package can
// resolve. publish_to stays none until a maintainer publishes.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('example SDK floors are not below the package', () {
    final package = _env(File('pubspec.yaml').readAsStringSync());
    final example = _env(File('example/pubspec.yaml').readAsStringSync());
    expect(package.dart, '3.12.2');
    expect(package.flutter, '3.44.2');
    expect(_atLeast(example.dart, package.dart), isTrue);
    expect(_atLeast(example.flutter, package.flutter), isTrue);
  });

  test(
    'publication stays disabled and native metadata is not a placeholder',
    () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, contains("publish_to: 'none'"));
      final version = RegExp(
        r'^version:\s*(\S+)',
        multiLine: true,
      ).firstMatch(pubspec)!.group(1)!;
      final podspec = File('darwin/pqkeystore.podspec').readAsStringSync();
      expect(podspec, contains("s.version          = '$version'"));
      expect(podspec.toLowerCase(), isNot(contains('todo')));
      expect(podspec.toLowerCase(), isNot(contains('placeholder')));
      expect(podspec, isNot(contains('example.com')));
      final manifest = File(
        'darwin/pqkeystore/Sources/pqkeystore/PrivacyInfo.xcprivacy',
      );
      expect(manifest.existsSync(), isTrue);
      final packageSwift = File(
        'darwin/pqkeystore/Package.swift',
      ).readAsStringSync();
      expect(packageSwift.toLowerCase(), isNot(contains('todo')));
      expect(packageSwift, contains('.iOS("15.0")'));
      expect(packageSwift, contains('.macOS("12.0")'));
    },
  );
}

final class _Floor {
  const _Floor(this.dart, this.flutter);
  final String dart;
  final String flutter;
}

_Floor _env(String pubspec) {
  final sdk = RegExp(r"sdk:\s*'>=(\d+\.\d+\.\d+)\s*<").firstMatch(pubspec);
  final flutter = RegExp(r"flutter:\s*'>=(\d+\.\d+\.\d+)'").firstMatch(pubspec);
  expect(sdk, isNotNull);
  expect(flutter, isNotNull);
  return _Floor(sdk!.group(1)!, flutter!.group(1)!);
}

bool _atLeast(String left, String right) {
  final a = left.split('.').map(int.parse).toList();
  final b = right.split('.').map(int.parse).toList();
  for (var i = 0; i < 3; i++) {
    if (a[i] != b[i]) {
      return a[i] > b[i];
    }
  }
  return true;
}
