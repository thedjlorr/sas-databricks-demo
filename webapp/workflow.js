const $ = (id) => document.getElementById(id);

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

$('joinButton').addEventListener('click', () => {
  $('joinCode').textContent = makeJoinCode();
  $('joinCodeWrap').hidden = false;
  $('joinStatus').textContent = $('promoteToggle').checked ? 'Promotion requested for approval' : 'Program ready for SAS Studio';
  showToast('SAS Studio join program drafted');
});

$('copyJoin').addEventListener('click', async () => {
  await navigator.clipboard.writeText(makeJoinCode());
  showToast('Join program copied to clipboard');
});

$('buildReport').addEventListener('click', () => {
  $('buildReport').textContent = 'VA brief ready';
  showToast(`${document.querySelector('.report-card.selected').dataset.report} brief prepared`);
});

$('runModel').addEventListener('click', () => {
  $('modelResult').hidden = false;
  $('saveRow').hidden = false;
  $('runModel').textContent = 'Run complete ✓';
  showToast('AutoML run complete: champion model selected');
});

$('saveScores').addEventListener('change', (event) => {
  $('saveButton').disabled = !event.target.checked;
  $('pushStatus').textContent = event.target.checked ? 'Ready to save and route the scores' : 'Save the scored dataset first';
});

$('saveButton').addEventListener('click', () => {
  $('saveButton').textContent = 'Dataset saved ✓';
  $('pushToggle').disabled = false;
  $('pushStatus').textContent = 'Choose whether to push the saved data back';
  showToast('Customer risk scores saved in Viya');
});

$('pushToggle').addEventListener('change', (event) => {
  $('pushButton').disabled = !event.target.checked;
  $('pushStatus').textContent = event.target.checked ? 'Write-back requires confirmation' : 'Write-back is off';
});

$('pushButton').addEventListener('click', () => {
  $('pushButton').textContent = 'Write-back queued ✓';
  $('pushStatus').textContent = 'Demo request ready for Databricks approval';
  showToast('Databricks write-back request prepared');
});