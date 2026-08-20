# ADR 0009: Stage 9 User Learning Model

## Status

Accepted for local implementation.

## Context

Stage 9 adds local user frequency learning on top of the stage 8 candidate and sentence decoding pipeline. The project must keep the existing ArkTS -> C++ -> Rust boundary: ArkTS owns HarmonyOS lifecycle and sandbox paths, C++ owns only bridge conversion, and Rust owns learning, scoring, persistence, atomic save, and recovery.

## Decisions

1. The user model is an independent Rust crate at `engine-rust/crates/user-model`.
2. The persisted key is `(schemeId, lexiconVersion, sourceKind, candidateHash)`. `candidateHash` is a deterministic FNV-1a 64-bit hash of the internal stable candidate id. This avoids saving candidate text even when older internal candidate ids contain text.
3. The model does not save `rawInput`, edit context, app package names, full input content, candidate text, contacts, clipboard data, or network-derived data.
4. Selection count is a saturating `u32` capped at `1024`.
5. Recency uses a logical selection sequence, not wall-clock time. Tests are deterministic and unaffected by system clock changes.
6. User weight is computed in `user-model/src/scoring.rs` and capped at `5000`. Count weight grows quickly for the first selections, then slows and caps at `4000`; recency contributes at most `1000` and decays by logical event age.
7. `candidate-ranking` exposes a user-score ranking entrypoint. With all user scores at zero, ordering is identical to stage 8.
8. `sentence-decoder` accepts a read-only user score callback. It still does not read or write user model files.
9. `ime-engine` records learning only after a candidate is selected through the current candidate session. Backspace, reset, page turns, scheme changes, invalid indexes, and disabled sessions do not learn.
10. Partial commit learns only the selected prefix candidate. Remaining raw input is not included in the learned key.
11. Global `userLearningEnabled=false` and `sessionLearningAllowed=false` both disable new learning and user-weighted ranking for that state, preserving stage 8 order.
12. The file format is compact binary with magic `HUM9`, format version, data version, record count, payload length, and checksum.
13. Atomic save uses `user_model.tmp` plus validation before replacement and `user_model.bak` for recovery. On Windows, replacement uses backup-before-remove because `rename` cannot overwrite an existing file reliably.
14. Load recovery priority is primary file, then backup file, then quarantine corrupt primary and use an empty model. Recovery never panics and never blocks system lexicon candidates.
15. Capacity control uses max record count, max file size, duplicate key merge on load, saturating counts, and compaction that keeps higher-value and more recent records.
16. ABI remains version `2` because existing exported functions, structs, memory ownership, and required JSON fields were not changed. Stage 9 adds independent exported functions only.
17. Engine version becomes `0.0.1-stage9`.
18. Stage 9 does not implement a settings page. It only provides application service methods and native interfaces; UI settings remain scheduled for stage 11.

## Consequences

- Existing stage 7 and stage 8 fixtures remain valid when the model is empty or learning/ranking is disabled.
- The persisted user model cannot be inspected as plain JSON and does not contain candidate text.
- Rust owns all model parsing and recovery. C++ and ArkTS cannot inspect or repair the model file.
- Stage 10 still needs full input field type mapping. Stage 9 provides the formal `setSessionLearningAllowed(false)` privacy capability and tests it with simulated sessions.
