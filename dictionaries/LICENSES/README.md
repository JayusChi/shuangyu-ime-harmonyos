# Dictionary Source Licenses

## rime-pinyin-simp production source

- License: Apache-2.0 (`rime-pinyin-simp-Apache-2.0.txt`)
- Attribution: `rime-pinyin-simp-AUTHORS.txt`
- Pinned provenance and checksum: `../manifest.json`
- Purpose: stage 11.5 production runtime lexicon

The same Apache-2.0 text covers the separately identified project-authored stage 11.5
short-sentence source listed in `../manifest.json`.

## stage6_test

- Name: Stage 6 hand-authored test lexicon
- Path: `dictionaries/source/stage6_test.tsv`
- Source: manually constructed by this project for stage 6 tests
- Project-authored: yes
- Purpose: verify TSV parsing, pinyin normalization, duplicate merging, deterministic binary serialization, and validation tooling
- License/copyright: project test data, `UNLICENSED` with the rest of the current repository
- Redistribution: allowed only as part of this repository's test materials

该测试词库为项目测试用途手工构造数据，不代表完整中文词库，
不用于正式发布，不包含从来源不明词库复制的数据。

## Required Metadata for Future Third-Party Dictionaries

Before any third-party dictionary is imported, record:

- dictionary name and version;
- original source URL or publisher;
- exact file path in this repository;
- license name and license text location;
- whether redistribution is allowed;
- whether commercial use is allowed;
- transformation steps from source to project format;
- checksum of the original downloaded artifact;
- reviewer and import date.

Do not import dictionaries with unclear origin, unclear license, or unknown redistribution terms.
