const DS = window.DATASETS;
const fmtBytes = (b) => (b >= 1048576 ? `${(b / 1048576).toFixed(1)} MB` : `${Math.max(1, Math.round(b / 1024))} KB`);
const sources = {
  databricks: {
    label: `Databricks, schema ${DS.databricks.schema} (${DS.databricks.tables.length})`,
    items: DS.databricks.tables.map(t => ({ name: t.name, detail: `${DS.databricks.library} · ${t.group}`, type: 'TABLE', size: `${t.cols} columns · ${t.rows.toLocaleString('en-US')} rows`, loadable: true }))
  },
  cas: {
    label: `CAS caslib ${DS.cas.caslib} (${DS.cas.tables.length})`,
    items: DS.cas.tables.map(t => ({ name: t.name, detail: `${DS.cas.caslib} · on disk, not loaded`, type: 'FILE', size: fmtBytes(t.bytes), loadable: false }))
  }
};

const state = { method: 'spark', source: 'databricks' };
const $ = (id) => document.getElementById(id);

function value(id) { return $(id).value.trim(); }

function makeCode() {
  const source = value('sourceTable') || 'source_table';
  const target = value('targetTable') || source;
  const caslib = value('caslib') || 'DB_DEMO';
  const method = state.method;
  let code;

  if (method === 'jdbc') {
    code = `%macro load_via_jdbc();\n\nlibname dbx jdbc\n   url="jdbc:databricks://${value('host')}:${value('port')}/&httpPath=${value('httpPath')}"\n   schema="${value('schema')}"\n   authdomain="${value('authDomain')}";\n\nlibname tgt cas caslib="${caslib}";\n\nproc casutil incaslib="${caslib}";\n   droptable casdata="${target}" quiet;\nquit;\n\ndata tgt.${target} (promote=yes);\n   set dbx.${source};\nrun;\n\n%mend;\n%load_via_jdbc();`;
  } else if (method === 'cas') {
    code = `%macro load_via_cas();\n\n/* Requires a Databricks-aware CASLIB on Viya. */\ncas mysess;\nproc casutil incaslib="${caslib}";\n   load casdata="${source}"\n      incaslib="DATABRICKS"\n      outcaslib="${caslib}"\n      casout="${target}"\n      promote;\nquit;\n\n%mend;\n%load_via_cas();`;
  } else {
    code = `%macro load_from_databricks();\n\ncas mysess;\nlibname tgt cas caslib="${caslib}" sessref=mysess;\n\nlibname dbx spark platform=databricks\n   server="${value('host')}"\n   port=${value('port')}\n   schema="${value('schema')}"\n   user="token"\n   authdomain="${value('authDomain')}"\n   httpPath="${value('httpPath')}"\n   properties="EnableArrow=0";\n\nproc casutil incaslib="${caslib}";\n   droptable casdata="${target}" quiet;\nquit;\n\ndata tgt.${target} (promote=yes);\n   set dbx.${source};\nrun;\n${$('saveToDisk').checked ? `\nproc casutil incaslib="${caslib}" outcaslib="${caslib}";\n   save casdata="${target}" casout="${target.toLowerCase()}.sashdat" replace;\nquit;` : ''}\n\n%mend;\n%load_from_databricks();`;
  }
  return code;
}

function renderCode() {
  const output = $('codeOutput');
  output.textContent = makeCode();
  $('pipelineCaslib').textContent = `${value('caslib') || 'DB_DEMO'} · promoted`;
  $('codeTitle').textContent = `${state.method === 'spark' ? 'The SAS connection' : state.method === 'jdbc' ? 'A JDBC route' : 'A native CAS load'}, made visible.`;
}

function renderTabs() {
  const box = $('catalogTabs');
  box.innerHTML = Object.keys(sources).map(k => `<button type="button" class="source-tab${k === state.source ? ' active' : ''}" data-source="${k}">${sources[k].label}</button>`).join('');
  box.querySelectorAll('.source-tab').forEach(btn => btn.addEventListener('click', () => { state.source = btn.dataset.source; renderTabs(); renderCatalog($('searchInput').value); }));
}

function renderCatalog(filter = '') {
  const items = sources[state.source].items;
  const filtered = items.filter(item => item.name.toLowerCase().includes(filter.toLowerCase()));
  $('resultCount').textContent = `${filtered.length} ${filtered.length === 1 ? 'table' : 'tables'}`;
  $('catalogList').innerHTML = filtered.length ? filtered.map(item => `<div class="catalog-row" data-table="${item.name}" data-loadable="${item.loadable}"><div class="catalog-name"><span class="table-icon">${item.type === 'FILE' ? 'F' : 'T'}</span><span><strong>${item.name}</strong><small>${item.detail}</small></span></div><span class="catalog-type">${item.type}</span><span class="catalog-size">${item.size}</span><span class="row-arrow">→</span></div>`).join('') : '<div class="catalog-row"><span class="catalog-meta">No matching tables.</span></div>';
  document.querySelectorAll('.catalog-row[data-table]').forEach(row => row.addEventListener('click', () => {
    if (row.dataset.loadable === 'true') {
      $('sourceTable').value = row.dataset.table;
      $('targetTable').value = row.dataset.table;
      renderCode();
      showToast(`${row.dataset.table} set as the source table. The SAS code above is updated.`);
    } else {
      showToast(`${row.dataset.table} is a file in caslib ${DS.cas.caslib}. Load it with PROC CASUTIL.`);
    }
  }));
}

