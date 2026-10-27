# 贡献指南

这是一个面向初学者、本地运行的四级备考工具。欢迎提 issue / PR，但请先看下面几条。

## 提交前

- 不要提交 `DEEPSEEK_API_KEY`、任何真实 API Key、日志、缓存、个人学习记录。
- 不要提交 `data/sessions/`、`data/plans/`、`data/logs/`、`data/cache/`。
- 题目/音频/词典数据有第三方版权，见 [DATA_LICENSE.md](DATA_LICENSE.md)。不要新增未经确认可再分发的受版权保护内容。
- 如果改了 UI，尽量附一张截图，并说明 Windows 缩放比例（100%/125%/150%）。
- 如果改了 PowerShell，分别用 Windows PowerShell 5.1 与 PowerShell 7 跑：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\Test-Parse.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests\Test-Core.ps1
```

## 代码风格

- 兼容 Windows PowerShell 5.1：不要用 `??`、三元运算符、`ForEach-Object -Parallel`。
- `.ps1` 文件保存为 **UTF-8 with BOM**（Windows PowerShell 5.1 识别中文所需）。
- UI 正文不小于 16px 等效大小，按钮大、留白足；新增等待必须有进度提示。
- 不把大模型 Key 写入配置、提示词、日志或缓存。
- 新功能尽量提供离线降级；不能因为无 Key 或额度用完就卡住学习。
