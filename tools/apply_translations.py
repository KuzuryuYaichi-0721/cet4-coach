import hashlib
import json
import pathlib

data = pathlib.Path("CET4Coach/data/word_sentences.json")
cache_path = pathlib.Path("CET4Coach/temp/translation_cache.json")
rows = json.loads(data.read_text(encoding="utf-8"))
cache = json.loads(cache_path.read_text(encoding="utf-8")) if cache_path.exists() else {}
translated = 0
for row in rows:
    key = hashlib.sha1(row["en"].encode("utf-8")).hexdigest()
    item = cache.get(key)
    if row.get("sentence_type") == "真题" and item and item.get("zh"):
        row["zh"] = item["zh"]
        row["zh_source"] = "MyMemory-machine-translation"
        translated += 1
data.write_text(json.dumps(rows, ensure_ascii=False, indent=1), encoding="utf-8")
print("applied translations", translated, "of", sum(1 for r in rows if r.get("sentence_type") == "真题"))
