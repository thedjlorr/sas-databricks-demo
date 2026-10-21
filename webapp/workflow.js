const $ = (id) => document.getElementById(id);
const live = { on: false };
const state = { base: null };
const busy = async (button, label, work) => {
  const original = button.innerHTML;
  button.disabled = true;
  button.textContent = label;
  try { return await work(); } finally { button.disabled = false; button.innerHTML = original; }
};

/* Fill the three table pickers with every table found in Databricks (see datasets.js). */
(function fillTablePickers() {
  const tables = window.DATASETS.databricks.tables;
  const defaults = { tableCustomer: 'CUSTOMER_PROFILE', tableAccount: 'ACCOUNT_SUMMARY', tableBehavior: 'FINANCIAL_TRANSACTIONS' };
  Object.keys(defaults).forEach((id) => {
    const select = document.getElementById(id);
    select.innerHTML = '';
    tables.forEach((t) => {
      const option = document.createElement('option');
      option.textContent = t.name;
      option.title = `${t.cols} columns, ${t.rows.toLocaleString('en-US')} rows`;
      select.appendChild(option);
    });
    select.value = defaults[id];
  });
})();


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
  showToast.timer = window.setTimeout(() => toast.classList.remove('show'), 2800);
}

function makeJoinCode() {
  const customer = $('tableCustomer').value;
  const account = $('tableAccount').value;
  const behavior = $('tableBehavior').value;
  const key = $('joinKey').value.trim() || 'CUSTOMER_ID';
  const output = $('outputTable').value.trim() || 'CUSTOMER_RISK_BASE';
  const promotion = $('promoteToggle').checked ? ' (promote=yes)' : '';
  return `%macro build_customer_base();\n\nlibname db_test cas caslib="DB_TEST";\n\nproc fedsql sessref=casauto;\n   create table db_test.${output}${promotion} as\n   select c.*, a.*, b.*\n   from db_test.${customer} as c\n   left join db_test.${account} as a on c.${key} = a.${key}\n   left join db_test.${behavior} as b on c.${key} = b.${key};\nquit;\n\n%mend;\n%build_customer_base();`;
}

document.querySelectorAll('.report-card').forEach((card) => card.addEventListener('click', () => {
  document.querySelectorAll('.report-card').forEach((item) => item.classList.remove('selected'));
  card.classList.add('selected');
  $('reportResultTitle').textContent = `${card.dataset.report} selected`;
}));

$('joinButton').addEventListener('click', async () => {
  $('joinCode').textContent = makeJoinCode();
  $('joinCodeWrap').hidden = false;
  if (!live.on) {
    $('joinStatus').textContent = $('promoteToggle').checked ? 'Promotion requested for approval' : 'Program ready for SAS Studio';
    showToast('SAS Studio join program drafted');
    return;
  }
  const button = $('joinButton');
  try {
    const res = await busy(button, 'Joining in Viya...', () => Live.post('/api/join', {
      customer: $('tableCustomer').value, account: $('tableAccount').value, behavior: $('tableBehavior').value,
      key: $('joinKey').value.trim() || 'PRIMARY_KEY', output: $('outputTable').value.trim() || 'CUSTOMER_RISK_BASE'
    }));
    state.base = res.target;
    $('joinStatus').textContent = `Joined in CAS: CASUSER.${res.target}, ${res.rows.toLocaleString('en-US')} rows, ${res.cols} columns`;
    Live.show(`Joined table ${res.target} is ready`, `${res.rows.toLocaleString('en-US')} customers and ${res.cols} columns, built in CAS from the three Databricks tables on your join key.`);
  } catch (err) { $('joinStatus').textContent = 'Join failed'; Live.fail('Join failed', err); }
});

$('copyJoin').addEventListener('click', async () => {
  showToast((await copyText(makeJoinCode())) ? 'Join program copied to clipboard' : 'Copy failed: select the code and copy it manually');
});

$('buildReport').addEventListener('click', () => {
  $('buildReport').textContent = 'VA brief ready';
  showToast(`${document.querySelector('.report-card.selected').dataset.report} brief prepared`);
});

$('runModel').addEventListener('click', async () => {
  if (!live.on) {
    $('modelResult').hidden = false;
    $('saveRow').hidden = false;
    $('runModel').textContent = 'Run complete ✓';
    showToast('AutoML run complete: champion model selected');
    return;
  }
  if (!state.base) { showToast('Join the three tables first (step 01).'); return; }
  try {
    const res = await busy($('runModel'), 'Training in CAS...', () => Live.post('/api/model', { table: state.base }));
    const m = res.metrics;
    const row = Object.fromEntries(m.columns.map((c, i) => [c, m.rows[0][i]]));
    $('modelName').textContent = row.model;
    $('modelDetail').textContent = `${(row.n_train + row.n_valid).toLocaleString('en-US')} accounts (${row.n_train.toLocaleString('en-US')} train, ${row.n_valid.toLocaleString('en-US')} validation) · validation AUC ${row.auc.toFixed(3)} · KS ${row.ks.toFixed(3)} · misclassification ${(row.misclass * 100).toFixed(1)}%`;
    $('modelResult').hidden = false;
    $('saveRow').hidden = false;
    $('runModel').textContent = 'Run complete ✓';
    if (res.importance) Live.show('What drives the score', 'Top inputs by relative importance in the gradient boosting model (target coll = Y).', { columns: res.importance.columns, rows: res.importance.rows.slice(0, 10) });
  } catch (err) { Live.fail('Model run failed', err); }
});

$('saveScores').addEventListener('change', (event) => {
  $('saveButton').disabled = !event.target.checked;
  $('pushStatus').textContent = event.target.checked ? 'Ready to save and route the scores' : 'Save the scored dataset first';
});

$('saveButton').addEventListener('click', async () => {
  if (!live.on) {
    $('saveButton').textContent = 'Dataset saved ✓';
    $('pushToggle').disabled = false;
    $('pushStatus').textContent = 'Choose whether to push the saved data back';
    showToast('Customer risk scores saved in Viya');
    return;
  }
  try {
    const res = await busy($('saveButton'), 'Saving...', () => Live.post('/api/save', { table: state.base }));
    $('saveButton').textContent = 'Dataset saved ✓';
    $('pushToggle').disabled = false;
    $('pushStatus').textContent = `Saved ${res.rows.toLocaleString('en-US')} scores to CASUSER.${res.target} and ${res.file}`;
    showToast('Customer risk scores saved in Viya');
  } catch (err) { Live.fail('Save failed', err); }
});

$('pushToggle').addEventListener('change', (event) => {
  $('pushButton').disabled = !event.target.checked;
  $('pushStatus').textContent = event.target.checked ? 'Write-back requires confirmation' : 'Write-back is off';
});

$('pushButton').addEventListener('click', () => {
  if (live.on) {
    $('pushStatus').textContent = 'Write-back to Databricks is not enabled in this build';
    showToast('Nothing was written to Databricks. Write-back needs an explicit sign-off first.');
    return;
  }
  $('pushButton').textContent = 'Write-back queued ✓';
  $('pushStatus').textContent = 'Demo request ready for Databricks approval';
  showToast('Databricks write-back request prepared');
});

Live.ready().then((status) => {
  if (!status) return;
  live.on = true;
  if (!status.ok) { showToast(status.error); return; }
  showToast(`Live mode: connected to Viya as ${status.user}`);
  $('joinKey').value = $('joinKey').value || 'PRIMARY_KEY';
});
