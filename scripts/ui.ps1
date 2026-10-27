# ui.ps1 - main window, dashboard, settings and the two tool pages.

$script:NavButtons = @()
$script:ContentPanel = $null
$script:StatusLabel = $null

function New-MainWindow {
    $width = [int](Get-ConfigValue 'ui.width' 1400)
    $height = [int](Get-ConfigValue 'ui.height' 940)
    try {
        $wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
        if ($wa.Width -gt 200) { $width = [Math]::Min($width, $wa.Width - 20) }
        if ($wa.Height -gt 200) { $height = [Math]::Min($height, $wa.Height - 20) }
    } catch { }
    $script:UiContentWidth = [Math]::Max(760, [Math]::Min(1060, $width - 292))
    $script:UiInnerWidth = $script:UiContentWidth - 50
    $form = New-Object System.Windows.Forms.Form
    $form.Text = [string](Get-ConfigValue 'appName' '四级教练 CET4Coach')
    $form.Width = $width
    $form.Height = $height
    $form.MinimumSize = New-Object System.Drawing.Size(1120, 760)
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $form.BackColor = $script:UiBackground
    $form.Font = Get-UiFont -Size 17
    try {
        $form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None
    } catch { }
    $root = New-Object System.Windows.Forms.TableLayoutPanel
    $root.Dock = [System.Windows.Forms.DockStyle]::Fill
    $root.ColumnCount = 1
    $root.RowCount = 3
    $root.ColumnStyles.Add((New-TableColumnStyle -Type ([System.Windows.Forms.SizeType]::Percent) -Value 100)) | Out-Null
    $root.RowStyles.Add((New-TableRowStyle -Type ([System.Windows.Forms.SizeType]::Absolute) -Value 88)) | Out-Null
    $root.RowStyles.Add((New-TableRowStyle -Type ([System.Windows.Forms.SizeType]::Percent) -Value 100)) | Out-Null
    $root.RowStyles.Add((New-TableRowStyle -Type ([System.Windows.Forms.SizeType]::Absolute) -Value 38)) | Out-Null
    $root.BackColor = $script:UiBackground
    $form.Controls.Add($root)

    $top = New-Object System.Windows.Forms.Panel
    $top.Dock = [System.Windows.Forms.DockStyle]::Fill
    $top.BackColor = $script:UiPrimaryDark
    $root.Controls.Add($top, 0, 0)
    $title = New-UiLabel -Text '四级教练' -Size 30 -Style ([System.Drawing.FontStyle]::Bold) -Color ([System.Drawing.Color]::White)
    $title.Location = New-Object System.Drawing.Point(24, 8)
    $top.Controls.Add($title)
    $sub = New-UiLabel -Text '本地题库 · 单词 30 分钟 · 20 题（听力/阅读）· 错题画像' -Size 13 -Color ([System.Drawing.Color]::FromArgb(205, 226, 217))
    $sub.Location = New-Object System.Drawing.Point(27, 56)
    $top.Controls.Add($sub)
    $api = New-UiLabel -Text '' -Size 12 -Color ([System.Drawing.Color]::FromArgb(255, 230, 170))
    $api.Location = New-Object System.Drawing.Point -ArgumentList ([Math]::Max(20, $width - 360)), 34
    $api.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
    if (Test-DeepSeekKeyPresent) {
        $api.Text = 'DeepSeek Key 已检测到'
        $api.ForeColor = [System.Drawing.Color]::FromArgb(200, 240, 215)
    } else {
        $api.Text = '未设置 API Key（本地功能可用）'
        $api.ForeColor = [System.Drawing.Color]::FromArgb(255, 220, 150)
    }
    $top.Controls.Add($api)

    $middle = New-Object System.Windows.Forms.TableLayoutPanel
    $middle.Dock = [System.Windows.Forms.DockStyle]::Fill
    $middle.ColumnCount = 2
    $middle.RowCount = 1
    $middle.ColumnStyles.Add((New-TableColumnStyle -Type ([System.Windows.Forms.SizeType]::Absolute) -Value 238)) | Out-Null
    $middle.ColumnStyles.Add((New-TableColumnStyle -Type ([System.Windows.Forms.SizeType]::Percent) -Value 100)) | Out-Null
    $middle.RowStyles.Add((New-TableRowStyle -Type ([System.Windows.Forms.SizeType]::Percent) -Value 100)) | Out-Null
    $root.Controls.Add($middle, 0, 1)

    $side = New-Object System.Windows.Forms.Panel
    $side.Dock = [System.Windows.Forms.DockStyle]::Fill
    $side.BackColor = [System.Drawing.Color]::FromArgb(239, 234, 222)
    $side.Padding = New-Object System.Windows.Forms.Padding(12)
    $middle.Controls.Add($side, 0, 0)

    $avatar = New-MascotPicture 'neutral' 82
    if ($avatar) { $avatar.Location = New-Object System.Drawing.Point(20, 12); $side.Controls.Add($avatar) }
    $mName = New-UiLabel -Text '大肥鱼' -Size 15 -Style ([System.Drawing.FontStyle]::Bold) -Color $script:UiPrimaryDark
    $mName.Location = New-Object System.Drawing.Point(22, 98); $side.Controls.Add($mName)
    $mSub = New-UiLabel -Text '今天也一起学吧' -Size 11 -Color $script:UiMutedColor
    $mSub.Location = New-Object System.Drawing.Point(23, 122); $side.Controls.Add($mSub)

    $navItems = @(
        @{ Text = '首页'; Action = { Show-HomePage } },
        @{ Text = '单词 30 分钟'; Action = { Show-WordPage } },
        @{ Text = '20 题刷题'; Action = { Start-QuizPage } },
        @{ Text = '打卡月历'; Action = { Show-CheckinPage } },
        @{ Text = '题库导入'; Action = { Show-ImportPage } },
        @{ Text = '听力整理'; Action = { Show-ListeningPage } },
        @{ Text = '入门微课'; Action = { Show-CoursePage -FromMenu } },
        @{ Text = '设置与诊断'; Action = { Show-SettingsPage } }
    )
    $y = 150
    $onboardingDone = [bool](Get-ObjectPropertyValue (Get-AppState) 'onboardingComplete' $false)
    foreach ($item in $navItems) {
        $b = New-UiButton -Text $item.Text -Width 212 -Height 48 -BackColor ([System.Drawing.Color]::FromArgb(239, 234, 222)) -ForeColor $script:UiTextColor
        $b.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
        $b.Padding = New-Object System.Windows.Forms.Padding(12, 0, 0, 0)
        $b.Font = Get-UiFont -Size 16 -Style ([System.Drawing.FontStyle]::Bold)
        $b.Location = New-Object System.Drawing.Point(10, $y)
        $b.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(222, 233, 226)
        $b.Add_Click($item.Action)
        if (-not $onboardingDone -and $item.Text -notin @('入门微课', '设置与诊断')) {
            $b.Enabled = $false
            $b.ForeColor = [System.Drawing.Color]::FromArgb(160, 158, 150)
        }
        $side.Controls.Add($b)
        $script:NavButtons += $b
        $y += 56
    }
    $help = New-UiLabel -Text '学习记录只保存在本机 data 目录；题库不会上传。' -Size 12 -Color $script:UiMutedColor -MaxWidth 200
    $help.Location = New-Object System.Drawing.Point(13, 600)
    $side.Controls.Add($help)
    if ($height -ge 860) {
        $full = New-MascotPicture 'fullbody' 170
        if ($full) { $full.Width = 96; $full.Height = 150; $full.Location = New-Object System.Drawing.Point(40, 660); $side.Controls.Add($full) }
    }

    $content = New-Object System.Windows.Forms.Panel
    $content.Dock = [System.Windows.Forms.DockStyle]::Fill
    $content.AutoScroll = $true
    $content.BackColor = $script:UiBackground
    $content.Padding = New-Object System.Windows.Forms.Padding(28, 18, 20, 22)
    $middle.Controls.Add($content, 1, 0)
    $script:ContentPanel = $content

    $bottom = New-Object System.Windows.Forms.Panel
    $bottom.Dock = [System.Windows.Forms.DockStyle]::Fill
    $bottom.BackColor = [System.Drawing.Color]::FromArgb(239, 234, 222)
    $root.Controls.Add($bottom, 0, 2)
    $status = New-UiLabel -Text '准备就绪。' -Size 12 -Color $script:UiMutedColor -MaxWidth $script:UiInnerWidth
    $status.Location = New-Object System.Drawing.Point(16, 8)
    $bottom.Controls.Add($status)
    $script:StatusLabel = $status

    $form.Add_FormClosing({
        try {
            if ($script:OnLeavePage) { & $script:OnLeavePage }
            Stop-PageTimer
            try { Save-PortableProgress -Silent } catch { }
            Stop-OwnPotPlayer
            Clear-ListeningTempWorkspace -Silent | Out-Null
        } catch { }
    })
    return $form
}

