# checkin.ps1 - daily base check-in, quiz badge, streak milestones, monthly
# calendar, and the Sunday wrong-book portrait.

function Get-CheckinFile { return (Get-ConfigValue 'paths.checkin' 'data/checkin.json') }

function Get-CheckinData {
    $c = Read-JsonFile (Get-CheckinFile) $null -Quiet
    if ($null -eq $c) {
        $c = [pscustomobject]@{ days = [pscustomobject]@{}; milestones = @() }
    }
    if ($null -eq (Get-ObjectPropertyValue $c 'days' $null)) { Set-ObjectPropertyValue $c 'days' ([pscustomobject]@{}) }
    if ($null -eq (Get-ObjectPropertyValue $c 'milestones' $null)) { Set-ObjectPropertyValue $c 'milestones' @() }
    return $c
}

function Save-CheckinData {
    param($Data)
    Write-JsonFile (Get-CheckinFile) $Data
}

function Get-CheckinDay {
    param($Data, [string]$Date)
    $days = Get-ObjectPropertyValue $Data 'days' ([pscustomobject]@{})
    $entry = Get-ObjectPropertyValue $days $Date $null
    if ($null -eq $entry) { return $null }
    return $entry
}

function Set-CheckinDay {
    param($Data, [string]$Date, [hashtable]$Patch)
    $days = Get-ObjectPropertyValue $Data 'days' ([pscustomobject]@{})
    $entry = Get-CheckinDay $Data $Date
    if ($null -eq $entry) {
        $entry = [pscustomobject]@{ word = $false; quiz = $false; minutes = 0; wordsDone = 0; quizCount = 0; updatedAt = $null }
    }
    foreach ($k in $Patch.Keys) { Set-ObjectPropertyValue $entry $k $Patch[$k] }
    Set-ObjectPropertyValue $entry 'updatedAt' (Get-Date).ToString('o')
    Set-ObjectPropertyValue $days $Date $entry
    Set-ObjectPropertyValue $Data 'days' $days
}

function Get-CheckinStreak {
    param($Data = (Get-CheckinData), [datetime]$From = (Get-Date).Date)
    $streak = 0
    $cursor = $From
    for ($i = 0; $i -lt 400; $i++) {
        $key = $cursor.ToString('yyyy-MM-dd')
        $entry = Get-CheckinDay $Data $key
        if ($null -ne $entry -and [bool](Get-ObjectPropertyValue $entry 'word' $false)) {
            $streak++
            $cursor = $cursor.AddDays(-1)
        } else {
            if ($i -eq 0) {
                # If today has not been checked in yet, count backwards from yesterday.
                $cursor = $cursor.AddDays(-1)
                continue
            }
            break
        }
    }
    return $streak
}

function Get-StreakEncouragement {
    param($Data, [int]$Streak)
    if ($Streak -notin @(7, 14, 30)) { return '' }
    $milestones = @(Get-ObjectPropertyValue $Data 'milestones' @())
    $today = Get-TodayString
    if ($milestones | Where-Object { [string](Get-ObjectPropertyValue $_ 'date' '') -eq $today -and [int](Get-ObjectPropertyValue $_ 'days' 0) -eq $Streak }) {
        return ''
    }
    $messages = @{
        7 = '连续 7 天。你已经把「每天碰一点英语」变成了习惯，这比一次学很久更有用。'
        14 = '连续 14 天。两周没有断，说明这个节奏适合你。继续保持，不用加量。'
        30 = '连续 30 天。一个月了，词汇和题感正在悄悄变稳。今天也只需完成该做的部分。'
    }
    $msg = $messages[$Streak]
    $milestones += [pscustomobject]@{ date = $today; days = $Streak; message = $msg }
    Set-ObjectPropertyValue $Data 'milestones' $milestones
    Save-CheckinData $Data
    return $msg
}

function Add-WordCheckin {
    param([string]$Date = (Get-TodayString), [int]$Minutes = 30, [int]$WordsDone = 0)
    $data = Get-CheckinData
    $entry = Get-CheckinDay $data $Date
    $oldMinutes = if ($entry) { [int](Get-ObjectPropertyValue $entry 'minutes' 0) } else { 0 }
    $oldWords = if ($entry) { [int](Get-ObjectPropertyValue $entry 'wordsDone' 0) } else { 0 }
    Set-CheckinDay $data $Date @{
        word = $true
        minutes = [Math]::Max($oldMinutes, $Minutes)
        wordsDone = [Math]::Max($oldWords, $WordsDone)
    }
    Save-CheckinData $data
    $streak = Get-CheckinStreak $data
    $msg = Get-StreakEncouragement $data $streak
    Write-CET4Log -Category 'checkin' -Message ("基础打卡 {0}，连续 {1} 天" -f $Date, $streak)
    return [pscustomobject]@{ Ok = $true; Streak = $streak; Encouragement = $msg; Date = $Date }
}

