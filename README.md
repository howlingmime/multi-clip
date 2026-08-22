# MultiClip

Native macOS menubar app. Captures every ⌘C into a rolling history (last 50,
deduped). Press ⇧⌘P to open a picker, click clips in the order you want them
pasted, hit Enter — joined text is pasted into the destination app.

## Install

    ./scripts/package.sh            # builds + bundles into ~/Applications/MultiClip.app
    ./scripts/launchagent.sh install  # start it now, and at every login

Then grant Accessibility (see below). That's the whole setup.

`package.sh` takes an optional destination (`./scripts/package.sh /Applications`).
Rebuilding after a code change is `package.sh` again followed by
`launchagent.sh install`, which restarts the running copy.

Two environment overrides, both optional: `MULTICLIP_BUNDLE_ID` (defaults to
`dev.howlingmime.MultiClip`) and `CODESIGN_IDENTITY`, if you have several
certificates and want a specific one.

To back out completely:

    ./scripts/launchagent.sh uninstall
    rm -rf ~/Applications/MultiClip.app

It runs as a menubar-only app (📋 icon, no Dock tile).

### Accessibility permission

Synthesizing the ⌘V keystroke requires Accessibility access. Open **System
Settings → Privacy & Security → Accessibility** and toggle **MultiClip** on.
Everything else — capturing clips, the picker, saving history — works without
it; only the final paste keystroke needs it.

This is why the app is bundled and code-signed rather than run as a bare
binary. macOS grants Accessibility to a *code identity*, not a file path:

- A bare `.build/release/MultiClip` run from a terminal has no identity of its
  own, so the permission has to be granted to Terminal/iTerm — which then lets
  *anything* you run from a shell synthesize keystrokes.
- An ad-hoc signature changes hash on every rebuild, so macOS revokes the grant
  each time you rebuild.

`package.sh` signs with a stable Developer identity when one is installed
(`security find-identity -v -p codesigning`), so you grant it once and rebuilds
keep working. Without an identity it falls back to ad-hoc and warns.

## Running as a service

The LaunchAgent (`~/Library/LaunchAgents/dev.howlingmime.MultiClip.plist`) is the
recommended way to run it: a clipboard history is only useful if it was running
*before* you copied something, so anything short of always-on loses clips.

    ./scripts/launchagent.sh status      # is it running?
    ./scripts/launchagent.sh uninstall   # stop and remove

**Quit** from the menubar icon stays quit until the next login — the agent uses
`KeepAlive: SuccessfulExit = false`, so it relaunches after a crash but respects
a deliberate quit. It also appears under **System Settings → General → Login
Items → Allow in the Background** if you want to toggle it from the UI.

Logs go to `~/Library/Logs/MultiClip.log`.

## Hacking on it

`swift build -c release` on its own still works and drops a binary at
`.build/release/MultiClip`, which is fine for a quick compile check. To actually
exercise the paste path you need the signed bundle, so use `package.sh` — a bare
binary can't hold its own Accessibility grant (see above).

## Use

1. Copy a few things with ⌘C (anywhere).
2. Focus the destination doc.
3. Press ⇧⌘P — picker appears.
4. Click clips in the order you want them pasted. The badge shows the order.
5. Pick a separator (newline by default), hit Enter.
6. The picker closes, the previous app regains focus, and the joined text is
   pasted at the cursor.

Esc cancels. Menubar icon has **Save History…** (exports all clips to a
plain-text file, separated by blank lines), **Clear History**, and **Quit**.
