function Get-QuizSessionAnsweredCount {
    param($Session)
    return @(Get-ObjectPropertyValue $Session 'results' @() | Where-Object { [bool](Get-ObjectPropertyValue $_ 'answered' $false) }).Count
}

function Get-QuizScoreSummary {
    param($Session)
    $results = @(Get-ObjectPropertyValue $Session 'results' @())
    $answered = @($results | Where-Object { [bool](Get-ObjectPropertyValue $_ 'answered' $false) })
    $correct = @($answered | Where-Object { [bool](Get-ObjectPropertyValue $_ 'correct' $false) }).Count
    $wrong = $answered.Count - $correct
    $incomplete = @($results | Where-Object { -not [bool](Get-ObjectPropertyValue $_ 'answered' $false) }).Count
    return [pscustomobject]@{
        Total = $results.Count
        Answered = $answered.Count
        Correct = $correct
        Wrong = $wrong
        Incomplete = $incomplete
        Accuracy = if ($answered.Count -gt 0) { [int][Math]::Round(100.0 * $correct / $answered.Count) } else { 0 }
    }
}

function Invoke-QuizEvaluation {
    param($Question, [string]$Selected, [string]$Reason, [int]$ReplayCount, [bool]$LocalCorrect)
    $opts = Format-QuestionOptionsForPrompt $Question.options
    $material = Get-QuizMaterial $Question
    $context = ''
    if ($material) {
        $context = [string](Get-ObjectPropertyValue $material 'text' '')
        if (-not $context) { $context = [string](Get-ObjectPropertyValue $material 'transcript' '') }
        if ($context.Length -gt 900) { $context = $context.Substring(0, 900) }
    }
    $system = '你是大学英语四级老师，评价学生的选择题作答和一句话理由。只输出 JSON，不要 markdown。JSON 字段：correct（布尔，必须与标准答案判断一致）、reason_quality（好/一般/较差）、error_type（定位错/同义替换没认出/蒙对/没找到位置/没听到信号词/时间不够/无）、encouragement（不超过 20 字的中文鼓励）。回答要短、直白。'
    $user = @"
题型：$(Get-TypeDisplayName $Question.type)
题干：$($Question.stem)
选项：
$opts
标准答案：$($Question.answer)
学生选择：$Selected
学生理由：$Reason
回放次数：$ReplayCount
材料片段（仅供判断定位）：$context
"@
    try {
        $r = Invoke-DeepSeekChat -System $system -User $user -Purpose 'quiz_evaluation' -RequireJson -MaxTokens 260 -CacheParts $null -LogTag ('eval-' + $Question.id)
        $j = $r.Json
        if ($null -eq $j) { throw '没有解析出评估 JSON。' }
        $enc = [string](Get-ObjectPropertyValue $j 'encouragement' '')
        if ($enc.Length -gt 20) { $enc = $enc.Substring(0, 20) }
        return [pscustomobject]@{
            correct = $LocalCorrect
            reason_quality = [string](Get-ObjectPropertyValue $j 'reason_quality' '一般')
            error_type = [string](Get-ObjectPropertyValue $j 'error_type' '无')
            encouragement = $enc
            source = 'deepseek'
        }
    } catch {
        Write-CET4Log -Category 'quiz' -Level 'WARN' -Message ('作答评估失败，用本地判断: ' + (Format-SafeError $_))
        return [pscustomobject]@{
            correct = $LocalCorrect
            reason_quality = if ($LocalCorrect -and $Reason.Length -ge 6) { '一般（本地）' } else { '未评估' }
            error_type = if ($LocalCorrect) { '无' } elseif ($Reason.Length -lt 4) { '没找到位置' } else { '待复盘' }
            encouragement = if ($LocalCorrect) { '先稳住，再提速。' } else { '这题先记动作，不记答案。' }
            source = 'local'
        }
    }
}

