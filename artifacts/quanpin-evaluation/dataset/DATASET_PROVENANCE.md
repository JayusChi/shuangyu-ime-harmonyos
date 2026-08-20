# Quanpin evaluation dataset provenance

Version: 1.0.0

Frozen-authoring date: 2026-08-13 (Asia/Shanghai)

License: PROJECT-INTERNAL-AUTHORED-DATA. This dataset was authored for this repository and contains no imported third-party corpus.

The expected texts and pinyin readings were written from ordinary Mandarin knowledge. Template expansion combines only the author-written morphemes in this source. Typo transformations are deterministic edits of those author-written readings. No commercial IME, web scrape, production lexicon lookup, current-engine candidate output, or unit-test export was used.

`blind.jsonl` is immutable after the first freeze. Any byte change is rejected by the evaluator until an operator explicitly creates a new baseline identity.
