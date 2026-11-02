# Agent Deck

![Agent Deck: a bar of keys that types continue, next, do it into any AI chat; it folds into an orb](docs/agent-deck.gif)

A Stream Deck for talking to AI. A bar of keys that type what you always type: *continue*, *next*, *do it*, *show me a preview first*, *stop*. One click, or ⌃⌥1…9, and the phrase lands in whatever chat is in front: Claude, ChatGPT, Cursor, Gemini, a terminal. Made by [Prompted](https://workwithprompted.com).

- A slim glass bar on the bottom of your screen, always on top, on every desktop. Drag it anywhere. It never steals the focus from your chat.
- Folds into a small orb that stays on screen; one click or ⌃⌥D brings the bar back.
- Built-in voice: hold Fn, speak and release; double-tap or Fn+Control for hands-free. OpenAI API transcription/cleanup with your own key, or the existing Apple on-device option. Paste or optional Enter, recoverable drafts, local text history and file transcription. ⌃⌥M still toggles recording.
- Eight keys out of the box, yours in two clicks: label, text, icon, Enter or not. They live in a JSON file you own.
- Global shortcuts ⌃⌥1…9 for the keys, ⌃⌥D to fold or unfold.
- A URL scheme for Shortcuts, Raycast or a hardware Stream Deck: `open "agentdeck://press?n=1"`, `agentdeck://dictate`, `agentdeck://toggle`, `agentdeck://send?text=continue`.
- Lives in the menu bar. Opens at login if you want. No Agent Deck account. Preset keys need no network; OpenAI voice and AI features contact OpenAI with your own API key. Apple + Verbatim uses on-device recognition where available.

## Install

Download `Agent-Deck-Mac.zip` from the [latest release](https://github.com/kemet333/agent-deck/releases/latest), unzip, move **Agent Deck.app** to Applications and open it. The first time, macOS asks for **Accessibility** (System Settings → Privacy & Security → Accessibility): that is what lets the deck type into the chat. Voice asks for the microphone when first used; the Apple engine additionally needs Speech Recognition. OpenAI mode uploads the recording, and AI cleanup/selection edits send their text to OpenAI. Voice settings keep the API key in macOS Keychain. The explicit text target/selection is checked through Accessibility; the app does not read other files or notes as voice context.

Apple Silicon, macOS 14 or newer. The build is signed locally, not notarized yet: if macOS says the app cannot be checked, right-click it and choose Open once.

## Build it yourself

Command Line Tools are enough, no Xcode project:

```bash
./build.sh
```

The app, menu bar and URL scheme are in `AgentDeskApp.swift`; keys/storage in `DeskModel.swift`; floating panel and glass UI in `FloatingPanel.swift` and `DeskView.swift`. The voice controller, native recorder/shortcuts, OpenAI client, Keychain and workspace have separate `Voice*.swift` files. See [voice features, privacy and remaining parity](docs/voice.md). Run `zsh test.sh` for synthetic checks without microphone, real API or external messages.

## How it types

Preset keys still paste into the focused text field and optionally press Enter. Voice captures the original target before recording; a changed target keeps a draft. Clipboard contents are restored only if another app has not changed them. Voice also offers direct Accessibility insertion and optional Enter after verification. See [the voice guide](docs/voice.md) for requirements and limits.

## License

MIT. Built by [Prompted](https://workwithprompted.com), the studio behind media systems for brands.
