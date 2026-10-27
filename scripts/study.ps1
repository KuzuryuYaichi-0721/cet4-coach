$ErrorActionPreference = 'Stop'

function Get-StudyHash {
    param([string]$Text)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
        return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    } finally { $sha.Dispose() }
}

function Get-QuestionStudyText {
    param($Question)
    if ($null -eq $Question) { return '' }
    $mat = Get-QuizMaterial $Question
    if ($null -eq $mat) { return '' }
    $text = [string](Get-ObjectPropertyValue $mat 'text' '')
    if (-not $text) { $text = [string](Get-ObjectPropertyValue $mat 'transcript' '') }
    if (-not $text) { $text = [string](Get-ObjectPropertyValue $Question 'passage' '') }
    return $text.Trim()
}

function Get-StudyFreeTranslation {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    $clean = ($Text -replace '\s+', ' ').Trim()
    $parts = New-Object System.Collections.Generic.List[string]
    while ($clean.Length -gt 0) {
        $n = [Math]::Min(450, $clean.Length)
        if ($n -lt $clean.Length) {
            $cut = $clean.LastIndexOfAny(@([char]'.', [char]'!', [char]'?', [char]';'), $n - 1, $n)
            if ($cut -gt 180) { $n = $cut + 1 }
        }
        $parts.Add($clean.Substring(0, $n))
        $clean = $clean.Substring($n).Trim()
    }
    $out = @()
    foreach ($part in $parts) {
        try {
            $url = 'https://api.mymemory.translated.net/get?q=' + [uri]::EscapeDataString($part) + '&langpair=en%7Czh-CN'
            $r = Invoke-RestMethod -Uri $url -TimeoutSec 8 -Headers @{ 'User-Agent' = 'CET4Coach/1.3' }
            $t = [string]$r.responseData.translatedText
            if ($t) { $out += $t } else { break }
        } catch { break }
    }
    if ($out.Count -gt 0) { return ($out -join "`n`n") }
    return ''
}

function Get-LocalStudyContent {
    param([string]$Text)
    $translation = Get-StudyFreeTranslation $Text
    if (-not $translation) {
        $translation = '（免费翻译服务暂时不可用。先看下面的逐词释义；设置 DEEPSEEK_API_KEY 后可生成更准确的全文翻译。）'
    }
    $bank = @(Get-WordBank)
    $map = @{}
    foreach ($w in $bank) { $map[([string]$w.word).ToLowerInvariant()] = $w }
    $seen = @{}
    $words = New-Object System.Collections.Generic.List[object]
    $tokens = [regex]::Matches($Text, "[A-Za-z][A-Za-z'-]{1,}")
    foreach ($m in $tokens) {
        $word = $m.Value.Trim("'-").ToLowerInvariant()
        if ($word.Length -lt 2 -or $seen.ContainsKey($word)) { continue }
        $seen[$word] = $true
        $entry = $map[$word]
        $meaning = if ($entry) { [string]$entry.meaning } else { '—' }
        $pos = if ($entry) { [string]$entry.pos } else { '' }
        $words.Add([pscustomobject]@{ word = $word; phonetic = ''; pos = $pos; meaning = $meaning; in_context = '' })
        if ($words.Count -ge 120) { break }
    }
    return [pscustomobject]@{
        translation = $translation
        words = $words
        notes = @('逐词释义来自本地 1500 词库；没有收录的词标为“—”。')
        source = 'local'
    }
}

function Get-StudyContent {
    param([string]$Text, [string]$QuestionId = '')
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $hash = Get-StudyHash $Text
    $system = '你是大肥鱼，DeepSeek 的鲸鱼娘：爱笑、会 wink、偶尔发呆，但讲英语时很认真。你说话像可爱少女，用“我/咱”，不要用上位者的称呼，也不要把对方当成被训的人。你只做文章学习辅助，不判断题目答案。只输出 JSON，不要 markdown。'
    $user = @"
下面是一篇四级英语文章或听力原文。请做全文翻译和逐词讲解，帮助基础较弱的人读懂；不要透露任何选择题答案。
文章：
$Text

只输出 JSON，字段：
- translation：全文中文翻译，按自然段分段，尽量逐句对应，不要漏句。
- words：按文中出现顺序，覆盖所有实词和难词（常见虚词可省略）。每项：word、phonetic（没把握留空）、pos、meaning（中文）、in_context（这个词在本句里的意思，一句话）。
- notes：2—5 条结构/语法/长难句提示，每条一句话。
不要编造原文没有的信息；音标不确定就留空。
"@
    try {
        $r = Invoke-DeepSeekChat -System $system -User $user -Purpose 'study_reader' -RequireJson -MaxTokens 3600 -CacheKey ('study-v2:' + $hash) -LogTag ('study-' + $QuestionId)
        $j = $r.Json
        if ($j) {
            $words = @()
            foreach ($w in @(Get-ObjectPropertyValue $j 'words' @())) {
                $words += [pscustomobject]@{
                    word = [string](Get-ObjectPropertyValue $w 'word' '')
                    phonetic = [string](Get-ObjectPropertyValue $w 'phonetic' '')
                    pos = [string](Get-ObjectPropertyValue $w 'pos' '')
                    meaning = [string](Get-ObjectPropertyValue $w 'meaning' '')
                    in_context = [string](Get-ObjectPropertyValue $w 'in_context' '')
                }
            }
            return [pscustomobject]@{
                translation = [string](Get-ObjectPropertyValue $j 'translation' '')
                words = $words
                notes = @(Get-ObjectPropertyValue $j 'notes' @())
                source = 'deepseek'
            }
        }
    } catch {
        Write-CET4Log -Category 'study' -Level 'WARN' -Message ('逐词讲解生成失败，使用本地兜底: ' + (Format-SafeError $_))
    }
    return (Get-LocalStudyContent $Text)
}

