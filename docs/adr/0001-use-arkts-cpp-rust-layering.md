# ADR-0001: Use ArkTS -> C++ -> Rust Layering

## Status

Accepted.

## Context

HarmonyOS input method lifecycle, UI, and IME Kit calls belong in ArkTS. The input method core should remain testable without HarmonyOS APIs. Node-API and C ABI provide a narrow bridge between these worlds.

## Decision

Use:

```text
ArkTS -> C++ Node-API -> Rust C ABI
```

## Consequences

- ArkTS keeps platform and UI responsibilities.
- C++ stays a bridge and must not contain input method algorithms.
- Rust owns current and future engine behavior.
- Cross-layer changes require updates to API contract and tests.
