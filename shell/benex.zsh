#!/bin/zsh
# Benex shell helpers — claudel, clauded, claudew.
#
# Shipped by mac-bootstrap (root.sh copies this to /usr/local/benex/shell/benex.zsh
# and /etc/benex/benex.zsh sources it). No secrets, no hostnames, no tokens.
# A newer ~/.benex/benex.zsh, if an engineer has one, is sourced after this file
# and overrides these functions. benex-day1 does not clone anything to get here.
#
# clauded  Claude Code with permission prompts disabled
#          (claude --dangerously-skip-permissions). This is the current default.
# claudel  Claude Code for the length of a session, with system sleep disabled
#          until the command exits (sudo pmset -a disablesleep 1, then 0).
#          A reboot also clears a leftover disablesleep via com.benex.sleeprestore.
# claudew  Claude Code with the arguments you pass, and no other changes.
#
# None of these set shell options in the caller's shell.

_benex_claude_subcommands() {
  print -r -- clauded claudel claudew
}

_benex_require_claude() {
  emulate -L zsh
  local wrapper=$1
  if ! command -v claude >/dev/null 2>&1; then
    print -u2 -- "$wrapper: claude is not on PATH."
    print -u2 -- "         benex-day1 installs Claude Code. When that finishes, open a new terminal tab and run $wrapper again."
    return 127
  fi
}

# clauded disables every Claude Code permission prompt. Kept identical to the
# helper this replaces; whether that stays the default for every hire is
# Daniel's call (see the pull request).
clauded() {
  emulate -L zsh
  _benex_require_claude clauded || return $?
  command claude --dangerously-skip-permissions "$@"
}

# claudew is the plain wrapper: same as typing `claude`, including whatever
# arguments you add. It does not disable permission prompts and it does not
# touch sleep.
claudew() {
  emulate -L zsh
  _benex_require_claude claudew || return $?
  command claude "$@"
}

# claudel is the only Benex command that sets `pmset -a disablesleep`.
# /etc/sudoers.d/benex-pmset lets admins run /usr/bin/pmset with no password.
# sudo -n fails instead of sitting on a password prompt if that rule is missing.
claudel() {
  emulate -L zsh
  setopt localtraps
  _benex_require_claude claudel || return $?
  if ! sudo -n /usr/bin/pmset -a disablesleep 1; then
    print -u2 -- "claudel: could not run 'sudo pmset -a disablesleep 1'."
    print -u2 -- "         /etc/sudoers.d/benex-pmset should allow admins to run /usr/bin/pmset with no password."
    print -u2 -- "         Claude will still start. Sleep is unchanged."
  fi
  trap 'sudo -n /usr/bin/pmset -a disablesleep 0 || print -u2 -- "claudel: could not restore sleep (sudo pmset -a disablesleep 0). A reboot clears it."' EXIT
  local rc=0
  command claude "$@" || rc=$?
  return $rc
}
