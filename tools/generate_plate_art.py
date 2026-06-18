#!/usr/bin/env python3
"""Pre-generate bundled plate art for every seed recipe.

The app (PlateRenderLibrary) loads `Resources/PlateArt/<slug>.png` for seed dishes
and only paints *new* user dishes at runtime. The seed set shipped with art for only
a handful of dishes, so this generates the rest via the same gpt-image-1 gouache
prompt, downscales to 640px (the app's cachedPixelSize), and writes them into
Resources/PlateArt/. Idempotent: existing <slug>.png files are skipped, so it resumes.

Usage: python3 tools/generate_plate_art.py [--limit N] [--workers 6]
Key is read from Config/LocalSecrets.xcconfig (OPENAI_API_KEY = ...).
"""
import json, re, os, sys, time, base64, unicodedata, subprocess, urllib.request, urllib.error
from concurrent.futures import ThreadPoolExecutor, as_completed

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ART = os.path.join(ROOT, "PantryChef/Resources/PlateArt")
SEED = os.path.join(ROOT, "PantryChef/Resources/seed_recipes.json")
MODEL, QUALITY, SIZE, MAXSIDE = "gpt-image-1", "medium", "1024x1024", 640

def read_key():
    for f in ("Config/LocalSecrets.xcconfig", "Config/Secrets.xcconfig"):
        p = os.path.join(ROOT, f)
        if not os.path.exists(p): continue
        for line in open(p):
            if line.strip().startswith("OPENAI_API_KEY"):
                return line.split("=", 1)[1].strip()
    raise SystemExit("OPENAI_API_KEY not found in Config/*.xcconfig")

def slug(name):
    n = unicodedata.normalize("NFKD", name.lower())
    n = "".join(c for c in n if not unicodedata.combining(c))
    return "-".join(t for t in re.split(r"[^a-z0-9]+", n) if t)

def prompt(name):
    return (f"A single round white ceramic plate of {name}, hand-painted gouache "
            "cookbook illustration. Make it appetising: a generous, abundant portion "
            "that fills the plate, fresh natural colours with soft raking light, gentle "
            "glossy highlights on sauces and oils, and a little fresh garnish. Fine "
            "deep-green ink outlines and a thin green double ring on the plate rim. "
            "Viewed from directly above, perfectly centred, isolated on a fully "
            "transparent background — nothing outside the circular plate, no text.")

def paint(name, key):
    body = json.dumps({"model": MODEL, "prompt": prompt(name), "size": SIZE,
                       "quality": QUALITY, "background": "transparent",
                       "output_format": "png"}).encode()
    req = urllib.request.Request("https://api.openai.com/v1/images/generations", data=body,
        headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"})
    last = None
    for attempt in range(5):
        try:
            with urllib.request.urlopen(req, timeout=180) as r:
                d = json.load(r)
            return base64.b64decode(d["data"][0]["b64_json"])
        except urllib.error.HTTPError as e:
            last = f"HTTP {e.code}: {e.read()[:160].decode('utf-8','replace')}"
            if e.code in (429, 500, 502, 503): time.sleep(2 ** attempt * 3); continue
            break
        except Exception as e:
            last = str(e); time.sleep(2 ** attempt * 3)
    raise RuntimeError(last)

def gen_one(name, key):
    s = slug(name)
    out = os.path.join(ART, f"{s}.png")
    if os.path.exists(out): return (s, "skip")
    png = paint(name, key)
    open(out, "wb").write(png)
    subprocess.run(["sips", "-Z", str(MAXSIDE), out], check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    normalize_transparency(out)
    return (s, "ok")

def normalize_transparency(path):
    """gpt-image-1 occasionally paints an opaque background square despite
    background=transparent; flood-fill it away from the corners so every plate sits
    transparently on the page. (PlateArtCoverageTests guards this too.)"""
    from PIL import Image, ImageDraw
    im = Image.open(path).convert("RGBA")
    w, h = im.size
    corners = [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)]
    if all(im.getpixel(c)[3] <= 40 for c in corners):
        return
    for c in corners:
        ImageDraw.floodfill(im, c, (0, 0, 0, 0), thresh=80)
    im.save(path)

def main():
    limit = workers = None
    args = sys.argv[1:]
    if "--limit" in args: limit = int(args[args.index("--limit") + 1])
    workers = int(args[args.index("--workers") + 1]) if "--workers" in args else 6
    key = read_key()
    os.makedirs(ART, exist_ok=True)
    recipes = json.load(open(SEED))
    recipes = recipes["recipes"] if isinstance(recipes, dict) else recipes
    names = [r["name"] for r in recipes]
    todo = [n for n in names if not os.path.exists(os.path.join(ART, f"{slug(n)}.png"))]
    if limit: todo = todo[:limit]
    print(f"key: {key[:8]}…  total recipes: {len(names)}  to generate: {len(todo)}  workers: {workers}", flush=True)
    ok = fail = 0
    with ThreadPoolExecutor(max_workers=workers) as ex:
        futs = {ex.submit(gen_one, n, key): n for n in todo}
        for i, f in enumerate(as_completed(futs), 1):
            n = futs[f]
            try:
                s, st = f.result(); ok += 1
                print(f"[{i}/{len(todo)}] {st:4} {s}", flush=True)
            except Exception as e:
                fail += 1
                print(f"[{i}/{len(todo)}] FAIL {slug(n)}: {e}", flush=True)
    print(f"\nDONE: ok={ok} fail={fail}  art files now: {len([f for f in os.listdir(ART) if f.endswith('.png')])}", flush=True)

if __name__ == "__main__":
    main()