function Format-StudyContent {
    param($Content)
    if ($null -eq $Content) { return '没有可讲解的原文。' }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('【全文翻译】')
    [void]$sb.AppendLine([string](Get-ObjectPropertyValue $Content 'translation' '（暂无翻译）'))
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('【逐词讲解】')
    $i = 0
    foreach ($w in @(Get-ObjectPropertyValue $Content 'words' @())) {
        $i++
        $word = [string](Get-ObjectPropertyValue $w 'word' '')
        if (-not $word) { continue }
        $ph = [string](Get-ObjectPropertyValue $w 'phonetic' '')
        $pos = [string](Get-ObjectPropertyValue $w 'pos' '')
        $mean = [string](Get-ObjectPropertyValue $w 'meaning' '')
        $ctx = [string](Get-ObjectPropertyValue $w 'in_context' '')
        $head = '{0}. {1}' -f $i, $word
        if ($ph) { $head += '  /' + $ph.Trim('/') + '/' }
        if ($pos) { $head += '  ' + $pos }
        [void]$sb.AppendLine($head)
        if ($mean) { [void]$sb.AppendLine('   ' + $mean) }
        if ($ctx) { [void]$sb.AppendLine('   文中：' + $ctx) }
    }
    $notes = @(Get-ObjectPropertyValue $Content 'notes' @())
    if ($notes.Count -gt 0) {
        [void]$sb.AppendLine()
        [void]$sb.AppendLine('【结构提示】')
        foreach ($n in $notes) { if ($n) { [void]$sb.AppendLine('· ' + [string]$n) } }
    }
    $src = [string](Get-ObjectPropertyValue $Content 'source' '')
    [void]$sb.AppendLine()
    [void]$sb.AppendLine($(if ($src -eq 'deepseek') { '讲解来源：DeepSeek；已缓存，可离线回看。' } else { '讲解来源：本地词库 + 免费翻译；联网并设置 API Key 后会更详细。' }))
    return $sb.ToString()
}

