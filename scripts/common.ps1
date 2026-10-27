# common.ps1 - shared helpers: paths, JSON, fonts, progress dialogs, timers, safe logging.
# Compatible with Windows PowerShell 5.1 and PowerShell 7+.

$ErrorActionPreference = 'Stop'

if (-not (Get-Variable -Name CET4Root -Scope Script -ErrorAction SilentlyContinue)) {
    $script:CET4Root = Split-Path -Parent $PSScriptRoot
}

function Get-CET4Path {
    param([Parameter(Mandatory)][string]$Child)
    if ([System.IO.Path]::IsPathRooted($Child)) { return $Child }
    return [System.IO.Path]::GetFullPath((Join-Path $script:CET4Root $Child))
}

function Get-ObjectPropertyValue {
    param($Object, [string]$Name, $Default = $null)
    if ($null -eq $Object) { return $Default }
    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) { return $Object[$Name] }
        return $Default
    }
    $prop = $Object.PSObject.Properties[$Name]
    if ($null -eq $prop) { return $Default }
    return $prop.Value
}

function Set-ObjectPropertyValue {
    param($Object, [string]$Name, $Value)
    if ($null -eq $Object) { return }
    if ($Object -is [System.Collections.IDictionary]) {
        $Object[$Name] = $Value
        return
    }
    $prop = $Object.PSObject.Properties[$Name]
    if ($null -eq $prop) {
        $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
    } else {
        $prop.Value = $Value
    }
}

function Get-ConfigValue {
    param([string]$Path, $Default = $null)
    $node = $script:Config
    foreach ($part in ($Path -split '\.')) {
        if ($null -eq $node) { return $Default }
        $prop = $node.PSObject.Properties[$part]
        if ($null -eq $prop) { return $Default }
        $node = $prop.Value
    }
    if ($null -eq $node) { return $Default }
    return $node
}

function Read-JsonFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        $Default = $null,
        [switch]$Quiet
    )
    try {
        $full = Get-CET4Path $Path
        if (-not (Test-Path -LiteralPath $full)) { return $Default }
        $raw = [System.IO.File]::ReadAllText($full, [System.Text.Encoding]::UTF8)
        if ([string]::IsNullOrWhiteSpace($raw)) { return $Default }
        return ($raw | ConvertFrom-Json)
    } catch {
        if (-not $Quiet) {
            Write-CET4Log -Category 'json' -Message ("读取 JSON 失败 {0}: {1}" -f $Path, $_.Exception.Message)
        }
        return $Default
    }
}

function Write-JsonFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$Value,
        [int]$Depth = 20
    )
    $full = Get-CET4Path $Path
    $dir = Split-Path -Parent $full
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    $json = $Value | ConvertTo-Json -Depth $Depth
    $tmp = $full + '.tmp'
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($tmp, $json, $utf8)
    if (Test-Path -LiteralPath $full) { Remove-Item -LiteralPath $full -Force }
    Move-Item -LiteralPath $tmp -Destination $full
}

function Get-TodayString {
    return (Get-Date).ToString('yyyy-MM-dd')
}

