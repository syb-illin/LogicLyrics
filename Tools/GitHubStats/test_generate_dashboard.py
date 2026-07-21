#!/usr/bin/env python3

from __future__ import annotations

import json
import re
import struct
import tempfile
import unittest
from datetime import datetime, timezone
from html.parser import HTMLParser
from pathlib import Path
from typing import Any

from generate_dashboard import (
    APIResponse,
    GitHubAPIError,
    collect_metrics,
    empty_history,
    merge_history,
    write_dashboard,
)


class StaticHTMLAudit(HTMLParser):
    """Collect structural and local-asset references without external dependencies."""

    def __init__(self) -> None:
        super().__init__()
        self.ids: list[str] = []
        self.h1_count = 0
        self.images_without_alt: list[str] = []
        self.local_references: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        values = dict(attrs)
        identifier = values.get("id")
        if identifier:
            self.ids.append(identifier)
        if tag == "h1":
            self.h1_count += 1
        if tag == "img" and "alt" not in values:
            self.images_without_alt.append(values.get("src") or "unknown image")
        attribute = "href" if tag in {"a", "link"} else "src" if tag in {"img", "script"} else None
        reference = values.get(attribute) if attribute else None
        if reference and not reference.startswith(("https://", "http://", "mailto:", "#")):
            self.local_references.append(reference.split("#", 1)[0])


class FakeClient:
    repository = "syb-illin/LogicLyrics"

    def __init__(self, traffic_available: bool = True) -> None:
        self.traffic_available = traffic_available

    def get(self, path: str, query: dict[str, str] | None = None) -> APIResponse:
        del query
        if path == "/repos/syb-illin/LogicLyrics":
            return APIResponse(
                {
                    "full_name": self.repository,
                    "html_url": "https://github.com/syb-illin/LogicLyrics",
                    "description": "Native macOS project-notes studio",
                    "default_branch": "main",
                    "stargazers_count": 9,
                    "forks_count": 3,
                    "subscribers_count": 2,
                    "open_issues_count": 1,
                },
                {},
            )
        if "/traffic/" in path and not self.traffic_available:
            raise GitHubAPIError(403, "GitHub API returned HTTP 403")
        payloads: dict[str, Any] = {
            "/repos/syb-illin/LogicLyrics/traffic/views": {
                "count": 8,
                "uniques": 5,
                "views": [{"timestamp": "2026-07-20T00:00:00Z", "count": 8, "uniques": 5}],
            },
            "/repos/syb-illin/LogicLyrics/traffic/clones": {
                "count": 4,
                "uniques": 3,
                "clones": [{"timestamp": "2026-07-20T00:00:00Z", "count": 4, "uniques": 3}],
            },
            "/repos/syb-illin/LogicLyrics/traffic/popular/referrers": [
                {"referrer": "Google", "count": 6, "uniques": 4}
            ],
            "/repos/syb-illin/LogicLyrics/traffic/popular/paths": [
                {"path": "/syb-illin/LogicLyrics", "title": "LogicLyrics", "count": 7, "uniques": 5}
            ],
        }
        return APIResponse(payloads[path], {})

    def get_all(self, path: str) -> list[dict[str, Any]]:
        self.assert_release_path(path)
        return [
            {
                "tag_name": "v2.2.1",
                "name": "Logic Lyrics v2.2.1",
                "published_at": "2026-07-20T08:00:00Z",
                "html_url": "https://github.com/syb-illin/LogicLyrics/releases/tag/v2.2.1",
                "prerelease": False,
                "assets": [
                    {
                        "name": "LogicLyrics.app.zip",
                        "download_count": 12,
                        "size": 100,
                        "browser_download_url": "https://example.invalid/app",
                    },
                    {
                        "name": "LogicLyrics.app.zip.sha256",
                        "download_count": 7,
                        "size": 64,
                        "browser_download_url": "https://example.invalid/checksum",
                    },
                ],
            }
        ]

    def assert_release_path(self, path: str) -> None:
        if path != "/repos/syb-illin/LogicLyrics/releases":
            raise AssertionError(f"Unexpected collection path: {path}")


