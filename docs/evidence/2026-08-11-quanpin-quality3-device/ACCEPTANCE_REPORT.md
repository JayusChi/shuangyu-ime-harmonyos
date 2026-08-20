# 26-key quanpin quality3 acceptance report

Date: 2026-08-11 (Asia/Shanghai)

## Outcome

The safety-critical defect is fixed: a quanpin letter action cannot commit text, the ArkTS controller rejects and rolls back a native letter result that violates that contract, and no-candidate/cancel/hide paths no longer finish compatible raw text into irreversible editor text. Initial and mixed-spelling recall is implemented in Rust, and the editable raw-input limit is 256 letters with a fail-closed 257th key.

This report does **not** claim mainstream candidate quality. The requested independent 1,000-item blind evaluation and word-level bigram/trigram language model have not been completed; those items are recorded as `NOT_RUN`/`NOT_MET` below.

## Root causes

1. **Old package / old Native was active.** Before replacement, `bm dump` reported installed `0.3.0`, versionCode `3000000`, buildVersion `1`, x86_64, while two old IME processes were still alive. Source-level tests therefore did not describe the code actually running on the device.
2. **Automatic-commit protocol was not fail-closed at both layers.** Rust now guarantees empty `commitText` and unfinished composition for quanpin letters; ArkTS independently treats any contrary native result as a protocol error and restores the pre-key engine/store snapshot before editor I/O.
3. **Compatible preedit fallback could leak raw text.** No-candidate Space/Enter/punctuation and lifecycle cleanup previously had paths that could finish the editor-owned compatible preview. They now clear/cancel that owned range and never substitute `finishPreviewText` or raw `insertText` as a fallback.
4. **Strict whole-string parsing discarded useful state.** `gj`, `gjt`, mixed full/initial input and incomplete tails were `Invalid` in the strict parser. Candidate recall now uses a bounded Rust lattice over full syllables, initials and a pending final prefix while preserving the original raw composition.
5. **Lexicon/ranking coverage was insufficient.** The existing licensed Rime source contains about 65k entries but misses some common phrases and has no word-level contextual LM. The deterministic project supplement is now 77 entries and includes the required common phrase `第一个人`; this is a narrow data improvement, not a claim that the broader quality problem is solved.

## Installed identity and provenance

- Before install: `0.3.0`, versionCode `3000000`, buildVersion `1`, ABI `x86_64`.
- After clean build and replacement install: `0.3.1`, versionCode `3000001`, buildVersion `2`, device `PHONE-001`, ABI `x86_64`, native path `libs/x86_64`.
- Runtime engine: `0.0.1-pinyin-stage2-quality3`.
- Runtime active scheme: `quanpin`; interface version: `6`.
- Runtime Native identity: `abi=x86_64;rustArchiveSha256=a4bc7a145d8cc3d300c37e60b8ace44b45894c9417a33b6e8da29b57ed878b00;fingerprint=a4bc7a145d8cc3d3`.
- Browser editor attributes: `kind=search`, `preview=false`; this exercises the compatible owned-range path rather than native TextPreview.
- The old process was force-stopped before install, the signed HAP was installed with replacement, and the IME was force-stopped again before being re-enabled and selected.

Runtime log evidence:

```text
Stage0NativeGateway: getEngineVersion ok: 0.0.1-pinyin-stage2-quality3
Stage0NativeGateway: getNativeBuildInfo ok: abi=x86_64;rustArchiveSha256=a4bc7a145d8cc3d300c37e60b8ace44b45894c9417a33b6e8da29b57ed878b00;fingerprint=a4bc7a145d8cc3d3
EngineCoordinator: engine scheme active: version=0.0.1-pinyin-stage2-quality3, schemeId=quanpin, interface=6, native=abi=x86_64;rustArchiveSha256=a4bc7a145d8cc3d300c37e60b8ace44b45894c9417a33b6e8da29b57ed878b00;fingerprint=a4bc7a145d8cc3d3
InputSessionController: editor attributes received: pattern=0, enter=3, preview=false, configured=none
```

The sandboxed device shell cannot read `/data/app/el1/bundle/public/com.corrosion.shuangyuime/entry.hap` (`Permission denied`), so an installed-file SHA readback is `BLOCKED_PERMISSION`. Runtime archive identity plus the HAP-internal/native-stage equality below provides the executable provenance available without root.

## Artifact hashes

| Artifact | Bytes | SHA-256 |
| --- | ---: | --- |
| x86_64 Rust `libime_ffi.a` | 26,414,140 | `A4BC7A145D8CC3D300C37E60B8ACE44B45894C9417A33B6E8DA29B57ED878B00` |
| arm64-v8a Rust `libime_ffi.a` | 26,918,640 | `8B6E989560F47B410BA0A34607E266C53F8B48701BAF4C7F9C4E275F6DC992CF` |
| stripped x86_64 `libime_bridge.so` | 2,982,008 | `F807D001BC51AE8237B06C75EE4342B2BA21D421E9415768194608377C1337D8` |
| HAP x86_64 `libime_bridge.so` | 2,982,008 | `F807D001BC51AE8237B06C75EE4342B2BA21D421E9415768194608377C1337D8` |
| stripped arm64-v8a `libime_bridge.so` | 2,683,656 | `1BE600343AD9D0291050B4670B4CE076E3F07E3490714C43149D01180F0199D7` |
| HAP arm64-v8a `libime_bridge.so` | 2,683,656 | `1BE600343AD9D0291050B4670B4CE076E3F07E3490714C43149D01180F0199D7` |
| production lexicon, source and HAP entry | 3,741,248 | `E14B9FA5546686CB3C7516C8494DD7BF014D4E525D64F08DE0BB6C8DEE721390` |
| final signed HAP | 38,520,540 | `C5DAE46B7D0B86D351604D74F2314446117CB935B676C3EBB21DA7BC0C60ECB8` |
| final unsigned HAP | 38,364,604 | `E46DEB38DE7CC62B3B36C13C69A610207D960C59F63A5700869EC557FFED6B70` |
| final signed APP | 10,398,754 | `3CDF7E4EA5125655E1D4857D2A4231C4F1FEA3AB732BEE128F04E5E80F5227BD` |

