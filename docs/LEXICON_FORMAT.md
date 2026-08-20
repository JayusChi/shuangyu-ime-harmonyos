# Lexicon Source and Binary Format

This document defines the stage 6 offline lexicon source format and binary
artifact format. Stage 7 reuses the same binary format at runtime for candidate
query. Stage 8 reuses the same binary format for sentence decoding. The format
is intentionally small, deterministic, and limited to the current test lexicon
scope.

## Source TSV

Stage 6 source dictionaries use UTF-8 TSV:

```text
word<TAB>pinyin<TAB>frequency<TAB>source
```

Rules:

- LF and CRLF line endings are accepted.
- Empty lines are ignored.
- Lines whose first non-space character is `#` are comments.
- Exactly four fields are required.
- All fields are trimmed; repeated whitespace inside a field is normalized to one ASCII space.
- `word`, `pinyin`, and `source` must not be empty.
- `word` is limited to 1-32 common CJK unified ideographs (`U+4E00..U+9FFF`) in stage 6.
- `pinyin` uses tone-less syllables separated by whitespace; 1-32 syllables are allowed.
- `frequency` is a non-negative `u64` integer and is stored unchanged except when duplicates are merged.
- `source` is 1-64 ASCII characters: letters, digits, `_`, `-`, or `.`.
- Control characters inside fields are rejected.

## Ordered TAB Code Table

The rule-enhancement phase 1 builder also accepts an explicitly selected,
offline-only format:

```text
word<TAB>code
```

Select it with `--input-format flypy-table`. The default remains
`pinyin-tsv`, so existing production builds are unchanged.

Rules:

- the delimiter must be one real TAB; ordinary spaces are not delimiters;
- exactly two fields are required;
- UTF-8, LF, CRLF, and an optional UTF-8 BOM on the first line are accepted;
- empty lines are ignored;
- words are non-empty strings of at most 32 Unicode scalar values; system-table
  input accepts common CJK, ASCII letters/digits, and the frozen test symbol set
  documented by `lexicon-core::validate_system_table_word`;
- codes are 1-64 lowercase ASCII letters;
- empty fields, extra fields, control characters, spaces in codes, and future
  markers such as `#删`, `#固`, and `#N` are rejected with path and line number;
- TXT input is read only by the offline builder; runtime code still loads only
  verified `.lex` files.

`source_order` is the zero-based ordinal of an accepted data row across the
ordered `--input` arguments. Files are processed in command-line order and rows
in physical line order. Empty rows do not consume an ordinal. Duplicate
`word + code` rows keep the first entry and its first ordinal; later duplicates
still consume their accepted-row ordinal, so gaps are allowed. No directory
enumeration, hash iteration, thread completion order, time, random value, or
absolute source path participates in this value or in the output bytes.

The stage 11.6.2A categorized fixture builder adds a strict validation pass
before `FlypyTableImporter`: identical `word + code` rows inside one category
are errors rather than merge inputs, and diagnostics carry a stable code,
source identifier, physical line, field, and redacted reason. The broader
system-table word policy does not change the CJK-only user-lexicon policy.

The runtime user overlay is intentionally a different text format and never
enters this builder or `production.lex`. Its `#删/#固/#N` grammar, last-rule
wins semantics, hard ordering, atomic save, and recovery behavior are defined
in [USER_LEXICON_FORMAT.md](USER_LEXICON_FORMAT.md). Both importers reuse the
same `lexicon-core::validation` code/word policy, while `FlypyTableImporter`
continues to reject every user marker.

## Pinyin Normalization

The builder normalizes pinyin in Rust and reuses `pinyin-syllable` validation:

- ASCII uppercase is converted to lowercase.
- Syllables are separated by one ASCII space.
- Leading/trailing and repeated whitespace is removed.
- `ü`, `u:`, and `v` are accepted.
- The final canonical spelling follows `pinyin-syllable`: `j/q/x/y + v` becomes standard `u`, while `nv`, `nve`, `lv`, and `lve` preserve `v`.
- Every normalized syllable must be in the maintained tone-less Mandarin syllable inventory.

For Chinese-only entries, the number of CJK characters must equal the number of pinyin syllables.

## Duplicate Merge

The duplicate key is:

```text
normalized word + normalized pinyin key
```

Merge rules:

- `frequency` uses saturating `u64` addition.
- `source` values are merged into a sorted unique set and persisted as a comma-separated string.
- Same word with different pinyin is a different entry.
- Output never depends on input row order or hash-map iteration order.

## Frequency and Sorting

Stage 6 stores merged raw base frequencies. It does not implement candidate
ranking. Entries are sorted deterministically by:

```text
pinyin key ASC, word ASC, source string ASC, frequency ASC
```

Same pinyin-key entries are contiguous so the index can point to one range.

