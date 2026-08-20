# ADR-0005: Stage 5 Formal Cross-Language Interface

## Status

Accepted.

## Context

Stage 4 produced a Rust-only Xiaohe shuangpin parser. Stage 5 must expose it to ArkTS through C++ without moving parser rules into ArkTS or C++, and without exposing native pointers to ArkTS.

## Decision

Add a formal Rust `ImeEngine` in `ime-engine` that owns `ShuangpinParser` and produces a stable `CompositionResult`. The Rust C ABI in `ime-ffi` creates opaque engine handles, returns UTF-8 JSON buffers, catches panic at every ABI boundary, and releases all Rust-allocated buffers through one Rust free function.

C++ owns a thread-safe `EngineRegistry`. ArkTS receives only positive numeric IDs. Each ID maps to a C++ RAII `RustEngineHandle`, which owns the Rust opaque handle and destroys it automatically.

The official ArkTS entrypoint is `NativeEngineGateway`, and lifecycle ownership is centralized in `EngineCoordinator`. UI components read state through controllers and stores; they do not import `libime_bridge.so`.

The old fixed-candidate regression interface remains available as a compatibility/test route.

## Rationale

- ArkTS numeric IDs avoid storing or truncating native pointers in JavaScript numbers.
- `EngineRegistry` gives C++ a single place to validate IDs, handle repeated destroy calls safely, and protect engine access with a mutex.
- Rust returns UTF-8 JSON because the Stage 5 result shape is stable, easy to test, and lower-risk than introducing a wide C struct protocol before performance data exists.
- Rust memory is released by Rust because cross-language allocation/free pairs are unsafe and easy to mismatch.
- `destroy` and `free_buffer` accept pointers that can be cleared so repeat cleanup is safe.
- Keeping the fixed-candidate interface protects Stage 2/3 regression tests while the formal chain replaces it for real input.

## Consequences

- Stage 5 supports only `xiaohe`; adding other schemes remains a later task.
- There is still no dictionary, no Chinese candidates, and no candidate commit in the formal chain.
- C++ contains no shuangpin mapping, syllable validation, lexicon lookup, or ranking logic.
- ArkTS can now update `InputSessionStore` with Rust-generated `preeditText` and parser state.
- Device validation still requires a connected HarmonyOS target and is reported separately from local build/test validation.