function Add-QuizCheckin {
    param([string]$Date = (Get-TodayString), [int]$QuizCount = 20)
    $data = Get-CheckinData
    $entry = Get-CheckinDay $data $Date
    $old = if ($entry) { [int](Get-ObjectPropertyValue $entry 'quizCount' 0) } else { 0 }
    Set-CheckinDay $data $Date @{ quiz = $true; quizCount = [Math]::Max($old, $QuizCount) }
    Save-CheckinData $data
    Write-CET4Log -Category 'checkin' -Message ("刷题打卡 {0}，{1} 题" -f $Date, $QuizCount)
}

function Get-WeekStart {
    param([datetime]$Date = (Get-Date).Date)
    $offset = ([int]$Date.DayOfWeek + 6) % 7  # Monday = 0
    return $Date.AddDays(-$offset)
}

function Get-WeeklyWrongStats {
    param([datetime]$Date = (Get-Date).Date)
    $start = Get-WeekStart $Date
    $end = $start.AddDays(7)
    $wrong = @(Read-JsonFile (Get-ConfigValue 'paths.wrongbook' 'data/wrongbook.json') @() -Quiet)
    $week = @($wrong | Where-Object {
        $t = [string](Get-ObjectPropertyValue $_ 'lastWrongAt' '')
        if (-not $t) { return $false }
        try { $dt = [datetime]::Parse($t); return ($dt -ge $start -and $dt -lt $end) } catch { return $false }
    })
    $byType = @{}
    foreach ($w in $week) {
        $type = [string](Get-ObjectPropertyValue $w 'type' '其他')
        if (-not $byType.ContainsKey($type)) { $byType[$type] = 0 }
        $byType[$type]++
    }
    return [pscustomobject]@{ Start = $start; End = $end.AddDays(-1); Wrong = $week; ByType = $byType }
}

function Get-LocalWeeklyReport {
    param($Stats)
    if ($Stats.Wrong.Count -eq 0) {
        return '这周没有新增错题，说明你做题比较稳。可以继续保持每天 20 题，重点看仔细阅读和听力篇章。'
    }
    $top = @($Stats.ByType.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 2)
    $typeNames = @{ careful_reading = '仔细阅读'; listening_passage = '听力篇章'; listening_news = '听力新闻'; listening_long = '长对话'; matching = '长篇匹配'; cloze = '选词填空' }
    $names = @($top | ForEach-Object { if ($typeNames.ContainsKey([string]$_.Key)) { $typeNames[[string]$_.Key] } else { [string]$_.Key } })
    $text = ('这周错得比较多的是：{0}。共同模式多半是：定位到了句子，但没认出同义替换，或者听力信号词后面的内容没跟上。下周每次先读题干圈关键词，再回原文/录音找对应。' -f ($names -join '、'))
    return $text
}

function Invoke-WeeklyReport {
    param([switch]$Force)
    $week = Get-WeekStart
    $weekKey = $week.ToString('yyyy-MM-dd')
    $cacheFile = Get-CET4Path ('data/cache/weekly-' + $weekKey + '.json')
    if ((Test-Path -LiteralPath $cacheFile) -and -not $Force) {
        return Read-JsonFile $cacheFile $null -Quiet
    }
    $stats = Get-WeeklyWrongStats
    $local = Get-LocalWeeklyReport $stats
    $report = [ordered]@{
        week = $weekKey
        createdAt = (Get-Date).ToString('o')
        source = 'local'
        text = $local
        byType = $stats.ByType
        wrongCount = $stats.Wrong.Count
    }
    if ((Test-DeepSeekKeyPresent) -and ($stats.Wrong.Count -gt 0)) {
        try {
            $summaries = @($stats.Wrong | Select-Object -First 30 | ForEach-Object {
                $t = [string](Get-ObjectPropertyValue $_ 'type' '')
                $reason = [string](Get-ObjectPropertyValue $_ 'userReason' '')
                $err = [string](Get-ObjectPropertyValue $_ 'errorType' '')
                "- $t | 学生理由: $reason | 错误类型: $err"
            }) -join "`n"
            $system = '你是大学英语四级老师，给基础较弱的学生写本周错题画像。要求：3-5 句话，浅显直白，不堆术语；先总结错得最多的 2 个题型，再指出 1 个共同错误模式，最后给 1 个下周可执行的小动作。不要编造数据，不要输出 markdown。'
            $user = "本周错题统计（按题型）：`n$($stats.ByType | ConvertTo-Json -Compress)`n`n错题样本：`n$summaries`n`n只写 3-5 句中文。"
            $r = Invoke-DeepSeekChat -System $system -User $user -Purpose 'weekly_report' -MaxTokens 350 -CacheParts @{ week = $weekKey; wrong = $stats.Wrong.Count } -LogTag ('week-' + $weekKey)
            if ($r.Content) { $report.text = $r.Content.Trim(); $report.source = 'deepseek' }
        } catch {
            Write-CET4Log -Category 'weekly' -Level 'WARN' -Message ('周复盘调用失败，用本地摘要: ' + (Format-SafeError $_))
        }
    }
    Write-JsonFile $cacheFile $report
    return [pscustomobject]$report
}

