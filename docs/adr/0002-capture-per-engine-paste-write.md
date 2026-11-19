# Read the selection per app engine, always write back by pasting

Fix My Words reads the selected text through Accessibility in apps where that read is trusted. In Chromium- and Electron-based apps (Chrome, Edge, Teams, and any app that ships the Electron or Chromium Embedded framework), and wherever the Accessibility read fails, it copies the selection with a guarded ⌘C instead. The fix is always written back with ⌘V, never through Accessibility writes or AppleScript. The code is in `SystemTextAccess.swift`.

This looks inconsistent, reading one way and writing another, but each half was measured:

- **Paste to write.** Accessibility writes don't work reliably across the target apps, and they lose formatting options. Pasting is the one write path that works in all of them.
- **⌘C in Chromium apps.** Chrome and Edge can be read through Accessibility, but they report the wrong text for some selections in rich editors. The copied text is what the user actually selected.

## Consequences

- The clipboard is touched once per paste, and once more per capture in Chromium apps and where the Accessibility read fails. It is saved and restored each time. Clipboard managers may still record the copied text.
- Posting ⌘C and ⌘V risks two known failures: a stray "c" typed into the document if the user still holds a modifier, and ⌘ left held after the paste. Both are guarded in `SystemTextAccess.swift`: the copy waits until every modifier key is released, and ⌘ is pressed and released as its own key. The UI tests cover the ⌘ guard. The stray-"c" guard is not yet proven in real use.
- Accessibility is still needed in every app, for the focus check that stops a paste landing in the wrong place.