function Invoke-PageLeave {
    if ($script:OnLeavePage) {
        try { & $script:OnLeavePage } catch { Write-CET4Log -Category 'ui' -Level 'WARN' -Message ('离开页面清理失败: ' + (Format-SafeError $_)) }
        $script:OnLeavePage = $null
    }
    Stop-PageTimer
    Reset-ContentScroll
}

function New-DashboardCard {
    param(
        [string]$Title,
        [string]$Description,
        [string]$ButtonText,
        [scriptblock]$Action,
        [System.Drawing.Color]$Accent = $script:UiPrimary,
        [System.Drawing.Color]$BackColor = $script:UiCard,
        [int]$Width = 510,
        [int]$Height = 200
    )
    $card = New-UiCard -Width $Width -Height $Height -Color $BackColor
    $t = New-UiLabel -Text $Title -Size 21 -Style ([System.Drawing.FontStyle]::Bold) -Color $script:UiPrimaryDark -MaxWidth ($Width - 40)
    $t.Location = New-Object System.Drawing.Point(20, 16)
    $card.Controls.Add($t)
    $d = New-UiLabel -Text $Description -Size 15 -Color $script:UiMutedColor -MaxWidth ($Width - 44)
    $d.Location = New-Object System.Drawing.Point(22, 56)
    $card.Controls.Add($d)
    $b = New-UiButton -Text $ButtonText -Width 185 -Height 44 -Size 16 -BackColor $Accent -OnClick $Action
    $b.Location = New-Object System.Drawing.Point(22, 136)
    $card.Controls.Add($b)
    return $card
}

