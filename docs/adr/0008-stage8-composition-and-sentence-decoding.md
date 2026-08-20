# ADR 0008: Stage 8 Composition and Sentence Decoding

## Status

Accepted for stage 8 local implementation.

## Context

Stage 7 can query and rank exact or prefix candidates for one normalized pinyin
key. It intentionally does not assemble multiple words into a sentence. Stage 8
needs continuous shuangpin input, sentence candidates, partial candidate commit,
and rollback after deletion while preserving the ArkTS -> C++ -> Rust boundary.

## Decision

Stage 8 adds `engine-rust/crates/sentence-decoder` as an independent Rust crate.
It owns the syllable graph, bounded path search, scoring, de-duplication, and
partial-commit metadata. `ime-engine` coordinates parser state and calls the
decoder when at least two complete syllables are available. ArkTS and C++ keep
using the existing `processKey`, `backspace`, `selectCandidate`, pagination,
`reset`, and `changeScheme` APIs.

## Search Algorithm

The decoder uses Viterbi-style dynamic programming with a beam cap per syllable
position. Viterbi was chosen because the current stage 8 model only needs a
deterministic best path set over an acyclic syllable graph, and it is simpler to
bound and test than a free-form beam search over arbitrary partial strings.

The limits are centralized in `DecodeLimits`:

- `max_raw_len = 64`
- `max_syllables = 32`
- `max_word_syllables = 6`
- `max_edges = 256`
- `beam_width = 8`
- `max_output_paths = 8`
- `max_entries_per_key = 8`
- `max_output_candidates = 16`

## Graph Model

Nodes are syllable positions. A `WordEdge` covers `[start, end)` and stores:
entry ID, text, reading, start/end positions, syllable count, base frequency,
source, and whether the edge is a fallback. Edges are generated only from the
verified `BinaryLexicon` via `lexicon-core::runtime_index`; the decoder never
reads TSV or binary bytes directly.

If a reachable syllable position has no lexicon edge, the graph creates a
single-syllable fallback edge using the pinyin syllable text. Fallback edges are
penalized and keep decoding safe instead of panicking or looping.

## Scoring

Sentence scoring is independent from stage 7 candidate ranking. It combines:

- normalized base frequency buckets;
- multi-syllable word bonus;
- complete coverage bonus;
- extra word-count penalty;
- fallback edge penalty;
- pending-tail penalty;
- stable tie-breakers on fallback count, word count, text, reading, and path key.

Stage 7 ranking is still used only by `candidate-query` for exact/prefix word
queries. It is not summed to become sentence score.

## Partial Commit

The decoder returns internal `raw_end` and consumed syllable metadata. `ime-engine`
stores it in the candidate session. When `selectCandidate` is called:

- if the candidate consumes all raw input, Rust returns `commitText` and clears
  composition;
- if it consumes only a prefix, Rust returns `commitText`, reparses the remaining
  raw input, regenerates candidates, and sets `compositionFinished=false`.

ArkTS only submits `commitText` to IME Kit and updates the store from Rust's
returned `CompositionResult`.

## Interface Compatibility

No `CompositionResult` or `Candidate` fields changed. ABI/interface version stays
at `2`; engine version is now `0.0.1-stage8`. C++ remains a bridge and does not
store sentence graph, path, or candidate business state.

## Boundary Preservation

- ArkTS does not split syllables, query lexicon entries, rank candidates, or
  assemble sentences.
- C++ does not contain Viterbi, beam search, graph, pinyin, lexicon, cache, or
  scoring logic.
- Rust core does not depend on HarmonyOS APIs.
- Runtime code reads `.lex` binary artifacts only; TSV is used by the offline
  builder and tests.
