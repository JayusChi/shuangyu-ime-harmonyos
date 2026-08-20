# ADR-0004: Keep Stage 4 Shuangpin Parsing Data-Driven Inside Rust

## Status

Accepted.

## Context

Stage 4 needs real shuangpin code parsing while preserving the existing ArkTS -> C++ -> Rust layering. The parser must be testable without HarmonyOS APIs, must not force a premature FFI shape, and must keep Xiaohe/FlyPY key rules out of parser control flow.

## Decision

Use three Rust-only crates:

```text
pinyin-syllable
  <- shuangpin-schema
  <- shuangpin-parser
  <- ime-engine
```

Use `engine-rust/schemas/xiaohe.json` as the Xiaohe schema data file, embedded at compile time by `shuangpin-schema`. Use a static pinyin syllable inventory in `pinyin-syllable`. Use deterministic two-key splitting in `shuangpin-parser`, with one trailing key represented as `Incomplete`.

Do not expose the stage 4 parser through C ABI in this stage. `ime-engine` may re-export a Rust constructor so stage 5 can wrap it with an Engine Handle.

## Consequences

- ArkTS and C++ keep their stage 3 responsibilities and do not receive shuangpin business logic.
- The parser is fully testable with `cargo test --workspace`.
- The schema can be validated independently and can later accept additional schemes.
- No third-party Rust dependencies are added.
- The current parser intentionally does not query dictionaries or produce Chinese candidates.
- Stage 5 must define the formal cross-language handle, result serialization, and memory contract before ArkTS can use this parser at runtime.
