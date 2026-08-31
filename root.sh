#!/bin/bash
# ------------------------------------------------------------------------------
# Benex Mac bootstrap — ROOT part.   Runs once per Mac, as root.
#
# Delivered two ways (same file):
#   • benex-bootstrap.pkg postinstall  (Apple Business → Blueprint → macOS Packages)  — zero-touch
#   • curl one-liner on day 1:  curl -fsSL https://benextechnologies.github.io/mac-bootstrap/bootstrap.sh | zsh
#
# What it does:
#   1. Sleep/display timers to match Dan's Mac + lets admins run pmset without a sudo password (claudel)
#   2. keepawake + sleeprestore LaunchDaemons (ported from the pre-MDM dev-machine setup)
#   3. Shared zsh config for every user  (/etc/benex/benex.zsh: brew, nvm, hook for the git helpers)
#   4. Xcode Command Line Tools
#   5. Homebrew into /opt/homebrew, owned by the employee (no sudo prompt ever again)
#   6. Installs /usr/local/bin/benex-day1 (from the same download / package payload)
#   7. Installs the Benex wallpaper to "/Library/Desktop Pictures/Benex.png"
#   8. Touch ID for sudo (/etc/pam.d/sudo_local — survives macOS updates)
#   9. Rosetta 2 on Apple silicon
# ------------------------------------------------------------------------------
set -u
LOG=/var/log/benex-bootstrap.log
exec > >(tee -a "$LOG") 2>&1
echo "== $(date) system bootstrap start"

# ---- 1. Sleep / display timers (mirrors Dan's Mac, `pmset -g custom`, 27 Aug 2026) --
# Battery (-b) and charger (-c). Minutes. 0 = never.
pmset -b displaysleep 5 sleep 1 disksleep 10 lowpowermode 1 powernap 1 standby 1 womp 0
pmset -c displaysleep 5 sleep 0 disksleep 10 lowpowermode 1 powernap 1 standby 1 womp 1

# claudel toggles sleep with `sudo pmset -a disablesleep` — let admins run pmset without a password prompt
mkdir -p /etc/sudoers.d
printf '%%admin ALL=(root) NOPASSWD: /usr/bin/pmset\n' > /etc/sudoers.d/benex-pmset
chmod 440 /etc/sudoers.d/benex-pmset
visudo -cf /etc/sudoers.d/benex-pmset >/dev/null 2>&1 || rm -f /etc/sudoers.d/benex-pmset

# ---- 2. Keep-awake + sleep-restore LaunchDaemons --------------------------------
# Ported verbatim from the pre-MDM dev-machine setup — behavior identical:
#   • com.benex.keepawake    ← new-laptop-setup-guide/scripts/install-keepawake.sh
#   • com.benex.sleeprestore ← benex-automation/macos/com.benex.sleeprestore.plist
# keepawake holds `caffeinate -i` whenever a real user is logged in with the lid
# OPEN, so terminals / Claude Code / Docker never idle-sleep (lid-close still
# sleeps — travel mode). sleeprestore is a one-shot at boot that resets
# `pmset -a disablesleep 0`, cleaning up after a `claudel` session that died
# without restoring sleep (disablesleep persists across reboots). It is
# installed copy-only, with NO `launchctl bootstrap`: RunAtLoad would fire
# immediately and could race an active claudel session (or sleep a lid-closed
# Mac mid-install); launchd picks the plist up at the next boot, which is the
# only time the reset is needed.

# -- keepawake watchdog script (root:wheel, NOT user-writable — it runs as root)
cat > /usr/local/bin/keepawake.sh <<'KEEPAWAKE_EOF'
#!/bin/bash
#
# keepawake.sh — keep this Mac awake (apps running) whenever a user is logged in and
# the lid is OPEN. Apps then run indefinitely until logout, shutdown, or lid-close.
#
# Holds a `caffeinate -i` assertion (PreventUserIdleSystemSleep) whenever BOTH:
#   1. a real user is logged into the console (NOT the login window), and
#   2. the laptop lid is OPEN.
#
# caffeinate -i works on battery AND AC, and is auto-overridden by lid-close (clamshell)
# sleep, so closing the lid always sleeps (travel mode). Screen-lock / screensaver /
# display-off do NOT pause apps — only system sleep does, which this prevents.

