"""Build the Viya + Databricks demo video: screenshots -> narrated scenes -> MP4.

Run: python build_video.py [--shots] [--voice "Microsoft Zira Desktop"]
  --shots   retake the web-app screenshots with headless Chrome first
"""
import json, subprocess, sys, wave, shutil, tempfile
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import imageio_ffmpeg

HERE = Path(__file__).resolve().parent
REPO = Path(r"C:\SAS\sas-databricks-demo")
OUT = REPO / "docs" / "video"
CHROME = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"  # headless Chrome was unreliable here
FFMPEG = imageio_ffmpeg.get_ffmpeg_exe()
W, H = 1920, 1080
SCALE = W / 1440            # screenshots are taken at 1440 CSS px wide
VOICE = sys.argv[sys.argv.index("--voice") + 1] if "--voice" in sys.argv else "Microsoft Zira Desktop"

PAGES = {"landing": "landing-page.html", "studio": "webapp/index.html", "workflow": "webapp/workflow.html"}
SCENES = json.loads((HERE / "scenes.json").read_text(encoding="utf-8"))


def shots():
    for key, rel in PAGES.items():
        url = (REPO / rel).as_uri()
        out = HERE / f"page_{key}.png"
        out.unlink(missing_ok=True)
        for _ in range(3):  # headless Chrome occasionally exits without writing the file
            subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars",
                            f"--user-data-dir={tempfile.mkdtemp(dir=HERE, prefix='edge-')}",  # fresh profile: no hand-off or lock
                            f"--force-device-scale-factor={SCALE}", "--virtual-time-budget=8000",
                            "--window-size=1440,6000", f"--screenshot={out}", url],
                           check=True, capture_output=True)
            if out.exists():
                break
        else:
            raise RuntimeError(f"screenshot failed: {key}")


def font(size, bold=False):
    name = "segoeuib.ttf" if bold else "segoeui.ttf"
    return ImageFont.truetype(str(Path(r"C:\Windows\Fonts") / name), size)


def card(title, subtitle, path):
    im = Image.new("RGB", (W, H), "#0f2f3a")
    d = ImageDraw.Draw(im)
    d.rectangle([0, H - 14, W, H], fill="#e66a24")
    d.rectangle([140, 380, 152, 640], fill="#0878b7")
    d.text((190, 370), "SAS VIYA  +  DATABRICKS", font=font(30, True), fill="#7fc4e6")
    y = 430
    for line in title.split("\n"):
        d.text((190, y), line, font=font(76, True), fill="white")
        y += 96
    d.text((190, y + 20), subtitle, font=font(34), fill="#b9d3da")
    im.save(path)


def frame(scene, path):
    kind = scene["kind"]
    if kind == "card":
        card(scene["title"], scene["subtitle"], path)
        return
    if kind == "page":
        src = Image.open(HERE / f"page_{scene['page']}.png")
        top = int(scene["y"] * SCALE)
        im = src.crop((0, top, W, top + H))
    else:  # image file, letterboxed onto the canvas
        src = Image.open(REPO / scene["file"]).convert("RGB")
        src.thumbnail((W - 120, H - 160), Image.LANCZOS)
        im = Image.new("RGB", (W, H), "#eef4f5")
        im.paste(src, ((W - src.width) // 2, 110))
        d = ImageDraw.Draw(im)
        d.text((60, 36), scene.get("label", ""), font=font(36, True), fill="#18333b")
    im.save(path)


def speak(text, wav):
    ps = ("Add-Type -AssemblyName System.Speech;"
          "$s=New-Object System.Speech.Synthesis.SpeechSynthesizer;"
          f"$s.SelectVoice('{VOICE}');$s.Rate=0;"
          f"$s.SetOutputToWaveFile('{wav}');"
          "$s.Speak([Console]::In.ReadToEnd());$s.Dispose()")
    subprocess.run(["powershell", "-NoProfile", "-Command", ps], input=text, text=True, check=True)
    with wave.open(str(wav)) as w:
        return w.getnframes() / w.getframerate()


def main():
    if "--shots" in sys.argv:
        shots()
    work = HERE / "build"
    shutil.rmtree(work, ignore_errors=True)
    work.mkdir()
    clips = []
    for i, sc in enumerate(SCENES):
        png, wav, mp4 = work / f"s{i:02}.png", work / f"s{i:02}.wav", work / f"s{i:02}.mp4"
        frame(sc, png)
        dur = speak(sc["say"], wav) + 0.8
        fade_out = max(dur - 0.35, 0)
        subprocess.run([FFMPEG, "-y", "-loglevel", "error", "-loop", "1", "-i", str(png), "-i", str(wav),
                        "-vf", f"scale={W}:{H},format=yuv420p,fade=t=in:st=0:d=0.35,fade=t=out:st={fade_out:.2f}:d=0.35",
                        "-af", "apad", "-t", f"{dur:.2f}", "-r", "30",
                        "-c:v", "libx264", "-tune", "stillimage", "-preset", "medium", "-crf", "20",
                        "-c:a", "aac", "-b:a", "160k", "-ar", "44100", str(mp4)], check=True)
        clips.append(mp4)
        print(f"scene {i:02} {dur:5.1f}s  {sc['say'][:60]}")
    lst = work / "list.txt"
    lst.write_text("".join(f"file '{c.as_posix()}'\n" for c in clips))
    OUT.mkdir(parents=True, exist_ok=True)
    final = OUT / "viya_databricks_demo.mp4"
    subprocess.run([FFMPEG, "-y", "-loglevel", "error", "-f", "concat", "-safe", "0", "-i", str(lst),
                    "-c", "copy", "-movflags", "+faststart", str(final)], check=True)
    print("wrote", final)


if __name__ == "__main__":
    main()
