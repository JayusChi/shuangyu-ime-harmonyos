# Pinyin-9 evaluation dataset provenance

Version: 1.0.0

Authoring/freeze preparation date: 2026-08-17 (Asia/Shanghai).

The public regression layer is a deterministic conversion of every applicable `clean` sample in the byte-frozen quanpin v1 dataset. When multiple original samples become the same `rawDigits + expectedTexts` pair under T9, they are deterministically collapsed and every original ID is retained in `sourceSampleIds`; this satisfies the duplicate gate without editing the frozen source. It retains the original expected text, category, source ID, and source sample identity. It is explicitly labelled `converted_public_regression` and is not represented as new blind data.

The T9-specialized layer contains independently authored common-character seeds plus deterministic synthetic compositions and T9-specific input transforms of accurately identified project-authored quanpin samples. `sourceSampleIds` records the exact upstream case. Error forms are generated before evaluation and are validated as the declared single edit. No expected text was read from current engine candidates.

No commercial IME candidate list, commercial corpus, user data, web scrape, or license-unknown text is present. The blind partition is byte-frozen before its sole three-repeat evaluation command; dev failures may be inspected, but blind rows may not be edited after freeze.
