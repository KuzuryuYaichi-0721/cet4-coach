# 文件职责与数据结构

## 入口

| 文件 | 职责 |
|---|---|
| `main.ps1` | STA WinForms 启动；加载 config；按顺序 dot-source 所有模块；`Initialize-AppData`；启动时清理旧临时目录；检查 Key 并提示；创建主窗口；首次未完成微课时强制进入课程；全局异常写入日志。 |
| `RUN.bat` | 优先 `pwsh`，否则 Windows PowerShell；设置 UTF-8 代码页；把退出码错误停住方便看报错。 |
| `config.json` | 所有可调参数；**不含 Key**。路径既可用相对路径也可用绝对路径。 |

## scripts

### common.ps1

- `Get-CET4Path`/`Get-ConfigValue`：路径与点分配置读取。
- `Read-JsonFile`/`Write-JsonFile`：UTF-8 原子写；JSON 读写失败记录但不致死。
- `Write-CET4Log`：按日 app 日志，2MB 滚动；自动脱敏由调用方做。
- `Initialize-AppData`：创建目录；首次生成 `checkin.json`、`state.json`、`word_progress.json`、`audio_timepoints.json`、`audio/index.json`。
- UI 基础设施：字体（Microsoft YaHei UI）、颜色、`New-UiLabel`、`New-UiButton`、`New-UiCard`、`New-PageHeader`、状态栏、计时器、`Show-UiProgress` / `Set-UiProgressText` / `Close-UiProgress`。
- `Get-Sha256Hex`、`Get-ObjectPropertyValue`、`Set-ObjectPropertyValue`、`Format-SafeError`。

### ui.ps1

- `New-MainWindow`：根 TableLayoutPanel（顶栏 76 / 中间 / 底栏 34），中间两列（侧栏 218 + 内容），左侧 8 个导航按钮。
- `Show-HomePage`：日期、连续天数、基础/刷题状态、Key 提示、6 个入口卡片；周日自动生成周画像。
- `Show-SettingsPage`：只显示 Key 是否存在；模型/base URL；今日调用；题库/听力索引；ffmpeg/PotPlayer；缓存；测试连接。
- `Show-ImportPage`：文件/文件夹选择；调用 `Import-CetPracticeData`；展示缺口摘要。
- `Show-ListeningPage`：ffmpeg/PotPlayer/目录状态；开始整理；打开目录；清理旧临时区；缺失报告。
- `Invoke-PageLeave`：调用当前页注册的清理回调并停计时器。

### llm.ps1

- `Invoke-DeepSeekChat`：主请求。
- `Get-DeepSeekApiKey`：环境变量读取与错误提示。
- `Get-DeepSeekEndpoint`/`Get-DeepSeekCachePath`/`Get-DeepSeekCache`/`Set-DeepSeekCache`。
- `Get-DeepSeekDailyUsage`/`Add-DeepSeekUsage`/`Assert-DeepSeekBudget`。
- `Protect-DeepSeekLogText`/`Write-DeepSeekLog`。
- `Get-DeepSeekJsonCandidate`/`ConvertFrom-DeepSeekJsonText`：JSON 容错。
- `Estimate-DeepSeekTokens`。
- `Test-DeepSeekConnection`。

### listening.ps1

- `Get-FFmpegInfo`：检查 ffmpeg 与 ffprobe。
- `Resolve-PotPlayerPath`：配置 + 常见路径。
- `ConvertFrom-AudioFileName`：解析年份/月/套/Section；支持中英文命名；识别“第 1 套”“set1”“sectionA”。
- `Import-ListeningLibrary`：扫描、复制已分 Section、整卷 ffmpeg 切分、写 index/missing report。**不删源，不猜时间点**。
- `Find-ListeningAudio`、`Get-AudioIndex`。
- `Get-ListeningTempRoot`/`Get-ListeningTempDir`/`Initialize-ListeningTempWorkspace`。
- `Clear-ListeningTempWorkspace`：计算源指纹、删除当天临时目录、写 cleanup 日志、返回未变动校验。
- `Clear-OldListeningTemp`：启动时清理超过 24 小时的临时目录。
- `Start-ListeningPlayback`/`Stop-OwnPotPlayer`：只结束本系统启动的 PID；验证路径。
- `Get-NeededAudioFromPlan`。

