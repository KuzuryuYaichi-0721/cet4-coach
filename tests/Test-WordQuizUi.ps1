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
foreach ($d in @('data\sessions','data\plans')) {
    $full = Join-Path $root $d
    if (-not (Test-Path $full)) { New-Item -ItemType Directory -Force -Path $full | Out-Null }
    $backup[$d] = @(Get-ChildItem $full -File -ErrorAction SilentlyContinue)
}
function Shot($name) {
    [System.Windows.Forms.Application]::DoEvents()
    Start-Sleep -Milliseconds 500
    [System.Windows.Forms.Application]::DoEvents()
    $bmp = New-Object System.Drawing.Bitmap($script:MainForm.Width, $script:MainForm.Height)
    $script:MainForm.DrawToBitmap($bmp, (New-Object System.Drawing.Rectangle(0,0,$script:MainForm.Width,$script:MainForm.Height)))
    $bmp.Save((Join-Path $root ('tests\' + $name)), [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
}
try {
    $st = Get-AppState
    Set-ObjectPropertyValue $st 'onboardingComplete' $true
    Save-AppState $st
    $script:MainForm = New-MainWindow
    $script:MainForm.Show()
    [System.Windows.Forms.Application]::DoEvents()
    Show-WordPage
    Shot 'word.png'
    if ($script:WordUi -and $script:WordUi.Session) {
        Write-Host "word session plan: $(@($script:WordUi.Session.plan).Count), index=$($script:WordUi.Session.index), step=$($script:WordUi.Session.step)"
    }
    Show-HomePage
    Start-QuizPage
    Shot 'quiz.png'
    if ($script:QuizUi -and $script:QuizUi.Session) {
        Write-Host "quiz session q: $($script:QuizUi.Session.questionIds.Count), index=$($script:QuizUi.Session.index)"
    }
    Write-Host 'Word+Quiz UI smoke OK'
} catch {
    Write-Host ('FAILED: ' + $_.Exception.Message)
    Write-Host $_.ScriptStackTrace
} finally {
    foreach ($p in $backup.Keys) {
        if ($p -like 'data*') {
            $full = Join-Path $root $p
            if ($backup[$p] -is [byte[]]) { [IO.File]::WriteAllBytes($full, $backup[$p]) }
        }
    }
    foreach ($d in @('data\sessions','data\plans')) {
        $full = Join-Path $root $d
        if ($backup[$d]) {
            foreach ($f in @(Get-ChildItem $full -File -ErrorAction SilentlyContinue)) {
                if (-not ($backup[$d].Name -contains $f.Name)) { Remove-Item $f.FullName -Force }
            }
        }
    }
    if ($script:MainForm) { $script:MainForm.Close(); $script:MainForm.Dispose() }
}
