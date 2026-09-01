# Production dictionary sources

The production lexicon is built from Rime's `rime-pinyin-simp` dictionary at commit
`0c6861ef7420ee780270ca6d993d18d4101049d0`, retrieved on 2026-07-13.

Upstream: <https://github.com/rime/rime-pinyin-simp>

License: Apache License 2.0. Redistribution and modification are allowed subject to
the license conditions. The unmodified license and upstream author list are stored
under `dictionaries/LICENSES/`. Exact provenance, checksum, and transformations are
machine-readable in `dictionaries/manifest.json`.

The stage 6 and stage 8 hand-authored files remain test fixtures only. They are not
merged into or loaded as the production runtime dictionary.

The mature full-pinyin layer also imports Jieba `dict.txt` from release `v0.42.1`
and derives readings with the pinned pypinyin `0.55.0` wheel. Both inputs are MIT
licensed, stored under `source/`, and rebuilt offline by
`scripts/import-jieba-quanpin.py`. The importer accepts only common-CJK words of
at most 16 characters, validates every syllable against the engine inventory,
preserves established Rime rows on exact text+reading duplicates, and emits a
deterministic report plus normalized TSV under `generated/`.

Stage 11.6.2A synthetic categorized code tables are generated entirely by the
repository's deterministic test tool. Their separate origin record is
`LICENSES/CODE_TABLE_FIXTURE_ORIGIN.md`. They are not production dictionary
sources and are forbidden from Release HAP resources.

Stage 11.5 also includes project-authored common short sentences and phrases from
`source/stage11_5_short_sentences.tsv`, licensed under Apache-2.0. They are tracked as
a separate source in `manifest.json`, including their SHA-256, and are merged only by
the offline builder.
