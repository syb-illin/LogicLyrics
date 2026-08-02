#!/usr/bin/env python3
"""Fail the build when app-wide English/French localization drifts.

The checker deliberately enforces explicit ``L10n`` calls for static SwiftUI
copy. That makes every user-facing string searchable and lets the build prove
that both supported catalogs contain the exact same non-empty keys.
"""

from __future__ import annotations

import argparse
from collections import Counter
from pathlib import Path
import re
import sys


STRING_ENTRY = re.compile(
    r'^\s*"((?:\\.|[^"\\])*)"\s*=\s*"((?:\\.|[^"\\])*)"\s*;\s*$',
    re.MULTILINE,
)
LOCALIZED_CALL = re.compile(
    r'\bL10n\.(?:text|format)\(\s*"((?:\\.|[^"\\])*)"'
)
DIRECT_UI_LITERAL = re.compile(
    r'(?:\b(?:Text|Button|Toggle|Label|Picker|Section|LabeledContent|CommandMenu|Window)'
    r'|\.(?:help|accessibilityLabel|accessibilityHint|navigationTitle|alert|confirmationDialog))'
    r'\s*\(\s*"((?:\\.|[^"\\])*)"',
    re.MULTILINE,
)


def parse_catalog(path: Path) -> tuple[dict[str, str], list[str]]:
    source = path.read_text(encoding="utf-8")
    entries = STRING_ENTRY.findall(source)
    counts = Counter(key for key, _ in entries)
    duplicates = sorted(key for key, count in counts.items() if count > 1)
    return dict(entries), duplicates


def source_localization_issues(source_root: Path, catalog_keys: set[str]) -> list[str]:
    issues: list[str] = []
    for path in sorted(source_root.rglob("*.swift")):
        source = path.read_text(encoding="utf-8")
        relative = path.relative_to(source_root.parent)
        for match in LOCALIZED_CALL.finditer(source):
            key = match.group(1)
            if key not in catalog_keys:
                line = source.count("\n", 0, match.start()) + 1
                issues.append(f"{relative}:{line}: missing localization key: {key!r}")
        for match in DIRECT_UI_LITERAL.finditer(source):
            literal = match.group(1)
            # A value containing only interpolation is data, not UI copy.
            # Interpolated labels that still contain words must be localized.
            without_interpolation = re.sub(r"\\\([^)]*\)", "", literal)
            if r"\(" in literal and not re.search(r"[A-Za-z]", without_interpolation):
                continue
            line = source.count("\n", 0, match.start()) + 1
            issues.append(
                f"{relative}:{line}: static UI copy must use L10n.text/format: {literal!r}"
            )
    return issues


def validate(source_root: Path, catalogs: list[Path]) -> list[str]:
    issues: list[str] = []
    parsed: dict[Path, dict[str, str]] = {}
    for path in catalogs:
        entries, duplicates = parse_catalog(path)
        parsed[path] = entries
        issues.extend(f"{path}: duplicate key: {key!r}" for key in duplicates)
        issues.extend(
            f"{path}: empty translation: {key!r}"
            for key, value in entries.items()
            if not value.strip()
        )

    baseline_path = catalogs[0]
    baseline = set(parsed[baseline_path])
    for path in catalogs[1:]:
        keys = set(parsed[path])
        issues.extend(
            f"{path}: key missing from this catalog: {key!r}"
            for key in sorted(baseline - keys)
        )
        issues.extend(
            f"{baseline_path}: key missing from this catalog: {key!r}"
            for key in sorted(keys - baseline)
        )

    issues.extend(source_localization_issues(source_root, baseline))
    return issues


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("source_root", type=Path)
    parser.add_argument("catalogs", nargs="+", type=Path)
    arguments = parser.parse_args()

    issues = validate(arguments.source_root, arguments.catalogs)
    if issues:
        print("Localization validation failed:", file=sys.stderr)
        for issue in issues:
            print(f"- {issue}", file=sys.stderr)
        return 1
    print(
        f"Localization validation passed for {len(arguments.catalogs)} catalogs "
        f"and all Swift sources in {arguments.source_root}."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
