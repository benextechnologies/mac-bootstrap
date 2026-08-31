#!/bin/zsh
# ------------------------------------------------------------------------------
# Benex Mac bootstrap — USER part.   Runs once per user, as the employee.
#   • from benex-bootstrap.pkg: a LaunchAgent runs it at the first login
#   • from the day-1 one-liner: bootstrap.sh runs it right after root.sh
#
#   brew: git, nvm, gh, dockutil + casks Chrome, Microsoft 365, 1Password, Teams,
#         Docker, Cursor, VS Code, cmux, iTerm2, CopyClip
#   Dock curation, ~/Projects, Node LTS + Claude Code, the ccstatusline status
#   line, git identity, SSH key, Chrome default
#
# Nothing here aborts on a single failure: every install is tried on its own and
# the result lands in the summary printed at the end. Safe to re-run.
# ------------------------------------------------------------------------------
set -u
LOG="$HOME/Library/Logs/benex-user-bootstrap.log"
mkdir -p "$HOME/Library/Logs"
exec > >(tee -a "$LOG") 2>&1
echo "== $(date) user bootstrap for $USER"

# The employee's work email is NEVER derived from the Mac's account name — people
# name their own local account ("samash"), so a derived address is simply wrong.
# benex-day1 asks for it once and saves it here; until then we do without.
EMAIL_FILE="$HOME/.benex/work-email"
WORK_EMAIL=""
[ -f "$EMAIL_FILE" ] && WORK_EMAIL=$(tr -d ' \t\r\n' < "$EMAIL_FILE" 2>/dev/null || true)

# Can this run answer an admin-password prompt? The LaunchAgent that provisions a
# packaged Mac sets BENEX_UNATTENDED=1; failing that, having no terminal to prompt
# on means the same thing. Anything needing a password is deferred, not attempted,
# because a run that can't finish would otherwise fail forever at every login.
UNATTENDED=0
if [ "${BENEX_UNATTENDED:-0}" = "1" ]; then
  UNATTENDED=1
elif ! : </dev/tty 2>/dev/null; then
  # /dev/tty, not [ -t 0 ]: the documented `curl … | zsh` one-liner has a pipe on
  # stdin but a perfectly good terminal to ask for a password on, exactly as the
  # sudo in bootstrap.sh relies on.
  UNATTENDED=1
fi
[ "$UNATTENDED" -eq 1 ] && echo "== unattended run: anything needing an admin password will be deferred to benex-day1"

# Casks whose installer is a .pkg, so Homebrew has to authenticate as an admin.
ADMIN_AUTH_CASKS=(microsoft-office)
needs_admin_auth() { case " ${ADMIN_AUTH_CASKS[*]} " in *" $1 "*) return 0 ;; esac; return 1; }

DEFER_FILE="$HOME/.benex/deferred-installs"
typeset -a DONE FAILED DEFERRED
note_ok()   { DONE+=("$1"); undefer "$1"; }
note_fail() { FAILED+=("$1"); echo "WARN: $1 — failed"; }
# Deferred is NOT failed: it's waiting for a person, and it must not hold the
# bootstrap open. benex-day1 drains this list on day 1.
note_defer() {
  DEFERRED+=("$1")
  mkdir -p "$HOME/.benex"
  grep -qxF "$1" "$DEFER_FILE" 2>/dev/null || print -r -- "$1" >> "$DEFER_FILE"
  echo "DEFERRED: $1 needs an admin password — benex-day1 will install it"
}
undefer() {
  [ -f "$DEFER_FILE" ] || return 0
  grep -qxF "$1" "$DEFER_FILE" 2>/dev/null || return 0
  # No `&&` on the mv: when this item is the only line, grep -v matches nothing
  # and exits 1 with empty output — which is exactly the "list is now empty" case,
  # not a failure. Gating the mv on it would leave the item deferred for ever.
  grep -vxF "$1" "$DEFER_FILE" > "$DEFER_FILE.tmp" 2>/dev/null
  mv "$DEFER_FILE.tmp" "$DEFER_FILE" 2>/dev/null || rm -f "$DEFER_FILE.tmp"
  [ -s "$DEFER_FILE" ] || rm -f "$DEFER_FILE"
}

