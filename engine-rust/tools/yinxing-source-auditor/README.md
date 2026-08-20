# Xiaohe Yinxing source auditor

This dependency-free Rust tool performs the read-only Stage 11.6.2B receipt audit for the
repository-root `码表/` and `小鹤音形/` delivery directories. It never executes source content,
never follows source symlinks, and writes only to explicitly supplied output/report directories.

Run from `engine-rust` through `../scripts/audit-xiaohe-yinxing.ps1`. An unresolved audit still
writes complete redacted outputs and exits with code 2. The accepted contract rejects and
quarantines credential-bearing configuration as a whole, emits a value-free deterministic
`sanitized_configuration.json`, and admits only explicitly listed numbered authoritative files.
`--allow-blocked` is reserved for diagnosis and never changes the contract result.
