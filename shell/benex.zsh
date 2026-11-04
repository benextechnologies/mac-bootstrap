# benex.zsh — Benex shared zsh helpers. Pure zsh, no secrets, no machine paths.
#
# Canonical source: github.com/benextechnologies/new-laptop-setup-guide → shell/benex.zsh
# Shipped in the signed benex-bootstrap package (Apple Business built-in MDM)
# to /usr/local/benex/shell/benex.zsh. Managed Benex Macs load it on every new shell:
#   /etc/zshrc → /etc/benex/benex.zsh → /usr/local/benex/shell/benex.zsh
# (after Homebrew and nvm, so `claude` is already on PATH when this runs).
# A ~/.benex/benex.zsh, if an engineer has one, is sourced after this file and overrides it.
# Unmanaged Macs: add   source ~/.benex/benex.zsh   to your ~/.zshrc yourself.
#
# Defines the Claude Code launchers clauded / claudel / claudew.
# Goal: behave exactly like the stock `claude` command for every argument form,
# with ONE addition — leading non-flag words become the session's display name
# (claude --name: shown in the prompt box, /resume picker, terminal title).
# They are NOT passed as the first prompt (that was the old bug: `clauded foo`
# started a session with "foo" pasted in as the prompt).
#
# Usage:
#   clauded my-session-name          # names the session, lid-open
#   clauded "pay links fix"          # quoted names work too
#   clauded pay links fix            # unquoted multi-word names also work
#   clauded my-session --effort max  # flags after the name pass through
#   clauded -c                       # first arg is a flag -> pure passthrough
#   clauded --resume                 # any stock flag usage works unchanged
#   clauded -p "query"               # print mode works unchanged
#   clauded mcp list                 # subcommands pass through verbatim
#   clauded update                   # (no --dangerously-skip-permissions added:
#                                    #  subcommands don't accept it)
#   clauded my-session -- "prompt"   # anything after `--` forwards verbatim,
#                                    # so a real first prompt is still possible
#   claudel ...                      # same, but for lid-CLOSED runs (sudo pmset)
#   claudew ...                      # same as clauded, in an isolated git worktree
#
# Caveat: a session name that collides with a subcommand word below won't work
# bare — use `clauded --name update` for that.
#
# Keep-awake: on Macs with the com.benex.keepawake LaunchDaemon (Intune, or
# benex-automation/macos on legacy dev machines), lid-OPEN sessions never
# idle-sleep, so no wrapper needs to caffeinate. Use `clauded` for lid-open
# work, `claudel` to run with the lid CLOSED.

# Everything below wraps the `claude` CLI — define nothing without it (e.g. the
# first-boot bootstrap is still installing; open a new terminal tab once done).
# Braced form: `$+commands[...]` misparses if the user set KSH_ARRAYS in ~/.zshenv.
(( ${+commands[claude]} )) || return 0

# Remote Control (drive the session from the Claude phone app / claude.ai/code)
# is not injected here either: put `"remoteControlAtStartup": true` in your
# ~/.claude/settings.json and every session is reachable from the phone, or pass
# `--remote-control` per session (flags pass through) / type `/rc` inside one.
# Lid-closed + phone recipe: benex-automation/shell/README.md.

# `claude` subcommands (from `claude --help` @ 2.1.259). If the first arg is one
# of these, forward everything untouched. Re-sync this list when `claude --help`
# grows a new subcommand, or `clauded <newcmd>` will treat it as a session name.
_benex_claude_subcommands=(
  agents attach auth auto-mode doctor gateway import install logs mcp plugin
  plugins project respawn rm setup-token stop kill ultrareview update upgrade
)

_benex_claude() {
  emulate -L zsh
  if (( $# )) && (( ${_benex_claude_subcommands[(Ie)$1]} )); then
    command claude "$@"           # subcommand: verbatim, no injected flags
    return
  fi
  local -a name_words pass
  local parsing_name=1 a
  for a in "$@"; do
    if (( parsing_name )) && [[ $a == -- ]]; then
      parsing_name=0            # drop the separator; the rest forwards verbatim
    elif (( parsing_name )) && [[ $a != -* ]]; then
      name_words+=("$a")
    else
      parsing_name=0
      pass+=("$a")
    fi
  done
  if (( ${#name_words} )); then
    command claude --dangerously-skip-permissions --name "${(j: :)name_words}" "${pass[@]}"
  else
    command claude --dangerously-skip-permissions "${pass[@]}"
  fi
}

clauded() {              # Claude, permission prompts disabled (lid OPEN: daemon keeps Mac awake)
  _benex_claude "$@"
}

claudel() {              # run Claude with the LID CLOSED (needs sudo + an admin account; sleep restored on exit)
  if ! sudo pmset -a disablesleep 1; then
    print -u2 "claudel: 'sudo pmset -a disablesleep 1' failed, so closing the lid WOULD sleep the Mac."
    print -u2 "claudel: not starting Claude. Fix sudo (admin account / Touch ID) or use clauded for lid-open work."
    return 1
  fi
  {
    _benex_claude "$@"
  } always {
    # restore even if claude is interrupted — otherwise SleepDisabled sticks at 1
    # and the Mac never sleeps again (sudo may re-prompt after a long session).
    # A reboot mid-session skips this entirely; the com.benex.sleeprestore
    # LaunchDaemon (mac-bootstrap installs it on every bootstrapped Benex Mac;
    # source in benex-automation/macos) resets disablesleep at boot. On a Mac
    # without it, run `sudo pmset -a disablesleep 0` once by hand.
    sudo pmset -a disablesleep 0
  }
}

claudew() {              # like clauded, but in an isolated git worktree (auto-named; name it via -w NAME)
  if (( $# )) && (( ${_benex_claude_subcommands[(Ie)$1]} )); then
    command claude "$@"  # subcommand runs aren't sessions — no worktree to inject
    return
  fi
  local -a wt=(--worktree)
  local a
  for a in "$@"; do      # if the user passed -w/--worktree themselves, don't inject a second one
    [[ $a == -w || $a == --worktree || $a == --worktree=* ]] && wt=()
  done
  # injected --worktree goes LAST so it can never swallow a positional as the worktree name
  _benex_claude "$@" "${wt[@]}"
}