[ -f "$HOME/.benex-bootstrapped" ] && { echo "already bootstrapped ($HOME/.benex-bootstrapped) — nothing to do"; exit 0; }

# ---- 1. Wait for Homebrew (root.sh installs it) --------------------------------
for _ in {1..60}; do
  [ -x /opt/homebrew/bin/brew ] && break
  sleep 30
done
if [ ! -x /opt/homebrew/bin/brew ]; then
  echo "ERROR: Homebrew not present after 30 min — aborting (re-run bootstrap.sh; the package path retries at next login)"
  exit 1
fi
eval "$(/opt/homebrew/bin/brew shellenv)"
export HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ANALYTICS=1

# ---- 2. CLI tools + terminal apps -------------------------------------------
# One item per line to add/remove a tool for every future Mac. Each is installed
# on its own so a broken one costs us that one thing, not the rest of the Mac.
install_formula() {
  if brew list --formula "$1" >/dev/null 2>&1; then note_ok "$1"; return 0; fi
  if brew install "$1"; then note_ok "$1"; else note_fail "$1"; fi
}
# Microsoft 365 is also pushed as an Apple Business Managed App. When it arrives
# that way Homebrew has no record of it, and `brew install --cask` refuses over an
# app it didn't put there — so check the disk, not just Homebrew's receipts.
cask_already_on_disk() {
  case "$1" in
    microsoft-office) [ -d "/Applications/Microsoft Word.app" ] || [ -d "/Applications/Microsoft Outlook.app" ] ;;
    *) return 1 ;;
  esac
}
install_cask() {
  if brew list --cask "$1" >/dev/null 2>&1; then note_ok "$1"; return 0; fi
  if cask_already_on_disk "$1"; then
    echo "$1: already on disk (Managed App) — leaving it alone"
    note_ok "$1"
    return 0
  fi
  if [ "$UNATTENDED" -eq 1 ] && needs_admin_auth "$1"; then note_defer "$1"; return 0; fi
  if brew install --cask "$1"; then note_ok "$1"; else note_fail "$1"; fi
}

for formula in git nvm gh dockutil; do
  install_formula "$formula"
done
# GUI apps — one line to add/remove an app for every future Mac. Each app self-updates after install.
# Browser and email lead the GUI apps: day 1 can't start until the employee can read
# the mailbox their GitHub / 1Password invites were sent to. Dev tools after them.
#
# microsoft-office is the whole Microsoft 365 suite in one cask — Word, Excel,
# PowerPoint, Outlook, OneNote (and OneDrive) — not just the mail client. It's a
# ~3GB .pkg, so it needs an admin password and macOS 14+; if either is missing it
# fails on its own and shows up in the summary without costing the other apps.
for cask in google-chrome microsoft-office 1password microsoft-teams \
            docker cursor visual-studio-code cmux iterm2 copyclip; do
  install_cask "$cask"
done

# Benex wallpaper — set it for this user right away (best-effort: the MDM
# wallpaper profile is the enforcement; this just makes it instant on day 1).
osascript -e 'tell application "System Events" to set picture of every desktop to "/Library/Desktop Pictures/Benex.png"' || true