function Show-HomePage {
    Invoke-PageLeave
    Clear-ContentPanel
    $state = Get-AppState
    if (-not [bool](Get-ObjectPropertyValue $state 'onboardingComplete' $false)) {
        Show-CoursePage
        return
    }
    foreach ($b in $script:NavButtons) {
        $b.Enabled = $true
        if ($b.Text -in @('首页', '单词 30 分钟', '20 题刷题', '打卡月历', '题库导入', '听力整理')) {
            $b.ForeColor = $script:UiTextColor
        }
    }
    Clear-ContentPanel
    $planDay = 1
    try {
        $planStart = [datetime]::ParseExact([string](Get-ConfigValue 'plan.startDate' (Get-TodayString)), 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
        $planDay = [int][Math]::Max(1, [Math]::Min([int](Get-ConfigValue 'plan.days' 90), ((Get-Date).Date - $planStart.Date).Days + 1))
    } catch { }
    $head = New-PageHeader '今天想先学哪一段呀？' ((Get-EuropeanDateLabel (Get-Date)) + (' · 90 天计划第 {0} 天 · 每天只做两件事：单词 30 分钟、20 题。' -f $planDay))
    $script:ContentPanel.Controls.Add($head)

    $checkin = Get-CheckinData
    $today = Get-CheckinDay $checkin (Get-TodayString)
    $streak = Get-CheckinStreak $checkin
    $wordDone = if ($today) { [bool](Get-ObjectPropertyValue $today 'word' $false) } else { $false }
    $quizDone = if ($today) { [bool](Get-ObjectPropertyValue $today 'quiz' $false) } else { $false }
    $statusCard = New-UiCard -Width $script:UiContentWidth -Height 82
    $statusCard.Location = New-Object System.Drawing.Point(0, 110)
    $script:ContentPanel.Controls.Add($statusCard)
    $s1 = New-UiLabel -Text ("基础打卡：{0}   刷题：{1}   连续：{2} 天" -f $(if ($wordDone) { '已完成' } else { '未完成' }), $(if ($quizDone) { '已完成' } else { '未完成' }), $streak) -Size 17 -Style ([System.Drawing.FontStyle]::Bold) -Color $script:UiPrimaryDark
    $s1.Location = New-Object System.Drawing.Point(22, 24)
    $statusCard.Controls.Add($s1)

    if (-not (Test-DeepSeekKeyPresent)) {
        $banner = New-UiCard -Width $script:UiContentWidth -Height 84 -Color ([System.Drawing.Color]::FromArgb(255, 248, 226))
        $banner.Location = New-Object System.Drawing.Point(0, 204)
        $script:ContentPanel.Controls.Add($banner)
        $bl = New-UiLabel -Text '还没有 DEEPSEEK_API_KEY：单词/题库/听力仍可用，但大模型评估与深度讲解会跳过。设置方法在「设置与诊断」。' -Size 15 -Color ([System.Drawing.Color]::FromArgb(130, 86, 20)) -MaxWidth $script:UiInnerWidth
        $bl.Location = New-Object System.Drawing.Point(22, 20)
        $banner.Controls.Add($bl)
    }

    $wordExisting = Get-ExistingWordSession
    $quizExisting = Get-ExistingQuizSession
    $startY = if (Test-DeepSeekKeyPresent) { 208 } else { 304 }
    $wordText = if ($wordExisting) { '继续上次单词' } else { '开始今天的单词' }
    $wordDesc = if ($wordDone) { '今天的基础打卡已完成。再练只会进入错词回炉，不会加新词。' } else { '26 个新词 + 昨日错词；到 30 分钟自动收尾。句子先猜意思，核心词再中译英、造句。' }
    $quizText = if ($quizExisting) { '继续上次刷题' } else { '开始 20 题' }
    $quizDesc = if ($quizDone) { '今天的 20 题已完成。错题会在明天优先重出。' } else { '限时 30 分钟；至少 12 题来自仔细阅读/听力篇章，2—3 种题型混合。' }
    $cards = New-Object System.Windows.Forms.FlowLayoutPanel
    $cards.Location = New-Object System.Drawing.Point(0, $startY)
    $cards.Size = New-Object System.Drawing.Size(($script:UiContentWidth + 20), 620)
    $cards.AutoScroll = $true
    $cards.WrapContents = $true
    $script:ContentPanel.Controls.Add($cards)
    $cards.Controls.Add((New-DashboardCard -Title '单词 30 分钟' -Description $wordDesc -ButtonText $wordText -Action { Show-WordPage } -Width 510 -Height 200))
    $cards.Controls.Add((New-DashboardCard -Title '20 题限时刷题' -Description $quizDesc -ButtonText $quizText -Action { Start-QuizPage } -Accent $script:UiAccent -Width 510 -Height 200))
    $cards.Controls.Add((New-DashboardCard -Title '打卡月历' -Description '看这个月哪几天完成了单词/刷题；连续 7/14/30 天会有一句简短鼓励。' -ButtonText '看打卡' -Action { Show-CheckinPage } -BackColor ([System.Drawing.Color]::FromArgb(238, 245, 241)) -Width 510 -Height 200))
    $cards.Controls.Add((New-DashboardCard -Title '题库与缺口报告' -Description ('当前题库 {0} 题；导入后按题干+选项去重，并统计重点题型是否够用。' -f @(Get-QuestionBank).Count) -ButtonText '查看题库' -Action { Show-ImportPage } -BackColor ([System.Drawing.Color]::FromArgb(238, 245, 241)) -Width 510 -Height 200))
    $cards.Controls.Add((New-DashboardCard -Title '听力整理' -Description '已分 Section 的文件只复制重命名；整卷才按时间点用 ffmpeg 切。缺时间点不猜。' -ButtonText '整理听力' -Action { Show-ListeningPage } -BackColor ([System.Drawing.Color]::FromArgb(248, 241, 230)) -Width 510 -Height 200))
    $cards.Controls.Add((New-DashboardCard -Title '本周错题画像' -Description '周日自动生成 3—5 句；平时也可手动生成。总结错得最多的 2 个题型和 1 个共同模式。' -ButtonText '看错题画像' -Action { Show-CheckinPage } -BackColor ([System.Drawing.Color]::FromArgb(248, 241, 230)) -Width 510 -Height 200))

    # Sunday automatic weekly portrait (one cached call at most).
    if ((Get-Date).DayOfWeek -eq [System.DayOfWeek]::Sunday -and (Test-DeepSeekKeyPresent)) {
        $cache = Get-CET4Path ('data/cache/weekly-' + (Get-WeekStart).ToString('yyyy-MM-dd') + '.json')
        if (-not (Test-Path -LiteralPath $cache)) {
            try {
                Show-UiProgress -Title '周日错题画像' -Text '正在根据本周错题生成 3—5 句画像…'
                Invoke-WeeklyReport | Out-Null
            } catch { } finally { Close-UiProgress }
        }
    }
    Set-StatusBar '今天先完成单词 30 分钟；有余力再做 20 题。'
    Reset-ContentScroll
}

function Add-ProgressToolsCard {
    $progressCard = New-UiCard -Width $script:UiContentWidth -Height 250
    $progressCard.Location = New-Object System.Drawing.Point(0, 1050)
    $script:ContentPanel.Controls.Add($progressCard)
    $pt = New-UiLabel -Text '学习进度包（跨版本 / 换电脑）' -Size 21 -Style ([System.Drawing.FontStyle]::Bold) -Color $script:UiPrimaryDark
    $pt.Location = New-Object System.Drawing.Point(20, 16)
    $progressCard.Controls.Add($pt)
    $pdesc = New-UiLabel -Text '每次答题、每轮结束、关闭程序都会更新 data/progress/latest.cet4progress.json。换电脑或换版本时导出/导入这个文件；题目按“题干+选项内容指纹”匹配，不靠数据库行号。旧版本没有的新题会保留为可识别的导入题，不会丢进度。' -Size 14 -Color $script:UiMutedColor -MaxWidth $script:UiInnerWidth
    $pdesc.Location = New-Object System.Drawing.Point(20, 58)
    $progressCard.Controls.Add($pdesc)
    $exportBtn = New-UiButton -Text '导出学习进度' -Width 220 -Height 46 -Size 15 -OnClick {
        $dlg = New-Object System.Windows.Forms.SaveFileDialog
        $dlg.Title = '导出学习进度包'
        $dlg.Filter = 'CET4Coach 进度包 (*.cet4progress.json)|*.cet4progress.json|JSON (*.json)|*.json'
        $dlg.FileName = ('CET4Coach-progress-' + (Get-Date).ToString('yyyyMMdd') + '.cet4progress.json')
        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            try {
                $r = Export-LearningProgress -Path $dlg.FileName
                Show-AppMessage ("进度已导出。`n`n单词状态：{0} 条`n题目记录：{1} 条`n打卡：{2} 天`n`n文件：{3}" -f $r.Words, $r.Questions, $r.Checkins, $r.Path) '导出学习进度'
                Show-SettingsPage
            } catch {
                Show-AppMessage ('导出失败：' + (Format-SafeError $_)) '导出学习进度' ([System.Windows.Forms.MessageBoxIcon]::Warning)
            }
        }
    }
    $exportBtn.Location = New-Object System.Drawing.Point(20, 135)
    $progressCard.Controls.Add($exportBtn)
    $importBtn = New-UiButton -Text '导入学习进度' -Width 220 -Height 46 -Size 15 -BackColor $script:UiAccent -OnClick {
        $dlg = New-Object System.Windows.Forms.OpenFileDialog
        $dlg.Title = '导入学习进度包'
        $dlg.Filter = 'CET4Coach 进度包 (*.cet4progress.json)|*.cet4progress.json|JSON (*.json)|*.json'
        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            Show-UiProgress -Title '导入学习进度' -Text '正在按内容指纹匹配题目，并保留旧版本没有的新题…'
            try {
                $r = Import-LearningProgress -Path $dlg.FileName
                Show-AppMessage ("导入完成。`n`n匹配到当前题库：{0} 题`n当前题库没有、已保留：{1} 题`n单词状态：{2} 条`n打卡：{3} 天`n`n导入题会出现在题库中，标记为来自进度包。" -f $r.Matched, $r.Orphans, $r.Words, $r.Checkins) '导入学习进度'
                Show-SettingsPage
            } catch {
                Show-AppMessage ('导入失败：' + (Format-SafeError $_)) '导入学习进度' ([System.Windows.Forms.MessageBoxIcon]::Warning)
            } finally { Close-UiProgress }
        }
    }
    $importBtn.Location = New-Object System.Drawing.Point(260, 135)
    $progressCard.Controls.Add($importBtn)
    $ppath = New-UiLabel -Text ('自动进度文件：' + (Get-PortableProgressPath)) -Size 12 -Color $script:UiMutedColor -MaxWidth $script:UiInnerWidth
    $ppath.Location = New-Object System.Drawing.Point(20, 198)
    $progressCard.Controls.Add($ppath)
}

