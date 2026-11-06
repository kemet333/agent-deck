# Agent Deck

![Agent Deck: a bar of keys that types continue, next, do it into any AI chat; it folds into an orb](docs/agent-deck.gif)

A Stream Deck for talking to AI. A bar of keys that type what you always type: *continue*, *next*, *do it*, *show me a preview first*, *stop*. One click, or ⌃⌥1…9, and the phrase lands in whatever chat is in front: Claude, ChatGPT, Cursor, Gemini, a terminal. Made by [Prompted](https://workwithprompted.com).

- A slim glass bar on the bottom of your screen, always on top, on every desktop. Drag it anywhere. It never steals the focus from your chat.
- Folds into a small orb that stays on screen; one click or ⌃⌥D brings the bar back.
- Built-in voice: hold Fn, speak and release; double-tap or Fn+Control for hands-free. OpenAI API transcription/cleanup with your own key, or the existing Apple on-device option. Paste or optional Enter, recoverable drafts, local text history and file transcription. ⌃⌥M still toggles recording.
- Eight keys out of the box, yours in two clicks: label, text, icon, Enter or not. They live in a JSON file you own.
- Global shortcuts ⌃⌥1…9 for the keys, ⌃⌥D to fold or unfold.
- Message flows for Codex desktop: repeat `next` a finite number of times or send an ordered sequence after each response. Explicit chat selection, saved flows, progress, pause and cancel; `⌃⌥F` opens flows and `⌃⌥P` pauses. Requires reviewing/trusting the bundled Codex hooks. See [setup and limits](docs/message-flows.md).
- A URL scheme for Shortcuts, Raycast or a hardware Stream Deck: `open "agentdeck://press?n=1"`, `agentdeck://dictate`, `agentdeck://toggle`, `agentdeck://send?text=continue`.
- Lives in the menu bar. Opens at login if you want. No Agent Deck account. Preset keys need no network; OpenAI voice and AI features contact OpenAI with your own API key. Apple + Verbatim uses on-device recognition where available.

## Install

1. Download **AgentBar.dmg** from the [latest release](https://github.com/kemet333/agent-deck/releases/latest) or [getagentbar.com](https://getagentbar.com).
2. Open it and drag **Agent Deck** into **Applications**, then open it from there.
3. It isn't notarized by Apple yet, so the first time macOS says it can't check it. Press **Done**, go to **System Settings → Privacy & Security**, scroll down and press **Open Anyway**.
4. A two-minute tutorial opens. It asks for **Accessibility** (to type into your chat) and, if you want to talk, the **microphone**, and sets up voice, alerts and your style. Reopen it any time from the menu → **Tutorial…**

Apple Silicon, macOS 14 or newer.

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
