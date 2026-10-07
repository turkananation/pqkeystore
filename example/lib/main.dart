// Copyright 2024–2026 Yardenah / Turkana Nation. MIT license.
//
// pqkeystore example: platform diagnostics plus a put → use → delete flow
// against the native OS backend, using the pqforge crypto adapter.
//
// The demo key is freshly generated random bytes (no real key material) and
// plaintext is never displayed or logged — only its length.

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pqkeystore/pqkeystore.dart';

void main() {
  runApp(const PqKeystoreExampleApp());
}

class PqKeystoreExampleApp extends StatelessWidget {
  const PqKeystoreExampleApp({super.key, this.backend});

  /// Injectable for tests; defaults to the native platform backend.
  final PlatformKeystoreBackend? backend;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'pqkeystore',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: KeystoreDemoPage(backend: backend ?? PlatformKeystoreBackend()),
    );
  }
}

class KeystoreDemoPage extends StatefulWidget {
  const KeystoreDemoPage({super.key, required this.backend});

  final PlatformKeystoreBackend backend;

  @override
  State<KeystoreDemoPage> createState() => _KeystoreDemoPageState();
}

class _KeystoreDemoPageState extends State<KeystoreDemoPage> {
  static const KeyId _demoId = KeyId('pqkeystore-example/demo');

  late final PqKeystore _keystore = PqKeystore(
    backend: widget.backend,
    crypto: PqForgeKeystoreCrypto(),
  );
  final TextEditingController _passphrase = TextEditingController();
  String _platform = 'Querying platform…';
  String _status = 'Ready';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadPlatformInfo();
  }

  @override
  void dispose() {
    _passphrase.dispose();
    super.dispose();
  }

  Future<void> _loadPlatformInfo() async {
    try {
      final info = await widget.backend.platformInfo();
      final options = info.supportedOptions.isEmpty
          ? 'none'
          : (info.supportedOptions.toList()..sort()).join(', ');
      setState(() {
        _platform = '${info.os} · ${info.backend} · contract '
            'v${info.contractVersion}\nEnforceable options: $options';
      });
    } on PqKeystoreError catch (e) {
      setState(() => _platform = 'Platform backend unavailable: $e');
    }
  }

  UnlockMethod _unlock() =>
      PassphraseUnlock(Uint8List.fromList(utf8.encode(_passphrase.text)));

  Future<void> _run(String label, Future<String> Function() action) async {
    if (_passphrase.text.isEmpty) {
      setState(() => _status = 'Enter a passphrase first.');
      return;
    }
    setState(() {
      _busy = true;
      _status = '$label…';
    });
    final message = await action();
    if (mounted) {
      setState(() {
        _busy = false;
        _status = message;
      });
    }
  }

  Future<String> _put() async {
    final random = Random.secure();
    final material = Uint8List.fromList(
      List<int>.generate(32, (_) => random.nextInt(256)),
    );
    final result = await _keystore.put(
      KeyMetadata(
        id: _demoId,
        kind: KeyKind.wrappedBlob,
        algorithm: 'demo-random-32',
        createdAt: DateTime.now().toUtc(),
        purpose: 'example',
      ),
      material,
      _unlock(),
    );
    material.fillRange(0, material.length, 0);
    return result.when(
      success: (_) => 'Stored a fresh random demo key.',
      failure: (e) => 'Store failed: $e',
    );
  }

  Future<String> _use() async {
    // Preferred API: plaintext exists only inside the callback.
    final result = await _keystore.use<int>(
      _demoId,
      _unlock(),
      (plaintext) async => plaintext.length,
    );
    return result.when(
      success: (n) => 'Unwrapped $n bytes inside the use() callback.',
      failure: (e) => 'Use failed: $e',
    );
  }

  Future<String> _delete() async {
    final result = await _keystore.delete(_demoId);
    return result.when(
      success: (_) => 'Deleted.',
      failure: (e) => 'Delete failed: $e',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('pqkeystore')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(_platform, key: const Key('platform')),
            const SizedBox(height: 24),
            TextField(
              controller: _passphrase,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Passphrase'),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              children: <Widget>[
                FilledButton(
                  onPressed: _busy ? null : () => _run('Storing', _put),
                  child: const Text('Store'),
                ),
                FilledButton(
                  onPressed: _busy ? null : () => _run('Unwrapping', _use),
                  child: const Text('Use'),
                ),
                OutlinedButton(
                  onPressed: _busy ? null : () => _run('Deleting', _delete),
                  child: const Text('Delete'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text(_status, key: const Key('status')),
          ],
        ),
      ),
    );
  }
}
