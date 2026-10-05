# Continuation Guide

[`doc/TRACKER.md`](doc/TRACKER.md) is the source of truth for production work;
[`doc/BUGS.md`](doc/BUGS.md) lists confirmed defects. Do not start implementation
work in TRK-003 through TRK-009 until the architecture decisions in TRK-002 are
reviewed and accepted or explicitly scoped out.

## Latest Verification

On 2026-10-05, `tool/verify.sh` passed with Dart 3.13.4 and Flutter 3.47.5:
root and example dependency resolution, `dart analyze`, and all 25 tests. This
does not verify the declared minimum SDK combination, any native build, or a
production security claim.

## Next Sequence

1. Complete TRK-001 by validating the approved minimum Flutter/Dart combination
   and recording the supported SDK matrix.
2. Complete TRK-002 architecture review. In particular, settle native channel
   atomicity/options, file-backend path/index/recovery/concurrency policy,
   unlock/KDF/passphrase/memory semantics, threshold boundaries, strict PQKS
   invariants, PQKS versus pqforge formats, and metadata/ID/key-lifecycle rules.
3. Only after the decision gate, start core implementation and tests under
   TRK-003 through TRK-005 and the consumer example work in TRK-013.
4. Then implement platform parity and CI under TRK-006, TRK-007, and TRK-009.

## Format Reminder

PQKS is the keystore's persisted record. `PqWrappedKey` is pqforge's
passphrase-based key wrapper. `.pqf` and `.pqfs` are pqforge recipient-oriented
one-shot and streaming content envelopes, respectively; neither is currently a
pqkeystore backend record. See
[ADR-0007](doc/adr/0007-pqks-and-pqforge-format-boundaries.md).