## Tests and measurements

- Full Rust workspace script: `PASS`, including clippy, unit/integration/doc tests, 30 FFI tests, quanpin quality tests, quanpin 256/257 boundary tests, and existing Xiaohe/code-table regressions.
- ArkTS unit tests: `405 run / 405 pass / 0 failure / 0 error`.
- Clean dual-ABI Release HAP/APP build: `PASS`.
- Runtime benchmark, 1,620 letter actions: `failures=0`, `automatic_commits=0`, `ascii_commits=0`, average `4.593 ms/key`, P50 `3.349 ms`, P95 `13.333 ms`.
- Earlier perf1 benchmark reference: average `2.027 ms/key`, 20 automatic commits. Quality3 removes those commits at the cost of additional recall latency; P95 remains below the 33.3 ms interval corresponding to 30 keys/s on this host benchmark.
- Formal lexicon build: 65,192 accepted rows, 39,105 pinyin keys, byte-deterministic two-build verification. Source is the pinned Apache-2.0 Rime pinyin-simp snapshot plus the project-authored Apache-2.0 supplement; manifest source hash for the 77-row supplement is `0B9EF7BCE3335D9B50C9084516A97A57D5A27AE3139C236FA7C2599F4C4E5F1D`.

## Modified files

- Engine/decoder: `candidate-query/src/query_engine.rs`, `ime-engine/src/formal.rs`, `engine-protocol/src/composition.rs`, `shuangpin-parser/src/quanpin.rs`.
- Rust/FFI verification: `ime-engine/tests/quanpin_stage2.rs`, `ime-engine/tests/quanpin_quality.rs`, `ime-ffi/src/lib.rs`, `ime-engine/examples/quanpin_runtime_baseline.rs`.
- Native identity bridge: `entry/src/main/cpp/CMakeLists.txt`, `napi/engine_napi.h`, `napi/engine_napi.cpp`, `napi/module_init.cpp`, `entry/src/main/types/libime_bridge/index.d.ts`.
- ArkTS protocol protection: `NativeEngineTypes.ets`, `NativeEngineGateway.ets`, `EngineCoordinator.ets`, `InputSessionController.ets`, `entry/src/test/Stage2Controller.test.ets`.
- Product/data: `AppScope/app.json5`, `dictionaries/source/stage11_5_short_sentences.tsv`, `dictionaries/manifest.json`, generated and packaged `production.lex`.
- Contract/evidence: `docs/API_CONTRACT.md`, `docs/PINYIN_STAGE2_QUANPIN_26.md`, and this evidence directory.

## Device scenarios on final HAP

Target: x86_64 HarmonyOS Phone emulator, Huawei Browser Search TextInput, physical-key event route.

| Scenario | Observed result |
| --- | --- |
| `guojitian` before explicit action | TextInput shows owned raw `guojitian`; candidate 1 is `过几天`; no commit occurred. |
| Space after `guojitian` | TextInput becomes exactly `过几天`. |
| `gj` | Owned raw remains `gj`; candidates are `感觉 / 国家 / 估计 / 根据 / 国际`; no ASCII commit. |
| Existing body `我是这样` + `diyigeren` | Owned raw remains reversible and candidate 1 is `第一个人`; clicking it yields exactly `我是这样第一个人`. |
| `dyigeern` | No correction candidate is currently produced, but raw remains an owned composition; Esc removes it and leaves the field empty, proving it was not irreversibly committed. |

Because this browser advertises `preview=false`, accessibility text includes the temporary compatible composition. The decisive checks are that Esc removes it and candidate replacement produces only Chinese; it is not treated as committed editor content by the IME state machine.

## NOT_RUN / NOT_MET

- Independent 1,000-item, no-leak Top1/Top3/Top5 evaluation: `NOT_RUN`; therefore the requested 90%/80%/95% quality targets are `NOT_PROVEN`.
- New large externally sourced modern conversational corpus: `NOT_ADDED`; only the already pinned licensed Rime source and 77-row project supplement are shipped.
- Word-level bigram/trigram contextual language model and spelling-correction model: `NOT_MET`.
- `dyigeern` correction candidate: `NOT_MET`; safety/no-ASCII-leak behavior passes.
- 30 keys/s device injection: `NOT_RUN`; host Rust/FFI latency and ordering tests pass, but are not a device substitute.
- Native TextPreview-supported editor device case: `NOT_RUN`; the accepted Browser editor is `preview=false`.
- Pad and 2in1 device runs, soft-keyboard matrix, arm64-v8a real device, third-party apps other than Huawei Browser: `NOT_RUN`.
- Installed public HAP/SO SHA readback: `BLOCKED_PERMISSION` on non-root device shell.
