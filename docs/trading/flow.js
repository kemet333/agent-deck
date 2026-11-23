// Apply quiz and purchase validation for getagentbar.com/trading.
// Answers are scored on the Prompted server (prompted-app, lib/trading.js); option ids here must match its QUIZ.
(function () {
  var MODE = document.currentScript.dataset.mode; // 'apply' | 'validate'
  var qs = new URLSearchParams(location.search);
  var LOCAL = /^(localhost|127\.0\.0\.1)$/.test(location.hostname);
  var API = (LOCAL && qs.get('api')) || 'https://prompted-app-production.up.railway.app';
  var FTMO = 'https://join.ftmo.com/tsmNaFTvCDtVODVoObpn';
  var KEY = 'agentbar-trading';
  var app = document.getElementById('app');

  var QUIZ = [
    { id: 'market', q: 'What do you trade?', opts: [
      ['futures_index', 'Index futures', 'NQ, ES, MNQ, MES…'], ['futures_other', 'Other futures', 'Gold, oil, Russell, Dow'],
      ['forex_cfd', 'Forex or CFDs'], ['crypto', 'Crypto'], ['none', 'I don’t trade yet']] },
    { id: 'platform', q: 'Where do you place your orders?', opts: [
      ['tradingview', 'TradingView'], ['tradovate', 'Tradovate'], ['ninjatrader', 'NinjaTrader'], ['other', 'Something else']] },
    { id: 'prop', q: 'Where are you with prop firms?', opts: [
      ['funded', 'I’m funded right now'], ['challenge', 'I’m in a challenge'], ['retrying', 'I failed one and want another go'], ['never', 'I’ve never tried one']] },
    { id: 'pain', q: 'What costs you the most money?', opts: [
      ['size', 'Wrong position size', 'Too big after a loss, too small on the good ones'], ['late', 'Late entries', 'By the time the ticket is ready, price is gone'],
      ['overtrading', 'Overtrading', 'One more trade, then another'], ['hesitation', 'Hesitating', 'I see it and don’t press'], ['other', 'Something else']] },
    { id: 'computer', q: 'What do you trade on?', opts: [
      ['mac_silicon', 'Mac with Apple Silicon', 'M1, M2, M3, M4 or newer'], ['mac_intel', 'Mac with Intel'], ['windows', 'Windows PC']] },
    { id: 'timing', q: 'When would you start an FTMO Futures account?', opts: [
      ['this_week', 'This week'], ['this_month', 'This month'], ['looking', 'Just looking for now']] }
  ];
  var PAIN = {
    size: 'Wrong size is exactly what the sizer fixes: you set the risk once, it tells you the contracts, never above it.',
    late: 'Late entries are what one-key orders fix: your preset bracket is ready, so pressing is all that’s left.',
    overtrading: 'For overtrading, the brake in the next update caps your entries per day and makes you wait between them.',
    hesitation: 'With the size worked out and the bracket preset, the decision is the only thing left. One key.',
    other: 'Start with the Trader pack and the sizer; most traders feel the difference on the first session.'
  };

  var st = load();
  function load() { try { return JSON.parse(localStorage.getItem(KEY)) || {}; } catch (e) { return {}; } }
  function save() { try { localStorage.setItem(KEY, JSON.stringify(st)); } catch (e) {} }
  function source() {
    var p = []; ['utm_source', 'utm_medium', 'utm_campaign', 'ref'].forEach(function (k) { if (qs.get(k)) p.push(k + '=' + qs.get(k)); });
    if (document.referrer && !/getagentbar\.com/.test(document.referrer)) p.push('referrer=' + document.referrer.slice(0, 80));
    return p.join('&');
  }
  function api(path, body) {
    return fetch(API + path, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) })
      .then(function (r) { return r.json().catch(function () { return {}; }).then(function (b) { if (!r.ok) throw new Error(b.error || 'Something went wrong. Try again.'); return b; }); });
  }
  var esc = function (s) { return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]; }); };
  var validEmail = function (e) { return /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(e); };
  function render(html, focusSel) {
    app.innerHTML = html; window.scrollTo({ top: 0, behavior: 'smooth' });
    var f = app.querySelector(focusSel || 'h1,h2'); if (f) { if (!f.matches('input,button,select')) f.setAttribute('tabindex', '-1'); f.focus({ preventScroll: true }); }
  }
  function prog(i, n, label) {
    return '<div class="prog"><span>' + label + '</span><span class="prog__t"><span class="prog__f" style="width:' + Math.round(i / n * 100) + '%"></span></span><span>' + i + '/' + n + '</span></div>';
  }
  function busy(form, on) { form.querySelectorAll('button,input,select').forEach(function (b) { b.disabled = on; }); }

  // 1. Contact: the email registered here is where the download goes.
  function contact() {
    render(prog(0, QUIZ.length + 1, 'Apply') +
      '<div class="q"><h1>Let’s see if Agent Bar fits how you trade.</h1>' +
      '<p class="lead">Six quick questions. Your download link will go to this email, so use one you check.</p>' +
      '<form class="form" id="f" novalidate>' +
      '<label class="fld">First name<input id="name" autocomplete="given-name" value="' + esc(st.name) + '" required></label>' +
      '<label class="fld">Email<input id="email" type="email" autocomplete="email" inputmode="email" value="' + esc(st.email) + '" required></label>' +
      '<div class="err" id="err" role="alert"></div>' +
      '<button class="btn btn--accent" type="submit">Start<span class="ic"><i class="ph ph-arrow-right"></i></span></button>' +
      '<p class="small">We use your email to send your access and a few useful messages about Agent Bar. Unsubscribe any time.</p>' +
      '</form></div>', '#name');
    document.getElementById('f').onsubmit = function (e) {
      e.preventDefault();
      var name = document.getElementById('name').value.trim(), email = document.getElementById('email').value.trim().toLowerCase();
      if (!validEmail(email)) { document.getElementById('err').textContent = 'Enter a valid email.'; document.getElementById('email').focus(); return; }
      st.name = name; st.email = email; st.answers = st.answers || {}; save();
      api('/api/trading/apply', { email: email, name: name, source: source() }).catch(function () {}); // keep going even if it fails; we send again at the end
      question(0);
    };
  }

  function question(i) {
    var Q = QUIZ[i], cur = (st.answers || {})[Q.id];
    var opts = Q.opts.map(function (o, k) {
      return '<button type="button" class="opt" data-v="' + o[0] + '" aria-pressed="' + (cur === o[0]) + '"><kbd>' + (k + 1) + '</kbd><span>' + esc(o[1]) + (o[2] ? '<small>' + esc(o[2]) + '</small>' : '') + '</span></button>';
    }).join('');
    render(prog(i + 1, QUIZ.length + 1, 'Apply') + '<div class="q"><h2>' + esc(Q.q) + '</h2><div class="opts" role="group" aria-label="' + esc(Q.q) + '">' + opts + '</div>' +
      '<div style="margin-top:20px"><button type="button" class="back" id="back">← Back</button></div></div>');
    var pick = function (v) {
      st.answers[Q.id] = v; save();
      app.querySelectorAll('.opt').forEach(function (b) { b.setAttribute('aria-pressed', b.dataset.v === v); });
      setTimeout(function () { i + 1 < QUIZ.length ? question(i + 1) : submit(); }, 180);
    };
    app.querySelectorAll('.opt').forEach(function (b) { b.onclick = function () { pick(b.dataset.v); }; });
    document.getElementById('back').onclick = function () { i ? question(i - 1) : contact(); };
    keys = function (e) { var n = +e.key; if (n >= 1 && n <= Q.opts.length) pick(Q.opts[n - 1][0]); };
  }
  var keys = null;
  addEventListener('keydown', function (e) { if (keys && !/input|select|textarea/i.test(document.activeElement.tagName) && !e.metaKey && !e.ctrlKey) keys(e); });

  function submit() {
    keys = null;
    render('<div class="q"><h2>Checking your fit…</h2><p class="lead">One second.</p></div>');
    api('/api/trading/apply', { email: st.email, name: st.name, answers: st.answers, source: source() })
      .then(function (r) { st.tier = r.tier; st.score = r.score; save(); result(); })
      .catch(function (e) { render('<div class="q"><h2>We couldn’t save your answers.</h2><p class="lead">' + esc(e.message) + '</p><div class="form"><button class="btn" id="retry">Try again<span class="ic"><i class="ph ph-arrow-clockwise"></i></span></button></div></div>'); document.getElementById('retry').onclick = submit; });
  }

  // 2. Result: fit + how access works + buy + validate, all on one screen.
  function result() {
    var a = st.answers || {}, tier = st.tier, first = st.name ? esc(st.name.split(' ')[0]) + ', ' : '';
    if (tier === 'not_eligible') {
      var why = a.computer === 'windows' ? 'Agent Bar runs on Mac only for now.' : 'Agent Bar needs a Mac with Apple Silicon (M1 or newer).';
      return render('<div class="q"><div class="eyebrow"><i></i>Your result</div><h1 style="margin-top:14px">' + first + 'not yet on your computer.</h1>' +
        '<p class="lead">' + why + ' We’ve saved your spot and we’ll email <b>' + esc(st.email) + '</b> as soon as it runs on yours. No need to buy anything today.</p>' +
        '<div class="form"><a class="btn btn--ghost" href="../">Back to Agent Bar for traders<span class="ic"><i class="ph ph-arrow-left"></i></span></a></div></div>');
    }
    var head = tier === 'hot' ? 'you’re exactly who we built this for.' : tier === 'warm' ? 'Agent Bar fits how you trade.' : 'you can use Agent Bar.';
    var extra = a.market === 'forex_cfd' || a.market === 'crypto' || a.market === 'none'
      ? ' Its sizer is built for futures contracts, which is what an FTMO Futures account trades.' : '';
    var plat = a.platform === 'tradingview' ? '' : a.platform === 'tradovate' ? ' Tradovate keys arrive in the next update; until then the Trader pack works in TradingView.' : ' The Trader pack works in TradingView, so you’ll place orders from there.';
    var pct = Math.min(100, Math.round((st.score || 0) / 105 * 100));
    render('<div class="q"><div class="eyebrow"><i></i>Your result</div>' +
      '<h1 style="margin-top:14px">' + first + head + '</h1>' +
      '<div class="score"><span>Fit</span><span class="prog__t"><span class="prog__f" style="width:' + pct + '%"></span></span><span>' + pct + '%</span></div>' +
      '<p class="lead">' + PAIN[a.pain || 'other'] + extra + plat + '</p>' +
      '<p class="lead"><b>How you get access:</b> Agent Bar for traders comes free with an FTMO Futures account bought through our link. Buy it, validate it here, and the download goes to <b>' + esc(st.email) + '</b>.</p></div>' +
      buyBox() + validateBox(false));
    wireBuy(); wireValidate();
  }

  function buyBox() {
    return '<div class="box' + (st.clicked ? ' done' : '') + '" id="buy"><h3><span class="n">' + (st.clicked ? '<i class="ph-bold ph-check"></i>' : '1') + '</span>Get your FTMO Futures account</h3>' +
      '<p>Choose Pro or Growth and a size from $50K to $150K. FTMO opens in a new tab; keep this one open. If you can, check out with <b>' + esc(st.email) + '</b>.</p>' +
      '<a class="btn btn--accent" id="ftmo" href="' + FTMO + '" target="_blank" rel="sponsored noopener">Open FTMO Futures<span class="ic"><i class="ph ph-arrow-up-right"></i></span></a></div>';
  }
  function wireBuy() {
    var b = document.getElementById('ftmo'); if (!b) return;
    b.onclick = function () {
      st.clicked = true; save();
      if (st.email) api('/api/trading/ftmo-click', { email: st.email }).catch(function () {});
      setTimeout(function () { var box = document.getElementById('buy'); box.classList.add('done'); box.querySelector('.n').innerHTML = '<i class="ph-bold ph-check"></i>'; var o = document.getElementById('order'); if (o) o.focus({ preventScroll: true }); }, 400);
    };
  }

  function validateBox(standalone) {
    var askEmail = standalone && !st.email;
    var plans = ['Growth $50K', 'Growth $100K', 'Growth $150K', 'Pro $50K', 'Pro $100K', 'Pro $150K'];
    return '<form class="box" id="v" novalidate><h3><span class="n">' + (standalone ? '<i class="ph-bold ph-seal-check"></i>' : '2') + '</span>Validate your purchase</h3>' +
      '<p>Paste the order number from FTMO’s payment confirmation email (it’s also in your FTMO client area).</p>' +
      '<div class="form" style="margin-top:0">' +
      (askEmail ? '<div class="row2"><label class="fld">First name<input id="vname" autocomplete="given-name"></label><label class="fld">Your email (where we send the download)<input id="vemail" type="email" autocomplete="email" inputmode="email"></label></div>' : '') +
      '<div class="row2"><label class="fld">FTMO order number<input id="order" autocomplete="off" placeholder="e.g. 12345678" required></label>' +
      '<label class="fld">Account<select id="plan"><option value="">Choose…</option>' + plans.map(function (p) { return '<option>' + p + '</option>'; }).join('') + '<option>Not sure</option></select></label></div>' +
      '<label class="fld">Email used at FTMO <span class="muted">(if different)</span><input id="femail" type="email" inputmode="email" placeholder="' + esc(st.email || 'same as above') + '"></label>' +
      '<label class="check"><input type="checkbox" id="confirm"> <span>I bought this FTMO Futures account through the Agent Bar link, and it’s mine.</span></label>' +
      '<div class="err" id="verr" role="alert"></div>' +
      '<button class="btn" type="submit">Validate and email my download<span class="ic"><i class="ph ph-paper-plane-tilt"></i></span></button>' +
      (!standalone ? '' : '<p class="small">Haven’t bought it yet? <a href="' + FTMO + '" target="_blank" rel="sponsored noopener" id="ftmo2">Open FTMO Futures</a> or <a href="../apply/">apply first</a>.</p>') +
      '</div></form>';
  }
  function wireValidate() {
    var f = document.getElementById('v'), err = document.getElementById('verr');
    var f2 = document.getElementById('ftmo2'); if (f2) f2.onclick = function () { st.clicked = true; save(); if (st.email) api('/api/trading/ftmo-click', { email: st.email }).catch(function () {}); };
    f.onsubmit = function (e) {
      e.preventDefault(); err.textContent = '';
      var ve = document.getElementById('vemail');
      if (ve) {
        var em = ve.value.trim().toLowerCase();
        if (!validEmail(em)) { err.textContent = 'Enter the email where we should send your download.'; ve.focus(); return; }
        st.email = em; st.name = document.getElementById('vname').value.trim(); save();
      }
      var order = document.getElementById('order').value.trim(), fe = document.getElementById('femail').value.trim().toLowerCase();
      if (order.replace(/^#/, '').length < 4) { err.textContent = 'Enter your FTMO order number.'; document.getElementById('order').focus(); return; }
      if (fe && !validEmail(fe)) { err.textContent = 'That FTMO email doesn’t look right.'; document.getElementById('femail').focus(); return; }
      if (!document.getElementById('confirm').checked) { err.textContent = 'Tick the box to confirm the purchase is yours.'; return; }
      busy(f, true);
      var go = ve ? api('/api/trading/apply', { email: st.email, name: st.name, source: source() }) : Promise.resolve();
      go.then(function () {
        return api('/api/trading/validate', { email: st.email, ftmo_order: order, ftmo_email: fe, ftmo_plan: document.getElementById('plan').value, confirm: true });
      }).then(function (r) { st.validated = true; save(); done(r); })
        .catch(function (e2) { busy(f, false); err.textContent = e2.message; });
    };
  }

  function done(r) {
    var mail = esc(r.email || st.email);
    render('<div class="okmail"><i class="ph-fill ph-seal-check big" aria-hidden="true"></i>' +
      (r.emailed
        ? '<h1>Check your inbox.</h1><p class="lead">We’ve sent the Agent Bar download and a five-minute setup guide to <b>' + mail + '</b>. Not there in two minutes? Look in spam or promotions.</p>'
        : '<h1>You’re in.</h1><p class="lead">Your purchase is registered. Here’s your download. If you need it again, write to hello@workwithprompted.com from <b>' + mail + '</b>.</p>' +
          '<a class="btn btn--accent" href="' + esc(r.download) + '">Download for Mac<span class="ic"><i class="ph ph-arrow-down"></i></span></a>') +
      '<div class="box" style="text-align:left;width:100%"><h3>Set it up in five minutes</h3><ol style="margin:10px 0 0;padding-left:20px;color:var(--ink-2);display:grid;gap:8px">' +
      '<li>Open AgentBar.dmg, drag it to Applications and open it. The first time, allow it in System Settings → Privacy &amp; Security → Open Anyway.</li>' +
      '<li>Menu → Key packs → <b>Trader · TradingView</b>.</li>' +
      '<li>Settings → <b>Trading</b>: your account size, risk per trade and stop.</li>' +
      '<li>In TradingView, turn on your order preset with stop and target.</li></ol></div>' +
      '<p class="small">Something wrong? Write to <a href="mailto:hello@workwithprompted.com">hello@workwithprompted.com</a>.</p></div>');
  }

  // Validate page: straight to the form, with whatever we remember from the quiz.
  function validatePage() {
    var who = st.email ? '<p class="lead">Your download goes to <b>' + esc(st.email) + '</b>. <button type="button" class="back" id="notme">Not you?</button></p>' : '<p class="lead">Bought your FTMO Futures account through our link? Validate it and we’ll email you the download.</p>';
    render('<div class="q"><div class="eyebrow"><i></i>Agent Bar for traders</div><h1 style="margin-top:14px">Validate your purchase.</h1>' + who + '</div>' + validateBox(true), st.email ? '#order' : '#vname');
    var nm = document.getElementById('notme'); if (nm) nm.onclick = function () { st = {}; save(); validatePage(); };
    wireValidate();
  }

  if (MODE === 'validate') validatePage();
  else if (st.validated && st.email) done({ email: st.email, emailed: true });
  else if (st.tier && st.email && qs.get('restart') == null) result();
  else contact();
})();
