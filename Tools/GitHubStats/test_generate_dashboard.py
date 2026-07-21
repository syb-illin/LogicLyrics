#!/usr/bin/env python3

from __future__ import annotations

import json
import tempfile
import unittest
from datetime import datetime, timezone
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
        template = Path(__file__).resolve().parent / "site"

        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "dashboard"
            write_dashboard(output, template, metrics, history)

            self.assertTrue((output / ".nojekyll").is_file())
            self.assertTrue((output / "index.html").is_file())
            dashboard = json.loads((output / "data" / "dashboard.json").read_text(encoding="utf-8"))
            self.assertEqual(dashboard["repository"]["fullName"], "syb-illin/LogicLyrics")
            self.assertEqual(dashboard["history"]["schemaVersion"], 1)


if __name__ == "__main__":
    unittest.main()
