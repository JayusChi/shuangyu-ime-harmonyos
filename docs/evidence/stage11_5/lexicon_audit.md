# Stage 11.5 lexicon audit

Audit date: 2026-07-13. The workspace contains no usable `.git` metadata, so Git
status cannot distinguish prior user edits. Changes were restricted to stage 11.5
files and direct integration points.

## Before modification

The default runtime resource was `stage8_sentence_test.lex` (1,049 bytes). Its TSV
had 17 data rows and 16 unique word/reading entries after one duplicate merge:
8 single-character entries, 6 two-character entries, 1 three-character entry, and
1 four-character entry. It contained no separately classified idiom or short-sentence
data. Stage 6's broader fixture had 48 data rows and remained test-only.

Raw fixtures use four tab-separated fields: word, space-separated tone-less pinyin,
unsigned base frequency, and source tag. `lexicon-builder` validates and emits
`HSPLEX01` format 1.0. The header stores lexicon/builder versions, section offsets,
entry and pinyin-key counts, checksum algorithm, and CRC32 of the payload. Records
store a word, word-level pinyin key and syllables, `u64` frequency, and sources.

The index is sorted by full pinyin key and maps each key to a contiguous entry range.
Exact lookup uses binary search; prefix lookup uses a lower bound and a bounded scan.
Ranking is centralized in `candidate-ranking`: exact before prefix, then descending
base/user-bounded score, then deterministic text/reading/source/id tie breakers.
Multiple readings are separate word/reading entries; readings are never reconstructed
from a default character pronunciation.

## Build, load, and packaging chain

`dictionaries/source/*.tsv` -> `engine-rust/tools/lexicon-builder` ->
`dictionaries/generated/*.lex` -> `entry/src/main/resources/rawfile/*.lex` ->
`LexiconResourceInstaller` -> ExtensionAbility files directory -> `EngineCoordinator`
-> Node-API -> Rust C ABI -> `ImeEngine::new` -> `lexicon-core` -> candidate query,
ranking, sentence decoder, and bounded user-model scoring.

The rawfile is packaged in the HAP. Runtime parses only the binary file, never YAML,
TSV, CSV, or JSON dictionary data. The shared coordinator creates one engine for the
ability lifecycle, so each key does not reload the dictionary. Missing/corrupt files
produce explicit lexicon-load failure rather than a fixture fallback.

## Isolation after modification

- Unit fixtures: `stage6_test.*`, `stage8_sentence_test.*`.
- Production source: pinned Rime YAML plus manifest/license files.
- Production build input/output: `production.normalized.tsv` and `production.lex`.
- Default packaged/runtime resource: `production.lex` only.

Detailed production statistics and rejected rows are in `lexicon_statistics.json`
and `lexicon_rejections.json`.
