# 四级教练 · 大肥鱼版

[![Windows](https://img.shields.io/badge/Windows-10%20%2F%2011-0078D4?logo=windows)](https://github.com/KuzuryuYaichi-0721/cet4-coach)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%20%7C%207-5391FE?logo=powershell)](https://github.com/KuzuryuYaichi-0721/cet4-coach)
[![License: MIT](https://img.shields.io/badge/code%20license-MIT-green.svg)](LICENSE)

面向英语基础较弱学习者的 **Windows 纯本地** 四级备考系统。题库、学习记录、音频整理都在本机；大模型只接入 DeepSeek，用于回答评估、错题讲解、周复盘和一次性趣味句预生成。

**形象说明：** [大肥鱼设定](docs/MASCOT.md) · [形象授权](MASCOT_LICENSE.md)。

**本版内容：** 你提供的大肥鱼 Q 版/立绘图片、DS 蓝配色、可爱少女陪练语气、听力篇章（原音频/下载 MP3 本地播放）、题目页“我不会，逐词讲解”、全文翻译+逐词表、全屏阅读、每日自动保存与备份提醒、跨版本 `.cet4progress.json` 学习进度包（按题目内容指纹匹配，旧版没有的新题会保留为导入题）。

**第一次用，先看 [从开始学习](docs/START_LEARNING.md)。** 只想跑起来，见下面“快速开始”。

**详细使用手册：** [CET4Coach 详细使用手册 PDF](docs/CET4Coach-User-Manual.zh-CN.pdf)（含大肥鱼形象、听力/逐词讲解、全屏阅读、跨版本进度包）。

## 下载

- 懒人包：[CET4Coach v1.3.2](https://github.com/KuzuryuYaichi-0721/cet4-coach/releases/latest)（下载 zip，解压，双击 `RUN.bat`）
- 源码：`git clone https://github.com/KuzuryuYaichi-0721/cet4-coach.git`
- 桌面版：`C:\Users\erwei\Desktop\CET4Coach`

> 重要数据诚实说明：`o-Sakurajimamai-o/cet-practice` 的仓库里没有题库 JSON，题库实际在 Release 包的 `seed/cet6.db`（含 CET4 行）。本系统从 **v1.1.0 Windows 发布包** 中读取该 SQLite，按真实字段导入。2020—2025 年 CET4 去重后只有 **1,668 道唯一客观题**，其中仔细阅读+听力篇章 **620 道**；这与“90 天 × 20 题 = 1,800 个题位、重点 1,080 个题位”不一致。系统不伪造题目，使用 7 天后可重出的间隔复习规则补足题位，并把缺口写进 [gap_report.json](data/gap_report.json) 与 [import_report.json](data/import_report.json)。

## 快速开始

1. 安装 Windows 10/11 自带的 Windows PowerShell 5.1 或 PowerShell 7。
2. 需要整理/切分听力时，安装 [ffmpeg](https://ffmpeg.org/) 并确保 `ffmpeg -version` 能运行；只导入已分 Section 的文件也建议装 `ffprobe` 以读取时长。
3. 安装 PotPlayer（可选，仅播放听力需要），默认会自动查找常见安装路径，也可在 `config.json` 的 `listening.potPlayer` 填完整路径。
4. 设置 DeepSeek Key（只在环境变量里，**不要写进 config.json**）：

```powershell
setx DEEPSEEK_API_KEY "你的Key"
```

关掉当前 PowerShell/程序再重新打开，让新环境变量生效。

5. 双击 `RUN.bat`，或：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\main.ps1
# 或
pwsh -NoProfile -ExecutionPolicy Bypass -File .\main.ps1
```

首次进入必须先完成 **5—8 分钟入门微课 + 3 题小测**。小测全对才进主菜单；答错会回到对应页面再讲，不扣分。

## 每天怎么用

- **单词 30 分钟**：开始即倒计时，后台把今天刷题计划需要的听力复制到 `%TEMP%\CET4Coach\listening_<日期>\`。每个词先看真题句（或预生成趣味句）猜中文；核心词再做中译英和造句。30 分钟到点立即停止出新词，未完成词进入次日复习；结束自动删除临时听力并校验源目录未变动。
- **20 题 30 分钟**：至少 12 题来自仔细阅读/听力篇章，至少 6 题同一主攻题型，2—3 种题型混合；7 天内不重复，错题优先重出。先选答案，再用一句话说理由；DeepSeek 评估理由质量，错题按“考什么 → 为什么对 → 你的误区 → 逐项分析每个选项 → 下次动作”做深度讲解，并附技巧。
- **第二次做错题**：选项顺序自动打乱，避免背字母；页面会显示上次选了什么、上次错误类型。看完两次讲解后，可勾选“跳过重复讲解”，只保留要点。
- **本地学习档案**：每轮单词/刷题结束写入 `data/history/`，包括题目、你的答案、理由、讲解来源和错误类型；下一次选题会优先重出旧错题。
- **界面**：1400×900 默认大窗口；标题、正文、注释分层；页面切换和下一题自动回到顶部；内容超出窗口时滚动。
- **打卡**：单词 30 分钟算基础打卡；完成 20 题额外标记“刷”。连续 7/14/30 天给一句简短鼓励。月历用颜色显示。
- **周复盘**：周日自动生成一次 3—5 句“本周错题画像”，也可在打卡页手动生成；结果缓存到 `data/cache/`。
- 随时可“保存并退出”；单词和刷题都会从断点继续。退出时会清掉当天临时听力。

### 深度讲解配置

`config.json` 的 `llm.explanationModel` 默认 `deepseek-chat`，`llm.explanationMaxTokens` 默认 2400。深度讲解会要求模型逐项分析 A/B/C/D、推断你的误区、引用原文依据并给出自测追问；没有 API Key 时会明确显示“本地解析”，不会假装联网。若你的账号支持 `deepseek-reasoner` 且 JSON 输出稳定，可把 `explanationModel` 改为它；否则保持默认。

## 目录与文件职责

```text
CET4Coach/
  main.ps1                启动、加载模块、首次 API Key 检查、打开 WinForms 主窗口
  config.json             路径、模型、base URL、超时、预算、按钮/字体参数；不存 API Key
  RUN.bat                 优先 pwsh、退而使用 Windows PowerShell 5.1
  scripts/
    common.ps1            路径/JSON/日志/字体/卡片/进度窗/计时器/安全错误处理
    ui.ps1                主窗口、侧栏、首页、设置与诊断、题库导入页、听力整理页
    llm.ps1               Invoke-DeepSeekChat、重试、JSON 提取、缓存、预算、脱敏日志
    listening.ps1         文件名解析、ffmpeg 切分、索引、缺口报告、临时区、PotPlayer
    words.ps1             1500 词、每日 50/50 新词、30 分钟闭环、离线判断、造句、错词状态
    quiz_data.ps1         题库读取、选题约束、每日计划、会话存储、错题本
    quiz.ps1              20 题 UI、限时、PotPlayer 回放计数、评估、讲解、技巧嵌入
    import.ps1            cet-practice DB/JSON 适配器、真实字段映射、哈希去重、缺口报告
    checkin.ps1           打卡、连续天数、7/14/30 鼓励、月历、周错题画像
    course.ps1            5 页入门微课 + 3 题小测（必须完成才进主菜单）
  data/
    questions.json        2020—2025 客观题（adapted，含 material_id/audio/answer/explanation）
    materials.json        阅读文章、听力原文、匹配段落、选词填空词库
    words.json            按 2020—2025 真题文本词频排序的 Top 1500
    word_sentences.json   每词最多两条：真题原句 + 离线趣味句；可选 DeepSeek 重新预生成
    word_progress.json    已学词、每日游标、复习队列、掌握状态
    wrongbook.json        按题型记录的错题、答案、理由、讲解摘要、技巧
    checkin.json          每日基础/刷题打卡、连续天数、里程碑
    audio_timepoints.json 整卷切分时间点；缺失时只提示，不猜
    import_report.json    本次导入统计 + 缺口报告
    gap_report.json       2020—2025 唯一题量/题位缺口的单独说明
    techniques.json       技巧库：id/题型/场景/动作/依据/置信度
    cache/                DeepSeek 讲解与周复盘缓存，目录可删
    logs/                 app 日志、cleanup 日志、脱敏 llm.jsonl
    sessions/             单词/刷题断点 JSON（按日期）
    history/              每轮学习档案（完整题目/答案/理由/讲解摘要）
    plans/                每日 20 题计划 JSON
  library/
    source_audio/         用户放入的原始听力素材（本系统不删除）
    audio/                整理后的 Section 音频 + index.json
  temp/                   运行期临时文件；旧听力目录会在启动时清理
  tools/
    build_data.py         开发期从真实 SQLite 生成 data/（运行时不需要 Python）
    Generate-WordSentences.ps1  一次性 DeepSeek 趣味句预生成（分批、可续跑）
    translate_sentences.py      可选的真题句翻译构建工具
    apply_translations.py       把已缓存的翻译写回 word_sentences.json
  tests/                  可重复运行的离线测试与 mock LLM 服务
  docs/                   使用说明、文件职责、LLM 封装说明、数据来源
```

## 关键设计

### 单词 1500 与 50/50

- 从 2020—2025 年题库文本（阅读文章、题干/选项、听力原文、选词填空词库）统计词频；去掉纯功能词和明显超出学习价值的词，取 Top 1500。
- 前 750 名为 `core`（核心词）：英译中 + 中译英 + 造句；后 750 名为 `recognition`（认识词）：只做英译中。
- **每天从 core 池取约 13 个、recognition 池取约 13 个**，而不是按整张表顺序先做完前 750。这样每天新词约 26 个且保持 50/50；90 天计划里全部覆盖后，剩余天数进入错词回炉。
- 复习错词默认双向；若当天时间不足，可降级为英译中，并把 `reviewMode` 记录到状态里。
- 看句子时先不显示中文；提交后再显示释义、词性、中文提示/翻译。

### 句子来源 50/50

`word_sentences.json` 每个词通常有两条：一条来自 2020—2025 题库的真题原句，一条离线趣味/记忆卡句。学习时按会话计数器交替选择；真题句不存在时自动用趣味句补。首次可运行 `tools\Generate-WordSentences.ps1` 用 DeepSeek 批量替换趣味句（约 50 次调用），之后完全离线读取。

### 听力整理

- 支持 `2023.06_set1.mp3`、`2023年6月第1套.mp3`、`2023_06_set1_sectionA.mp3` 等命名；Section 可从文件名或目录识别。
- **已分 Section 优先快速路径**：直接复制并重命名为 `library/audio/<suite>/SectionA.mp3`，不转码。
- **整卷才切分**：只读取 `data/audio_timepoints.json` 的起止秒，调用 `ffmpeg -ss ... -to ... -i ... -c copy`；缺时间点只记录并提示，**绝不猜测**。
- 每次整理不删除源文件；生成 `index.json` 和 `audio_missing_report.json`。
- 若某题听力缺失，选题时按规则跳过，并在计划说明中提示“缺音频”。

### 临时工作区与清理

- 路径：`%TEMP%\CET4Coach\listening_<日期>\`。
- 单词任务开始复制今天计划所需音频并写 `manifest.json`；结束删除临时目录中的音频、manifest、中间文件/日志。
- 清理前计算 `library/audio` 文件数+总字节指纹，清理后复核；日志写“已删除临时文件 N 个，源音频目录未变动”。源素材和题库不动。
- 启动时清理超过 1 天的 `listening_*` 目录；异常退出不会阻断下次启动。

### DeepSeek 封装

完整说明见 [LLM_WRAPPER.md](LLM_WRAPPER.md)。核心保证：

- Key 只从 `DEEPSEEK_API_KEY` 读；不写 config/cache/log/prompt。
- 默认 `deepseek-chat`，`https://api.deepseek.com/chat/completions`；60 秒超时；网络/5xx/429 指数退避重试 2 次。
- 需要 JSON 时要求“只输出 JSON”，PowerShell 端去 markdown 围栏、截取第一个完整 `{}` 或 `[]`，解析失败重试一次；再失败由业务层降级本地提示。
- 错题讲解按“题目 ID + 用户选项”缓存；周复盘按周缓存；趣味句按词/批写入 JSON；回答评估不缓存。
- 日志只写用途、模型、耗时、重试次数、token 估算、是否命中缓存；不写 API Key、不写完整题干。日志用 `llm.jsonl`。
- 每日调用软预算默认 60 次；超过后本地判断/缓存继续可用，不阻塞学习。

### 题库与选题

- 适配器读取 `cet-practice` 的实际字段：`uid / paper_key / section / q_no / group_key / stem / options_json / answer / analysis_text / source_file`，并读取 `section_materials` 的 `content_json` 作为文章/听力原文。
- 按题干+选项 SHA256 去重，保留来源、年份、套卷、题型。
- 每轮 20 题：优先仔细阅读和听力篇章；有音频时 3 种题型，7 个主攻 + 7 个次重点 + 6 个混合；无音频时 14 个仔细阅读 + 3 个匹配 + 3 个选词，仍满足 3 种题型。
- 7 天窗口内不重复；题库不足时允许旧题重出（计划里注明），不伪造题目。

## 测试

```powershell
# 核心数据/选题
powershell -NoProfile -ExecutionPolicy Bypass -File tests\Test-Core.ps1
# 听力整理、切分、临时区清理（会用 ffmpeg 生成测试音频）
powershell -NoProfile -ExecutionPolicy Bypass -File tests\Test-Listening.ps1
# LLM 封装（本地 mock，检查缓存、JSON 重试、Key 缺失、日志脱敏）
powershell -NoProfile -ExecutionPolicy Bypass -File tests\Test-Llm.ps1
# 题库 SQLite 适配/dedupe
powershell -NoProfile -ExecutionPolicy Bypass -File tests\Test-Import.ps1
# 界面/交互流程
powershell -NoProfile -ExecutionPolicy Bypass -File tests\Test-Course.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests\Test-WordFlow.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests\Test-QuizFlow.ps1
```

测试会临时备份/恢复状态文件；不要在自己的正式学习数据上运行 `Test-*` 前删除备份。

## 已知边界

- 2020—2025 的唯一重点题量 620，低于题位目标 1,080；系统用“7 天后可重出”补题位，并在缺口报告里如实记录。若要更多新题，请用“题库导入”追加人工确认过的 2015—2019/2026 数据。
- 题库来源的 CET4 数据中，部分套卷本身是重复组卷，按题干+选项去重后只剩 1,668 道唯一客观题。
- `catteacher0515/cet4-download` 的 PDF/音频不能可靠地自动变成带答案的题目；系统不自动猜答案，需人工转 JSON/SQLite 后导入。
- 趣味句离线种子只保证“可读、可理解、含目标词”，不保证每条都像母语者写的谚语；建议运行一次 `Generate-WordSentences.ps1`。
- 真题句的中文翻译只有一部分有免费机器翻译；其余显示“中文提示”（目标词在该句中的核心意思），不是逐句翻译。

## 开源与许可

- 源代码：[MIT License](LICENSE)
- 题库/词典/翻译等数据：**不是 MIT 授权**，见 [DATA_LICENSE.md](DATA_LICENSE.md) 和 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)
- 贡献前请读 [CONTRIBUTING.md](CONTRIBUTING.md)
- 仓库：<https://github.com/KuzuryuYaichi-0721/cet4-coach>

