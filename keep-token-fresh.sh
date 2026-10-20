#!/bin/bash
# Run Claude Code with a tiny prompt so it refreshes its OAuth token (used by the usage menu bar app).
# Install a launchd job that runs this every 2 hours:  ./keep-token-fresh.sh --install
# Remove it:                                           ./keep-token-fresh.sh --uninstall
LABEL=com.ai-usage-menubar.keepfresh
PLIST=~/Library/LaunchAgents/$LABEL.plist
DIR="$(cd "$(dirname "$0")" && pwd)"
# launchd cannot read ~/Desktop, ~/Documents, ~/Downloads, so run a copy from ~/.config
INSTALLED=~/.config/ai-usage-menubar/keep-token-fresh.sh

if [ "$1" = "--install" ]; then
  CLAUDE="$(command -v claude)" || { echo "claude not found in PATH"; exit 1; }
  CA="${USAGE_CA_CERT:-${NODE_EXTRA_CA_CERTS:-}}"
  [ -z "$CA" ] && [ -f ~/.config/ai-usage-menubar/ca_cert_path ] && CA="$(cat ~/.config/ai-usage-menubar/ca_cert_path)"
  [ -z "$CA" ] && [ -f "/Library/Application Support/Netskope/STAgent/data/nscacert.pem" ] && CA="/Library/Application Support/Netskope/STAgent/data/nscacert.pem"
  mkdir -p ~/.config/ai-usage-menubar && cp "$DIR/keep-token-fresh.sh" "$INSTALLED" && chmod +x "$INSTALLED"
  cat > "$PLIST" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>$LABEL</string>
<key>ProgramArguments</key><array><string>/bin/bash</string><string>$INSTALLED</string></array>
<key>StartInterval</key><integer>7200</integer>
<key>RunAtLoad</key><true/>
<key>EnvironmentVariables</key><dict>
<key>HOME</key><string>$HOME</string>
<key>USER</key><string>$USER</string>
<key>LOGNAME</key><string>$USER</string>
<key>PATH</key><string>$(dirname "$CLAUDE"):/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin</string>
<key>NODE_EXTRA_CA_CERTS</key><string>$CA</string>
</dict>
</dict></plist>
PL
  launchctl unload "$PLIST" 2>/dev/null; launchctl load "$PLIST" && echo "Installed: refreshes the Claude token every 2 hours."
  exit 0
fi
if [ "$1" = "--uninstall" ]; then
  launchctl unload "$PLIST" 2>/dev/null; rm -f "$PLIST" "$INSTALLED"; echo "Removed."; exit 0
fi

[ -z "$NODE_EXTRA_CA_CERTS" ] && unset NODE_EXTRA_CA_CERTS
LOG=~/.config/ai-usage-menubar/keepfresh.log
{ echo "== $(date) =="; claude -p "ok" --model haiku 2>&1 | head -c 300; echo "rc=${PIPESTATUS[0]}"; } >> "$LOG" 2>&1
tail -n 200 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