async function copyText(text) {
  try {
    await navigator.clipboard.writeText(text);
    return true;
  } catch (err) {
    const area = document.createElement('textarea');
    area.value = text;
    area.style.position = 'fixed';
    area.style.opacity = '0';
    document.body.appendChild(area);
    area.select();
    let ok = false;
    try { ok = document.execCommand('copy'); } catch (e) { ok = false; }
    area.remove();
    return ok;
  }
}

function showToast(message) {
  const toast = $('toast');
  toast.textContent = message;
  toast.classList.add('show');
  window.clearTimeout(showToast.timer);
  showToast.timer = window.setTimeout(() => toast.classList.remove('show'), 2600);
}

document.querySelectorAll('.method-tab').forEach(tab => tab.addEventListener('click', () => {
  document.querySelectorAll('.method-tab').forEach(item => item.classList.remove('active'));
  tab.classList.add('active');
  state.method = tab.dataset.method;
  renderCode();
}));

$('generateButton').addEventListener('click', () => { renderCode(); showToast('SAS connection recipe refreshed'); });
$('caslib').addEventListener('change', renderCode);
$('saveToDisk').addEventListener('change', renderCode);
$('searchInput').addEventListener('input', (event) => renderCatalog(event.target.value));
$('copyButton').addEventListener('click', async () => { showToast((await copyText(makeCode())) ? 'SAS code copied to clipboard' : 'Copy failed: select the code and copy it manually'); });
$('downloadButton').addEventListener('click', () => { const blob = new Blob([makeCode()], { type: 'text/plain' }); const link = document.createElement('a'); link.href = URL.createObjectURL(blob); link.download = 'viya_bridge_connection.sas'; link.click(); URL.revokeObjectURL(link.href); showToast('SAS file downloaded'); });
/* Live mode: when served by webapp/server.py the buttons below run real SAS on Viya. */
const live = { on: false };
const busy = async (button, label, work) => {
  const original = button.innerHTML;
  button.disabled = true;
  button.textContent = label;
  try { return await work(); } finally { button.disabled = false; button.innerHTML = original; }
};

$('connectButton').addEventListener('click', async () => {
  const button = $('connectButton');
  if (!live.on) { button.innerHTML = '<span class="pulse-icon"></span> Connection verified'; showToast('Demo handshake complete: CAS server is reachable'); return; }
  try {
    const res = await busy(button, 'Connecting...', () => fetch('/api/status?deep=1').then((r) => r.json().then((j) => { if (!r.ok || !j.ok) throw new Error(j.error || 'Connection failed'); return j; })));
    $('connectionResult').innerHTML = `<span class="result-icon">✓</span><span><strong>Connected to Viya</strong><small>${res.name || res.user} · ${res.context}</small></span>`;
    showToast('Connected to Viya as ' + res.user);
  } catch (err) { Live.fail('Connection test failed', err); }
});

$('runButton').addEventListener('click', async () => {
  const source = value('sourceTable');
  try {
    const res = await busy($('runButton'), 'Loading...', () => Live.post('/api/load', { source, target: value('targetTable') }));
    Live.show(`${res.source} loaded into CASUSER.${res.target}`, `${res.rows.toLocaleString('en-US')} rows copied from Databricks and promoted. Targets are always written to your CASUSER caslib, because DB_DEMO is a read-only Databricks caslib.`);
    $('pipelineCaslib').textContent = `CASUSER.${res.target} · promoted`;
  } catch (err) { Live.fail('Load failed', err); }
});

$('readinessButton').addEventListener('click', async () => {
  if (!live.on) { showToast('Readiness checks: keys, gaps, missingness, duplicates'); return; }
  const table = value('targetTable') || value('sourceTable');
  try {
    const res = await busy($('readinessButton'), 'Profiling...', () => Live.post('/api/profile', { table }));
    Live.show(`Readiness check for ${res.table}`, 'Row counts, missing values and ranges per numeric column, computed in CAS.', res);
  } catch (err) { Live.fail('Readiness check needs the table loaded first. Use Load into Viya.', err); }
});

Live.ready().then((status) => {
  if (!status) return;
  live.on = true;
  $('runButton').hidden = false;
  const badge = $('connectBadge');
  if (status.ok) { badge.innerHTML = `<span class="status-dot"></span> Live · ${status.user}`; }
  else { badge.innerHTML = '<span class="status-dot"></span> Server up, Viya not connected'; showToast(status.error); }
});
$('helpButton').addEventListener('click', () => showToast('Choose a method, tune the recipe, then generate SAS'));

renderCode();
renderTabs();
renderCatalog();
