#!/bin/zsh
# ------------------------------------------------------------------------------
# Benex Mac bootstrap — day-1 one-liner (until the signed package is in place):
#
#     curl -fsSL https://benextechnologies.github.io/mac-bootstrap/bootstrap.sh | zsh
#
# Downloads root.sh, user.sh, benex-day1, and the shell helpers from the same
# location, runs the root part with sudo (one password prompt), then the user
# part as you. Safe to re-run.
# ------------------------------------------------------------------------------
set -u
BASE="${BENEX_BOOTSTRAP_BASE:-https://benextechnologies.github.io/mac-bootstrap}"
[ "$(id -u)" -eq 0 ] && { echo "Run this as yourself, not with sudo — it asks for sudo when it needs it."; exit 1; }

TMP="$(mktemp -d /tmp/benex-bootstrap.XXXXXX)"
for f in root.sh user.sh benex-day1; do
  curl -fsSL "$BASE/$f" -o "$TMP/$f" || { echo "Could not download $BASE/$f"; exit 1; }
done
# claudel / clauded / claudew. Required: day 1 no longer clones a private repo for them.
mkdir -p "$TMP/shell"
if ! curl -fsSL "$BASE/shell/benex.zsh" -o "$TMP/shell/benex.zsh"; then
  echo "Could not download $BASE/shell/benex.zsh"
  echo "claudel, clauded, and claudew come from that file. It is part of this repo, not a private clone."
  echo "If that URL 404s, shell/benex.zsh is not on the GitHub Pages branch yet."
  exit 1
fi
chmod 755 "$TMP"/*

# The Claude Code status line files ride along; user.sh skips that step without them.
mkdir -p "$TMP/statusline"
for f in settings.json session-output.js; do
  curl -fsSL "$BASE/statusline/$f" -o "$TMP/statusline/$f" \
    || echo "note: could not download $BASE/statusline/$f — the status line will be skipped"
done

echo
echo "── Benex Mac bootstrap ──────────────────────────────────────────────"
echo "Step 1/2 needs your Mac password once (system settings, Homebrew)."
sudo -p "Mac password: " bash "$TMP/root.sh" || { echo "root part failed — see /var/log/benex-bootstrap.log"; exit 1; }

echo "Step 2/2: apps and dev tools as $USER (15–30 min)…"
echo "          Microsoft 365 is a ~3GB installer package, so this may ask for your Mac"
echo "          password once. It prints what installed and what didn't when it finishes."
zsh "$TMP/user.sh"

rm -rf "$TMP"
echo
echo "   logs:  ~/Library/Logs/benex-user-bootstrap.log   (apps and dev tools)"
echo "          /var/log/benex-bootstrap.log              (system settings)"
echo "✔ Done. Open a new terminal tab, then run:  benex-day1"
