#!/usr/bin/env python3
"""Collect privacy-safe GitHub repository metrics and build a static dashboard."""

from __future__ import annotations

import argparse
import json
import os
import shutil
import sys
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable, Mapping
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen


API_VERSION = "2026-03-10"
SCHEMA_VERSION = 1
USER_AGENT = "LogicLyrics-GitHub-Stats"
APP_ASSET_NAME = "LogicLyrics.app.zip"


class GitHubAPIError(RuntimeError):
    """A sanitized GitHub API failure that never contains credentials."""

    def __init__(self, status: int | None, message: str) -> None:
        super().__init__(message)
        self.status = status


@dataclass(frozen=True)
class APIResponse:
    payload: Any
    headers: Mapping[str, str]


class GitHubClient:
    """Small defensive adapter around the GitHub REST API."""

    def __init__(
        self,
        repository: str,
        token: str,
        *,
        timeout: float = 20,
        attempts: int = 3,
        opener: Callable[..., Any] = urlopen,
        sleeper: Callable[[float], None] = time.sleep,
    ) -> None:
        if repository.count("/") != 1:
            raise ValueError("repository must use the owner/name format")
        self.repository = repository
        self._token = token.strip()
        self._timeout = timeout
        self._attempts = max(1, attempts)
        self._opener = opener
        self._sleeper = sleeper

    def get(self, path: str, query: Mapping[str, str] | None = None) -> APIResponse:
        url = f"https://api.github.com{path}"
        if query:
            url = f"{url}?{urlencode(query)}"

        headers = {
            "Accept": "application/vnd.github+json",
            "User-Agent": USER_AGENT,
            "X-GitHub-Api-Version": API_VERSION,
        }
        if self._token:
            headers["Authorization"] = f"Bearer {self._token}"

        for attempt in range(self._attempts):
            try:
                request = Request(url, headers=headers, method="GET")
                with self._opener(request, timeout=self._timeout) as response:
                    payload = json.loads(response.read().decode("utf-8"))
                    return APIResponse(payload=payload, headers=dict(response.headers.items()))
            except HTTPError as error:
                retryable = error.code in {429, 500, 502, 503, 504}
                if retryable and attempt + 1 < self._attempts:
                    self._sleeper(self._retry_delay(error.headers, attempt))
                    continue
                raise GitHubAPIError(error.code, f"GitHub API returned HTTP {error.code}") from None
            except (URLError, TimeoutError, json.JSONDecodeError) as error:
                if attempt + 1 < self._attempts:
                    self._sleeper(float(2**attempt))
                    continue
                raise GitHubAPIError(None, f"GitHub API request failed: {type(error).__name__}") from None

        raise GitHubAPIError(None, "GitHub API request failed")

    def get_all(self, path: str) -> list[dict[str, Any]]:
        """Read a paginated array endpoint without silently truncating releases."""
        items: list[dict[str, Any]] = []
        page = 1
        while True:
            response = self.get(path, {"per_page": "100", "page": str(page)})
            if not isinstance(response.payload, list):
                raise GitHubAPIError(None, "GitHub API returned an unexpected collection")
            items.extend(item for item in response.payload if isinstance(item, dict))
            if len(response.payload) < 100:
                break
            page += 1
            if page > 100:
                raise GitHubAPIError(None, "GitHub API pagination exceeded the safety limit")
        return items

    @staticmethod
    def _retry_delay(headers: Mapping[str, str], attempt: int) -> float:
        retry_after = headers.get("Retry-After")
        if retry_after and retry_after.isdigit():
            return min(float(retry_after), 30)
        reset_at = headers.get("X-RateLimit-Reset")
        if reset_at and reset_at.isdigit():
            return min(max(float(reset_at) - time.time(), 1), 30)
        return float(2**attempt)


def _integer(value: Any) -> int:
    return value if isinstance(value, int) and not isinstance(value, bool) else 0


def _text(value: Any) -> str:
    return value if isinstance(value, str) else ""


def _safe_get(client: GitHubClient, path: str) -> tuple[Any | None, int | None]:
    try:
        return client.get(path).payload, None
    except GitHubAPIError as error:
        return None, error.status