set -u

# Lid is open unless ioreg reports AppleClamshellState = Yes (closed).
lid_is_open() {
  ! ioreg -r -k AppleClamshellState 2>/dev/null | grep -q 'AppleClamshellState" = Yes'
}

# A real user is at the console (logged in, even if the screen is locked) — not the
# login window (shows as root / _windowserver) and not a system "_" account.
user_logged_in() {
  local u; u=$(stat -f '%Su' /dev/console 2>/dev/null)
  [ -n "$u" ] && [ "$u" != "root" ] && [ "${u#_}" = "$u" ]
}

CAFF_PID=""
holding=0
log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1"; }

start_caffeinate() {
  if [ -z "$CAFF_PID" ] || ! kill -0 "$CAFF_PID" 2>/dev/null; then
    caffeinate -i &
    CAFF_PID=$!
    [ "$holding" -eq 0 ] && log "HOLD    user logged in + lid open -> caffeinate -i (pid $CAFF_PID)"
    holding=1
  fi
}

stop_caffeinate() {
  if [ -n "$CAFF_PID" ] && kill -0 "$CAFF_PID" 2>/dev/null; then
    kill "$CAFF_PID" 2>/dev/null
  fi
  CAFF_PID=""
  [ "$holding" -eq 1 ] && log "RELEASE logged out or lid closed -> allow normal sleep"
  holding=0
}

trap 'stop_caffeinate; exit 0' TERM INT

log "keepawake started (pid $$)"
while true; do
  if user_logged_in && lid_is_open; then
    start_caffeinate
  else
    stop_caffeinate
  fi
  sleep 30
done
KEEPAWAKE_EOF
chown root:wheel /usr/local/bin/keepawake.sh
chmod 755 /usr/local/bin/keepawake.sh

# -- keepawake LaunchDaemon plist (root:wheel), then (re)load it now
cat > /Library/LaunchDaemons/com.benex.keepawake.plist <<'PLIST_EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.benex.keepawake</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>/usr/local/bin/keepawake.sh</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>ProcessType</key>
    <string>Background</string>
    <key>StandardOutPath</key>
    <string>/Library/Logs/benex-keepawake.log</string>
    <key>StandardErrorPath</key>
    <string>/Library/Logs/benex-keepawake.log</string>
</dict>
</plist>
PLIST_EOF
chown root:wheel /Library/LaunchDaemons/com.benex.keepawake.plist
chmod 644 /Library/LaunchDaemons/com.benex.keepawake.plist
launchctl bootout system/com.benex.keepawake 2>/dev/null
launchctl bootstrap system /Library/LaunchDaemons/com.benex.keepawake.plist

# -- sleeprestore LaunchDaemon plist (copy-only; see the note above)
cat > /Library/LaunchDaemons/com.benex.sleeprestore.plist <<'PLIST_EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.benex.sleeprestore</string>
    <!-- One-shot at boot (RunAtLoad, no KeepAlive): claudel arms
         `pmset -a disablesleep 1` and restores 0 on exit, but a reboot
         mid-session (e.g. a macOS auto-update) kills the shell before the exit
         handler runs, and disablesleep PERSISTS across reboots - the Mac then
         never sleeps on lid close. After a boot no claudel session can still
         be alive, so resetting to 0 here is always correct. Runs as root, so
         no password prompt.
         INVARIANT: claudel is the only thing on this machine that sets
         disablesleep. Any manual `pmset -a disablesleep 1` will be undone at
         the next boot by this daemon. -->
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>-c</string>
        <string>if /usr/bin/pmset -a disablesleep 0; then echo "$(date '+%Y-%m-%d %H:%M:%S') boot: disablesleep reset to 0 (stale claudel state cleared if any)"; else rc=$?; echo "$(date '+%Y-%m-%d %H:%M:%S') boot: pmset -a disablesleep 0 FAILED rc=$rc"; fi</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/Library/Logs/benex-sleeprestore.log</string>
    <key>StandardErrorPath</key>
    <string>/Library/Logs/benex-sleeprestore.log</string>