function Add-PlayerSettingsCard {
    $card = New-UiCard -Width $script:UiContentWidth -Height 250
    $card.Location = New-Object System.Drawing.Point(0, 720)
    $script:ContentPanel.Controls.Add($card)
    $t = New-UiLabel -Text '听力播放器' -Size 21 -Style ([System.Drawing.FontStyle]::Bold) -Color $script:UiPrimaryDark
    $t.Location = New-Object System.Drawing.Point(20, 14); $card.Controls.Add($t)
    $d = New-UiLabel -Text '内置播放器不依赖外部程序，兼容 WAV/MP3；也可以选 PotPlayer、Windows Media Player、系统默认或自定义程序。选 PotPlayer 但未安装时，播放前会询问是否打开下载页。' -Size 14 -Color $script:UiMutedColor -MaxWidth $script:UiInnerWidth
    $d.Location = New-Object System.Drawing.Point(20, 52); $card.Controls.Add($d)
    $values = @('builtin','potplayer','wmplayer','default','custom')
    $names = @('内置播放器（推荐）','PotPlayer','Windows Media Player','系统默认程序','自定义程序')
    $combo = New-Object System.Windows.Forms.ComboBox
    $combo.DropDownStyle = 'DropDownList'
    foreach ($n in $names) { [void]$combo.Items.Add($n) }
    $cur = [string](Get-ConfigValue 'listening.player' 'builtin')
    $idx = [Array]::IndexOf($values, $cur); if ($idx -lt 0) { $idx = 0 }
    $combo.SelectedIndex = $idx
    $combo.Location = New-Object System.Drawing.Point(20, 100)
    $combo.Width = 280; $combo.Height = 34
    $combo.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 12)
    $card.Controls.Add($combo)
    $custom = New-Object System.Windows.Forms.TextBox
    $custom.Text = [string](Get-ConfigValue 'listening.customPlayer' '')
    $custom.Location = New-Object System.Drawing.Point(318, 100)
    $custom.Width = 460; $custom.Height = 32
    $custom.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 11)
    $card.Controls.Add($custom)
    $browse = New-UiButton -Text '浏览…' -Width 90 -Height 34 -Size 13 -BackColor ([System.Drawing.Color]::FromArgb(224, 232, 255)) -ForeColor $script:UiPrimaryDark -OnClick {
        $dlg = New-Object System.Windows.Forms.OpenFileDialog
        $dlg.Filter = '播放器 (*.exe)|*.exe|所有文件 (*.*)|*.*'
        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $custom.Text = $dlg.FileName; $combo.SelectedIndex = 4 }
    }
    $browse.Location = New-Object System.Drawing.Point(790, 100); $card.Controls.Add($browse)
    $save = New-UiButton -Text '保存播放器设置' -Width 210 -Height 44 -Size 14 -OnClick {
        try {
            $cfg = Read-JsonFile (Get-CET4Path 'config.json') ([pscustomobject]@{})
            $listen = Get-ObjectPropertyValue $cfg 'listening' $null
            if ($null -eq $listen) { $listen = [pscustomobject]@{}; Set-ObjectPropertyValue $cfg 'listening' $listen }
            Set-ObjectPropertyValue $listen 'player' $values[$combo.SelectedIndex]
            Set-ObjectPropertyValue $listen 'customPlayer' $custom.Text.Trim()
            Write-JsonFile (Get-CET4Path 'config.json') $cfg
            $script:Config = $cfg
            Show-AppMessage ('播放器已保存：' + $names[$combo.SelectedIndex]) '听力播放器'
        } catch { Show-AppMessage ('保存失败：' + (Format-SafeError $_)) '听力播放器' ([System.Windows.Forms.MessageBoxIcon]::Warning) }
    }
    $save.Location = New-Object System.Drawing.Point(20, 165); $card.Controls.Add($save)
    $hint = New-UiLabel -Text $(if (Resolve-PotPlayerPath) { '已检测到 PotPlayer。' } else { '当前未检测到 PotPlayer；选择它时播放前会询问是否下载。' }) -Size 13 -Color $script:UiMutedColor -MaxWidth 600
    $hint.Location = New-Object System.Drawing.Point(250, 172); $card.Controls.Add($hint)
}

