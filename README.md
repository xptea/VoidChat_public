# VoidChat downloads

Download Windows installers and macOS disk images from [Releases](https://github.com/xptea/VoidChat_public/releases).
Desktop and helper releases have independent versions (`desktop-v...` and `helper-v...`).
This repository distributes binaries; application source is maintained separately.

Preview builds have signed update metadata and desktop update archives, but do
not yet have Windows Authenticode or Apple Developer ID/notarization. They may
show operating-system warnings. Preview and stable update channels are separate.

## Install a remote helper

Use an ordinary user account, without sudo or an elevated terminal. Install/sign
in to Tailscale on both computers. To run agent chats, install Codex and sign in
as the helper's user on the accepting computer. The installer does not change
network policy or install/sign in to those third-party tools.

Linux/macOS preview helper, with inbound access explicitly enabled:

```sh
curl -fsSL https://raw.githubusercontent.com/xptea/VoidChat_public/main/install-preview.sh | sh -s -- --enable-remote
```

Windows preview helper, from an ordinary PowerShell terminal:

```powershell
& ([scriptblock]::Create((Invoke-RestMethod 'https://raw.githubusercontent.com/xptea/VoidChat_public/main/install-preview.ps1'))) -EnableRemote
```

The installer detects OS/CPU, verifies its pinned bootstrap verifier, verifies
the signed catalog and helper, and starts it. Once Tailscale is ready it prints
the computer address, short pairing code and expiry. Enter the address and code
in VoidChat -> Settings -> Connections -> Remote computers -> Add computer.
Do not share the pairing code publicly.

Omit `--enable-remote` / `-EnableRemote` for controller-only installation.
Optional `--service=user` / `-Service User` adds login startup; it is not
continuous crash supervision. Linux boot/logout behavior follows existing
systemd user/lingering policy. The installer does not enable lingering.

## Manage it from a terminal

```sh
voidchat-helper status
voidchat-helper invite
voidchat-helper update-status
voidchat-helper update-check
voidchat-helper update
voidchat-helper update-auto --enabled=false
```

Windows uses the same command name and arguments. A new terminal may be needed
after PATH registration. Updates check the signed channel roughly every twelve
hours, reuse cached results on connection activity and defer application while
work is active or its idle state is unknown. Desktop updates offer an explicit
restart; helper updates do not require reinstalling the desktop.

The installer preserves an existing different launcher. Use the managed update
command for later versions, rather than overwriting a running installation.
Signed catalogs are `versions-preview.json` and, when a stable release exists,
`versions.json`. Dependency notices accompany the release artifacts and are also
available through `voidchat-helper licenses`.
