$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$script:CET4Root = $root
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
. (Join-Path $root 'scripts\common.ps1')
$script:Config = Read-JsonFile (Join-Path $root 'config.json')
. (Join-Path $root 'scripts\llm.ps1')
. (Join-Path $root 'scripts\listening.ps1')
. (Join-Path $root 'scripts\quiz_data.ps1')
. (Join-Path $root 'scripts\quiz.ps1')
. (Join-Path $root 'scripts\words.ps1')
. (Join-Path $root 'scripts\import.ps1')
. (Join-Path $root 'scripts\checkin.ps1')
. (Join-Path $root 'scripts\course.ps1')
. (Join-Path $root 'scripts\ui.ps1')

Write-Host "questions: $((Get-QuestionBank).Count)"
Write-Host "words: $((Get-WordBank).Count)"
Write-Host "sentences: $((Get-WordSentenceBank).Count)"
$plan = Get-OrCreateDailyQuizPlan -Quiet
Write-Host "plan types:" ($plan.type_counts | ConvertTo-Json -Compress)
Write-Host "focus: $($plan.focus_count), main: $($plan.main_type) $($plan.main_count)"
Write-Host "ids unique: $(@($plan.questions.id | Select-Object -Unique).Count)"
$wp = New-WordSessionPlan
$new = @($wp | Where-Object { $_.mode -eq 'new' })
$core = @($new | Where-Object { $_.group -eq 'core' }).Count
$rec = @($new | Where-Object { $_.group -eq 'recognition' }).Count
Write-Host "word plan: $($wp.Count) new=$($new.Count) review=$($wp.Count-$new.Count) core=$core rec=$rec"
$s = [pscustomobject]@{ plan = @($wp); sentenceCounter = 0; current = $null }
$entry = $wp[0]
$sent = Get-SentenceForWordEntry $s $entry
Write-Host "first word=$($entry.word) sentenceType=$($sent.sentence_type) en=$($sent.en.Substring(0,[Math]::Min(60,$sent.en.Length)))"
Write-Host "date: $(Get-TodayString); weekly start: $(Get-WeekStart)"
Write-Host "ffmpeg: $((Get-FFmpegInfo).Available)"
Write-Host "potplayer: $(Resolve-PotPlayerPath)"
