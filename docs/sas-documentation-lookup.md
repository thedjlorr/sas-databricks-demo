# Referencing SAS documentation for the right version

Starter information. SAS Viya is released on a monthly cadence and the
Help Center keeps every edition; quoting the wrong edition (as happened on
2026-08-26, when a 2023 guide was used for a 2026.03 tenant) is easy to
do and hard to notice. This is the method that works and the tool that
does it.

## 1. Know the tenant's release first

```sas
%put &sysvlong;          /* e.g. V.04.00M0P030926 */
%put &sysviyaversion;    /* e.g. Long-Term Support 2026.03 */
```
or `builtins.about` in CAS (`Viya Version`). Record it in CLAUDE.md's
Environment table. **Stable** = LTS (e.g. 2026.03), **Fast** = monthly
(e.g. 2026.07). The doc edition must contain that release.

## 2. How the Help Center is organised

Every document is `collection / docset / version`:

```
https://documentation.sas.com/api/collections/<collection>/v_<NNN>/docsets/<docset>/content/<docset>.pdf?locale=en
```

- **collection** — the product family, e.g. `vfcdc` (Visual Forecasting),
  `capcdc` (Viya Platform Analytics umbrella that re-hosts the same pages).
- **docset** — the book, e.g. `vfug` (User's Guide), `vfov` (Overview).
- **version** — `v_NNN`, an opaque counter per collection. It is **not**
  the release number; the only reliable mapping is the cover page of the
  PDF ("2025.10 - 2026.03*"). Numbers are reused across collections, so
  `v_029` in `vfcdc` says nothing about `v_029` elsewhere.

Known mappings (verified 2026-08-27, `vfcdc/vfug`):

| version | edition |
|---|---|
| v_017, v_018 | 2023.04 – 2023.10 |
| v_019 | 2023.11 – 2024.01 |
| v_028, v_029 | 2025.10 – 2026.03 ← matches LTS 2026.03 |
| v_030 | 2026.04 – 2026.08 |

## 3. What works and what doesn't (for a non-browser client)

| Route | Result |
|---|---|
| Help Center HTML (`documentation.sas.com/doc/en/<collection>/<version>/<docset>/<page>.htm`) | 404 / 500 — the site is a browser app |
| PDF API with default `requests` UA | **403** |
| PDF API with a browser `User-Agent` | **200**, full PDF (3–6 MB for a user's guide) |
| Web search restricted to `documentation.sas.com` / `support.sas.com` | good for finding collection/docset ids and page titles |
| `pypdf` text extraction | fine; printed page N ≈ PDF index N+4 (front matter) |

## 4. The tool — `starter/sasdoc.py`

```powershell
python starter\sasdoc.py match    vfcdc vfug 2026.03            # which v_NNN contains the tenant release
python starter\sasdoc.py versions vfcdc vfug --from 25 --to 35  # map versions -> cover editions
python starter\sasdoc.py grep     vfcdc vfug v_029 "Panel Series Neural Network"
python starter\sasdoc.py section  vfcdc vfug v_029 "Panel Series Neural Network Settings" --pages 10 --last --out docs\reference-x.txt
```
PDFs and extracted text are cached in `docs/.sasdoc-cache/` (gitignored).
`--last` picks the heading's last occurrence (the reference chapter)
rather than the first (the TOC).

## 5. Keep what you used

Save the extract you relied on as `docs/reference-<topic>-<edition>.txt`
with the edition in the file name and the source URL on the first line,
and push it to the project's SAS Content `docs/` folder. Cite the edition
when quoting a setting or default; if the tenant is upgraded, re-check
against the new edition rather than trusting the saved extract.

## 6. Other sources, and when to use them

- **developer.sas.com** REST API references — for `analyticsGateway`,
  `forecastingGateway`, `files`, `folders` etc. Note: the Viya services
  themselves serve no `apiMeta`; the verified request shapes live in
  CLAUDE.md, learned by probing (see `docs/lessons-learned.md` §E).
- **communities.sas.com** articles — useful for intent and examples, but
  they drift (a 2020 article said "up to 3 hidden layers"; the 2026.03
  guide says 0–2). Treat as secondary; confirm against the guide.
- **SAS Global Forum / SGF papers** on support.sas.com — background on
  methods (e.g. the 2020 paper on neural-network forecasting strategies).

## 7. Adding a new docset

Find the ids via a site-restricted web search for the book title, then
`sasdoc.py versions <collection> <docset>` to confirm it resolves, and add
the pair to `KNOWN` in the script with the book title.
