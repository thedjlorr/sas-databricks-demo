// ETS forecast chart: actual, fitted, 3-month forecast and 95% LCL/UCL band, drawn as inline SVG.
// rows: [{period:"2020-01", kind:"history"|"forecast", actual, predict, lower, upper}] with rates as fractions.
window.drawEtsChart = function (host, rows) {
  const W = 1000, H = 440, L = 60, R = 96, T = 34, B = 48, NS = "http://www.w3.org/2000/svg";
  const n = rows.length, firstF = rows.findIndex(r => r.kind === "forecast"), last = firstF - 1;
  const pc = v => v * 100;
  const lo = Math.floor((Math.min(...rows.map(r => pc(r.lower)).filter(Number.isFinite), ...rows.map(r => pc(r.actual ?? 99))) - 0.25) * 2) / 2;
  const hi = Math.ceil((Math.max(...rows.map(r => pc(r.upper)).filter(Number.isFinite), ...rows.map(r => pc(r.actual ?? 0))) + 0.25) * 2) / 2;
  // history takes 66% of the width, the 3 forecast months get the rest so the band and labels have room
  const hw = 0.66 * (W - L - R);
  const x = i => i <= last ? L + hw * i / last : L + hw + (W - L - R - hw) * (i - last) / (n - 1 - last), y = v => T + (H - T - B) * (1 - (pc(v) - lo) / (hi - lo));
  const mon = p => ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"][+p.slice(5) - 1] + " " + p.slice(2, 4);
  const path = (pts) => pts.map((p, i) => (i ? "L" : "M") + p[0].toFixed(1) + " " + p[1].toFixed(1)).join(" ");
  const hist = rows.slice(0, firstF);
  const actualPts = hist.map((r, i) => [x(i), y(r.actual)]);
  const fitPts = hist.map((r, i) => [x(i), y(r.predict)]);
  const fcPts = [[x(last), y(rows[last].actual)], ...rows.slice(firstF).map((r, i) => [x(firstF + i), y(r.predict)])];
  const upPts = [[x(last), y(rows[last].actual)], ...rows.slice(firstF).map((r, i) => [x(firstF + i), y(r.upper)])];
  const loPts = [[x(last), y(rows[last].actual)], ...rows.slice(firstF).map((r, i) => [x(firstF + i), y(r.lower)])];
  const band = path(upPts) + " " + loPts.slice().reverse().map(p => "L" + p[0].toFixed(1) + " " + p[1].toFixed(1)).join(" ") + " Z";
  const area = path(actualPts) + ` L${x(last).toFixed(1)} ${H - B} L${L} ${H - B} Z`;
  let ticks = "";
  for (let v = lo; v <= hi + 1e-9; v += 0.5) ticks += `<line class="grid" x1="${L}" x2="${W - R}" y1="${y(v / 100)}" y2="${y(v / 100)}"/><text class="ax" x="${L - 10}" y="${y(v / 100) + 4}" text-anchor="end">${v.toFixed(1)}%</text>`;
  let xl = "";
  rows.forEach((r, i) => { if (r.kind === "forecast" || r.period.endsWith("-01") || r.period.endsWith("-07")) xl += `<text class="ax" x="${x(i)}" y="${H - B + 22}" text-anchor="middle">${mon(r.period)}</text>`; });
  const fl = rows[n - 1];
  const tag = (v, cls, label) => `<g class="${cls}"><rect x="${W - R + 8}" y="${y(v) - 11}" width="84" height="22" rx="3"/><text x="${W - R + 16}" y="${y(v) + 4}">${label} ${pc(v).toFixed(2)}%</text></g>`;
  host.innerHTML = `<div class="ets-wrap"><svg viewBox="0 0 ${W} ${H}" role="img" aria-label="Delinquency rate: actual, ETS fit, and 3 month forecast with 95 percent limits">
    <defs>
      <linearGradient id="gA" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#1f6fd1" stop-opacity=".22"/><stop offset="1" stop-color="#1f6fd1" stop-opacity="0"/></linearGradient>
      <linearGradient id="gB" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#c3002f" stop-opacity=".10"/><stop offset="1" stop-color="#c3002f" stop-opacity=".28"/></linearGradient>
      <filter id="glow" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="3" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter>
    </defs>
    ${ticks}
    <rect class="zone" x="${x(last)}" y="${T}" width="${W - R - x(last)}" height="${H - T - B}"/>
    <text class="zlab" x="${(x(last) + W - R) / 2}" y="${T + 16}" text-anchor="middle">FORECAST, NEXT 3 MONTHS</text>
    <path class="area" d="${area}"/>
    <path class="band" d="${band}"/>
    <path class="lim" d="${path(upPts)}"/><path class="lim" d="${path(loPts)}"/>
    <path class="fit" d="${path(fitPts)}" pathLength="1"/>
    <path class="act" d="${path(actualPts)}" pathLength="1" filter="url(#glow)"/>
    <path class="fc" d="${path(fcPts)}" pathLength="1"/>
    ${fcPts.slice(1).map((p, i) => `<circle class="fcdot" cx="${p[0]}" cy="${p[1]}" r="6"/>${i < fcPts.length - 2 ? `<text class="fcval" x="${p[0]}" y="${p[1] - 14}" text-anchor="middle">${pc(rows[firstF + i].predict).toFixed(2)}%</text>` : ""}`).join("")}
    <circle class="nowdot" cx="${x(last)}" cy="${y(rows[last].actual)}" r="5"/>
    ${tag(fl.upper, "tagU", "UCL")}${tag(fl.predict, "tagF", "Fcst")}${tag(fl.lower, "tagL", "LCL")}
    ${xl}
    <line class="cross" id="cx" y1="${T}" y2="${H - B}" x1="0" x2="0" style="display:none"/>
    <circle class="hov" id="hd" r="5" style="display:none"/>
    <rect id="hit" x="${L}" y="${T}" width="${W - L - R}" height="${H - T - B}" fill="transparent"/>
  </svg><div class="ets-tip" id="tip" style="display:none"></div></div>`;
  const svg = host.querySelector("svg"), tip = host.querySelector("#tip"), cx = host.querySelector("#cx"), hd = host.querySelector("#hd");
  host.querySelector("#hit").addEventListener("mousemove", e => {
    const b = svg.getBoundingClientRect(), px = (e.clientX - b.left) / b.width * W;
    let i = 0; rows.forEach((_, k) => { if (Math.abs(x(k) - px) < Math.abs(x(i) - px)) i = k; });
    const r = rows[i], f = r.kind === "forecast";
    cx.style.display = hd.style.display = tip.style.display = "block";
    cx.setAttribute("x1", x(i)); cx.setAttribute("x2", x(i));
    hd.setAttribute("cx", x(i)); hd.setAttribute("cy", y(f ? r.predict : r.actual));
    tip.innerHTML = `<b>${mon(r.period)}</b>` + (f
      ? `<div>Forecast <b>${pc(r.predict).toFixed(2)}%</b></div><div class="u">UCL 95% ${pc(r.upper).toFixed(2)}%</div><div class="u">LCL 95% ${pc(r.lower).toFixed(2)}%</div>`
      : `<div>Actual <b>${pc(r.actual).toFixed(2)}%</b></div><div class="u">ETS fit ${pc(r.predict).toFixed(2)}%</div>`);
    const tx = x(i) / W * b.width, flip = tx > b.width * .72;
    tip.style.left = (flip ? tx - tip.offsetWidth - 14 : tx + 14) + "px"; tip.style.top = Math.max(8, y(f ? r.predict : r.actual) / H * b.height - 40) + "px";
  });
  host.querySelector("#hit").addEventListener("mouseleave", () => { cx.style.display = hd.style.display = tip.style.display = "none"; });
};
