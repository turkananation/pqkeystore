// Copyright 2024–2026 Yardenah / Turkana Nation. MIT license.
//
// Example smoke test against the pure-Dart contract reference (no device).

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pqkeystore/pqkeystore.dart';
import 'package:pqkeystore_example/main.dart';

// The reference store is shared with the package's unit tests.
// ignore: avoid_relative_lib_imports
import '../../test/contract/reference_native_store.dart';

void main() {
  testWidgets('shows native platform info', (tester) async {
    const channel = MethodChannel(PlatformContract.channelName);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      ReferenceNativeStore(os: 'android').handle,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    await tester.pumpWidget(const PqKeystoreExampleApp());
    await tester.pumpAndSettle();

    expect(find.textContaining('android · reference-memory'), findsOneWidget);
    expect(find.textContaining('Enforceable options: none'), findsOneWidget);
  });
}
