# Message flows for Codex desktop

Agent Deck can schedule a finite number of continuations for one selected Codex chat:

- Repeat the exact same message 1–50 times, for example `siguiente` five times.
- Send an ordered sequence of 1–50 messages, with multiline text and editable order.
- Save up to 30 definitions; pause, resume or cancel the current run.

One message is emitted after each Codex response finishes. Five repetitions means five additional prompts, not five prompts inserted together. The last response must finish before the run is marked completed. This is completion of the **sequence**, not verification that project tasks are done.

## Connection and first run

1. Open **Flows** from the glass bar, card footer, menu bar or `⌃⌥F`. It is also available in the app's Settings.
2. Choose **Connect Codex…** and review the in-app confirmation. The app creates `~/.codex/hooks.json` only if absent, using atomic exclusive publication. An existing file is never replaced: in that case, the app exports only its own `Agent Deck/Flows/Codex-hooks-fragment.json` for a reviewed manual merge. Repeating setup preserves the existing configuration too.
3. In Codex, review/trust the exact hooks in **Settings → Hooks**. New or changed hooks must be reviewed again. The app never bypasses that trust check, enables disabled features, edits `config.toml` or changes approval policies. A restart may be needed in versions that do not reload hooks.
4. Send a normal task in Codex. Its directory and session identifier appear in Agent Deck. Select that chat explicitly. No chat history or desktop database is imported.
5. Choose the repeat count or ordered messages, then **Schedule flow**. If the chat is idle, first send its initial task manually; no automatic prompt is sent just by scheduling.

The connector is a native signed helper bundled with Agent Deck. No API key, server or Python installation is required. Automatic continuations consume the selected Codex account's normal quota.

## Completion source

The integration uses Codex's documented `Stop` command hook. Its JSON response `{ "decision": "block", "reason": "<your exact next message>" }` requests a continuation. This is a Codex continuation prompt; it is **not** a simulated keypress or a timer guessing that a response has finished. The host controls how that prompt appears in its UI.

`UserPromptSubmit` confirms expected prompts. Hosts may continue inside one turn using `stop_hook_active`; the reducer also supports that documented case after a distinct completion. Duplicated completion fingerprints pause the run without consuming another step. Each run is bound to a session ID **and** directory.

Sources, checked 3 November 2026:

- [Codex hooks: Stop and trust](https://learn.chatgpt.com/docs/hooks)
- [Codex app server: turn completion differs from tool completion](https://learn.chatgpt.com/docs/app-server)

## Pause and recovery

- `PermissionRequest` pauses the flow and returns no approval decision.
- Recognized `request_user_input`, `request_user_input_async` and `AskUserQuestion` tool events pause it. Plain-language questions in final text are not classified by a model.
- Interruptions, model failure/cancellation events, session end/resume, a changed directory or unexpected user message pause it.
- A new manual message is never rewritten or blocked by this connector. Resolve the chat, then explicitly resume if appropriate.
- Runs expire after 24 hours and use a 15-second Agent Deck heartbeat. Closing/restarting the app pauses active runs; lost heartbeats prevent new emissions. A message already handed to Codex cannot be recalled by pausing.
- `⌃⌥P`, the menu item or the flow window pauses future messages. Cancel does not interrupt Codex's currently running work.
- Persistent progress is consumed before returning a continuation. If the helper or host fails after that write, a step may have been issued without delivery; the app reports **issued continuations**, not guaranteed task execution. Review the chat before resuming. It does not automatically retry paid work.

## Storage and boundaries

Definitions, frozen run messages, counters, session IDs/directories and states live in the private local `~/Library/Application Support/Agent Deck/Flows/state.json` (0600). The native app and helper share a bounded, locked transaction. Assistant completion text is hashed for duplicate detection; raw answers, unrelated user prompts and transcripts are not saved. No transcript path is opened. No network request is made by the connector itself.

Only explicitly armed runs can issue messages. The connector never answers approvals, changes sandbox/permission settings, launches another CLI agent, chooses another chat, or silently starts a run after restart. Existing manual preset keys, voice dictation, URL scheme, Keychain and saved keys remain separate.

Hooks must be supported and trusted in the host. Local command hooks are not available in every cloud-orchestrated workflow. Synthetic checks do not establish compatibility with an owner's particular installed Codex version, subscription, managed policy or active chat. Native host trust and a real owner-selected test remain required before calling the integration end-to-end verified.