function Get-NowStamp {
    return (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
}

function Write-CET4Log {
    param(
        [string]$Category = 'app',
        [string]$Message = '',
        [string]$Level = 'INFO'
    )
    try {
        if ($env:DEEPSEEK_API_KEY) { $Message = $Message.Replace($env:DEEPSEEK_API_KEY, '[已隐藏 API Key]') }
        $Message = [regex]::Replace($Message, 'sk-[A-Za-z0-9_\-]{8,}', 'sk-***')
        $logDir = Get-CET4Path (Get-ConfigValue 'paths.logs' 'data/logs')
        if (-not (Test-Path -LiteralPath $logDir)) { New-Item -ItemType Directory -Force -Path $logDir | Out-Null }
        $file = Join-Path $logDir ('app-{0}.log' -f (Get-Date).ToString('yyyy-MM-dd'))
        $line = '{0} [{1}] [{2}] {3}' -f (Get-NowStamp), $Level, $Category, $Message
        [System.IO.File]::AppendAllText($file, $line + [Environment]::NewLine, [System.Text.Encoding]::UTF8)
        if ((Get-Item $file).Length -gt 2MB) {
            $old = Join-Path $logDir ('app-{0}.old.log' -f (Get-Date).ToString('yyyy-MM-dd'))
            Move-Item -LiteralPath $file -Destination $old -Force
        }
    } catch {
        # Logging must never break the lesson.
    }
}

function Initialize-AppData {
    $dirs = @(
        (Get-ConfigValue 'paths.data' 'data'),
        (Get-ConfigValue 'paths.cache' 'data/cache'),
        (Get-ConfigValue 'paths.logs' 'data/logs'),
        (Get-ConfigValue 'paths.sessions' 'data/sessions'),
        (Get-ConfigValue 'paths.history' 'data/history'),
        (Get-ConfigValue 'paths.progress' 'data/progress'),
        (Get-ConfigValue 'paths.libraryAudio' 'library/audio'),
        (Get-ConfigValue 'paths.sourceAudio' 'library/source_audio'),
        (Get-ConfigValue 'paths.temp' 'temp')
    )
    foreach ($d in $dirs) {
        $full = Get-CET4Path $d
        if (-not (Test-Path -LiteralPath $full)) { New-Item -ItemType Directory -Force -Path $full | Out-Null }
    }
    $defaults = @{
        'paths.wrongbook'      = 'data/wrongbook.json'
        'paths.checkin'        = 'data/checkin.json'
        'paths.state'          = 'data/state.json'
        'paths.wordProgress'   = 'data/word_progress.json'
        'paths.audioTimepoints'= 'data/audio_timepoints.json'
        'paths.audioIndex'     = 'library/audio/index.json'
    }
    foreach ($k in $defaults.Keys) {
        $p = Get-CET4Path (Get-ConfigValue $k $defaults[$k])
        if (-not (Test-Path -LiteralPath $p)) {
            switch ($k) {
                'paths.checkin'       { Write-JsonFile $p @{ days = @{}; milestones = @() } }
                'paths.state'         { Write-JsonFile $p @{ onboardingComplete = $false; tutorialPassed = $false; version = 1 } }
                'paths.wordProgress'  { Write-JsonFile $p @{ introduced = @(); coreCursor = 0; recognitionCursor = 750; reviewQueue = @(); status = @{}; lastSessionDate = $null } }
                'paths.audioTimepoints' { Write-JsonFile $p ([ordered]@{ '_readme' = '套卷 ID -> 各 Section 起止秒。缺时间点时不猜测，程序只提示你补充。'; '2023-06-set1' = [ordered]@{ SectionA = @(0,420); SectionB = @(420,900); SectionC = @(900,1500) } }) }
                'paths.audioIndex'    { Write-JsonFile $p @() }
                default               { Write-JsonFile $p @() }
            }
        }
    }
    $state = Read-JsonFile (Get-ConfigValue 'paths.state' 'data/state.json') @{}
    if ($null -eq $state.PSObject.Properties['onboardingComplete']) {
        Write-JsonFile (Get-ConfigValue 'paths.state' 'data/state.json') @{ onboardingComplete = $false; tutorialPassed = $false; version = 1 }
    }
}

function Get-AppState {
    $state = Read-JsonFile (Get-ConfigValue 'paths.state' 'data/state.json') @{}
    if ($null -eq $state) { $state = [pscustomobject]@{} }
    return $state
}

function Save-AppState {
    param($State)
    Write-JsonFile (Get-ConfigValue 'paths.state' 'data/state.json') $State
}

function Test-DeepSeekKeyPresent {
    return -not [string]::IsNullOrWhiteSpace($env:DEEPSEEK_API_KEY)
}

function Format-SafeError {
    param($ErrorRecord)
    $msg = if ($ErrorRecord -and $ErrorRecord.Exception) { $ErrorRecord.Exception.Message } else { [string]$ErrorRecord }
    if ($env:DEEPSEEK_API_KEY) { $msg = $msg.Replace($env:DEEPSEEK_API_KEY, '[已隐藏 API Key]') }
    $msg = [regex]::Replace($msg, 'sk-[A-Za-z0-9_\-]{8,}', 'sk-***')
    return $msg
}

# ---------------- WinForms visual helpers ----------------

if (-not ('System.Windows.Forms.Application' -as [type])) {
    Add-Type -AssemblyName System.Windows.Forms
}
if (-not ('System.Drawing.Font' -as [type])) {
    Add-Type -AssemblyName System.Drawing
}

$script:UiFontName = 'Microsoft YaHei UI'
$script:UiTextColor = [System.Drawing.Color]::FromArgb(35, 53, 47)
$script:UiMutedColor = [System.Drawing.Color]::FromArgb(105, 120, 114)
$script:UiBackground = [System.Drawing.Color]::FromArgb(247, 243, 234)
$script:UiCard = [System.Drawing.Color]::White
$script:UiPrimary = [System.Drawing.Color]::FromArgb(31, 111, 92)
$script:UiPrimaryDark = [System.Drawing.Color]::FromArgb(23, 82, 68)
$script:UiAccent = [System.Drawing.Color]::FromArgb(232, 163, 61)
$script:UiDanger = [System.Drawing.Color]::FromArgb(180, 70, 60)
$script:UiGood = [System.Drawing.Color]::FromArgb(58, 130, 94)

function Get-MascotPath {
    param([string]$Expression = 'neutral')
    return (Join-Path $script:CET4Root ('assets\mascot\fish-' + $Expression + '.png'))
}

function New-MascotPicture {
    param([string]$Expression = 'neutral', [int]$Size = 72)
    $p = Get-MascotPath $Expression
    if (-not (Test-Path -LiteralPath $p)) { return $null }
    try {
        $img = [System.Drawing.Image]::FromFile($p)
        $pb = New-Object System.Windows.Forms.PictureBox
        $pb.Width = $Size; $pb.Height = $Size
        $pb.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
        $pb.BackColor = [System.Drawing.Color]::Transparent
        $pb.Image = $img
        $pb.TabStop = $false
        return $pb
    } catch { return $null }
}
function Get-UiFont {
    param([int]$Size = 16, [System.Drawing.FontStyle]$Style = [System.Drawing.FontStyle]::Regular)
    return New-Object System.Drawing.Font($script:UiFontName, $Size, $Style, [System.Drawing.GraphicsUnit]::Point)
}

function New-TableColumnStyle {
    param([System.Windows.Forms.SizeType]$Type, [double]$Value)
    return (New-Object System.Windows.Forms.ColumnStyle -ArgumentList $Type, $Value)
}

function New-TableRowStyle {
    param([System.Windows.Forms.SizeType]$Type, [double]$Value)
    return (New-Object System.Windows.Forms.RowStyle -ArgumentList $Type, $Value)
}

function New-UiLabel {
    param(
        [string]$Text = '',
        [int]$Size = 16,
        [System.Drawing.FontStyle]$Style = [System.Drawing.FontStyle]::Regular,
        [System.Drawing.Color]$Color = $script:UiTextColor,
        [int]$MaxWidth = 0
    )
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $Text
    $l.Font = Get-UiFont -Size $Size -Style $Style
    $l.ForeColor = $Color
    $l.AutoSize = $true
    $maxW = if ($MaxWidth -gt 0) { $MaxWidth } else { 1200 }
    $l.MaximumSize = New-Object System.Drawing.Size -ArgumentList $maxW, 0
    $l.Margin = New-Object System.Windows.Forms.Padding(0, 4, 0, 4)
    return $l
}

function New-UiButton {
    param(
        [string]$Text,
        [scriptblock]$OnClick,
        [int]$Width = 220,
        [int]$Height = 52,
        [System.Drawing.Color]$BackColor = $script:UiPrimary,
        [System.Drawing.Color]$ForeColor = [System.Drawing.Color]::White,
        [int]$Size = 16
    )
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $Text
    $b.Font = Get-UiFont -Size $Size -Style ([System.Drawing.FontStyle]::Bold)
    $b.Width = $Width
    $b.Height = $Height
    $b.BackColor = $BackColor
    $b.ForeColor = $ForeColor
    $b.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $b.FlatAppearance.BorderSize = 0
    $b.Cursor = [System.Windows.Forms.Cursors]::Hand
    $b.Margin = New-Object System.Windows.Forms.Padding(0, 5, 10, 5)
    if ($OnClick) { $b.Add_Click($OnClick) }
    return $b
}

function New-UiCard {
    param([int]$Width = 860, [int]$Height = 120, [System.Drawing.Color]$Color = $script:UiCard)
    $p = New-Object System.Windows.Forms.Panel
    $p.Width = $Width
    $p.Height = $Height
    $p.BackColor = $Color
    $p.Padding = New-Object System.Windows.Forms.Padding(18)
    $p.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 12)
    $p.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    return $p
}

