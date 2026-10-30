# Agent Deck

![Agent Deck: a bar of keys that types continue, next, do it into any AI chat; it folds into an orb](docs/agent-deck.gif)

A Stream Deck for talking to AI. A bar of keys that type what you always type: *continue*, *next*, *do it*, *show me a preview first*, *stop*. One click, or ⌃⌥1…9, and the phrase lands in whatever chat is in front: Claude, ChatGPT, Cursor, Gemini, a terminal. Made by [Prompted](https://workwithprompted.com).

- A slim glass bar on the bottom of your screen, always on top, on every desktop. Drag it anywhere. It never steals the focus from your chat.
- Folds into a small orb that stays on screen; one click or ⌃⌥D brings the bar back.
- Dictate (⌃⌥M): speak, see the words appear, release and they land in the chat. On-device Spanish recognition, nothing recorded.
- Eight keys out of the box, yours in two clicks: label, text, icon, Enter or not. They live in a JSON file you own.
- Global shortcuts ⌃⌥1…9 for the keys, ⌃⌥D to fold or unfold.
- A URL scheme for Shortcuts, Raycast or a hardware Stream Deck: `open "agentdeck://press?n=1"`, `agentdeck://dictate`, `agentdeck://toggle`, `agentdeck://send?text=continue`.
- Lives in the menu bar. Opens at login if you want. No account, no network.

## Install

Download `Agent-Deck-Mac.zip` from the [latest release](https://github.com/kemet333/agent-deck/releases/latest), unzip, move **Agent Deck.app** to Applications and open it. The first time, macOS asks for **Accessibility** (System Settings → Privacy & Security → Accessibility): that is what lets the deck type into the chat. Dictation asks for the microphone and speech recognition when you first use it. Nothing else is read.

Apple Silicon, macOS 14 or newer. The build is signed locally, not notarized yet: if macOS says the app cannot be checked, right-click it and choose Open once.

## Build it yourself

Command Line Tools are enough, no Xcode project:

```bash
./build.sh
```

Six Swift files in `Sources/`: the app, menu bar and URL scheme (`AgentDeskApp.swift`), the keys and their storage (`DeskModel.swift`), the floating panel (`FloatingPanel.swift`), the interface (`DeskView.swift`), the typing into the front app (`Sender.swift`) and the dictation (`Dictation.swift`).

## How it types

The key's text goes to the clipboard, the deck presses ⌘V in the front app and, if the key says so, Enter; half a second later your previous clipboard is back. No plugin, no API key, nothing to connect: if a text box is focused, it types there.

## License

MIT. Built by [Prompted](https://workwithprompted.com), the studio behind media systems for brands.