</dict>
</plist>
PLIST_EOF
chown root:wheel /Library/LaunchDaemons/com.benex.sleeprestore.plist
chmod 644 /Library/LaunchDaemons/com.benex.sleeprestore.plist

# ---- 3. Shared Benex zsh helpers (system-wide, every user) --------------------
mkdir -p /etc/benex
cat > /etc/benex/benex.zsh <<'EOF'
# Benex shared zsh config — managed by the Benex bootstrap
# (github.com/benextechnologies/mac-bootstrap → root.sh). Edit it there, not here.

# Homebrew (Apple silicon)
[ -x /opt/homebrew/bin/brew ] && eval "$(/opt/homebrew/bin/brew shellenv)"

# nvm (Node version manager) — installed per-user by user.sh
export NVM_DIR="$HOME/.nvm"
[ -s /opt/homebrew/opt/nvm/nvm.sh ] && . /opt/homebrew/opt/nvm/nvm.sh

# Benex shell helpers (claudel / clauded / claudew …) live in git:
#   github.com/benextechnologies/new-laptop-setup-guide  →  shell/install.sh
# `benex-day1` clones the repo and installs them to ~/.benex/benex.zsh
[ -f "$HOME/.benex/benex.zsh" ] && source "$HOME/.benex/benex.zsh"
EOF
chmod 644 /etc/benex/benex.zsh
grep -q '/etc/benex/benex.zsh' /etc/zshrc 2>/dev/null || \
  printf '\n# Benex shared config (managed by Benex mac-bootstrap)\n[ -f /etc/benex/benex.zsh ] && source /etc/benex/benex.zsh\n' >> /etc/zshrc

# ---- 4. Xcode Command Line Tools -----------------------------------------------
if ! xcode-select -p >/dev/null 2>&1; then
  echo "Installing Command Line Tools…"
  touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
  CLT_LABEL=$(softwareupdate -l 2>/dev/null | grep -o 'Command Line Tools for Xcode-[0-9.]*' | sort -V | tail -1)
  if [ -n "$CLT_LABEL" ]; then
    softwareupdate -i "$CLT_LABEL" --verbose
  else
    echo "WARNING: could not find a Command Line Tools package via softwareupdate"
  fi
  rm -f /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
fi

# ---- 5. Homebrew into /opt/homebrew, usable by every admin user -----------------
# Installed the "untar" way as root so no sudo password is ever needed, then handed to the
# admin group (the first account a Mac creates is an admin). Works whether or not anyone is
# logged in yet — so it is safe inside the package postinstall during first boot.
if [ ! -x /opt/homebrew/bin/brew ]; then
  echo "Installing Homebrew to /opt/homebrew…"
  mkdir -p /opt/homebrew
  curl -fsSL https://github.com/Homebrew/brew/tarball/master | tar xz --strip-components 1 -C /opt/homebrew
fi
chgrp -R admin /opt/homebrew 2>/dev/null || true
chmod -R g+rwX /opt/homebrew 2>/dev/null || true
CONSOLE_USER="${SUDO_USER:-$(stat -f%Su /dev/console 2>/dev/null || true)}"
case "$CONSOLE_USER" in ""|root|_mbsetupuser|loginwindow) CONSOLE_USER="" ;; esac
if [ -n "$CONSOLE_USER" ]; then
  chown -R "$CONSOLE_USER":admin /opt/homebrew
  sudo -u "$CONSOLE_USER" -H /opt/homebrew/bin/brew update --force --quiet || true
fi

