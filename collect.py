#!/usr/bin/env python3
"""Collect Claude + Codex usage on this Mac and print it as JSON."""
import glob, json, os, sys, time
from datetime import datetime, timezone, timedelta

HOME = os.path.expanduser("~")

def parse_ts(s):
    return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()

def claude():
    now = time.time()
    seen, events = set(), []
    for f in glob.glob(f"{HOME}/.claude/projects/**/*.jsonl", recursive=True):
        if now - os.path.getmtime(f) > 8 * 86400:
            continue
        try:
            for line in open(f, errors="ignore"):
                if '"usage"' not in line:
                    continue
                try: d = json.loads(line)
                except Exception: continue
                m = d.get("message") or {}
                u = m.get("usage")
                if d.get("type") != "assistant" or not u or "timestamp" not in d:
                    continue
                key = (m.get("id"), d.get("requestId"))
                if key in seen: continue
                seen.add(key)
                tok = (u.get("input_tokens", 0) + u.get("output_tokens", 0)
                       + u.get("cache_creation_input_tokens", 0))
                events.append((parse_ts(d["timestamp"]), tok))
        except OSError:
            pass
    events.sort()
    # 5-hour block: starts at the hour of the first message after a >=5h gap
    block_start = None
    for ts, _ in events:
        if block_start is None or ts >= block_start + 5 * 3600:
            block_start = ts - ts % 3600
    in_block = block_start is not None and now < block_start + 5 * 3600
    block_tok = sum(t for ts, t in events if in_block and ts >= block_start)
    day0 = datetime.now().replace(hour=0, minute=0, second=0, microsecond=0).timestamp()
    return {
        "block_tokens": block_tok,
        "block_resets_at": block_start + 5 * 3600 if in_block else None,
        "today_tokens": sum(t for ts, t in events if ts >= day0),
        "week_tokens": sum(t for ts, t in events if ts >= now - 7 * 86400),
    }

def ca_bundle():
    """Optional extra CA for networks that intercept TLS (corporate proxies)."""
    cands = [os.environ.get("USAGE_CA_CERT"), os.environ.get("NODE_EXTRA_CA_CERTS")]
    try:
        cands.append(open(f"{HOME}/.config/ai-usage-menubar/ca_cert_path").read().strip())
    except OSError:
        pass
    cands.append("/Library/Application Support/Netskope/STAgent/data/nscacert.pem")
    return next((c for c in cands if c and os.path.exists(c)), None)

def claude_official():
    import subprocess
    try:
        raw = subprocess.run(["security", "find-generic-password", "-s", "Claude Code-credentials", "-w"],
                             capture_output=True, text=True, timeout=10).stdout
        tok = json.loads(raw)["claudeAiOauth"]["accessToken"]
        ca = ca_bundle()
        cfg = 'url = "https://api.anthropic.com/api/oauth/usage"\n' \
              'header = "Authorization: Bearer %s"\n' \
              'header = "anthropic-beta: oauth-2025-04-20"\n' \
              'header = "User-Agent: claude-code/2.1.109"\n' % tok
        cmd = ["/usr/bin/curl", "-s", "--max-time", "15", "-K", "-"]
        if ca: cmd += ["--cacert", ca]
        j = json.loads(subprocess.run(cmd, input=cfg, capture_output=True, text=True, timeout=20).stdout)
        t = lambda w: w and {"used_percent": w["utilization"], "resets_at": parse_ts(w["resets_at"])}
        return {"five_hour": t(j.get("five_hour")), "seven_day": t(j.get("seven_day"))}
    except Exception:
        return None

def codex_official():
    import subprocess
    try:
        t = json.load(open(f"{HOME}/.codex/auth.json"))["tokens"]
        ca = ca_bundle()
        cfg = 'url = "https://chatgpt.com/backend-api/wham/usage"\n' \
              'header = "Authorization: Bearer %s"\n' \
              'header = "chatgpt-account-id: %s"\n' \
              'header = "User-Agent: codex-cli"\n' % (t["access_token"], t["account_id"])
        cmd = ["/usr/bin/curl", "-s", "--max-time", "15", "-K", "-"]
        if ca: cmd += ["--cacert", ca]
        j = json.loads(subprocess.run(cmd, input=cfg, capture_output=True, text=True, timeout=20).stdout)
        rl = j["rate_limit"]
        win = lambda w: w and {"used_percent": w["used_percent"],
                               "window_minutes": w["limit_window_seconds"] / 60,
                               "resets_at": w["reset_at"]}
        return {"primary": win(rl.get("primary_window")), "secondary": win(rl.get("secondary_window")),
                "plan": j.get("plan_type")}
    except Exception:
        return None

def codex():
    files = sorted(glob.glob(f"{HOME}/.codex/sessions/**/*.jsonl", recursive=True),
                   key=os.path.getmtime, reverse=True)[:10]
    for f in files:
        last = None
        for line in open(f, errors="ignore"):
            if '"rate_limits"' in line:
                last = line
        if last:
            try:
                p = json.loads(last)["payload"]
                rl = p["rate_limits"]
            except Exception:
                continue
            win = lambda w: w and {"used_percent": w["used_percent"],
                                   "window_minutes": w["window_minutes"],
                                   "resets_at": w["resets_at"]}
            return {"primary": win(rl.get("primary")), "secondary": win(rl.get("secondary")),
                    "plan": rl.get("plan_type")}
    return None

data = {"updated_at": int(time.time()), "claude": {**claude(), "official": claude_official()}, "codex": codex_official() or codex()}
print(json.dumps(data))
