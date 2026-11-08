# Agent Bar voice server (Pro)

The included voice of Agent Bar Pro. Prompted's OpenAI key stays on this server. The Mac app only ever receives a temporary token for one realtime transcription session, plus cleaned text.

| Route | What it does |
|---|---|
| `POST /v1/voice/session` | Checks the Lemon Squeezy license and this month's minutes. Returns a temporary OpenAI token (`ek_…`, 5 min to start a session) for `gpt-live-transcribe`. |
| `POST /v1/voice/usage` | The app reports the seconds it used. Each session counts at least 10 s. |
| `POST /v1/text` | `clean`, `prompt` or `summary`, using the server's own instructions. |
| `GET /health` | `{"ok":true}` |

- No dependencies. Node 20 or newer.
- Licenses are stored only as a sha256 fingerprint, together with each month's seconds, in `DATA_DIR/usage.json`.
- Tests use fake Lemon Squeezy and OpenAI endpoints: `node --test voice-checks.mjs`.

## Environment

| Variable | |
|---|---|
| `OPENAI_API_KEY` | Prompted's key (secret: set it in the host, never in git) |
| `LEMON_STORE_ID`, `LEMON_PRODUCT_ID` | Only licenses of this product are accepted |
| `MONTHLY_MINUTES` | Minutes per license per month (default 300 ≈ 5 $ at 0.017 $/min) |
| `DATA_DIR` | Where `usage.json` lives (a persistent volume) |
| `PORT` | Set by the host |

## Deploy (Railway, like the Prompted website)
1. New service from this repo, root directory `server/`, start command `node main.mjs`.
2. Add a volume mounted at `/data` and set `DATA_DIR=/data`.
3. Set the variables above. Diego pastes `OPENAI_API_KEY` himself.
4. Give it a domain, e.g. `voice.getagentbar.com`.
5. Check it: `curl https://voice.getagentbar.com/health` → `{"ok":true}`.

Then, in the app, set `ProVoice.server` (`Sources/ProVoice.swift`) to that URL and test with a real Pro license:
1. Does the realtime WebSocket accept the `ek_` token as `Authorization: Bearer` or as the `openai-insecure-api-key.` subprotocol? Both are sent. OpenAI documents only the subprotocol, for browsers.
2. Is the text cleaned through `/v1/text` when there is no own key?
