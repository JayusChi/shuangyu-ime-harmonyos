# Xiaohe Yinxing Production Converter

`yinxing-converter/1.0.0` is the offline production converter. It consumes only the twelve files frozen by `conversion_contract.json`, writes a deterministic `HSPYXP01` 1.0 production bundle, and never executes source actions.

## Build and verify

From the repository root:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\build-xiaohe-yinxing-production.ps1
powershell -ExecutionPolicy Bypass -File scripts\build-xiaohe-yinxing-production.ps1 -VerifyOnly
```

The default output is `dictionaries/generated/xiaohe-yinxing-production/`. A different clean directory can be supplied with `-OutputDirectory`. The script verifies the three frozen audit hashes before invoking the Rust binary.

The binary also exposes the lower-level interface:

```text
yinxing-converter build --contract PATH --source-manifest PATH --command-policy PATH --sanitized-configuration PATH --source-root PATH --output DIR
yinxing-converter verify --bundle FILE
yinxing-converter compare --left DIR --right DIR
yinxing-converter --version
```

`compare` checks the complete relative file set, byte size, bytes, and SHA-256; it does not limit comparison to the archive.

## Safety and normalization

Preflight validates the frozen IDs, versions, hashes, source roles, category order, decisions, sizes, and paths. It rejects symlinks and reads all twelve source files and verifies all hashes before parsing the first line. Directory enumeration is not an input mechanism.

The parser accepts UTF-8 with optional BOM, LF, CRLF, and a missing final newline. Ordinary rows become `text<TAB>lowercase-code`, with one-to-four ASCII code letters and bounded Unicode-scalar text. The `ok-spelling` category is the sole length exception: it requires a lowercase `ok` prefix and exactly 6 or 8 ASCII letters. Configuration headers, comments, and empty lines are counted but not emitted. User `#删`, `#固`, and `#N` records are separated into the user overlay contract; `#直` is accepted only for `full-code-word`. Mixed or unsupported rules are rejected with stable reason codes.

`$cmd`, `$ddcmd`, URLs, credentials, network actions, external commands, platform-private actions, and all contract-deferred features are never executed. Rejection metadata stores only source file ID, physical line, stable reason, safe summary, and line digest.

Outputs are staged and then installed into the requested directory. Existing unmanaged output is refused. The converter never writes to the customer delivery roots and never copies `ime.android.ini` or the audit-only alternative exports.

## Determinism

No timestamp, host name, user name, absolute path, random UUID, or temporary path enters output. Ordering is based on the contract and ordered collections. JSON has stable key ordering, text uses UTF-8/LF/no BOM, binary integers are little-endian, and the archive uses a fixed record order.

For a reproducibility check, build into two new directories and run `compare`. The frozen result is documented in `docs/features/code-table/XIAOHE_YINXING_PRODUCTION_BUNDLE_FORMAT.md`.

## Stable converter error codes

| Reason | Exit | Meaning |
| --- | ---: | --- |
| `YX_CLI_INVALID` | 2 | Invalid command or flags |
| `YX_FROZEN_HASH_MISMATCH` | 10 | Audit artifact differs from the pinned SHA-256 |
| `YX_JSON_INVALID` | 11 | Required JSON cannot be parsed |
| `YX_CONTRACT_INVALID` | 11 | Contract is incomplete or disallows conversion |
| `YX_CONTRACT_VERSION_UNSUPPORTED` | 11 | Contract version is not 1.1.0 |
| `YX_IDENTITY_MISMATCH` | 12 | Scheme, bundle, data, auditor, or manifest identity differs |
| `YX_CATEGORY_INVALID` | 12 | Category list, role, order, or decision differs |
| `YX_PATH_INVALID` | 13 | Non-relative, escaping, or otherwise unapproved source path |
| `YX_SYMLINK_REJECTED` | 13 | A source path resolves through a symbolic link |
| `YX_SOURCE_MISSING` | 14 | Frozen source is absent |
| `YX_SOURCE_SIZE_MISMATCH` | 14 | Frozen source size differs |
| `YX_SOURCE_SHA256_MISMATCH` | 14 | Frozen source content differs |
| `YX_INVALID_UTF8` | 15 | Source is not valid UTF-8 |
| `YX_UNSAFE_CONTROL_CHARACTER` | 15 | Disallowed control/format character is present |
| `YX_INVALID_RECORD` | 15 | A strict record cannot be classified safely |
| `YX_SERIALIZATION_FAILED` | 16 | Deterministic output construction failed |
| `YX_INTEGRITY_FAILED` | 16 | Generated data failed its own round trip |
| `YX_OUTPUT_PATH_UNSAFE` | 17 | Output target or replacement state is unsafe |
| `YX_IO_ERROR` | 18 | Bounded filesystem operation failed |

Per-record rejections do not terminate a valid build. The frozen production data uses `REJECT_UNSUPPORTED_COMMAND` and `REJECT_NETWORK_ACTION`; those records appear only in safe action/report metadata.
