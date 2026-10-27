# llm.ps1 - DeepSeek OpenAI-compatible client with retries, JSON tolerance,
# local caching, budget accounting, and redacted logs.
# API key is read only from $env:DEEPSEEK_API_KEY and is never written anywhere.

$script:LlmCacheVersion = 1

function Get-DeepSeekApiKey {
    $key = [Environment]::GetEnvironmentVariable('DEEPSEEK_API_KEY', 'Process')
    if ([string]::IsNullOrWhiteSpace($key)) {
        $key = [Environment]::GetEnvironmentVariable('DEEPSEEK_API_KEY', 'User')
    }
    if ([string]::IsNullOrWhiteSpace($key)) {
        throw '还没有设置 DEEPSEEK_API_KEY。请在 PowerShell 中运行：setx DEEPSEEK_API_KEY "你的Key"，然后重新打开程序。'
    }
    return $key.Trim()
}

function Get-DeepSeekEndpoint {
    $base = [string](Get-ConfigValue 'llm.baseUrl' 'https://api.deepseek.com')
    $base = $base.Trim().TrimEnd('/')
    if ($base -match '/chat/completions$') { return $base }
    return $base + '/chat/completions'
}

function Get-DeepSeekCachePath {
    param([string]$CacheKey)
    $cacheDir = Get-CET4Path (Join-Path (Get-ConfigValue 'paths.cache' 'data/cache') 'llm')
    if (-not (Test-Path -LiteralPath $cacheDir)) { New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null }
    return (Join-Path $cacheDir ((Get-Sha256Hex $CacheKey) + '.json'))
}

function Get-DeepSeekCache {
    param([string]$CacheKey)
    if ([string]::IsNullOrWhiteSpace($CacheKey)) { return $null }
    $p = Get-DeepSeekCachePath $CacheKey
    if (-not (Test-Path -LiteralPath $p)) { return $null }
    try {
        $obj = Read-JsonFile $p $null -Quiet
        if ($null -eq $obj) { return $null }
        if ($obj.version -ne $script:LlmCacheVersion) { return $null }
        return $obj
    } catch {
        return $null
    }
}

function Set-DeepSeekCache {
    param([string]$CacheKey, [string]$Content, $Json, [string]$Purpose, $Usage)
    if ([string]::IsNullOrWhiteSpace($CacheKey)) { return }
    $obj = [ordered]@{
        version    = $script:LlmCacheVersion
        purpose    = $Purpose
        createdAt  = (Get-Date).ToString('o')
        content    = $Content
        json       = $Json
        usage      = $Usage
    }
    try { Write-JsonFile (Get-DeepSeekCachePath $CacheKey) $obj } catch { }
}

function Get-DeepSeekDailyUsage {
    $p = Get-CET4Path 'data/llm_usage.json'
    $u = Read-JsonFile $p $null -Quiet
    $today = Get-TodayString
    if ($null -eq $u -or (Get-ObjectPropertyValue $u 'date' '') -ne $today) {
        $u = [pscustomobject]@{ date = $today; calls = 0; promptTokens = 0; completionTokens = 0; byPurpose = @{} }
    }
    if ($null -eq (Get-ObjectPropertyValue $u 'byPurpose' $null)) {
        Set-ObjectPropertyValue $u 'byPurpose' @{}
    }
    return $u
}

function Add-DeepSeekUsage {
    param([string]$Purpose, [int]$PromptTokens = 0, [int]$CompletionTokens = 0, [int]$Calls = 1)
    try {
        $u = Get-DeepSeekDailyUsage
        $u.calls = [int](Get-ObjectPropertyValue $u 'calls' 0) + $Calls
        $u.promptTokens = [int](Get-ObjectPropertyValue $u 'promptTokens' 0) + $PromptTokens
        $u.completionTokens = [int](Get-ObjectPropertyValue $u 'completionTokens' 0) + $CompletionTokens
        $by = Get-ObjectPropertyValue $u 'byPurpose' $null
        if ($null -eq $by) { $by = @{}; Set-ObjectPropertyValue $u 'byPurpose' $by }
        $old = [int](Get-ObjectPropertyValue $by $Purpose 0)
        Set-ObjectPropertyValue $by $Purpose ($old + $Calls)
        Write-JsonFile (Get-CET4Path 'data/llm_usage.json') $u
    } catch {
        Write-CET4Log -Category 'llm' -Level 'WARN' -Message ('用量记录失败: ' + (Format-SafeError $_))
    }
}

