# 测试说明

这些测试在 Windows PowerShell 5.1 和 PowerShell 7 下均可运行（需在项目根目录执行）。

| 测试 | 需要 | 覆盖 |
|---|---|---|
| `Test-Parse.ps1` | 无 | 所有 `.ps1` 语法解析（PS 5.1） |
| `Test-Core.ps1` | 无 | 题库/词表/句子数量、每日 50/50、20 题约束、ffmpeg/PotPlayer 探测 |
| `Test-Llm.ps1` | Python（启动本地 mock） | 成功调用、缓存命中、坏 JSON 重试、无 Key 不请求、日志不泄漏 Key |
| `Test-Listening.ps1` | ffmpeg | 文件名解析、已分 Section 复制、整卷切分、index、缺失报告、临时区复制/清理、源指纹不变 |
| `Test-Import.ps1` | `temp\cet_practice.db` | 真实 SQLite 字段适配、哈希去重；没有数据库时自动 SKIP |
| `Test-Course.ps1` | WinForms | 5 页微课 + 3 题小测 + 状态写入 |
| `Test-WordFlow.ps1` | WinForms | 单词三步（英译中→中译英→造句）离线流程、反馈、推进 |
| `Test-QuizFlow.ps1` | WinForms | 选项、理由、评估降级、错题本、下一题 |
| `Test-UiSmoke.ps1` | WinForms | 首页/课程/设置/导入/听力/打卡页面渲染 |
| `Test-WordQuizUi.ps1` | WinForms | 单词页、刷题页初始渲染 |

大部分测试会备份/恢复 `data/state.json`、`data/word_progress.json`、`data/wrongbook.json` 等；但建议在正式学习前先复制整个 `data` 目录再跑。

`mock_llm_server.py` 只监听 `127.0.0.1:18080`，仅测试用。
