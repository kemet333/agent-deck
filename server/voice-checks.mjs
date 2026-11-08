// Pruebas del servidor de voz con un Lemon Squeezy y un OpenAI falsos (sin red, sin claves de verdad).
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createVoiceServer } from './voice.mjs';

function fake() {
  const calls = [];
  const fetchImpl = async (url, opts) => {
    calls.push({ url, opts });
    const json = (o, status = 200) => ({ status, json: async () => o });
    if (url.includes('lemonsqueezy')) {
      const key = new URLSearchParams(opts.body).get('license_key');
      return json(key === 'GOOD-LICENSE-KEY' ? { valid: true, meta: { store_id: 1, product_id: 2 } } : key === 'OTHER-PRODUCT-KEY' ? { valid: true, meta: { store_id: 9, product_id: 9 } } : { valid: false });
    }
    if (url.endsWith('/realtime/client_secrets')) {
      const b = JSON.parse(opts.body);
      assert.equal(b.session.type, 'transcription');
      assert.match(opts.headers.Authorization, /^Bearer sk-prompted/);
      return json({ value: 'ek_test123', expires_at: 1900000000 });
    }
    if (url.endsWith('/responses')) return json({ output: [{ type: 'message', content: [{ type: 'output_text', text: 'Hecho; ¿sigo?' }] }] });
    return json({}, 404);
  };
  return { fetchImpl, calls };
}

function server(extra = {}) {
  const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'abvoice-'));
  const f = fake();
  let t = Date.parse('2026-11-08T12:00:00Z');
  const s = createVoiceServer({ env: { OPENAI_API_KEY: 'sk-prompted', LEMON_STORE_ID: '1', LEMON_PRODUCT_ID: '2', MONTHLY_MINUTES: '1', ...extra }, fetchImpl: f.fetchImpl, now: () => t, dataDir });
  return { s, f, dataDir, advance: (ms) => { t += ms; } };
}
const lic = { license_key: 'GOOD-LICENSE-KEY', instance_id: 'mac-1' };

test('a valid license gets a temporary transcription token; the real key never leaves', async () => {
  const { s } = server();
  const r = await s.handle('POST', '/v1/voice/session', '1.1.1.1', lic);
  assert.equal(r.status, 200);
  assert.equal(r.json.token, 'ek_test123');
  assert.ok(!JSON.stringify(r.json).includes('sk-prompted'));
});

test('bad or foreign licenses are refused', async () => {
  const { s } = server();
  assert.equal((await s.handle('POST', '/v1/voice/session', '1.1.1.1', { license_key: 'NOPE-NOPE-NOPE', instance_id: 'x' })).status, 403);
  assert.equal((await s.handle('POST', '/v1/voice/session', '1.1.1.1', { license_key: 'OTHER-PRODUCT-KEY', instance_id: 'x' })).status, 403);
});

test('monthly minutes run out, then come back next month', async () => {
  const { s, advance } = server();   // 1 min al mes
  await s.handle('POST', '/v1/voice/session', '1.1.1.1', lic);
  const u = await s.handle('POST', '/v1/voice/usage', '1.1.1.1', { ...lic, seconds: 70 });
  assert.equal(u.json.minutes_left, 0);
  assert.equal((await s.handle('POST', '/v1/voice/session', '1.1.1.1', lic)).status, 402);
  advance(31 * 86_400_000);
  assert.equal((await s.handle('POST', '/v1/voice/session', '1.1.1.1', lic)).status, 200);
});

test('text cleanup and summaries use the server instructions', async () => {
  const { s, f } = server();
  const r = await s.handle('POST', '/v1/text', '1.1.1.1', { ...lic, task: 'summary', text: 'I finished the login page and all tests pass. Should I continue?' });
  assert.equal(r.status, 200); assert.equal(r.json.text, 'Hecho; ¿sigo?');
  const body = JSON.parse(f.calls.at(-1).opts.body);
  assert.match(body.instructions, /ONE short sentence/);
  assert.equal((await s.handle('POST', '/v1/text', '1.1.1.1', { ...lic, task: 'anything-else', text: 'x' })).status, 400);
});

test('the license is checked once an hour, and stored only as a fingerprint', async () => {
  const { s, f, dataDir } = server({ MONTHLY_MINUTES: '300' });
  await s.handle('POST', '/v1/voice/session', '1.1.1.1', lic);
  await s.handle('POST', '/v1/voice/session', '1.1.1.1', lic);
  assert.equal(f.calls.filter((c) => c.url.includes('lemonsqueezy')).length, 1);
  assert.ok(!fs.readFileSync(path.join(dataDir, 'usage.json'), 'utf8').includes('GOOD-LICENSE-KEY'));
});

test('too many requests from one place are slowed down', async () => {
  const { s } = server({ MONTHLY_MINUTES: '300' });
  let last;
  for (let i = 0; i < 62; i++) last = await s.handle('POST', '/v1/voice/usage', '2.2.2.2', { ...lic, seconds: 1 });
  assert.equal(last.status, 429);
});