class DashboardTests(unittest.TestCase):
    now = datetime(2026, 7, 21, 9, 30, tzinfo=timezone.utc)
    repository_root = Path(__file__).resolve().parents[2]
    site_template = Path(__file__).resolve().parent / "site"

    def test_collects_app_downloads_without_counting_checksum_downloads(self) -> None:
        metrics = collect_metrics(FakeClient(), self.now)

        self.assertEqual(metrics["downloads"]["app"], 12)
        self.assertEqual(metrics["downloads"]["allAssets"], 19)
        self.assertTrue(metrics["traffic"]["available"])
        self.assertEqual(metrics["traffic"]["reason"], "available")

    def test_permission_failure_keeps_public_metrics_available(self) -> None:
        metrics = collect_metrics(FakeClient(traffic_available=False), self.now)

        self.assertEqual(metrics["downloads"]["app"], 12)
        self.assertFalse(metrics["traffic"]["available"])
        self.assertEqual(metrics["traffic"]["reason"], "permission-required")
        self.assertEqual(metrics["traffic"]["referrers"], [])

    def test_history_overwrites_same_day_and_preserves_previous_days(self) -> None:
        history = empty_history()
        history["dailyTraffic"] = {"2026-07-19": {"views": 2, "uniqueVisitors": 1}}
        history["snapshots"] = [{"date": "2026-07-21", "appDownloads": 1}]
        metrics = collect_metrics(FakeClient(), self.now)

        merged = merge_history(history, metrics)
        merged_again = merge_history(merged, metrics)

        self.assertEqual(merged_again["dailyTraffic"]["2026-07-19"]["views"], 2)
        self.assertEqual(merged_again["dailyTraffic"]["2026-07-20"]["clones"], 4)
        self.assertEqual(len(merged_again["snapshots"]), 1)
        self.assertEqual(merged_again["snapshots"][0]["appDownloads"], 12)

    def test_writes_complete_static_site_and_valid_json(self) -> None:
        metrics = collect_metrics(FakeClient(), self.now)
        history = merge_history(empty_history(), metrics)
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "dashboard"
            write_dashboard(output, self.site_template, metrics, history)

            self.assertTrue((output / ".nojekyll").is_file())
            self.assertTrue((output / "index.html").is_file())
            self.assertTrue((output / "stats" / "index.html").is_file())
            self.assertTrue((output / "assets" / "social-preview.png").is_file())
            dashboard = json.loads((output / "stats" / "data" / "dashboard.json").read_text(encoding="utf-8"))
            self.assertEqual(dashboard["repository"]["fullName"], "syb-illin/LogicLyrics")
            self.assertEqual(dashboard["history"]["schemaVersion"], 1)

    def test_generated_site_has_valid_local_references_and_basic_accessibility_structure(self) -> None:
        metrics = collect_metrics(FakeClient(), self.now)
        history = merge_history(empty_history(), metrics)

        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "dashboard"
            write_dashboard(output, self.site_template, metrics, history)

            for html_path in sorted(output.rglob("*.html")):
                audit = StaticHTMLAudit()
                audit.feed(html_path.read_text(encoding="utf-8"))
                self.assertEqual(audit.h1_count, 1, f"{html_path} must contain exactly one h1")
                self.assertEqual(len(audit.ids), len(set(audit.ids)), f"duplicate HTML id in {html_path}")
                self.assertEqual(audit.images_without_alt, [], f"missing image alt text in {html_path}")
                for reference in audit.local_references:
                    target = html_path.parent / reference
                    self.assertTrue(target.exists(), f"broken local reference {reference} in {html_path}")

    def test_workflow_checks_existing_dashboard_script_and_preserves_legacy_history(self) -> None:
        workflow = self.repository_root / ".github" / "workflows" / "github-stats.yml"
        source = workflow.read_text(encoding="utf-8")
        checked_paths = re.findall(r"node\s+--check\s+([^\s]+)", source)
        generated_json_match = re.search(
            r'DASHBOARD_JSON="\$\{RUNNER_TEMP\}/generated-dashboard/([^\"]+)"',
            source,
        )

        self.assertTrue(checked_paths, "workflow must syntax-check its JavaScript")
        for relative_path in checked_paths:
            self.assertTrue((self.repository_root / relative_path).is_file(), f"missing CI target: {relative_path}")
        self.assertIsNotNone(generated_json_match, "workflow must declare its generated dashboard JSON path")
        metrics = collect_metrics(FakeClient(), self.now)
        history = merge_history(empty_history(), metrics)
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "dashboard"
            write_dashboard(output, self.site_template, metrics, history)
            generated_json = output / generated_json_match.group(1)  # type: ignore[union-attr]
            self.assertTrue(generated_json.is_file(), f"workflow reads a missing generated file: {generated_json}")
        self.assertIn("stats/data/history.json", source)
        self.assertIn("data/history.json", source, "legacy dashboard history must survive the path migration")

    def test_product_metadata_and_social_preview_are_release_ready(self) -> None:
        product_page = (self.site_template / "index.html").read_text(encoding="utf-8")
        preview = self.site_template / "assets" / "social-preview.png"

        self.assertIn("releases/latest/download/LogicLyrics.app.zip", product_page)
        self.assertIn('property="og:image"', product_page)
        self.assertTrue(preview.is_file())
        with preview.open("rb") as stream:
            header = stream.read(24)
        self.assertEqual(header[:8], b"\x89PNG\r\n\x1a\n")
        width, height = struct.unpack(">II", header[16:24])
        self.assertEqual((width, height), (1280, 640))


if __name__ == "__main__":
    unittest.main()