## Binary Layout

All integers are little-endian. Rust structs are not transmuted or written with
their in-memory layout.

```text
Header (96 bytes)
String Table
Entry Table
Pinyin-Key Index
```

Header fields:

| Offset | Type | Field |
| --- | --- | --- |
| 0 | `[u8; 8]` | Magic `HSPLEX01` |
| 8 | `u32` | Header length, currently `96` |
| 12 | `u16` | Format major version, currently `1` |
| 14 | `u16` | Format minor version: `0` for pinyin TSV, `1` for ordered TAB tables |
| 16 | `u32` | Builder version |
| 20 | `u32` | Lexicon version |
| 24 | `u32` | Entry count |
| 28 | `u32` | Pinyin-key count |
| 32 | `u64` | String table offset |
| 40 | `u64` | String table length |
| 48 | `u64` | Entry table offset |
| 56 | `u64` | Entry table length |
| 64 | `u64` | Index offset |
| 72 | `u64` | Index length |
| 80 | `u32` | Checksum algorithm, `1 = IEEE CRC32` |
| 84 | `u32` | Payload checksum |
| 88 | `u32` | Reserved, zero |
| 92 | `u32` | Reserved, zero |

Format 1.0 entry record, 36 bytes:

```text
word_offset:u32
word_length:u32
pinyin_offset:u32
pinyin_length:u32
source_offset:u32
source_length:u32
frequency:u64
syllable_count:u16
reserved:u16
```

Format 1.1 appends one field and has a 40-byte entry record:

```text
source_order:u32
```

The builder continues to emit format 1.0 for the existing `pinyin-tsv` path.
Only `flypy-table` emits format 1.1. This preserves the current production
`production.lex` bytes and IDs while allowing ordered code tables to recover
global row order after entries have been grouped by code for the index.

Offsets in entry and index records are relative to the string table.

Index record, 16 bytes:

```text
pinyin_offset:u32
pinyin_length:u32
entry_start:u32
entry_count:u32
```

## Checksum

The payload is every byte after the fixed 96-byte header. The builder writes an
IEEE CRC32 checksum of the payload into the header. Loading verifies:

- magic;
- header length;
- supported format version;
- checksum algorithm;
- section offsets and lengths;
- table record lengths;
- string reference bounds;
- UTF-8 validity;
- index ranges;
- payload checksum.

Truncated files and payload mutations are rejected. File length alone is never
used as validation.

## Compatibility

Readers accept formats `1.0` and `1.1`. A 1.0 entry loads with
`source_order = u32::MAX` (unspecified) because that information did not exist
on disk. Unsupported newer minor or major versions fail explicitly. A future
major version must use an explicit migration or separate reader path.

Stage 7 loads the verified binary lexicon in Rust when the formal engine is
created with `EngineConfig.lexiconPath`. ArkTS installs the rawfile into the
application sandbox and passes the sandbox path through C++; neither ArkTS nor
C++ parses the binary content.

Stage 8 did not change the binary layout or source TSV format. Sentence decoding
uses the verified `BinaryLexicon` and `lexicon-core::runtime_index` APIs to read
exact pinyin-key ranges for contiguous syllable spans.

## Runtime Query Rules

Stage 7 keeps format version `1.0`; no binary layout upgrade was required.

Runtime lookup uses the sorted pinyin-key index:

- exact query performs binary search on `PinyinIndex.pinyin_key`;
- prefix query performs a lower-bound search on the same sorted index, then
  scans only contiguous keys that start with the prefix and stops at configured
  limits;
- empty prefixes return no records and never enumerate the whole lexicon;
- query results are capped before pagination;
- candidates are deduplicated by `text + normalized reading`;
- duplicate sources are merged into a sorted comma-separated source string;
- exact-query ranking is deterministic: exact before prefix, higher base
  frequency first, then stable text/reading/source/id tie-breakers;
- production broad-prefix recall still uses that base-frequency key for its
  bounded global Top-K. After recall and deduplication, `ime-engine` applies
  the stage 5 prefix-only quality profile: exact before prefix, bounded
  length/repetition-adjusted frequency plus bounded user score, raw frequency,
  then stable text/reading/source/id. The profile never applies to an exact
  query or sentence decoding.

Ordered code-table lookup is an explicit internal policy and does not replace
the rules above:

1. query the full code exactly;
2. when exact entries exist, return only those entries;
3. otherwise scan all longer indexed codes sharing the non-empty prefix;
4. sort the collected entries by persisted `source_order` across codes;
5. deduplicate stably, apply the configured result limit, then paginate;
6. an empty code returns no candidates and never enumerates the table.

The Xiaohe pinyin production path uses base frequency and match type for exact
queries and bounded global prefix recall, the isolated stage 5 quality profile
for broad-prefix snapshots, independent sentence scores for sentence queries,
and bounded user learning before snapshot truncation. `source_order` is not
consulted by that path.

