# Xiaohe Yinxing Production Bundle Format

## Full-code fixed and direct records

The production profile remains exactly 11 categories; fixed and direct records do not create a twelfth category. The authoritative `full-code-word` source accepts these suffixes:

```text
置顶词条<TAB>编码#固
直通词条<TAB>编码#直
```

`#固` establishes protected top ordering while `full-code-word` is enabled. `#直` remains available to ordinary code input but is stored outside the system-category rows scanned by the backtick universal key. Both records disappear when `full-code-word` is disabled and return atomically when it is enabled; the external user lexicon remains independent. The converter rejects `#直` in every other category. Quick symbols remain isolated behind the semicolon guide.

`#直` controls candidate visibility only; it never grants execution authority. `$cmd/$ddcmd`, network access, external programs, arbitrary file operations, and platform commands remain quarantined by the action policy.

## Scope

Stage 11.6.2C introduces `HSPYXP01` version 1.0 for the formal Xiaohe Yinxing data bundle. It extends the existing code-table runtime boundary without changing the test-only `HSPCTF01` fixture format or the nested `HSPLEX01` 1.1 category format.

The container binds 11 categories, source traceability, user rules, action dispositions, machine statistics, converter identity, and whole-bundle integrity. `code-table-runtime` dispatches by magic and preserves the complete legacy fixture loader and tests.

| Field | Value |
| --- | --- |
| Magic | `HSPYXP01` |
| Format | 1.0 |
| Manifest | 1 |
| Converter binary | 1 |
| Scheme | `xiaohe-yinxing` |
| Bundle | `xiaohe-yinxing-production` |
| Data version | `source-receipt-1` |
| Converter | `yinxing-converter/1.0.0` |

## Archive layout

All integers are unsigned little-endian. Strings and machine text are UTF-8. The 128-byte header contains magic, header length, versions, archive/category counts, record-section length, the frozen source-manifest SHA-256, and SHA-256 of all record bytes. Reserved bytes must be zero.

Each record contains a relative UTF-8 path, typed flags, stable order, byte length, payload SHA-256, and payload bytes. `manifest.json` must be first. Duplicate paths, missing or undeclared files, trailing bytes, path traversal, checksum mismatch, and inconsistent flags are errors.

The archive has these 13 entries:

```text
manifest.json
categories/core.lex
categories/category-secondary.lex
categories/one-key-secondary.lex
categories/two-key-secondary.lex
categories/out-of-table-character.lex
categories/full-code-word.lex
categories/rare-character.lex
categories/full-code-character.lex
user-rules.txt
action-metadata.json
trace-index.jsonl
build-report.json
```

The generated directory additionally contains the archive itself and `build-report.md`; these are not nested archive entries.

## Category, user, and action data

Each category file is a checksummed `HSPLEX01` 1.1 binary. It retains the frozen category ID, contract order, source SHA-256, and complete zero-based `source_order`. Runtime query uses exact-before-prefix, category order, then `source_order`, with stable text deduplication.

`user-rules.txt` uses the existing strict user-lexicon grammar and contains only user overlay records. It is parsed during conversion and again by the production loader. The first build contains 36 `#固` rules and no add/delete/position rules.

`action-metadata.json` has `execution_allowed=false`. Rejected actions contain only source file ID, physical line, syntax class, disposition, reason, and line digest. `trace-index.jsonl` maps accepted output to source file ID, relative source path, source SHA-256, physical line, category, source order, normalization disposition, and digest. No original sensitive action line is copied.

Deferred features—spelling, complete symbol groups, passthrough, simplified/traditional conversion, hidden lexicons, correction, English completion, quick symbols, date/time, paired-symbol actions, and cursor actions—are absent from runtime data. Network/URL, external program/shell, credential, Android/private keycode, absolute-path, script, wildcard, and unknown actions are rejected and absent from runtime data.

## Manifest and integrity

`manifest.json` includes all required stage fields plus source files, role/display metadata, machine-report hashes, command-policy hash, and auditor identity. `build_timestamp_policy` is always `omitted`.

Integrity is checked at four levels:

1. Frozen audit/contract identity and each source size/hash before parsing.
2. SHA-256 for every output record.
3. `bundle_content_sha256` over deterministically ordered typed outputs.
4. Archive SHA-256 followed by nested lexicon and user-rule round trips.

The loader returns bounded errors for invalid magic/version, truncation, checksum mismatch, missing/unexpected files, invalid manifest, invalid category metadata, bad source order, and invalid user rules. Stage 11.6.2C adds the stable runtime codes `missing_bundle_file`, `unexpected_bundle_file`, and `invalid_user_rules`; it reuses `invalid_magic`, `unsupported_version`, `truncated_data`, `checksum_mismatch`, `invalid_manifest`, `metadata_mismatch`, `invalid_source_order`, and related existing codes. It does not panic or silently treat a corrupt production bundle as a fixture.

## Frozen 11.6.2C build

| Output | Bytes | SHA-256 |
| --- | ---: | --- |
| `action-metadata.json` | 1,726 | `26fe0d54609357e07f23cd4201e43be79dd01ad9c350e124b1de3cbe91dd7f8c` |
| `build-report.json` | 8,103 | `b5de2a74a846a0a6f6240fb909b2b6dff2038a4eb1089ab893e719616c676266` |
| `build-report.md` | 2,039 | `d0e080209974734f1aaf621c2898b2bd9598ecce54c8b7e2872a338e89b93fd0` |
| `categories/category-secondary.lex` | 115,959 | `e0676343dd756c23556a80eb929e853cdd57b651ddc7588845effe1fc3bed537` |
| `categories/core.lex` | 4,591,497 | `cdc37681700f173f7a9e1abe5315cf5f3c1b5ea33a6b6cbcb52c2069991eb5fb` |
| `categories/full-code-character.lex` | 103,270 | `9969dc88b88620a8e82bab28bb8a52e2fe1bb182eafe78a6875dff344b241f57` |
| `categories/full-code-word.lex` | 31,148 | `ea8aed7b4d2aa6280f531ab48b7b25b8ac3e26ffbaa2165403f32c2b5246874c` |
| `categories/one-key-secondary.lex` | 1,730 | `27eb79f3703a68b18af949e1249ed266772f377841be08cb50bb415919492670` |
| `categories/out-of-table-character.lex` | 22,721 | `61328b2357562618cc277fcc1ed93c55f73be3e5bbdb4ab9f3f3b777d057c9c8` |
| `categories/rare-character.lex` | 31,131 | `76b32ea8967cba66892fe44c5db884251af7e243e5e52bf507072ead727df874` |
| `categories/two-key-secondary.lex` | 4,139 | `4d103737f6c6a40b86a2a4c89616d31a772dcc78f7f2e78db2092956c12df9a1` |
| `manifest.json` | 8,239 | `8696575f96455f6cd65dc5f191a02e0ef5f5ec66d319948825c9918772b293df` |
| `trace-index.jsonl` | 20,476,629 | `64d6c2275fcfd9c0a874c906e8dd79a667d41ba16e46b8e60237e45bdf575f99` |
| `user-rules.txt` | 582 | `6167a97066c38cd19ba3d3ac88085da0f52fc635a98b0b8144889f148897d3ab` |
| `xiaohe-yinxing-production.hsyx` | 25,397,952 | `00c7d5a9d6b74a079a7434df23f510aa348fe8fee5bf1eaf72e691d68bcd1e30` |

`bundle_content_sha256` is `a2b2a8500c68e7e904fbc6bdefa89e4e9cc821182a0c6cbe409e0ec045229f68`.

## Build, determinism, and Release boundary

Use `scripts/build-xiaohe-yinxing-production.ps1`. For determinism, build into two absent directories and invoke `yinxing-converter compare`; the frozen build compared all 15 generated files byte-for-byte.

The output is a stage artifact under `dictionaries/generated/`, not a Release resource. Raw customer TXT/INI, this bundle, trace/report files, fixtures, and audit evidence remain excluded from the current HAP. Stage 11.6.2C adds no network permission, UI exposure, settings, or input-state-machine path. Product packaging requires a later explicitly approved stage.