function Get-QuizTeacherFeedback {
    param($Question, [string]$Selected, [string]$UserReason, [int]$ReplayCount, [bool]$Correct)
    $technique = Get-TechniqueForType $Question.type
    $techText = if ($technique) { [string]$technique.action } else { '先读题干，再回原文/录音定位，找同义替换。' }
    if ($Correct) {
        $local = Get-LocalTeacherFeedback $Question $Selected $false
        $local.technique = $techText
        return $local
    }
    $cacheKey = 'quiz-explanation:{0}:{1}:v1' -f $Question.id, $Selected
    if (Test-DeepSeekKeyPresent) {
        try {
            $material = Get-QuizMaterial $Question
            $passage = ''
            if ($material) { $passage = [string](Get-ObjectPropertyValue $material 'text' ''); if (-not $passage) { $passage = [string](Get-ObjectPropertyValue $material 'transcript' '') } }
            if ($passage.Length -gt 2600) { $passage = $passage.Substring(0, 2600) }
            $analysis = [string]$Question.explanation
            if ($analysis.Length -gt 2200) { $analysis = $analysis.Substring(0, 2200) }
            $system = '你是耐心、浅显的大学英语四级老师。讲解错题，不要用「语义场」「图式理论」等术语。只输出 JSON，不要 markdown。JSON 字段：exam_point（这道题考什么，一句话）、why_correct（正确答案为什么对，指出原文/听力信号词位置）、why_wrong（学生选项为什么是陷阱）、next_action（下次遇到同类题的动作，一句话）、technique（一条技巧，直接写动作）。'
            $user = @"
题型：$(Get-TypeDisplayName $Question.type)
题干：$($Question.stem)
选项：
$(Format-QuestionOptionsForPrompt $Question.options)
正确答案：$($Question.answer)
学生选择：$Selected
学生理由：$UserReason
回放次数：$ReplayCount
原文/材料片段：$passage
题库参考解析：$analysis
"@
            $r = Invoke-DeepSeekChat -System $system -User $user -Purpose 'quiz_explanation' -RequireJson -CacheKey $cacheKey -MaxTokens 700 -LogTag ('exp-' + $Question.id)
            $j = $r.Json
            if ($null -ne $j) {
                return [pscustomobject]@{
                    exam_point = [string](Get-ObjectPropertyValue $j 'exam_point' '这题考定位和同义替换。')
                    why_correct = [string](Get-ObjectPropertyValue $j 'why_correct' '')
                    why_wrong = [string](Get-ObjectPropertyValue $j 'why_wrong' '')
                    next_action = [string](Get-ObjectPropertyValue $j 'next_action' $techText)
                    technique = [string](Get-ObjectPropertyValue $j 'technique' $techText)
                    source = if ($r.Cached) { 'deepseek-cache' } else { 'deepseek' }
                }
            }
        } catch {
            Write-CET4Log -Category 'quiz' -Level 'WARN' -Message ('讲解生成失败，用本地解析: ' + (Format-SafeError $_))
        }
    }
    $local = Get-LocalTeacherFeedback $Question $Selected $true
    $local.technique = $techText
    return $local
}

function Get-LocalTeacherFeedback {
    param($Question, [string]$Selected, [bool]$Wrong)
    $analysis = [string]$Question.explanation
    if ($analysis.Length -gt 1400) { $analysis = $analysis.Substring(0, 1400) + '…' }
    $optionText = ''
    foreach ($o in @($Question.options)) {
        if ([string](Get-ObjectPropertyValue $o 'key' '') -eq $Selected) { $optionText = [string](Get-ObjectPropertyValue $o 'text' '') }
    }
    $exam = switch -Wildcard ($Question.type) {
        'careful_reading' { '这题考「回原文定位 + 识别同义替换」，不是考你背了多少生词。' }
        'listening_*' { '这题考「预读选项 + 抓信号词后的关键信息」。' }
        'matching' { '这题考「关键词定位」，不需要逐字读完整段。' }
        'cloze' { '这题考「词性 + 上下文搭配」，先排除词性不对的词。' }
        default { '这题考定位和同义替换。' }
    }
    $whyWrong = if ($Wrong) { "你选的是 $Selected)。$optionText 这个选项看起来像原文，但和题目问的不是同一件事。先回定位句，圈出主语和转折词。" } else { '' }
    return [pscustomobject]@{
        exam_point = $exam
        why_correct = if ($analysis) { $analysis } else { '正确答案对应原文/录音中的定位句；先找同义替换，再对照选项。' }
        why_wrong = $whyWrong
        next_action = '下次先读题干圈关键词，再回原文/录音找同义替换。'
        technique = Get-TechniqueText $Question.type
        source = 'local'
    }
}

function Get-FeedbackText {
    param($Feedback)
    if ($null -eq $Feedback) { return '' }
    $lines = @()
    if (Get-ObjectPropertyValue $Feedback 'exam_point' '') { $lines += ('这道题考什么：' + [string](Get-ObjectPropertyValue $Feedback 'exam_point' '')) }
    if (Get-ObjectPropertyValue $Feedback 'why_correct' '') { $lines += ('正确答案为什么对：' + [string](Get-ObjectPropertyValue $Feedback 'why_correct' '')) }
    if (Get-ObjectPropertyValue $Feedback 'why_wrong' '') { $lines += ('你选的为什么是陷阱：' + [string](Get-ObjectPropertyValue $Feedback 'why_wrong' '')) }
    if (Get-ObjectPropertyValue $Feedback 'next_action' '') { $lines += ('下次动作：' + [string](Get-ObjectPropertyValue $Feedback 'next_action' '')) }
    if (Get-ObjectPropertyValue $Feedback 'technique' '') { $lines += ('技巧：' + [string](Get-ObjectPropertyValue $Feedback 'technique' '')) }
    return ($lines -join "`n`n")
}

function Add-ResultToSession {
    param($Session, $Question, [string]$Selected, [string]$Reason, [int]$ReplayCount, [bool]$Correct, $Evaluation, $Feedback)
    $results = @(Get-ObjectPropertyValue $Session 'results' @())
    $results = @($results | Where-Object { [string](Get-ObjectPropertyValue $_ 'questionId' '') -ne [string]$Question.id })
    $results += [ordered]@{
        questionId = $Question.id
        type = $Question.type
        selected = $Selected
        answer = $Question.answer
        reason = $Reason
        replayCount = $ReplayCount
        correct = $Correct
        answered = $true
        errorType = [string](Get-ObjectPropertyValue $Evaluation 'error_type' '')
        reasonQuality = [string](Get-ObjectPropertyValue $Evaluation 'reason_quality' '')
        feedbackSource = [string](Get-ObjectPropertyValue $Feedback 'source' '')
    }
    Set-ObjectPropertyValue $Session 'results' $results
}