def _release_summary(release: Mapping[str, Any]) -> dict[str, Any]:
    assets: list[dict[str, Any]] = []
    app_downloads = 0
    all_downloads = 0
    raw_assets = release.get("assets", [])
    if not isinstance(raw_assets, list):
        raw_assets = []

    for raw_asset in raw_assets:
        if not isinstance(raw_asset, dict):
            continue
        name = _text(raw_asset.get("name"))
        downloads = _integer(raw_asset.get("download_count"))
        all_downloads += downloads
        if name == APP_ASSET_NAME:
            app_downloads += downloads
        assets.append(
            {
                "name": name,
                "downloads": downloads,
                "size": _integer(raw_asset.get("size")),
                "url": _text(raw_asset.get("browser_download_url")),
            }
        )

    return {
        "tag": _text(release.get("tag_name")),
        "name": _text(release.get("name")),
        "publishedAt": _text(release.get("published_at")),
        "url": _text(release.get("html_url")),
        "prerelease": bool(release.get("prerelease", False)),
        "appDownloads": app_downloads,
        "allAssetDownloads": all_downloads,
        "assets": assets,
    }


def collect_metrics(client: GitHubClient, captured_at: datetime) -> dict[str, Any]:
    repository_path = f"/repos/{client.repository}"
    repository_response = client.get(repository_path).payload
    if not isinstance(repository_response, dict):
        raise GitHubAPIError(None, "GitHub API returned an unexpected repository")

    releases = [_release_summary(item) for item in client.get_all(f"{repository_path}/releases")]
    releases.sort(key=lambda item: item["publishedAt"], reverse=True)

    traffic_paths = {
        "views": f"{repository_path}/traffic/views",
        "clones": f"{repository_path}/traffic/clones",
        "referrers": f"{repository_path}/traffic/popular/referrers",
        "popularPaths": f"{repository_path}/traffic/popular/paths",
    }
    traffic_payloads: dict[str, Any] = {}
    traffic_statuses: list[int | None] = []
    for name, path in traffic_paths.items():
        payload, status = _safe_get(client, path)
        traffic_payloads[name] = payload
        if payload is None:
            traffic_statuses.append(status)

    traffic_available = isinstance(traffic_payloads["views"], dict) and isinstance(traffic_payloads["clones"], dict)
    traffic_complete = not traffic_statuses
    if traffic_complete:
        traffic_reason = "available"
    elif traffic_available:
        traffic_reason = "partially-available"
    elif any(status in {401, 403, 404} for status in traffic_statuses):
        traffic_reason = "permission-required"
    else:
        traffic_reason = "temporarily-unavailable"

    app_downloads = sum(item["appDownloads"] for item in releases)
    all_asset_downloads = sum(item["allAssetDownloads"] for item in releases)

    return {
        "schemaVersion": SCHEMA_VERSION,
        "capturedAt": captured_at.astimezone(timezone.utc).isoformat().replace("+00:00", "Z"),
        "repository": {
            "fullName": _text(repository_response.get("full_name")) or client.repository,
            "url": _text(repository_response.get("html_url")),
            "description": _text(repository_response.get("description")),
            "defaultBranch": _text(repository_response.get("default_branch")),
            "stars": _integer(repository_response.get("stargazers_count")),
            "forks": _integer(repository_response.get("forks_count")),
            "watchers": _integer(repository_response.get("subscribers_count")),
            "openIssues": _integer(repository_response.get("open_issues_count")),
        },
        "downloads": {
            "app": app_downloads,
            "allAssets": all_asset_downloads,
        },
        "releases": releases,
        "traffic": {
            "available": traffic_available,
            "complete": traffic_complete,
            "reason": traffic_reason,
            "views": traffic_payloads["views"] if isinstance(traffic_payloads["views"], dict) else {},
            "clones": traffic_payloads["clones"] if isinstance(traffic_payloads["clones"], dict) else {},
            "referrers": traffic_payloads["referrers"] if isinstance(traffic_payloads["referrers"], list) else [],
            "popularPaths": (
                traffic_payloads["popularPaths"] if isinstance(traffic_payloads["popularPaths"], list) else []
            ),
        },
    }


def empty_history() -> dict[str, Any]:
    return {"schemaVersion": SCHEMA_VERSION, "dailyTraffic": {}, "snapshots": []}


def load_history(path: Path | None) -> dict[str, Any]:
    if path is None or not path.is_file():
        return empty_history()
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return empty_history()
    if not isinstance(value, dict) or value.get("schemaVersion") != SCHEMA_VERSION:
        return empty_history()
    daily = value.get("dailyTraffic")
    snapshots = value.get("snapshots")
    return {
        "schemaVersion": SCHEMA_VERSION,
        "dailyTraffic": daily if isinstance(daily, dict) else {},
        "snapshots": snapshots if isinstance(snapshots, list) else [],
    }


