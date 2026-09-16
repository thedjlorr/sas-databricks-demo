"""sasdoc.py — find, fetch and extract SAS Help Center documentation for the
release that matches a Viya tenant.

SAS Help Center publishes every doc as  collection / docset / version:
  https://documentation.sas.com/api/collections/<collection>/v_<NNN>/docsets/<docset>/content/<docset>.pdf?locale=en
Version numbers are opaque (v_017 = 2023.04-2023.10, v_029 = 2025.10-2026.03 for
vfcdc/vfug); the only reliable way to map them is to open each PDF's cover.
The HTML pages need a browser; the PDF API needs a browser User-Agent (403
without). This tool does the probing, caches PDFs, and extracts text.

Usage:
  python starter\\sasdoc.py versions vfcdc vfug                 # map v_NNN -> edition (cover dates)
  python starter\\sasdoc.py versions vfcdc vfug --from 25 --to 35
  python starter\\sasdoc.py fetch vfcdc vfug v_029                # download + extract text to cache
  python starter\\sasdoc.py grep vfcdc vfug v_029 "Panel Series Neural Network" --context 600
  python starter\\sasdoc.py section vfcdc vfug v_029 "Panel Series Neural Network Settings" --pages 10 --out docs\\ref.txt
  python starter\\sasdoc.py match vfcdc vfug 2026.03               # pick the version whose cover range contains a release

Known collection/docset ids (verified 2026-08-27):
  vfcdc/vfug    SAS Visual Forecasting: User's Guide
  vfcdc/vfov    SAS Visual Forecasting: Overview
Add more to KNOWN as they are verified.
"""
import argparse, io, os, re, sys, pathlib
import requests

UA = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36",
      "Accept": "application/pdf,*/*"}
API = "https://documentation.sas.com/api/collections/{col}/{ver}/docsets/{ds}/content/{ds}.pdf?locale=en"
CACHE = pathlib.Path(os.environ.get("SASDOC_CACHE", pathlib.Path(__file__).resolve().parents[1] / "docs" / ".sasdoc-cache"))
KNOWN = {("vfcdc", "vfug"): "SAS Visual Forecasting: User's Guide",
         ("vfcdc", "vfov"): "SAS Visual Forecasting: Overview"}

def pdf_pages(data: bytes):
    import pypdf
    return [(p.extract_text() or "") for p in pypdf.PdfReader(io.BytesIO(data)).pages]

def cover_edition(first_page: str) -> str:
    # editions look like "2025.10 - 2026.03*" or "2021.2.6 - 2024.09" or "8.5"
    m = re.search(r"(20\d\d\.\d+(?:\.\d+)?\s*-\s*20\d\d\.\d+(?:\.\d+)?\*?|20\d\d\.\d+(?:\.\d+)?\*?|\b\d\.\d\b)", first_page)
    return m.group(1).replace("\n", " ") if m else " ".join(first_page.split())[:80]

def get(col, ds, ver) -> bytes | None:
    CACHE.mkdir(parents=True, exist_ok=True)
    f = CACHE / f"{col}_{ds}_{ver}.pdf"
    if f.exists():
        return f.read_bytes()
    r = requests.get(API.format(col=col, ds=ds, ver=ver), headers=UA, timeout=180)
    if r.status_code == 200 and r.content[:4] == b"%PDF":
        f.write_bytes(r.content); return r.content
    return None

def text_of(col, ds, ver) -> str:
    t = CACHE / f"{col}_{ds}_{ver}.txt"
    if t.exists():
        return t.read_text(encoding="utf-8")
    data = get(col, ds, ver)
    if data is None: sys.exit(f"{col}/{ds}/{ver}: not found")
    txt = "\n".join(pdf_pages(data)); t.write_text(txt, encoding="utf-8"); return txt

def cmd_versions(a):
    print(f"{a.collection}/{a.docset}  ({KNOWN.get((a.collection, a.docset), 'unknown docset')})")
    misses = 0
    for v in range(a.frm, a.to + 1):
        ver = f"v_{v:03d}"; data = get(a.collection, a.docset, ver)
        if data is None:
            print(f"  {ver}: -"); misses += 1
            if misses >= 4 and v > a.frm + 4: print("  (4 consecutive misses - stopping)"); break
            continue
        misses = 0
        print(f"  {ver}: {cover_edition(pdf_pages(data)[0]):24}  {len(data)//1024:5d} KB")

