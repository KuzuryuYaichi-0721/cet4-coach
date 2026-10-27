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

$backup = @{}
foreach ($p in @('data\state.json','data\word_progress.json')) {
    $full = Join-Path $root $p
    if (Test-Path $full) { $backup[$p] = [IO.File]::ReadAllBytes($full) }
}
$sessionsDir = Join-Path $root 'data\sessions'
$oldSessions = @(Get-ChildItem $sessionsDir -File -ErrorAction SilentlyContinue)
function Find-Button($card, $text) {
    return @($card.Controls | Where-Object { $_ -is [System.Windows.Forms.Button] -and $_.Text -eq $text })[0]
}
try {
    $st = Get-AppState
    Set-ObjectPropertyValue $st 'onboardingComplete' $true
    Save-AppState $st
    $script:MainForm = New-MainWindow
    $script:MainForm.Show(); [System.Windows.Forms.Application]::DoEvents()
    Show-WordPage
    $entry = Get-WordEntryFromSession $script:WordUi.Session
    $wordObj = @(Get-WordBank | Where-Object { $_.word -eq $entry.word })[0]
    Write-Host "word=$($entry.word) meaning=$($wordObj.short_meaning)"
    $input = @($script:WordUi.Card.Controls | Where-Object { $_ -is [System.Windows.Forms.TextBox] })[0]
    $input.Text = $wordObj.short_meaning
    $btn = Find-Button $script:WordUi.Card '交给大肥鱼'
    $btn.PerformClick(); [System.Windows.Forms.Application]::DoEvents()
    Write-Host "after meaning step=$($script:WordUi.Session.step)"
    if ($script:WordUi.Session.step -ne 'meaning_feedback') { throw 'meaning step did not reach feedback' }
    $continue = @($script:WordUi.Card.Controls | Where-Object { $_ -is [System.Windows.Forms.Button] -and $_.Text -eq '继续' })[0]
    $continue.PerformClick(); [System.Windows.Forms.Application]::DoEvents()
    Write-Host "after continue step=$($script:WordUi.Session.step)"
    if ($script:WordUi.Session.step -ne 'english') { throw 'did not reach english step' }
    $input = @($script:WordUi.Card.Controls | Where-Object { $_ -is [System.Windows.Forms.TextBox] })[0]
    $input.Text = $entry.word
    $btn = Find-Button $script:WordUi.Card '交给大肥鱼'
    $btn.PerformClick(); [System.Windows.Forms.Application]::DoEvents()
    Write-Host "after english step=$($script:WordUi.Session.step)"
    $continue = @($script:WordUi.Card.Controls | Where-Object { $_ -is [System.Windows.Forms.Button] -and $_.Text -eq '继续' })[0]
    $continue.PerformClick(); [System.Windows.Forms.Application]::DoEvents()
    Write-Host "after continue2 step=$($script:WordUi.Session.step)"
    if ($script:WordUi.Session.step -ne 'sentence') { throw 'did not reach sentence step' }
    $input = @($script:WordUi.Card.Controls | Where-Object { $_ -is [System.Windows.Forms.TextBox] })[0]
    $input.Text = "This is a simple $($entry.word) sentence."
    $btn = Find-Button $script:WordUi.Card '交给大肥鱼'
    $btn.PerformClick(); [System.Windows.Forms.Application]::DoEvents()
    Write-Host "after sentence step=$($script:WordUi.Session.step)"
    $continue = @($script:WordUi.Card.Controls | Where-Object { $_ -is [System.Windows.Forms.Button] -and $_.Text -eq '继续' })[0]
    $continue.PerformClick(); [System.Windows.Forms.Application]::DoEvents()
    Write-Host "after next index=$($script:WordUi.Session.index) step=$($script:WordUi.Session.step) results=$(@($script:WordUi.Session.results).Count)"
    if ($script:WordUi.Session.index -ne 1) { throw 'index did not advance' }
    Write-Host 'Word flow test passed'
} catch {
    Write-Host ('WORD FLOW FAILED: ' + $_.Exception.Message)
    Write-Host $_.ScriptStackTrace
} finally {
    foreach ($p in @('data\state.json','data\word_progress.json')) {
        $full = Join-Path $root $p
        if ($backup[$p]) { [IO.File]::WriteAllBytes($full, $backup[$p]) }
    }
    foreach ($f in @(Get-ChildItem $sessionsDir -File -ErrorAction SilentlyContinue)) {
        if (-not ($oldSessions.Name -contains $f.Name)) { Remove-Item $f.FullName -Force }
    }
    if ($script:MainForm) { $script:MainForm.Close(); $script:MainForm.Dispose() }
}
