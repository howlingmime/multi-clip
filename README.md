# MultiClip

Native macOS menubar app. Captures every ⌘C into a rolling history (last 50,
deduped). Press ⇧⌘P to open a picker, click clips in the order you want them
pasted, hit Enter — joined text is pasted into the destination app.

## Build

    swift build -c release

The binary lands at `.build/release/MultiClip`.

## Run

    .build/release/MultiClip

It runs as a menubar-only app (📋 icon, no Dock tile).

### Accessibility permission

Synthesizing the ⌘V keystroke requires Accessibility access. On first launch
macOS will prompt; if it doesn't, open **System Settings → Privacy & Security →
Accessibility**, click `+`, add the `MultiClip` binary, and toggle it on.

Whichever process runs the binary needs the permission — if you launch from
Terminal/iTerm, Terminal/iTerm itself needs Accessibility access.

For a friendlier setup, wrap the binary in a `.app` bundle (drop the executable
into `MultiClip.app/Contents/MacOS/` with a minimal `Info.plist` that sets
`LSUIElement = true`) and grant the bundle Accessibility access directly.

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
