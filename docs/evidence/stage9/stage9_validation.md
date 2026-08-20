# Stage 9 Validation Evidence

Date: 2026-07-09

## Scope

Stage 9 implements local user frequency learning, bounded user weighting, delayed persistence, recovery, clear, privacy session disablement, and cross-language control interfaces.

## Automated Evidence

Commands executed so far in this work session:

```powershell
cargo test -p user-model
cargo test -p candidate-ranking
cargo test -p sentence-decoder
cargo test -p ime-engine
cargo test -p ime-ffi
cargo fmt
cargo clippy --workspace --all-targets -- -D warnings
$env:DEVECO_SDK_HOME='C:\Program Files\Huawei\DevEco Studio\sdk'; & 'C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat' --no-daemon --mode module -p module=entry@default test
```

Observed results:

| Area | Result |
| --- | --- |
| `user-model` | Passed, 20 tests |
| `candidate-ranking` | Passed, 10 tests |
| `sentence-decoder` | Passed, 21 tests |
| `ime-engine` | Passed, 32 unit tests plus stage 7/8/9 fixture tests |
| `ime-ffi` | Passed, 16 tests |
| Rust clippy | Passed |
| ArkTS unit tests | Passed via hvigor |

Full `scripts/verify-stage9.ps1`, native dual ABI, Rust workspace, and HAP results are recorded in `PROJECT_STATE.md` after final execution.

## Final Stage 9 Script

```powershell
powershell -ExecutionPolicy Bypass -File scripts\verify-stage9.ps1
```

Result: passed.

Script summary:

| Step | Result |
| --- | --- |
| Environment check | PASS |
| Stage 9 required files | PASS |
| Rust format | PASS |
| Rust clippy | PASS |
| user-model tests | PASS |
| candidate-ranking tests | PASS |
| sentence-decoder tests | PASS |
| ime-engine tests | PASS |
| ime-ffi tests | PASS |
| Rust workspace tests | PASS |
| Rust x86_64 and arm64-v8a artifacts | PASS |
| ArkTS unit tests | PASS |
| C++/ArkTS/HAP build | PASS |
| Stage 9 architecture boundary checks | PASS |
| Artifact summary | PASS |

Artifacts from the final run:

| Artifact | Size |
| --- | ---: |
| `engine-rust/target/ohos/x86_64/libime_ffi.a` | 23,909,764 bytes |
| `engine-rust/target/ohos/arm64-v8a/libime_ffi.a` | 24,493,554 bytes |
| `entry/build/default/outputs/default/entry-default-unsigned.hap` | 7,161,861 bytes |

Final HAP SHA-256: `D02D5E52F3F459B7C9708EE3B277BA53C04F3E2E8E6E5FB1493B8A16D2757C98`.

Clean log for the final local verification run: `docs/evidence/stage9/device/stage9_verify_after_hide_flush_clean_2026-07-09.log`.

## Device Evidence

Date: 2026-07-09

Device:

- Target: `127.0.0.1:5557`
- Type: HarmonyOS emulator
- Version: `emulator 6.1.0.125(SP9DEVC00E120R4P11)`
- ABI: `x86_64`
- Bundle: `com.example.harmonyos_input`
- IME status: `com.example.harmonyos_input`, `FULL_EXPERIENCE_MODE`

Result: passed.

| Item | Result | Evidence |
| --- | --- | --- |
| HAP install and IME enable | PASS | `docs/evidence/stage9/device/final_acceptance_2026-07-09.log` |
| Base `ni` ordering | PASS | `final_stage9_base_ni_2_after_i.json` showed `你`, `尼`, `泥` |
| Repeated non-first selection | PASS | `final_stage9_mud_commit_1.json` through `final_stage9_mud_commit_4.json` |
| Bounded learned ordering | PASS | `final_stage9_learned_ni_2_after_i.json` showed `你`, `泥`, `尼` |
| Hide flush and process restart persistence | PASS | `final_stage9_restart_ni_2_after_i.json` retained `你`, `泥`, `尼` after `隐藏` and `aa force-stop` |

Final transcript marker:

```text
FINAL_DEVICE_ACCEPTANCE_RESULT=PASS
```

Summary document: `docs/evidence/stage9/device/stage8_stage9_device_acceptance_2026-07-09.md`.

Not performed:

- Physical-device validation.
- Real password input field learning disable validation.
- Settings-page clear UX validation.