# ---- 3. Dock — work apps in, consumer apps out --------------------------------
# Every change is --no-restart; the Dock is restarted once, at the end. Apps are
# only added if they actually made it onto the disk, so a failed cask above can't
# break this step, and anything already in the Dock is left alone.
DOCK_NOW=""
command -v dockutil >/dev/null 2>&1 && DOCK_NOW=$(dockutil --list 2>/dev/null || true)
if [ -n "$DOCK_NOW" ]; then
  DOCK_TOUCHED=0
  # Is this .app already in the Dock? Match the path, not the label — the Dock's
  # label is the app's display name, which isn't always the filename (iTerm.app
  # shows up as "iTerm2"). --list gives paths as file:// URLs, so try both the
  # plain and the percent-encoded spelling.
  in_dock() { print -r -- "$DOCK_NOW" | grep -qF "$1" || print -r -- "$DOCK_NOW" | grep -qF "${1// /%20}"; }

  # Out: consumer apps a work Mac doesn't need. Finder, Safari, Mail and System
  # Settings stay. Removing something that isn't there just fails harmlessly.
  for app in Messages Maps Photos TV Music News Freeform FaceTime; do
    dockutil --remove "$app" --no-restart >/dev/null 2>&1 && DOCK_TOUCHED=1
  done

  # In: the tools people actually open, in the order they'll reach for them.
  # Only what's really on disk, so a cask that failed above can't break the Dock.
  # (An app that only turns up on a later retry is appended, not slotted back
  # into this order — the order holds for the normal case where all six install.)
  DOCK_FAIL=0
  for app in \
      "/Applications/Google Chrome.app" \
      "/Applications/Microsoft Outlook.app" \
      "/Applications/Microsoft Teams.app" \
      "/Applications/1Password.app" \
      "/Applications/iTerm.app" \
      "/Applications/Cursor.app"; do
    [ -d "$app" ] || continue
    in_dock "$app" && continue
    if dockutil --add "$app" --no-restart >/dev/null 2>&1; then
      DOCK_TOUCHED=1
    else
      DOCK_FAIL=1
      echo "WARN: could not add ${app:t:r} to the Dock"
    fi
  done

  [ "$DOCK_TOUCHED" -eq 1 ] && killall Dock 2>/dev/null
  if [ "$DOCK_FAIL" -eq 0 ]; then note_ok "Dock curated"; else note_fail "Dock (some apps could not be added)"; fi
else
  note_fail "Dock (dockutil unavailable)"
fi

# ---- 4. ~/Projects and the macOS preferences -----------------------------------
# Where work lives on every Benex Mac. Making it here means clone instructions and
# the shell helpers can assume it exists.
mkdir -p "$HOME/Projects"

# Per-user preferences, all of them write-the-same-value-again idempotent. The
# screen-lock password prompt is NOT set here — that's the MDM Blueprint's job.
defaults write NSGlobalDomain AppleShowAllExtensions -bool true          # real file extensions
defaults write com.apple.finder ShowPathbar -bool true
defaults write com.apple.finder ShowStatusBar -bool true
defaults write com.apple.AppleMultitouchTrackpad Clicking -bool true     # tap to click
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool true
defaults write NSGlobalDomain com.apple.mouse.tapBehavior -int 1
defaults -currentHost write NSGlobalDomain com.apple.mouse.tapBehavior -int 1
defaults write NSGlobalDomain KeyRepeat -int 2                           # fast key repeat
defaults write NSGlobalDomain InitialKeyRepeat -int 15
mkdir -p "$HOME/Screenshots"                                            # screenshots out of the Desktop
defaults write com.apple.screencapture location "$HOME/Screenshots"
defaults -currentHost write com.apple.screensaver idleTime -int 120      # screensaver after 2 min
# One restart for the whole block rather than one per setting.
killall Finder SystemUIServer 2>/dev/null
note_ok "macOS preferences"

# Rosetta 2 is installed by root.sh (it needs root); report it here so the
# employee sees it in the same summary as everything else.
if [ "$(uname -m)" != "arm64" ] || [ -d /Library/Apple/usr/share/rosetta ]; then
  note_ok "Rosetta 2"
else
  note_fail "Rosetta 2"
fi

# ---- 5. Node LTS + Claude Code ----------------------------------------------
export NVM_DIR="$HOME/.nvm"
mkdir -p "$NVM_DIR"
if [ -s /opt/homebrew/opt/nvm/nvm.sh ]; then
  source /opt/homebrew/opt/nvm/nvm.sh
  if nvm install --lts && nvm alias default 'lts/*' && nvm use default; then
    note_ok "Node LTS"
    if npm install -g @anthropic-ai/claude-code; then note_ok "Claude Code"; else note_fail "Claude Code"; fi
  else
    note_fail "Node LTS"
    note_fail "Claude Code"
  fi
