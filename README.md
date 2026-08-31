# mac-bootstrap

Everything a new Benex Mac needs beyond what Apple Business's Blueprint already enforces
(FileVault, firewall, screen lock, software updates, browser policy).

| File | Runs as | What |
|---|---|---|
| `root.sh` | root | sleep timers + pmset sudoers, keepawake/sleeprestore daemons, `/etc/benex/benex.zsh`, Xcode CLT, Homebrew (owned by the user), installs `benex-day1`, Benex wallpaper to `/Library/Desktop Pictures` |
| `user.sh` | the employee | git/nvm/gh/dockutil, Chrome, Outlook, 1Password, Teams, Docker, Cursor, iTerm2, CopyClip, Benex wallpaper, Dock curation, Node LTS, Claude Code, git identity, SSH key, Chrome default — then prints what installed and what didn't |
| `benex-day1` | the employee | guided sign-ins on day 1, email first (see below) |
| `bootstrap.sh` | the employee | the day-1 one-liner: downloads the three files above and runs root.sh (sudo) then user.sh |
| `pkg/build-pkg.sh` | Dan | builds + signs `benex-bootstrap.pkg` for Apple Business (zero-touch path) |

## The day-1 order (`benex-day1`)

Email first. The GitHub org invite and the 1Password invite are both sent to
`first.name@getbenex.com`, so nothing can be activated until the employee can read that
mailbox — and a new hire may not have a GitHub account at all yet. (Duo is the only thing
that has to work before the mailbox does; it's set up during the Microsoft sign-in itself.)

0. **Your address** — `benex-day1` asks for the employee's `@getbenex.com` address, saves it to
   `~/.benex/work-email` (mode 600) and reuses it on every later run. Everything downstream —
   git `user.email`, the SSH key comment, every "sign in as…" instruction — uses that value.
1. **Work email** — sign in at `outlook.office.com` with the `@getbenex.com` account (password + Duo push).
2. **Activate the accounts waiting in the mailbox** — create a GitHub account with the work
   email if there isn't one and accept the `benextechnologies` org invite; accept the
   1Password invite (`benex.1password.com`).
3. **CLI + app sign-ins** — GitHub CLI (`gh auth login`) and SSH key, the shell-helper repo,
   the 1Password app, Outlook/Teams/Company Portal, Claude Code, Docker, Cursor.

Steps 0–2 are new: before them, day 1 asked for `gh auth login` while the employee still had
no way to read the invite that made a GitHub sign-in possible. Steps 1–2 re-prompt on every
run (like the other steps the script can't check for itself); answering them again is harmless.

**Never derive the address from the Mac's account name.** Employees name their own local
account, so `$USER@getbenex.com` is simply wrong (a local account of `samash` produced
`samash@getbenex.com` everywhere — 1Password sign-in instructions and git `user.email`
included). Only the saved answer from step 0 is used; if `user.sh` runs before that answer
exists it leaves `user.email` unset rather than guessing, and `benex-day1` fills it in — and
rewrites the SSH key's comment — as soon as it knows.

**Claude accounts are personal.** Benex runs no Claude Team/Enterprise workspace and nobody
is pre-invited, so day 1 has the employee create their own account at `claude.ai` on their
Benex address (Claude Code needs a paid plan, Pro at minimum) *before* the `claude` login.

`user.sh` matches that order — Chrome and Outlook install ahead of the dev-tool casks.

## What `user.sh` leaves behind

- **A curated Dock** (via `dockutil`): Messages, Maps, Photos, TV, Music, News, Freeform and
  FaceTime out; Chrome, Outlook, Teams, 1Password, iTerm2 and Cursor in, in that order. Only
  apps actually on disk are added, nothing is added twice, and the Dock restarts once at the end.
- **A summary you can act on.** Every formula and cask installs on its own — one failure never
  costs the rest — and the run ends with a ✓/✗ list, the log path, and how to retry. A run with
  failures is deliberately *not* marked done, so the next login retries just the failures.
- **A log**: `~/Library/Logs/benex-user-bootstrap.log`, appended per run (the root half logs to
  `/var/log/benex-bootstrap.log`).

## Two delivery paths

**Until the Developer ID certificate exists** — employee runs, in Terminal, on day 1:

```
curl -fsSL https://benextechnologies.github.io/mac-bootstrap/bootstrap.sh | zsh
```

**Once it exists** — `./pkg/build-pkg.sh "Developer ID Installer: Benex Technologies Inc (TEAMID)"`,
commit `dist/benex-bootstrap.pkg`, add it in Apple Business → macOS Packages (URL + SHA-256),
attach to the Work Devices Blueprint. From then on every Mac installs everything on first boot.

## Hosting

This repo is **public** and served by GitHub Pages from the root (Settings → Pages → Deploy from branch → `main` / `/ (root)`).
Nothing in it is secret: the shell helpers (`claudel` etc.) live in the private `new-laptop-setup-guide` repo and are
fetched by `benex-day1` after the employee has signed in to GitHub.

## Updating

Edit `root.sh` / `user.sh`, commit, done — the one-liner always pulls the latest. For the package path,
rebuild, commit the new `.pkg`, and update the hash in Apple Business.
