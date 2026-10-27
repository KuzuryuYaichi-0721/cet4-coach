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
$statePath = Join-Path $root 'data\state.json'
$old = [IO.File]::ReadAllBytes($statePath)
try {
    $st = Get-AppState; Set-ObjectPropertyValue $st 'onboardingComplete' $false; Save-AppState $st
    $script:MainForm = New-MainWindow; $script:MainForm.Show(); [System.Windows.Forms.Application]::DoEvents()
    Show-CoursePage
    for ($i=0; $i -lt 4; $i++) {
        $next = @($script:CourseCtx.Next.Controls.Count) # noop
        $script:CourseCtx.Next.PerformClick(); [System.Windows.Forms.Application]::DoEvents()
    }
    $script:CourseCtx.Next.PerformClick(); [System.Windows.Forms.Application]::DoEvents()
    Write-Host "quiz visible=$($script:CourseCtx.QuizPanel.Visible)"
    foreach ($q in $script:CourseQuestions) {
        $radios = @($script:CourseCtx.QuizPanel.Controls | Where-Object { $_ -is [System.Windows.Forms.RadioButton] })
        $target = @($radios | Where-Object { $_.Tag -eq $q.Answer })[0]
        if (-not $target) { throw "choice not found for $($q.Q)" }
        $target.Checked = $true
        $submit = @($script:CourseCtx.QuizPanel.Controls | Where-Object { $_ -is [System.Windows.Forms.Button] -and $_.Text -eq '提交这一题' })[0]
        $submit.PerformClick(); [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 500
        [System.Windows.Forms.Application]::DoEvents()
    }
    $final = @($script:CourseCtx.QuizPanel.Controls | Where-Object { $_ -is [System.Windows.Forms.Button] -and $_.Text -eq '进入主菜单' })[0]
    Write-Host "final button=$($null -ne $final)"
    if (-not $final) { throw 'final button missing' }
    $final.PerformClick(); [System.Windows.Forms.Application]::DoEvents()
    $st2 = Get-AppState
    Write-Host "onboarding=$($st2.onboardingComplete) tutorial=$($st2.tutorialPassed)"
    if (-not $st2.onboardingComplete) { throw 'onboarding not saved' }
    Write-Host 'Course test passed'
} catch {
    Write-Host ('COURSE TEST FAILED: ' + $_.Exception.Message)
    Write-Host $_.ScriptStackTrace
} finally {
    [IO.File]::WriteAllBytes($statePath, $old)
    if ($script:MainForm) { $script:MainForm.Close(); $script:MainForm.Dispose() }
}
