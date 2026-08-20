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

Stage 11.6.2A synthetic categorized code tables are generated entirely by the
repository's deterministic test tool. Their separate origin record is
`LICENSES/CODE_TABLE_FIXTURE_ORIGIN.md`. They are not production dictionary
sources and are forbidden from Release HAP resources.

Stage 11.5 also includes project-authored common short sentences and phrases from
`source/stage11_5_short_sentences.tsv`, licensed under Apache-2.0. They are tracked as
a separate source in `manifest.json`, including their SHA-256, and are merged only by
the offline builder.
