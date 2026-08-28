# Xiaohe Yinxing Production Bundle Format

## Current production identity

The formal Xiaohe Yinxing data container uses `HSPYXP01` format 1.0 and is shipped as the main HAP raw resource. The 2026-08-26 direct-display build has this frozen identity:

| Field | Value |
| --- | --- |
| Scheme | `xiaohe-yinxing` |
| Bundle | `xiaohe-yinxing-production` |
| Data version | `source-receipt-1` |
| Converter | `yinxing-converter/1.0.0` |
| Categories | 12 internal / 10 customer-visible switches |
| Accepted records | 162,731 |
| Bundle bytes | 56,184,164 |
| Bundle SHA-256 | `f7bbfdf4473e9317d618c9ad02a792b47ff2dab8bfd74fa23416579e01f9bdc7` |
| Content SHA-256 | `83fa186fb43acc045fac88ba74ea3db5d761bf8c7c901499c4b517d953eef2e3` |

The raw resource installer uses a v5 installed filename and receipt, so a previously verified customer-category resource cannot mask this build after an application upgrade.

## Categories

The manifest freezes category order, entry counts and defaults:

| order | id | display | entries | default |
| ---: | --- | --- | ---: | --- |
| 0 | `core` | 首选 | 68,568 | on, required |
| 1 | `category-secondary` | 分类 | 1,690 | on |
| 2 | `quick-symbol` | 快符 | 16 | on |
| 3 | `one-key-secondary` | 一简次选 | 26 | on |
| 4 | `two-key-secondary` | 二简次选 | 66 | off |
| 5 | `out-of-table-character` | 表外字 | 362 | on |
| 6 | `full-code-word` | 全码词 | 464 | off |
| 7 | `symbol` | 符号 | 623 | on |
| 8 | `symbol-group` | 符号组 | 707 | on |
| 9 | `rare-character` | 生僻字 | 498 | off |
| 10 | `full-code-character` | 全码字 | 1,654 | off |
| 11 | `ok-spelling` | ok拼字 | 88,020 | on |

The settings UI merges `category-secondary` plus `out-of-table-character` into the customer-visible “分类” switch and merges `symbol` plus `symbol-group` into “符号”. “直通” is a property of a record in its owning category, and “用户” is the separate user lexicon layer; neither creates a system switch.

## Fixed and direct records

An authoritative category source accepts:

```text
普通词条<TAB>编码
置顶词条<TAB>编码#固
直通词条<TAB>编码#直
上屏内容,候选提示<TAB>完整编码#直
```

`#固` establishes protected top ordering while its owning category is enabled. `#直` reserves the precise longer-code hint and remains hidden from backtick universal-key lookup. The optional ASCII comma splits clean commit text from candidate-only presentation text; the UI appends the untyped code suffix. For example, `给予,给ʲⁱ̌予<TAB>gwyu#直` displays `给ʲⁱ̌予u` after `gwy`, while selection or the complete `gwyu` commits `给予`. Both rule types disappear atomically when their owning category is disabled.

`#直` controls candidate visibility only; it grants no execution authority. `$cmd/$ddcmd`, network access, external programs, arbitrary file operations and platform-private commands remain quarantined by the action policy.

## ok spelling records

`ok-spelling` is built from `小鹤音形/0.2.拼字.txt`. Rows use `text<TAB>code`; codes are normalized to lowercase and must start with `ok` with a total length of exactly 6 or 8 ASCII letters. The runtime checks this category for a longer `ok...` continuation before applying the ordinary four-code top-screen boundary.

## Archive layout

All integers are unsigned little-endian. Strings and machine text are UTF-8. The 128-byte header contains magic, header length, versions, archive/category counts, record-section length, the frozen source-manifest SHA-256, and SHA-256 of all record bytes. Reserved bytes must be zero.

The archive contains 17 records: `manifest.json`, 12 `categories/*.lex` files, `user-rules.txt`, `action-metadata.json`, `trace-index.jsonl`, and `build-report.json`. Each record includes a relative path, typed flags, stable order, byte length, payload SHA-256, and payload bytes. Duplicate paths, missing or undeclared files, path traversal, checksum mismatch, trailing bytes, and inconsistent flags are rejected.

Each category file is a checksummed `HSPLEX01` 1.1 binary retaining the category ID, contract order, source SHA-256 and zero-based `source_order`. Runtime query order is exact-before-prefix, category order, then `source_order`, with stable text deduplication.

`user-rules.txt` uses the strict embedded grammar `commit<TAB>code-and-marker<TAB>display-or-empty<TAB>category-id`; the runtime filters these records by their owning category before merging the independent external user lexicon. `action-metadata.json` has `execution_allowed=false`. Rejected actions retain only safe source identity, line number, syntax class, disposition, reason and digest; original sensitive action lines are not copied.

## Integrity and build

Integrity is checked at four levels:

1. Frozen audit/contract identity and every source size/hash before parsing.
2. SHA-256 for every output record.
3. `bundle_content_sha256` over deterministically ordered typed outputs.
4. Archive SHA-256 followed by nested lexicon and user-rule round trips.

Build and verify from the repository root:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\build-xiaohe-yinxing-production.ps1
powershell -ExecutionPolicy Bypass -File scripts\build-xiaohe-yinxing-production.ps1 -VerifyOnly
```

The converter omits timestamps, host/user names, absolute paths, randomness and temporary paths from generated content. `compare` validates the full relative output set byte-for-byte for reproducibility.
