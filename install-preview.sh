#!/bin/sh
# RELEASE TEMPLATE: CI replaces every marker only after the signed helper release exists.
# Bootstrap trust is the HTTPS-delivered script. Its immutable verifier URL and
# SHA256 are embedded here; no unsigned catalog supplies executable trust.
set -eu
umask 077
version='0.1.0-preview.1'
catalog_url='https://raw.githubusercontent.com/xptea/VoidChat_public/main/versions-preview.json'
public_key='WXyktmciSitTp6LhDDCcWyOSVwCmCliFIdKD1ZTzsZk='
case "$version" in *@*) echo 'Use the generated installer from the public distribution repository.' >&2; exit 1;; esac
service=none
enable_remote=no
for option in "$@"; do
  case "$option" in --service=none) service=none;; --service=user) service=user;; --enable-remote) enable_remote=yes;; *) echo 'Usage: install.sh [--service=none|--service=user] [--enable-remote]' >&2; exit 1;; esac
done
[ "$(id -u)" -ne 0 ] || { echo 'Run as the ordinary account that will own the helper, without sudo.' >&2; exit 1; }
case "$(uname -s)" in Linux) os=linux;; Darwin) os=darwin;; *) echo 'Unsupported OS; use install.ps1 on Windows.' >&2; exit 1;; esac
case "$(uname -m)" in x86_64|amd64) arch=amd64;; aarch64|arm64) arch=arm64;; i?86) arch=386;; armv7*|armv8l) arch=arm;; *) echo 'Unsupported CPU (ARMv6 is not supported).' >&2; exit 1;; esac
if [ "$os" = darwin ] && [ "$(sysctl -n hw.optional.arm64 2>/dev/null || echo 0)" = 1 ]; then arch=arm64; fi
if [ "$os" = linux ] && [ "$(getconf LONG_BIT 2>/dev/null || echo 64)" = 32 ]; then
  case "$arch" in amd64) arch=386;; arm64) arch=arm;; esac
fi
# Both glibc and musl use the same CGO_ENABLED=0, libc-independent executables.
if [ "$os" = linux ]; then
  if command -v ldd >/dev/null 2>&1 && ldd --version 2>&1 | grep -qi musl; then libc=musl; else libc=glibc-or-static; fi
  printf 'Detected Linux %s (%s; pure-Go helper)\n' "$arch" "$libc"
fi
verifier_sha=''
case "$os-$arch" in
    darwin-amd64) verifier_sha='d3ec4d396750a6d73ec36f28b6f329bc65520a0e69379fa7428a40b4c37c609e' ;;
    darwin-arm64) verifier_sha='e8656e3be0fb8d451b7936ca58c511dc2f72e6bea134e34da10487364ad7f7d8' ;;
    linux-386) verifier_sha='46c446cfec0991b1a9267e400cebed36316ee8edabe4d68f224a454bcbb2f348' ;;
    linux-amd64) verifier_sha='4dd5cfe482418f91600f2825f3a261204ee44c0c1c5afce21c5e579e3ef65d7e' ;;
    linux-arm) verifier_sha='5d1a86f297e74fe2eae81f40d292f2899f0e086eaebc65311f88c0cf49086997' ;;
    linux-arm64) verifier_sha='166b637a8aa165ac32ac62a4b6e11fd801bbb252f837c7735f999fc7792e6000' ;;
    windows-amd64) verifier_sha='c1bded7fb5d3d67fa68c32380c3dc5156b49e4e4dbf1c0388dff8e350e0b2f46' ;;
    windows-arm64) verifier_sha='8fddc193f9aa2f2941e3cd465ca859a7fc5f3105f714ee1f266e78fe98d88a12' ;;

  *) echo 'No signed release for this platform.' >&2; exit 1;;