function Start-QuizPage {
    $plan = $null
    $session = Get-ExistingQuizSession
    if ($null -eq $session) {
        $completedPath = Get-QuizSessionPath
        if (Test-Path -LiteralPath $completedPath) {
            $old = Read-JsonFile $completedPath $null -Quiet
            if ($old -and [bool](Get-ObjectPropertyValue $old 'completed' $false)) {
                Show-AppMessage '今天这一轮 20 题已经完成了。可以看打卡月历，或者明天再来。' '今天已完成'
                return
            }
        }
        $plan = Get-OrCreateDailyQuizPlan
        $session = New-QuizSession -Plan $plan
    } else {
        $plan = Get-OrCreateDailyQuizPlan
    }
    if ($null -eq $plan) { $plan = Get-OrCreateDailyQuizPlan }
    # Rebuild plan questions from the current bank, keeping the session's order.
    $sessionIds = @(Get-ObjectPropertyValue $session 'questionIds' @())
    $bank = @(Get-QuestionBank)
    $questions = @()
    foreach ($id in $sessionIds) {
        $q = @($bank | Where-Object { $_.id -eq $id })[0]
        if ($q) { $questions += $q }
    }
    if ($questions.Count -eq 0) {
        Show-AppMessage '今天的题目找不到，可能题库被换过。请重新生成计划或导入题库。' '题库问题' ([System.Windows.Forms.MessageBoxIcon]::Warning)
        return
    }
    $needed = @()
    foreach ($q in $questions) { if ($q.audio) { $needed += [pscustomobject]@{ suite = $q.audio.suite; section = $q.audio.section; audio_id = $q.audio.audio_id } } }
    if ($needed.Count -gt 0) {
        $dir = Get-ListeningTempDir
        $manifestPath = Join-Path $dir 'manifest.json'
        if (-not (Test-Path -LiteralPath $manifestPath)) {
            try {
                Show-UiProgress -Title '准备听力' -Text '正在把今天要用的听力复制到临时工作区…'
                Initialize-ListeningTempWorkspace -NeededAudio @($needed | Sort-Object suite, section -Unique) | Out-Null
                Set-ObjectPropertyValue $session 'tempPrepared' $true
            } catch {
                Write-CET4Log -Category 'listening' -Level 'WARN' -Message (Format-SafeError $_)
            } finally { Close-UiProgress }
        }
    }

    Clear-ContentPanel
    $head = New-PageHeader '20 题 · 30 分钟' '先选答案，再用一句话说理由；错题会像老师一样拆开讲。'
    $script:ContentPanel.Controls.Add($head)
    $status = New-UiCard -Width 960 -Height 78
    $status.Location = New-Object System.Drawing.Point(0, 100)
    $script:ContentPanel.Controls.Add($status)
    $timer = New-UiLabel -Text '30:00' -Size 22 -Style ([System.Drawing.FontStyle]::Bold) -Color $script:UiPrimaryDark
    $timer.Location = New-Object System.Drawing.Point(18, 15)
    $status.Controls.Add($timer)
    $progress = New-UiLabel -Text '' -Size 15 -Color $script:UiMutedColor
    $progress.Location = New-Object System.Drawing.Point(200, 24)
    $status.Controls.Add($progress)
    $focus = New-UiLabel -Text ("重点题 {0}/20 · 主攻 {1}" -f [int](Get-ObjectPropertyValue $plan 'focus_count' 0), (Get-TypeDisplayName ([string](Get-ObjectPropertyValue $plan 'main_type' '')))) -Size 13 -Color $script:UiMutedColor
    $focus.Location = New-Object System.Drawing.Point(650, 26)
    $status.Controls.Add($focus)
    $card = New-UiCard -Width 960 -Height 680
    $card.Location = New-Object System.Drawing.Point(0, 190)
    $script:ContentPanel.Controls.Add($card)
    $exit = New-UiButton -Text '保存并退出' -Width 160 -BackColor ([System.Drawing.Color]::FromArgb(210, 205, 192)) -ForeColor $script:UiTextColor -OnClick {
        $s = $script:QuizUi.Session
        Save-QuizSession $s
        try { Clear-ListeningTempWorkspace -Silent | Out-Null; Set-ObjectPropertyValue $s 'tempPrepared' $false; Save-QuizSession $s } catch { }
        Stop-PageTimer
        Show-HomePage
    }
    $exit.Location = New-Object System.Drawing.Point(780, 0)
    $head.Controls.Add($exit)

    $script:QuizUi = [pscustomobject]@{
        Session = $session; Plan = $plan; Questions = $questions; Card = $card;
        TimerLabel = $timer; ProgressLabel = $progress; ReminderLabel = $null;
        OptionControls = $null; ReasonBox = $null; EndsAt = $null; ShownFeedback = $false;
    }
    $script:OnLeavePage = {
        if ($script:QuizUi -and $script:QuizUi.Session) {
            $s = $script:QuizUi.Session
            if (-not [bool](Get-ObjectPropertyValue $s 'completed' $false)) {
                Save-QuizSession $s
                try { Clear-ListeningTempWorkspace -Silent | Out-Null; Set-ObjectPropertyValue $s 'tempPrepared' $false; Save-QuizSession $s } catch { }
            }
        }
    }
    $minutes = [int](Get-ConfigValue 'quiz.minutes' 30)
    try { $script:QuizUi.EndsAt = [datetime]::Parse([string](Get-ObjectPropertyValue $session 'endsAt' (Get-Date).AddMinutes($minutes).ToString('o'))) } catch { $script:QuizUi.EndsAt = (Get-Date).AddMinutes($minutes) }
    $tick = {
        if (-not $script:QuizUi -or $null -eq $script:QuizUi.Session) { return }
        $s = $script:QuizUi.Session
        $remaining = [int][Math]::Max(0, [Math]::Floor(($script:QuizUi.EndsAt - (Get-Date)).TotalSeconds))
        $script:QuizUi.TimerLabel.Text = ('{0:D2}:{1:D2}' -f [int][Math]::Floor($remaining / 60), [int]($remaining % 60))
        $idx = [int](Get-ObjectPropertyValue $s 'index' 0)
        $script:QuizUi.ProgressLabel.Text = ('第 {0}/{1} 题 · 已答 {2}' -f ([Math]::Min($idx + 1, $script:QuizUi.Questions.Count)), $script:QuizUi.Questions.Count, (Get-QuizSessionAnsweredCount $s))
        $cur = Get-ObjectPropertyValue $s 'current' $null
        if ($cur -and -not [bool](Get-ObjectPropertyValue $cur 'submitted' $false) -and -not [bool](Get-ObjectPropertyValue $cur 'reminded' $false)) {
            $started = [string](Get-ObjectPropertyValue $cur 'startedAt' '')
            if ($started) {
                try {
                    $elapsed = ((Get-Date) - [datetime]::Parse($started)).TotalSeconds
                    $q = $script:QuizUi.Questions[$idx]
                    $limit = if ($q.type -like 'listening*') { [int](Get-ConfigValue 'quiz.listeningReminderSec' 120) } else { [int](Get-ConfigValue 'quiz.readingReminderSec' 180) }
                    if ($elapsed -gt $limit) {
                        Set-ObjectPropertyValue $cur 'reminded' $true
                        Save-QuizSession $s
                        if ($script:QuizUi.ReminderLabel -and -not $script:QuizUi.ReminderLabel.IsDisposed) {
                            $script:QuizUi.ReminderLabel.Text = '这道题花的时间有点长了，先选一个，后面看讲解。'
                            $script:QuizUi.ReminderLabel.Visible = $true
                        }
                        Set-StatusBar '这道题花的时间有点长了，先选一个，后面看讲解。' $script:UiAccent
                    }
                } catch { }
            }
        }
        if ($remaining -le 0) {
            Stop-PageTimer
            Complete-QuizRound -TimeExpired
        }
    }
    Set-PageTimer -IntervalMs 1000 -OnTick $tick | Out-Null
    & $tick
    if ((Get-Date) -ge $script:QuizUi.EndsAt) {
        Complete-QuizRound -TimeExpired
        return
    }
    Show-QuizQuestion
}

