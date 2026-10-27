"""Optional build-time helper: add Chinese translations to real question
sentences via the free MyMemory endpoint.  Runtime never calls this."""
import hashlib
import json
import pathlib
import time
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed

DATA = pathlib.Path("CET4Coach/data/word_sentences.json")
CACHE = pathlib.Path("CET4Coach/temp/translation_cache.json")
cache = json.loads(CACHE.read_text(encoding="utf-8")) if CACHE.exists() else {}
rows = json.loads(DATA.read_text(encoding="utf-8"))
real = [r for r in rows if r.get("sentence_type") == "真题"]
todo = [r for r in real if hashlib.sha1(r["en"].encode("utf-8")).hexdigest() not in cache]
print("real", len(real), "todo", len(todo), flush=True)


def translate(row):
    key = hashlib.sha1(row["en"].encode("utf-8")).hexdigest()
    q = urllib.parse.quote(row["en"][:450])
    url = "https://api.mymemory.translated.net/get?q=" + q + "&langpair=en|zh-CN"
    try:
        with urllib.request.urlopen(url, timeout=30) as resp:
            d = json.load(resp)
        text = d.get("responseData", {}).get("translatedText", "")
        status = d.get("responseStatus")
        if status == 200 and text and "MYMEMORY WARNING" not in text.upper():
            return key, {"zh": text.strip(), "status": 200}
        return key, {"zh": "", "status": status}
    except Exception as exc:
        return key, {"zh": "", "status": str(exc)}


done = 0
with ThreadPoolExecutor(max_workers=6) as pool:
    futures = {pool.submit(translate, row): row for row in todo}
    for fut in as_completed(futures):
        key, result = fut.result()
        cache[key] = result
        done += 1
        if done % 25 == 0:
            CACHE.write_text(json.dumps(cache, ensure_ascii=False), encoding="utf-8")
            print("done", done, "ok", sum(1 for v in cache.values() if v.get("status") == 200), flush=True)
        if result.get("status") not in (200, "200"):
            # Quota/network failure: keep going but avoid hammering.
            time.sleep(0.3)
    CACHE.write_text(json.dumps(cache, ensure_ascii=False), encoding="utf-8")

translated = 0
for row in rows:
    key = hashlib.sha1(row["en"].encode("utf-8")).hexdigest()
    if row.get("sentence_type") == "真题" and key in cache and cache[key].get("zh"):
        row["zh"] = cache[key]["zh"]
        row["zh_source"] = "MyMemory-machine-translation"
        translated += 1
DATA.write_text(json.dumps(rows, ensure_ascii=False, indent=1), encoding="utf-8")
print("translated", translated, "of", len(real), flush=True)