Runtime code reads only `.lex` binary artifacts. TSV parsing remains confined
to `lexicon-builder` and tests.

## Stage 11.6.2A Categorized Fixture Bundle

The internal `code-table-fixture-generator` reads an explicit version-1 JSON
manifest and builds one `HSPLEX01` 1.1 binary per normal category plus one
isolated guide binary. It then places them in the test-only `HSPCTF01` 1.0
container. The manifest records `bundleId`, test display name, `fixtureOnly`,
ordered category IDs, default switches, relative source paths, expected entry
counts, and source SHA-256 values. Absolute paths, `..`, duplicate IDs/orders,
missing files, count mismatches, checksum mismatches, and category/guide mixing
fail the build.

The bundle records the exact manifest, category order, per-category metadata,
overall build-input SHA-256, content SHA-256, and nested binary bytes. It is not
installed in `entry/src/main/resources`, and no runtime reader is wired into
`ime-engine`. See [CODE_TABLE_BUNDLE_FORMAT.md](CODE_TABLE_BUNDLE_FORMAT.md)
and [CODE_TABLE_FIXTURE_GENERATION.md](CODE_TABLE_FIXTURE_GENERATION.md).

## Commands

From `engine-rust`:

```powershell
cargo run -p lexicon-builder -- `
  --input ..\dictionaries\source\stage6_test.tsv `
  --output ..\dictionaries\generated\stage6_test.lex `
  --lexicon-version 1 `
  --strict
```

Ordered test-table build:

```powershell
cargo run -p lexicon-builder -- `
  --input ..\dictionaries\source\test-fixtures\flypy_order_table.txt `
  --input-format flypy-table `
  --output $env:TEMP\flypy_order.lex `
  --lexicon-version 1 `
  --strict --verify
```

```powershell
cargo run -p lexicon-builder -- `
  --verify ..\dictionaries\generated\stage6_test.lex
```

## Stage 11.6.2C Formal Xiaohe Yinxing Data

The formal Xiaohe Yinxing converter emits eight `HSPLEX01` 1.1 category
lexicons. Their `source_order` values are complete zero-based sequences within
each frozen category, and category order comes from the conversion contract
rather than directory enumeration. The category binaries are nested inside
the checksummed `HSPYXP01` 1.0 archive and are also emitted separately for
auditability.

User `#删`, `#固`, and `#N` records are not encoded as system entries. They are
written to a separate strict user-lexicon payload and parsed through the
existing `user-lexicon` implementation. Unsupported commands and deferred
features are metadata only and cannot become candidates. See
`docs/XIAOHE_YINXING_PRODUCTION_BUNDLE_FORMAT.md` for the container layout,
hashes, trace contract, and Release boundary.

## Error Example

```text
dictionaries/source/stage6_test.tsv:17:
word="输入法"
pinyin="shu ru invalid"
field=pinyin
error=invalid pinyin syllable "invalid" at syllable index 3
```

## Dictionary License Requirements

Stage 7 tests still use the hand-authored `stage6_test` lexicon from
`dictionaries/generated/stage6_test.lex`. It is a test fixture and is not copied
to `entry/src/main/resources/rawfile/` or packaged into a HAP. Third-party
dictionaries must not be imported until their source, license, redistribution
permission, transformation steps, and checksum are recorded under
`dictionaries/LICENSES/`.

## Stage 8 Test Lexicon

Stage 8 adds a separate small sentence-decoder fixture lexicon:

```text
dictionaries/source/stage8_sentence_test.tsv
dictionaries/generated/stage8_sentence_test.lex
```

It contains hand-authored minimal entries for single characters, two-character
words, three-syllable words, a four-syllable phrase, duplicate merge, stable
tie-breakers, and partial commit cases. It is not a production dictionary.
The generated lexicon is consumed directly by automated tests and is not a HAP
resource. The only runtime lexicon under `entry/src/main/resources/rawfile/` is
`production.lex`.

Build command:

```powershell
cd engine-rust
cargo run -p lexicon-builder -- `
  --input ..\dictionaries\source\stage8_sentence_test.tsv `
  --output ..\dictionaries\generated\stage8_sentence_test.lex `
  --lexicon-version 8 `
  --strict
```

Recorded stage 8 build result:

| Item | Value |
| --- | --- |
| Input rows | 17 |
| Accepted rows | 17 |
| Merged duplicates | 1 |
| Entries written | 16 |
| Pinyin keys | 10 |
| Binary size | 1,049 bytes |
| CRC32 payload checksum | `e220942f` |
| SHA-256 | `9C54A2CD65A3C19C9ECC13EFE5F2A351957C791A15C30AA96B357E2B65AFDDEE` |