function Show-SettingsPage {
    Invoke-PageLeave
    Clear-ContentPanel
    $head = New-PageHeader '设置与诊断' '这里只显示状态，不读取、不显示 API Key 的内容。'
    $script:ContentPanel.Controls.Add($head)
    $keyOk = Test-DeepSeekKeyPresent
    $keyHint = if ($keyOk) { '已检测到 DEEPSEEK_API_KEY（只显示是否存在，不显示内容）' } else { '未设置。请在 PowerShell 运行：setx DEEPSEEK_API_KEY "你的Key"，然后关掉本程序重开。' }
    $ff = Get-FFmpegInfo
    $pot = Resolve-PotPlayerPath
    $usage = Get-DeepSeekDailyUsage
    $qCount = @(Get-QuestionBank).Count
    $audioCount = @(Get-AudioIndex).Count
    $cacheDir = Get-CET4Path (Get-ConfigValue 'paths.cache' 'data/cache')
    $cacheFiles = if (Test-Path -LiteralPath $cacheDir) { @(Get-ChildItem -LiteralPath $cacheDir -Recurse -File).Count } else { 0 }
    $fields = @(
        @{ K = 'API Key'; V = $keyHint; C = $(if ($keyOk) { $script:UiGood } else { $script:UiDanger }) },
        @{ K = '模型 / Base URL'; V = ('{0}  ·  {1}' -f (Get-ConfigValue 'llm.model' 'deepseek-chat'), (Get-ConfigValue 'llm.baseUrl' 'https://api.deepseek.com')); C = $script:UiTextColor },
        @{ K = '今日大模型调用'; V = ('{0} / {1} 次（预算 {1}）' -f [int](Get-ObjectPropertyValue $usage 'calls' 0), [int](Get-ConfigValue 'llm.dailyCallBudget' 60)); C = $script:UiTextColor },
        @{ K = '题库'; V = ('{0} 题（唯一题，已按题干+选项去重）' -f $qCount); C = $script:UiTextColor },
        @{ K = '听力索引'; V = ('{0} 个 Section 文件' -f $audioCount); C = $script:UiTextColor },
        @{ K = 'ffmpeg'; V = $ff.Message; C = $(if ($ff.Available) { $script:UiGood } else { $script:UiDanger }) },
        @{ K = 'PotPlayer'; V = $(if ($pot) { $pot } else { '未找到。请在 config.json 的 listening.potPlayer 填写完整路径。' }); C = $(if ($pot) { $script:UiGood } else { $script:UiDanger }) },
        @{ K = '缓存文件'; V = ('{0} 个（data/cache）' -f $cacheFiles); C = $script:UiTextColor }
    )
    $card = New-UiCard -Width $script:UiContentWidth -Height 590
    $card.Location = New-Object System.Drawing.Point(0, 100)
    $script:ContentPanel.Controls.Add($card)
    $fieldsHost = New-Object System.Windows.Forms.Panel
    $fieldsHost.Location = New-Object System.Drawing.Point(0, 0)
    $fieldsHost.Size = New-Object System.Drawing.Size(($script:UiContentWidth - 20), 470)
    $fieldsHost.AutoScroll = $true
    $fieldsHost.BackColor = $script:UiCard
    $card.Controls.Add($fieldsHost)
    $y = 20
    foreach ($f in $fields) {
        $k = New-UiLabel -Text ($f.K + '：') -Size 15 -Style ([System.Drawing.FontStyle]::Bold) -Color $script:UiMutedColor -MaxWidth 200
        $k.Location = New-Object System.Drawing.Point(20, $y)
        $fieldsHost.Controls.Add($k)
        $v = New-UiLabel -Text ([string]$f.V) -Size 15 -Color $f.C -MaxWidth 780
        $v.Location = New-Object System.Drawing.Point(225, $y)
        $fieldsHost.Controls.Add($v)
        $rowH = [Math]::Max(46, [int]$v.PreferredHeight + 16)
        $y += $rowH
    }
    $buttonY = 500
    $test = New-UiButton -Text '测试 DeepSeek 连接' -Width 235 -Height 46 -Size 15 -OnClick {
        $r = Test-DeepSeekConnection
        Show-AppMessage $r.Message '连接测试' $(if ($r.Ok) { [System.Windows.Forms.MessageBoxIcon]::Information } else { [System.Windows.Forms.MessageBoxIcon]::Warning })
    }
    $test.Location = New-Object System.Drawing.Point(20, $buttonY)
    $card.Controls.Add($test)
    $open = New-UiButton -Text '打开数据文件夹' -Width 180 -Height 46 -Size 15 -BackColor ([System.Drawing.Color]::FromArgb(210, 205, 192)) -ForeColor $script:UiTextColor -OnClick {
        Start-Process explorer.exe (Get-CET4Path 'data')
    }
    $open.Location = New-Object System.Drawing.Point(270, $buttonY)
    $card.Controls.Add($open)
    $course = New-UiButton -Text '重看入门微课' -Width 180 -Height 46 -Size 15 -BackColor $script:UiAccent -OnClick { Show-CoursePage -FromMenu }
    $course.Location = New-Object System.Drawing.Point(465, $buttonY)
    $card.Controls.Add($course)
    Add-PlayerSettingsCard
    Add-ProgressToolsCard
    Set-StatusBar '环境检查不会上传任何文件。'
    Reset-ContentScroll
}

