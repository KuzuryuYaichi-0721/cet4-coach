$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$script:CET4Root = $root
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
. (Join-Path $root 'scripts\common.ps1')
$script:Config = Read-JsonFile (Join-Path $root 'config.json')
$oldKey = $env:DEEPSEEK_API_KEY
$proc = $null
$oldUsage = $null
$usageFile = Join-Path $root 'data\llm_usage.json'
if (Test-Path $usageFile) { $oldUsage = [IO.File]::ReadAllBytes($usageFile) }
try {
    $proc = Start-Process -FilePath 'python' -ArgumentList (Join-Path $root 'tests\mock_llm_server.py') -PassThru -WindowStyle Hidden
    Start-Sleep -Milliseconds 800
    $env:DEEPSEEK_API_KEY = 'test-key-not-real'
    Set-ObjectPropertyValue $script:Config.llm 'baseUrl' 'http://127.0.0.1:18080'
    . (Join-Path $root 'scripts\llm.ps1')
    . (Join-Path $root 'scripts\listening.ps1')
    . (Join-Path $root 'scripts\quiz_data.ps1')
    . (Join-Path $root 'scripts\quiz.ps1')
    $q = @(Get-QuestionBank | Where-Object { $_.type -eq 'careful_reading' -and @($_.options).Count -eq 4 })[0]
    $opts = @($q.options)
    $fb = Get-QuizTeacherFeedback -Question $q -Selected 'A' -UserReason '我选 A，因为看起来像原文。' -ReplayCount 0 -Correct $false -DisplayOptions $opts -CorrectKey ([string]$q.answer) -PreviousEntry $null
    if ([string](Get-ObjectPropertyValue $fb 'source' '') -notlike 'deepseek*') { throw 'deep call did not go through the network path' }
    if (@(Get-ObjectPropertyValue $fb 'option_analysis' @()).Count -ne 4) { throw 'deep network path did not preserve all-option analysis' }
    Write-Host 'Deep LLM network path passed'
} finally {
    if ($oldKey) { $env:DEEPSEEK_API_KEY = $oldKey } else { Remove-Item Env:DEEPSEEK_API_KEY -ErrorAction SilentlyContinue }
    if ($proc -and -not $proc.HasExited) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
    if ($null -ne $oldUsage) { [IO.File]::WriteAllBytes($usageFile, $oldUsage) } elseif (Test-Path $usageFile) { Remove-Item $usageFile -Force }
}
