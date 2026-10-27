# chat.ps1 - DeepSeek chat for the home page and the current question.
# The same DEEPSEEK_API_KEY / baseUrl configuration as the rest of the app is used.

$script:ChatHistories = @{}

function Get-ChatHistory {
    param([string]$Key)
    if (-not $Key) { return @() }
    return @($script:ChatHistories[$Key])
}

function Set-ChatHistory {
    param([string]$Key, [object[]]$Messages)
    if (-not $Key) { return }
    $arr = @($Messages)
    if ($arr.Count -gt 16) { $arr = @($arr[($arr.Count - 16)..($arr.Count - 1)]) }
    $script:ChatHistories[$Key] = $arr
}

function Add-ChatMessage {
    param([string]$Key, [string]$Role, [string]$Content)
    if (-not $Key -or [string]::IsNullOrWhiteSpace($Content)) { return }
    $h = @(Get-ChatHistory $Key)
    $h += [pscustomobject]@{ role = $Role; content = $Content.Trim() }
    Set-ChatHistory $Key $h
}

function Remove-LastChatMessage {
    param([string]$Key)
    $h = @(Get-ChatHistory $Key)
    if ($h.Count -le 1) { Set-ChatHistory $Key @(); return }
    $h = @($h[0..($h.Count - 2)])
    Set-ChatHistory $Key $h
}

function Format-ChatTranscript {
    param([object[]]$Messages)
    $arr = @($Messages)
    if ($arr.Count -eq 0) { return '还没有对话。可以问这道题的定位、同义替换、听力技巧，或下一步怎么练。' }
    $lines = @()
    foreach ($m in $arr) {
        $role = [string](Get-ObjectPropertyValue $m 'role' 'user')
        $text = [string](Get-ObjectPropertyValue $m 'content' '')
        if ($role -eq 'assistant') { $lines += ('大肥鱼：' + $text) } else { $lines += ('你：' + $text) }
    }
    return ($lines -join "`r`n`r`n")
}

function Limit-ChatText {
    param([string]$Text, [int]$Max = 4200)
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    $t = $Text.Trim()
    if ($t.Length -gt $Max) { return $t.Substring(0, $Max) + '…（后面省略）' }
    return $t
}

function Get-ChatQuestionContext {
    param($Question, $Current)
    if ($null -eq $Question) { return '' }
    $submitted = [bool](Get-ObjectPropertyValue $Current 'submitted' $false)
    $answer = [string](Get-ObjectPropertyValue $Question 'answer' '')
    $options = @()
    foreach ($o in @(Get-ObjectPropertyValue $Question 'options' @())) {
        $options += ('{0}) {1}' -f (Get-ObjectPropertyValue $o 'key' ''), (Get-ObjectPropertyValue $o 'text' ''))
    }
    $lines = @(
        ('题型：' + (Get-TypeDisplayName ([string]$Question.type))),
        ('题号：' + [string]$Question.q_no),
        ('题干：' + [string]$Question.stem),
        ('选项：' + ($options -join ' / '))
    )
    if ($submitted) {
        $lines += ('正确答案：' + $answer)
        $lines += ('学生选择：' + [string](Get-ObjectPropertyValue $Current 'selected' ''))
        $lines += ('是否正确：' + $(if ([bool](Get-ObjectPropertyValue $Current 'correct' $false)) { '正确' } else { '错误' }))
        $lines += ('学生理由：' + [string](Get-ObjectPropertyValue $Current 'reason' ''))
        $lines += ('题目解析：' + (Limit-ChatText ([string](Get-ObjectPropertyValue $Question 'explanation' '')) 3600))
    } else {
        $lines += '学生尚未提交。不要直接说出正确选项；先用提示、定位方法和排除思路引导。'
    }
    $transcript = Limit-ChatText ([string](Get-QuestionTranscript $Question)) 4200
    if ($transcript) { $lines += ('听力原文/材料：' + $transcript) }
    return ($lines -join "`r`n")
}

