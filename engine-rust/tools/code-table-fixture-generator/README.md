# code-table-fixture-generator

Deterministic offline generator and builder for the stage 11.6.2A project-authored synthetic code-table fixture.

```powershell
cargo run -p code-table-fixture-generator -- generate <output-dir>
cargo run -p code-table-fixture-generator -- build <manifest.json> <fixture.bundle>
cargo run -p code-table-fixture-generator -- verify <fixture.bundle>
cargo run -p code-table-fixture-generator -- all <output-dir>
```

`all` writes source tables and a manifest under the selected test output directory, then writes clearly marked fixture-only nested binaries and `code-table-fixture-synthetic.bundle` under `binary/`. The output directory is never inferred from the current working directory.

Do not copy any generated file to `entry/src/main/resources`. See `docs/features/code-table/CODE_TABLE_FIXTURE_GENERATION.md`, `docs/features/code-table/CODE_TABLE_BUNDLE_FORMAT.md`, and `dictionaries/LICENSES/CODE_TABLE_FIXTURE_ORIGIN.md`.