function Show-ImportPage {
    Invoke-PageLeave
    Clear-ContentPanel
    $head = New-PageHeader '题库导入' '优先使用 cet-practice 的真实字段；按题干+选项 SHA256 去重，不重复导入。'
    $script:ContentPanel.Controls.Add($head)
    $report = Read-JsonFile (Get-CET4Path 'data/import_report.json') $null -Quiet
    $card = New-UiCard -Width $script:UiContentWidth -Height 320
    $card.Location = New-Object System.Drawing.Point(0, 100)
    $script:ContentPanel.Controls.Add($card)
    $count = @(Get-QuestionBank).Count
    $focus = @(Get-QuestionBank | Where-Object { $_.focus }).Count
    $lines = @(
        ('当前唯一题量：{0} 题' -f $count),
        ('其中仔细阅读+听力篇章：{0} 题' -f $focus),
        '题库来源：o-Sakurajimamai-o/cet-practice v1.1.0（真实 seed/cet6.db 中的 CET4 行，2020—2025）',
        '适配字段：uid / paper_key / section / q_no / group_key / stem / options_json / answer / analysis_text / source_file',
        '缺口处理：题位不足时按「7 天后才可重复」滚动；不假装题库有 1800 道唯一题。'
    )
    $info = New-Object System.Windows.Forms.RichTextBox
    $info.Location = New-Object System.Drawing.Point(20, 18)
    $info.Size = New-Object System.Drawing.Size($script:UiInnerWidth, 175)
    $info.ReadOnly = $true
    $info.BorderStyle = [System.Windows.Forms.BorderStyle]::None
    $info.BackColor = $script:UiCard; $info.ForeColor = $script:UiTextColor
    $info.Font = New-Object System.Drawing.Font($script:UiFontName, 14)
    $info.Text = ($lines -join [Environment]::NewLine)
    $card.Controls.Add($info)
    $b1 = New-UiButton -Text '选择 JSON / SQLite 文件' -Width 260 -Height 46 -Size 15 -OnClick {
        $dlg = New-Object System.Windows.Forms.OpenFileDialog
        $dlg.Title = '选择 cet-practice 导出的 JSON 或 seed 数据库'
        $dlg.Filter = '题库文件 (*.json;*.db)|*.json;*.db|所有文件 (*.*)|*.*'
        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            try {
                Show-UiProgress -Title '导入题库' -Text '正在读取文件并去重…'
                $r = Import-CetPracticeData -SourcePath $dlg.FileName
                Show-AppMessage ("导入完成：新增 {0} 题，当前共 {1} 题。" -f $r.imported_new, $r.total_questions) '题库导入'
                Show-ImportPage
            } catch {
                Show-AppMessage ('导入失败：' + (Format-SafeError $_)) '题库导入' ([System.Windows.Forms.MessageBoxIcon]::Warning)
            } finally { Close-UiProgress }
        }
    }
    $b1.Location = New-Object System.Drawing.Point(20, 215)
    $card.Controls.Add($b1)
    $b2 = New-UiButton -Text '选择文件夹批量导入' -Width 230 -Height 46 -Size 15 -BackColor $script:UiAccent -OnClick {
        $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
        $dlg.Description = '选择包含题目 JSON 的文件夹'
        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            try {
                Show-UiProgress -Title '导入题库' -Text '正在扫描文件夹并去重…'
                $r = Import-CetPracticeData -SourcePath $dlg.SelectedPath
                Show-AppMessage ("导入完成：新增 {0} 题，当前共 {1} 题。" -f $r.imported_new, $r.total_questions) '题库导入'
                Show-ImportPage
            } catch {
                Show-AppMessage ('导入失败：' + (Format-SafeError $_)) '题库导入' ([System.Windows.Forms.MessageBoxIcon]::Warning)
            } finally { Close-UiProgress }
        }
    }
    $b2.Location = New-Object System.Drawing.Point(295, 215)
    $card.Controls.Add($b2)

    $gapCard = New-UiCard -Width $script:UiContentWidth -Height 190
    $gapCard.Location = New-Object System.Drawing.Point(0, 365)
    $script:ContentPanel.Controls.Add($gapCard)
    $gl = New-UiLabel -Text '缺口报告' -Size 18 -Style ([System.Drawing.FontStyle]::Bold) -Color $script:UiPrimaryDark
    $gl.Location = New-Object System.Drawing.Point(20, 14)
    $gapCard.Controls.Add($gl)
    $totalReported = if ($report) { [int](Get-ObjectPropertyValue $report 'objective_questions' (Get-ObjectPropertyValue $report 'total_questions' 0)) } else { 0 }
    $focusReported = if ($report) { [int](Get-ObjectPropertyValue $report 'focus_questions' 0) } else { $focus }
    $gapText = if ($report) {
        "目标题位 90×20=1800；重点题位 90×12=1080。`n实际唯一题量 $totalReported，重点 $focusReported。`n题库用间隔重出补足题位；缺口与来源已写入 data/import_report.json。"
    } else { '还没有导入报告。导入一次后，这里会显示各题型题量与缺口。' }
    $gt = New-UiLabel -Text $gapText -Size 14 -Color $script:UiMutedColor -MaxWidth $script:UiInnerWidth
    $gt.Location = New-Object System.Drawing.Point(20, 54)
    $gapCard.Controls.Add($gt)
    $openReport = New-UiButton -Text '打开完整缺口报告' -Width 210 -Height 42 -Size 15 -BackColor ([System.Drawing.Color]::FromArgb(210, 205, 192)) -ForeColor $script:UiTextColor -OnClick {
        $p = Get-CET4Path 'data/import_report.json'
        if (Test-Path -LiteralPath $p) { Start-Process notepad.exe $p } else { Show-AppMessage '还没有导入报告。' '缺口报告' }
    }
    $openReport.Location = New-Object System.Drawing.Point(20, 125)
    $gapCard.Controls.Add($openReport)
    Set-StatusBar '导入不会删除你已有的题库；重复题会被哈希去重。'
    Reset-ContentScroll
}

