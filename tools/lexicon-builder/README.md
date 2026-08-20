# Lexicon Builder Entry

The Cargo package lives under `engine-rust/tools/lexicon-builder` so it can be a
member of the existing `engine-rust` workspace and participate in
`cargo run -p lexicon-builder`, `cargo clippy --workspace`, and
`cargo test --workspace`.

Run it from `engine-rust`:

```powershell
cargo run -p lexicon-builder -- `
  --input ..\dictionaries\source\stage6_test.tsv `
  --output ..\dictionaries\generated\stage6_test.lex `
  --lexicon-version 1 `
  --strict
```

Build the project-authored ordered code-table fixture without changing the
default production pinyin path:

```powershell
cargo run -p lexicon-builder -- `
  --input ..\dictionaries\source\test-fixtures\flypy_order_table.txt `
  --input-format flypy-table `
  --output $env:TEMP\flypy_order.lex `
  --lexicon-version 1 `
  --strict --verify
```