def merge_history(history: Mapping[str, Any], metrics: Mapping[str, Any]) -> dict[str, Any]:
    daily = dict(history.get("dailyTraffic", {})) if isinstance(history.get("dailyTraffic"), dict) else {}
    traffic = metrics.get("traffic", {})
    if isinstance(traffic, dict) and traffic.get("available") is True:
        views = traffic.get("views", {}).get("views", []) if isinstance(traffic.get("views"), dict) else []
        clones = traffic.get("clones", {}).get("clones", []) if isinstance(traffic.get("clones"), dict) else []
        for item in views if isinstance(views, list) else []:
            if not isinstance(item, dict):
                continue
            day = _text(item.get("timestamp"))[:10]
            if day:
                current = dict(daily.get(day, {})) if isinstance(daily.get(day), dict) else {}
                current.update({"views": _integer(item.get("count")), "uniqueVisitors": _integer(item.get("uniques"))})
                daily[day] = current
        for item in clones if isinstance(clones, list) else []:
            if not isinstance(item, dict):
                continue
            day = _text(item.get("timestamp"))[:10]
            if day:
                current = dict(daily.get(day, {})) if isinstance(daily.get(day), dict) else {}
                current.update({"clones": _integer(item.get("count")), "uniqueCloners": _integer(item.get("uniques"))})
                daily[day] = current

    captured_at = _text(metrics.get("capturedAt"))
    snapshot_day = captured_at[:10]
    repository = metrics.get("repository", {}) if isinstance(metrics.get("repository"), dict) else {}
    downloads = metrics.get("downloads", {}) if isinstance(metrics.get("downloads"), dict) else {}
    releases = metrics.get("releases", []) if isinstance(metrics.get("releases"), list) else []
    new_snapshot = {
        "date": snapshot_day,
        "capturedAt": captured_at,
        "appDownloads": _integer(downloads.get("app")),
        "allAssetDownloads": _integer(downloads.get("allAssets")),
        "stars": _integer(repository.get("stars")),
        "forks": _integer(repository.get("forks")),
        "watchers": _integer(repository.get("watchers")),
        "openIssues": _integer(repository.get("openIssues")),
        "releases": {
            _text(item.get("tag")): _integer(item.get("appDownloads"))
            for item in releases
            if isinstance(item, dict) and _text(item.get("tag"))
        },
    }

    existing_snapshots = history.get("snapshots", []) if isinstance(history.get("snapshots"), list) else []
    snapshots_by_day = {
        _text(item.get("date")): dict(item)
        for item in existing_snapshots
        if isinstance(item, dict) and _text(item.get("date"))
    }
    if snapshot_day:
        snapshots_by_day[snapshot_day] = new_snapshot

    return {
        "schemaVersion": SCHEMA_VERSION,
        "dailyTraffic": {key: daily[key] for key in sorted(daily)},
        "snapshots": [snapshots_by_day[key] for key in sorted(snapshots_by_day)],
    }


def _atomic_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    os.replace(temporary, path)


def write_dashboard(output: Path, template: Path, metrics: dict[str, Any], history: dict[str, Any]) -> None:
    if output.exists():
        shutil.rmtree(output)
    shutil.copytree(template, output)
    (output / ".nojekyll").touch()
    dashboard = dict(metrics)
    dashboard["history"] = history
    _atomic_json(output / "data" / "dashboard.json", dashboard)
    _atomic_json(output / "data" / "history.json", history)


def parse_arguments(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository", default=os.environ.get("GITHUB_REPOSITORY", ""))
    parser.add_argument("--history", type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--now", help="ISO-8601 timestamp used by deterministic tests")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    arguments = parse_arguments(argv or sys.argv[1:])
    if not arguments.repository:
        print("error: --repository or GITHUB_REPOSITORY is required", file=sys.stderr)
        return 2

    token = os.environ.get("STATS_TOKEN") or os.environ.get("GITHUB_TOKEN", "")
    now = datetime.fromisoformat(arguments.now.replace("Z", "+00:00")) if arguments.now else datetime.now(timezone.utc)
    if now.tzinfo is None:
        now = now.replace(tzinfo=timezone.utc)

    template = Path(__file__).resolve().parent / "site"
    try:
        metrics = collect_metrics(GitHubClient(arguments.repository, token), now)
        history = merge_history(load_history(arguments.history), metrics)
        write_dashboard(arguments.output, template, metrics, history)
    except (GitHubAPIError, OSError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    reason = metrics["traffic"]["reason"]
    print(f"Dashboard generated for {arguments.repository}; traffic status: {reason}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