function Show-ListeningPage {
    Invoke-PageLeave
    Clear-ContentPanel
    $head = New-PageHeader '听力素材自动化整理' '已分 Section 的文件优先复制重命名；整卷只在有明确时间点时切分。'
    $script:ContentPanel.Controls.Add($head)
    $ff = Get-FFmpegInfo
    $pot = Resolve-PotPlayerPath
    $source = Get-CET4Path (Get-ConfigValue 'paths.sourceAudio' 'library/source_audio')
    $lib = Get-CET4Path (Get-ConfigValue 'paths.libraryAudio' 'library/audio')
    $card = New-UiCard -Width $script:UiContentWidth -Height 300
    $card.Location = New-Object System.Drawing.Point(0, 100)
    $script:ContentPanel.Controls.Add($card)
    $lines = @(
        ('ffmpeg：{0}' -f $ff.Message),
        ('PotPlayer：{0}' -f $(if ($pot) { $pot } else { '未找到（在 config.json 的 listening.potPlayer 填写路径）' })),
        ('原始素材目录：{0}' -f $source),
        ('整理后音频库：{0}' -f $lib),
        ('音频索引：{0}' -f (Get-CET4Path (Get-ConfigValue 'paths.audioIndex' 'library/audio/index.json')))
    )
    $info = New-Object System.Windows.Forms.RichTextBox
    $info.Location = New-Object System.Drawing.Point(20, 18)
    $info.Size = New-Object System.Drawing.Size($script:UiInnerWidth, 185)
    $info.ReadOnly = $true
    $info.BorderStyle = [System.Windows.Forms.BorderStyle]::None
    $info.BackColor = $script:UiCard; $info.ForeColor = $script:UiTextColor
    $info.Font = New-Object System.Drawing.Font($script:UiFontName, 14)
    $info.Text = ($lines -join [Environment]::NewLine)
    $card.Controls.Add($info)
    $start = New-UiButton -Text '开始整理' -Width 170 -Height 46 -Size 15 -OnClick {
        try {
            Show-UiProgress -Title '整理听力素材' -Text '正在扫描文件名、识别套卷和 Section…'
            $r = Import-ListeningLibrary
            $msg = "扫描 {0} 个文件，复制 {1}，切分 {2}，已存在 {3} 个。缺失套卷 {4} 个。" -f $r.Scanned, $r.Copied, $r.Split, $r.AlreadyPresent, @($r.Missing).Count
            Show-AppMessage ($msg + "`n`n如果有整卷文件被跳过，请先在 data/audio_timepoints.json 补该套卷的起止秒；程序不会猜测。") '听力整理'
            Show-ListeningPage
        } catch {
            Show-AppMessage ('整理失败：' + (Format-SafeError $_)) '听力整理' ([System.Windows.Forms.MessageBoxIcon]::Warning)
        } finally { Close-UiProgress }
    }
    $start.Location = New-Object System.Drawing.Point(20, 220)
    $card.Controls.Add($start)
    $openSource = New-UiButton -Text '打开原始素材目录' -Width 210 -Height 46 -Size 15 -BackColor ([System.Drawing.Color]::FromArgb(210, 205, 192)) -ForeColor $script:UiTextColor -OnClick {
        if (-not (Test-Path -LiteralPath $source)) { New-Item -ItemType Directory -Force -Path $source | Out-Null }
        Start-Process explorer.exe $source
    }
    $openSource.Location = New-Object System.Drawing.Point(205, 220)
    $card.Controls.Add($openSource)
    $clean = New-UiButton -Text '清理旧临时目录' -Width 190 -Height 46 -Size 15 -BackColor $script:UiAccent -OnClick {
        try {
            $r = @(Clear-OldListeningTemp)
            Show-AppMessage ("已清理 {0} 个超过 1 天的临时目录。" -f $r.Count) '清理'
        } catch { Show-AppMessage ('清理失败：' + (Format-SafeError $_)) '清理' ([System.Windows.Forms.MessageBoxIcon]::Warning) }
    }
    $clean.Location = New-Object System.Drawing.Point(430, 220)
    $card.Controls.Add($clean)

    $missingCard = New-UiCard -Width $script:UiContentWidth -Height 270
    $missingCard.Location = New-Object System.Drawing.Point(0, 415)
    $script:ContentPanel.Controls.Add($missingCard)
    $mTitle = New-UiLabel -Text '缺失报告' -Size 18 -Style ([System.Drawing.FontStyle]::Bold) -Color $script:UiPrimaryDark
    $mTitle.Location = New-Object System.Drawing.Point(20, 14)
    $missingCard.Controls.Add($mTitle)
    $missing = @(Read-JsonFile (Get-CET4Path 'data/audio_missing_report.json') @() -Quiet)
    $mText = if ($missing.Count -eq 0) { '目前没有缺失记录，或者还没整理过。' } else { (@($missing | Select-Object -First 8 | ForEach-Object { '套卷 {0} 缺 {1}' -f (Get-ObjectPropertyValue $_ 'suite' ''), ((Get-ObjectPropertyValue $_ 'missing_sections' @()) -join '/') }) -join "`n") }
    $ml = New-UiLabel -Text $mText -Size 14 -Color $script:UiMutedColor -MaxWidth $script:UiInnerWidth
    $ml.Location = New-Object System.Drawing.Point(20, 54)
    $missingCard.Controls.Add($ml)
    Set-StatusBar '整理过程不会删除原始素材。'
    Reset-ContentScroll
}