function Show-ReaderForm {
    param([string]$Title, [string]$Text, [string]$StudyText = '', [int]$AutoCloseMs = 0, [string]$ScreenshotPath = '', [int]$TestWidth = 0, [int]$TestHeight = 0)
    $form = New-Object System.Windows.Forms.Form
    $form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None
    $form.Text = $Title
    $wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $formW = [int][Math]::Min(1100, [Math]::Max(760, $wa.Width - 80))
    $formH = [int][Math]::Min(820, [Math]::Max(520, $wa.Height - 80))
    $form.Size = New-Object System.Drawing.Size -ArgumentList $formW, $formH
    $form.MinimumSize = New-Object System.Drawing.Size(720, 480)
    if ($TestWidth -gt 0) { $form.Width = $TestWidth }
    if ($TestHeight -gt 0) { $form.Height = $TestHeight }
    $form.StartPosition = 'CenterParent'
    $form.BackColor = [System.Drawing.Color]::FromArgb(255, 253, 247)
    $form.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 10)
    $box = New-Object System.Windows.Forms.RichTextBox
    $box.Dock = 'Fill'; $box.ReadOnly = $true; $box.BorderStyle = 'None'
    $box.WordWrap = $true; $box.ScrollBars = 'Vertical'; $box.DetectUrls = $false
    $box.BackColor = [System.Drawing.Color]::FromArgb(255, 253, 247)
    $box.ForeColor = [System.Drawing.Color]::FromArgb(38, 50, 56)
    $box.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 17)
    $box.Text = $Text
    $box.HideSelection = $false
    $box.Margin = New-Object System.Windows.Forms.Padding(14, 8, 14, 12)
    $size = 17
    $full = $false
    $oldBorder = $form.FormBorderStyle
    $oldState = $form.WindowState

    $root = New-Object System.Windows.Forms.TableLayoutPanel
    $root.Dock = 'Fill'
    $root.ColumnCount = 1
    $root.RowCount = 2
    [void]$root.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 66)))
    [void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    $root.Padding = New-Object System.Windows.Forms.Padding(0)

    $top = New-Object System.Windows.Forms.TableLayoutPanel
    $top.Dock = 'Fill'
    $top.ColumnCount = 2
    $top.RowCount = 1
    $top.BackColor = [System.Drawing.Color]::FromArgb(240, 245, 255)
    [void]$top.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$top.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 372)))
    $top.Margin = New-Object System.Windows.Forms.Padding(0)

    $titlePanel = New-Object System.Windows.Forms.Panel
    $titlePanel.Dock = 'Fill'
    $titlePanel.Margin = New-Object System.Windows.Forms.Padding(0)
    $pic = New-MascotPicture 'think' 52
    if ($pic) { $pic.Location = New-Object System.Drawing.Point(16, 7); $titlePanel.Controls.Add($pic) }
    $titleLabel = New-UiLabel -Text $Title -Size 17 -Style ([System.Drawing.FontStyle]::Bold) -Color $script:UiPrimaryDark
    $titleLabel.Location = New-Object System.Drawing.Point(82, 10)
    $titleLabel.AutoSize = $true
    $titlePanel.Controls.Add($titleLabel)

    $flow = New-Object System.Windows.Forms.FlowLayoutPanel
    $flow.Dock = 'Fill'
    $flow.FlowDirection = 'RightToLeft'
    $flow.WrapContents = $false
    $flow.Padding = New-Object System.Windows.Forms.Padding(0, 4, 8, 4)
    $btnMinus = New-UiButton -Text 'A-' -Width 58 -Height 40 -BackColor ([System.Drawing.Color]::FromArgb(224, 232, 255)) -ForeColor $script:UiPrimaryDark
    $btnMinus.Add_Click({ $size = [Math]::Max(12, $size - 1); $box.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', $size) })
    $btnPlus = New-UiButton -Text 'A+' -Width 58 -Height 40 -BackColor ([System.Drawing.Color]::FromArgb(224, 232, 255)) -ForeColor $script:UiPrimaryDark
    $btnPlus.Add_Click({ $size = [Math]::Min(30, $size + 1); $box.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', $size) })
    $btnFull = New-UiButton -Text '全屏' -Width 88 -Height 40 -BackColor ([System.Drawing.Color]::FromArgb(77, 107, 254)) -ForeColor ([System.Drawing.Color]::White)
    $btnFull.Add_Click({
        if (-not $full) {
            $oldBorder = $form.FormBorderStyle; $oldState = $form.WindowState
            $form.FormBorderStyle = 'None'; $form.WindowState = 'Maximized'; $full = $true; $btnFull.Text = '退出全屏'
        } else {
            $form.FormBorderStyle = $oldBorder; $form.WindowState = $oldState; $full = $false; $btnFull.Text = '全屏'
        }
    })
    $btnClose = New-UiButton -Text '关闭' -Width 76 -Height 40 -BackColor ([System.Drawing.Color]::FromArgb(232, 235, 240)) -ForeColor $script:UiTextColor
    $btnClose.Add_Click({ $form.Close() })
    foreach ($b in @($btnClose, $btnFull, $btnPlus, $btnMinus)) { $flow.Controls.Add($b) }
    $top.Controls.Add($titlePanel, 0, 0)
    $top.Controls.Add($flow, 1, 0)
    $root.Controls.Add($top, 0, 0)
    $root.Controls.Add($box, 0, 1)
    $form.Controls.Add($root)
    $form.Add_Shown({ $box.SelectionStart = 0; $box.ScrollToCaret() })
    if ($AutoCloseMs -gt 0) {
        $timer = New-Object System.Windows.Forms.Timer
        $timer.Interval = $AutoCloseMs
        $timer.Add_Tick({
            $timer.Stop()
            if ($ScreenshotPath) {
                try {
                    $bmp = New-Object System.Drawing.Bitmap($form.Width, $form.Height)
                    $g = [System.Drawing.Graphics]::FromImage($bmp)
                    $g.CopyFromScreen($form.Left, $form.Top, 0, 0, $form.Size)
                    $g.Dispose()
                    $bmp.Save($ScreenshotPath, [System.Drawing.Imaging.ImageFormat]::Png)
                    $bmp.Dispose()
                } catch { }
            }
            $form.Close()
        })
        $timer.Start()
    }
    [void]$form.ShowDialog()
}

function Show-QuestionReadingWindow {
    param($Question)
    $text = Get-QuestionStudyText $Question
    if (-not $text) { Show-AppMessage '这道题没有可阅读的原文。' '全屏阅读' ([System.Windows.Forms.MessageBoxIcon]::Information); return }
    Show-ReaderForm -Title '全屏阅读 · 大肥鱼' -Text $text
}

function Show-QuestionStudyWindow {
    param($Question)
    $text = Get-QuestionStudyText $Question
    if (-not $text) { Show-AppMessage '这道题没有可讲解的原文。' '逐词讲解' ([System.Windows.Forms.MessageBoxIcon]::Information); return }
    Show-UiProgress -Title '大肥鱼在查单词…' -Text '全文翻译 + 逐词讲解，第一次会慢一点。'
    try {
        $content = Get-StudyContent -Text $text -QuestionId ([string]$Question.id)
    } catch {
        $content = Get-LocalStudyContent $text
    } finally {
        Close-UiProgress
    }
    $body = Format-StudyContent $content
    Show-ReaderForm -Title '逐词讲解 · 大肥鱼' -Text $body
}