function Assert-DeepSeekBudget {
    param([int]$ExtraCalls = 1, [switch]$BypassBudget)
    if ($BypassBudget) { return }
    $budget = [int](Get-ConfigValue 'llm.dailyCallBudget' 60)
    $u = Get-DeepSeekDailyUsage
    if ([int](Get-ObjectPropertyValue $u 'calls' 0) + $ExtraCalls -gt $budget) {
        throw ("今天的 DeepSeek 调用已达到上限（{0} 次）。为了控制成本，请明天继续；本地缓存和离线复习仍可使用。" -f $budget)
    }
}

function Protect-DeepSeekLogText {
    param([string]$Text)
    if ($null -eq $Text) { return '' }
    $s = $Text
    if ($env:DEEPSEEK_API_KEY) { $s = $s.Replace($env:DEEPSEEK_API_KEY, '[已隐藏 API Key]') }
    $s = [regex]::Replace($s, 'sk-[A-Za-z0-9_\-]{8,}', 'sk-***')
    $s = [regex]::Replace($s, '(?i)Bearer\s+[A-Za-z0-9._\-]+', 'Bearer ***')
    if ($s.Length -gt 600) { $s = $s.Substring(0, 600) + '…' }
    return $s
}

function Write-DeepSeekLog {
    param(
        [string]$Purpose,
        [string]$Model,
        [int]$ElapsedMs,
        [int]$Attempts,
        [int]$PromptTokens,
        [int]$CompletionTokens,
        [bool]$Cached,
        [bool]$JsonOk,
        [string]$Status = 'ok',
        [string]$LogTag = ''
    )
    try {
        $safeTag = ''
        if (-not [string]::IsNullOrWhiteSpace($LogTag)) {
            $safeTag = ($LogTag -replace '[^A-Za-z0-9_\-]', '')
            if ($safeTag.Length -gt 40) { $safeTag = $safeTag.Substring(0, 40) }
        }
        $line = [ordered]@{
            time         = (Get-Date).ToString('o')
            purpose      = $Purpose
            tag          = $safeTag
            model        = $Model
            elapsedMs    = $ElapsedMs
            attempts     = $Attempts
            promptTokens = $PromptTokens
            completionTokens = $CompletionTokens
            totalTokens  = $PromptTokens + $CompletionTokens
            cached       = $Cached
            jsonOk       = $JsonOk
            status       = $Status
            note         = '不记录 API Key，也不记录题干全文'
        }
        $logDir = Get-CET4Path (Get-ConfigValue 'paths.logs' 'data/logs')
        if (-not (Test-Path -LiteralPath $logDir)) { New-Item -ItemType Directory -Force -Path $logDir | Out-Null }
        $file = Join-Path $logDir 'llm.jsonl'
        $json = ($line | ConvertTo-Json -Compress)
        [System.IO.File]::AppendAllText($file, $json + [Environment]::NewLine, [System.Text.Encoding]::UTF8)
        if ((Get-Item $file).Length -gt 2MB) {
            Move-Item -LiteralPath $file -Destination ($file + '.1') -Force
        }
    } catch { }
}

function Estimate-DeepSeekTokens {
    param([string]$Text)
    if ($null -eq $Text) { return 0 }
    $cjk = ([regex]::Matches($Text, '[\u4e00-\u9fff]')).Count
    $rest = [Math]::Max(0, $Text.Length - $cjk)
    return [int][Math]::Ceiling($cjk * 0.75 + $rest / 4.0)
}