function Show-StartupProgressDialog {
    try { Write-CET4Log -Category 'startup' -Level 'INFO' -Message '显示进度提醒' } catch { }
    $form = New-Object System.Windows.Forms.Form
    $form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None
    $form.Text = '学习进度提醒'
    $form.Size = New-Object System.Drawing.Size(700, 450)
    $form.StartPosition = 'Manual'
    $form.Left = 24
    $form.Top = 64
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.BackColor = [System.Drawing.Color]::FromArgb(255, 253, 247)
    $form.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 10)
    $pic = New-MascotPicture 'happy' 130
    if ($pic) { $pic.Location = New-Object System.Drawing.Point(24, 45); $form.Controls.Add($pic) }
    $title = New-UiLabel -Text '先存一下今天的进度吧' -Size 25 -Style ([System.Drawing.FontStyle]::Bold) -Color $script:UiPrimaryDark
    $title.Location = New-Object System.Drawing.Point(180, 36); $form.Controls.Add($title)
    $desc = New-UiLabel -Text '每次打开都会提醒一次：学习记录会自动保存到本机 data 目录。换电脑、重装或更新前，建议把整个 data 文件夹复制到 U 盘或网盘。' -Size 15 -Color $script:UiTextColor -MaxWidth 470
    $desc.Location = New-Object System.Drawing.Point(182, 86); $form.Controls.Add($desc)
    $path = New-UiLabel -Text ('进度包：' + (Get-PortableProgressPath)) -Size 12 -Color $script:UiMutedColor -MaxWidth 470
    $path.Location = New-Object System.Drawing.Point(182, 178); $form.Controls.Add($path)
    $tip = New-UiLabel -Text '也可以点“设置与诊断 → 学习进度包”导出/导入。' -Size 13 -Color $script:UiMutedColor -MaxWidth 470
    $tip.Location = New-Object System.Drawing.Point(182, 208); $form.Controls.Add($tip)
    $status = New-UiLabel -Text '' -Size 13 -Color $script:UiGood -MaxWidth 500
    $status.Location = New-Object System.Drawing.Point(182, 244); $form.Controls.Add($status)
    $save = New-UiButton -Text '立即保存进度' -Width 180 -Height 46 -Size 15 -OnClick {
        try {
            $r = Save-DailyProgress -Silent
            $status.Text = '已保存：' + $r.Package
        } catch { $status.Text = '保存失败：' + (Format-SafeError $_) }
    }
    $save.Location = New-Object System.Drawing.Point(20, 340); $form.Controls.Add($save)
    $open = New-UiButton -Text '打开 data 文件夹' -Width 180 -Height 46 -Size 15 -BackColor ([System.Drawing.Color]::FromArgb(210, 205, 192)) -ForeColor $script:UiTextColor -OnClick {
        try { Start-Process explorer.exe (Get-CET4Path 'data') } catch { }
    }
    $open.Location = New-Object System.Drawing.Point(210, 340); $form.Controls.Add($open)
    $close = New-UiButton -Text '关闭' -Width 130 -Height 46 -Size 15 -BackColor ([System.Drawing.Color]::FromArgb(232, 235, 240)) -ForeColor $script:UiTextColor -OnClick { $form.Close() }
    $close.Location = New-Object System.Drawing.Point(545, 340); $form.Controls.Add($close)
    $form.AcceptButton = $close
    $form.CancelButton = $close
    [void]$form.ShowDialog()
    try { Write-CET4Log -Category 'startup' -Level 'INFO' -Message '关闭进度提醒' } catch { }
}
