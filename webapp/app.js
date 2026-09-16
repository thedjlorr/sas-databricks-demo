const catalog = [
  { name: 'CUSTOMER_PROFILE', detail: 'DB_DEMO · promoted', type: 'TABLE', size: 'Auto-discovered' },
  { name: 'FINANCIAL_TRANSACTIONS', detail: 'DB_DEMO · promoted', type: 'TABLE', size: 'Auto-discovered' },
  { name: 'HMEQ', detail: 'DB_DEMO · promoted', type: 'TABLE', size: 'Auto-discovered' },
  { name: 'AUTOLOAN_1', detail: 'DB_DEMO · promoted', type: 'TABLE', size: 'Auto-discovered' },
  { name: 'LOAN_DATA_SET_CSV', detail: 'DB_DEMO · promoted', type: 'TABLE', size: 'Auto-discovered' },
  { name: 'STATE_EXP', detail: 'DB_DEMO · generated', type: 'TABLE', size: 'Auto-discovered' }
];

const state = { method: 'spark' };
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

function renderCatalog(filter = '') {
  const filtered = catalog.filter(item => item.name.toLowerCase().includes(filter.toLowerCase()));
  $('resultCount').textContent = `${filtered.length} ${filtered.length === 1 ? 'asset' : 'assets'}`;
  $('catalogList').innerHTML = filtered.length ? filtered.map(item => `<div class="catalog-row" data-table="${item.name}"><div class="catalog-name"><span class="table-icon">${item.type === 'REPORT' ? 'R' : 'T'}</span><span><strong>${item.name}</strong><small>${item.detail}</small></span></div><span class="catalog-type">${item.type}</span><span class="catalog-size">${item.size}</span><span class="row-arrow">→</span></div>`).join('') : '<div class="catalog-row"><span class="catalog-meta">No matching assets.</span></div>';
  document.querySelectorAll('.catalog-row[data-table]').forEach(row => row.addEventListener('click', () => showToast(`${row.dataset.table}: schema preview coming next`)));
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
$('copyButton').addEventListener('click', async () => { await navigator.clipboard.writeText(makeCode()); showToast('SAS code copied to clipboard'); });
$('downloadButton').addEventListener('click', () => { const blob = new Blob([makeCode()], { type: 'text/plain' }); const link = document.createElement('a'); link.href = URL.createObjectURL(blob); link.download = 'viya_bridge_connection.sas'; link.click(); URL.revokeObjectURL(link.href); showToast('SAS file downloaded'); });
$('connectButton').addEventListener('click', () => { const button = $('connectButton'); button.innerHTML = '<span class="pulse-icon"></span> Connection verified'; showToast('Demo handshake complete: CAS server is reachable'); });
$('readinessButton').addEventListener('click', () => showToast('Readiness checks: keys, gaps, missingness, duplicates'));
$('helpButton').addEventListener('click', () => showToast('Choose a method, tune the recipe, then generate SAS'));

renderCode();
renderCatalog();
