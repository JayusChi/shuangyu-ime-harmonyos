# ADR 0012: Stage 11.5 production lexicon

## Status

Accepted and fully validated on 2026-07-13, including the production-specific
x86_64 simulator matrix. ARM64 physical-device execution is explicitly excluded.

## Decision

Use `rime/rime-pinyin-simp` at commit
`0c6861ef7420ee780270ca6d993d18d4101049d0` as the sole external production source.
The repository declares Apache-2.0 and includes its license and authors; both are
preserved verbatim under `dictionaries/LICENSES/`. Apache-2.0 permits modification
and redistribution when its conditions are retained.

The existing `HSPLEX01` 1.0 binary format is retained. It already represents
word-level readings, including the same word under multiple readings, a deterministic
base frequency, source tags, a sorted exact/prefix index, format and data versions,
and a CRC32 payload checksum. No C ABI, Node-API, or user-model format changes are
needed. Seven project-authored common short sentences are separately licensed under
Apache-2.0 and merged through the same validated multi-source build; they correct
demonstrated low-quality homophone sentence paths without query-code special cases.

The offline build normalizes whitespace and pinyin, maps upstream `lue/nue` to the
engine's `lve/nve` convention, validates every syllable against the engine inventory,
checks word/syllable cardinality and common-CJK scope, clamps `(upstream weight + 1)`
to `1..1,000,000`, and reports every rejected row. Duplicate word/reading pairs are
merged deterministically by the Rust builder. Two clean builds must have identical
size and SHA-256 before the artifact is copied to the runtime rawfile directory.

The stage 6 and 8 dictionaries remain small fixtures. `production.lex` is the only
default runtime dictionary. ArkTS installs it once into the ExtensionAbility files
directory; Rust validates and loads it while creating the shared engine. ArkTS never
reads the index and C++ remains a conversion-only bridge. A stale installed file is
replaced when its size differs; CRC32 corruption and format mismatch are rejected by
Rust at engine creation.

## Consequences

- Production sources: 65,132 rows; 65,122 accepted and 10 explicitly rejected.
- Binary: 3,734,484 bytes, SHA-256
  `765E2B0BD90244192A4C1BB6B2EC501ED28E0DBD731CBAB4C326534F091ECA10`.
- Runtime lexicon version: 115; binary format remains 1.0.
- No new runtime dependency, permission, ABI, or user-model migration.
- Stage 12 should focus on load allocation/copy cost and sentence-refresh latency,
  using the stage 11.5 benchmark rather than redesigning the format speculatively.

## Alternatives rejected

- Unknown web dictionaries and commercial IME extraction: no acceptable provenance.
- Rime fixture fallback: insufficient daily coverage and would conceal load failure.
- A new binary format or FFI: existing evidence does not justify compatibility risk.
- Runtime YAML/TSV parsing: violates startup and layering requirements.
