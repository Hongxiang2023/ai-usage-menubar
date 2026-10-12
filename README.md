# AI Usage Menu Bar

A tiny macOS menu bar app that shows how much of your **Claude** and **Codex** quota is **left**, e.g. `Claude 92% · Codex 100%`.
Click it for weekly / 5-hour remaining and reset countdowns.

- Claude: weekly and 5-hour session limits (from your Claude Code login)
- Codex: weekly limit (from your Codex CLI login). A week that hasn't started yet is shown as "window starts at first use"
- Includes usage from every device (web, phone, other computers), not just this Mac
- Auto-refresh interval is configurable (1 min / 5 min / 10 min / 30 min / 1 h, default 10 min)

## Requirements

- macOS 13+
- Xcode or the Command Line Tools (`xcode-select --install`) to build
- Logged in to **Claude Code** (`claude`, then `/login`) and/or **Codex CLI** (`codex login`) on this Mac. Either one alone also works.

## Download and install

```bash
git clone https://github.com/Hongxiang2023/ai-usage-menubar.git
cd ai-usage-menubar
./build.sh
open "AI Usage.app"
```

The percentage appears in the menu bar. To start it at login:
**System Settings → General → Login Items → +** and add `AI Usage.app`
(you can move it to `/Applications` first).

If macOS blocks the first launch, right-click the app → Open.

## Change the refresh interval

Click the menu bar item → **Refresh every** → pick a value. It is remembered across restarts.
**Refresh** (⌘R) updates immediately.

## Keep the Claude token fresh (recommended)

Claude Code's login token expires after a few hours and is only renewed when you use `claude`. If you haven't used it for a while,
the Claude number falls back to local token counts and the menu says `token expired`. To avoid that, install a background job
that sends one tiny prompt (cheapest model) every 2 hours so Claude Code renews its own token:

```bash
./keep-token-fresh.sh --install      # remove with: ./keep-token-fresh.sh --uninstall
```

## How it works

`collect.py` (Python standard library only) reads the login tokens that Claude Code (macOS Keychain) and Codex
(`~/.codex/auth.json`) already store on your Mac, queries each service's usage endpoint over HTTPS, and prints JSON.
The Swift app just runs it on a timer and renders the result.

If a query fails (offline, token expired), it falls back to local data:
Claude shows token counts from `~/.claude/projects`, Codex shows the last value from `~/.codex/sessions`.

## Privacy and caveats

- Tokens are read locally, sent only to `api.anthropic.com` / `chatgpt.com`, and are never stored, logged or shared.
- **These usage endpoints are undocumented internal APIs.** They can change or break at any time, and using them may not be
  endorsed by the providers. Use at your own risk.
- Tokens expire. If a number looks stale, run `claude` or `codex` once and they refresh themselves.
- On first run macOS may ask to allow access to the Keychain item "Claude Code-credentials". Choose "Allow".

## Behind a corporate proxy (TLS interception)

If your network re-signs HTTPS (Netskope, Zscaler, ...), point the app to your proxy's CA certificate in one of these ways:

```bash
# any one of:
export USAGE_CA_CERT=/path/to/ca.pem
export NODE_EXTRA_CA_CERTS=/path/to/ca.pem
mkdir -p ~/.config/ai-usage-menubar && echo /path/to/ca.pem > ~/.config/ai-usage-menubar/ca_cert_path
```

The config-file way is the one that also works when the app is started from Login Items.
The default Netskope certificate location is detected automatically. Normal certificate verification stays on.
Check with your IT policy before using personal accounts on a managed device.

## License

MIT
