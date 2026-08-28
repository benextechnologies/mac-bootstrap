# mac-bootstrap

Everything a new Benex Mac needs beyond what Apple Business's Blueprint already enforces
(FileVault, firewall, screen lock, software updates, browser policy).

| File | Runs as | What |
|---|---|---|
| `root.sh` | root | sleep timers + pmset sudoers, keepawake/sleeprestore daemons, `/etc/benex/benex.zsh`, Xcode CLT, Homebrew (owned by the user), installs `benex-day1`, Benex wallpaper to `/Library/Desktop Pictures` |
| `user.sh` | the employee | git/nvm/gh, Chrome, 1Password, Teams, Docker, Cursor, iTerm2, CopyClip, sets the Benex wallpaper, Node LTS, Claude Code, git identity, SSH key, Chrome default |
| `benex-day1` | the employee | guided sign-ins on day 1 (GitHub + SSH key, helper repo, 1Password, Claude Code, Docker, Cursor) |
| `bootstrap.sh` | the employee | the day-1 one-liner: downloads the three files above and runs root.sh (sudo) then user.sh |
| `pkg/build-pkg.sh` | Dan | builds + signs `benex-bootstrap.pkg` for Apple Business (zero-touch path) |

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