def cmd_fetch(a):
    txt = text_of(a.collection, a.docset, a.version)
    print(f"{a.collection}/{a.docset}/{a.version}: {len(txt)} chars, edition {cover_edition(txt[:3000])}; cached in {CACHE}")

def cmd_grep(a):
    txt = text_of(a.collection, a.docset, a.version)
    hits = [m.start() for m in re.finditer(re.escape(a.pattern), txt)]
    print(f"{len(hits)} hits for '{a.pattern}'")
    for h in hits[: a.max]:
        s = max(0, h - a.context // 3); e = min(len(txt), h + a.context)
        print(f"\n--- @{h} ---\n" + re.sub(r"[ \t]+", " ", txt[s:e]))

def cmd_section(a):
    """Print/save the pages starting where `title` appears as a heading in the
    reference part of the guide (after its own TOC entry)."""
    data = get(a.collection, a.docset, a.version); pages = pdf_pages(data)
    idx = [i for i, p in enumerate(pages) if ("\n" + a.title + "\n") in p or p.strip().startswith(a.title)]
    if not idx: sys.exit(f"heading '{a.title}' not found as a page heading")
    start = idx[-1] if a.last else idx[0]
    out = f"# {KNOWN.get((a.collection, a.docset), a.docset)} {cover_edition(pages[0])} — {a.title} (pdf pages {start+1}-{start+a.pages})\n\n"
    out += "\n".join(re.sub(r"[ \t]+", " ", pages[i]) for i in range(start, min(start + a.pages, len(pages))))
    if a.out:
        pathlib.Path(a.out).write_text(out, encoding="utf-8"); print("saved", a.out, len(out), "chars")
    else:
        print(out)

def cmd_match(a):
    """Find the version whose cover range contains the tenant release (e.g. 2026.03)."""
    want = tuple(int(x) for x in a.release.split("."))
    best = None
    for v in range(a.frm, a.to + 1):
        ver = f"v_{v:03d}"; data = get(a.collection, a.docset, ver)
        if data is None: continue
        ed = cover_edition(pdf_pages(data)[0]).rstrip("*")
        m = re.findall(r"(20\d\d)\.(\d+)", ed)
        if not m: continue
        lo = tuple(int(x) for x in m[0]); hi = tuple(int(x) for x in m[-1])
        print(f"  {ver}: {ed}")
        if lo <= want <= hi: best = (ver, ed)
    print("\nMATCH:", best if best else "none in range — extend --to, or the tenant is newer than the newest edition")

def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    def common(p):
        p.add_argument("collection"); p.add_argument("docset")
    p = sub.add_parser("versions"); common(p); p.add_argument("--from", dest="frm", type=int, default=15); p.add_argument("--to", type=int, default=40); p.set_defaults(fn=cmd_versions)
    p = sub.add_parser("fetch");    common(p); p.add_argument("version"); p.set_defaults(fn=cmd_fetch)
    p = sub.add_parser("grep");     common(p); p.add_argument("version"); p.add_argument("pattern"); p.add_argument("--context", type=int, default=400); p.add_argument("--max", type=int, default=8); p.set_defaults(fn=cmd_grep)
    p = sub.add_parser("section");  common(p); p.add_argument("version"); p.add_argument("title"); p.add_argument("--pages", type=int, default=6); p.add_argument("--last", action="store_true", help="use the last heading occurrence (reference chapter) instead of the first"); p.add_argument("--out"); p.set_defaults(fn=cmd_section)
    p = sub.add_parser("match");    common(p); p.add_argument("release", help="tenant release, e.g. 2026.03"); p.add_argument("--from", dest="frm", type=int, default=15); p.add_argument("--to", type=int, default=40); p.set_defaults(fn=cmd_match)
    a = ap.parse_args(); a.fn(a)

if __name__ == "__main__":
    main()
