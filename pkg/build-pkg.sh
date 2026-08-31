#!/bin/zsh
# ------------------------------------------------------------------------------
# Build (and sign) benex-bootstrap.pkg for Apple Business → Blueprint → macOS Packages.
#
#   ./pkg/build-pkg.sh                       # unsigned (for local testing only)
#   ./pkg/build-pkg.sh "Developer ID Installer: Benex Technologies Inc (TEAMID)"
#
# Run on a Mac, from the mac-bootstrap repo root. Needs Xcode Command Line Tools.
# The package is payload-only-scripts: it copies root.sh / user.sh / benex-day1 to
# /usr/local/benex, runs root.sh immediately, and installs a LaunchAgent that runs
# user.sh once at each user's first login. macOS only accepts MDM-pushed packages
# that are signed with a Developer ID Installer certificate.
# ------------------------------------------------------------------------------
set -euo pipefail
cd "$(dirname "$0")/.."
SIGN_ID="${1:-}"
VERSION="$(date +%Y.%m.%d)"
OUT="dist"; STAGE="$(mktemp -d)"; ROOT="$STAGE/root"; SCRIPTS="$STAGE/scripts"
mkdir -p "$OUT" "$ROOT/usr/local/benex" "$ROOT/Library/LaunchAgents" "$SCRIPTS"

install -m 755 root.sh user.sh benex-day1 "$ROOT/usr/local/benex/"
mkdir -p "$ROOT/usr/local/benex/wallpaper"
install -m 644 wallpaper/benex.png "$ROOT/usr/local/benex/wallpaper/"
mkdir -p "$ROOT/usr/local/benex/statusline"
install -m 644 statusline/settings.json statusline/session-output.js "$ROOT/usr/local/benex/statusline/"

cat > "$ROOT/Library/LaunchAgents/com.benex.userbootstrap.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.benex.userbootstrap</string>
  <key>ProgramArguments</key><array><string>/bin/zsh</string><string>/usr/local/benex/user.sh</string></array>
  <key>RunAtLoad</key><true/>
  <key>StandardOutPath</key><string>/tmp/benex-userbootstrap.out</string>
  <key>StandardErrorPath</key><string>/tmp/benex-userbootstrap.err</string>
</dict></plist>
EOF

cat > "$SCRIPTS/postinstall" <<'EOF'
#!/bin/bash
# runs as root right after the files land
/bin/bash /usr/local/benex/root.sh || true
# kick the user part now if someone is already logged in (otherwise the LaunchAgent does it at next login)
U=$(stat -f%Su /dev/console 2>/dev/null || true)
case "$U" in ""|root|_mbsetupuser|loginwindow) ;; *)
  UID_=$(id -u "$U")
  launchctl bootstrap "gui/$UID_" /Library/LaunchAgents/com.benex.userbootstrap.plist 2>/dev/null || true ;;
esac
exit 0
EOF
chmod 755 "$SCRIPTS/postinstall"

PKG_UNSIGNED="$STAGE/benex-bootstrap-unsigned.pkg"
pkgbuild --root "$ROOT" --scripts "$SCRIPTS" --identifier com.getbenex.bootstrap --version "$VERSION" --install-location / "$PKG_UNSIGNED"

if [ -n "$SIGN_ID" ]; then
  productsign --sign "$SIGN_ID" "$PKG_UNSIGNED" "$OUT/benex-bootstrap.pkg"
  pkgutil --check-signature "$OUT/benex-bootstrap.pkg" | head -3
else
  cp "$PKG_UNSIGNED" "$OUT/benex-bootstrap.pkg"
  echo "WARNING: unsigned — fine for a local test install, NOT accepted by MDM. Re-run with your Developer ID Installer identity."
fi
rm -rf "$STAGE"

echo
echo "Package : $OUT/benex-bootstrap.pkg   (version $VERSION, bundle id com.getbenex.bootstrap)"
echo "SHA-256 : $(shasum -a 256 "$OUT/benex-bootstrap.pkg" | awk '{print $1}')"
echo
echo "Next: commit dist/benex-bootstrap.pkg to the mac-bootstrap repo (GitHub Pages), then in Apple Business:"
echo "  Devices → macOS Packages → +  →  URL https://benextechnologies.github.io/mac-bootstrap/benex-bootstrap.pkg"
echo "  bundle id com.getbenex.bootstrap, paste the SHA-256, Save → add the package to the Work Devices Blueprint."
echo "  (Apple caches by URL+hash: every rebuild = update the package entry with the new hash.)"
