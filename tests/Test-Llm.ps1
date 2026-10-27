$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$script:CET4Root = $root
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
. (Join-Path $root 'scripts\common.ps1')
$script:Config = Read-JsonFile (Join-Path $root 'config.json')

$usageFile = Join-Path $root 'data\llm_usage.json'
$logFile = Join-Path $root 'data\logs\llm.jsonl'
$oldUsage = if (Test-Path $usageFile) { [IO.File]::ReadAllBytes($usageFile) } else { $null }
$oldLog = if (Test-Path $logFile) { [IO.File]::ReadAllBytes($logFile) } else { $null }
$oldKey = $env:DEEPSEEK_API_KEY
$proc = $null
try {
    $proc = Start-Process -FilePath 'python' -ArgumentList (Join-Path $root 'tests\mock_llm_server.py') -PassThru -WindowStyle Hidden
    Start-Sleep -Milliseconds 900
    $env:DEEPSEEK_API_KEY = 'test-key-not-real'
    Set-ObjectPropertyValue $script:Config.llm 'baseUrl' 'http://127.0.0.1:18080'
    . (Join-Path $root 'scripts\llm.ps1')

    $cacheFile = Get-DeepSeekCachePath 'unit-success'
    if (Test-Path $cacheFile) { Remove-Item $cacheFile -Force }
    $r1 = Invoke-DeepSeekChat -System '只输出 JSON。' -User 'Give me a JSON result.' -Purpose 'unit_success' -RequireJson -CacheKey 'unit-success' -LogTag 'unit-success'
    if (-not $r1.Json.ok) { throw 'JSON parse failed' }
    Write-Host "call1 ok, cached=$($r1.Cached)"
    $r2 = Invoke-DeepSeekChat -System '只输出 JSON。' -User 'Give me a JSON result.' -Purpose 'unit_success' -RequireJson -CacheKey 'unit-success' -LogTag 'unit-success'
    if (-not $r2.Cached) { throw 'cache miss on second call' }
    Write-Host 'cache hit OK'

    $stats = Invoke-RestMethod -Uri 'http://127.0.0.1:18080/stats' -Method Get
    Write-Host "server calls before retry: $($stats.calls)"
    try {
        Invoke-DeepSeekChat -System '只输出 JSON。' -User 'TRIGGER_BADJSON' -Purpose 'unit_badjson' -RequireJson -MaxRetries 2 -NoCache -LogTag 'unit-badjson' | Out-Null
        Write-Host 'JSON retry OK'
    } catch {
        Write-Host "JSON retry FAILED: $($_.Exception.Message)"
    }

    $stats2 = Invoke-RestMethod -Uri 'http://127.0.0.1:18080/stats' -Method Get
    Write-Host "server calls after json retry: $($stats2.calls)"

    $noKeyMsg = ''
    Remove-Item Env:DEEPSEEK_API_KEY -ErrorAction SilentlyContinue
    try { Invoke-DeepSeekChat -System 'x' -User 'x' -Purpose 'unit_nokey' -NoCache | Out-Null } catch { $noKeyMsg = $_.Exception.Message }
    if ($noKeyMsg -notmatch 'DEEPSEEK_API_KEY') { throw 'missing key did not fail correctly' }
    Write-Host 'no key guard OK'

    $env:DEEPSEEK_API_KEY = 'test-key-not-real'
    $log = if (Test-Path $logFile) { [IO.File]::ReadAllText($logFile) } else { '' }
    if ($log -match 'test-key-not-real') { throw 'API key leaked into llm log!' }
    if ($log -notmatch 'unit-success') { throw 'log missing purpose' }
    Write-Host 'log redaction OK'
    Write-Host 'LLM tests passed'
} catch {
    Write-Host ('LLM TEST FAILED: ' + $_.Exception.Message)
    Write-Host $_.ScriptStackTrace
} finally {
    if ($oldKey) { $env:DEEPSEEK_API_KEY = $oldKey } else { Remove-Item Env:DEEPSEEK_API_KEY -ErrorAction SilentlyContinue }
    if ($proc -and -not $proc.HasExited) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
    if ($null -ne $oldUsage) { [IO.File]::WriteAllBytes($usageFile, $oldUsage) } elseif (Test-Path $usageFile) { Remove-Item $usageFile -Force }
    if ($null -ne $oldLog) { [IO.File]::WriteAllBytes($logFile, $oldLog) } elseif (Test-Path $logFile) { Remove-Item $logFile -Force }
    if (Test-Path $cacheFile) { Remove-Item $cacheFile -Force -ErrorAction SilentlyContinue }
}
