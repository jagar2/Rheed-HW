"""Small compatibility client for Console fields missing from the beta SDK.

The published beta CLI remains the source of authentication.  This module only
reads its existing credential entry long enough to call Console endpoints that
the current Python SDK does not yet expose (collection creation and asset
``record_type`` updates).  Tokens are never printed or written by this module.
"""

from __future__ import annotations

import base64
import json
import os
from pathlib import Path
import subprocess
import sys
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen


_GO_KEYRING_PREFIX = "go-keyring-base64:"


class DataeraiConsoleError(RuntimeError):
    """A sanitized Console API failure that never includes credentials."""


def _decode_credentials(raw: str) -> dict[str, Any]:
    value = raw.strip()
    if value.startswith(_GO_KEYRING_PREFIX):
        encoded = value.removeprefix(_GO_KEYRING_PREFIX)
        value = base64.b64decode(encoded).decode("utf-8")
    payload = json.loads(value)
    if not isinstance(payload, dict):
        raise ValueError("Dataerai credentials must be a JSON object")
    if not payload.get("access_token") or not payload.get("server_url"):
        raise ValueError("Dataerai credentials are missing access_token or server_url")
    return payload


def _credential_file_candidates() -> list[Path]:
    candidates: list[Path] = []
    if os.getenv("XDG_CONFIG_HOME"):
        candidates.append(Path(os.environ["XDG_CONFIG_HOME"]) / "dataerai" / "credentials")
    candidates.extend(
        [
            Path.home() / ".config" / "dataerai" / "credentials",
            Path.home() / "Library" / "Application Support" / "dataerai" / "credentials",
        ]
    )
    return candidates


def load_cli_credentials() -> dict[str, Any]:
    """Load the CLI credential entry without exposing its token to the caller UI."""

    env_value = os.getenv("DATAERAI_CREDENTIALS_JSON")
    if env_value:
        return _decode_credentials(env_value)

    if sys.platform == "darwin":
        completed = subprocess.run(
            [
                "security",
                "find-generic-password",
                "-s",
                "dataerai",
                "-a",
                "auth",
                "-w",
            ],
            check=False,
            capture_output=True,
            text=True,
        )
        if completed.returncode == 0 and completed.stdout.strip():
            return _decode_credentials(completed.stdout)

    for path in _credential_file_candidates():
        if path.is_file():
            return _decode_credentials(path.read_text(encoding="utf-8"))

    raise RuntimeError(
        "Could not read the Dataerai CLI credential store. Run `dataerai auth "
        "login`, or provide DATAERAI_CREDENTIALS_JSON in a headless environment."
    )


class DataeraiConsoleAPI:
    """Authenticated subset of the Console API needed by notebook capture."""

    def __init__(self) -> None:
        self._credentials = load_cli_credentials()

    def _reload_credentials(self) -> None:
        self._credentials = load_cli_credentials()

    def _request(
        self,
        method: str,
        path: str,
        *,
        payload: dict[str, Any] | None = None,
        query: dict[str, str] | None = None,
    ) -> Any:
        for attempt in range(2):
            server = str(self._credentials["server_url"]).rstrip("/")
            url = f"{server}{path}"
            if query:
                url = f"{url}?{urlencode(query)}"
            body = None
            headers = {
                "Authorization": f"Bearer {self._credentials['access_token']}",
                "Accept": "application/json",
            }
            if payload is not None:
                body = json.dumps(payload).encode("utf-8")
                headers["Content-Type"] = "application/json"
            request = Request(url, data=body, headers=headers, method=method)
            try:
                with urlopen(request, timeout=30) as response:
                    raw = response.read()
                return json.loads(raw) if raw else None
            except HTTPError as exc:
                if exc.code == 401 and attempt == 0:
                    self._reload_credentials()
                    continue
                detail = exc.read().decode("utf-8", errors="replace")[:1000]
                raise DataeraiConsoleError(
                    f"{method} {path}: HTTP {exc.code}: {detail}"
                ) from exc
            except URLError as exc:
                raise DataeraiConsoleError(f"{method} {path}: {exc.reason}") from exc
        raise AssertionError("unreachable")

    def find_owned_project(
        self,
        name: str,
        *,
        owner_id: str,
        description: str,
    ) -> dict[str, Any] | None:
        payload = self._request(
            "GET",
            "/api/projects/",
            query={"access_scope": "home", "q": name},
        )
        items = payload.get("results", []) if isinstance(payload, dict) else payload
        exact = [
            item
            for item in (items or [])
            if item.get("name") == name and str(item.get("owner_id")) == owner_id
        ]
        marked = [item for item in exact if item.get("description") == description]
        candidates = marked or exact
        return min(candidates, key=lambda item: item.get("created_at", "")) if candidates else None

    def create_collection(
        self,
        *,
        project_id: str,
        parent_id: str,
        title: str,
        description: str,
        tags: list[str],
    ) -> dict[str, Any]:
        return self._request(
            "POST",
            "/api/collections/",
            payload={
                "title": title,
                "description": description,
                "tags": tags,
                "type": ["notebook-run"],
                "owner_type": "project",
                "owner_id": project_id,
                "parent_id": parent_id,
            },
        )

    def set_record_type(self, asset_id: str, record_type: str) -> None:
        self._request(
            "PATCH",
            f"/api/assets/{asset_id}/",
            payload={"record_type": record_type},
        )


__all__ = ["DataeraiConsoleAPI", "DataeraiConsoleError", "load_cli_credentials"]