function Get-ChatSystemPrompt {
    param([string]$Mode, $Question, $Current)
    $base = '你是四级教练「大肥鱼」，用中文回答，语气温和、直接、具体。先给结论，再给 1—3 个可执行步骤；控制在 350 字以内。只讨论 CET-4 英语、这道题和学习方法。不要编造原文或听力内容；资料不足就明确说不足，并告诉学生下一步怎么查。'
    if ($Mode -eq 'question') {
        return $base + "`r`n`r`n【本题资料】`r`n" + (Get-ChatQuestionContext $Question $Current) + "`r`n`r`n回答必须围绕这道题；学生问其他题时，先拉回本题。"
    }
    $planDay = 1
    try {
        $start = [datetime]::ParseExact([string](Get-ConfigValue 'plan.startDate' (Get-TodayString)), 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
        $planDay = [int][Math]::Max(1, [Math]::Min([int](Get-ConfigValue 'plan.days' 90), ((Get-Date).Date - $start.Date).Days + 1))
    } catch { }
    $streak = 0
    try { $streak = Get-CheckinStreak (Get-CheckinData) } catch { }
    $wrong = 0
    try { $wrong = @(Read-JsonFile (Get-CET4Path 'data/wrongbook.json') @() -Quiet).Count } catch { }
    return $base + "`r`n`r`n学生当前：90 天计划第 $planDay 天，连续打卡 $streak 天，错题本 $wrong 条。可以回答听力技巧、阅读方法、时间分配、复盘安排等通用问题。"
}

function Invoke-HomeChatTurn {
    param([string]$Key)
    $history = @(Get-ChatHistory $Key)
    if ($history.Count -eq 0) { throw '还没有输入问题。' }
    $system = Get-ChatSystemPrompt -Mode 'home'
    $last = [string](Get-ObjectPropertyValue $history[$history.Count - 1] 'content' '')
    $messages = @([ordered]@{ role = 'system'; content = $system })
    foreach ($m in $history) {
        $messages += [ordered]@{ role = [string](Get-ObjectPropertyValue $m 'role' 'user'); content = [string](Get-ObjectPropertyValue $m 'content' '') }
    }
    $resp = Invoke-DeepSeekChat -System $system -User $last -Messages $messages -Purpose 'chat-home' -NoCache -Temperature 0.45 -MaxTokens 1000
    return [string]$resp.Content
}

function Invoke-QuestionChatTurn {
    param([string]$Key, $Question, $Current)
    $history = @(Get-ChatHistory $Key)
    if ($history.Count -eq 0) { throw '还没有输入问题。' }
    $system = Get-ChatSystemPrompt -Mode 'question' -Question $Question -Current $Current
    $last = [string](Get-ObjectPropertyValue $history[$history.Count - 1] 'content' '')
    $messages = @([ordered]@{ role = 'system'; content = $system })
    foreach ($m in $history) {
        $messages += [ordered]@{ role = [string](Get-ObjectPropertyValue $m 'role' 'user'); content = [string](Get-ObjectPropertyValue $m 'content' '') }
    }
    $resp = Invoke-DeepSeekChat -System $system -User $last -Messages $messages -Purpose 'chat-question' -NoCache -Temperature 0.4 -MaxTokens 1100
    return [string]$resp.Content
}

function New-ChatCard {
    param(
        [string]$Key,
        [string]$Title = '问大肥鱼',
        [string]$Subtitle = '接入 DeepSeek；问题和本机学习记录一起理解。',
        [int]$Height = 400,
        $Question = $null,
        $Current = $null,
        [switch]$General
    )
    $w = $script:UiContentWidth
    $card = New-UiCard -Width $w -Height $Height
    $titleLabel = New-UiLabel -Text $Title -Size 20 -Style ([System.Drawing.FontStyle]::Bold) -Color $script:UiPrimaryDark
    $titleLabel.Location = New-Object System.Drawing.Point(20, 14)
    $card.Controls.Add($titleLabel)
    $sub = New-UiLabel -Text $Subtitle -Size 13 -Color $script:UiMutedColor -MaxWidth ($w - 40)
    $sub.Location = New-Object System.Drawing.Point(20, 46)
    $card.Controls.Add($sub)
    if (-not (Test-DeepSeekKeyPresent)) {
        $warn = New-UiLabel -Text '还没有 DEEPSEEK_API_KEY。聊天需要先在「设置与诊断」绑定 Key；绑定后与深度讲解共用。' -Size 12 -Color $script:UiDanger -MaxWidth ($w - 40)
        $warn.Location = New-Object System.Drawing.Point(20, 68)
        $card.Controls.Add($warn)
    }

    $box = New-Object System.Windows.Forms.TextBox
    $box.Multiline = $true
    $box.ReadOnly = $true
    $box.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
    $box.WordWrap = $true
    $box.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $box.BackColor = [System.Drawing.Color]::FromArgb(252, 250, 244)
    $box.Font = New-Object System.Drawing.Font($script:UiFontName, 12)
    $box.Location = New-Object System.Drawing.Point(20, 96)
    $box.Size = New-Object System.Drawing.Size(($w - 40), 164)
    $box.Text = Format-ChatTranscript (Get-ChatHistory $Key)
    $card.Controls.Add($box)

    $input = New-Object System.Windows.Forms.TextBox
    $input.Font = New-Object System.Drawing.Font($script:UiFontName, 13)
    $input.Location = New-Object System.Drawing.Point(20, 274)
    $input.Size = New-Object System.Drawing.Size(($w - 360), 40)
    $input.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $card.Controls.Add($input)

    $send = New-UiButton -Text '发送' -Width 100 -Height 40 -Size 14 -BackColor $script:UiPrimaryDark -ForeColor ([System.Drawing.Color]::White)
    $send.Location = New-Object System.Drawing.Point(($w - 210), 274)
    $card.Controls.Add($send)

    $clear = New-UiButton -Text '清空对话' -Width 90 -Height 40 -Size 12 -BackColor ([System.Drawing.Color]::FromArgb(210, 205, 192)) -ForeColor $script:UiTextColor
    $clear.Location = New-Object System.Drawing.Point(($w - 340), 274)
    $card.Controls.Add($clear)

    $hint = New-UiLabel -Text 'Enter 发送；回答基于当前题目/学习数据，不替代原文。' -Size 11 -Color $script:UiMutedColor -MaxWidth ($w - 40)
    $hint.Location = New-Object System.Drawing.Point(20, 326)
    $card.Controls.Add($hint)

    $send.Add_Click({
        $text = [string]$input.Text
        if ([string]::IsNullOrWhiteSpace($text)) { return }
        if (-not (Test-DeepSeekKeyPresent)) {
            Show-AppMessage '还没有设置 DEEPSEEK_API_KEY。请到「设置与诊断」绑定 Key，聊天和深度讲解共用同一个 Key。' '聊天需要 API Key' ([System.Windows.Forms.MessageBoxIcon]::Information)
            return
        }
        Add-ChatMessage -Key $Key -Role 'user' -Content $text
        $input.Text = ''
        $box.Text = Format-ChatTranscript (Get-ChatHistory $Key)
        $box.SelectionStart = $box.Text.Length
        $box.ScrollToCaret()
        Show-UiProgress -Title '大肥鱼正在想' -Text '正在结合当前题目/学习数据分析…'
        $err = $null
        try {
            if ($General) {
                $reply = Invoke-HomeChatTurn -Key $Key
            } else {
                $reply = Invoke-QuestionChatTurn -Key $Key -Question $Question -Current $Current
            }
            Add-ChatMessage -Key $Key -Role 'assistant' -Content $reply
            Set-StatusBar '大肥鱼回答已更新。'
        } catch {
            $err = $_
            Remove-LastChatMessage -Key $Key
        } finally {
            Close-UiProgress
        }
        $box.Text = Format-ChatTranscript (Get-ChatHistory $Key)
        $box.SelectionStart = $box.Text.Length
        $box.ScrollToCaret()
        if ($err) {
            Show-AppMessage ('聊天失败：' + (Format-SafeError $err)) '聊天' ([System.Windows.Forms.MessageBoxIcon]::Warning)
        }
        $input.Focus() | Out-Null
    })

    $clear.Add_Click({
        $script:ChatHistories[$Key] = @()
        $box.Text = Format-ChatTranscript @()
    })

    $input.Add_KeyDown({
        param($sender, $e)
        if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Enter) {
            $e.SuppressKeyPress = $true
            $send.PerformClick()
        }
    })

    return $card
}
