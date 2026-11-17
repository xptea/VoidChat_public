#!/bin/sh
# RELEASE TEMPLATE: CI replaces every marker only after the signed helper release exists.
# Bootstrap trust is the HTTPS-delivered script. Its immutable verifier URL and
# SHA256 are embedded here; no unsigned catalog supplies executable trust.
set -eu
umask 077
version='0.1.2'
catalog_url='https://raw.githubusercontent.com/xptea/VoidChat_public/main/versions.json'
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
printf 'Installing VoidChat helper...\n'
verifier_sha=''
case "$os-$arch" in
    darwin-arm64) verifier_sha='842ed70f783687566f4e1cf3570237da5e2d6e856c2580ecbb9dce50a3e37fe3' ;;
    linux-386) verifier_sha='fead152f270e26930babbaa4cff7305c685870e46993f4112de93ab793369d68' ;;
    linux-amd64) verifier_sha='90f065f770c457d1f1de89dd0e1bb45d823172250786216cb4e815c53b818687' ;;
    linux-arm) verifier_sha='4147061a88bd5c883d6a11372f91a44b145133eec0cbaa5189ff6a3b338d5d62' ;;
    linux-arm64) verifier_sha='653c71ae785b9c3b756a2f2be80e4e19f1565496b9e2d2e3b45c9e7abaf07b7a' ;;
    windows-amd64) verifier_sha='fea6033e96e8eb65d714b4ce85001cfb08ed5078191c75aa5e98b317282bf35c' ;;

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
"$work/verifier" verify-asset --catalog "$work/versions.json" --component helper --os "$os" --arch "$arch" --file "$work/helper" > /dev/null
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
  printf 'Command added to PATH for new login shells.\n'
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
else "$target" start > /dev/null; fi
printf '\nVoidChat helper %s installed.\n' "$selected_version"
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
  echo 'To pair this computer, run: voidchat-helper enable && voidchat-helper invite'
fi