else
  note_fail "Node LTS"
  note_fail "Claude Code"
fi

# ---- 6. Claude Code status line ----------------------------------------------
# The shared ccstatusline setup: the npm package, the widget config, and the
# statusLine key in ~/.claude/settings.json. Anything the employee has already
# customised is left exactly as it is — this only ever fills in what's missing.
# Files come from next to this script, from the package payload, or off the web,
# the same three ways root.sh finds the wallpaper.
if command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
  if npm install -g ccstatusline; then note_ok "ccstatusline"; else note_fail "ccstatusline"; fi

  HERE="${0:A:h}"
  SL_BASE="${BENEX_BOOTSTRAP_BASE:-https://benextechnologies.github.io/mac-bootstrap}"
  SL_DIR="$HOME/.config/ccstatusline"
  SL_STAGE=$(mktemp -d /tmp/benex-statusline.XXXXXX)
  for f in settings.json session-output.js; do
    if [ -f "$HERE/statusline/$f" ]; then
      cp "$HERE/statusline/$f" "$SL_STAGE/$f"
    elif [ -f "/usr/local/benex/statusline/$f" ]; then
      cp "/usr/local/benex/statusline/$f" "$SL_STAGE/$f"
    else
      curl -fsSL "$SL_BASE/statusline/$f" -o "$SL_STAGE/$f" || true
    fi
  done

  if [ -s "$SL_STAGE/settings.json" ] && [ -s "$SL_STAGE/session-output.js" ]; then
    mkdir -p "$SL_DIR"
    # The widget script, then the config that points at it — neither overwrites
    # a file that is already there. The committed config carries a __HOME__
    # placeholder for the script's path; resolve it as we copy it in.
    [ -f "$SL_DIR/session-output.js" ] || cp "$SL_STAGE/session-output.js" "$SL_DIR/session-output.js"
    chmod +x "$SL_DIR/session-output.js" 2>/dev/null || true
    SL_OK=1
    if [ ! -f "$SL_DIR/settings.json" ]; then
      node -e '
        const fs = require("fs");
        const [src, dst, cmd] = process.argv.slice(1);
        const cfg = JSON.parse(fs.readFileSync(src, "utf8"));
        for (const line of cfg.lines || [])
          for (const w of line || [])
            if (w && typeof w.commandPath === "string") w.commandPath = cmd;
        fs.writeFileSync(dst, JSON.stringify(cfg, null, 2) + "\n");
      ' "$SL_STAGE/settings.json" "$SL_DIR/settings.json" "$SL_DIR/session-output.js" || SL_OK=0
    fi

    # Point Claude Code at it. Merge into whatever settings.json is already
    # there; an existing statusLine key wins, and a file we can't parse is left
    # untouched rather than clobbered.
    CCSL=$(command -v ccstatusline 2>/dev/null || true)
    if [ -n "$CCSL" ]; then
      mkdir -p "$HOME/.claude"
      node -e '
        const fs = require("fs");
        const [p, cmd] = process.argv.slice(1);
        let s = {};
        if (fs.existsSync(p)) {
          const raw = fs.readFileSync(p, "utf8").trim();
          if (raw) s = JSON.parse(raw);   // malformed: throw, and change nothing
        }
        if (s.statusLine) { console.log("status line: keeping the one already configured"); process.exit(0); }
        s.statusLine = { type: "command", command: cmd, padding: 0 };
        fs.writeFileSync(p, JSON.stringify(s, null, 2) + "\n");
        console.log("status line: added to " + p);
      ' "$HOME/.claude/settings.json" "$CCSL" || SL_OK=0
    else
      SL_OK=0
    fi
    if [ "$SL_OK" -eq 1 ]; then note_ok "status line config"; else note_fail "status line config"; fi
  else
    note_fail "status line config (files not found)"
  fi
  rm -rf "$SL_STAGE"
