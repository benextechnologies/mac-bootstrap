#!/bin/zsh
# ------------------------------------------------------------------------------
# Benex Mac bootstrap — USER part.   Runs once per user, as the employee.
#   • from benex-bootstrap.pkg: a LaunchAgent runs it at the first login
#   • from the day-1 one-liner: bootstrap.sh runs it right after root.sh
#
#   brew: git, nvm, gh, dockutil + casks Chrome, Outlook, 1Password, Teams,
#         Docker, Cursor, iTerm2, CopyClip
#   Dock curation, Node LTS + Claude Code, git identity, SSH key, Chrome default
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

typeset -a DONE FAILED
note_ok()   { DONE+=("$1"); }
note_fail() { FAILED+=("$1"); echo "WARN: $1 did not install"; }

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
install_cask() {
  if brew list --cask "$1" >/dev/null 2>&1; then note_ok "$1"; return 0; fi
  if brew install --cask "$1"; then note_ok "$1"; else note_fail "$1"; fi
}

for formula in git nvm gh dockutil; do
  install_formula "$formula"
done
# GUI apps — one line to add/remove an app for every future Mac. Each app self-updates after install.
# Browser and email lead the GUI apps: day 1 can't start until the employee can read
# the mailbox their GitHub / 1Password invites were sent to. Dev tools after them.
for cask in google-chrome microsoft-outlook 1password microsoft-teams docker cursor iterm2 copyclip; do
  install_cask "$cask"
done
# brew install --cask cmux   # <- enable later once it's stable

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
      echo "WARN: could not add ${app:t:r} to the Dock"
    fi
  done

  [ "$DOCK_TOUCHED" -eq 1 ] && killall Dock 2>/dev/null
  note_ok "Dock curated"
else
  note_fail "Dock (dockutil unavailable)"
fi

# ---- 4. Node LTS + Claude Code ----------------------------------------------
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

# ---- 5. Git identity --------------------------------------------------------
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
  # Clear anything an older, guessing version of this script left behind.
  git config --global --unset user.email 2>/dev/null || true
  note_ok "git identity ($FULL_NAME — benex-day1 will set the email)"
fi

# ---- 6. SSH key for GitHub ----------------------------------------------------
mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
if [ ! -f "$HOME/.ssh/id_ed25519" ]; then
  # No work email yet? Use ssh-keygen's own user@host comment — benex-day1
  # rewrites it to the real address once it has asked for it.
  ssh-keygen -t ed25519 -C "${WORK_EMAIL:-${USER}@$(hostname -s)}" -N "" -f "$HOME/.ssh/id_ed25519"
fi
# Put the public key on the Desktop so it's easy to paste into GitHub on Day 1
cp "$HOME/.ssh/id_ed25519.pub" "$HOME/Desktop/GitHub-SSH-key-paste-me.txt" 2>/dev/null || true

# ---- 7. Chrome as default browser (macOS asks the user to confirm) -----------
if [ -d "/Applications/Google Chrome.app" ]; then
  open -a "Google Chrome" --args --make-default-browser || true
fi

# ---- 8. What worked, what didn't ---------------------------------------------
echo
echo "── Benex Mac bootstrap: what got installed ──────────────────────────"
for item in "${DONE[@]}";   do echo "   ✓ $item"; done
for item in "${FAILED[@]}"; do echo "   ✗ $item   FAILED"; done
echo
echo "   log:  $LOG"
if [ ${#FAILED[@]} -eq 0 ]; then
  touch "$HOME/.benex-bootstrapped"
  echo "   next: open a new terminal tab and run:  benex-day1"
else
  echo "   ${#FAILED[@]} thing(s) failed, so this Mac is NOT marked done — the next login retries them."
  echo "   to retry now:  curl -fsSL https://benextechnologies.github.io/mac-bootstrap/bootstrap.sh | zsh"
  echo "   still failing? send the list above and $LOG to Dan on Teams."
fi
echo "== $(date) user bootstrap done"
exit 0