function Show-WeeklyReportCard {
    param($Parent, [int]$Y = 0)
    $card = New-UiCard -Width 1060 -Height 250
    $card.Location = New-Object System.Drawing.Point(0, $Y)
    $Parent.Controls.Add($card)
    $title = New-UiLabel -Text '本周错题画像' -Size 20 -Style ([System.Drawing.FontStyle]::Bold) -Color $script:UiPrimaryDark
    $title.Location = New-Object System.Drawing.Point(20, 16)
    $card.Controls.Add($title)
    $body = New-UiLabel -Text '每周日会根据错题本生成 3-5 句画像；平时也可以点按钮手动生成。' -Size 15 -Color $script:UiMutedColor -MaxWidth 960
    $body.Location = New-Object System.Drawing.Point(20, 58)
    $card.Controls.Add($body)
    $btn = New-UiButton -Text '生成本周画像' -Width 190 -OnClick {
        try {
            Show-UiProgress -Title '本周错题画像' -Text '正在整理错题；有 DeepSeek Key 时会调用一次大模型…'
            $r = Invoke-WeeklyReport -Force
            $script:WeeklyBody.Text = [string]$r.text
            $script:WeeklyBody.AutoSize = $true
            $script:WeeklyBody.MaximumSize = New-Object System.Drawing.Size -ArgumentList 960, 0
            Set-StatusBar '本周画像已生成并缓存。'
        } catch {
            Show-AppMessage ('生成失败：' + (Format-SafeError $_)) '周复盘' ([System.Windows.Forms.MessageBoxIcon]::Warning)
        } finally { Close-UiProgress }
    }
    $btn.Location = New-Object System.Drawing.Point(20, 130)
    $card.Controls.Add($btn)
    $script:WeeklyBody = $body
    $existing = Read-JsonFile (Get-CET4Path ('data/cache/weekly-' + (Get-WeekStart).ToString('yyyy-MM-dd') + '.json')) $null -Quiet
    if ($existing -and $existing.text) { $body.Text = [string]$existing.text }
    return $card
}