### words.ps1

- 数据：`Get-WordBank`、`Get-WordSentenceBank`、`Get-WordProgress`、`Save-WordProgress`。
- 计划：`New-WordSessionPlan`（core/recognition 各约 13 个 + 到期复习，最多 48）、`New-WordSession`、`Get-ExistingWordSession`、`Save-WordSession`。
- 句子：`Get-SentenceForWordEntry`（真题/趣味交替）。
- 本地判断：`Test-WordMeaningLocal`、`Test-EnglishWordAnswer`、`Get-LevenshteinDistance`。
- 状态：`Get-WordStatusEntry`、`Add-ReviewQueueWord`、`Remove-ReviewQueueWord`、`Get-DueReviewWords`、`Complete-WordCurrentWord`。
- LLM：`Invoke-WordLlmCheck`（只对模糊/造句调用）。
- UI：`Show-WordPage`、`Show-WordStep`、`Show-WordFeedbackView`、`Show-WordSessionSummary`、`Complete-WordSessionUi`、`Continue-WordOrFinish`、`Add-WordReviewBatch`。
- 清理/打卡：`Start-WordSessionAudioPreparation`、`Stop-WordSessionCleanup`；完成时调用 `Add-WordCheckin`。

### quiz_data.ps1

- 题库：`Get-QuestionBank`、`Get-MaterialIndex`、`Get-QuizMaterial`。
- 技巧：`Get-TechniqueBank`、`Get-TechniqueForType`、`Get-TechniqueText`。
- 音频可用性：`Test-QuestionAudioAvailable`。
- 选题：`Get-RecentQuizQuestionIds`、`Select-QuizPool`、`Get-OrCreateDailyQuizPlan`。选题强制重点题和题型数量；无音频时跳过听力。
- 计划/断点：`Get-QuizPlanPath`、`New-QuizSession`、`Get-ExistingQuizSession`、`Save-QuizSession`。
- 错题本：`Add-QuestionToWrongBook`、`Register-CorrectWrongBookAnswer`；连续 2 次答对移出活跃错题。
- 音频路径：`Get-QuizAudioPath`（只从当天临时区取；没有临时文件就按缺音频处理）。
- `Format-QuestionOptionsForPrompt`。

### quiz.ps1

- `Start-QuizPage`：加载/恢复计划，准备临时音频，建 30 分钟 UI。
- `Show-QuizQuestion`：阅读材料、听力播放按钮、选项（≤4 用单选，>4 用下拉）、理由框、提交/跳过。
- `Get-SelectedQuizOption`、`Get-QuizSessionAnsweredCount`、`Get-QuizScoreSummary`。
- `Invoke-QuizEvaluation`：严格 JSON；失败本地降级。
- `Get-QuizTeacherFeedback`、`Get-LocalTeacherFeedback`、`Get-FeedbackText`。
- `Show-QuizFeedback`：结果、理由质量、错误类型、大肥鱼讲解、技巧、下一题。
- `Complete-QuizRound`：超时/完成；未答标记 incomplete 进复习；20 题完成才加刷题打卡；清理临时音频。

### import.ps1

- `Initialize-Cet4Sqlite` / `Invoke-Cet4SqliteQuery`：P/Invoke `winsqlite3.dll`（Windows 10/11 自带），不依赖 Python 或第三方 DLL。
- `ConvertFrom-CetPracticeRecord`：实际字段映射；听力题干从 `analysis_text` 的 `【题目】` 提取；匹配题从材料段落生成选项。
- `Get-MaterialsFromCetPracticeDb`：读取 `section_materials.content_json`，建文章/听力原文/匹配段落/选词词库。
- `Import-CetPracticeData`：DB 或 JSON；去重；写 `questions.json`、`materials.json`、`import_report.json`；备份旧题库到 `data/backup/`。
- `ConvertTo-QuestionHash`：题干+选项 SHA256。

