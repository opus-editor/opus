#!/bin/sh
# Installs Opus as a per-user Flatpak from the latest GitHub release:
#
#   curl -fsSL https://raw.githubusercontent.com/opus-editor/opus/main/install.sh | sh
#
# Never asks for a password: everything is --user. Re-running it
# updates an existing install in place.
#
#   OPUS_VERSION=v0.2.0   install that release instead of the latest
#   OPUS_BUNDLE=./Opus.flatpak   install a local bundle, no download
set -eu

app_id="io.github.opus_editor.Opus"
repo="opus-editor/opus"
version="${OPUS_VERSION:-latest}"

say() { printf '%s\n' "$*"; }
fail() {
  say "install.sh: $*" >&2
  exit 1
}

if ! command -v flatpak >/dev/null 2>&1; then
  say "install.sh: Opus is distributed as a Flatpak, and 'flatpak' is not installed." >&2
  say "Install it with your distribution's package manager, then run this again:" >&2
  say "  Debian/Ubuntu:  sudo apt install flatpak" >&2
  say "  Fedora:         sudo dnf install flatpak" >&2
  say "  Arch:           sudo pacman -S flatpak" >&2
  say "  openSUSE:       sudo zypper install flatpak" >&2
  exit 1
fi

# The bundle carries Opus only; its GNOME runtime comes from Flathub.
flatpak remote-add --user --if-not-exists flathub \
  https://dl.flathub.org/repo/flathub.flatpakrepo

if [ -n "${OPUS_BUNDLE:-}" ]; then
  [ -f "$OPUS_BUNDLE" ] || fail "no such file: $OPUS_BUNDLE"
  bundle="$OPUS_BUNDLE"
else
  command -v curl >/dev/null 2>&1 || fail "'curl' is required to download the release."
  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "$tmp_dir"' EXIT INT TERM
  bundle="$tmp_dir/Opus.flatpak"
  if [ "$version" = "latest" ]; then
    url="https://github.com/$repo/releases/latest/download/Opus.flatpak"
  else
    url="https://github.com/$repo/releases/download/$version/Opus.flatpak"
  fi
  say "Downloading Opus ($version)..."
  curl -fsSL -o "$bundle" "$url" || fail "download failed: $url"
fi

say "Installing..."
flatpak install --user -y --noninteractive --reinstall "$bundle"

# `opus` on the PATH: a wrapper around `flatpak run`, which also owns
# `opus --update` and `opus --uninstall` — both have to run on the
# host, where they can reach GitHub, the Flatpak, the app's data and
# the wrapper itself; the sandboxed app can't. Written to a temp file
# and moved into place: `opus --update` runs this very script, and a
# shell script must never be overwritten while it is executing — mv
# swaps the inode, the running copy keeps reading the old one.
bin_dir="${XDG_BIN_HOME:-$HOME/.local/bin}"
mkdir -p "$bin_dir"
cat >"$bin_dir/opus.tmp" <<EOF
#!/bin/sh
# Opus — written by install.sh. \`opus --update\` / \`opus --uninstall\`.
app_id="$app_id"
install_url="https://raw.githubusercontent.com/$repo/main/install.sh"
case "\$1" in
--uninstall)
  flatpak uninstall --user -y --noninteractive --delete-data "\$app_id"
  rm -f "\$0"
  echo "Opus removed."
  exit 0
  ;;
--update)
  command -v curl >/dev/null 2>&1 || { echo "opus: 'curl' is required to check for updates." >&2; exit 1; }
  installed=\$(flatpak info --user "\$app_id" 2>/dev/null | sed -n 's/^ *Version: *//p')
  # The release page's redirect ends in /tag/vX.Y.Z — no API, no token.
  latest=\$(curl -fsSI "https://github.com/$repo/releases/latest" | sed -n 's/^[Ll]ocation:.*\\/tag\\/v\\([^[:space:]]*\\).*/\\1/p')
  [ -n "\$latest" ] || { echo "opus: could not reach GitHub to check the latest release." >&2; exit 1; }
  if [ "\$installed" = "\$latest" ]; then
    echo "Opus \$installed is up to date."
    exit 0
  fi
  echo "Opus \$installed installed, \$latest is the latest release — updating..."
  exec sh -c "curl -fsSL '\$install_url' | sh"
  ;;
esac
if ! flatpak info --user "\$app_id" >/dev/null 2>&1; then
  echo "opus: Opus is no longer installed; removing this launcher." >&2
  rm -f "\$0"
  exit 1
fi
exec flatpak run "\$app_id" "\$@"
EOF
chmod +x "$bin_dir/opus.tmp"
mv -f "$bin_dir/opus.tmp" "$bin_dir/opus"

say ""
say "Opus is installed."
say "  Run it:     opus [folder]   (or from your app launcher)"
say "  Update it:  opus --update"
say "  Remove it:  opus --uninstall"
case ":$PATH:" in
*":$bin_dir:"*) ;;
*)
  say ""
  say "Note: $bin_dir is not on your PATH yet — open a new terminal, or add it to your shell's profile."
  ;;
esac