function Show-CheckinPage {
    Clear-ContentPanel
    $head = New-PageHeader '打卡与错题画像' '单词 30 分钟算基础打卡；20 题刷题会在日历上多一个「刷」标记。'
    $script:ContentPanel.Controls.Add($head)
    $data = Get-CheckinData
    $streak = Get-CheckinStreak $data
    $card = New-UiCard -Width 1060 -Height 82
    $card.Location = New-Object System.Drawing.Point(0, 100)
    $script:ContentPanel.Controls.Add($card)
    $streakLabel = New-UiLabel -Text ("连续学习 {0} 天" -f $streak) -Size 24 -Style ([System.Drawing.FontStyle]::Bold) -Color $script:UiPrimaryDark
    $streakLabel.Location = New-Object System.Drawing.Point(20, 14)
    $card.Controls.Add($streakLabel)
    $enc = Get-StreakEncouragement $data $streak
    $sub = New-UiLabel -Text ($(if ($enc) { $enc } else { '完成 7/14/30 天时，这里会出现一句简短的鼓励。' })) -Size 14 -Color $script:UiMutedColor -MaxWidth 950
    $sub.Location = New-Object System.Drawing.Point(280, 22)
    $card.Controls.Add($sub)

    $calCard = New-UiCard -Width 1060 -Height 500
    $calCard.Location = New-Object System.Drawing.Point(0, 195)
    $script:ContentPanel.Controls.Add($calCard)
    $script:CalendarMonth = (Get-Date).Date.AddDays(1 - (Get-Date).Day)
    $script:CalendarHost = $calCard
    $renderCalendar = {
        $calCard = $script:CalendarHost
        $calCard.Controls.Clear()
        $month = $script:CalendarMonth
        $prev = New-UiButton -Text '上个月' -Width 100 -Height 40 -BackColor ([System.Drawing.Color]::FromArgb(220, 215, 203)) -ForeColor $script:UiTextColor -OnClick { $script:CalendarMonth = $script:CalendarMonth.AddMonths(-1); & $script:RenderCalendar }
        $prev.Location = New-Object System.Drawing.Point(20, 14)
        $calCard.Controls.Add($prev)
        $next = New-UiButton -Text '下个月' -Width 100 -Height 40 -BackColor ([System.Drawing.Color]::FromArgb(220, 215, 203)) -ForeColor $script:UiTextColor -OnClick { $script:CalendarMonth = $script:CalendarMonth.AddMonths(1); & $script:RenderCalendar }
        $next.Location = New-Object System.Drawing.Point(135, 14)
        $calCard.Controls.Add($next)
        $title = New-UiLabel -Text ($month.ToString('yyyy年M月')) -Size 22 -Style ([System.Drawing.FontStyle]::Bold) -Color $script:UiPrimaryDark
        $title.Location = New-Object System.Drawing.Point(330, 16)
        $calCard.Controls.Add($title)
        $weekNames = @('一', '二', '三', '四', '五', '六', '日')
        for ($i = 0; $i -lt 7; $i++) {
            $l = New-UiLabel -Text $weekNames[$i] -Size 14 -Color $script:UiMutedColor
            $l.Location = New-Object System.Drawing.Point((25 + $i * 128), 78)
            $calCard.Controls.Add($l)
        }
        $first = $month
        $offset = (([int]$first.DayOfWeek) + 6) % 7
        $days = [DateTime]::DaysInMonth($month.Year, $month.Month)
        for ($d = 1; $d -le $days; $d++) {
            $date = New-Object datetime($month.Year, $month.Month, $d)
            $pos = $offset + $d - 1
            $row = [Math]::Floor($pos / 7); $col = $pos % 7
            $cell = New-Object System.Windows.Forms.Panel
            $cell.Size = New-Object System.Drawing.Size(112, 50)
            $cell.Location = New-Object System.Drawing.Point((20 + $col * 128), (112 + $row * 56))
            $cell.BackColor = [System.Drawing.Color]::FromArgb(252, 250, 244)
            $cell.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
            $check = Get-CheckinDay $data ($date.ToString('yyyy-MM-dd'))
            $numColor = $script:UiMutedColor
            if ($check) { $cell.BackColor = [System.Drawing.Color]::FromArgb(231, 243, 236); $numColor = $script:UiPrimaryDark }
            if ($date.Date -eq (Get-Date).Date) { $cell.BackColor = [System.Drawing.Color]::FromArgb(255, 242, 204); $numColor = [System.Drawing.Color]::FromArgb(120, 75, 20) }
            $nl = New-UiLabel -Text ([string]$d) -Size 14 -Style ([System.Drawing.FontStyle]::Bold) -Color $numColor
            $nl.Location = New-Object System.Drawing.Point(7, 5)
            $cell.Controls.Add($nl)
            if ($check) {
                $isWord = [bool](Get-ObjectPropertyValue $check 'word' $false)
                $isQuiz = [bool](Get-ObjectPropertyValue $check 'quiz' $false)
                $mark = if ($isWord -and $isQuiz) { '单词✓ 刷题✓' } elseif ($isWord) { '单词✓' } elseif ($isQuiz) { '刷题✓' } else { '' }
                if ($mark) {
                    $ml = New-UiLabel -Text $mark -Size 12 -Color $script:UiGood
                    $ml.Location = New-Object System.Drawing.Point(6, 27)
                    $cell.Controls.Add($ml)
                }
            }
            $calCard.Controls.Add($cell)
        }
    }
    $script:RenderCalendar = $renderCalendar
    & $renderCalendar

    $weeklyCard = Show-WeeklyReportCard -Parent $script:ContentPanel -Y 710
    Set-StatusBar '打卡记录保存在 data/checkin.json。'
    Reset-ContentScroll
}