function Get-SelectedQuizOption {
    $ctrl = $script:QuizUi.OptionControls
    if ($null -eq $ctrl) { return '' }
    if ($ctrl -is [System.Windows.Forms.ComboBox]) {
        if ($ctrl.SelectedIndex -lt 0) { return '' }
        $txt = [string]$ctrl.SelectedItem
        $m = [regex]::Match($txt, '^([A-O])\)')
        if ($m.Success) { return $m.Groups[1].Value }
        return ''
    }
    foreach ($rb in @($ctrl.Controls)) {
        if ($rb -is [System.Windows.Forms.RadioButton] -and $rb.Checked) { return [string]$rb.Tag }
    }
    return ''
}

function Show-QuizQuestion {
    $ui = $script:QuizUi
    $s = $ui.Session
    $idx = [int](Get-ObjectPropertyValue $s 'index' 0)
    if ($idx -ge $ui.Questions.Count) { Complete-QuizRound; return }
    $q = $ui.Questions[$idx]
    $cur = Get-ObjectPropertyValue $s 'current' $null
    if ($null -eq $cur -or [string](Get-ObjectPropertyValue $cur 'questionId' '') -ne [string]$q.id) {
        $cur = [ordered]@{
            questionId = $q.id; selected = ''; reason = ''; replayCount = 0;
            startedAt = (Get-Date).ToString('o'); submitted = $false; optionsShown = ($q.type -notlike 'listening*');
            reminded = $false; evaluation = $null; feedback = $null;
        }
        Set-ObjectPropertyValue $s 'current' $cur
        Set-ObjectPropertyValue $s 'index' $idx
        Save-QuizSession $s
    }
    if ([bool](Get-ObjectPropertyValue $cur 'submitted' $false)) {
        Show-QuizFeedback
        return
    }
    $ui.Card.Controls.Clear()
    $ui.ShownFeedback = $false
    $title = New-UiLabel -Text ("第 {0} 题 · {1} · {2} 分" -f ($idx + 1), (Get-TypeDisplayName $q.type), $q.point) -Size 18 -Style ([System.Drawing.FontStyle]::Bold) -Color $script:UiPrimaryDark
    $title.Location = New-Object System.Drawing.Point(20, 14)
    $ui.Card.Controls.Add($title)
    $source = New-UiLabel -Text ("{0} 年 {1} 月 · {2}" -f $q.year, $q.month, (Get-TypeDisplayName $q.type)) -Size 12 -Color $script:UiMutedColor
    $source.Location = New-Object System.Drawing.Point(700, 20)
    $ui.Card.Controls.Add($source)
    $y = 48
    $mat = Get-QuizMaterial $q
    if ($q.type -notlike 'listening*' -and $mat) {
        $passage = [string](Get-ObjectPropertyValue $mat 'text' '')
        if ($passage.Length -gt 0) {
            $pb = New-Object System.Windows.Forms.RichTextBox
            $pb.Location = New-Object System.Drawing.Point(20, $y)
            $pb.Width = 910; $pb.Height = 130
            $pb.ReadOnly = $true; $pb.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
            $pb.BackColor = [System.Drawing.Color]::FromArgb(252, 250, 244)
            $pb.Font = New-Object System.Drawing.Font($script:UiFontName, 14)
            $pb.Text = $passage
            $ui.Card.Controls.Add($pb)
            $y += 140
        }
    }
    if ($q.type -like 'listening*') {
        $info = New-UiLabel -Text '先播放听力，听完再显示选项。播放次数会被记录下来，供老师评估参考。' -Size 15 -Color $script:UiMutedColor -MaxWidth 900
        $info.Location = New-Object System.Drawing.Point(20, $y)
        $ui.Card.Controls.Add($info)
        $y += 38
        $play = New-UiButton -Text '播放听力' -Width 180 -Height 46 -OnClick {
            $s = $script:QuizUi.Session
            $cur = Get-ObjectPropertyValue $s 'current' $null
            $q = $script:QuizUi.Questions[[int](Get-ObjectPropertyValue $s 'index' 0)]
            $path = Get-QuizAudioPath $q
            if (-not $path) {
                Show-AppMessage '这道题缺少音频。按规则应标记「缺音频」并跳过；请补充 library/audio 后再来。' '缺音频' ([System.Windows.Forms.MessageBoxIcon]::Warning)
                return
            }
            try {
                Start-ListeningPlayback -Path $path | Out-Null
                $cur.replayCount = [int](Get-ObjectPropertyValue $cur 'replayCount' 0) + 1
                Set-ObjectPropertyValue $cur 'replayCount' $cur.replayCount
                Set-ObjectPropertyValue $s 'current' $cur
                Save-QuizSession $s
                $script:QuizUi.PlayCountLabel.Text = ('已播放 {0} 次' -f $cur.replayCount)
                Set-StatusBar ('已调用 PotPlayer 播放；本次是第 {0} 次回放。' -f $cur.replayCount)
            } catch {
                Show-AppMessage ('播放失败：' + (Format-SafeError $_)) '播放' ([System.Windows.Forms.MessageBoxIcon]::Warning)
            }
        }
        $play.Location = New-Object System.Drawing.Point(20, $y)
        $ui.Card.Controls.Add($play)
        $script:QuizUi.PlayCountLabel = New-UiLabel -Text ('已播放 {0} 次' -f [int](Get-ObjectPropertyValue $cur 'replayCount' 0)) -Size 14 -Color $script:UiMutedColor
        $script:QuizUi.PlayCountLabel.Location = New-Object System.Drawing.Point(220, $y + 12)
        $ui.Card.Controls.Add($script:QuizUi.PlayCountLabel)
        $showOpts = New-UiButton -Text '我已听完，显示选项' -Width 220 -Height 46 -BackColor $script:UiAccent -OnClick {
            $s = $script:QuizUi.Session
            $cur = Get-ObjectPropertyValue $s 'current' $null
            Set-ObjectPropertyValue $cur 'optionsShown' $true
            Set-ObjectPropertyValue $s 'current' $cur
            Save-QuizSession $s
            Show-QuizQuestion
        }
        $showOpts.Location = New-Object System.Drawing.Point(430, $y)
        $ui.Card.Controls.Add($showOpts)
        $y += 58
        if (-not [bool](Get-ObjectPropertyValue $cur 'optionsShown' $false)) {
            $hint = New-UiLabel -Text '选项暂时隐藏。听力原文不会提前显示。' -Size 14 -Color $script:UiMutedColor
            $hint.Location = New-Object System.Drawing.Point(20, $y)
            $ui.Card.Controls.Add($hint)
            $ui.OptionControls = $null
            $ui.ReasonBox = $null
            return
        }
    }
    $stemLabel = New-UiLabel -Text ([string]$q.stem) -Size 16 -Style ([System.Drawing.FontStyle]::Bold) -Color $script:UiTextColor -MaxWidth 900
    $stemLabel.Location = New-Object System.Drawing.Point(20, $y)
    $ui.Card.Controls.Add($stemLabel)
    $y += [Math]::Max(36, $stemLabel.PreferredHeight + 10)
    $opts = @($q.options)
    if ($opts.Count -le 4) {
        $flow = New-Object System.Windows.Forms.FlowLayoutPanel
        $flow.Location = New-Object System.Drawing.Point(20, $y)
        $flow.Width = 910; $flow.Height = 155
        $flow.FlowDirection = [System.Windows.Forms.FlowDirection]::TopDown
        $flow.WrapContents = $false
        $flow.AutoScroll = $true
        foreach ($o in $opts) {
            $rb = New-Object System.Windows.Forms.RadioButton
            $rb.Text = ('{0}) {1}' -f (Get-ObjectPropertyValue $o 'key' ''), (Get-ObjectPropertyValue $o 'text' ''))
            $rb.Tag = [string](Get-ObjectPropertyValue $o 'key' '')
            $rb.Font = New-Object System.Drawing.Font($script:UiFontName, 15)
            $rb.AutoSize = $true
            $rb.MaximumSize = New-Object System.Drawing.Size(880, 0)
            $rb.Margin = New-Object System.Windows.Forms.Padding(0, 4, 0, 4)
            $flow.Controls.Add($rb)
        }
        $ui.Card.Controls.Add($flow)
        $ui.OptionControls = $flow
        $y += 164
    } else {
        $combo = New-Object System.Windows.Forms.ComboBox
        $combo.Location = New-Object System.Drawing.Point(20, $y)
        $combo.Width = 910
        $combo.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
        $combo.Font = New-Object System.Drawing.Font($script:UiFontName, 15)
        foreach ($o in $opts) {
            $label = ('{0}) {1}' -f (Get-ObjectPropertyValue $o 'key' ''), (Get-ObjectPropertyValue $o 'text' ''))
            if ($label.Length -gt 120) { $label = $label.Substring(0, 120) + '…' }
            [void]$combo.Items.Add($label)
        }
        $combo.SelectedIndex = -1
        $ui.Card.Controls.Add($combo)
        $ui.OptionControls = $combo
        $y += 48
    }
    $reasonLabel = New-UiLabel -Text '用一句话说理由，例如「我选 B，因为原文 however 后面说……」。' -Size 14 -Color $script:UiMutedColor -MaxWidth 900
    $reasonLabel.Location = New-Object System.Drawing.Point(20, $y)
    $ui.Card.Controls.Add($reasonLabel)
    $y += 30
    $reasonBox = New-Object System.Windows.Forms.TextBox
    $reasonBox.Location = New-Object System.Drawing.Point(20, $y)
    $reasonBox.Width = 910; $reasonBox.Height = 52; $reasonBox.Multiline = $true
    $reasonBox.Font = New-Object System.Drawing.Font($script:UiFontName, 15)
    $reasonBox.Text = [string](Get-ObjectPropertyValue $cur 'reason' '')
    $ui.Card.Controls.Add($reasonBox)
    $ui.ReasonBox = $reasonBox
    $reminder = New-UiLabel -Text '' -Size 14 -Color $script:UiAccent -MaxWidth 900
    $reminder.Location = New-Object System.Drawing.Point(20, ($y + 66))
    $reminder.Visible = $false
    $ui.Card.Controls.Add($reminder)
    $ui.ReminderLabel = $reminder
    $submit = New-UiButton -Text '提交答案和理由' -Width 230 -OnClick {
        $s = $script:QuizUi.Session
        $cur = Get-ObjectPropertyValue $s 'current' $null
        $q = $script:QuizUi.Questions[[int](Get-ObjectPropertyValue $s 'index' 0)]
        $selected = Get-SelectedQuizOption
        $reason = [string]$script:QuizUi.ReasonBox.Text.Trim()
        if (-not $selected) { Show-AppMessage '先选一个答案。不会也先选一个，后面看讲解。' '还没选答案'; return }
        if ([string]::IsNullOrWhiteSpace($reason) -or $reason.Length -lt 4) { Show-AppMessage '用一句话说说为什么选它，哪怕理由是「我听到 but 后面像答案」。' '还差一句理由'; return }
        Set-ObjectPropertyValue $cur 'selected' $selected
        Set-ObjectPropertyValue $cur 'reason' $reason
        Save-QuizSession $s
        $localCorrect = ($selected -eq [string]$q.answer)
        $replay = [int](Get-ObjectPropertyValue $cur 'replayCount' 0)
        Show-UiProgress -Title '老师正在看这道题' -Text '先判断对错，再准备讲解…'
        try {
            $evaluation = Invoke-QuizEvaluation -Question $q -Selected $selected -Reason $reason -ReplayCount $replay -LocalCorrect $localCorrect
            $feedback = Get-QuizTeacherFeedback -Question $q -Selected $selected -UserReason $reason -ReplayCount $replay -Correct $localCorrect
            if ($localCorrect) {
                $reasonQ = [string](Get-ObjectPropertyValue $evaluation 'reason_quality' '')
                $reasonOk = ($reasonQ -notin @('较差', '未评估', ''))
                Register-CorrectWrongBookAnswer -Question $q -ReasonOk $reasonOk
            } else {
                Add-QuestionToWrongBook -Question $q -UserAnswer $selected -UserReason $reason -ErrorType ([string](Get-ObjectPropertyValue $evaluation 'error_type' '')) -Explanation (Get-FeedbackText $feedback) -TeacherExplanation (Get-FeedbackText $feedback) -Technique (Get-TechniqueText $q.type)
            }
            Add-ResultToSession -Session $s -Question $q -Selected $selected -Reason $reason -ReplayCount $replay -Correct $localCorrect -Evaluation $evaluation -Feedback $feedback
            Set-ObjectPropertyValue $cur 'submitted' $true
            Set-ObjectPropertyValue $cur 'evaluation' $evaluation
            Set-ObjectPropertyValue $cur 'feedback' $feedback
            Set-ObjectPropertyValue $cur 'correct' $localCorrect
            Set-ObjectPropertyValue $cur 'feedbackAt' (Get-Date).ToString('o')
            Set-ObjectPropertyValue $s 'current' $cur
            Save-QuizSession $s
            Show-QuizFeedback
        } catch {
            Show-AppMessage ('评估失败：' + (Format-SafeError $_)) '这道题' ([System.Windows.Forms.MessageBoxIcon]::Warning)
        } finally { Close-UiProgress }
    }
    $submit.Location = New-Object System.Drawing.Point(20, ($y + 72))
    $ui.Card.Controls.Add($submit)
    $skip = New-UiButton -Text '先跳过（记入待复习）' -Width 220 -BackColor ([System.Drawing.Color]::FromArgb(210, 205, 192)) -ForeColor $script:UiTextColor -OnClick {
        $s = $script:QuizUi.Session
        $cur = Get-ObjectPropertyValue $s 'current' $null
        $q = $script:QuizUi.Questions[[int](Get-ObjectPropertyValue $s 'index' 0)]
        Add-QuestionToWrongBook -Question $q -UserAnswer '' -UserReason '主动跳过' -ErrorType '时间不够' -Explanation '' -TeacherExplanation '这题先跳过，已进入待复习队列。' -Technique (Get-TechniqueText $q.type) -Incomplete
        $results = @(Get-ObjectPropertyValue $s 'results' @())
        $results += [ordered]@{ questionId = $q.id; type = $q.type; selected = ''; answer = $q.answer; reason = '主动跳过'; replayCount = [int](Get-ObjectPropertyValue $cur 'replayCount' 0); correct = $false; answered = $false; errorType = '时间不够'; reasonQuality = ''; feedbackSource = '' }
        Set-ObjectPropertyValue $s 'results' $results
        Set-ObjectPropertyValue $s 'current' $null
        Set-ObjectPropertyValue $s 'index' ([int](Get-ObjectPropertyValue $s 'index' 0) + 1)
        Save-QuizSession $s
        if ([int](Get-ObjectPropertyValue $s 'index' 0) -ge $script:QuizUi.Questions.Count) { Complete-QuizRound } else { Show-QuizQuestion }
    }
    $skip.Location = New-Object System.Drawing.Point(270, ($y + 72))
    $ui.Card.Controls.Add($skip)
}

