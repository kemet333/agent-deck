# Agent Desk

A Stream Deck for talking to AI. A floating palette of keys that type what you always type: *continue*, *next*, *do it*, *show me a preview first*, *stop*. One click, or ⌃⌥1…9, and the phrase lands in whatever chat is in front: Claude, ChatGPT, Cursor, Gemini, a terminal. Made by Kemet Capital.

- Floating, always on top, on every desktop. Never steals the focus from your chat.
- Eight keys out of the box, yours in two clicks: label, text, Enter or not.
- Global shortcuts ⌃⌥1…9; ⌃⌥D shows or hides the desk.
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

Sources are five Swift files in `Sources/`: the app and menu bar (`AgentDeskApp.swift`), the keys and their storage (`DeskModel.swift`), the floating panel (`FloatingPanel.swift`), the interface (`DeskView.swift`) and the typing into the front app (`Sender.swift`).

## How it types

The key's text goes to the clipboard, the desk presses ⌘V in the front app and, if the key says so, Enter; half a second later your previous clipboard is back.
