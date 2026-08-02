#!/usr/bin/env python3
"""Enforce line coverage for explicitly selected critical Swift sources."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("report", type=Path)
    parser.add_argument("sources", nargs="+")
    parser.add_argument("--minimum", type=float, default=100.0)
    return parser.parse_args()


def normalized(path: str) -> str:
    return path.replace("\\", "/")


def main() -> int:
    arguments = parse_arguments()
    if not 0 <= arguments.minimum <= 100:
        raise SystemExit("--minimum must be between 0 and 100")

    payload = json.loads(arguments.report.read_text(encoding="utf-8"))
    files = payload.get("data", [{}])[0].get("files", [])
    failures: list[str] = []

    print("Critical Swift line coverage:")
    for source in arguments.sources:
        suffix = normalized(source)
        matches = [item for item in files if normalized(item.get("filename", "")).endswith(suffix)]
        if len(matches) != 1:
            failures.append(f"{source}: expected one coverage record, found {len(matches)}")
            continue

        summary = matches[0].get("summary", {})
        metrics: list[str] = []
        for metric in ("lines", "regions"):
            values = summary.get(metric, {})
            count = int(values.get("count", 0))
            covered = int(values.get("covered", 0))
            percent = 100.0 if count == 0 else covered * 100.0 / count
            metrics.append(f"{covered}/{count} {metric} ({percent:.2f}%)")
            if percent + 1e-9 < arguments.minimum:
                failures.append(
                    f"{source} {metric}: {percent:.2f}% is below the required "
                    f"{arguments.minimum:.2f}%"
                )
        print(f"  {source}: " + "; ".join(metrics))

    if failures:
        print("Coverage gate failed:", file=sys.stderr)
        for failure in failures:
            print(f"  - {failure}", file=sys.stderr)
        return 1

    print(f"Coverage gate passed (minimum {arguments.minimum:.2f}%).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
