# MultiClip

Native macOS menubar app. Captures every ⌘C into a rolling history (last 50,
deduped). Press ⇧⌘P to open a picker, click clips in the order you want them
pasted, hit Enter — joined text is pasted into the destination app.

## Features

**Rich content types.** RTF, HTML, images, file URLs, and colors are captured in
their original pasteboard flavor, not flattened to text. Each row carries a type
badge, the preview pane renders images, swatches, and file icons, and pasting a
single clip restores the original flavor. Selecting several clips joins their
text with the chosen separator.

**Fuzzy search.** The picker's search field filters live. Queries are tokenized
on whitespace and path punctuation, so `sources/picker` searches for `sources`
and `picker` independently; every token must match, and results are ranked by
match quality (exact word → word prefix → substring → fuzzy subsequence). File
clips match on any single path component, snippet names are weighted highest,
and the type badge is searchable (`img`, `file`, `rtf`).

**Encrypted persistent history.** Off by default. **Enable Encrypted Persistent
History…** in the menubar asks for a passphrase, then moves history into a
SQLite database where each clip is encrypted with AES-GCM under a key derived
from it. The passphrase lives in your Keychain, the plaintext `history.json` is
deleted on switchover, history survives reboots, and the cap rises from 50 to
5000 clips. Disabling deletes the database and trims back to the most recent 50.

**Named snippets.** Right-click any clip → **Pin as Snippet…** to give it a name.
Snippets never expire — clearing history and eviction both skip them — and
⇧⌘S opens the picker filtered to just snippets. Right-click a snippet to rename
or unpin it.

## Build

    swift build -c release

The binary lands at `.build/release/MultiClip`.

## Run

Foreground (blocks the terminal, Ctrl-C to quit):

    .build/release/MultiClip

Background (detach from the terminal, keep running after it closes):

    nohup .build/release/MultiClip >/dev/null 2>&1 &

It runs as a menubar-only app (📋 icon, no Dock tile).

Check whether it's running:

    pgrep -lf MultiClip

Stop it:

    pkill -f MultiClip

…or use **Quit** from the menubar icon.

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
plain-text file, separated by blank lines), **Clear History** (keeps pinned
snippets), **Enable/Disable Encrypted Persistent History**, and **Quit**.

Storage lives in `~/Library/Application Support/MultiClip/` — `history.json`
by default, or `history.sqlite` when encrypted persistence is on.
