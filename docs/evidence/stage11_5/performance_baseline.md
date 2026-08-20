# Stage 11.5 performance and size baseline

Host: Windows desktop build, release-mode Rust benchmark, 2026-07-13. These are
engineering baselines, not HarmonyOS device timings.

| Metric | Result |
| --- | ---: |
| Raw source files / bytes | 2 / 1,266,891 |
| Accepted entries | 65,122 |
| Binary bytes | 3,734,484 |
| Build script wall time | about 34 s (conversion + two verified builds + corpus generation) |
| Cold read + parse | 56.337 ms |
| Warm in-memory parse | 57.961 ms |
| Exact query P50 | 4.4 µs |
| Exact query P95 | 23.2 µs |
| Exact query P99 | 61.5 µs |
| Slowest sampled query | 227.0 µs (`yi`) |
| Multi-syllable process P50 | 703.1 µs |
| Multi-syllable process P95 | 1.242 ms |

The benchmark executed 5,000 exact queries and 500 multi-syllable engine input
sequences. Process peak memory and post-load resident delta were not collected:
the repository has no stable cross-platform memory probe and fabricated estimates
would be misleading. HarmonyOS startup, first-key, continuous-key, and process-memory
metrics remain uncollected because current UI automation does not expose a reliable
measurement boundary. Functional x86_64 simulator acceptance passed.

The unsigned HAP is 11,248,595 bytes, SHA-256
`2DCAD7666FAAFD3FDE848308D85FD2AF956CB1593BCC8DD2C3FF7092FC7F6485`.
Against the prompt's stage 11 baseline of 7,502,316 bytes, it increased by
3,746,279 bytes (49.93%). The 3,734,484-byte production lexicon accounts for
99.69% of the byte increase and 33.20% of the resulting HAP.
