# Stage 8/9 Device Acceptance Evidence

Date: 2026-07-09

## Environment

- Device target: `127.0.0.1:5557`
- Device type: HarmonyOS emulator
- Software version: `emulator 6.1.0.125(SP9DEVC00E120R4P11)`
- CPU ABI: `x86_64`
- Bundle: `com.example.harmonyos_input`
- IME status after install: `FULL_EXPERIENCE_MODE`
- HAP: `entry/build/default/outputs/default/entry-default-unsigned.hap`
- HAP size: 7,161,861 bytes
- HAP SHA-256: `D02D5E52F3F459B7C9708EE3B277BA53C04F3E2E8E6E5FB1493B8A16D2757C98`

## Commands

```powershell
hdc list targets
hdc uninstall com.example.harmonyos_input
hdc install -r entry\build\default\outputs\default\entry-default-unsigned.hap
hdc shell bm clean -n com.example.harmonyos_input -d
hdc shell ime -e com.example.harmonyos_input -f
hdc shell ime -s com.example.harmonyos_input
hdc shell ime -g
hdc shell aa start -b com.example.harmonyos_input -a EntryAbility
hdc shell uitest dumpLayout -p /data/local/tmp/<name>.json
hdc shell uitest screenCap -p /data/local/tmp/<name>.png
hdc shell uitest uiInput click <x> <y>
hdc shell aa force-stop com.example.harmonyos_input
```

Full transcript: `docs/evidence/stage9/device/final_acceptance_2026-07-09.log`.

## Results

| Scope | Result | Evidence |
| --- | --- | --- |
| Install HAP | PASS | `final_acceptance_2026-07-09.log` |
| Enable IME | PASS | `ime -g` reported `com.example.harmonyos_input`, `FULL_EXPERIENCE_MODE` |
| Stage 8 `nihc` full candidate | PASS | `final_stage8_nihc_candidates.png`, `final_stage8_nihc_committed.json` |
| Stage 8 `uurufa` full and partial candidates | PASS | `final_stage8_uurufa_candidates.png` |
| Stage 8 partial commit and remaining input | PASS | `final_stage8_uurufa_partial_committed.json`, `final_stage8_uurufa_full_committed.json` |
| Stage 9 base order | PASS | `final_stage9_base_ni_2_after_i.json` showed `你`, `尼`, `泥` |
| Stage 9 repeated non-first selection | PASS | `final_stage9_mud_commit_1.json` through `final_stage9_mud_commit_4.json` |
| Stage 9 bounded learning | PASS | `final_stage9_learned_ni_2_after_i.json` showed `你`, `泥`, `尼` |
| Stage 9 hide flush and process restart | PASS | `final_stage9_restart_ni_2_after_i.json` kept `你`, `泥`, `尼` after `隐藏` and `aa force-stop` |

Final transcript marker:

```text
FINAL_DEVICE_ACCEPTANCE_RESULT=PASS
```

## Runtime Fixes Validated

- `CandidateBar.ets`: made the page-control overlay transparent for hit testing so candidate text clicks reach the candidate row.
- `InputSessionController.ets`: flushes the Stage 9 user model before hiding the keyboard, so learned ordering persists through a later process restart.

## Limits

- This is emulator acceptance, not physical-device acceptance.
- Password/input-type privacy behavior was not validated on a real password field; full input type routing remains Stage 10 scope.
- Settings-page user model clear UX remains Stage 11 scope.
