// Arranque: node main.mjs (PORT, OPENAI_API_KEY, LEMON_STORE_ID, LEMON_PRODUCT_ID, MONTHLY_MINUTES, DATA_DIR).
import http from 'node:http';
import { createVoiceServer } from './voice.mjs';

const server = createVoiceServer();
http.createServer((req, res) => {
  let size = 0; const chunks = [];
  req.on('data', (c) => { size += c.length; if (size > 64 * 1024) { res.writeHead(413).end(); req.destroy(); } else chunks.push(c); });
  req.on('end', async () => {
    if (res.writableEnded) return;
    let body = {};
    try { if (chunks.length) body = JSON.parse(Buffer.concat(chunks).toString('utf8')); } catch { res.writeHead(400).end(); return; }
    const ip = String(req.headers['x-forwarded-for'] || req.socket.remoteAddress || '').split(',')[0].trim();
    try {
      const r = await server.handle(req.method, req.url, ip, body);
      res.writeHead(r.status, { 'Content-Type': 'application/json' }).end(JSON.stringify(r.json));
    } catch { res.writeHead(500, { 'Content-Type': 'application/json' }).end('{"error":"server"}'); }
  });
}).listen(Number(process.env.PORT || 8080), () => console.log('agent bar voice server on', process.env.PORT || 8080));
