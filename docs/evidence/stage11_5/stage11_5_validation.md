# Stage 11.5 validation record

Status: **complete** on 2026-07-13. ARM64 physical-device execution is explicitly
excluded by user direction; arm64-v8a Native build remains required and passed.

## Production data and corpus

The deterministic production build combines pinned Apache-2.0 Rime data with seven
project-authored Apache-2.0 common short sentences. It contains 65,122 entries,
39,035 pinyin keys, and 39,032 encodable Xiaohe sequences. The 3,734,484-byte binary
has SHA-256 `765E2B0BD90244192A4C1BB6B2EC501ED28E0DBD731CBAB4C326534F091ECA10`.

All 5,171 fixed cases passed: 5,000 generated coverage cases, 30 high-value manual
cases, 78 curated idioms, 10 short sentences, 26 incomplete inputs, and 27 illegal
inputs. Generated top-1/top-3/top-5/queryability and human polyphone/idiom/sentence/
safety pass rates are all 100%. Generated hit rates are coverage metrics, not claims
about unrestricted natural-language quality.

## Local and package validation

`verify-stage11_5.ps1` passed Rust fmt, clippy with warnings denied, workspace and
focused crate tests, x86_64 and arm64-v8a Native builds, ArkTS tests, HAP build, and
exact-size package inspection. The unsigned HAP is 11,248,595 bytes with SHA-256
`2DCAD7666FAAFD3FDE848308D85FD2AF956CB1593BCC8DD2C3FF7092FC7F6485`.

## Emulator validation

On the connected x86_64 HarmonyOS emulator (`6.1.0.125`):

- stage 10 full editor/layout regression passed;
- stage 11 settings, persistence, learning, and clear-model regression passed;
- stage 11.5 typed and committed `你好`, `输入法`, `银行`, `一心一意`,
  `不用客气`, and `今天天气不错` through real keyboard coordinates;
- partial candidate `输入` was selected on candidate page 2, remaining `fa` produced
  `法`, and the exact combined text was committed;
- after hiding the keyboard and restarting the process, the production lexicon loaded
  and `你好` was queried and committed again.

Device layouts, screenshots, and the complete transcript are under `device/`.
HarmonyOS timing and process-memory numbers remain marked uncollected because the
current UI automation/tooling does not expose a reliable measurement boundary; no
numbers were fabricated. ARM64 physical-device behavior is not claimed.
