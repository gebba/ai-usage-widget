#!/usr/bin/env python3
"""Fetch ChatGPT/Codex usage balance using local Codex-compatible auth.

Supported auth sources, in order:
  1. --auth-file / AI_USAGE_AUTH_FILE, if provided
  2. ~/.codex/auth.json  (official Codex CLI)
  3. ~/.pi/agent/auth.json (Pi coding agent)

Sanitized output:
  ~/.local/state/ai-usage-widget/state.json
  ~/.local/state/ai-usage-widget/state-cache.qml
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import socket
import tempfile
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

ENDPOINT = "https://chatgpt.com/backend-api/wham/usage"
CODEX_AUTH = Path.home() / ".codex" / "auth.json"
PI_AUTH = Path.home() / ".pi" / "agent" / "auth.json"
DEFAULT_STATE = Path.home() / ".local" / "state" / "ai-usage-widget" / "state.json"
DEFAULT_QML_CACHE = Path.home() / ".local" / "state" / "ai-usage-widget" / "state-cache.qml"


class UsageWidgetError(Exception):
    """User-facing helper error."""


def utc_now_iso() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z")


def normalize_auth(data: dict[str, Any], path: Path) -> dict[str, Any]:
    """Normalize known Codex/Pi auth file shapes into access/accountId/source."""
    tokens = data.get("tokens")
    if isinstance(tokens, dict) and tokens.get("access_token"):
        return {
            "access": tokens["access_token"],
            "refresh": tokens.get("refresh_token"),
            "accountId": tokens.get("account_id"),
            "source": "codex-cli",
            "sourcePath": str(path),
        }

    pi_auth = data.get("openai-codex")
    if isinstance(pi_auth, dict) and pi_auth.get("access"):
        return {
            "access": pi_auth["access"],
            "refresh": pi_auth.get("refresh"),
            "accountId": pi_auth.get("accountId"),
            "source": "pi-auth",
            "sourcePath": str(path),
        }

    if data.get("access"):
        return {
            "access": data["access"],
            "refresh": data.get("refresh"),
            "accountId": data.get("accountId") or data.get("account_id"),
            "source": "custom-auth",
            "sourcePath": str(path),
        }

    raise UsageWidgetError(
        f"Unsupported auth file format: {path}. Expected Codex CLI auth (~/.codex/auth.json) "
        "or Pi openai-codex auth (~/.pi/agent/auth.json)."
    )


def load_auth_file(path: Path) -> dict[str, Any]:
    try:
        with path.open("r", encoding="utf-8") as f:
            return normalize_auth(json.load(f), path)
    except json.JSONDecodeError as exc:
        raise UsageWidgetError(f"Auth file is not valid JSON: {path} ({exc})") from exc
    except PermissionError as exc:
        raise UsageWidgetError(f"Cannot read auth file due to permissions: {path}") from exc


def candidate_auth_paths(explicit_path: str | None = None) -> list[Path]:
    if explicit_path:
        return [Path(explicit_path).expanduser()]
    env_path = os.environ.get("AI_USAGE_AUTH_FILE")
    if env_path:
        return [Path(env_path).expanduser()]
    return [CODEX_AUTH, PI_AUTH]


def load_first_available_auth(explicit_path: str | None = None) -> dict[str, Any]:
    errors: list[str] = []
    paths = candidate_auth_paths(explicit_path)
    for path in paths:
        if not path.exists():
            errors.append(f"missing {path}")
            continue
        try:
            return load_auth_file(path)
        except UsageWidgetError as exc:
            errors.append(str(exc))
        except Exception as exc:
            errors.append(f"{path}: {type(exc).__name__}: {exc}")

    tried = "\n- " + "\n- ".join(str(path) for path in paths)
    details = "\n\nDetails:\n- " + "\n- ".join(errors) if errors else ""
    raise UsageWidgetError(
        "No usable Codex auth found.\n\n"
        "Run `codex login` to create ~/.codex/auth.json, or authenticate Pi so "
        "~/.pi/agent/auth.json contains an openai-codex entry.\n\n"
        f"Tried:{tried}{details}"
    )


def fetch_usage(auth: dict[str, Any], timeout: int = 20) -> dict[str, Any]:
    req = urllib.request.Request(ENDPOINT)
    req.add_header("Authorization", f"Bearer {auth['access']}")
    req.add_header("User-Agent", "codex-cli")
    if auth.get("accountId"):
        req.add_header("ChatGPT-Account-Id", auth["accountId"])

    try:
        with urllib.request.urlopen(req, timeout=timeout) as response:
            try:
                return json.loads(response.read().decode("utf-8"))
            except json.JSONDecodeError as exc:
                raise UsageWidgetError("ChatGPT returned a non-JSON response. The internal usage endpoint may have changed.") from exc
    except urllib.error.HTTPError as exc:
        detail = exc.read(500).decode("utf-8", "replace").strip()
        suffix = f" Response: {detail}" if detail else ""
        if exc.code == 401:
            raise UsageWidgetError("ChatGPT rejected the saved auth token (HTTP 401). Run `codex login` or re-authenticate Pi, then refresh again." + suffix) from exc
        if exc.code == 403:
            raise UsageWidgetError("ChatGPT denied access to the usage endpoint (HTTP 403). Check that this account has Codex access, then re-authenticate." + suffix) from exc
        if exc.code == 429:
            raise UsageWidgetError("ChatGPT rate-limited usage refreshes (HTTP 429). Wait a while or disable auto-refresh temporarily." + suffix) from exc
        if 500 <= exc.code <= 599:
            raise UsageWidgetError(f"ChatGPT usage service is temporarily unavailable (HTTP {exc.code}). Try again later." + suffix) from exc
        raise UsageWidgetError(f"ChatGPT usage request failed (HTTP {exc.code})." + suffix) from exc
    except urllib.error.URLError as exc:
        reason = getattr(exc, "reason", exc)
        raise UsageWidgetError(f"Network error while contacting ChatGPT usage endpoint: {reason}") from exc
    except TimeoutError as exc:
        raise UsageWidgetError("Timed out while contacting ChatGPT usage endpoint. Check your network and try again.") from exc
    except socket.timeout as exc:
        raise UsageWidgetError("Timed out while contacting ChatGPT usage endpoint. Check your network and try again.") from exc


def window_label(seconds: int | None) -> str:
    if seconds == 18_000:
        return "5 hours"
    if seconds == 604_800:
        return "weekly"
    if not seconds:
        return "unknown"
    if seconds % 86400 == 0:
        days = seconds // 86400
        return f"{days} day" + ("s" if days != 1 else "")
    if seconds % 3600 == 0:
        hours = seconds // 3600
        return f"{hours} hour" + ("s" if hours != 1 else "")
    return f"{seconds}s"


def iso_from_epoch(value: Any) -> str | None:
    if value in (None, ""):
        return None
    try:
        return dt.datetime.fromtimestamp(int(value), dt.timezone.utc).isoformat().replace("+00:00", "Z")
    except Exception:
        return None


def concise_limit_label(label: str) -> str:
    parts = label.split("-Codex-")
    if len(parts) == 2 and parts[1]:
        return "Codex " + parts[1].replace("-", " ")
    return label.replace("GPT-", "").replace("-", " ")


def normalize_window(source: dict[str, Any], *, name: str, scope: str, model: str | None = None) -> dict[str, Any]:
    used = source.get("used_percent")
    try:
        used_num = float(used)
    except Exception:
        used_num = 0.0
    remaining = max(0.0, min(100.0, 100.0 - used_num))
    seconds = source.get("limit_window_seconds")
    try:
        seconds_int = int(seconds) if seconds is not None else None
    except Exception:
        seconds_int = None

    return {
        "name": name,
        "scope": scope,
        "model": model,
        "windowSeconds": seconds_int,
        "windowLabel": window_label(seconds_int),
        "usedPercent": round(used_num, 2),
        "remainingPercent": round(remaining, 2),
        "resetAt": iso_from_epoch(source.get("reset_at")),
        "resetAfterSeconds": source.get("reset_after_seconds"),
        "allowed": source.get("allowed"),
        "limitReached": source.get("limit_reached"),
    }


def normalize(raw: dict[str, Any], auth_source: str) -> dict[str, Any]:
    main = raw.get("rate_limit")
    if not isinstance(main, dict):
        raise UsageWidgetError("ChatGPT usage response did not include rate_limit data. The internal endpoint may have changed.")

    limits: list[dict[str, Any]] = []
    if main.get("primary_window"):
        limits.append(normalize_window(main["primary_window"], name="Codex · 5-hour", scope="shared"))
    if main.get("secondary_window"):
        limits.append(normalize_window(main["secondary_window"], name="Codex · Weekly", scope="shared"))

    for item in raw.get("additional_rate_limits") or []:
        label = item.get("limit_name") or item.get("metered_feature") or "Additional limit"
        short_label = concise_limit_label(label)
        rate = item.get("rate_limit") or {}
        if rate.get("primary_window"):
            limits.append(normalize_window(rate["primary_window"], name=f"{short_label} · 5-hour", scope="additional", model=label))
        if rate.get("secondary_window"):
            limits.append(normalize_window(rate["secondary_window"], name=f"{short_label} · Weekly", scope="additional", model=label))

    if not limits:
        raise UsageWidgetError("ChatGPT usage response did not contain any recognizable usage windows. The internal endpoint may have changed.")

    lowest = min((x["remainingPercent"] for x in limits), default=None)
    return {
        "schemaVersion": 1,
        "source": f"{auth_source} wham/usage",
        "updatedAt": utc_now_iso(),
        "status": "ok",
        "planType": raw.get("plan_type"),
        "lowestRemainingPercent": lowest,
        "limits": limits,
        "credits": {
            "hasCredits": (raw.get("credits") or {}).get("has_credits"),
            "unlimited": (raw.get("credits") or {}).get("unlimited"),
            "balance": (raw.get("credits") or {}).get("balance"),
        },
    }


def error_state(message: str) -> dict[str, Any]:
    return {
        "schemaVersion": 1,
        "source": "wham/usage",
        "updatedAt": utc_now_iso(),
        "status": "error",
        "error": message,
        "limits": [],
        "lowestRemainingPercent": None,
    }


def atomic_write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(prefix=path.name + ".", dir=str(path.parent))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(content)
        os.chmod(tmp_name, 0o600)
        os.replace(tmp_name, path)
    finally:
        try:
            os.unlink(tmp_name)
        except FileNotFoundError:
            pass


def atomic_write_json(path: Path, data: dict[str, Any]) -> None:
    atomic_write(path, json.dumps(data, indent=2, sort_keys=True) + "\n")


def atomic_write_qml_cache(path: Path, data: dict[str, Any]) -> None:
    payload = json.dumps(data, indent=2, sort_keys=True)
    atomic_write(path, "import QtQuick\nQtObject {\n    readonly property var state: " + payload + "\n}\n")


def run_once(args: argparse.Namespace) -> int:
    try:
        auth = load_first_available_auth(args.auth_file)
        raw = fetch_usage(auth, timeout=args.timeout)
        state = normalize(raw, auth_source=auth.get("source", "unknown-auth"))
    except UsageWidgetError as exc:
        state = error_state(str(exc))
    except Exception as exc:
        state = error_state(f"Unexpected error: {type(exc).__name__}: {exc}")

    if args.print:
        print(json.dumps(state, indent=2, sort_keys=True))
    atomic_write_json(Path(args.state_file).expanduser(), state)
    atomic_write_qml_cache(Path(args.qml_cache_file).expanduser(), state)
    return 0 if state.get("status") == "ok" else 1


def main() -> int:
    parser = argparse.ArgumentParser(description="Fetch Codex usage into a sanitized local JSON cache")
    parser.add_argument("--auth-file", default=None, help="Explicit auth JSON path. Defaults to AI_USAGE_AUTH_FILE, ~/.codex/auth.json, then ~/.pi/agent/auth.json")
    parser.add_argument("--state-file", default=str(DEFAULT_STATE), help="Output state JSON path")
    parser.add_argument("--qml-cache-file", default=str(DEFAULT_QML_CACHE), help="Output QML cache path")
    parser.add_argument("--timeout", type=int, default=20)
    parser.add_argument("--print", action="store_true", help="Print sanitized state JSON")
    parser.add_argument("--watch", action="store_true", help="Keep refreshing until interrupted")
    parser.add_argument("--interval", type=int, default=300, help="Watch refresh interval in seconds")
    args = parser.parse_args()

    if not args.watch:
        return run_once(args)

    exit_code = 0
    while True:
        exit_code = run_once(args)
        time.sleep(max(60, args.interval))
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
