$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot; $script:CET4Root=$root
Add-Type -AssemblyName System.Windows.Forms; Add-Type -AssemblyName System.Drawing
. (Join-Path $root 'scripts\common.ps1'); $script:Config=Read-JsonFile (Join-Path $root 'config.json')
. (Join-Path $root 'scripts\llm.ps1'); . (Join-Path $root 'scripts\checkin.ps1')
$p=Join-Path $root 'data\checkin.json'; $old=[IO.File]::ReadAllBytes($p)
try{
  $r=Add-WordCheckin -Date (Get-Date).ToString('yyyy-MM-dd') -Minutes 30 -WordsDone 26
  Write-Host "streak=$($r.Streak) enc=$($r.Encouragement)"
  Add-QuizCheckin -Date (Get-Date).ToString('yyyy-MM-dd') -QuizCount 20
  $d=Get-CheckinData; Write-Host ($d|ConvertTo-Json -Depth 6 -Compress)
  $s=Get-WeeklyWrongStats; Write-Host "weekly wrong=$($s.Wrong.Count)"
  $wr=Invoke-WeeklyReport -Force; Write-Host "weekly source=$($wr.source) text=$($wr.text.Substring(0,[Math]::Min(80,$wr.text.Length)))"
  Remove-Item (Get-CET4Path ('data/cache/weekly-' + (Get-WeekStart).ToString('yyyy-MM-dd') + '.json')) -Force -ErrorAction SilentlyContinue
  Write-Host 'checkin test passed'
} finally { [IO.File]::WriteAllBytes($p,$old) }