function Show-QuizFeedback {
    $ui = $script:QuizUi
    $s = $ui.Session
    $idx = [int](Get-ObjectPropertyValue $s 'index' 0)
    $q = $ui.Questions[$idx]
    $cur = Get-ObjectPropertyValue $s 'current' $null
    $ev = Get-ObjectPropertyValue $cur 'evaluation' $null
    $fb = Get-ObjectPropertyValue $cur 'feedback' $null
    $correct = [bool](Get-ObjectPropertyValue $cur 'correct' $false)
    $ui.Card.Controls.Clear()
    $ui.ShownFeedback = $true
    $bannerColor = if ($correct) { $script:UiGood } else { $script:UiDanger }
    $title = New-UiLabel -Text $(if ($correct) { '答对了 · 第 ' + ($idx + 1) + ' 题' } else { '这题先记动作 · 第 ' + ($idx + 1) + ' 题' }) -Size 22 -Style ([System.Drawing.FontStyle]::Bold) -Color $bannerColor
    $title.Location = New-Object System.Drawing.Point(20, 14)
    $ui.Card.Controls.Add($title)
    $enc = [string](Get-ObjectPropertyValue $ev 'encouragement' '')
    $reasonQ = [string](Get-ObjectPropertyValue $ev 'reason_quality' '')
    $err = [string](Get-ObjectPropertyValue $ev 'error_type' '')
    $summary = "你的答案：$(Get-ObjectPropertyValue $cur 'selected' '') · 正确答案：$($q.answer) · 理由质量：$reasonQ · 错误类型：$err"
    $sl = New-UiLabel -Text $summary -Size 14 -Color $script:UiMutedColor -MaxWidth 900
    $sl.Location = New-Object System.Drawing.Point(20, 56)
    $ui.Card.Controls.Add($sl)
    if ($enc) {
        $el = New-UiLabel -Text ('老师赠你一句：' + $enc) -Size 15 -Color $script:UiPrimaryDark -MaxWidth 900
        $el.Location = New-Object System.Drawing.Point(20, 84)
        $ui.Card.Controls.Add($el)
    }
    $box = New-Object System.Windows.Forms.RichTextBox
    $box.Location = New-Object System.Drawing.Point(20, 118)
    $box.Width = 910; $box.Height = 330
    $box.ReadOnly = $true; $box.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $box.BackColor = [System.Drawing.Color]::FromArgb(252, 250, 244)
    $box.Font = New-Object System.Drawing.Font($script:UiFontName, 15)
    $text = Get-FeedbackText $fb
    if (-not $text) { $text = '这题没有额外解析。先记住动作：先读题干，再回原文/录音定位，找同义替换。' }
    $box.Text = $text
    $ui.Card.Controls.Add($box)
    $srcLabel = New-UiLabel -Text ("讲解来源：{0} · 回放 {1} 次" -f (Get-ObjectPropertyValue $fb 'source' 'local'), (Get-ObjectPropertyValue $cur 'replayCount' 0)) -Size 12 -Color $script:UiMutedColor
    $srcLabel.Location = New-Object System.Drawing.Point(20, 456)
    $ui.Card.Controls.Add($srcLabel)
    $next = New-UiButton -Text '下一题' -Width 200 -OnClick {
        $s = $script:QuizUi.Session
        Set-ObjectPropertyValue $s 'current' $null
        Set-ObjectPropertyValue $s 'index' ([int](Get-ObjectPropertyValue $s 'index' 0) + 1)
        Save-QuizSession $s
        if ([int](Get-ObjectPropertyValue $s 'index' 0) -ge $script:QuizUi.Questions.Count) {
            Complete-QuizRound
        } else {
            Show-QuizQuestion
        }
    }
    $next.Location = New-Object System.Drawing.Point(20, 500)
    $ui.Card.Controls.Add($next)
}

