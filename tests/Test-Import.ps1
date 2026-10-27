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
. (Join-Path $root 'scripts\import.ps1')
$db = Join-Path $root 'temp\cet_practice.db'
if (-not (Test-Path $db)) {
    Write-Host 'SKIP: tests\Test-Import.ps1 需要把 cet-practice 的 seed/cet6.db 放到 temp\cet_practice.db。'
    exit 0
}
$m = Get-MaterialsFromCetPracticeDb $db
Write-Host "materials $($m.Count)"
$r = Import-CetPracticeData -SourcePath $db -NoWrite
Write-Host "imported_new=$($r.imported_new) total=$($r.total_questions) focus=$($r.focus_questions) gap=$(@($r.gap_report).Count)"
Write-Host ('by type: ' + ($r.by_type | ConvertTo-Json -Compress))
if ($r.total_questions -lt 1600) { throw 'DB import lost questions' }
Write-Host 'Import adapter test passed'
