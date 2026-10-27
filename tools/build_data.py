"""Build-time data extractor for CET4Coach.

Reads the actual cet-practice SQLite seed database (release v1.1.0), exports
questions/materials into this project, and builds a 1500-word list ranked by
word frequency in the 2020-2025 CET-4 papers.  This script is a maintenance
tool only; the PowerShell app has no Python dependency.
"""
from __future__ import annotations

import hashlib
import json
import re
import sqlite3
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(r"CET4Coach")
TEMP = ROOT / "temp"
DATA = ROOT / "data"
DB = TEMP / "cet_practice.db"

WORD_RE = re.compile(r"[A-Za-z][A-Za-z'-]*")
SENT_RE = re.compile(r"(?<=[.!?])\s+(?=[A-Z\"'])")

STOP = set("""
a an the and or but if because so than then that this these those there here
i you he she it we they me him her us them my your his its our their
am is are was were be been being do does did done have has had having
will would shall should can could may might must ought
to of in on at by for from with without about into over under between among
as not no nor very too also just only even still yet already
what which who whom whose when where why how
all any both each few more most other some such own same
one two three four five six seven eight nine ten first second third
mr mrs ms dr etc vs per via
""".split())

# Function words / super-basic words that are not useful as standalone CET-4
# vocabulary cards.  This is deliberately conservative.
SKIP_EXTRA = set("""
able about above across after again against ago ahead almost alone along already
although always another answer around back bad became become before began begin
behind best better big black bring brought buy call called came can't cannot
care carry case change children city come could country day days different
doesn't done down during each early earth end enough evening ever every family
far fast father feel felt find first food found friend friends get gets getting
give given go goes going gone good got great group hand happy hard help her
high home house how however idea important keep kind know known large last late
later learn left less let life like line little live long look made make making
man many may mean men might mind money month more morning most mother move much
must name near need never new next night now number off often old once open order
other out over own part passage people perhaps place play point possible put question quite
rather read real really right room run said same say says school see seem seen
sense set several show side since small something sometimes soon sound start
state still stop such take talk tell than thing things think thought three time
today together told took toward town try turn two under until upon us use used
very want water way week well went were what when where which while white who
whole why will with without woman women word work world would write year years
yes yesterday yet young
working learning according lot kid kids parent parents american ask asks asked
""".split())

CEFR_LEVEL = {"A1": "基础", "A2": "基础", "B1": "进阶", "B2": "进阶", "C1": "挑战", "C2": "挑战"}


def split_sentences(text: str):
    text = re.sub(r"\s+", " ", text or "").strip()
    if not text:
        return []
    parts = SENT_RE.split(text)
    return [p.strip() for p in parts if 20 <= len(p) <= 380 and re.search(r"[A-Za-z]{3,}", p)]


def normalize_question_text(text: str) -> str:
    return re.sub(r"\s+", " ", (text or "").lower()).strip()


def qhash(stem: str, options) -> str:
    payload = normalize_question_text(stem) + "|" + "|".join(
        f"{o.get('key','')}:{normalize_question_text(o.get('text',''))}" for o in options
    )
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def parse_json(value, default=None):
    if not value:
        return default
    try:
        return json.loads(value)
    except Exception:
        return default


def extract_question_stem(row):
    if row["stem"]:
        return re.sub(r"\s+", " ", row["stem"]).strip()
    analysis = row["analysis_text"] or ""
    m = re.search(r"【题目】\s*(.+?)(?:\n|【)", analysis, re.S)
    if m:
        return re.sub(r"\s+", " ", m.group(1)).strip()
    return f"请听录音，回答第 {row['q_no']} 题。"