function Set-StatusBar {
    param([string]$Text, [System.Drawing.Color]$Color = $script:UiMutedColor)
    if ($script:StatusLabel -and -not $script:StatusLabel.IsDisposed) {
        $script:StatusLabel.Text = $Text
        $script:StatusLabel.ForeColor = $Color
        [System.Windows.Forms.Application]::DoEvents()
    }
}

function Stop-PageTimer {
    if ($script:PageTimer) {
        try { $script:PageTimer.Stop(); $script:PageTimer.Dispose() } catch { }
        $script:PageTimer = $null
    }
}

function Set-PageTimer {
    param([int]$IntervalMs = 1000, [scriptblock]$OnTick)
    Stop-PageTimer
    $t = New-Object System.Windows.Forms.Timer
    $t.Interval = $IntervalMs
    $t.Add_Tick($OnTick)
    $t.Start()
    $script:PageTimer = $t
    return $t
}

function Reset-ContentScroll {
    if ($null -eq $script:ContentPanel) { return }
    $panel = $script:ContentPanel
    try {
        $panel.AutoScrollPosition = New-Object System.Drawing.Point(0, 0)
        $panel.VerticalScroll.Value = 0
        $panel.HorizontalScroll.Value = 0
        $panel.PerformLayout()
    } catch { }
    # 控件刚加入时布局还没算完；用一次性 Timer 在消息循环里再置顶一次。
    try {
        if ($script:ScrollResetTimer) { $script:ScrollResetTimer.Stop(); $script:ScrollResetTimer.Dispose() }
        $t = New-Object System.Windows.Forms.Timer
        $t.Interval = 60
        $t.Add_Tick({
            try {
                $script:ContentPanel.AutoScrollPosition = New-Object System.Drawing.Point(0, 0)
                $script:ContentPanel.VerticalScroll.Value = 0
                $script:ContentPanel.HorizontalScroll.Value = 0
            } catch { }
            try { $script:ScrollResetTimer.Stop(); $script:ScrollResetTimer.Dispose(); $script:ScrollResetTimer = $null } catch { }
        })
        $script:ScrollResetTimer = $t
        $t.Start()
    } catch { }
}

