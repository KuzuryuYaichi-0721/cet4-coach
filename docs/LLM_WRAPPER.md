# Invoke-DeepSeekChat 封装说明

实现文件：`scripts/llm.ps1`。目标不是“能请求一次”，而是让一个没有工程背景的学习者，在本地长期使用时不把 Key 弄丢、不把日志变成泄密文件、不因为网络抖动就卡死。

## 1. 配置项

`config.json` 里只有：

```json
{
  "llm": {
    "baseUrl": "https://api.deepseek.com",
    "model": "deepseek-chat",
    "timeoutSec": 60,
    "maxRetries": 2,
    "dailyCallBudget": 60,
    "temperature": 0.3,
    "maxTokens": 1600,
    "cacheEnabled": true
  }
}
```

API Key **不在这里**，也不在 `data/` 的任何文件里。唯一读取处：

```powershell
[Environment]::GetEnvironmentVariable('DEEPSEEK_API_KEY','Process')
if ([string]::IsNullOrWhiteSpace($key)) {
    [Environment]::GetEnvironmentVariable('DEEPSEEK_API_KEY','User')
}
```

没有 Key 时 `Get-DeepSeekApiKey` 直接抛错，`Invoke-DeepSeekChat` 不会发出任何 HTTP 请求。主程序启动时检查并提示设置，但不把 Key 写进提示。

## 2. 函数签名

```powershell
Invoke-DeepSeekChat
  -System <string>
  -User <string>
  [-Purpose <string>]             # 日志用途，如 quiz_evaluation、quiz_explanation
  [-RequireJson]                  # 要求严格 JSON，并做容错提取
  [-CacheKey <string>]            # 显式缓存键；讲解用 "quiz-explanation:<qid>:<option>:v1"
  [-CacheParts <object>]          # 或传入参与哈希的对象
  [-Temperature <double>]
  [-MaxTokens <int>]
  [-TimeoutSec <int>]
  [-MaxRetries <int>]
  [-NoCache]
  [-BypassBudget]
  [-LogTag <string>]              # 只允许字母数字下划线短横线，最多 40 字符
```

返回：

```powershell
[pscustomobject]@{
  Content   = '模型回复的原文'
  Json      = $parsedObject 或 $null
  Usage     = @{ prompt_tokens; completion_tokens; total_tokens }
  Cached    = $true/$false
  ElapsedMs = 1234
  Attempts  = 1
  Purpose   = 'quiz_explanation'
  Model     = 'deepseek-chat'
}
```

## 3. 请求

- Endpoint：`baseUrl.TrimEnd('/') + '/chat/completions'`，默认 `https://api.deepseek.com/chat/completions`；如果配置本身已带 `/chat/completions` 则不重复拼。
- Header：`Authorization: Bearer <env key>`、`Accept: application/json`。
- Body：OpenAI 兼容 `model/messages/temperature/max_tokens/stream=false`；`-RequireJson` 时追加 `response_format = {type:"json_object"}`，并保证 system 里有 “JSON” 字样（DeepSeek JSON mode 的要求）。
- Body 用 UTF-8 字节发送，避免 Windows PowerShell 5.1 的中文编码问题。
- `Invoke-RestMethod` 的 `-TimeoutSec` 取配置，默认 60。

## 4. 重试与 JSON 容错

网络异常、429、5xx：指数退避，默认最多重试 2 次（总 3 次），延迟约 1.2s、2.4s，上限 8s。400/401/403/404/422 不重试，直接报错并提示检查 Key/模型/网络。

`RequireJson` 时：

1. 去掉 ```json ... ``` 围栏；
2. 从第一个 `{` 或 `[` 起，按字符串/转义/括号深度找第一个完整对象或数组；
3. `ConvertFrom-Json`；
4. 解析失败自动用同一 prompt 再请求一次，system 追加“只输出合法 JSON”；
5. 仍失败则抛“没有返回可解析的 JSON”，由业务层降级成本地判断/题库原有解析。

这比 `ConvertFrom-Json` 直接吃整段回复 tolerant，也不会把模型多写的一段解释带进解析器。

## 5. 缓存

缓存目录：`data/cache/llm/`，文件名是缓存键的 SHA256。缓存对象：

```json
{
  "version": 1,
  "purpose": "quiz_explanation",
  "createdAt": "...",
  "content": "模型原文",
  "json": { "...": "..." },
  "usage": { "prompt_tokens": 1, "completion_tokens": 1 }
}
```

使用规则：

- **错题讲解**：`Get-QuizTeacherFeedback` 传入 `quiz-explanation:<question.id>:<selected>:v1`，所以同一题、同一错误选项第二次看讲解不花钱；换选项才重新生成。
- **周复盘**：周缓存。
- **趣味句**：预生成写入 `word_sentences.json`（业务层缓存）；LLM 层再按批键缓存。
- **回答评估**：不缓存，传入 `-CacheParts $null` 且没有 `CacheKey`。
- 缓存只影响模型调用；不影响作答记录、错题本和打卡。

## 6. 日志与脱敏

日志：`data/logs/llm.jsonl`，每行：

```json
{"time":"...","purpose":"quiz_explanation","tag":"exp-...","model":"deepseek-chat","elapsedMs":1234,"attempts":1,"promptTokens":1000,"completionTokens":300,"totalTokens":1300,"cached":false,"jsonOk":true,"status":"ok","note":"不记录 API Key，也不记录题干全文"}
```

- 不记录完整 prompt、完整题干或用户答案。
- 异常信息经过 `Protect-DeepSeekLogText`：替换环境变量 Key、`sk-...`、`Bearer ...`，并截断 600 字符。
- API Key 永远不会出现在 `config.json`、缓存、日志、提示词或测试快照中。
- `data/logs/llm.jsonl` 超过 2MB 自动滚动为 `.1`。

## 7. 预算

`data/llm_usage.json` 记录当天：

```json
{
  "date": "2026-10-27",
  "calls": 43,
  "promptTokens": 0,
  "completionTokens": 0,
  "byPurpose": { "quiz_evaluation": 20, "quiz_explanation": 8, "word_sentence": 15 }
}
```

默认每天最多 60 次；超过时抛中文提示。单词/刷题会捕获这个错误并用本地判断继续，所以不会因为预算卡住学习。预生成可以用 `-AllowOverBudget` 明确破例（默认不使用）。

## 8. 当前每日调用策略

- 刷题：20 次回答评估；错误讲解优先缓存，首次错误约 8 次；合计约 28 次。
- 单词：中文释义先本地匹配；匹配明显成功时不调用；只有模糊/不确定和造句调用 LLM。26 个新词通常 13 个核心词，约 10—15 次。
- 周复盘：每周 1 次。
- 一次性趣味句预生成：约 50 次（30 词/批），在设置日单独进行。

## 9. 测试

`tests/Test-Llm.ps1` + `tests/mock_llm_server.py` 覆盖：

- 正常 JSON 返回、缓存命中；
- 第一次返回坏 JSON，第二次修复成功；
- 无 Key 时不发请求；
- 日志中不出现测试 Key；
- 在 PowerShell 5.1 与 7 下均通过。