def main():
    DATA.mkdir(parents=True, exist_ok=True)
    db = sqlite3.connect(DB)
    db.row_factory = sqlite3.Row

    papers = [dict(r) for r in db.execute(
        "select * from papers where exam_type='cet4' and year between 2020 and 2025 "
        "order by year, month, set_no"
    )]
    paper_by_id = {p["id"]: p for p in papers}
    allowed = set(paper_by_id)

    # Section materials: passages and listening transcripts.
    materials = {}
    corpus_parts = []
    sentence_bank = defaultdict(list)
    for row in db.execute(
        "select m.*, p.paper_key from section_materials m join papers p on p.id=m.paper_id "
        "where p.exam_type='cet4' and p.year between 2020 and 2025"
    ):
        if row["paper_id"] not in allowed:
            continue
        content = parse_json(row["content_json"], {}) or {}
        paper = paper_by_id[row["paper_id"]]
        sec = row["section"]
        if sec == "listening":
            groups = content.get("groups") or []
            for g in groups:
                gkey = g.get("key") or f"g{g.get('from','')}"
                lines = g.get("lines") or []
                transcript = "\n".join(
                    (f"{x.get('speaker','')}: " if x.get("speaker") else "") + (x.get("en", "") or "")
                    for x in lines
                ).strip()
                mid = f"{paper['paper_key']}:listening:{gkey}"
                materials[mid] = {
                    "id": mid, "paper_key": paper["paper_key"], "section": "listening",
                    "group_key": gkey, "title": f"听力第 {g.get('from')}-{g.get('to')} 题",
                    "kind": "transcript", "text": "", "transcript": transcript,
                }
                for line in lines:
                    en = line.get("en", "") or ""
                    corpus_parts.append(en)
                    for s in split_sentences(en):
                        sentence_bank[paper["paper_key"]].append((s, mid, "listening"))
            continue

        if sec == "reading1" or sec == "reading2":
            text = content.get("passage", "") or ""
            mid = f"{paper['paper_key']}:{sec}:{row['group_key'] or 'passage'}"
            materials[mid] = {
                "id": mid, "paper_key": paper["paper_key"], "section": sec,
                "group_key": row["group_key"] or "passage", "kind": "passage",
                "title": "仔细阅读" + (" Passage 1" if sec == "reading1" else " Passage 2"),
                "text": text.strip(), "transcript": "",
            }
        elif sec == "matching":
            title = content.get("title", "") or ""
            paras = content.get("paragraphs") or []
            body = "\n\n".join(f"{p.get('label','')}) {p.get('text','')}" for p in paras)
            text = (title + "\n\n" + body).strip()
            mid = f"{paper['paper_key']}:matching:{row['group_key'] or 'passage'}"
            materials[mid] = {
                "id": mid, "paper_key": paper["paper_key"], "section": "matching",
                "group_key": row["group_key"] or "passage", "kind": "matching",
                "title": title or "长篇匹配", "text": text, "transcript": "",
            }
        elif sec == "cloze":
            text = content.get("passage", "") or ""
            bank = content.get("word_bank") or []
            mid = f"{paper['paper_key']}:cloze:{row['group_key'] or 'bank'}"
            materials[mid] = {
                "id": mid, "paper_key": paper["paper_key"], "section": "cloze",
                "group_key": row["group_key"] or "bank", "kind": "cloze",
                "title": "选词填空", "text": text.strip(), "transcript": "",
                "word_bank": bank,
            }
            corpus_parts.extend(w.get("text", "") for w in bank)
        else:
            continue
        corpus_parts.append(text)
        for s in split_sentences(text):
            sentence_bank[paper["paper_key"]].append((s, mid, sec))

    # Questions.
    def material_id_for(paper_key, section, group_key):
        exact = f"{paper_key}:{section}:{group_key}"
        if exact in materials:
            return exact
        prefix = f"{paper_key}:{section}:"
        for key in materials:
            if key.startswith(prefix):
                return key
        return exact

    raw_questions = [dict(r) for r in db.execute(
        "select q.* from questions q join papers p on p.id=q.paper_id "
        "where p.exam_type='cet4' and p.year between 2020 and 2025 "
        "and q.section in ('listening','cloze','matching','reading1','reading2') "
        "order by p.year,p.month,p.set_no,q.section_order,q.q_no"
    )]
    seen_hashes = {}
    questions = []
    for row in raw_questions:
        paper = paper_by_id[row["paper_id"]]
        options = parse_json(row["options_json"], []) or []
        sec = row["section"]
        if sec == "matching" and not options:
            mid = material_id_for(paper["paper_key"], "matching", row["group_key"] or "passage")
            mat = materials.get(mid) or {}
            text = mat.get("text", "")
            for p in re.findall(r"^([A-O])\)\s*(.*)$", text, re.M):
                snippet = re.sub(r"\s+", " ", p[1]).strip()
                options.append({"key": p[0], "text": snippet[:90]})
        if not options or not row["answer"]:
            continue
        stem = extract_question_stem(row)
        h = qhash(stem, options)
        if h in seen_hashes:
            continue
        if sec == "listening":
            if row["q_no"] <= 7:
                qtype, point, asec = "listening_news", 7.1, "A"
            elif row["q_no"] <= 15:
                qtype, point, asec = "listening_long", 7.1, "B"
            else:
                qtype, point, asec = "listening_passage", 14.2, "C"
            mid = material_id_for(paper["paper_key"], "listening", row["group_key"] or ("g" + str(row["q_no"])))
            corpus_parts.append(stem)
            corpus_parts.extend(o.get("text", "") for o in options)
        elif sec in ("reading1", "reading2"):
            qtype, point, asec = "careful_reading", 14.2, None
            mid = material_id_for(paper["paper_key"], sec, row["group_key"] or "passage")
        elif sec == "matching":
            qtype, point, asec = "matching", 7.1, None
            mid = material_id_for(paper["paper_key"], "matching", row["group_key"] or "passage")
        elif sec == "cloze":
            qtype, point, asec = "cloze", 3.55, None
            mid = material_id_for(paper["paper_key"], "cloze", row["group_key"] or "bank")
        else:
            continue
        if sec != "listening":
            corpus_parts.append(stem)
            corpus_parts.extend(o.get("text", "") for o in options)
        audio = None
        if sec == "listening":
            suite = f"{paper['year']}-{paper['month']:02d}-set{paper['set_no']}"
            audio = {
                "required": True,
                "suite": suite,
                "section": asec,
                "audio_id": f"{suite}-Section{asec}",
            }
        questions.append({
            "id": row["uid"],
            "paper_key": paper["paper_key"],
            "year": paper["year"],
            "month": paper["month"],
            "set_no": paper["set_no"],
            "section": sec,
            "type": qtype,
            "q_no": row["q_no"],
            "group_key": row["group_key"],
            "stem": stem,
            "options": options,
            "answer": str(row["answer"]).strip().upper(),
            "material_id": mid,
            "audio": audio,
            "point": point,
            "focus": qtype in ("careful_reading", "listening_passage"),
            "explanation": (row["analysis_text"] or "").strip(),
            "answer_source": row["answer_source"] or "",
            "source": "cet-practice v1.1.0 (o-Sakurajimamai-o/cet-practice) / seed/cet6.db / CET4 2020-2025",
            "source_file": row["source_file"] or "",
            "hash": h,
        })
        seen_hashes[h] = True

    questions.sort(key=lambda q: (q["year"], q["month"], q["set_no"], {"listening": 0, "cloze": 1, "matching": 2, "reading1": 3, "reading2": 4}.get(q["section"], 9), q["q_no"]))
    print("questions", len(questions), Counter(q["type"] for q in questions), "dupes", len(raw_questions) - len(questions))

    # Missing materials: make a placeholder so UI never crashes.
    for q in questions:
        if q["material_id"] not in materials:
            materials[q["material_id"]] = {
                "id": q["material_id"], "paper_key": q["paper_key"], "section": q["section"],
                "group_key": q["group_key"], "kind": "placeholder", "title": "材料缺失",
                "text": "（这道题的材料没有随题库导入，可先跳过。）", "transcript": "",
            }

    stats = {
        "generated_at": __import__("datetime").datetime.now().isoformat(timespec="seconds"),
        "source": "cet-practice v1.1.0 Windows release, genuine seed/cet6.db (CET4 rows only)",
        "years": "2020-2025",
        "papers": len({q["paper_key"] for q in questions}),
        "source_papers": len(papers),
        "total_questions": len(questions),
        "objective_questions": len(questions),
        "unique_hashes": len(seen_hashes),
        "by_type": dict(Counter(q["type"] for q in questions)),
        "by_year": {str(y): sum(1 for q in questions if q["year"] == y) for y in range(2020, 2026)},
        "focus_questions": sum(1 for q in questions if q["focus"]),
        "target_90_day_questions": 1800,
        "target_focus_1080": 1080,
        "focus_sufficient": sum(1 for q in questions if q["focus"]) >= 1080,
        "total_sufficient": len(questions) >= 1800,
        "supplement_needed": [] if (len(questions) >= 1800 and sum(1 for q in questions if q["focus"]) >= 1080) else ["note: source is below 90-day target; see gap report"],
        "gap_report": [
            {
                "kind": "focus_questions",
                "have_unique": sum(1 for q in questions if q["focus"]),
                "need_slots": 1080,
                "message": "2020-2025 年 CET4 的仔细阅读+听力篇章唯一题量为 620；90 天每天 12 道重点题需要 1080 个题位。系统按 7 天后可重出规则滚动，不伪造新题。",
                "supplement_sources": [
                    "catteacher0515/cet4-download（仅 PDF/音频，需要人工转 JSON 后才能导入）",
                    "o-Sakurajimamai-o/cet-practice 其他年份的 seed 数据（需明确标注为补缺题）"
                ]
            },
            {
                "kind": "total_questions",
                "have_unique": len(questions),
                "need_slots": 1800,
                "message": "唯一题量为 1668；90 天每天 20 题需要 1800 个题位。最后 7 天会按 7 天后可重出规则复用错题/旧题，仍保持 7 天内不重复。"
            }
        ],
        "duplicates_removed": len(raw_questions) - len(questions),
    }
    (DATA / "materials.json").write_text(json.dumps(list(materials.values()), ensure_ascii=False, indent=1), encoding="utf-8")
    (DATA / "questions.json").write_text(json.dumps(questions, ensure_ascii=False, indent=1), encoding="utf-8")
    (DATA / "import_report.json").write_text(json.dumps(stats, ensure_ascii=False, indent=1), encoding="utf-8")

    # Frequency corpus (full text + questions; no Chinese explanation).
    corpus = "\n".join(corpus_parts)
    tokens = [m.group(0).lower().strip("'-") for m in WORD_RE.finditer(corpus)]
    tokens = [t for t in tokens if len(t) >= 3 and t.isalpha()]
    print("corpus tokens", len(tokens), "unique", len(set(tokens)))

    lanz = {r["word"].lower(): r for r in json.loads((TEMP / "lanznote_parsed.json").read_text(encoding="utf-8"))}
    kb = json.loads((TEMP / "kb_map.json").read_text(encoding="utf-8"))

    # Vocabulary set and inflection mapping.
    vocab = set(kb) | set(lanz)
    forms = {}
    for base in vocab:
        if len(base) < 3 or not base.isalpha():
            continue
        cand = {base + "s", base + "es", base + "ed", base + "ing", base + "d", base + "er", base + "est"}
        if base.endswith("y"):
            cand |= {base[:-1] + "ies", base[:-1] + "ied", base[:-1] + "ier", base[:-1] + "iest"}
        if base.endswith("e"):
            cand |= {base[:-1] + "ing", base + "r", base + "st"}
        if len(base) >= 4 and base[-1] not in "aeiou":
            cand |= {base + base[-1] + "ed", base + base[-1] + "ing", base + base[-1] + "er"}
        for f in cand:
            if f not in vocab:
                forms.setdefault(f, base)

    def lemma(t):
        if t in vocab:
            return t
        if t in forms:
            return forms[t]
        for suf, cut in (("ies", "y"), ("ied", "y"), ("ing", ""), ("ed", ""), ("es", ""), ("s", ""), ("ly", "")):
            if t.endswith(suf) and len(t) > len(suf) + 2:
                stem = t[:-len(suf)] + cut
                if stem in vocab:
                    return stem
                if suf == "ing" and stem + "e" in vocab:
                    return stem + "e"
        return t

    counts = Counter(lemma(t) for t in tokens)
    # Lower-case-only presence helps filter names.
    lowercase = Counter(t for t in tokens if t.islower() or True)  # tokens already lower
    candidates = []
    for w, n in counts.items():
        if w in STOP or w in SKIP_EXTRA or len(w) < 3 or not w.isalpha():
            continue
        info = lanz.get(w)
        kb_info = kb.get(w)
        if not info and not kb_info:
            continue
        if not info and n < 2:
            continue
        candidates.append((w, n, info, kb_info))
    candidates.sort(key=lambda x: (-x[1], lanz.get(x[0], {}).get("rank", 99999), x[0]))
    print("candidates", len(candidates), "top", [(w, n) for w, n, _, _ in candidates[:30]])

    chosen = candidates[:1500]
    if len(chosen) < 1500:
        # Fill from the curated lanznote ranking, even if a word did not occur
        # in the extracted text.
        have = {w for w, _, _, _ in chosen}
        for r in sorted(lanz.values(), key=lambda x: x["rank"]):
            w = r["word"].lower()
            if w in have or w in STOP or w in SKIP_EXTRA or len(w) < 3:
                continue
            if w not in kb and not r.get("definition"):
                continue
            chosen.append((w, 0, r, kb.get(w)))
            have.add(w)
            if len(chosen) >= 1500:
                break

    words = []
    for rank, (w, n, info, kb_info) in enumerate(chosen, 1):
        definition = (info or {}).get("definition") or (kb_info or {}).get("translation") or ""
        definition = re.sub(r"\s+", " ", definition).strip()
        cefr = (info or {}).get("cefr") or ""
        if cefr not in CEFR_LEVEL:
            cefr = "B1" if rank <= 1000 else "B2"
        pos = ""
        m = re.match(r"([a-z]+)\.", definition)
        if m:
            pos = m.group(1)
        elif kb_info:
            pos = (kb_info.get("pos") or "").strip()
        # Keep the first one or two senses readable.
        short = definition.split(" | ")[0]
        short = re.sub(r"^[a-z]+\.\s*", "", short, flags=re.I)
        short = short.split("；")[0].split(";")[0].strip()
        words.append({
            "rank": rank,
            "word": w,
            "frequency": n,
            "cefr": cefr,
            "pos": pos or "n.",
            "meaning": definition,
            "short_meaning": short[:70],
            "difficulty": CEFR_LEVEL[cefr],
            "group": "core" if rank <= 750 else "recognition",
            "source": "lanznote CET4 high-frequency list" if info else "KyleBing english-vocabulary (CET4)",
            "corpus_years": "2020-2025",
        })
    (DATA / "words.json").write_text(json.dumps(words, ensure_ascii=False, indent=1), encoding="utf-8")
    print("words", len(words), "core", sum(1 for w in words if w["group"] == "core"), "freq range", words[0]["frequency"], words[-1]["frequency"])

    # Real sentence lookup: build one best sentence per word.
    sent_index = defaultdict(list)
    for paper_key, pairs in sentence_bank.items():
        for sent, mid, sec in pairs:
            low = sent.lower()
            for w in set(lemma(t) for t in [m.group(0).lower().strip("'-") for m in WORD_RE.finditer(sent)] if len(t) >= 3):
                if w in {x["word"] for x in words}:
                    sent_index[w].append((sent, mid, sec))
    wordset = {x["word"] for x in words}
    output = []
    real_count = 0
    for idx, w in enumerate(words):
        candidates = sent_index.get(w["word"], [])
        # filter and score
        clean = []
        seen_sent = set()
        for sent, mid, sec in candidates:
            if "__" in sent or "\ufffd" in sent or "Directions:" in sent:
                continue
            low = sent.lower()
            if w["word"] not in re.findall(r"[a-z]+", low):
                continue
            words_n = len(re.findall(r"[A-Za-z]+", sent))
            if words_n < 7 or words_n > 28:
                continue
            if sent in seen_sent:
                continue
            seen_sent.add(sent)
            score = abs(words_n - 14)
            clean.append((score, sent, mid, sec))
        clean.sort(key=lambda x: x[0])
        real = clean[0] if clean else None
        if real:
            real_count += 1
            output.append({
                "word": w["word"],
                "en": real[1],
                "zh": f"真题例句。句中 {w['word']} 的核心意思是：{w['short_meaning']}。",
                "target_meaning": w["short_meaning"],
                "sentence_type": "真题",
                "source": real[3],
                "material_id": real[2],
            })
        # Fun/word-card sentence. Kept simple and always grammatical, so it
        # remains usable offline; the optional DeepSeek pre-generation command
        # replaces these with richer sentences.
        variants = [
            (f'Today\'s word card is "{w["word"]}". Say it once, then use it in your own sentence.',
             f'今天的单词卡是“{w["word"]}”。先读一遍，再用它造一个自己的句子。'),
            (f'Quick question: what does "{w["word"]}" mean? Think of the Chinese meaning before you answer.',
             f'快问快答：“{w["word"]}”是什么意思？回答前先想一想它的中文意思。'),
            (f'Here is a small challenge: explain "{w["word"]}" to a friend in one short sentence.',
             f'小挑战：用一句简短的话向朋友解释“{w["word"]}”。'),
        ]
        en, zh = variants[idx % len(variants)]
        output.append({
            "word": w["word"],
            "en": en,
            "zh": zh,
            "target_meaning": w["short_meaning"],
            "sentence_type": "趣味",
            "source": "offline-seed",
            "material_id": None,
        })
    (DATA / "word_sentences.json").write_text(json.dumps(output, ensure_ascii=False, indent=1), encoding="utf-8")
    print("sentences", len(output), "real coverage", real_count, "/", len(words))
    print("real sentence per word missing", len(words) - real_count)


if __name__ == "__main__":
    main()
