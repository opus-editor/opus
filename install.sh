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

say ""
say "Opus is installed."
say "  Run it:     flatpak run $app_id   (or from your app launcher)"
say "  Update it:  run this script again"
say "  Remove it:  flatpak uninstall --user $app_id"
