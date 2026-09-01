#!/usr/bin/env python3
"""Build the audited Jieba -> full-pinyin lexicon layer.

This tool is deliberately offline.  It imports pypinyin from the pinned wheel
stored in dictionaries/source and never installs or downloads dependencies.
The output is deterministic UTF-8 TSV accepted by lexicon-builder.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
import tempfile
import zipfile
from collections import Counter
from pathlib import Path


SOURCE_ID = "jieba_0_42_1_pypinyin_0_55_0"
MAX_WORD_CHARACTERS = 16


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_inventory(path: Path) -> set[str]:
    marker = 'const VALID_SYLLABLES: &str = "'
    text = path.read_text(encoding="utf-8")
    start = text.find(marker)
    if start < 0:
        raise RuntimeError(f"cannot find pinyin inventory in {path}")
    start += len(marker)
    end = text.find('";', start)
    if end < 0:
        raise RuntimeError(f"cannot find pinyin inventory terminator in {path}")
    return set(text[start:end].split())


def load_existing_keys(paths: list[Path]) -> set[tuple[str, str]]:
    keys: set[tuple[str, str]] = set()
    for path in paths:
        with path.open("r", encoding="utf-8-sig", newline="") as source:
            for raw_line in source:
                line = raw_line.strip()
                if not line or line.startswith("#"):
                    continue
                fields = line.split("\t")
                if len(fields) >= 2:
                    keys.add((fields[0].strip(), " ".join(fields[1].lower().split())))
    return keys


def normalize_syllable(value: str) -> str:
    return value.strip().lower().replace("u:", "v").replace("ü", "v")


def is_common_cjk(word: str) -> bool:
    return bool(word) and all("\u4e00" <= character <= "\u9fff" for character in word)


def write_report(path: Path, report: dict[str, object]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
        newline="\n",
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--pypinyin-wheel", required=True, type=Path)
    parser.add_argument("--inventory", required=True, type=Path)
    parser.add_argument("--existing", action="append", default=[], type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--report", required=True, type=Path)
    args = parser.parse_args()

    required = [args.input, args.pypinyin_wheel, args.inventory, *args.existing]
    missing = [str(path) for path in required if not path.is_file()]
    if missing:
        raise RuntimeError("required input missing: " + ", ".join(missing))

    # pypinyin opens its bundled JSON through the regular filesystem API, so
    # unpack the pinned wheel into an isolated temporary directory instead of
    # importing the zip directly.  Keeping this object alive until main exits
    # also keeps lazy package reads safe and removes the directory afterwards.
    pypinyin_runtime = tempfile.TemporaryDirectory(prefix="quanpin-pypinyin-")
    with zipfile.ZipFile(args.pypinyin_wheel) as wheel:
        wheel.extractall(pypinyin_runtime.name)
    sys.path.insert(0, pypinyin_runtime.name)
    from pypinyin import Style, __version__, lazy_pinyin  # type: ignore

    if __version__ != "0.55.0":
        raise RuntimeError(f"unexpected pypinyin version: {__version__}")

    inventory = load_inventory(args.inventory)
    existing = load_existing_keys(args.existing)
    accepted: dict[tuple[str, str], tuple[int, int]] = {}
    rejected: Counter[str] = Counter()
    input_rows = 0

    with args.input.open("r", encoding="utf-8-sig", newline="") as source:
        for source_order, raw_line in enumerate(source, start=1):
            line = raw_line.strip()
            if not line:
                continue
            input_rows += 1
            fields = line.rsplit(maxsplit=2)
            if len(fields) != 3:
                rejected["field_count"] += 1
                continue
            word, raw_frequency, _part_of_speech = fields
            if not is_common_cjk(word):
                rejected["unsupported_characters"] += 1
                continue
            if len(word) > MAX_WORD_CHARACTERS:
                rejected["too_long"] += 1
                continue
            try:
                frequency = int(raw_frequency)
            except ValueError:
                rejected["invalid_frequency"] += 1
                continue
            if frequency < 0:
                rejected["invalid_frequency"] += 1
                continue

            syllables = [
                normalize_syllable(syllable)
                for syllable in lazy_pinyin(
                    word,
                    style=Style.NORMAL,
                    strict=True,
                    errors="default",
                )
            ]
            if len(syllables) != len(word):
                rejected["syllable_count"] += 1
                continue
            if any(syllable not in inventory for syllable in syllables):
                rejected["invalid_syllable"] += 1
                continue

            pinyin = " ".join(syllables)
            key = (word, pinyin)
            if key in existing:
                rejected["inherited_duplicate"] += 1
                continue
            # Match the established Rime conversion: its source weights are
            # from the same frequency scale and production stores weight + 1.
            normalized_frequency = min(1_000_000, max(1, frequency + 1))
            current = accepted.get(key)
            if current is None or normalized_frequency > current[0]:
                if current is not None:
                    rejected["source_duplicate"] += 1
                accepted[key] = (normalized_frequency, source_order)
            else:
                rejected["source_duplicate"] += 1

    rows = sorted(
        (
            pinyin,
            word,
            frequency,
            source_order,
        )
        for (word, pinyin), (frequency, source_order) in accepted.items()
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", encoding="utf-8", newline="\n") as output:
        for pinyin, word, frequency, _source_order in rows:
            output.write(f"{word}\t{pinyin}\t{frequency}\t{SOURCE_ID}\n")

    report: dict[str, object] = {
        "schemaVersion": "jieba-quanpin-import/1",
        "sourceId": SOURCE_ID,
        "jiebaVersion": "0.42.1",
        "pypinyinVersion": __version__,
        "inputSha256": sha256(args.input),
        "pypinyinWheelSha256": sha256(args.pypinyin_wheel),
        "inventorySha256": sha256(args.inventory),
        "outputSha256": sha256(args.output),
        "inputRows": input_rows,
        "acceptedRows": len(rows),
        "existingKeyCount": len(existing),
        "rejectedRows": sum(rejected.values()),
        "rejectedByReason": dict(sorted(rejected.items())),
        "maximumWordCharacters": MAX_WORD_CHARACTERS,
        "frequencyRule": "min(1000000, max(1, jieba_frequency + 1))",
        "ordering": "pinyin, word, source order",
    }
    write_report(args.report, report)
    print(
        "JIEBA_QUANPIN_IMPORT=PASS "
        f"input={input_rows} accepted={len(rows)} rejected={sum(rejected.values())} "
        f"sha256={report['outputSha256']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
