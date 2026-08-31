#!/bin/zsh
# ------------------------------------------------------------------------------
# Benex Mac bootstrap — USER part.   Runs once per user, as the employee.
#   • from benex-bootstrap.pkg: a LaunchAgent runs it at the first login
#   • from the day-1 one-liner: bootstrap.sh runs it right after root.sh
#
#   brew: git, nvm, gh + casks Chrome, Outlook, 1Password, Teams, Docker, Cursor, iTerm2, CopyClip
#   Node LTS + Claude Code, git identity, SSH key, Chrome as default browser
# ------------------------------------------------------------------------------
set -u
[ -f "$HOME/.benex-bootstrapped" ] && { echo "already bootstrapped ($HOME/.benex-bootstrapped) — nothing to do"; exit 0; }
LOG="$HOME/Library/Logs/benex-user-bootstrap.log"
mkdir -p "$HOME/Library/Logs"
exec > >(tee -a "$LOG") 2>&1
echo "== $(date) user bootstrap for $USER"

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
brew install git nvm gh || true
# GUI apps — one line to add/remove an app for every future Mac. Each app self-updates after install.
# Browser and email lead the GUI apps: day 1 can't start until the employee can read
# the mailbox their GitHub / 1Password invites were sent to. Dev tools after them.
for cask in google-chrome microsoft-outlook 1password microsoft-teams docker cursor iterm2 copyclip; do
  brew install --cask "$cask" || echo "WARN: cask $cask failed"
done
# brew install --cask cmux   # <- enable later once it's stable

# Benex wallpaper — set it for this user right away (best-effort: the MDM
# wallpaper profile is the enforcement; this just makes it instant on day 1).
osascript -e 'tell application "System Events" to set picture of every desktop to "/Library/Desktop Pictures/Benex.png"' || true

# ---- 3. Node LTS + Claude Code ----------------------------------------------
export NVM_DIR="$HOME/.nvm"
mkdir -p "$NVM_DIR"
source /opt/homebrew/opt/nvm/nvm.sh
nvm install --lts
nvm alias default 'lts/*'
nvm use default
npm install -g @anthropic-ai/claude-code

# ---- 4. Git identity --------------------------------------------------------
FULL_NAME=$(id -F 2>/dev/null || echo "$USER")
git config --global user.name  "$FULL_NAME"
git config --global user.email "${USER}@getbenex.com"
git config --global init.defaultBranch main
git config --global pull.rebase false

# ---- 5. SSH key for GitHub ----------------------------------------------------
mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
if [ ! -f "$HOME/.ssh/id_ed25519" ]; then
  ssh-keygen -t ed25519 -C "${USER}@getbenex.com" -N "" -f "$HOME/.ssh/id_ed25519"
fi
# Put the public key on the Desktop so it's easy to paste into GitHub on Day 1
cp "$HOME/.ssh/id_ed25519.pub" "$HOME/Desktop/GitHub-SSH-key-paste-me.txt" 2>/dev/null || true

# ---- 6. Chrome as default browser (macOS asks the user to confirm) -----------
if [ -d "/Applications/Google Chrome.app" ]; then
  open -a "Google Chrome" --args --make-default-browser || true
fi

touch "$HOME/.benex-bootstrapped"
echo "== $(date) user bootstrap done"
exit 0
