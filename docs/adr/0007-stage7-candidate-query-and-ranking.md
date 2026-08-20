# ADR 0007: Stage 7 Candidate Query and Ranking

## Status

Accepted for stage 7; runtime fixture packaging was superseded on 2026-07-13.

The candidate-query and ranking design remains active. The historical decision
to package `stage7_test.lex` no longer applies: production HAPs now package only
`production.lex`, and Stage 7 fixture lexicons are consumed by tests outside the
application package.

## Context

Stage 6 produced a deterministic binary lexicon but the formal input chain still
returned empty candidates. Stage 7 needs real candidates without moving lexicon
business logic into ArkTS or C++ and without introducing sentence decoding or
user learning.

## Decision

Stage 7 adds:

- `lexicon-core::runtime_index` for exact and bounded prefix lookup on the
  existing sorted pinyin-key index;
- `candidate-query` for runtime exact/prefix query, query limits, deduplication
  handoff, and bounded query-result caching;
- `candidate-ranking` for deterministic ranking and `text + reading`
  deduplication;
- `ime-engine` candidate session state for current page, previous/next page,
  selection, and composition reset;
- Stage 7 FFI methods: `selectCandidate`, `nextCandidatePage`, and
  `previousCandidatePage`;
- ArkTS rawfile installation that copies `stage7_test.lex` to the app sandbox
  and passes that path in `EngineConfig.lexiconPath`.

The binary lexicon format remains `1.0`. Stage 6 already stores entries sorted
by normalized pinyin key and keeps same-key entries contiguous, so exact query
uses binary search and prefix query uses lower-bound range scanning over the
index. No format upgrade was needed.

## Ranking and Deduplication

The deduplication key is:

```text
candidate text + normalized reading
```

If duplicates are found, base frequency keeps the maximum value, match type
keeps the better class (`Exact` before `Prefix`), and sources are merged into a
sorted comma-separated string.

Ranking uses only Stage 7 data:

1. exact match before prefix match;
2. higher base frequency before lower frequency;
3. text ascending;
4. reading ascending;
5. source ascending;
6. stable candidate id ascending.

The policy does not read HashMap iteration order, user history, current editor
context, recent selection time, or language-model scores.

## Candidate IDs

Candidate IDs are stable strings derived from:

```text
lexicon version + normalized reading + candidate text
```

They are not random UUIDs and are repeatable across identical lexicons.

## Pagination

Pagination state belongs to Rust `ImeEngine`. ArkTS renders the current page
returned by Rust and sends page commands back through `EngineCoordinator`. C++
does not store candidate state.

Input changes, backspace, reset, scheme changes, and candidate selection reset
the page to the first page or clear it as appropriate.

## Cache Strategy

`candidate-query` uses an in-crate bounded cache with a fixed capacity. The key
includes:

```text
scheme id + normalized reading + query mode + page size + lexicon version
```

Cache hits and misses return the same candidate order. Cache entries are
cleared on reset and scheme changes, and the cache cannot grow without bound.
No third-party cache dependency is introduced.

## Resource Installation

At the time of the Stage 7 decision, the repository only had a hand-authored
test lexicon, and Stage 7 packaged that binary as:

```text
entry/src/main/resources/rawfile/stage7_test.lex
```

ArkTS `LexiconResourceInstaller` copies it to the application files directory
once per ability lifecycle when needed. ArkTS does not inspect binary internals.
C++ forwards the UTF-8 path unchanged. Rust loads and validates the binary file
at engine creation.

This test lexicon is only for Stage 7 functional validation and is not a
production Chinese dictionary.

## FFI Extension

The ArkTS interface version and Rust ABI version are both bumped to `2`.
Existing `processKey`, `backspace`, `reset`, and `changeScheme` behavior remains
compatible, while candidates are now populated when a lexicon is loaded.

## Non-Goals

Stage 7 does not implement:

- sentence decoding;
- dynamic multi-entry path search;
- beam search or Viterbi;
- language models;
- user frequency learning;
- user dictionaries;
- recent-selection ranking.

Those features require later-stage state, scoring, persistence, privacy policy,
and tests. Stage 7 only queries complete lexicon entries that already exist in
the binary lexicon.

## Consequences

- Runtime no longer reads TSV.
- ArkTS and C++ remain bridge/UI layers.
- The formal input chain can return Chinese candidates and commit selected
  text through IME Kit.
- Device installation and real text-field validation remain separate from local
  automated verification.