esac
command -v curl >/dev/null 2>&1 || { echo 'curl is required.' >&2; exit 1; }
if command -v sha256sum >/dev/null 2>&1; then hash() { sha256sum "$1" | cut -d ' ' -f1; }
elif command -v shasum >/dev/null 2>&1; then hash() { shasum -a 256 "$1" | cut -d ' ' -f1; }
else echo 'sha256sum or shasum is required.' >&2; exit 1; fi
work=$(mktemp -d "${TMPDIR:-/tmp}/voidchat-install.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
download() { curl --proto '=https' --proto-redir '=https' --tlsv1.2 --fail --silent --show-error --location --connect-timeout 15 --max-time 180 --max-filesize "$3" "$1" -o "$2"; }
verifier_name="voidchat-release-tool-$version-$os-$arch"
download "https://github.com/xptea/VoidChat_public/releases/download/helper-v$version/$verifier_name" "$work/verifier" 134217728
[ "$(hash "$work/verifier")" = "$verifier_sha" ] || { echo 'Bootstrap verifier SHA256 mismatch; nothing installed.' >&2; exit 1; }
chmod 700 "$work/verifier"
download "$catalog_url" "$work/versions.json" 1048576
"$work/verifier" resolve --catalog "$work/versions.json" --component helper --os "$os" --arch "$arch" > "$work/selected"
asset_url=$(sed -n '1p' "$work/selected")
asset_size=$(sed -n '3p' "$work/selected")
selected_version=$(sed -n '4p' "$work/selected")
download "$asset_url" "$work/helper" "$asset_size"
"$work/verifier" verify-asset --catalog "$work/versions.json" --component helper --os "$os" --arch "$arch" --file "$work/helper"
bin_dir="$HOME/.local/bin"
target="$bin_dir/voidchat-helper"
mkdir -p "$bin_dir"
if [ -f "$target" ] && [ "$(hash "$target")" != "$(hash "$work/helper")" ]; then
  echo 'An existing helper launcher differs and was preserved. Use its managed update command, or explicitly migrate that installation after active work finishes.' >&2; exit 1
fi
stage="$bin_dir/.voidchat-helper-install-$$"
cp "$work/helper" "$stage"; chmod 755 "$stage"; mv -f "$stage" "$target"
# BEGIN helper-path
register_helper_path() {
  case ":$PATH:" in *":$bin_dir:"*) return 0;; esac
  case "${SHELL:-}" in
    zsh|*/zsh) profile="$HOME/.zprofile";;
    bash|*/bash)
      if [ -f "$HOME/.bash_profile" ]; then profile="$HOME/.bash_profile"; else profile="$HOME/.profile"; fi;;
    fish|*/fish)
      printf 'Add the helper to your fish PATH manually: fish_add_path "$HOME/.local/bin"\n'
      return 0;;
    *)
      printf 'Add %s to PATH using your shell configuration. Helper executable: %s\n' "$bin_dir" "$target"
      return 0;;
  esac
  marker='# VoidChat per-user helper path'
  if ! grep -F "$marker" "$profile" >/dev/null 2>&1; then
    printf '\n%s\n%s\n' "$marker" 'case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH" ;; esac' >> "$profile"
  fi
  printf 'New login shells load %s from %s; current shell: export PATH="$HOME/.local/bin:$PATH"\n' "$target" "$profile"
}
# END helper-path
register_helper_path
if [ "$service" = user ]; then
  if [ "$os" = linux ]; then
    command -v systemctl >/dev/null 2>&1 || { echo 'systemd user services are unavailable; rerun with --service=none.' >&2; exit 1; }
    mkdir -p "$HOME/.config/systemd/user"
    unit="$HOME/.config/systemd/user/voidchat-helper.service"
    printf '[Unit]\nDescription=VoidChat per-user helper login startup\n[Service]\nType=oneshot\nRemainAfterExit=yes\nExecStart="%s" start\nExecStop="%s" stop\nKillMode=control-group\nTimeoutStopSec=15\n[Install]\nWantedBy=default.target\n' "$target" "$target" > "$unit"
    systemctl --user daemon-reload; systemctl --user enable --now voidchat-helper.service
    echo 'User login startup enabled (not crash supervision). This installer does not enable systemd lingering.'
  else
    mkdir -p "$HOME/Library/LaunchAgents"
    plist="$HOME/Library/LaunchAgents/seths.app.voidchat.helper.plist"
    # HOME paths with XML metacharacters need an explicit manual LaunchAgent.
    case "$target" in *'&'*|*'<'*|*'>'*) echo 'Create a LaunchAgent manually for this home path.' >&2; exit 1;; esac
    printf '<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>Label</key><string>seths.app.voidchat.helper</string><key>ProgramArguments</key><array><string>%s</string><string>start</string></array><key>RunAtLoad</key><true/><key>KeepAlive</key><false/></dict></plist>\n' "$target" > "$plist"
    launchctl bootout "gui/$(id -u)/seths.app.voidchat.helper" >/dev/null 2>&1 || true
    launchctl bootstrap "gui/$(id -u)" "$plist"
  fi
else "$target" start; fi
printf 'Installed helper %s (catalog key primary: %s).\n' "$selected_version" "$public_key"
# BEGIN pairing-readiness
pairing_ready() {
  attempt=0
  while [ "$attempt" -lt 30 ]; do
    if "$target" invite > "$work/pairing.txt" 2>/dev/null; then cat "$work/pairing.txt"; return 0; fi
    attempt=$((attempt + 1))
    [ "$attempt" -ge 30 ] || sleep 1
  done
  echo 'Helper installed, but its Tailscale listener is not ready. Install/sign in to Tailscale, then run voidchat-helper invite. No login or network policy was changed.' >&2
  return 1
}
# END pairing-readiness
if [ "$enable_remote" = yes ]; then
  "$target" enable
  pairing_ready
else
  echo 'Remote access was not changed (off on a first install). To pair this host, rerun with --enable-remote after signing in to Tailscale.'
fi
