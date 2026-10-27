# 数据来源与导入说明

## 1. 题库底本：o-Sakurajimamai-o/cet-practice

仓库：<https://github.com/o-Sakurajimamai-o/cet-practice>

实际检查结果：

- 仓库源代码里没有题目 JSON；`seed/` 只有 `import-report.json` 等。
- Windows 发布包 `CET-Practice-v1.1.0-Windows-x64.zip` 内含 `CET-Practice/_internal/seed/cet6.db`。这是一个 SQLite 合并库，里面有 `exam_type='cet4'` 的 46 套记录。
- 本系统只取 `exam_type='cet4'` 且年份 2020—2025 的行。

实际读取到的表与字段：

```text
papers(id, paper_key, exam_type, year, month, set_no, has_listening, audio_path, ...)
questions(id, uid, paper_id, paper_key, section, section_order, q_no, q_index,
          qtype, group_key, stem, options_json, answer, answer_source,
          analysis_json, analysis_text, source_file, ...)
section_materials(id, paper_id, section, group_key, directions, content_json,
                  translation_json, analysis_text, source_file, ...)
```

适配器（`scripts/import.ps1`）不假设字段名，直接读取这些实际列；同时支持把同样的字段导出成 JSON 后再导入。

题库中：

- `section = listening`：`q_no` 1—7 归为短篇新闻，8—15 长对话，16—25 听力篇章；
- `section = reading1/reading2`：归为仔细阅读（两篇共 10 题）；
- `section = matching`：长篇匹配；
- `section = cloze`：选词填空；
- `writing/translation` 不进入 20 题客观题池。

### 去重结果（2020—2025）

| 项目 | 数量 |
|---|---:|
| 原始客观题行 | 2,365 |
| 按题干+选项 SHA256 去重后 | **1,668** |
| 仔细阅读 | 370 |
| 听力篇章 | 250 |
| 重点小计 | **620** |
| 短篇新闻 | 175 |
| 长对话 | 201 |
| 长篇匹配 | 370 |
| 选词填空 | 302 |
| 去重移除 | 697 |

为什么去重这么多？同一场考试的“第 2/3 套”经常复用同一题干和选项，或者题库本身把同一 PDF 的题重复导入；按用户要求“题干+选项哈希去重”后，数字就是 1,668。

### 90 天题位缺口

90 天 × 20 题 = 1,800 个题位；90 天 × 12 道重点 = 1,080 个重点题位。2020—2025 只有 620 道唯一重点题，**无法用唯一新题填满**。

系统做法：

- 每轮仍强制 12+ 重点题、6+ 同一主攻、2—3 种题型；
- 7 天窗口内不重复；题位不足时，允许 7 天前出现的题重出；
- 缺口写进 `data/gap_report.json`，不伪造、不把同题改字母当新题；
- 如果用户补 2015—2019 或 2026 的**带答案结构化数据**，可从“题库导入”追加。补缺题会单独标注，不会假装是 2020—2025 新题。

## 2. 单词表

- 语料：上述 2020—2025 题库的全部英文文本（阅读文章、题干/选项、听力原文、匹配段落、选词填空词库），约 22.4 万 token、10,147 个不同词形。
- 处理：小写化、词形归并、去掉功能词/过于基础的词/纯名字；按语料出现次数排序，取有中文释义的 Top 1500。
- 500 个核心/认识词分组：前 750 为 `core`，后 750 为 `recognition`；每日计划各取约 13 个，以保持每天 50/50。
- 释义来源：
  - 大部分来自懒笔记四级真题高频词表（2015—2026 真题语料，公开网页）：<https://english-exam.lazynote.cn/cet4/words/stats/frequency/>
  - 缺释义或需要更多词性时，用 KyleBing/english-vocabulary 的 CET4 JSON 补充：<https://github.com/KyleBing/english-vocabulary>
- 这不是官方发布的“2020—2025 官方 Top 1500 名单”；官方不发布这种榜单。它是本系统基于所导入真题文本的可复核统计结果。

### 句子

- 真题原句优先从上述文章/听力原文/题干中抽取：要求 7—28 个词、含目标词、不是填空残缺句；每个词最多取一条。
- 1441/1500 个词找到了真题原句；59 个词没有合适原句，只能用趣味句。
- 趣味句为离线种子，格式是“单词卡/小挑战”，始终可读、含目标词；`tools\Generate-WordSentences.ps1` 可以用 DeepSeek 分批替换成更自然的趣味/谚语句，之后离线复用。
- 部分真题原句通过 MyMemory 免费接口补充了机器翻译；未翻译的显示“中文提示”，指出目标词在该句里的核心意思，不冒充逐句翻译。

## 3. 听力

用户自行整理下载。系统不内置真题音频，也不会自动从第三方下载版权音频。

目录：

```text
library/source_audio/     原始素材（mp3/wav/m4a）
library/audio/            整理后的 Section 文件 + index.json
%TEMP%/CET4Coach/listening_<日期>/   每日临时复制区
```

整理规则与测试见 `README.md`、`tests/Test-Listening.ps1`。

## 4. catteacher0515/cet4-download

仓库：<https://github.com/catteacher0515/cet4-download>

- 它主要提供 PDF、音频和网页预览；仓库内没有与 cet-practice 同构的“题干/选项/答案”JSON。
- 自动从 PDF 抽题需要 OCR/版式对齐，容易把答案错配。本系统不把未核对的 PDF 直接变成题目。
- 如用户人工整理出 JSON/SQLite，可从“题库导入”选择文件追加；接口与 cet-practice 字段兼容。缺口报告会记录来源和补充量。

## 5. 技巧库

`data/techniques.json` 的 `basis` 只使用：

- `官方大纲要求`
- `历年真题统计规律`
- `公开备考教材常见方法`
- `经验性技巧`

没有编造论文、具体统计数据或“某研究证明”。

## 6. 隐私

- 题库、记录、音频均在本机。
- 大模型只收到当前一道题的题干/选项/理由、或当前单词/句子、或本周错题摘要；不上传整个题库或音频。
- API Key 只从环境变量读；不写任何文件。
- `data/logs/llm.jsonl` 只记录元数据，不记录题干全文。
