# mac-bootstrap

Everything a new Benex Mac needs beyond what Apple Business's Blueprint already enforces
(FileVault, firewall, screen lock, software updates, browser policy).

| File | Runs as | What |
|---|---|---|
| `root.sh` | root | sleep timers + pmset sudoers, keepawake/sleeprestore daemons, `/etc/benex/benex.zsh`, Xcode CLT, Homebrew (owned by the user), installs `benex-day1`, Benex wallpaper to `/Library/Desktop Pictures` |
| `user.sh` | the employee | git/nvm/gh, Chrome, Outlook, 1Password, Teams, Docker, Cursor, iTerm2, CopyClip, sets the Benex wallpaper, Node LTS, Claude Code, git identity, SSH key, Chrome default |
| `benex-day1` | the employee | guided sign-ins on day 1, email first (see below) |
| `bootstrap.sh` | the employee | the day-1 one-liner: downloads the three files above and runs root.sh (sudo) then user.sh |
| `pkg/build-pkg.sh` | Dan | builds + signs `benex-bootstrap.pkg` for Apple Business (zero-touch path) |

## The day-1 order (`benex-day1`)

Email first. The GitHub org invite, the 1Password invite and the Duo enrolment are all
sent to `first.name@getbenex.com`, so nothing can be activated until the employee can
read that mailbox — and a new hire may not have a GitHub account at all yet.

1. **Work email** — sign in at `outlook.office.com` with the `@getbenex.com` account (password + Duo push).
2. **Activate the accounts waiting in the mailbox** — create a GitHub account with the work
   email if there isn't one and accept the `benextechnologies` org invite; accept the
   1Password invite (`benex.1password.com`).
3. **CLI + app sign-ins** — GitHub CLI (`gh auth login`) and SSH key, the shell-helper repo,
   the 1Password app, Company Portal, Claude Code, Docker, Cursor.

Steps 1–2 are new: before them, day 1 asked for `gh auth login` while the employee still had
no way to read the invite that made a GitHub sign-in possible.

`user.sh` matches that order — Chrome and Outlook install ahead of the dev-tool casks.

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
