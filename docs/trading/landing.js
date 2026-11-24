(function () {
  var reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;
  var io = new IntersectionObserver(function (es) { es.forEach(function (e) { if (e.isIntersecting) { e.target.classList.add('in'); io.unobserve(e.target); } }); }, { rootMargin: '0px 0px -8% 0px' });
  document.querySelectorAll('.rv').forEach(function (el, i) { el.style.transitionDelay = (i % 3) * 70 + 'ms'; io.observe(el); });

  // Same instruments and math as the app (Sources/Trading.swift).
  var INS = [
    ['MNQ', 'Micro Nasdaq 100', 2, 0.25], ['NQ', 'Nasdaq 100', 20, 0.25], ['MES', 'Micro S&P 500', 5, 0.25], ['ES', 'S&P 500', 50, 0.25],
    ['M2K', 'Micro Russell 2000', 5, 0.1], ['RTY', 'Russell 2000', 50, 0.1], ['MYM', 'Micro Dow', 0.5, 1], ['YM', 'Dow', 5, 1],
    ['MGC', 'Micro Gold', 10, 0.1], ['GC', 'Gold', 100, 0.1], ['MCL', 'Micro Crude Oil', 100, 0.01], ['CL', 'Crude Oil', 1000, 0.01]
  ];
  function size(risk, stop, ins) {
    if (!(risk > 0) || !(stop > 0)) return null;
    var ticks = Math.ceil(stop / ins[3] - 1e-9), per = ticks * ins[2] * ins[3];
    var n = Math.floor(risk / per + 1e-9);
    return { n: n, per: per, real: n * per, ticks: ticks };
  }
  var money = function (v) { return '$' + v.toLocaleString('en-US', { maximumFractionDigits: v % 1 ? 2 : 0, minimumFractionDigits: v % 1 ? 2 : 0 }); };
  var num = function (id) { return parseFloat(String(document.getElementById(id).value).replace(/[, $%]/g, '')); };

  var sym = document.getElementById('c_sym'), pctMode = true;
  INS.forEach(function (x, i) { var o = document.createElement('option'); o.value = i; o.textContent = x[0] + ' · ' + x[1]; sym.appendChild(o); });
  function calc() {
    var ins = INS[+sym.value], bal = num('c_bal'), r = num('c_risk'), stop = num('c_stop');
    var risk = pctMode ? Math.max(0, bal * r / 100) : r;
    var s = size(risk, stop, ins), out = document.getElementById('c_d');
    var n = document.getElementById('c_n');
    if (!s) { n.innerHTML = '–<small>contracts</small>'; out.innerHTML = '<span>Fill in risk and stop.</span>'; return null; }
    n.innerHTML = s.n + '<small>' + (s.n === 1 ? 'contract' : 'contracts') + ' of ' + ins[0] + '</small>';
    out.innerHTML = '<span>Your risk <b>' + money(risk) + '</b></span>' +
      '<span>Stop <b>' + s.ticks + ' ticks</b> · <b>' + money(s.per) + '</b> per contract</span>' +
      '<span>Real risk <b>' + money(s.real) + '</b></span>' +
      (s.n === 0 ? '<span class="calc__warn">One contract risks more than you allow. Tighten the stop or use the micro.</span>' : '');
    return { s: s, ins: ins };
  }
  ['c_sym', 'c_bal', 'c_risk', 'c_stop'].forEach(function (id) { document.getElementById(id).addEventListener('input', calc); });
  function setMode(p) {
    if (p === pctMode) return;
    var bal = num('c_bal') || 0, v = num('c_risk') || 0, inp = document.getElementById('c_risk');
    inp.value = p ? (bal ? +(v / bal * 100).toFixed(2) : 0.5) : Math.round(bal * v / 100);
    pctMode = p;
    document.getElementById('c_pct').setAttribute('aria-pressed', p); document.getElementById('c_usd').setAttribute('aria-pressed', !p);
    calc();
  }
  document.getElementById('c_pct').onclick = function () { setMode(true); };
  document.getElementById('c_usd').onclick = function () { setMode(false); };
  calc();

  // Demo chart: a seeded random walk so it looks the same every visit.
  var svg = document.getElementById('chart'), seed = 7;
  var rnd = function () { seed = (seed * 16807) % 2147483647; return seed / 2147483647; };
  var N = 56, W = 1000, H = 360, cw = W / N, price = 21300, bars = [];
  for (var i = 0; i < N; i++) {
    var o = price, drift = Math.sin(i / 7) * 2 + (i > 38 ? 3.2 : 0.4), c = o + drift + (rnd() - 0.5) * 18;
    c = Math.round(c * 4) / 4;
    bars.push({ o: o, c: c, h: Math.max(o, c) + rnd() * 7, l: Math.min(o, c) - rnd() * 7 }); price = c;
  }
  var lastC = bars[N - 1].c, hi = Math.max(Math.max.apply(null, bars.map(function (b) { return b.h; })) + 6, lastC + 55), lo = Math.min(Math.min.apply(null, bars.map(function (b) { return b.l; })) - 6, lastC - 55);
  var y = function (p) { return H - 24 - (p - lo) / (hi - lo) * (H - 48); };
  var ns = 'http://www.w3.org/2000/svg', g = '';
  for (var k = 1; k < 5; k++) g += '<line x1="0" x2="' + W + '" y1="' + (H / 5 * k) + '" y2="' + (H / 5 * k) + '" stroke="rgba(255,255,255,.05)"/>';
  bars.forEach(function (b, i) {
    var x = i * cw + cw / 2, up = b.c >= b.o, col = up ? '#22c55e' : '#ef4444';
    g += '<line x1="' + x + '" x2="' + x + '" y1="' + y(b.h) + '" y2="' + y(b.l) + '" stroke="' + col + '" stroke-width="1.5"/>';
    g += '<rect x="' + (x - cw * 0.32) + '" width="' + (cw * 0.64) + '" y="' + y(Math.max(b.o, b.c)) + '" height="' + Math.max(1.5, Math.abs(y(b.o) - y(b.c))) + '" fill="' + col + '" rx="1"/>';
  });
  var last = bars[N - 1].c;
  g += '<line id="pl" x1="0" x2="' + W + '" y1="' + y(last) + '" y2="' + y(last) + '" stroke="rgba(255,255,255,.35)" stroke-dasharray="4 5"/>';
  g += '<g id="bracket"></g>';
  svg.innerHTML = g;
  document.getElementById('px').textContent = last.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });

  // Keys: show what the order would be, using the calculator's size (MNQ unless you changed it).
  var toast = document.getElementById('toast'), txt = document.getElementById('toastTxt'), t;
  function show(msg, sell) {
    txt.textContent = msg; toast.classList.toggle('sell', !!sell); toast.classList.add('on');
    clearTimeout(t); t = setTimeout(function () { toast.classList.remove('on'); }, 2600);
  }
  function bracket(side, entry, stopPts) {
    var b = document.getElementById('bracket'), sp = side > 0 ? entry - stopPts : entry + stopPts, tp = side > 0 ? entry + stopPts * 2 : entry - stopPts * 2;
    var line = function (p, c, l) { return '<line x1="560" x2="' + W + '" y1="' + y(p) + '" y2="' + y(p) + '" stroke="' + c + '" stroke-width="1.5"/><text x="' + (W - 8) + '" y="' + (y(p) - 6) + '" text-anchor="end" fill="' + c + '" font-size="13" font-family="Geist Mono, monospace">' + l + '</text>'; };
    b.innerHTML = line(entry, '#e9e9e6', 'ENTRY') + line(sp, '#ef4444', 'STOP') + line(tp, '#22c55e', 'TARGET');
  }
  function press(k) {
    var r = calc(), ins = r ? r.ins : INS[0], n = r ? Math.max(r.s.n, 1) : 1, stop = num('c_stop') || 20;
    var q = n + ' ' + ins[0];
    var risk = r ? ' · risk ' + money(Math.max(r.s.n, 1) * r.s.per) : '';
    if (k === 'buy') { show('Buy ' + q + ' at market · stop ' + stop + ' pts' + risk); bracket(1, last, stop); }
    if (k === 'sell') { show('Sell ' + q + ' at market · stop ' + stop + ' pts' + risk, true); bracket(-1, last, stop); }
    if (k === 'blim') { show('Buy limit ' + q + ' at the cursor price'); bracket(1, last - stop / 2, stop); }
    if (k === 'slim') { show('Sell limit ' + q + ' at the cursor price', true); bracket(-1, last + stop / 2, stop); }
    if (k === 'dom') { show('DOM centered on last price'); document.getElementById('bracket').innerHTML = ''; }
  }
  document.querySelectorAll('.tk').forEach(function (b) { b.addEventListener('click', function () { press(b.dataset.k); }); });
  // Real shortcuts work on the demo too.
  addEventListener('keydown', function (e) {
    if (!e.shiftKey || e.metaKey || e.ctrlKey || /input|select|textarea/i.test(document.activeElement.tagName)) return;
    var map = { KeyB: e.altKey ? 'blim' : 'buy', KeyS: e.altKey ? 'slim' : 'sell', KeyC: e.altKey ? 'dom' : null }, k = map[e.code];
    if (!k) return;
    e.preventDefault(); press(k);
    var btn = document.querySelector('.tk[data-k="' + k + '"]'); btn.classList.add('press'); setTimeout(function () { btn.classList.remove('press'); }, 160);
  });
  if (!reduce) setTimeout(function () { press('buy'); }, 1400);

  // How it works: light up the three steps in turn while the section is on screen.
  var steps = document.querySelectorAll('.f3__s'), cur = -1, timer = null;
  function next() { steps.forEach(function (s) { s.classList.remove('on'); }); cur = (cur + 1) % steps.length; steps[cur].classList.add('on'); }
  new IntersectionObserver(function (es) {
    es.forEach(function (e) {
      if (e.isIntersecting && !timer) { next(); if (!reduce) timer = setInterval(next, 2400); }
      else if (!e.isIntersecting && timer) { clearInterval(timer); timer = null; }
    });
  }, { threshold: 0.35 }).observe(document.getElementById('f3'));
  steps.forEach(function (s, i) { s.addEventListener('mouseenter', function () { clearInterval(timer); timer = null; steps.forEach(function (x) { x.classList.remove('on'); }); s.classList.add('on'); cur = i; }); });
})();