function Clear-ContentPanel {
    Stop-PageTimer
    if ($script:ContentPanel) {
        $script:ContentPanel.SuspendLayout()
        try {
            $script:ContentPanel.Controls.Clear()
            Reset-ContentScroll
        } finally {
            $script:ContentPanel.ResumeLayout($true)
        }
    }
}

function New-PageHeader {
    param([string]$Title, [string]$Subtitle = '')
    $head = New-Object System.Windows.Forms.Panel
    $head.Width = $script:UiContentWidth
    $head.Height = $(if ($Subtitle) { 96 } else { 72 })
    $head.BackColor = $script:UiBackground
    $head.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 10)
    $t = New-UiLabel -Text $Title -Size 30 -Style ([System.Drawing.FontStyle]::Bold) -Color $script:UiPrimaryDark -MaxWidth ($script:UiContentWidth - 10)
    $t.Location = New-Object System.Drawing.Point(0, 0)
    $head.Controls.Add($t)
    if ($Subtitle) {
        $s = New-UiLabel -Text $Subtitle -Size 14 -Color $script:UiMutedColor -MaxWidth ($script:UiContentWidth - 20)
        $s.Location = New-Object System.Drawing.Point(3, 56)
        $head.Controls.Add($s)
    }
    return $head
}

function Show-AppMessage {
    param([string]$Text, [string]$Title = '四级教练', [System.Windows.Forms.MessageBoxIcon]$Icon = [System.Windows.Forms.MessageBoxIcon]::Information)
    [System.Windows.Forms.MessageBox]::Show($script:MainForm, $Text, $Title, [System.Windows.Forms.MessageBoxButtons]::OK, $Icon) | Out-Null
}

