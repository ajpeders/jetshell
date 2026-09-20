#!/usr/bin/python3
"""Collect DeepSeek, Ollama, and MiniMax usage from opencode's database.

One JSON record per agent lands in ~/.local/state/omarchy/agents/usage/, the
same directory the omarchy.agents panel (and this plugin's fork of it) watches.
The panel never learns how the numbers are made: a record that appears there is
an agent, whoever wrote it. Agent definitions live in agents.json alongside
this script, so adding an agent is a config entry, not a code change.

Local stats come from opencode's message table, which records per-message
provider, model, and token usage. DeepSeek's documented balance endpoint adds
the current prepaid credit ledger; Ollama is local, and MiniMax Coding Plan
does not expose a documented account-usage endpoint.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sqlite3
import sys
import tempfile
import urllib.error
import urllib.request
from datetime import datetime, timedelta, timezone
from decimal import Decimal, InvalidOperation
from pathlib import Path
from typing import Any


DEEPSEEK_BALANCE_URL = "https://api.deepseek.com/user/balance"


def state_usage_dir() -> Path:
  root = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local" / "state"))
  return root / "omarchy" / "agents" / "usage"


def cache_root() -> Path:
  root = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "omarchy" / "agent-usage"
  root.mkdir(parents=True, exist_ok=True)
  return root


def opencode_db() -> Path:
  data_home = os.environ.get("XDG_DATA_HOME") or str(Path.home() / ".local" / "share")
  return Path(data_home) / "opencode" / "opencode.db"


def opencode_auth() -> Path:
  data_home = os.environ.get("XDG_DATA_HOME") or str(Path.home() / ".local" / "share")
  return Path(data_home) / "opencode" / "auth.json"


def number(value: Any) -> int:
  try:
    n = float(value or 0)
    return round(n) if n == n else 0
  except (TypeError, ValueError):
    return 0


def empty_bucket() -> dict[str, int]:
  return {
    "inputTokens": 0,
    "outputTokens": 0,
    "cacheReadInputTokens": 0,
    "cacheCreationInputTokens": 0,
  }


def recent_date_strings() -> list[str]:
  today = datetime.now().date()
  return [(today - timedelta(days=offset)).strftime("%Y-%m-%d") for offset in range(6, -1, -1)]


def load_agents(config_path: Path) -> list[dict[str, str]]:
  try:
    data = json.loads(config_path.read_text(encoding="utf-8"))
  except Exception:
    return []
  agents = []
  for entry in data.get("agents", []):
    provider_id = str(entry.get("providerId") or "").strip()
    agent_id = str(entry.get("id") or "").strip()
    name = str(entry.get("name") or agent_id)
    tier_label = str(entry.get("tierLabel") or "")
    if provider_id and agent_id:
      agents.append({"providerId": provider_id, "id": agent_id, "name": name, "tierLabel": tier_label})
  return agents


def provider_api_key(provider_id: str, env_name: str) -> str:
  value = str(os.environ.get(env_name) or "").strip()
  if value:
    return value
  try:
    auth = json.loads(opencode_auth().read_text(encoding="utf-8"))
    entry = auth.get(provider_id) or {}
    return str(entry.get("key") or "").strip()
  except Exception:
    return ""


def money_number(value: Any) -> float:
  try:
    amount = Decimal(str(value or "0"))
    return float(max(Decimal("0"), amount))
  except (InvalidOperation, TypeError, ValueError):
    return 0.0


def deepseek_balance() -> tuple[dict[str, Any] | None, bool | None]:
  key = provider_api_key("deepseek", "DEEPSEEK_API_KEY")
  if not key:
    return None, None

  request = urllib.request.Request(
    DEEPSEEK_BALANCE_URL,
    headers={"Authorization": f"Bearer {key}", "Accept": "application/json"},
  )
  try:
    with urllib.request.urlopen(request, timeout=10) as response:
      payload = json.load(response)
  except (OSError, urllib.error.URLError, urllib.error.HTTPError, ValueError):
    return None, None

  infos = payload.get("balance_infos") if isinstance(payload, dict) else None
  if not isinstance(infos, list) or not infos:
    return None, bool(payload.get("is_available")) if isinstance(payload, dict) else None

  info = next((item for item in infos if str((item or {}).get("currency") or "").upper() == "USD"), infos[0])
  if not isinstance(info, dict):
    return None, bool(payload.get("is_available"))
  return {
    "remaining": money_number(info.get("total_balance")),
    "funded": 0,
    "spent": 0,
    "granted": money_number(info.get("granted_balance")),
    "toppedUp": money_number(info.get("topped_up_balance")),
    "currency": str(info.get("currency") or "USD").upper(),
    "estimated": False,
  }, bool(payload.get("is_available"))


def enrich_account_details(
  records: dict[str, dict[str, Any]],
  agents: list[dict[str, str]],
  selected_ids: set[str],
) -> None:
  for agent in agents:
    agent_id = agent["id"]
    if agent_id in selected_ids and agent_id in records:
      records[agent_id]["tierLabel"] = agent.get("tierLabel", "")

  if "deepseek" not in selected_ids or "deepseek" not in records:
    return
  balance, available = deepseek_balance()
  if balance is not None:
    records["deepseek"]["balance"] = balance
  if available is True:
    records["deepseek"]["usageStatusText"] = ""
    records["deepseek"]["authHelpText"] = ""
  elif available is False:
    records["deepseek"]["usageStatusText"] = "No API credit"
    records["deepseek"]["authHelpText"] = "Top up DeepSeek API credits at platform.deepseek.com."


def new_accumulator() -> dict[str, Any]:
  return {
    "recent": {day: 0 for day in recent_date_strings()},
    "sessions": set(),
    "active_days": set(),
    "today_sessions": set(),
    "today_tokens_by_model": {},
    "model_usage": {},
    "prompts": 0,
    "today_prompts": 0,
    "today_total_tokens": 0,
  }


def scan_opencode(db: Path, agents: list[dict[str, str]]) -> dict[str, dict[str, Any]]:
  """Scan opencode.db once and return per-agent-id accumulators."""
  provider_to_id = {agent["providerId"]: agent["id"] for agent in agents}
  accs = {agent["id"]: new_accumulator() for agent in agents}
  today = datetime.now().strftime("%Y-%m-%d")

  if not db.is_file():
    return accs

  try:
    # Read-only: opencode may be writing right now.
    conn = sqlite3.connect(db.resolve().as_uri() + "?mode=ro", uri=True, timeout=2)
  except sqlite3.Error:
    return accs
  try:
    conn.execute("PRAGMA query_only = ON")
    for session_id, raw in conn.execute("SELECT session_id, data FROM message"):
      # One malformed row must not abort the scan, so every shape assumption
      # lives inside the try.
      try:
        entry = json.loads(raw)
        # Exact match: opencode provider ids are free-form, and a custom
        # "deepseek-proxy" gateway is not this subscription.
        if not isinstance(entry, dict) or entry.get("role") != "assistant":
          continue
        provider_id = str(entry.get("providerID") or "")
        if provider_id not in provider_to_id:
          continue
        tokens = entry.get("tokens") or {}
        cache = tokens.get("cache") or {}
        input_tokens = number(tokens.get("input"))
        # opencode keeps thinking tokens out of output; both are generated.
        output_tokens = number(tokens.get("output")) + number(tokens.get("reasoning"))
        cache_read = number(cache.get("read"))
        cache_write = number(cache.get("write"))
        total = input_tokens + output_tokens + cache_read + cache_write
        if total <= 0:
          continue

        created = number((entry.get("time") or {}).get("created"))
        day = datetime.fromtimestamp(created / 1000).strftime("%Y-%m-%d") if created > 0 else today
        model = str(entry.get("modelID") or "unknown").rstrip("/").split("/")[-1]
      except Exception:
        continue

      acc = accs[provider_to_id[provider_id]]
      session_key = "opencode:" + str(session_id)
      acc["sessions"].add(session_key)
      acc["active_days"].add(day)
      acc["prompts"] += 1

      if day in acc["recent"]:
        acc["recent"][day] += total
      if day == today:
        acc["today_prompts"] += 1
        acc["today_sessions"].add(session_key)
        acc["today_total_tokens"] += total
        acc["today_tokens_by_model"][model] = acc["today_tokens_by_model"].get(model, 0) + total

      bucket = acc["model_usage"].setdefault(model, empty_bucket())
      bucket["inputTokens"] += input_tokens
      bucket["outputTokens"] += output_tokens
      bucket["cacheReadInputTokens"] += cache_read
      bucket["cacheCreationInputTokens"] += cache_write
  except sqlite3.Error:
    return accs
  finally:
    conn.close()
  return accs


def build_record(agent: dict[str, str], acc: dict[str, Any]) -> dict[str, Any]:
  return {
    "schemaVersion": 1,
    "id": agent["id"],
    "name": agent["name"],
    "updatedAt": datetime.now(timezone.utc).isoformat(),
    "ready": True,
    "hasLocalStats": True,
    "scope": "device",
    "hasPromptStats": True,
    "tierLabel": agent.get("tierLabel", ""),
    "usageStatusText": "",
    "authHelpText": "",
    "limits": [],
    "todayPrompts": acc["today_prompts"],
    "todaySessions": len(acc["today_sessions"]),
    "todayTotalTokens": acc["today_total_tokens"],
    "todayTokensByModel": acc["today_tokens_by_model"],
    "recentDays": [{"date": day, "messageCount": acc["recent"][day]} for day in recent_date_strings()],
    "totalPrompts": acc["prompts"],
    "totalSessions": len(acc["sessions"]),
    "activeDays": len(acc["active_days"]),
    "activeDates": sorted(acc["active_days"]),
    "modelUsage": acc["model_usage"],
  }


def write_json(path: Path, payload: dict[str, Any]) -> None:
  # A temp name unique to this writer, not derived from the target: the stock
  # update command backgrounds one collector per agent while the panel
  # refreshes on its own, and a shared temp path would race.
  handle_fd, tmp_name = tempfile.mkstemp(dir=path.parent, prefix=path.name + ".", suffix=".tmp")
  tmp = Path(tmp_name)
  try:
    with os.fdopen(handle_fd, "w", encoding="utf-8") as handle:
      handle.write(json.dumps(payload, separators=(",", ":"), sort_keys=True) + "\n")
    tmp.chmod(0o644)
    tmp.replace(path)
  except BaseException:
    tmp.unlink(missing_ok=True)
    raise


def read_cache(path: Path) -> dict[str, Any] | None:
  try:
    return json.loads(path.read_text(encoding="utf-8"))
  except Exception:
    return None


def read_existing_records(usage_dir: Path, agents: list[dict[str, str]]) -> dict[str, dict[str, Any]]:
  records: dict[str, dict[str, Any]] = {}
  for agent in agents:
    record = read_cache(usage_dir / f"{agent['id']}.json")
    if isinstance(record, dict):
      records[agent["id"]] = record
  return records


def write_cache(path: Path, payload: dict[str, Any]) -> None:
  try:
    write_json(path, payload)
  except Exception:
    pass  # a cache miss just costs a rescan next time


def collect_records(db: Path, agents: list[dict[str, str]], signature: str, cache_file: Path) -> dict[str, dict[str, Any]]:
  accs = scan_opencode(db, agents)
  records: dict[str, dict[str, Any]] = {}
  for agent in agents:
    acc = accs.get(agent["id"])
    if acc and acc["prompts"] > 0:
      records[agent["id"]] = build_record(agent, acc)
  write_cache(cache_file, {"signature": signature, "records": records})
  return records


def main() -> int:
  parser = argparse.ArgumentParser(description="Collect jetshell agent usage from opencode")
  parser.add_argument("--force", action="store_true", help="bypass the scan cache")
  parser.add_argument("--limits-only", action="store_true", help="refresh only provider account details")
  parser.add_argument("--except", dest="exclude", action="append", default=[], help="skip an agent id")
  parser.add_argument("agents", nargs="*", help="only emit these agent ids")
  args = parser.parse_args()

  agents = load_agents(Path(__file__).parent / "agents.json")
  if not agents:
    return 0

  excluded = set(args.exclude)
  only = set(args.agents)
  selected_ids = {
    agent["id"] for agent in agents
    if agent["id"] not in excluded and (not only or agent["id"] in only)
  }
  usage_dir = state_usage_dir()
  usage_dir.mkdir(parents=True, exist_ok=True)

  if args.limits_only:
    records = read_existing_records(usage_dir, agents)
    enrich_account_details(records, agents, selected_ids)
    for agent_id in selected_ids:
      if agent_id in records:
        write_json(usage_dir / f"{agent_id}.json", records[agent_id])
    return 0

  db = opencode_db()
  try:
    st = db.stat()
    signature = f"{st.st_mtime_ns}:{st.st_size}"
  except OSError:
    return 0

  cache_file = cache_root() / f"jetshell-{hashlib.sha1(str(db).encode('utf-8')).hexdigest()[:16]}.json"

  if args.force:
    records = collect_records(db, agents, signature, cache_file)
  else:
    cached = read_cache(cache_file)
    if cached and cached.get("signature") == signature and cached.get("records") is not None:
      records = cached["records"]
    else:
      records = collect_records(db, agents, signature, cache_file)

  enrich_account_details(records, agents, selected_ids)

  for agent in agents:
    agent_id = agent["id"]
    if agent_id not in selected_ids:
      continue
    record = records.get(agent_id)
    if record:
      write_json(usage_dir / f"{agent_id}.json", record)
  return 0


if __name__ == "__main__":
  sys.exit(main())