function Get-DeepSeekJsonCandidate {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $s = $Text.Trim()
    $s = [regex]::Replace($s, '^```(?:json)?\s*', '', 'IgnoreCase')
    $s = [regex]::Replace($s, '\s*```$', '')
    $firstObj = $s.IndexOf('{')
    $firstArr = $s.IndexOf('[')
    $start = -1
    if ($firstObj -ge 0 -and ($firstArr -lt 0 -or $firstObj -lt $firstArr)) { $start = $firstObj }
    elseif ($firstArr -ge 0) { $start = $firstArr }
    if ($start -lt 0) { return $s }
    $open = $s[$start]
    $close = if ($open -eq '{') { '}' } else { ']' }
    $depth = 0
    $inStr = $false
    $escaped = $false
    for ($i = $start; $i -lt $s.Length; $i++) {
        $ch = $s[$i]
        if ($inStr) {
            if ($escaped) { $escaped = $false }
            elseif ($ch -eq '\') { $escaped = $true }
            elseif ($ch -eq '"') { $inStr = $false }
            continue
        }
        if ($ch -eq '"') { $inStr = $true; continue }
        if ($ch -eq $open) { $depth++ }
        elseif ($ch -eq $close) {
            $depth--
            if ($depth -eq 0) { return $s.Substring($start, $i - $start + 1) }
        }
    }
    return $s.Substring($start)
}

function ConvertFrom-DeepSeekJsonText {
    param([string]$Text)
    $candidate = Get-DeepSeekJsonCandidate $Text
    if ($null -eq $candidate) { return $null }
    try { return ($candidate | ConvertFrom-Json) } catch { return $null }
}

function Get-DeepSeekCacheKey {
    param([string]$Purpose, $CacheParts, [string]$Model = '')
    if ([string]::IsNullOrWhiteSpace($Model)) { $Model = [string](Get-ConfigValue 'llm.model' 'deepseek-chat') }
    $payload = [ordered]@{ purpose = $Purpose; model = $Model; parts = $CacheParts }
    return (($payload | ConvertTo-Json -Depth 12 -Compress))
}

function Invoke-DeepSeekChat {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$System,
        [Parameter(Mandatory)][string]$User,
        [object[]]$Messages = $null,
        [string]$Purpose = 'general',
        [switch]$RequireJson,
        [string]$CacheKey = '',
        $CacheParts = $null,
        [double]$Temperature = -1,
        [int]$MaxTokens = 0,
        [int]$TimeoutSec = 0,
        [int]$MaxRetries = -1,
        [switch]$NoCache,
        [switch]$BypassBudget,
        [string]$LogTag = '',
        [string]$Model = ''
    )

    if ([string]::IsNullOrWhiteSpace($Model)) { $Model = [string](Get-ConfigValue 'llm.model' 'deepseek-chat') }
    $model = $Model
    if ($Temperature -lt 0) { $Temperature = [double](Get-ConfigValue 'llm.temperature' 0.3) }
    if ($MaxTokens -le 0) { $MaxTokens = [int](Get-ConfigValue 'llm.maxTokens' 1600) }
    if ($TimeoutSec -le 0) { $TimeoutSec = [int](Get-ConfigValue 'llm.timeoutSec' 60) }
    if ($MaxRetries -lt 0) { $MaxRetries = [int](Get-ConfigValue 'llm.maxRetries' 2) }
    $cacheEnabled = [bool](Get-ConfigValue 'llm.cacheEnabled' $true)

    if ([string]::IsNullOrWhiteSpace($CacheKey) -and $null -ne $CacheParts) {
        $CacheKey = Get-DeepSeekCacheKey -Purpose $Purpose -CacheParts $CacheParts -Model $model
    }
    $useCache = (-not $NoCache) -and $cacheEnabled -and (-not [string]::IsNullOrWhiteSpace($CacheKey))
    if ($useCache) {
        $cached = Get-DeepSeekCache $CacheKey
        if ($null -ne $cached) {
            $json = $null
            if ($RequireJson) {
                if ($null -ne $cached.json) { $json = $cached.json }
                else { $json = ConvertFrom-DeepSeekJsonText ([string]$cached.content) }
            }
            Write-DeepSeekLog -Purpose $Purpose -Model $model -ElapsedMs 0 -Attempts 0 -PromptTokens 0 -CompletionTokens 0 -Cached $true -JsonOk ($null -ne $json) -Status 'cache-hit' -LogTag $LogTag
            return [pscustomobject]@{
                Content = [string]$cached.content
                Json = $json
                Usage = $cached.usage
                Cached = $true
                ElapsedMs = 0
                Attempts = 0
                Purpose = $Purpose
                Model = $model
            }
        }
    }

    $apiKey = Get-DeepSeekApiKey
    Assert-DeepSeekBudget -BypassBudget:$BypassBudget

    $chatMessages = @()
    if ($Messages) {
        foreach ($m in @($Messages)) {
            $chatMessages += [ordered]@{ role = [string](Get-ObjectPropertyValue $m 'role' 'user'); content = [string](Get-ObjectPropertyValue $m 'content' '') }
        }
    } else {
        $chatMessages = @(
            [ordered]@{ role = 'system'; content = $System },
            [ordered]@{ role = 'user'; content = $User }
        )
    }
    $body = [ordered]@{
        model = $model
        messages = $chatMessages
        temperature = $Temperature
        max_tokens = $MaxTokens
        stream = $false
    }
    if ($RequireJson) {
        $body['response_format'] = @{ type = 'json_object' }
        # DeepSeek JSON mode requires the word json in the messages.
        if ($body.messages[0].content -notmatch '(?i)json') {
            $body.messages[0].content = $body.messages[0].content + "`n只输出一个合法 JSON 对象；不要输出 markdown、解释或代码围栏。"
        }
    }

    $endpoint = Get-DeepSeekEndpoint
    $headers = @{ Authorization = 'Bearer ' + $apiKey; Accept = 'application/json' }
    $bodyJson = $body | ConvertTo-Json -Depth 12 -Compress
    $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($bodyJson)
    $estimateText = if ($Messages) { (@($Messages | ForEach-Object { [string](Get-ObjectPropertyValue $_ 'content' '') }) -join "`n") } else { $System + "`n" + $User }
    $estimatePrompt = Estimate-DeepSeekTokens $estimateText
    $attempt = 0
    $jsonRepairUsed = $false
    $lastError = $null
    $started = [System.Diagnostics.Stopwatch]::StartNew()

    while ($attempt -le $MaxRetries) {
        $attempt++
        try {
            $resp = Invoke-RestMethod -Uri $endpoint -Method Post -Headers $headers `
                -ContentType 'application/json; charset=utf-8' -Body $bodyBytes -TimeoutSec $TimeoutSec `
                -ErrorAction Stop
            $content = $null
            if ($resp -and $resp.choices -and $resp.choices.Count -gt 0) {
                $content = [string]$resp.choices[0].message.content
            }
            if ([string]::IsNullOrWhiteSpace($content)) {
                $errMsg = ''
                if ($resp.error) { $errMsg = [string]$resp.error.message }
                throw ("DeepSeek 返回了空内容。{0}" -f $errMsg)
            }
            $usage = $null
            $pT = $estimatePrompt
            $cT = Estimate-DeepSeekTokens $content
            if ($resp.usage) {
                if ($resp.usage.prompt_tokens) { $pT = [int]$resp.usage.prompt_tokens }
                if ($resp.usage.completion_tokens) { $cT = [int]$resp.usage.completion_tokens }
            }
            $usage = [pscustomobject]@{ prompt_tokens = $pT; completion_tokens = $cT; total_tokens = $pT + $cT }
            Add-DeepSeekUsage -Purpose $Purpose -PromptTokens $pT -CompletionTokens $cT -Calls 1

            $json = $null
            $jsonOk = $true
            if ($RequireJson) {
                $json = ConvertFrom-DeepSeekJsonText $content
                $jsonOk = ($null -ne $json)
                if (-not $jsonOk -and -not $jsonRepairUsed) {
                    $jsonRepairUsed = $true
                    # One JSON-specific retry, then let the caller degrade gracefully.
                    if ($attempt -le $MaxRetries) {
                        $body.messages[0].content = $System + "`n重要：上次回复不是合法 JSON。只输出一个合法 JSON 对象，不要输出 markdown、解释或代码围栏。"
                        $bodyJson = $body | ConvertTo-Json -Depth 12 -Compress
                        $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($bodyJson)
                        throw 'JSON 解析失败，准备重试一次。'
                    }
                }
                if (-not $jsonOk) {
                    throw 'DeepSeek 没有返回可解析的 JSON。'
                }
            }

            $elapsed = [int]$started.ElapsedMilliseconds
            if ($useCache) {
                Set-DeepSeekCache -CacheKey $CacheKey -Content $content -Json $json -Purpose $Purpose -Usage $usage
            }
            Write-DeepSeekLog -Purpose $Purpose -Model $model -ElapsedMs $elapsed -Attempts $attempt -PromptTokens $pT -CompletionTokens $cT -Cached $false -JsonOk $jsonOk -Status 'ok' -LogTag $LogTag
            return [pscustomobject]@{
                Content = $content
                Json = $json
                Usage = $usage
                Cached = $false
                ElapsedMs = $elapsed
                Attempts = $attempt
                Purpose = $Purpose
                Model = $model
            }
        } catch {
            $lastError = $_
            $errText = Format-SafeError $_
            $isJsonRepair = ($errText -like '*JSON*')
            $transient = $true
            if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
                $code = [int]$_.Exception.Response.StatusCode
                if ($code -in @(400,401,403,404,422)) { $transient = $false }
            }
            Write-DeepSeekLog -Purpose $Purpose -Model $model -ElapsedMs ([int]$started.ElapsedMilliseconds) -Attempts $attempt -PromptTokens 0 -CompletionTokens 0 -Cached $false -JsonOk $false -Status ('attempt-failed: ' + (Protect-DeepSeekLogText $errText)) -LogTag $LogTag
            if ($attempt -gt $MaxRetries) { break }
            if (-not $transient -and -not $isJsonRepair) { break }
            $delay = [Math]::Min(8000, [int](1200 * [Math]::Pow(2, $attempt - 1)))
            Start-Sleep -Milliseconds $delay
        }
    }

    Add-DeepSeekUsage -Purpose ($Purpose + '_failed') -Calls 1
    throw ("DeepSeek 调用失败：{0}" -f (Format-SafeError $lastError))
}

function Test-DeepSeekConnection {
    if (-not (Test-DeepSeekKeyPresent)) {
        return [pscustomobject]@{ Ok = $false; Message = '没有找到 DEEPSEEK_API_KEY，不会调用大模型。' }
    }
    try {
        Show-UiProgress -Title '测试 DeepSeek' -Text '正在发送一条最小请求…'
        $r = Invoke-DeepSeekChat -System '你是连接测试助手。只输出 JSON。' -User '只输出 {"ok":true}。' -Purpose 'diagnostic' -RequireJson -NoCache -MaxTokens 30 -MaxRetries 0 -LogTag 'connectivity'
        return [pscustomobject]@{ Ok = $true; Message = ('连接成功，模型：{0}，耗时 {1} ms' -f $r.Model, $r.ElapsedMs) }
    } catch {
        return [pscustomobject]@{ Ok = $false; Message = ('连接失败：' + (Format-SafeError $_)) }
    } finally {
        Close-UiProgress
    }
}