function Confirm-App {
    param([string]$Text, [string]$Title = '请确认')
    return ([System.Windows.Forms.MessageBox]::Show($script:MainForm, $Text, $Title, [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question) -eq [System.Windows.Forms.DialogResult]::Yes)
}

# ---------------- progress window ----------------

function Show-UiProgress {
    param([string]$Title = '正在准备…', [string]$Text = '请稍等，程序没有卡住。')
    if ($script:ProgressForm -and -not $script:ProgressForm.IsDisposed) {
        Set-UiProgressText $Text
        return
    }
    $f = New-Object System.Windows.Forms.Form
    $f.Text = $Title
    $f.Width = 520
    $f.Height = 170
    $f.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterParent
    $f.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $f.ControlBox = $false
    $f.BackColor = $script:UiBackground
    $f.TopMost = $true
    $mascot = New-MascotPicture 'think' 62
    if ($mascot) { $mascot.Location = New-Object System.Drawing.Point(18, 18); $f.Controls.Add($mascot) }
    $lbl = New-UiLabel -Text $Text -Size 14 -MaxWidth 390
    $lbl.Location = New-Object System.Drawing.Point(96, 24)
    $bar = New-Object System.Windows.Forms.ProgressBar
    $bar.Location = New-Object System.Drawing.Point(96, 82)
    $bar.Width = 390
    $bar.Height = 20
    $bar.Style = [System.Windows.Forms.ProgressBarStyle]::Marquee
    $bar.MarqueeAnimationSpeed = 30
    $f.Controls.Add($lbl)
    $f.Controls.Add($bar)
    $script:ProgressLabel = $lbl
    $script:ProgressForm = $f
    $f.Show()
    $f.Refresh()
    [System.Windows.Forms.Application]::DoEvents()
}

function Set-UiProgressText {
    param([string]$Text)
    if ($script:ProgressLabel -and -not $script:ProgressLabel.IsDisposed) {
        $script:ProgressLabel.Text = $Text
        $script:ProgressForm.Refresh()
        [System.Windows.Forms.Application]::DoEvents()
    }
}

function Close-UiProgress {
    if ($script:ProgressForm -and -not $script:ProgressForm.IsDisposed) {
        $script:ProgressForm.Close()
        $script:ProgressForm.Dispose()
    }
    $script:ProgressForm = $null
    $script:ProgressLabel = $null
}

function Invoke-WithProgress {
    param(
        [string]$Title,
        [string]$InitialText,
        [scriptblock]$Action
    )
    Show-UiProgress -Title $Title -Text $InitialText
    try {
        & $Action
    } finally {
        Close-UiProgress
    }
}

# ---------------- misc ----------------

function Get-Sha256Hex {
    param([string]$Text)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
        return ([System.BitConverter]::ToString($sha.ComputeHash($bytes)) -replace '-', '').ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

function ConvertTo-SafeFileName {
    param([string]$Name)
    $invalid = [System.IO.Path]::GetInvalidFileNameChars()
    $out = $Name
    foreach ($c in $invalid) { $out = $out.Replace([string]$c, '_') }
    return $out
}

function Get-EuropeanDateLabel {
    param([datetime]$Date)
    $week = @('周日','周一','周二','周三','周四','周五','周六')[[int]$Date.DayOfWeek]
    return $Date.ToString('yyyy年M月d日') + ' ' + $week
}
