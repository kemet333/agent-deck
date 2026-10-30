# Agent Desk

A Stream Deck for talking to AI. A floating palette of keys that type what you always type: *continue*, *next*, *do it*, *show me a preview first*, *stop*. One click, or ⌃⌥1…9, and the phrase lands in whatever chat is in front: Claude, ChatGPT, Cursor, Gemini, a terminal. Made by Kemet Capital.

- Dock mode: a slim bar at the bottom of the screen, centered, always on top, on every desktop. Or a floating card, from the menu bar. Never steals the focus from your chat.
- Eight keys out of the box, yours in two clicks: label, text, Enter or not.
- Folds into a small glass orb that stays on screen; one click or ⌃⌥D brings the bar back.
- Dictate (⌃⌥M): speak, see the words appear, release and they land in the chat. On-device Spanish recognition, nothing recorded.
- Global shortcuts ⌃⌥1…9 for the keys, ⌃⌥D to fold or unfold.
- A URL scheme for Shortcuts, Raycast or a hardware Stream Deck: `open "agentdesk://press?n=1"`, `agentdesk://dictate`, `agentdesk://toggle`, `agentdesk://send?text=continue`.
- Lives in the menu bar. Opens at login if you want.
- Your keys stay in `~/Library/Application Support/Agent Desk/keys.json`. No account, no network.

## Install

Download `Agent-Desk-Mac.zip`, unzip, move **Agent Desk.app** to Applications and open it. The first time, macOS asks for **Accessibility** (System Settings → Privacy & Security → Accessibility): that is what lets the desk type into the chat. Nothing else is read.

Apple Silicon, macOS 14 or newer.

## Build it yourself

Command Line Tools are enough, no Xcode project:

```bash
./build.sh
```

Sources are six Swift files in `Sources/`: the app, menu bar and URL scheme (`AgentDeskApp.swift`), the keys and their storage (`DeskModel.swift`), the floating panel (`FloatingPanel.swift`), the interface (`DeskView.swift`), the typing into the front app (`Sender.swift`) and the dictation (`Dictation.swift`).

## How it types

The key's text goes to the clipboard, the desk presses ⌘V in the front app and, if the key says so, Enter; half a second later your previous clipboard is back.
