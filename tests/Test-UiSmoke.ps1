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
. (Join-Path $root 'scripts\progress.ps1')
. (Join-Path $root 'scripts\course.ps1')
. (Join-Path $root 'scripts\ui.ps1')

$statePath = Join-Path $root 'data\state.json'
$oldState = [IO.File]::ReadAllText($statePath)
$sessionsDir = Join-Path $root 'data\sessions'
if (-not (Test-Path $sessionsDir)) { New-Item -ItemType Directory -Force -Path $sessionsDir | Out-Null }
$oldSessions = @(Get-ChildItem $sessionsDir -File -ErrorAction SilentlyContinue)
function Shot($name) {
    [System.Windows.Forms.Application]::DoEvents()
    Start-Sleep -Milliseconds 600
    [System.Windows.Forms.Application]::DoEvents()
    $bmp = New-Object System.Drawing.Bitmap($script:MainForm.Width, $script:MainForm.Height)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $script:MainForm.DrawToBitmap($bmp, (New-Object System.Drawing.Rectangle(0, 0, $script:MainForm.Width, $script:MainForm.Height)))
    $g.Dispose()
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
    Show-HomePage
    Shot 'home.png'
    Show-CoursePage -FromMenu
    Shot 'course.png'
    Show-SettingsPage
    Shot 'settings.png'
    Show-ImportPage
    Shot 'import.png'
    $script:ContentPanel.AutoScrollPosition = New-Object System.Drawing.Point(0, 260)
    Show-ListeningPage
    if ([Math]::Abs($script:ContentPanel.AutoScrollPosition.Y) -gt 2) { throw 'page navigation did not reset scroll to top' }
    Shot 'listening.png'
    Show-CheckinPage
    Shot 'checkin.png'
    Write-Host 'UI smoke OK'
} catch {
    Write-Host ('UI smoke FAILED: ' + $_.Exception.Message)
    Write-Host $_.ScriptStackTrace
} finally {
    [IO.File]::WriteAllText($statePath, $oldState, (New-Object Text.UTF8Encoding($false)))
    foreach ($f in @(Get-ChildItem $sessionsDir -File -ErrorAction SilentlyContinue)) {
        if (-not ($oldSessions.Name -contains $f.Name)) { Remove-Item $f.FullName -Force }
    }
    if ($script:MainForm) { $script:MainForm.Close(); $script:MainForm.Dispose() }
}
