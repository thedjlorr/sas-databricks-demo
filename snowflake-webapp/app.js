(function () {
  const $ = (s, r = document) => r.querySelector(s);
  const view = $("#view");
  const fmt = n => Math.round(n).toLocaleString("en-US");
  const esc = s => String(s).replace(/[&<>]/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;" }[c]));
  const pct = (x, d = 1) => (x * 100).toFixed(d) + "%";
  const money = n => Math.abs(n) >= 1e6 ? "$" + (n / 1e6).toFixed(1) + "M" : Math.abs(n) >= 1e3 ? "$" + (n / 1e3).toFixed(0) + "K" : "$" + Math.round(n);
  const usd = n => "$" + fmt(n);
  const MON = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
  const monShort = p => MON[+p.slice(5) - 1] + " " + p.slice(2, 4);
  const monLong = p => MON[+p.slice(5) - 1] + " " + p.slice(0, 4);
  const objs = t => t.rows.map(r => Object.fromEntries(t.columns.map((c, i) => [c.toLowerCase(), r[i]])));
  const TIERS = ["Super Prime", "Prime", "Near Prime", "Subprime"];
  const BANDS = ["Low", "Medium", "High", "Very High"];
  const BAND_COL = { "Low": "#1f9d55", "Medium": "#e8a317", "High": "#ea580c", "Very High": "#b4002a" };

  function toast(msg) { const t = $("#toast"); t.textContent = msg; t.classList.add("show"); setTimeout(() => t.classList.remove("show"), 1800); }
  function copy(text) {
    const done = () => toast("SAS copied");
    const fallback = () => { const a = document.createElement("textarea"); a.value = text; document.body.appendChild(a); a.select(); try { document.execCommand("copy"); done(); } catch (e) { toast("Copy failed, select the code by hand"); } a.remove(); };
    if (navigator.clipboard && window.isSecureContext) navigator.clipboard.writeText(text).then(done, fallback); else fallback();
  }

  // ---- state: live results (server running) override the saved run ----
  const live = { on: false, user: null, score: null, ets: null, tables: null, busy: "", wb: null };
  const SC = () => live.score || SCORE_STATIC;
  const ET = () => live.ets || ETS_STATIC;
  const T = n => objs(SC()[n]);
  async function api(path, body) {
    const r = await fetch("/api/" + path, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body || {}) });
    const j = await r.json().catch(() => ({ ok: false, error: "Unreadable response from the server" }));
    if (!j.ok) throw new Error(j.error || "HTTP " + r.status);
    return j;
  }

  // ---- building blocks ----
  const codeBlock = (key, title) => `<details class="card" open><summary>${title || "SAS code"}</summary><div class="codebox"><button class="copy" data-copy="${key}">Copy</button><pre>${esc(SAS_CODE[key])}</pre></div></details>`;
  const lineage = (from, steps, out) => `<div class="lineage"><code>${from}</code> &rarr; ${steps.map(s => `<span>${s}</span> &rarr;`).join(" ")} <code>${out}</code></div>`;
  const head = (h, p) => `<h1>${h}</h1><p class="lede">${p}</p>`;
  const takeaway = (t, w, cls = "") => `<div class="take ${cls}"><b>${t}</b> ${w}</div>`;
  const tile = (cls, label, val, small) => `<div class="tile ${cls}"><small>${label}</small><b${small ? ' style="font-size:21px"' : ""}>${val}</b></div>`;
  const hbars = (rows, o) => rows.map(r => `<div class="hb"><span>${o.label(r)}</span><div class="trk"><i style="width:${Math.max(1.5, o.val(r) / o.max * 100)}%;background:${o.color(r)}"></i></div><b>${o.text(r)}</b></div>`).join("");
  const liveBar = (what, key, busyKey) => {
    const lbl = live.busy === busyKey ? "Running in Viya..." : (live[key] ? "Run again" : `Run ${what} in Viya now`);
    return !live.on
      ? `<div class="live off">Static demo. Showing the saved Viya run of 27 Oct 2026. Run <code>python snowflake-webapp/server.py</code> to run it live against SNOWLIB.</div>`
      : `<div class="live on">${live[key] ? "Live result from Viya, just now." : "Live mode is on. Showing the saved run."} <button class="btn" data-act="${busyKey}" ${live.busy ? "disabled" : ""}>${lbl}</button> <span class="muted">About 30 seconds. Reads SNOWLIB and writes WEB_SF_* tables to your CASUSER.</span></div>`;
  };
  const synth = () => `<span class="syn">Synthetic NMAC-style data</span>`;

  // ---- write-back and connection cards (Architecture tab) ----
  function wbCard() {
    const wb = live.wb, k = T("web_kpi")[0], bands = BANDS.map(b => T("web_bands").find(x => x.risk_band === b)).filter(Boolean);
    const flow = `<div class="wbflow"><div><b>1  CASUSER.WEB_SF_SCORES_OUT</b><small>LOAN_ID, CUSTOMER_ID, SNAPSHOT_DATE, PD, RISK_BAND, BALANCE, EXPECTED_LOSS, SCORED_AT</small></div><span>&rarr;</span><div><b>2  SNOWLIB table.save</b><small>SAS Data Connector to Snowflake</small></div><span>&rarr;</span><div class="${wb ? "done" : ""}"><b>3  RND_DB.SEFORD.NMAC_AUTO_SCORES</b><small>${wb ? fmt(wb.sf_rows) + " loans, counted by Snowflake" : "new table, not written yet"}</small></div></div>`;
    const summary = `<div class="take ok"><b>${live.score ? "Scored" : "Last saved run scored"} ${fmt(k.loans)} live loans</b> (${fmt(k.customers)} customers, ${money(k.balance)} outstanding). Average PD ${pct(k.avg_pd)}, expected loss ${money(k.expected_loss)}.
      <div class="chips">${bands.map(b => `<span><b>${fmt(b.loans)}</b> ${b.risk_band}</span>`).join("")}</div>
      <div class="muted" style="margin-top:8px">Validation AUC ${T("web_result")[0].auc.toFixed(3)} on held-out customers. Step 2 sends one row per loan. You do not need to review every report tab first, they are drawn from this same scoring run.</div></div>`;
    const status = wb ? `<div class="take ok"><b>Written and verified.</b> Snowflake counted ${fmt(wb.sf_rows)} loans${wb.sf_el != null ? ", expected loss " + money(wb.sf_el) : ""}${wb.cas_rows ? ", Viya sent " + fmt(wb.cas_rows) + (wb.cas_rows === wb.sf_rows ? ", counts match" : ", counts differ") : ""}${wb.sf_avg_pd != null ? ", average PD " + pct(wb.sf_avg_pd) : ""}. ${wb.created ? "Created " + esc(wb.created) + "." : ""}</div>` : `<p class="muted">Creates one new table in Snowflake. No existing table is changed, and re-running replaces only NMAC_AUTO_SCORES.</p>`;
    const act = !live.on ? `<p class="muted">Live mode runs this step for real. In the static demo this panel shows the design only.</p>`
      : `<div class="tools"><button class="btn" data-act="score" ${live.busy ? "disabled" : ""}>${live.busy === "score" ? "Scoring in Viya, about 30 seconds..." : live.score ? "Step 1 done: scored in Viya (run again)" : "Step 1: Score in Viya now"}</button></div>
         <label class="chk"><input type="checkbox" id="wbok" ${live.score ? "" : "disabled"}> I approve: create or replace RND_DB.SEFORD.NMAC_AUTO_SCORES in Snowflake with ${live.score ? fmt(k.loans) + " scored loans" : "the scores from my last run"}</label>
         <div class="tools"><button class="btn" data-act="writeback" id="wbbtn" disabled>Step 2: Write scores back to Snowflake</button><span class="muted">${live.score ? "Tick the box to enable." : "Unlocks after step 1."}</span></div>`;
    return `<div class="card"><h2>Write-back: scores return to Snowflake</h2>${flow}${status}${live.on ? summary : ""}${act}<div id="wb-out" class="muted"></div></div>`;
  }
  const connectCard = () => !live.on ? "" : `<div class="card"><h2>Live connection</h2><p class="muted">Runs SAS on Viya against SNOWLIB. Reads only, nothing is written to Snowflake.</p><div class="tools"><button class="btn" data-act="check">Test SNOWLIB connection</button><button class="btn" data-act="load">Load the loan tables into Viya</button></div><div id="conn-out" class="muted">Not run yet.</div></div>`;

  async function runAct(act, btn) {
    const out = $("#conn-out");
    btn.disabled = true;
    try {
      if (act === "check") {
        out.textContent = "Asking Snowflake...";
        const r = objs(await api("check"))[0];
        out.innerHTML = `Snowflake ${esc(r.sf_version)} answered as user <b>${esc(r.sf_user)}</b>, role ${esc(r.sf_role)}, warehouse ${esc(r.sf_warehouse)}, server time ${esc(r.sf_time)}. These values come from Snowflake, not from a copy.`;
      } else if (act === "load") {
        out.textContent = "Loading into CAS...";
        const r = objs(await api("load"))[0];
        out.innerHTML = `Snowflake counted <b>${fmt(r.sf_loans)}</b> loans, ${fmt(r.sf_customers)} customers, ${fmt(r.sf_active)} active, ${money(r.sf_balance)} outstanding. CAS now holds <b>${fmt(r.cas_loans)}</b> loans and ${fmt(r.cas_snapshot)} snapshot rows in CASUSER. ${r.sf_loans === r.cas_loans ? "Counts match." : "Counts differ."}`;
      } else if (act === "writeback") {
        $("#wb-out").textContent = "Writing to Snowflake, then asking Snowflake to count it...";
        const r = objs(await api("writeback", { confirm: true }))[0];
        live.wb = { sf_rows: r.sf_rows, sf_avg_pd: r.sf_avg_pd, sf_el: r.sf_el, cas_rows: r.cas_rows, created: String(r.scored_at).replace("T", " ") };
        show(current); toast("Scores written to Snowflake");
        return;
      } else if (act === "score" || act === "ets") {
        live.busy = act; show(current);
        const j = await api(act === "ets" ? "forecast" : "score");
        live[act === "ets" ? "ets" : "score"] = j.tables; live.busy = ""; show(current); toast(act === "ets" ? "ETS forecast run in Viya" : "Scored in Viya");
        return;
      }
    } catch (e) {
      live.busy = "";
      const wo = $("#wb-out");
      if (act === "writeback" && wo) wo.innerHTML = `<span class="err">${esc(e.message)}</span>`;
      else if (out && (act === "check" || act === "load")) out.innerHTML = `<span class="err">${esc(e.message)}</span>`;
      else { toast("Failed: " + e.message.slice(0, 90)); show(current); }
    }
    btn.disabled = btn.id === "wbbtn" ? !($("#wbok") && $("#wbok").checked) : false;
  }

  // ---- tabs ----
  const tabs = {
    data() {
      const rows = live.tables || SF_TABLES, colsCache = {};
      view.innerHTML = head("Snowflake data", "Every table in RND_DB.SEFORD, read through the SNOWLIB caslib. The three NMAC_AUTO tables are the auto loan book this demo runs on.") + `
        <div class="grid g2"><div class="card">
          <div class="tools"><input id="q" placeholder="Filter tables"><select id="f"><option value="">All tables</option><option value="nmac">NMAC auto loan book</option><option value="legacy">Earlier demo tables</option><option value="sandbox">Shared sandbox</option></select>${live.on ? `<button class="btn" id="rf">Refresh from Snowflake</button>` : ""}<span class="count" id="cnt"></span></div>
          <table><thead><tr><th>Table</th><th class="n">Rows</th><th class="n">Columns</th><th>Created</th><th>Use</th></tr></thead><tbody id="tb"></tbody></table>
        </div><div class="card" id="detail"></div></div>`;
      let sel = "NMAC_AUTO_LOANS";
      const label = { nmac: "NMAC auto", legacy: "Earlier", sandbox: "Sandbox" };
      const draw = () => {
        const q = $("#q").value.toLowerCase(), f = $("#f").value;
        const list = rows.filter(t => t.name.toLowerCase().includes(q) && (!f || t.role === f));
        $("#cnt").textContent = `${list.length} of ${rows.length} tables`;
        $("#tb").innerHTML = list.map(t => `<tr class="pick ${t.name === sel ? "sel" : ""}" data-n="${t.name}"><td><b>${t.name}</b></td><td class="n">${fmt(t.rows)}</td><td class="n">${t.cols}</td><td>${t.created}</td><td><span class="badge ${t.role === "nmac" ? "hot" : ""}">${label[t.role]}</span></td></tr>`).join("");
        const t = rows.find(x => x.name === sel) || rows[0];
        const cols = SF_COLUMNS[sel] || colsCache[sel];
        if (!cols && live.on && !colsCache["_b" + sel]) {
          colsCache["_b" + sel] = 1;
          api("columns", { table: sel }).then(j => { colsCache[sel] = j.rows.map(r => [r[0], String(r[1])]); if (sel === j.table) draw(); }).catch(() => {});
        }
        $("#detail").innerHTML = `<h2>${t.name}</h2><p class="muted">RND_DB.SEFORD.${t.name}<br>${fmt(t.rows)} rows, ${t.cols} columns, created ${t.created}</p><p>${t.note || "No description recorded."}</p>` +
          (cols ? `<div class="cols">${cols.map(c => `<div><span>${c[0]}</span><span>${c[1]}</span></div>`).join("")}</div>` : `<p class="muted">${live.on ? "Reading the column list from SNOWLIB..." : "Column list is read live from SNOWLIB. Shown here for the NMAC_AUTO tables."}</p>`);
      };
      $("#q").oninput = draw; $("#f").onchange = draw;
      const rf = $("#rf");
      if (rf) rf.onclick = async () => {
        rf.disabled = true; rf.textContent = "Reading INFORMATION_SCHEMA...";
        try {
          const j = await api("tables?refresh=1");
          live.tables = objs(j).map(r => { const k = SF_TABLES.find(t => t.name === String(r.name).toUpperCase()); return { name: String(r.name).toUpperCase(), rows: r.row_count, cols: r.cols, created: r.created, role: k ? k.role : "sandbox", note: k ? k.note : "" }; });
          toast("Table list read from Snowflake"); show("data");
        } catch (e) { rf.disabled = false; rf.textContent = "Refresh from Snowflake"; toast("Failed: " + e.message.slice(0, 80)); }
      };
      draw();
    },

    arch() {
      view.innerHTML = head("Architecture", "Snowflake stays the system of record. Viya reads it live, builds the risk tables in memory, and sends decisions and scores back out.") + `
        <div class="arch">${LAYERS.map(l => `<div class="layer ${l.tone}"><h3>${l.title}</h3><div class="sub">${l.sub}</div>${l.items.map(i => { const w = i.name === "SEFORD.NMAC_AUTO_SCORES" && live.wb; return `<div class="node ${w ? "done" : i.tag === "target" ? "target" : ""}"><span class="badge">${w ? "written" : i.tag}</span><strong>${i.name}</strong><small>${w ? fmt(live.wb.sf_rows) + " loans, verified by Snowflake" : i.meta}</small></div>`; }).join("")}</div>`).join("")}</div>
        <div style="margin-top:18px"></div>${wbCard()}${connectCard()}
        <div class="card"><h2>How the data moves</h2><ol class="steps">
          <li><b>Connect.</b> SNOWLIB is a global, permanent caslib. Credentials are masked and queries push down into Snowflake.</li>
          <li><b>Load.</b> The loan and snapshot tables load into CASUSER. Snowflake counts the rows itself so the two sides can be compared.</li>
          <li><b>Score.</b> A gradient boosting model learns from past snapshots with a known outcome and gives every live loan a 12-month default probability (PD), a risk band and an expected loss.</li>
          <li><b>Summarize.</b> CAS builds the report tables: credit tier, risk band, heatmap, dealer view, collector worklist, 12-month outlook.</li>
          <li><b>Forecast.</b> Four ETS models compete on the 36-month delinquency history and the best one forecasts three months ahead.</li>
          <li><b>Act.</b> Scores are written back to Snowflake as NMAC_AUTO_SCORES, and the worklist feeds collector queues.</li>
        </ol></div>` + codeBlock("connect", "SAS: prove the connection") + codeBlock("load", "SAS: Snowflake to CAS") + codeBlock("writeback", "SAS: write scores back to Snowflake");
    },

    kpi() {
      const k = T("web_kpi")[0], r = T("web_result")[0], tier = TIERS.map(t => T("web_tier").find(x => x.credit_tier === t)).filter(Boolean);
      const bands = BANDS.map(b => T("web_bands").find(x => x.risk_band === b)).filter(Boolean), maxBal = Math.max(...bands.map(b => b.balance));
      const prod = T("web_product").sort((a, b) => b.balance - a.balance), maxP = Math.max(...prod.map(p => p.balance));
      view.innerHTML = head("Portfolio overview", "The live auto loan book at 30 Sep 2026, scored by a gradient boosting model that was validated on customers it was not trained on.") + synth() +
        lineage("SNOWLIB.NMAC_AUTO_*", ["load", "score"], "CASUSER.WEB_SF_LIVE") + liveBar("scoring", "score", "score") + `
        <div class="tiles"><div class="tile t-blue"><small>Active loans</small><b>${fmt(k.loans)}</b></div><div class="tile t-violet"><small>Customers</small><b>${fmt(k.customers)}</b></div><div class="tile t-teal"><small>Outstanding balance</small><b>${money(k.balance)}</b></div><div class="tile t-red"><small>30+ days past due</small><b>${pct(k.delinq_rate, 2)}</b></div><div class="tile t-orange"><small>High-risk balance</small><b>${money(k.high_risk_balance)}</b></div><div class="tile t-green"><small>Model AUC (validation)</small><b>${r.auc.toFixed(3)}</b></div></div>` +
        takeaway(`${fmt(k.high_risk_loans)} loans (${pct(k.high_risk_loans / k.loans, 0)}) are High or Very High risk,`, `holding ${money(k.high_risk_balance)} of balance. Expected loss on the whole book is ${money(k.expected_loss)} at an assumed ${pct(r.lgd, 0)} loss given default. AUC ${r.auc.toFixed(3)} is measured on ${fmt(r.n_valid)} loan-months from customers held out of training.`) + `
        <div class="grid g2"><div class="card"><h2>12-month default rate by credit tier: model vs actual</h2><p class="muted">Held-out customers. A calibrated model puts the two bars level.</p>
          ${tier.map(t => `<div class="pair"><div class="pl">${t.credit_tier}<small>${fmt(t.loans)} loans</small></div><div>${hbars([t], { label: () => "Actual", val: x => x.actual_rate, max: 0.17, color: () => "#0f1e3d", text: x => pct(x.actual_rate) })}${hbars([t], { label: () => "Model", val: x => x.avg_pd, max: 0.17, color: () => "#1f6fd1", text: x => pct(x.avg_pd) })}</div></div>`).join("")}</div>
        <div class="card"><h2>Balance by risk band</h2>${hbars(bands, { label: b => b.risk_band, val: b => b.balance, max: maxBal, color: b => BAND_COL[b.risk_band], text: b => money(b.balance) })}
          <h2 style="margin-top:22px">Balance by product</h2>${hbars(prod, { label: p => p.product, val: p => p.balance, max: maxP, color: () => "#1f6fd1", text: p => money(p.balance) })}</div></div>` + codeBlock("score", "SAS: train and score") + codeBlock("tier", "SAS: tier summary");
    },

    forecast() {
      const fc = T("web_fc"), bands = BANDS.map(b => T("web_bands").find(x => x.risk_band === b)).filter(Boolean), k = T("web_kpi")[0];
      const byM = {}; fc.forEach(r => { (byM[r.m] = byM[r.m] || {})[r.risk_band] = r.exp_defaults; });
      const tot = m => BANDS.reduce((a, b) => a + (byM[m][b] || 0), 0), months = Object.keys(byM).map(Number).sort((a, b) => a - b);
      const all = months.reduce((a, m) => a + tot(m), 0), max = Math.max(...months.map(tot));
      view.innerHTML = head("12-month default outlook", "Expected defaults over the next 12 months for the loans on the book today, stacked by risk band.") + synth() +
        lineage("CASUSER.WEB_SF_LIVE", ["accumulate PD by month"], "CASUSER.WEB_SF_FCM") + liveBar("scoring", "score", "score") +
        takeaway(`About ${fmt(all)} of ${fmt(k.loans)} loans are expected to reach 90+ days past due in 12 months,`, `and ${pct(bands[3].exp_defaults / all, 0)} of them come from the Very High band, which is 5% of loans. Reaching that band early is where outreach pays back.`) + `
        <div class="grid g2"><div class="card"><h2>Expected defaults per month</h2><div class="cols12">${months.map(m => `<div class="col"><div class="stk" style="height:${tot(m) / max * 100}%">${BANDS.map(b => `<i style="flex:${byM[m][b] || 0};background:${BAND_COL[b]}" title="${b}: ${(byM[m][b] || 0).toFixed(1)}"></i>`).join("")}</div><b>${tot(m).toFixed(0)}</b><span>M${m}</span></div>`).join("")}</div>
          <div class="ets-legend">${BANDS.map(b => `<span><i style="border-color:${BAND_COL[b]}"></i>${b}</span>`).join("")}</div></div>
        <div class="card"><h2>12-month result by band</h2><table><thead><tr><th>Band</th><th class="n">Loans</th><th class="n">Balance</th><th class="n">Exp. defaults</th></tr></thead><tbody>${bands.map(b => `<tr><td><b>${b.risk_band}</b></td><td class="n">${fmt(b.loans)}</td><td class="n">${money(b.balance)}</td><td class="n">${b.exp_defaults.toFixed(0)}</td></tr>`).join("")}</tbody></table>
        <p class="muted">Each loan PD is a 12-month probability, cumulative q = 1-(1-PD)^(m/12).</p></div></div>` + codeBlock("forecast12");
    },

    ets() {
      const E = ET(), rows = objs(E.web_ts), res = objs(E.web_result)[0];
      const names = { addwinters: "Holt-Winters additive", addseasonal: "Additive seasonal", linear: "Linear trend", damptrend: "Damped trend" };
      const fc = rows.filter(r => r.kind === "forecast"), end = fc[fc.length - 1], hist = rows.filter(r => r.kind === "history");
      view.innerHTML = head("Delinquency forecast (ETS)", "Four exponential smoothing models compete on 36 months of portfolio history from Snowflake. The one with the lowest error forecasts the next three months, with 95% limits.") + synth() + `
        <div class="live ${live.on ? "on" : "off"}">${live.on ? `<button class="btn" data-act="ets" ${live.busy ? "disabled" : ""}>${live.busy === "ets" ? "Running ETS in Viya..." : live.ets ? "Re-run ETS in Viya" : "Run ETS in Viya now"}</button> <span class="muted">${live.ets ? "Live result from Viya, PROC ESM." : "Showing the saved run of 27 Oct 2026."}</span>` : "Static demo, showing the saved ETS run of 27 Oct 2026. Start the server to run it live."}</div>
        <div class="tiles">${tile("t-blue", "Winning model", names[res.model] || res.model, true)}${tile("t-green", "Fit error (RMSE)", (res.rmse * 100).toFixed(2) + " pts")}${tile("t-red", monLong(end.period) + " forecast", pct(end.predict, 2))}${tile("t-teal", "95% range, " + monLong(end.period), pct(end.lower, 2) + " to " + pct(end.upper, 2), true)}</div>
        <div class="card ets-card"><h2>30+ days past due rate: actual, ETS fit and 3-month forecast</h2><div id="etsbox"></div>
          <div class="ets-legend"><span><i style="border-color:#0f1e3d"></i>Actual</span><span><i style="border-color:#0891b2;border-top-style:dashed"></i>ETS fit</span><span><i style="border-color:#c3002f"></i>Forecast</span><span><span class="b"></span>95% prediction band (LCL to UCL)</span></div></div>
        <div class="why"><div><b>Model competition</b><small>Four ETS models are fitted and ranked by error, so the choice is evidence, not a default.</small></div><div><b>Hundreds of series</b><small>The same code runs by product, credit tier, state and dealer at once (Visual Forecasting, PROC TSMODEL) rather than one chart at a time.</small></div><div><b>Governed and repeatable</b><small>The SAS program is versioned and reruns on every new Snowflake month.</small></div><div><b>Closes the loop</b><small>Forecast and scores flow back into Snowflake for collections planning, in the same platform.</small></div></div>` + codeBlock("ets", "SAS: ETS forecast");
      drawEtsChart($("#etsbox"), rows);
    },

    heatmap() {
      const h = T("web_heat"), grp = ["Current", "30-59", "60-89", "90+"], v = h.map(x => x.avg_pd), hi = Math.max(...v);
      const cell = (t, g) => { const x = h.find(r => r.credit_tier === t && r.dpd_group === g); return x ? `<td class="n" style="background:rgba(195,0,47,${(.08 + Math.sqrt(x.avg_pd / hi) * .8).toFixed(2)});color:${x.avg_pd / hi > .45 ? "#fff" : "inherit"}" title="${fmt(x.loans)} loans">${pct(x.avg_pd)}</td>` : `<td class="n muted">none</td>`; };
      view.innerHTML = head("Risk heatmap", "Average 12-month default probability by credit tier and current days past due, for the live book.") + synth() +
        lineage("CASUSER.WEB_SF_LIVE", ["group by tier, DPD bucket"], "CASUSER.WEB_HEAT") + liveBar("scoring", "score", "score") +
        takeaway("Both axes matter.", "A Subprime loan that is current carries a similar risk to a Prime loan that is 30 days late, and a 60+ day loan is high risk in every tier. A queue sorted on days past due alone misses the first group.") + `
        <div class="card"><h2>Average PD</h2><table class="heat"><thead><tr><th>Credit tier</th>${grp.map(g => `<th class="n">${g === "Current" ? "Current" : g + " DPD"}</th>`).join("")}</tr></thead><tbody>${TIERS.map(t => `<tr><td><b>${t}</b></td>${grp.map(g => cell(t, g)).join("")}</tr>`).join("")}</tbody></table><p class="muted">Hover a cell for the loan count.</p></div>` + codeBlock("heatmap");
    },

    drivers() {
      const imp = T("web_imp").map(x => ({ v: x.variable, r: parseFloat(x.relativeimportance) })).sort((a, b) => b.r - a.r).slice(0, 12);
      const nice = { credit_score: "Credit score", payment_ratio: "Last payment / scheduled", dpd: "Days past due", dti: "Debt to income", apr: "APR", n30_12m: "Times 30+ in 12 months", ltv: "Loan to value", mob: "Months on book", age: "Customer age", income: "Income", balance: "Balance", pti: "Payment to income", monthly_payment: "Monthly payment", amount_financed: "Amount financed" };
      view.innerHTML = head("Risk drivers", "What the gradient boosting model leans on most when it scores a loan.") + synth() +
        lineage("CASUSER.WEB_SF_ALL", ["train gradient boosting"], "CASUSER.WEB_SF_SCORED") + liveBar("scoring", "score", "score") +
        takeaway("Credit quality and payment behavior lead.", "Credit score, how much of the scheduled payment was actually paid, days past due and debt to income come first, which is the order a credit officer would expect. Dealer, state and vehicle model are left out of the model on purpose: there are too many of them for the number of defaults.") + `
        <div class="card"><h2>Relative importance, top 12</h2>${hbars(imp, { label: i => nice[i.v] || i.v, val: i => i.r, max: 1, color: () => "#1f6fd1", text: i => i.r.toFixed(2) })}</div>` + codeBlock("drivers");
    },

    dealers() {
      const d = T("web_dealer"), k = T("web_kpi")[0], max = Math.max(...d.map(x => x.expected_loss)), top = d.reduce((a, x) => a + x.expected_loss, 0);
      view.innerHTML = head("Dealer view", "Where expected loss sits across the dealer network, ranked by model PD times balance.") + synth() +
        lineage("CASUSER.WEB_SF_LIVE", ["group by dealer"], "CASUSER.WEB_DEALER_ALL") + liveBar("scoring", "score", "score") +
        takeaway(`The top 10 of ${k.dealers} dealers hold ${money(top)} of expected loss`, `(${pct(top / k.expected_loss, 0)} of the book). Dealers are not a model input, so this ranking reflects the loans each dealer originated, and gives collections and dealer management a shared list to act on.`) + `
        <div class="card"><table><thead><tr><th>Dealer</th><th class="n">Loans</th><th class="n">Balance</th><th class="n">30+ DPD rate</th><th class="n">Avg PD</th><th class="n">Expected loss</th><th style="width:22%"></th></tr></thead><tbody>${d.map(x => `<tr><td><b>${x.dealer_id}</b></td><td class="n">${fmt(x.loans)}</td><td class="n">${money(x.balance)}</td><td class="n">${pct(x.delinq_rate)}</td><td class="n">${pct(x.avg_pd)}</td><td class="n"><b>${usd(x.expected_loss)}</b></td><td><div class="trk"><i style="width:${x.expected_loss / max * 100}%;background:#b4002a"></i></div></td></tr>`).join("")}</tbody></table></div>` + codeBlock("dealer");
    },

    worklist() {
      const W = T("web_work"), n = T("web_work_n")[0], tot = W.reduce((a, r) => [a[0] + r.balance, a[1] + r.expected_loss], [0, 0]);
      view.innerHTML = head("Collector worklist", "Customers with a loan 30+ days past due, ranked by expected loss, so collectors start with the most money at the most risk.") + synth() +
        lineage("CASUSER.WEB_SF_LIVE", ["delinquent loans, roll up by customer"], "CASUSER.WEB_WORK_ALL") + liveBar("scoring", "score", "score") + `
        <div class="facts"><div class="fact"><b>${fmt(n.delinquent_customers)}</b><small>customers 30+ days past due</small></div><div class="fact"><b>${usd(tot[0])}</b><small>balance, top 15</small></div><div class="fact"><b>${usd(tot[1])}</b><small>expected loss, top 15 (${pct(tot[1] / n.total_el, 0)} of ${usd(n.total_el)})</small></div></div>
        <div class="card"><table><thead><tr><th>Customer</th><th class="n">Loans</th><th class="n">PD</th><th class="n">Balance</th><th class="n">Expected loss</th><th class="n">Days past due</th><th class="n">Credit score</th><th>State</th><th>Dealer</th></tr></thead><tbody>${W.map(r => `<tr><td><b>${r.customer_id}</b></td><td class="n">${r.loans}</td><td class="n">${pct(r.max_pd, 0)}</td><td class="n">${usd(r.balance)}</td><td class="n ${r.expected_loss > 15000 ? "red-cell" : ""}">${usd(r.expected_loss)}</td><td class="n">${r.max_dpd}</td><td class="n">${Math.round(r.score)}</td><td>${r.state}</td><td>${r.dealer_id}</td></tr>`).join("")}</tbody></table>
        <p class="muted">Expected loss = PD x balance x LGD (50% assumed). Red cells are over $15K. Next step: publish to Intelligent Decisioning queues.</p></div>` + codeBlock("worklist");
    }
  };

  let current = "data";
  function show(name) {
    current = name; tabs[name]();
    document.querySelectorAll("#tabs button").forEach(b => b.classList.toggle("on", b.dataset.tab === name));
    try { history.replaceState(null, "", "#" + name); } catch (e) {}
    if (!live.busy) window.scrollTo({ top: Math.min(window.scrollY, 0) });
  }
  async function detectLive() {
    const badge = $("#mode");
    try {
      const j = await (await fetch("/api/status")).json();
      if (!j.ok) throw new Error(j.error);
      live.on = true; live.user = j.user;
      badge.innerHTML = `<i class="dot"></i>Live: ${esc(j.user)}`;
      api("writeback_status").then(w => { const r = objs(w)[0]; if (r && r.sf_rows != null) { live.wb = { sf_rows: r.sf_rows, created: r.created }; if (current === "arch") show("arch"); } }).catch(() => {});
    } catch (e) { live.on = false; badge.textContent = "Static demo"; }
    show(current);
  }
  $("#tabs").onclick = e => { const b = e.target.closest("button"); if (b) { window.scrollTo(0, 0); show(b.dataset.tab); } };
  view.addEventListener("change", e => { if (e.target.id === "wbok") $("#wbbtn").disabled = !e.target.checked || !live.score; });
  view.addEventListener("click", e => {
    const c = e.target.closest("[data-copy]"); if (c) copy(SAS_CODE[c.dataset.copy]);
    const a = e.target.closest("[data-act]"); if (a && !live.busy) runAct(a.dataset.act, a);
  });
  show(tabs[location.hash.slice(1)] ? location.hash.slice(1) : "data");
  detectLive();
})();
