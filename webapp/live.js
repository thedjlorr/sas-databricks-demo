/* Live mode for the Viya Bridge pages.
   When the pages are served by webapp/server.py, buttons call real SAS on Viya.
   Opened straight from disk (file://) there is no server and the pages keep
   their original behaviour, so Live.ready() resolves to null. */
(function () {
  const Live = {};
  const served = location.protocol === 'http:' || location.protocol === 'https:';

  Live.ready = () => {
    if (!served) return Promise.resolve(null);
    if (!Live._ready) {
      Live._ready = fetch('/api/status')
        .then((r) => r.json().then((j) => ({ status: r.status, body: j })))
        .then(({ status, body }) => (body && typeof body.ok === 'boolean' ? { ...body, status } : null))
        .catch(() => null);
    }
    return Live._ready;
  };

  Live.post = async (path, body) => {
    let resp;
    try {
      resp = await fetch(path, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body || {}) });
    } catch (err) {
      throw new Error('The Viya Bridge server is not running. Start it with: python webapp/server.py');
    }
    let json = null;
    try { json = await resp.json(); } catch (err) { /* handled below */ }
    if (!resp.ok || !json || json.ok === false) throw new Error((json && json.error) || `Request failed (${resp.status})`);
    return json;
  };

  const css = document.createElement('style');
  css.textContent = `
    #bridgeResult{position:fixed;left:16px;right:16px;bottom:16px;max-width:980px;margin:0 auto;z-index:50;max-height:55vh;overflow:auto;
      background:var(--panel,#fff);color:var(--ink,#1b1b1b);border:1px solid var(--line,#ccc);border-radius:14px;box-shadow:0 12px 40px rgba(0,0,0,.25);padding:14px 16px}
    #bridgeResult[hidden],.text-button[hidden]{display:none !important}
    #bridgeResult h3{margin:0 0 4px;font-size:16px}
    #bridgeResult .br-note{margin:0 0 10px;color:var(--muted,#666);font-size:13px}
    #bridgeResult .br-close{position:absolute;top:8px;right:12px;border:0;background:none;font-size:22px;cursor:pointer;color:inherit}
    #bridgeResult table{border-collapse:collapse;font-size:13px;width:100%}
    #bridgeResult th,#bridgeResult td{border-bottom:1px solid var(--line,#ddd);padding:4px 8px;text-align:left;white-space:nowrap}
    #bridgeResult th{position:sticky;top:0;background:var(--panel,#fff)}
    #bridgeResult.br-error{border-color:#b3261e}
    #bridgeResult.br-error h3{color:#b3261e}`;
  document.head.appendChild(css);

  const box = document.createElement('div');
  box.id = 'bridgeResult';
  box.hidden = true;
  box.setAttribute('role', 'status');
  box.innerHTML = '<button class="br-close" aria-label="Close">&times;</button><h3></h3><p class="br-note"></p><div class="br-body"></div>';
  document.addEventListener('DOMContentLoaded', () => document.body.appendChild(box));
  box.querySelector('.br-close').addEventListener('click', () => { box.hidden = true; });

  const fmt = (v) => {
    if (v === null || v === undefined || v === '') return '';
    if (typeof v === 'number') return Number.isInteger(v) ? v.toLocaleString('en-US') : String(Math.round(v * 10000) / 10000);
    return String(v);
  };

  Live.show = (title, note, data) => {
    box.classList.remove('br-error');
    box.querySelector('h3').textContent = title;
    box.querySelector('.br-note').textContent = note || '';
    const body = box.querySelector('.br-body');
    body.textContent = '';
    if (data && data.columns) {
      const table = document.createElement('table');
      const head = table.createTHead().insertRow();
      data.columns.forEach((c) => { const th = document.createElement('th'); th.textContent = c; head.appendChild(th); });
      const tbody = table.createTBody();
      data.rows.forEach((row) => {
        const tr = tbody.insertRow();
        row.forEach((v) => { tr.insertCell().textContent = fmt(v); });
      });
      body.appendChild(table);
    }
    box.hidden = false;
  };

  Live.fail = (title, err) => {
    Live.show(title, err && err.message ? err.message : String(err), null);
    box.classList.add('br-error');
  };

  window.Live = Live;
})();
