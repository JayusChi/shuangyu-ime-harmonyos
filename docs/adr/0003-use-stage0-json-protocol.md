# ADR-0003: Keep Stage 0 JSON Protocol For Now

## Status

Accepted.

## Context

Stage 0 only needs fixed candidates and simple status fields. A flat JSON payload is easy to inspect and sufficient for validation.

## Decision

Keep the current JSON payload shape for stage 1. `engine-protocol` owns serialization, C++ converts it into ArkTS objects, and ArkTS keeps the existing `TestEngineResult` shape.

## Consequences

- Stage 0 behavior remains stable.
- No new third-party serialization dependency is introduced.
- If JSON parsing becomes a bottleneck or the protocol grows, a later ADR can replace it with a typed C structure.