else
  note_fail "ccstatusline (node/npm missing)"
fi

# ---- 7. Git identity --------------------------------------------------------
# Name comes from the macOS account's display name. The EMAIL does not: it is
# whatever benex-day1 asked the employee for, or nothing at all. An unset
# user.email makes git ask; a guessed one silently signs commits as the wrong
# person (and gets the address wrong for anyone the Mac's account name isn't).
FULL_NAME=$(id -F 2>/dev/null || echo "$USER")
git config --global user.name  "$FULL_NAME"
git config --global init.defaultBranch main
git config --global pull.rebase false
if [ -n "$WORK_EMAIL" ]; then
  git config --global user.email "$WORK_EMAIL"
  note_ok "git identity ($FULL_NAME <$WORK_EMAIL>)"
else
  # Clear the address the old guessing version of this script left behind — but
  # only that one. An address the employee set themselves is theirs to keep.
  CURRENT_EMAIL=$(git config --global user.email 2>/dev/null || true)
  [ "$CURRENT_EMAIL" = "${USER}@getbenex.com" ] && git config --global --unset user.email 2>/dev/null
  note_ok "git identity ($FULL_NAME — benex-day1 will set the email)"
fi

# ---- 8. SSH key for GitHub ----------------------------------------------------
mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
if [ ! -f "$HOME/.ssh/id_ed25519" ]; then
  # No work email yet? Use ssh-keygen's own user@host comment — benex-day1
  # rewrites it to the real address once it has asked for it.
  ssh-keygen -t ed25519 -C "${WORK_EMAIL:-${USER}@$(hostname -s)}" -N "" -f "$HOME/.ssh/id_ed25519"
fi
# Put the public key on the Desktop so it's easy to paste into GitHub on Day 1
cp "$HOME/.ssh/id_ed25519.pub" "$HOME/Desktop/GitHub-SSH-key-paste-me.txt" 2>/dev/null || true

# ---- 9. Chrome as default browser (macOS asks the user to confirm) -----------
# macOS answers this with a confirmation dialog, so it only makes sense when
# somebody is actually there. Headless, it would pop Chrome open at first login
# with a prompt nobody sees; skip it and let Chrome ask on first launch instead.
if [ -d "/Applications/Google Chrome.app" ] && [ "$UNATTENDED" -eq 0 ]; then
  open -a "Google Chrome" --args --make-default-browser || true
elif [ "$UNATTENDED" -eq 1 ]; then
  echo "skipped the make-Chrome-default prompt (unattended run — Chrome asks on first launch)"
fi

# ---- 10. What worked, what didn't --------------------------------------------
echo
echo "── Benex Mac bootstrap: what got installed ──────────────────────────"
for item in "${DONE[@]}";     do echo "   ✓ $item"; done
for item in "${DEFERRED[@]}"; do echo "   ⏸ $item   deferred — needs an interactive run"; done
for item in "${FAILED[@]}";   do echo "   ✗ $item   FAILED"; done
echo
echo "   log:  $LOG"
# Deferred work does NOT hold the bootstrap open. If it did, the packaged Mac's
# LaunchAgent would re-run this whole script at every login, for ever, waiting for
# a password it can never be given. benex-day1 is the interactive completion path.
if [ ${#FAILED[@]} -eq 0 ]; then
  touch "$HOME/.benex-bootstrapped"
  if [ ${#DEFERRED[@]} -gt 0 ]; then
    echo "   ${#DEFERRED[@]} install(s) need your password — benex-day1 does them first, no action needed now."
  fi
  echo "   next: open a new terminal tab and run:  benex-day1"
else
  echo "   ${#FAILED[@]} thing(s) failed, so this Mac is NOT marked done — the next login retries them."
  echo "   to retry now:  curl -fsSL https://benextechnologies.github.io/mac-bootstrap/bootstrap.sh | zsh"
  echo "   still failing? send the list above and $LOG to Dan on Teams."
fi
echo "== $(date) user bootstrap done"
exit 0
