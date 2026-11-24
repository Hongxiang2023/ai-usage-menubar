# AI Usage Menu Bar

A tiny macOS menu bar app that shows how much of your **Claude** and **Codex** quota is **left**, e.g. `Claude 92% · Codex 100%`.
Click it for weekly / 5-hour remaining and reset countdowns.

- Claude: weekly and 5-hour session limits (from the app's own claude.ai sign-in, or a Claude Code login as fallback)
- Codex: weekly limit (from your Codex CLI login). A week that hasn't started yet is shown as "window starts at first use"
- Includes usage from every device (web, phone, other computers), not just this Mac
- Auto-refresh interval is configurable (1 min / 5 min / 10 min / 30 min / 1 h, default 10 min)

## Requirements

- macOS 13+
- Xcode or the Command Line Tools (`xcode-select --install`) to build
- For Claude: a claude.ai account (sign in from the app's menu). For Codex: **Codex CLI** logged in (`codex login`). Either one alone also works.

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

## Sign in to claude.ai (recommended)

Click the menu bar item → **Sign in to claude.ai…** and log in in the window that opens. It closes by itself once the
session works. From then on Claude usage is read straight from claude.ai (the same numbers as *Settings → Usage*),
independent of Claude Code's login. The sign-in is kept in the app's own private WebKit store; the app never sees your password.

claude.ai will ask you to sign in again every so often: use **sign in again…** in the menu. **Sign out of claude.ai** clears the stored session.
If Google sign-in refuses the embedded window, use the email code login instead.

### Without signing in: Claude Code token (fallback)

If you don't sign in, the app uses the token of a logged-in Claude Code CLI (`claude`, then `/login`). That token expires after a few
hours and is only renewed when `claude` runs, and the login itself can end after days or weeks, so this path needs more care.
A background job can renew the token every 2 hours by sending one tiny prompt:

```bash
./keep-token-fresh.sh --install      # remove with: ./keep-token-fresh.sh --uninstall
```

## How it works

Claude usage is fetched inside a hidden WebKit view that holds the app's claude.ai session.
`collect.py` (Python standard library only) handles Codex and the Claude fallback: it reads the login tokens that Claude Code (macOS Keychain) and Codex
(`~/.codex/auth.json`) already store on your Mac, queries each service's usage endpoint over HTTPS, and prints JSON.
The Swift app just runs it on a timer and renders the result.

If the Claude query fails (offline, token expired), the app keeps showing the last known official value marked with `~`
(e.g. `Claude ~73%`), retries within a minute, and refreshes right after the Mac wakes from sleep.
With no earlier value to show, it falls back to local data:
Claude shows token counts from `~/.claude/projects`, Codex shows the last value from `~/.codex/sessions`.

## Privacy and caveats

- Tokens are read locally, sent only to `claude.ai` / `api.anthropic.com` / `chatgpt.com`, and are never stored, logged or shared.
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
