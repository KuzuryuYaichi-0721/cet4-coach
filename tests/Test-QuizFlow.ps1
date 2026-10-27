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
foreach ($p in @('data\state.json','data\wrongbook.json','data\checkin.json','data\word_progress.json')) {
    $full = Join-Path $root $p
    if (Test-Path $full) { $backup[$p] = [IO.File]::ReadAllBytes($full) }
}
$sessionsDir = Join-Path $root 'data\sessions'
$plansDir = Join-Path $root 'data\plans'
$oldSessions = @(Get-ChildItem $sessionsDir -File -ErrorAction SilentlyContinue)
$oldPlans = @(Get-ChildItem $plansDir -File -ErrorAction SilentlyContinue)
function Select-Option($key) {
    $ctrl = $script:QuizUi.OptionControls
    if ($ctrl -is [System.Windows.Forms.ComboBox]) {
        for ($i=0; $i -lt $ctrl.Items.Count; $i++) {
            if ([string]$ctrl.Items[$i] -match ('^' + [regex]::Escape($key) + '\)')) { $ctrl.SelectedIndex = $i; return }
        }
    } else {
        foreach ($rb in @($ctrl.Controls)) {
            if ($rb -is [System.Windows.Forms.RadioButton] -and [string]$rb.Tag -eq $key) { $rb.Checked = $true; return }
        }
    }
    throw "option $key not found"
}
try {
    $st = Get-AppState
    Set-ObjectPropertyValue $st 'onboardingComplete' $true
    Save-AppState $st
    Write-JsonFile (Join-Path $root 'data\wrongbook.json') @()
    $script:MainForm = New-MainWindow
    $script:MainForm.Show(); [System.Windows.Forms.Application]::DoEvents()
    Start-QuizPage
    $q = $script:QuizUi.Questions[0]
    $wrong = @($q.options | Where-Object { $_.key -ne $q.answer })[0].key
    Write-Host "q=$($q.id) type=$($q.type) answer=$($q.answer) choose=$wrong"
    Select-Option $wrong
    $reason = @($script:QuizUi.Card.Controls | Where-Object { $_ -is [System.Windows.Forms.TextBox] })[0]
    if (-not $reason) { throw 'reason textbox missing' }
    $reason.Text = '我选这个，因为原文里好像有这个词。'
    $submit = @($script:QuizUi.Card.Controls | Where-Object { $_ -is [System.Windows.Forms.Button] -and $_.Text -eq '提交答案和理由' })[0]
    $submit.PerformClick(); [System.Windows.Forms.Application]::DoEvents()
    Write-Host "after submit step index=$($script:QuizUi.Session.index) submitted=$($script:QuizUi.Session.current.submitted)"
    if (-not [bool]$script:QuizUi.Session.current.submitted) { throw 'not submitted' }
    $wb = @(Read-JsonFile (Join-Path $root 'data\wrongbook.json') @())
    Write-Host "wrongbook entries=$($wb.Count)"
    if ($wb.Count -lt 1) { throw 'wrongbook not updated' }
    $next = @($script:QuizUi.Card.Controls | Where-Object { $_ -is [System.Windows.Forms.Button] -and $_.Text -eq '下一题' })[0]
    if (-not $next) { throw 'next button missing' }
    $next.PerformClick(); [System.Windows.Forms.Application]::DoEvents()
    Write-Host "after next index=$($script:QuizUi.Session.index)"
    if ($script:QuizUi.Session.index -ne 1) { throw 'index did not advance' }
    Write-Host 'Quiz flow test passed'
} catch {
    Write-Host ('QUIZ FLOW FAILED: ' + $_.Exception.Message)
    Write-Host $_.ScriptStackTrace
} finally {
    foreach ($p in @('data\state.json','data\wrongbook.json','data\checkin.json','data\word_progress.json')) {
        $full = Join-Path $root $p
        if ($backup[$p]) { [IO.File]::WriteAllBytes($full, $backup[$p]) }
    }
    foreach ($f in @(Get-ChildItem $sessionsDir -File -ErrorAction SilentlyContinue)) {
        if (-not ($oldSessions.Name -contains $f.Name)) { Remove-Item $f.FullName -Force }
    }
    foreach ($f in @(Get-ChildItem $plansDir -File -ErrorAction SilentlyContinue)) {
        if (-not ($oldPlans.Name -contains $f.Name)) { Remove-Item $f.FullName -Force }
    }
    if ($script:MainForm) { $script:MainForm.Close(); $script:MainForm.Dispose() }
}
