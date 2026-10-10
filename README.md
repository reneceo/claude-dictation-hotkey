# claude-dictation-hotkey

**A keyboard shortcut for the microphone button in the Claude desktop app — on macOS, using Claude's own transcription.**

Hold a key, speak, release. No mouse. No third‑party dictation app.

Everyone who has looked into this concluded it was impossible. It isn't — it just needs one undocumented accessibility flag.

---

## The problem

The Claude desktop app has a microphone button in the Code tab's input bar. It is **mouse‑click only**. There is no keyboard shortcut, and the usual ways of adding one all fail:

| What you try | What happens |
| --- | --- |
| `/voice` | `/voice isn't available in this environment.` — it's a CLI‑only feature |
| `~/.claude/keybindings.json` → `voice:pushToTalk` | No effect. The keybindings file applies to the terminal CLI, not the desktop app |
| AppleScript / System Events | Finds nothing. The button isn't in the accessibility tree |
| Hammerspoon with `hs.axuielement` | Same — finds nothing |
| AutoHotkey (Windows) visually locating the icon | Works until you move or resize the window |

This has been asked for repeatedly and is still open:
[#97929](https://github.com/anthropics/claude-code/issues/97929) ·
[#48305](https://github.com/anthropics/claude-code/issues/48305) ·
[#59400](https://github.com/anthropics/claude-code/issues/59400) ·
[#92402](https://github.com/anthropics/claude-code/issues/92402) ·
[#90576](https://github.com/anthropics/claude-code/issues/90576) ·
[#96340](https://github.com/anthropics/claude-code/issues/96340)

## The fix

The mic button lives inside an **Electron WebArea**, and Chromium does not expose web content to the macOS accessibility API until something asks it to. Walk the app's accessibility tree cold and you get about **292 nodes — menu bar and window chrome only**. The button genuinely isn't there.

Set one attribute on the application element:

```swift
AXUIElementSetAttributeValue(axApp, "AXManualAccessibility" as CFString, kCFBooleanTrue)
```

and the tree jumps to roughly **840 nodes**, two `AXWebArea` nodes appear, and the control is right there:

```
AXGroup        desc="Press and hold to record"
  AXCheckBox      desc="Press and hold to record"    actions: AXPress ✅
  AXPopUpButton   desc="Dictation settings"
```

`AXPress` on the checkbox toggles recording. That's the whole trick.

Because the element is found **by its accessibility description at runtime** rather than by screen coordinates, it keeps working when you move the window, resize it, or switch monitors — the exact failure mode that made the coordinate‑clicking workarounds unusable.

## Do you still need Wispr Flow?

**If you only use Wispr Flow (or Fluid Voice, or Superwhisper) to talk to Claude — no.**

That was the motivation here. Claude's built‑in dictation is already good, and for coding it's arguably better: transcription is tuned for development vocabulary, so `regex`, `OAuth`, `JSON` and `localhost` come out right, and your project and branch names are fed in as recognition hints. It costs no tokens and doesn't count toward your usage limits.

The only thing the paid tools had that Claude's didn't was **a hotkey**. That's what this repo adds.

If you dictate into Slack, email, Notion and your IDE all day, keep your dictation app — it works everywhere and this doesn't. But if you looked at that subscription and realised the only window you ever use it in is Claude, you can drop it.

A nice side effect: you can point this at the *same key* your old tool used, so there's no muscle memory to relearn. Caps Lock works here too, which Claude Code's own keybindings can't do.

## Requirements

- macOS
- [Hammerspoon](https://www.hammerspoon.org/) — `brew install --cask hammerspoon`
- The Claude desktop app, signed in
- Accessibility permission for Hammerspoon

## Install

```bash
brew install --cask hammerspoon
curl -o ~/.hammerspoon/init.lua \
  https://raw.githubusercontent.com/code22d/claude-dictation-hotkey/main/init.lua
open -a Hammerspoon
```

If you already have an `init.lua`, append the contents of [`init.lua`](init.lua) to it instead of overwriting.

Then:

1. Grant Hammerspoon **Accessibility** access when prompted (System Settings → Privacy & Security → Accessibility). This is a broad permission — Hammerspoon can control anything on your Mac. Read the config before you enable it; it's ~110 commented lines.
2. Reload: Hammerspoon menu bar icon → **Reload Config**, or `killall Hammerspoon && open -a Hammerspoon`.
3. Put your cursor in the Claude input and **hold Right Option**.

You should see a `● recording` flash. Speak, release, done.

## Changing the key

The default is **Right Option**. Edit `RIGHT_OPTION` in `init.lua`:

| Key | Code |
| --- | --- |
| Right Option | `61` *(default)* |
| Left Option | `58` |
| Right Command | `54` |
| Left Control | `59` |
| Right Shift | `60` |
| Caps Lock | `57` |

Then reload Hammerspoon.

**Using a modifier alone as a hotkey has a catch:** Option is also the accent‑composition key, so a naive binding fires every time you type `é` or `ñ`. The config guards against this with a 150 ms arm delay plus cancel‑on‑other‑keypress — a deliberate hold triggers dictation, a composition keystroke doesn't. The key is never swallowed, so Option+letter still types normally. Tune `ARM_DELAY` if your typing trips it.

If your old dictation app is still installed, **change its hotkey first** — global hotkeys are grabbed before Hammerspoon sees them, and you'll think this is broken when it's actually being intercepted.

## Troubleshooting

**`Claude mic not found`** — the lookup failed. Usual causes: the Claude app isn't running, Accessibility isn't granted to Hammerspoon, or the button's accessibility description changed in an app update. Run the probes below to see the current tree.

**Nothing happens at all** — Accessibility not granted, or the config wasn't reloaded after granting. The running instance doesn't pick up the permission by itself.

**Your old dictation app opens instead** — its global hotkey is intercepting. Change it or quit the app.

**It worked, then stopped after an update** — most likely the description string moved. Edit `MIC_DESC` in `init.lua` to whatever `probes/03-inspect-mic-element.swift` reports.

## Probes

The [`probes/`](probes) directory has the three read‑only Swift scripts used to find this, which are useful for adapting the technique to any Electron app:

| Script | Shows |
| --- | --- |
| `01-bare-walk.swift` | The cold tree — ~292 nodes, no web content. The dead end everyone hits |
| `02-manual-accessibility.swift` | The same walk after `AXManualAccessibility` — ~840 nodes, web content visible |
| `03-inspect-mic-element.swift` | The mic element's supported actions and frame |

Run with `swift probes/01-bare-walk.swift`. No dependencies; `/usr/bin/swift` ships with Xcode command line tools. They only read — nothing is clicked.

## Adapting this to other Electron apps

The `AXManualAccessibility` gate is **not Claude‑specific**. It's a Chromium behaviour, so the same approach reaches UI inside Slack, Discord, VS Code, Notion, Figma, Linear, Obsidian, Spotify and any other Electron app whose controls appear unreachable to AppleScript or Hammerspoon.

The recipe: set the flag on the app element, walk the tree for a stable `AXDescription` or `AXTitle`, then `performAction("AXPress")`. Swap the bundle ID and the description string in `init.lua`.

## Caveats

- Unofficial, and depends on an accessibility description Anthropic can change at any time. If that happens it's a one‑line fix, not a rewrite.
- macOS only. The same gate exists on Windows via UI Automation, but this config doesn't cover it.
- Accessibility access is a powerful permission. Read the config first.
- If Anthropic ships a native shortcut, delete this and use theirs. 👍 [#97929](https://github.com/anthropics/claude-code/issues/97929) to help that happen.

## License

MIT — see [LICENSE](LICENSE).

---

<details>
<summary><strong>Keywords</strong> — the searches that currently return "it can't be done"</summary>

Claude Code voice dictation keyboard shortcut · Claude desktop app microphone hotkey · Claude desktop push to talk · `/voice isn't available in this environment` · `voice:pushToTalk` not working desktop app · `keybindings.json` no effect Claude desktop · Claude Code dictation shortcut macOS · keyboard shortcut for Claude mic button · Claude desktop mic button mouse only · Wispr Flow alternative for Claude Code · Fluid Voice alternative · Superwhisper alternative Claude · stop paying for dictation app Claude · Claude built-in dictation hotkey · Hammerspoon Claude dictation · Hammerspoon Electron accessibility · `AXManualAccessibility` Electron · Electron WebArea not in accessibility tree · AppleScript can't find Electron buttons · `hs.axuielement` Electron empty tree · AXUIElement Chromium web content hidden · macOS accessibility API Electron app automation · AutoHotkey Claude microphone click · bind modifier key to button click macOS · right Option key hotkey Hammerspoon · push to talk hotkey macOS app · anthropics/claude-code#97929 · anthropics/claude-code#48305

</details>
