# PowerShell ZIP compatibility fixtures

These three small templates were packaged using the .NET ZIP implementation in
`scripts/package-keyboard-customization.ps1`. They cover a color-only skin, an
image skin and a keyboard structure. `verify.cjs` imports the original bytes to
check compatibility with packages produced outside the JavaScript editor.

The fixtures were retained from the 2026-09-08 template examples. They contain
only sample definitions and skin images; they do not depend on local outputs.
Current distributable examples are built from `examples/keyboard-customization/`
by `package-preview.cjs`.