### checkin.ps1

- `Get-CheckinData`/`Set-CheckinDay`/`Add-WordCheckin`/`Add-QuizCheckin`。
- `Get-CheckinStreak`：今天没打卡时从昨天回算。
- `Get-StreakEncouragement`：只在 7/14/30 天且当天未重复时返回鼓励。
- `Get-WeekStart`/`Get-WeeklyWrongStats`/`Get-LocalWeeklyReport`。
- `Invoke-WeeklyReport`：缓存 + 一次 DeepSeek 调用，失败回本地 3 句话。
- `Show-CheckinPage`：月历、里程碑、周画像卡片。

### course.ps1

- `$CourseSlides`：5 页结构/听力/阅读/写作翻译/时间轴，包含 ASCII 表格和色块。
- `Show-CoursePage`：翻页、进度、强制小测入口。
- `Show-CourseQuiz`：3 题；错题回对应页再讲；全对写 `onboardingComplete=true`。

## data 结构与关键字段

### questions.json（数组）

```json
{
  "id": "cet4-2020-07-1:listening:5",
  "paper_key": "cet4-2020-07-1",
  "year": 2020, "month": 7, "set_no": 1,
  "section": "listening", "type": "listening_news",
  "q_no": 5, "group_key": "g3",
  "stem": "...",
  "options": [{"key":"A","text":"..."}],
  "answer": "A",
  "material_id": "cet4-2020-07-1:listening:g3",
  "audio": {"required":true,"suite":"2020-07-set1","section":"A","audio_id":"2020-07-set1-SectionA"},
  "point": 7.1, "focus": false,
  "explanation": "题库参考解析",
  "source": "cet-practice ...",
  "source_file": "...",
  "hash": "sha256..."
}
```

### materials.json（数组）

`id` 为 `<paper_key>:<section>:<group_key>`；`kind` 为 `passage`/`transcript`/`matching`/`cloze`/`placeholder`。阅读显示 `text`；听力不提前显示，`transcript` 只在讲解里参考。

### words.json（数组）

`rank, word, frequency, cefr, pos, meaning, short_meaning, difficulty, group, source, corpus_years`。`group=core` 前 750，`recognition` 后 750。

### word_sentences.json（数组）

`word, en, zh, target_meaning, sentence_type（真题/趣味/谚语）, source, material_id, zh_source`。每个词最多两条（真题 + 趣味）；学习时 50/50 交替。

### wrongbook.json（数组）

`id, type, year, paper_key, stem, options, answer, userAnswer, userReason, errorType, explanation, teacherExplanation, technique, source, wrongCount, firstWrongAt, lastWrongAt, masteredConsecutive, active, incomplete`。

### checkin.json

```json
{"days":{"2026-10-27":{"word":true,"quiz":false,"minutes":30,"wordsDone":26,"quizCount":0,"updatedAt":"..."}},"milestones":[]}
```

### state.json

`onboardingComplete`、`tutorialPassed`、`tutorialCompletedAt`、`version`。

## 运行数据流

1. 启动 → `Initialize-AppData` → 清理旧临时区 → 主窗口。
2. 首次：课程 → 3 题小测 → 状态写入 → 主菜单。
3. 单词：选计划 → 复制听力到 TEMP → 30 分钟逐词 → 完成/超时 → 清理 TEMP → 基础打卡。
4. 刷题：选计划 → 准备 TEMP → 20 题/30 分钟 → 评估/讲解/错题本 → 完成 → 刷题打卡 → 清理。
5. 周日：首页触发一次周画像缓存。
