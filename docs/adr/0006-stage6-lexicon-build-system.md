# ADR 0006: Stage 6 Lexicon Build System

## Status

Accepted for stage 6.

## Context

The project needs a deterministic lexicon artifact before runtime candidate
query work can begin. Runtime code must not parse large source TSV files at
startup or on keypress, and ArkTS/C++ must not gain lexicon business logic.

## Decision

Stage 6 introduces:

- `lexicon-core` for shared lexicon models, binary serialization, CRC32, and defensive loading;
- `lexicon-builder` as an offline Rust CLI under the existing `engine-rust` workspace;
- a hand-authored UTF-8 TSV test lexicon;
- a versioned binary format with magic `HSPLEX01`, format `1.0`, and payload CRC32;
- deterministic sorting and duplicate merging before serialization.

The Cargo package for the builder lives at `engine-rust/tools/lexicon-builder`
because Cargo workspace members must be under the `engine-rust` workspace root.
The repository-level `tools/lexicon-builder` directory remains as an entry note
for the project-level tool path.

## Rationale

Offline building keeps text cleaning, source parsing, duplicate merging, and
format validation out of the runtime engine. Runtime readers can load a compact
binary structure without reparsing TSV.

TSV is used for the first source format because it is simple to review in
version control, easy to construct by hand for tests, and precise enough for the
stage 6 fields: word, pinyin, frequency, and source.

The binary format uses explicit little-endian integers, string-table offsets,
entry records, and pinyin-key index records. It does not write Rust struct
memory layouts, padding, absolute paths, timestamps, random IDs, machine names,
or user names.

Build time is not written by default. Reproducibility is more important at this
stage than embedding local environment metadata. If future artifacts need build
time, it must be injected by an explicit parameter and documented as affecting
bytes.

The builder uses sorted maps and sorted output keys, so equivalent input sets
produce identical bytes regardless of row order, duplicate row order, CRLF/LF,
or pinyin whitespace/case differences.

Stage 6 deliberately does not expose candidate lookup APIs. It only creates and
verifies the indexed binary data required by stage 7.

## Consequences

- `cargo test --workspace` now covers lexicon parsing, normalization, binary
  verification, CLI behavior, and determinism.
- Stage 7 can add query APIs on top of `lexicon-core` without changing ArkTS or
  C++ responsibilities.
- Empty lexicons are rejected in stage 6.
- Third-party dictionary import remains blocked until license metadata is
  recorded.

## Upgrade Strategy

Backward-compatible additions may use a minor version bump if older readers can
reject or ignore the new data safely. Incompatible changes require a major
version bump and explicit loader branching. The magic remains fixed for this
format family unless a future format is intentionally unrelated.
