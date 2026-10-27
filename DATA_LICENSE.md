# Data license and redistribution boundaries

The **source code** of CET4Coach is MIT-licensed (see LICENSE).

The following files include material derived from third-party sources and are
**not** relicensed by the MIT license:

- `data/questions.json`
- `data/materials.json`
- `data/word_sentences.json` (the `真题` rows)
- `data/words.json` (definitions/CEFR labels derived from public word lists)
- `data/import_report.json`, `data/gap_report.json` (statistics about the above)
- `library/audio/` and any audio you add
- `THIRD_PARTY_NOTICES.md` references

Primary sources:

- o-Sakurajimamai-o/cet-practice — <https://github.com/o-Sakurajimamai-o/cet-practice>
- 懒笔记 CET4 high-frequency word list — <https://english-exam.lazynote.cn/cet4/words/stats/frequency/>
- KyleBing/english-vocabulary — <https://github.com/KyleBing/english-vocabulary>
- MyMemory machine translation (for some sentence translations) — <https://mymemory.translated.net/>

CET-4 past papers are copyrighted by the relevant examination authority.
This project is for **personal study and research**. It does not claim ownership
of the papers, dictionaries, translations, or audio. Do not use these data files
for commercial redistribution; obtain permission from the rights holders first.

If you fork this project, you are responsible for deciding which data files to
publish in your fork. A code-only fork can remove `data/questions.json`,
`data/materials.json`, and the `真题` rows of `data/word_sentences.json`, then
use the app's importer with your own licensed copies.