# ---- 6. Day-1 helper for the employee (/usr/local/bin/benex-day1) -------------
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p /usr/local/bin
if [ -f "$HERE/benex-day1" ]; then
  install -m 755 "$HERE/benex-day1" /usr/local/bin/benex-day1
elif [ -f /usr/local/benex/benex-day1 ]; then
  install -m 755 /usr/local/benex/benex-day1 /usr/local/bin/benex-day1
fi

# ---- 7. Benex wallpaper (/Library/Desktop Pictures/Benex.png) -------------------
# From the package payload when present; else (curl one-liner path) from Pages.
# user.sh sets it for the current user; the MDM wallpaper profile is the enforcement.
mkdir -p "/Library/Desktop Pictures"
if [ -f "$HERE/wallpaper/benex.png" ]; then
  install -m 644 "$HERE/wallpaper/benex.png" "/Library/Desktop Pictures/Benex.png"
elif [ -f /usr/local/benex/wallpaper/benex.png ]; then
  install -m 644 /usr/local/benex/wallpaper/benex.png "/Library/Desktop Pictures/Benex.png"
else
  curl -fsSL https://benextechnologies.github.io/mac-bootstrap/wallpaper/benex.png \
      -o "/Library/Desktop Pictures/.benex-wallpaper.tmp" \
    && mv "/Library/Desktop Pictures/.benex-wallpaper.tmp" "/Library/Desktop Pictures/Benex.png" \
    && chmod 644 "/Library/Desktop Pictures/Benex.png" \
    || { rm -f "/Library/Desktop Pictures/.benex-wallpaper.tmp"; echo "WARNING: could not fetch the Benex wallpaper"; }
fi

# ---- 8. Touch ID for sudo (/etc/pam.d/sudo_local) -------------------------------
# Apple's supported hook: /etc/pam.d/sudo includes sudo_local, and sudo_local is
# left alone by system updates — editing /etc/pam.d/sudo directly is what gets
# silently reverted. Written unconditionally rather than sniffing for a Touch ID
# sensor: on a Mac without one, pam_tid.so just doesn't succeed and sudo falls
# through to asking for the password, so there is nothing to detect and nothing
# to break.
PAM_TID_LINE='auth       sufficient     pam_tid.so'
if [ ! -f /etc/pam.d/sudo_local ]; then
  if [ -f /etc/pam.d/sudo_local.template ]; then
    sed 's/^#auth/auth/' /etc/pam.d/sudo_local.template > /etc/pam.d/sudo_local
  else
    printf '# sudo_local: local config, included by sudo and kept across updates\n%s\n' "$PAM_TID_LINE" > /etc/pam.d/sudo_local
  fi
  chown root:wheel /etc/pam.d/sudo_local
  chmod 444 /etc/pam.d/sudo_local
  echo "Touch ID for sudo: enabled"
elif grep -qE '^[[:space:]]*auth[[:space:]]+sufficient[[:space:]]+pam_tid\.so' /etc/pam.d/sudo_local; then
  echo "Touch ID for sudo: already enabled"
else
  # The file is there but the line is missing or commented out — add it once.
  chmod u+w /etc/pam.d/sudo_local
  printf '%s\n' "$PAM_TID_LINE" >> /etc/pam.d/sudo_local
  chmod 444 /etc/pam.d/sudo_local
  echo "Touch ID for sudo: added pam_tid to the existing sudo_local"
fi

# ---- 9. Rosetta 2 (Apple silicon only) ------------------------------------------
# --agree-to-license keeps it headless-safe; user.sh reports the result in its
# summary so the employee sees it alongside everything else.
if [ "$(uname -m)" = "arm64" ]; then
  if [ -d /Library/Apple/usr/share/rosetta ]; then
    echo "Rosetta 2: already installed"
  elif softwareupdate --install-rosetta --agree-to-license; then
    echo "Rosetta 2: installed"
  else
    echo "WARNING: Rosetta 2 did not install"
  fi
else
  echo "Rosetta 2: not applicable on this architecture ($(uname -m))"
fi

echo "== $(date) system bootstrap done"
exit 0