function Complete-QuizRound {
    param([switch]$TimeExpired)
    $ui = $script:QuizUi
    if ($null -eq $ui -or $null -eq $ui.Session) { return }
    $s = $ui.Session
    if ([bool](Get-ObjectPropertyValue $s 'completed' $false)) { return }
    Stop-PageTimer
    # Mark the current unanswered question and any remaining questions as incomplete.
    $idx = [int](Get-ObjectPropertyValue $s 'index' 0)
    $results = @(Get-ObjectPropertyValue $s 'results' @())
    for ($i = $idx; $i -lt $ui.Questions.Count; $i++) {
        $q = $ui.Questions[$i]
        $already = @($results | Where-Object { [string](Get-ObjectPropertyValue $_ 'questionId' '') -eq [string]$q.id }).Count -gt 0
        if ($already) { continue }
        Add-QuestionToWrongBook -Question $q -UserAnswer '' -UserReason $(if ($TimeExpired) { '时间到，未作答' } else { '未完成' }) -ErrorType '时间不够' -Explanation '' -TeacherExplanation '这题未作答，已进入待复习队列；下次先保重点题。' -Technique (Get-TechniqueText $q.type) -Incomplete
        $results += [ordered]@{ questionId = $q.id; type = $q.type; selected = ''; answer = $q.answer; reason = ''; replayCount = 0; correct = $false; answered = $false; errorType = '时间不够'; reasonQuality = ''; feedbackSource = '' }
    }
    Set-ObjectPropertyValue $s 'results' $results
    $summary = Get-QuizScoreSummary $s
    $award = ($summary.Answered -ge [int](Get-ConfigValue 'quiz.questionCount' 20))
    Set-ObjectPropertyValue $s 'completed' $true
    Set-ObjectPropertyValue $s 'completedAt' (Get-Date).ToString('o')
    Set-ObjectPropertyValue $s 'quizAwarded' $award
    Set-ObjectPropertyValue $s 'summary' ([ordered]@{ answered = $summary.Answered; correct = $summary.Correct; wrong = $summary.Wrong; incomplete = $summary.Incomplete; accuracy = $summary.Accuracy; timeExpired = [bool]$TimeExpired })
    Save-QuizSession $s
    if ($award) {
        try { Add-QuizCheckin -Date ([string](Get-ObjectPropertyValue $s 'date' (Get-TodayString))) -QuizCount $summary.Answered } catch { }
    }
    try { Clear-ListeningTempWorkspace -Silent | Out-Null } catch { }
    Clear-ContentPanel
    $head = New-PageHeader '这一轮结束了' '先看结果，再看错题画像。错题已经在错题本里，次日会优先重出。'
    $script:ContentPanel.Controls.Add($head)
    $card = New-UiCard -Width 960 -Height 430
    $card.Location = New-Object System.Drawing.Point(0, 100)
    $script:ContentPanel.Controls.Add($card)
    $l1 = New-UiLabel -Text ("答对 {0} / 已答 {1}" -f $summary.Correct, $summary.Answered) -Size 26 -Style ([System.Drawing.FontStyle]::Bold) -Color $script:UiPrimaryDark
    $l1.Location = New-Object System.Drawing.Point(20, 22)
    $card.Controls.Add($l1)
    $l2 = New-UiLabel -Text ("正确率 {0}% · 未完成 {1} 题 · {2}" -f $summary.Accuracy, $summary.Incomplete, $(if ($award) { '刷题打卡已记录' } else { '未满 20 题，不记刷题打卡' })) -Size 17 -Color $script:UiMutedColor
    $l2.Location = New-Object System.Drawing.Point(20, 80)
    $card.Controls.Add($l2)
    $l3 = New-UiLabel -Text '未完成的题不计正确率，但已经进入待复习队列。' -Size 15 -Color $script:UiMutedColor
    $l3.Location = New-Object System.Drawing.Point(20, 122)
    $card.Controls.Add($l3)
    $b1 = New-UiButton -Text '查看打卡月历' -Width 210 -OnClick { Show-CheckinPage }
    $b1.Location = New-Object System.Drawing.Point(20, 210)
    $card.Controls.Add($b1)
    $b2 = New-UiButton -Text '回到主菜单' -Width 200 -BackColor $script:UiAccent -OnClick { Show-HomePage }
    $b2.Location = New-Object System.Drawing.Point(260, 210)
    $card.Controls.Add($b2)
    Set-StatusBar '本轮结束。'
}
