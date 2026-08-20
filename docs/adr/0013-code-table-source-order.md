# ADR 0013: TAB code tables and persisted source order

## Status

Accepted on 2026-07-14 for “词库规则增强第一阶段：码表顺序基础”.

## Context

The production builder accepted only four-field pinyin TSV. Its deterministic
binary order groups entries by normalized pinyin and then sorts by word and
metadata. That order is correct for indexed frequency-ranked pinyin lookup but
cannot recover the original row order across several different code keys.

The project needs infrastructure for project-authored `word<TAB>code` fixtures,
same-code row order, and prefix fallback in global row order. It must not switch
the current Xiaohe production lexicon from frequency ranking to file order or
change user-model candidate identities.

## Decision

- Add an isolated offline `FlypyTableImporter`, selected explicitly with
  `--input-format flypy-table`; the existing pinyin TSV remains the default.
- Define `source_order` as the zero-based accepted-data-row ordinal across
  `--input` files in command-line order and physical rows within each file.
  Empty lines do not consume an ordinal. Duplicate `word + code` entries retain
  the first occurrence and its order; later accepted duplicates may leave gaps.
- Do not scan source directories. The caller supplies every source in a stable,
  explicit order. Parsing and merging are sequential and ordered.
- Keep `HSPLEX01` major version 1. Existing pinyin builds continue writing 1.0.
  Ordered tables write backward-compatible format 1.1, appending a `u32
  source_order` to each entry record. The reader accepts both; 1.0 loads the
  sentinel `u32::MAX` because no source order was stored.
- Add an explicit internal `CandidateOrder` boundary. Existing requests default
  to `ExistingRanking`. Table tests select `SourceOrder` together with
  `ExactOrPrefix`.
- `ExactOrPrefix` returns only exact-code entries when present. Otherwise it
  collects all longer prefix keys, sorts globally by `source_order`, performs
  stable deduplication and limiting, and leaves pagination to the existing
  candidate-session boundary. Empty input returns no entries.
- Keep production Xiaohe ranking unchanged: exactness, base frequency, sentence
  score, and bounded user learning continue to apply. The user-model format and
  candidate IDs are unchanged.

## Consequences

Format 1.1 adds four bytes per ordered-table entry, while format 1.0 production
artifacts remain byte-compatible. Runtime lookup still reads only binary data.
Prefix fallback in source-order mode intentionally scans every matching index
key before sorting so a lexicographically later code cannot hide an earlier
source row.

This phase does not import an official Xiaohe shape table, change the default
scheme, add a UI option, implement user dictionaries, or implement `#删/#固/#N`.
Those concerns are deliberately outside this ADR.

