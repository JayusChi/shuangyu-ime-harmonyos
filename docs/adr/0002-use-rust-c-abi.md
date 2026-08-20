# ADR-0002: Rust Communicates Through C ABI

## Status

Accepted.

## Context

The HarmonyOS native module is C++ Node-API. Rust objects should not cross directly into ArkTS or C++ ownership.

## Decision

Rust exposes stable `extern "C"` functions and opaque buffers. Rust-allocated buffers are released by `ime_engine_free_buffer`.

## Consequences

- ABI ownership rules are explicit.
- Panic is caught inside Rust FFI.
- C++ can remain focused on validation, conversion, and memory release.
- Future ABI changes must preserve compatibility or bump the ABI contract.
