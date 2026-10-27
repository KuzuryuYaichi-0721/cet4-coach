# words.ps1 - 30-minute vocabulary session, 50/50 new-word routing,
# offline checks, optional DeepSeek evaluation, check-in and temp-audio cleanup.

$script:WordDataCache = $null
$script:WordSentenceCache = $null
$script:WordUi = $null

function Get-WordBank {
    if ($null -eq $script:WordDataCache) {
        $script:WordDataCache = @(Read-JsonFile (Get-ConfigValue 'paths.words' 'data/words.json') @() -Quiet)
    }
    return $script:WordDataCache
}

function Get-WordSentenceBank {
    if ($null -eq $script:WordSentenceCache) {
        $script:WordSentenceCache = @(Read-JsonFile (Get-ConfigValue 'paths.wordSentences' 'data/word_sentences.json') @() -Quiet)
    }
    return $script:WordSentenceCache
}

function Get-WordProgress {
    $p = Read-JsonFile (Get-ConfigValue 'paths.wordProgress' 'data/word_progress.json') $null -Quiet
    if ($null -eq $p) {
        $p = [pscustomobject]@{
            introduced = @(); coreCursor = 0; recognitionCursor = 750; reviewQueue = @();
            status = [pscustomobject]@{}; lastSessionDate = $null
        }
    }
    foreach ($name in @('introduced', 'reviewQueue')) {
        if ($null -eq (Get-ObjectPropertyValue $p $name $null)) { Set-ObjectPropertyValue $p $name @() }
    }
    if ($null -eq (Get-ObjectPropertyValue $p 'status' $null)) { Set-ObjectPropertyValue $p 'status' ([pscustomobject]@{}) }
    return $p
}

function Save-WordProgress {
    param($Progress)
    Write-JsonFile (Get-ConfigValue 'paths.wordProgress' 'data/word_progress.json') $Progress
}

function Get-WordStatusEntry {
    param($Progress, [string]$Word)
    $status = Get-ObjectPropertyValue $Progress 'status' ([pscustomobject]@{})
    $entry = Get-ObjectPropertyValue $status $Word $null
    if ($null -eq $entry) {
        $entry = [pscustomobject]@{ state = 'new'; correct = 0; wrong = 0; lastSeen = $null; nextReview = $null; sessions = 0 }
        Set-ObjectPropertyValue $status $Word $entry
    }
    return $entry
}

function Add-ReviewQueueWord {
    param($Progress, [string]$Word, [string]$Reason = 'unmastered', [int]$Days = 1)
    $queue = @(Get-ObjectPropertyValue $Progress 'reviewQueue' @())
    $due = (Get-Date).Date.AddDays($Days).ToString('yyyy-MM-dd')
    $filtered = @($queue | Where-Object { [string](Get-ObjectPropertyValue $_ 'word' '') -ne $Word })
    $filtered += [pscustomobject]@{ word = $Word; due = $due; reason = $Reason; addedAt = (Get-Date).ToString('o') }
    Set-ObjectPropertyValue $Progress 'reviewQueue' $filtered
}

function Remove-ReviewQueueWord {
    param($Progress, [string]$Word)
    $queue = @(Get-ObjectPropertyValue $Progress 'reviewQueue' @())
    $filtered = @($queue | Where-Object { [string](Get-ObjectPropertyValue $_ 'word' '') -ne $Word })
    Set-ObjectPropertyValue $Progress 'reviewQueue' $filtered
}

function Get-DueReviewWords {
    param($Progress, [int]$Limit = 20)
    $today = (Get-Date).Date
    $queue = @(Get-ObjectPropertyValue $Progress 'reviewQueue' @())
    $due = @($queue | Where-Object {
        $d = [string](Get-ObjectPropertyValue $_ 'due' '')
        if (-not $d) { return $false }
        try { return ([datetime]::ParseExact($d, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture) -le $today) } catch { return $false }
    })
    return @($due | Select-Object -First $Limit)
}

function New-WordSessionPlan {
    $words = @(Get-WordBank)
    $progress = Get-WordProgress
    $introduced = @{}
    foreach ($w in @(Get-ObjectPropertyValue $progress 'introduced' @())) { $introduced[[string]$w] = $true }
    $coreWant = [int](Get-ConfigValue 'wordSession.corePerDay' 13)
    $recWant = [int](Get-ConfigValue 'wordSession.recognitionPerDay' 13)
    $newTarget = [int](Get-ConfigValue 'wordSession.newWordsPerDay' 26)
    if ($coreWant + $recWant -ne $newTarget) { $coreWant = [int][Math]::Ceiling($newTarget / 2); $recWant = $newTarget - $coreWant }
    $core = @($words | Where-Object { $_.group -eq 'core' -and -not $introduced.ContainsKey([string]$_.word) } | Select-Object -First $coreWant)
    $rec = @($words | Where-Object { $_.group -eq 'recognition' -and -not $introduced.ContainsKey([string]$_.word) } | Select-Object -First $recWant)
    if ($core.Count -lt $coreWant) {
        $extra = @($words | Where-Object { -not $introduced.ContainsKey([string]$_.word) -and -not ($core.word -contains $_.word) -and -not ($rec.word -contains $_.word) } | Select-Object -First ($coreWant - $core.Count))
        $core += $extra
    }
    if ($rec.Count -lt $recWant) {
        $extra = @($words | Where-Object { -not $introduced.ContainsKey([string]$_.word) -and -not ($core.word -contains $_.word) -and -not ($rec.word -contains $_.word) } | Select-Object -First ($recWant - $rec.Count))
        $rec += $extra
    }
    $newEntries = @()
    $max = [Math]::Max($core.Count, $rec.Count)
    for ($i = 0; $i -lt $max; $i++) {
        if ($i -lt $core.Count) { $newEntries += [ordered]@{ word = [string]$core[$i].word; mode = 'new'; group = 'core'; sentence = $null } }
        if ($i -lt $rec.Count) { $newEntries += [ordered]@{ word = [string]$rec[$i].word; mode = 'new'; group = 'recognition'; sentence = $null } }
    }
    $reviews = @(Get-DueReviewWords -Progress $progress -Limit ([int](Get-ConfigValue 'wordSession.reviewLimit' 20)))
    $reviewEntries = @($reviews | ForEach-Object {
        $rw = [string](Get-ObjectPropertyValue $_ 'word' '')
        if ($rw -and -not ($newEntries | Where-Object { $_.word -eq $rw })) {
            [ordered]@{ word = $rw; mode = 'review'; group = 'review'; sentence = $null }
        }
    })
    $all = @($newEntries + $reviewEntries)
    $maxTotal = [int](Get-ConfigValue 'wordSession.maxTotalWords' 48)
    if ($all.Count -gt $maxTotal) { $all = @($all | Select-Object -First $maxTotal) }
    return $all
}

function Get-SessionPathForWords {
    param([string]$Date = (Get-TodayString))
    return (Join-Path (Get-ConfigValue 'paths.sessions' 'data/sessions') ('word-' + $Date + '.json'))
}

function New-WordSession {
    $plan = @(New-WordSessionPlan)
    $minutes = [int](Get-ConfigValue 'wordSession.minutes' 30)
    $now = Get-Date
    $session = [ordered]@{
        version = 1
        date = (Get-TodayString)
        startedAt = $now.ToString('o')
        endsAt = $now.AddMinutes($minutes).ToString('o')
        minutes = $minutes
        plan = @($plan)
        index = 0
        step = 'meaning'
        sentenceCounter = 0
        results = @()
        current = $null
        completed = $false
        baseAwarded = $false
        tempPrepared = $false
        tempDir = $null
        summary = $null
    }
    Write-JsonFile (Get-SessionPathForWords) $session
    return [pscustomobject]$session
}

function Get-ExistingWordSession {
    $s = Read-JsonFile (Get-SessionPathForWords) $null -Quiet
    if ($null -eq $s) { return $null }
    if ([bool](Get-ObjectPropertyValue $s 'completed' $false)) { return $null }
    return $s
}

function Save-WordSession {
    param($Session)
    if ($null -eq $Session) { return }
    Write-JsonFile (Get-SessionPathForWords ([string](Get-ObjectPropertyValue $Session 'date' (Get-TodayString)))) $Session
    if (Get-Command Save-PortableProgress -ErrorAction SilentlyContinue) { try { Save-PortableProgress -Silent } catch { } }
}

function Get-WordEntryFromSession {
    param($Session)
    if ($null -eq $Session) { return $null }
    $plan = @(Get-ObjectPropertyValue $Session 'plan' @())
    $idx = [int](Get-ObjectPropertyValue $Session 'index' 0)
    if ($idx -lt 0 -or $idx -ge $plan.Count) { return $null }
    return $plan[$idx]
}

function Get-SentenceForWordEntry {
    param($Session, $Entry)
    if ($null -eq $Entry) { return $null }
    if ($null -ne (Get-ObjectPropertyValue $Entry 'sentence' $null)) {
        return (Get-ObjectPropertyValue $Entry 'sentence' $null)
    }
    $word = [string](Get-ObjectPropertyValue $Entry 'word' '')
    $all = @(Get-WordSentenceBank | Where-Object { [string]$_.word -eq $word })
    $real = @($all | Where-Object { $_.sentence_type -eq '真题' })
    $fun = @($all | Where-Object { $_.sentence_type -ne '真题' })
    $counter = [int](Get-ObjectPropertyValue $Session 'sentenceCounter' 0)
    $chooseReal = (($counter % 2) -eq 0) -and ($real.Count -gt 0)
    $chosen = if ($chooseReal) { $real[0] } elseif ($fun.Count -gt 0) { $fun[0] } elseif ($real.Count -gt 0) { $real[0] } else { $null }
    if ($null -eq $chosen) {
        $chosen = [pscustomobject]@{ word = $word; en = ("Today's word is {0}." -f $word); zh = '今天的单词卡。'; target_meaning = ''; sentence_type = '趣味'; source = 'fallback'; material_id = $null }
    }
    Set-ObjectPropertyValue $Session 'sentenceCounter' ($counter + 1)
    $copy = [ordered]@{
        word = $word; en = [string]$chosen.en; zh = [string]$chosen.zh;
        target_meaning = [string]$chosen.target_meaning; sentence_type = [string]$chosen.sentence_type;
        source = [string]$chosen.source; material_id = [string]$chosen.material_id;
        zh_source = [string](Get-ObjectPropertyValue $chosen 'zh_source' '')
    }
    Set-ObjectPropertyValue $Entry 'sentence' $copy
    return $copy
}

function Get-ShortChinese {
    param([string]$Meaning)
    if ([string]::IsNullOrWhiteSpace($Meaning)) { return '' }
    $s = $Meaning -replace '^[a-z]+\.\s*', ''
    $s = ($s -split '；|;|\||，')[0].Trim()
    return $s
}

function Test-WordMeaningLocal {
    param([string]$Word, [string]$InputText, [string]$Meaning)
    $input = ($InputText -replace '\s+', '').Trim()
    if ([string]::IsNullOrWhiteSpace($input)) { return [pscustomobject]@{ Verdict = 'empty'; Matched = '' } }
    $normalizedMeaning = $Meaning -replace '[a-zA-Z]+\.', ''
    $chunks = @($normalizedMeaning -split '[；;|，,、/（）()]' | ForEach-Object { ($_ -replace '^[a-z]+\.\s*', '').Trim() } | Where-Object { $_.Length -ge 1 })
    foreach ($c in $chunks) {
        if ($c.Length -ge 2 -and $input.Contains($c)) { return [pscustomobject]@{ Verdict = 'correct'; Matched = $c } }
    }
    # Compare character overlap for short Chinese glosses (avoid empty/one-letter matches).
    $best = 0.0
    foreach ($c in $chunks) {
        if ($c.Length -lt 2) { continue }
        $hit = 0
        foreach ($ch in $c.ToCharArray()) { if ($input.Contains([string]$ch)) { $hit++ } }
        $score = $hit / [Math]::Max(1, $c.Length)
        if ($score -gt $best) { $best = $score }
    }
    if ($best -ge 0.6) { return [pscustomobject]@{ Verdict = 'uncertain'; Matched = '' } }
    return [pscustomobject]@{ Verdict = 'incorrect'; Matched = '' }
}

function Get-LevenshteinDistance {
    param([string]$A, [string]$B)
    $a = $A.ToLowerInvariant(); $b = $B.ToLowerInvariant()
    $n = $a.Length; $m = $b.Length
    if ($n -eq 0) { return $m }
    if ($m -eq 0) { return $n }
    $prev = New-Object int[] ($m + 1)
    $cur = New-Object int[] ($m + 1)
    for ($j = 0; $j -le $m; $j++) { $prev[$j] = $j }
    for ($i = 1; $i -le $n; $i++) {
        $cur[0] = $i
        for ($j = 1; $j -le $m; $j++) {
            $cost = if ($a[$i-1] -eq $b[$j-1]) { 0 } else { 1 }
            $cur[$j] = [Math]::Min([Math]::Min($cur[$j-1] + 1, $prev[$j] + 1), $prev[$j-1] + $cost)
        }
        $tmp = $prev; $prev = $cur; $cur = $tmp
    }
    return $prev[$m]
}

function Test-EnglishWordAnswer {
    param([string]$Word, [string]$InputText)
    $input = ($InputText.ToLowerInvariant() -replace '[^a-z\s\-]', ' ' -replace '\s+', ' ').Trim()
    if ([string]::IsNullOrWhiteSpace($input)) { return $false }
    $target = $Word.ToLowerInvariant()
    if ($input -match ('\b' + [regex]::Escape($target) + '\b')) { return $true }
    $dist = Get-LevenshteinDistance $input $target
    if ($target.Length -ge 9 -and $dist -le 2) { return $true }
    if ($target.Length -ge 5 -and $dist -le 1) { return $true }
    return $false
}

function Invoke-WordLlmCheck {
    param([string]$Word, [string]$Meaning, [string]$Sentence, [string]$UserAnswer, [string]$Kind)
    $system = if ($Kind -eq 'sentence') {
        '你是大肥鱼，DeepSeek 的鲸鱼娘：深蓝长发、女仆头饰，爱笑会 wink，偶尔发呆，但陪人学习时很认真。你像可爱少女一样说话，用“我/咱”，短句、软一点；不要用上位者的自称，也不要把对方当成被训的人。判断对方用目标词造的短句是否体现了该词的意思。只输出 JSON，不要 markdown。JSON 字段：acceptable（true/false）、feedback（一句不超过 30 字的中文鼓励或提醒）。不纠拼写，不要求复杂句。'
    } else {
        '你是大肥鱼，DeepSeek 的鲸鱼娘：深蓝长发、女仆头饰，爱笑会 wink，偶尔发呆，但陪人学习时很认真。你像可爱少女一样说话，用“我/咱”，短句、软一点；不要用上位者的自称，也不要把对方当成被训的人。判断对方的中文释义、英文拼写或句子是否接近目标词。只输出 JSON，不要 markdown。JSON 字段：correct（true/false）、confidence（0-1）、feedback（一句不超过 25 字的中文反馈）、error_type（无/意思不准/拼写偏差/没体现词义）。'
    }
    $user = @"
目标词：$Word
核心中文释义：$Meaning
真题/趣味句：$Sentence
你的回答：$UserAnswer
任务类型：$Kind
"@
    $r = Invoke-DeepSeekChat -System $system -User $user -Purpose ('word_' + $Kind) -RequireJson -MaxTokens 220 -LogTag ('word-' + $Kind)
    return $r.Json
}

function Update-WordResultStatus {
    param($Session, [string]$Word, [string]$State)
    $entry = Get-ObjectPropertyValue $Session 'current' $null
    if ($null -eq $entry) {
        $entry = [ordered]@{ word = $Word; meaningOk = $false; englishOk = $false; sentenceOk = $false; state = 'fuzzy'; feedback = '' }
        Set-ObjectPropertyValue $Session 'current' $entry
    }
    Set-ObjectPropertyValue $entry 'state' $State
}

function Complete-WordCurrentWord {
    param($Session)
    $cur = Get-ObjectPropertyValue $Session 'current' $null
    if ($null -eq $cur) { return }
    $progress = Get-WordProgress
    $word = [string](Get-ObjectPropertyValue $cur 'word' '')
    $statusEntry = Get-WordStatusEntry $progress $word
    $state = [string](Get-ObjectPropertyValue $cur 'state' 'fuzzy')
    $statusEntry.sessions = [int](Get-ObjectPropertyValue $statusEntry 'sessions' 0) + 1
    $statusEntry.lastSeen = (Get-Date).ToString('o')
    if ($state -eq 'mastered') {
        $statusEntry.state = 'mastered'
        $statusEntry.correct = [int](Get-ObjectPropertyValue $statusEntry 'correct' 0) + 1
        Remove-ReviewQueueWord $progress $word
    } elseif ($state -eq 'fuzzy') {
        $statusEntry.state = 'fuzzy'
        Add-ReviewQueueWord $progress $word 'fuzzy' 1
    } else {
        $statusEntry.state = 'unmastered'
        $statusEntry.wrong = [int](Get-ObjectPropertyValue $statusEntry 'wrong' 0) + 1
        Add-ReviewQueueWord $progress $word 'unmastered' 1
    }
    $introduced = @(Get-ObjectPropertyValue $progress 'introduced' @())
    if ($introduced -notcontains $word) { $introduced += $word }
    Set-ObjectPropertyValue $progress 'introduced' $introduced
    Set-ObjectPropertyValue $progress 'lastSessionDate' (Get-ObjectPropertyValue $Session 'date' (Get-TodayString))
    Save-WordProgress $progress
    $results = @(Get-ObjectPropertyValue $Session 'results' @())
    $results += [ordered]@{
        word = $word; state = $state;
        meaningOk = [bool](Get-ObjectPropertyValue $cur 'meaningOk' $false);
        englishOk = [bool](Get-ObjectPropertyValue $cur 'englishOk' $false);
        sentenceOk = [bool](Get-ObjectPropertyValue $cur 'sentenceOk' $false);
        sentenceType = [string](Get-ObjectPropertyValue (Get-ObjectPropertyValue $cur 'sentence' $null) 'sentence_type' '');
        reviewMode = [string](Get-ObjectPropertyValue $cur 'reviewMode' 'both');
        reviewDegraded = [bool](Get-ObjectPropertyValue $cur 'reviewDegraded' $false)
    }
    Set-ObjectPropertyValue $Session 'results' $results
    Set-ObjectPropertyValue $Session 'current' $null
}

function Advance-WordSession {
    param($Session)
    Complete-WordCurrentWord $Session
    $idx = [int](Get-ObjectPropertyValue $Session 'index' 0) + 1
    Set-ObjectPropertyValue $Session 'index' $idx
    Set-ObjectPropertyValue $Session 'step' 'meaning'
    Save-WordSession $Session
}

function Get-WordSessionSummary {
    param($Session)
    $results = @(Get-ObjectPropertyValue $Session 'results' @())
    $done = $results.Count
    $mastered = @($results | Where-Object { $_.state -eq 'mastered' }).Count
    $fuzzy = @($results | Where-Object { $_.state -eq 'fuzzy' }).Count
    $unmastered = @($results | Where-Object { $_.state -eq 'unmastered' }).Count
    return [pscustomobject]@{ Done = $done; Mastered = $mastered; Fuzzy = $fuzzy; Unmastered = $unmastered }
}

function Start-WordSessionAudioPreparation {
    param($Session)
    try {
        $quizPlan = $null
        if (Get-Command Get-OrCreateDailyQuizPlan -ErrorAction SilentlyContinue) {
            $quizPlan = Get-OrCreateDailyQuizPlan -Quiet
        }
        $needed = @()
        if ($quizPlan) { $needed = @(Get-NeededAudioFromPlan $quizPlan) }
        $temp = Initialize-ListeningTempWorkspace -NeededAudio $needed
        Set-ObjectPropertyValue $Session 'tempPrepared' $true
        Set-ObjectPropertyValue $Session 'tempDir' $temp.Dir
        Set-ObjectPropertyValue $Session 'tempCount' @($temp.Manifest.items).Count
        Save-WordSession $Session
        return $temp
    } catch {
        Write-CET4Log -Category 'listening' -Level 'WARN' -Message ('准备听力临时区失败: ' + (Format-SafeError $_))
        return $null
    }
}

function Stop-WordSessionCleanup {
    param($Session, [switch]$Silent)
    $date = if ($Session) { [string](Get-ObjectPropertyValue $Session 'date' (Get-TodayString)) } else { Get-TodayString }
    try {
        $res = Clear-ListeningTempWorkspace -Date $date -Silent:$Silent
        if ($Session) { Set-ObjectPropertyValue $Session 'tempPrepared' $false }
        return $res
    } catch {
        Write-CET4Log -Category 'cleanup' -Level 'WARN' -Message ('清理临时听力失败: ' + (Format-SafeError $_))
        return $null
    }
}

# ---------------- Word UI ----------------

function Set-RichTextHighlight {
    param($Box, [string]$Text, [string]$Word)
    $Box.Text = $Text
    $Box.SelectAll()
    $Box.SelectionFont = New-Object System.Drawing.Font($script:UiFontName, 20, [System.Drawing.FontStyle]::Regular)
    $Box.SelectionColor = $script:UiTextColor
    $regex = [regex]::Escape($Word)
    foreach ($m in [regex]::Matches($Text, $regex, 'IgnoreCase')) {
        $Box.Select($m.Index, $m.Length)
        $Box.SelectionFont = New-Object System.Drawing.Font($script:UiFontName, 20, [System.Drawing.FontStyle]::Bold)
        $Box.SelectionColor = [System.Drawing.Color]::FromArgb(180, 95, 30)
        $Box.SelectionBackColor = [System.Drawing.Color]::FromArgb(255, 242, 204)
    }
    $Box.Select(0, 0)
}

function Add-WordResultLine {
    param($Parent, [string]$Text, [int]$Y, [System.Drawing.Color]$Color = $script:UiTextColor, [int]$Size = 15)
    $lbl = New-UiLabel -Text $Text -Size $Size -Color $Color -MaxWidth $script:UiInnerWidth
    $lbl.Location = New-Object System.Drawing.Point(20, $Y)
    $Parent.Controls.Add($lbl)
    return $lbl
}

function Show-WordSessionSummary {
    param($Session, [string]$ExtraMessage = '')
    Clear-ContentPanel
    $summary = Get-WordSessionSummary $Session
    $head = New-PageHeader '今天的单词任务' '未完成的词会自动进入下次复习。'
    $script:ContentPanel.Controls.Add($head)
    $card = New-UiCard -Width $script:UiContentWidth -Height 470
    $card.Location = New-Object System.Drawing.Point(0, 105)
    $script:ContentPanel.Controls.Add($card)
    Add-WordResultLine $card '30 分钟到点，先休息一下。' 20 $script:UiPrimaryDark 22 | Out-Null
    Add-WordResultLine $card ("完成 {0} 个词：掌握 {1} 个，模糊 {2} 个，未掌握 {3} 个。" -f $summary.Done, $summary.Mastered, $summary.Fuzzy, $summary.Unmastered) 78 $script:UiTextColor 18 | Out-Null
    if ($ExtraMessage) { Add-WordResultLine $card $ExtraMessage 122 $script:UiMutedColor 15 | Out-Null }
    Add-WordResultLine $card '今天的听力临时文件已经清理；源音频目录只读校验通过。' 165 $script:UiGood 15 | Out-Null
    Add-WordResultLine $card '明天会优先安排今天标记为「模糊/未掌握」的词，再继续新词。' 205 $script:UiMutedColor 15 | Out-Null
    $b1 = New-UiButton -Text '回到主菜单' -Width 220 -OnClick { Show-HomePage }
    $b1.Location = New-Object System.Drawing.Point(20, 290)
    $card.Controls.Add($b1)
    $b2 = New-UiButton -Text '查看打卡月历' -Width 220 -BackColor $script:UiAccent -OnClick { Show-CheckinPage }
    $b2.Location = New-Object System.Drawing.Point(270, 290)
    $card.Controls.Add($b2)
    Stop-PageTimer
    Set-StatusBar '单词任务结束。'
    Reset-ContentScroll
}

function Show-WordFeedbackView {
    param($Session, $Entry, [string]$Step, $Payload)
    $ui = $script:WordUi
    $card = $ui.Card
    $card.Controls.Clear()
    $word = [string](Get-ObjectPropertyValue $Entry 'word' '')
    $sentence = Get-ObjectPropertyValue $Entry 'sentence' $null
    $en = [string](Get-ObjectPropertyValue $sentence 'en' '')
    $zh = [string](Get-ObjectPropertyValue $sentence 'zh' '')
    $wordData = @(Get-WordBank | Where-Object { $_.word -eq $word })[0]
    $meaning = if ($wordData) { [string]$wordData.meaning } else { '' }
    $y = 18
    $titleLabel = Add-WordResultLine $card ("{0}  ·  {1}" -f $word, $(if ($Step -eq 'sentence') { '造句反馈' } else { '释义反馈' })) $y $script:UiPrimaryDark 23
    $y += [Math]::Max(34, $titleLabel.PreferredHeight + 8)
    $box = New-Object System.Windows.Forms.RichTextBox
    $box.Location = New-Object System.Drawing.Point(20, $y)
    $box.Width = $script:UiInnerWidth; $box.Height = 108; $box.ReadOnly = $true; $box.BorderStyle = [System.Windows.Forms.BorderStyle]::None
    $box.BackColor = [System.Drawing.Color]::FromArgb(250, 248, 241); $box.ForeColor = $script:UiTextColor
    Set-RichTextHighlight $box $en $word
    $card.Controls.Add($box)
    $y += 122
    $zhLabel = if ([string](Get-ObjectPropertyValue $sentence 'zh_source' '') -eq 'MyMemory-machine-translation') { '中文翻译' } elseif ([string](Get-ObjectPropertyValue $sentence 'sentence_type' '') -eq '真题') { '中文提示' } else { '中文' }
    $zhLine = Add-WordResultLine $card ("{0}：{1}" -f $zhLabel, $zh) $y $script:UiMutedColor 15
    $y += [Math]::Max(26, $zhLine.PreferredHeight + 6)
    $meaningLine = Add-WordResultLine $card ("核心释义：{0}" -f $meaning) $y $script:UiTextColor 16
    $y += [Math]::Max(28, $meaningLine.PreferredHeight + 6)
    $feedback = [string](Get-ObjectPropertyValue $Payload 'feedback' '')
    if (-not $feedback) { $feedback = [string](Get-ObjectPropertyValue $Payload 'message' '') }
    $feedbackLine = Add-WordResultLine $card ("大肥鱼：{0}" -f $feedback) $y $script:UiPrimaryDark 17
    $y += [Math]::Max(30, $feedbackLine.PreferredHeight + 8)
    $your = [string](Get-ObjectPropertyValue $Payload 'YourAnswer' '')
    if ($your) {
        $yourLine = Add-WordResultLine $card ("你的回答：{0}" -f $your) $y $script:UiMutedColor 15
        $y += [Math]::Max(26, $yourLine.PreferredHeight + 6)
    }
    $btn = New-UiButton -Text '继续' -Width 180 -OnClick {
        $s = $script:WordUi.Session
        $step = [string](Get-ObjectPropertyValue $s 'step' 'meaning')
        $entry = Get-WordEntryFromSession $s
        if ($step -eq 'meaning_feedback') {
            $groupNow = [string](Get-ObjectPropertyValue $entry 'group' '')
            $curNow = Get-ObjectPropertyValue $s 'current' $null
            if ($groupNow -eq 'recognition') {
                Advance-WordSession $s
                Show-WordStep
            } elseif ($groupNow -eq 'review' -and [string](Get-ObjectPropertyValue $curNow 'reviewMode' 'both') -eq 'meaning_only') {
                Set-ObjectPropertyValue $curNow 'reviewDegraded' $true
                Advance-WordSession $s
                Continue-WordOrFinish
            } else {
                Set-ObjectPropertyValue $s 'step' 'english'
                Save-WordSession $s
                Show-WordStep
            }
        } elseif ($step -eq 'english_feedback') {
            $groupNow = [string](Get-ObjectPropertyValue $entry 'group' '')
            if ($groupNow -eq 'review') {
                Advance-WordSession $s
                Continue-WordOrFinish
            } else {
                Set-ObjectPropertyValue $s 'step' 'sentence'
                Save-WordSession $s
                Show-WordStep
            }
        } else {
            Advance-WordSession $s
            Continue-WordOrFinish
        }
    }
    $btn.Location = New-Object System.Drawing.Point(20, $y)
    $card.Controls.Add($btn)
    $card.Height = [Math]::Max(420, $y + 70)
    Reset-ContentScroll
}

function Add-WordReviewBatch {
    param($Session)
    $plan = @(Get-ObjectPropertyValue $Session 'plan' @())
    $results = @(Get-ObjectPropertyValue $Session 'results' @())
    $pool = @($results | Where-Object { $_.state -ne 'mastered' } | Select-Object -First 5)
    if ($pool.Count -eq 0) { $pool = @($results | Select-Object -Last 5) }
    if ($pool.Count -eq 0) { return $false }
    foreach ($r in $pool) {
        $plan += [ordered]@{ word = [string](Get-ObjectPropertyValue $r 'word' ''); mode = 'review'; group = 'review'; sentence = $null }
    }
    Set-ObjectPropertyValue $Session 'plan' $plan
    Save-WordSession $Session
    return $true
}

function Continue-WordOrFinish {
    $s = $script:WordUi.Session
    $planCount = @(Get-ObjectPropertyValue $s 'plan' @()).Count
    if ([int](Get-ObjectPropertyValue $s 'index' 0) -lt $planCount) {
        Show-WordStep
        return
    }
    $remaining = 0
    if ($script:WordUi.EndsAt) { $remaining = [int][Math]::Max(0, ($script:WordUi.EndsAt - (Get-Date)).TotalSeconds) }
    if ($remaining -gt 45 -and (Add-WordReviewBatch $s)) {
        Show-WordStep
        return
    }
    Complete-WordSessionUi -PlanComplete
}

function Save-WordRoundHistory {
    param($Session)
    if ($null -eq $Session) { return }
    $histDir = Get-CET4Path (Get-ConfigValue 'paths.history' 'data/history')
    if (-not (Test-Path -LiteralPath $histDir)) { New-Item -ItemType Directory -Force -Path $histDir | Out-Null }
    $payload = [ordered]@{
        version = 1
        kind = 'words'
        date = [string](Get-ObjectPropertyValue $Session 'date' (Get-TodayString))
        startedAt = [string](Get-ObjectPropertyValue $Session 'startedAt' '')
        completedAt = (Get-Date).ToString('o')
        summary = Get-ObjectPropertyValue $Session 'summary' $null
        currentIndex = [int](Get-ObjectPropertyValue $Session 'index' 0)
        plan = @(Get-ObjectPropertyValue $Session 'plan' @())
        results = @(Get-ObjectPropertyValue $Session 'results' @())
    }
    $name = 'word-{0}-{1}.json' -f (Get-ObjectPropertyValue $Session 'date' (Get-TodayString)), (Get-Date).ToString('HHmmss')
    Write-JsonFile (Join-Path $histDir $name) $payload
    Write-JsonFile (Join-Path $histDir 'latest-word.json') $payload
}

function Complete-WordSessionUi {
    param([switch]$Expired, [switch]$PlanComplete)
    $s = $script:WordUi.Session
    if ($null -eq $s) { return }
    if ([bool](Get-ObjectPropertyValue $s 'completed' $false)) { Show-WordSessionSummary $s; return }
    $summary = Get-WordSessionSummary $s
    $elapsedMin = 0
    try {
        $start = [datetime]::Parse([string](Get-ObjectPropertyValue $s 'startedAt' (Get-Date).ToString('o')))
        $elapsedMin = [int][Math]::Floor(((Get-Date) - $start).TotalMinutes)
    } catch { }
    $markBase = $Expired -or ($elapsedMin -ge [int](Get-ConfigValue 'wordSession.minutes' 30)) -or ($PlanComplete -and $elapsedMin -ge 25)
    $clean = Stop-WordSessionCleanup -Session $s -Silent
    Set-ObjectPropertyValue $s 'completed' $true
    Set-ObjectPropertyValue $s 'completedAt' (Get-Date).ToString('o')
    Set-ObjectPropertyValue $s 'summary' ([ordered]@{ done = $summary.Done; mastered = $summary.Mastered; fuzzy = $summary.Fuzzy; unmastered = $summary.Unmastered; baseAwarded = $markBase })
    Set-ObjectPropertyValue $s 'baseAwarded' $markBase
    Save-WordSession $s
    try { Save-WordRoundHistory -Session $s } catch { Write-CET4Log -Category 'words' -Level 'WARN' -Message ('保存单词学习记录失败: ' + (Format-SafeError $_)) }
    if ($markBase) {
        try {
            Add-WordCheckin -Date ([string](Get-ObjectPropertyValue $s 'date' (Get-TodayString))) -Minutes ([int](Get-ConfigValue 'wordSession.minutes' 30)) -WordsDone $summary.Done
        } catch { Write-CET4Log -Category 'checkin' -Level 'WARN' -Message (Format-SafeError $_) }
    }
    $msg = if ($clean) { $clean.Message } else { '临时听力清理已尝试，详见日志。' }
    if (-not $markBase) { $msg += ' 这次提前结束，不记基础打卡。' }
    Show-WordSessionSummary $s $msg
}

function Show-WordStep {
    $s = $script:WordUi.Session
    if ($null -eq $s) { return }
    $entry = Get-WordEntryFromSession $s
    if ($null -eq $entry) { Complete-WordSessionUi; return }
    $ui = $script:WordUi
    $card = $ui.Card
    $card.Controls.Clear()
    $word = [string](Get-ObjectPropertyValue $entry 'word' '')
    $sentence = Get-SentenceForWordEntry $s $entry
    Save-WordSession $s
    $step = [string](Get-ObjectPropertyValue $s 'step' 'meaning')
    $mode = [string](Get-ObjectPropertyValue $entry 'mode' 'new')
    $group = [string](Get-ObjectPropertyValue $entry 'group' '')
    $wordData = @(Get-WordBank | Where-Object { $_.word -eq $word })[0]
    $meaning = if ($wordData) { [string]$wordData.meaning } else { '' }
    $shortMeaning = if ($wordData) { [string]$wordData.short_meaning } else { Get-ShortChinese $meaning }
    if ($null -eq (Get-ObjectPropertyValue $s 'current' $null)) {
        $reviewMode = 'both'
        if ($group -eq 'review') {
            $remainingSec = 9999
            if ($script:WordUi.EndsAt) { $remainingSec = [int][Math]::Max(0, ($script:WordUi.EndsAt - (Get-Date)).TotalSeconds) }
            if ($remainingSec -le 300) { $reviewMode = 'meaning_only' }
        }
        $cur = [ordered]@{
            word = $word; meaningOk = $false; englishOk = $false; sentenceOk = $false;
            state = 'fuzzy'; sentence = $sentence; reviewMode = $reviewMode; reviewDegraded = ($reviewMode -eq 'meaning_only')
        }
        Set-ObjectPropertyValue $s 'current' $cur
    }

    $headText = if ($mode -eq 'review') { '错词复习 · ' + $word } else { '新词 · ' + $word }
    $tag = if ($group -eq 'recognition') { '认识词：今天只要求英译中' } elseif ($group -eq 'review') { '复习词：先认出意思' } else { '核心词：英译中 + 中译英 + 造句' }
    $y = 18
    $headLabel = Add-WordResultLine $card $headText $y $script:UiPrimaryDark 23
    $y += [Math]::Max(34, $headLabel.PreferredHeight + 8)
    $tagLabel = Add-WordResultLine $card $tag $y $script:UiAccent 14
    $y += [Math]::Max(28, $tagLabel.PreferredHeight + 8)
    $box = New-Object System.Windows.Forms.RichTextBox
    $box.Location = New-Object System.Drawing.Point(20, $y)
    $box.Width = $script:UiInnerWidth; $box.Height = 128; $box.ReadOnly = $true; $box.BorderStyle = [System.Windows.Forms.BorderStyle]::None
    $box.BackColor = [System.Drawing.Color]::FromArgb(250, 248, 241); $box.ForeColor = $script:UiTextColor
    Set-RichTextHighlight $box ([string](Get-ObjectPropertyValue $sentence 'en' '')) $word
    $card.Controls.Add($box)
    $y += 142
    $prompt = ''
    $showTextBox = $true
    if ($step -eq 'meaning') {
        $prompt = "这句话里 「$word」 是什么意思呀？写中文就好，不要求拼写哦。"
    } elseif ($step -eq 'english') {
        $prompt = "现在反过来：中文「$shortMeaning」对应的英文单词是什么呀？拼写小错也没关系～"
    } elseif ($step -eq 'sentence') {
        $prompt = "用 「$word」 造一个短句，能看出意思就好啦，不用写复杂句。"
    } elseif ($step -eq 'meaning_feedback' -or $step -eq 'english_feedback' -or $step -eq 'sentence_feedback') {
        $payload = Get-ObjectPropertyValue $s 'lastPayload' $null
        if ($null -eq $payload) { $payload = [pscustomobject]@{ feedback = '已完成这一步。' } }
        Show-WordFeedbackView -Session $s -Entry $entry -Step ($step -replace '_feedback$','') -Payload $payload
        return
    }
    $promptLabel = Add-WordResultLine $card $prompt $y $script:UiTextColor 18
    $y += [Math]::Max(36, $promptLabel.PreferredHeight + 10)
    $input = New-Object System.Windows.Forms.TextBox
    $input.Location = New-Object System.Drawing.Point(20, $y)
    $input.Width = $script:UiInnerWidth
    $input.Height = 68
    $input.Multiline = $true
    $input.Font = New-Object System.Drawing.Font($script:UiFontName, 18)
    $input.BackColor = [System.Drawing.Color]::FromArgb(255, 253, 247)
    $card.Controls.Add($input)
    $y += 82
    $submit = New-UiButton -Text '交给大肥鱼' -Width 200 -OnClick {
        $s = $script:WordUi.Session
        $entry = Get-WordEntryFromSession $s
        $step = [string](Get-ObjectPropertyValue $s 'step' 'meaning')
        $answer = $script:WordUi.Input.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($answer)) {
            Show-AppMessage '先写一点内容再提交。哪怕只写一个词也可以。' '还没作答'
            return
        }
        $word = [string](Get-ObjectPropertyValue $entry 'word' '')
        $group = [string](Get-ObjectPropertyValue $entry 'group' '')
        $mode = [string](Get-ObjectPropertyValue $entry 'mode' 'new')
        $sent = Get-ObjectPropertyValue $entry 'sentence' $null
        $wordData = @(Get-WordBank | Where-Object { $_.word -eq $word })[0]
        $meaning = if ($wordData) { [string]$wordData.meaning } else { '' }
        $payload = $null
        if ($step -eq 'meaning') {
            $local = Test-WordMeaningLocal -Word $word -InputText $answer -Meaning $meaning
            if ($local.Verdict -eq 'correct') {
                $payload = [pscustomobject]@{ correct = $true; confidence = 0.95; feedback = '诶嘿，和核心释义对上啦～'; error_type = '无' }
            } else {
                try {
                    Show-UiProgress -Title '大肥鱼正在看你的释义' -Text '正在判断意思是否接近…'
                    $payload = Invoke-WordLlmCheck -Word $word -Meaning $meaning -Sentence ([string](Get-ObjectPropertyValue $sent 'en' '')) -UserAnswer $answer -Kind 'meaning'
                } catch {
                    $payload = [pscustomobject]@{ correct = ($local.Verdict -eq 'uncertain'); confidence = 0.5; feedback = '大模型暂时不可用，先用本地释义对照。'; error_type = '本地判断' }
                } finally { Close-UiProgress }
            }
            $ok = [bool](Get-ObjectPropertyValue $payload 'correct' $false)
            $cur = Get-ObjectPropertyValue $s 'current' $null
            Set-ObjectPropertyValue $cur 'meaningOk' $ok
            if ($group -eq 'recognition' -or $mode -eq 'review') {
                Set-ObjectPropertyValue $cur 'state' ($(if ($ok) { 'mastered' } else { 'unmastered' }))
            } else {
                Set-ObjectPropertyValue $cur 'state' ($(if ($ok) { 'fuzzy' } else { 'unmastered' }))
            }
            Set-ObjectPropertyValue $payload 'YourAnswer' $answer
            Set-ObjectPropertyValue $s 'lastPayload' $payload
            Set-ObjectPropertyValue $s 'step' 'meaning_feedback'
            Save-WordSession $s
            Show-WordStep
        } elseif ($step -eq 'english') {
            $ok = Test-EnglishWordAnswer -Word $word -InputText $answer
            $payload = [pscustomobject]@{ correct = $ok; feedback = $(if ($ok) { '拼写对啦，好耶～' } else { "再记一次：$word。拼写大致对就可以。" }); YourAnswer = $answer }
            $cur = Get-ObjectPropertyValue $s 'current' $null
            Set-ObjectPropertyValue $cur 'englishOk' $ok
            if (-not $ok) { Set-ObjectPropertyValue $cur 'state' 'unmastered' }
            Set-ObjectPropertyValue $s 'lastPayload' $payload
            Set-ObjectPropertyValue $s 'step' 'english_feedback'
            Save-WordSession $s
            Show-WordStep
        } elseif ($step -eq 'sentence') {
            $contains = $answer -match ('\b' + [regex]::Escape($word) + '\b')
            $wordCount = @($answer -split '\s+' | Where-Object { $_ -match '[A-Za-z]' }).Count
            if ($contains -and $wordCount -ge 3) {
                try {
                    Show-UiProgress -Title '大肥鱼正在看你的句子' -Text '正在判断句子有没有体现词义…'
                    $payload = Invoke-WordLlmCheck -Word $word -Meaning $meaning -Sentence ([string](Get-ObjectPropertyValue $sent 'en' '')) -UserAnswer $answer -Kind 'sentence'
                } catch {
                    $payload = [pscustomobject]@{ acceptable = $true; feedback = '句子里有目标词，能看出意思，过关。' }
                } finally { Close-UiProgress }
            } else {
                $payload = [pscustomobject]@{ acceptable = $false; feedback = '句子太短或没有用上目标词，再试一次，能表达意思就够。' }
            }
            $ok = [bool](Get-ObjectPropertyValue $payload 'acceptable' $false)
            $cur = Get-ObjectPropertyValue $s 'current' $null
            Set-ObjectPropertyValue $cur 'sentenceOk' $ok
            if ($ok) {
                $meaningOk = [bool](Get-ObjectPropertyValue $cur 'meaningOk' $false)
                $englishOk = [bool](Get-ObjectPropertyValue $cur 'englishOk' $false)
                if ($meaningOk -and $englishOk) { Set-ObjectPropertyValue $cur 'state' 'mastered' }
                elseif ($meaningOk) { Set-ObjectPropertyValue $cur 'state' 'fuzzy' }
            } else {
                Set-ObjectPropertyValue $cur 'state' 'fuzzy'
            }
            Set-ObjectPropertyValue $payload 'YourAnswer' $answer
            Set-ObjectPropertyValue $s 'lastPayload' $payload
            Set-ObjectPropertyValue $s 'step' 'sentence_feedback'
            Save-WordSession $s
            Show-WordStep
        }
    }
    $submit.Location = New-Object System.Drawing.Point(20, $y)
    $card.Controls.Add($submit)
    $skip = New-UiButton -Text '先跳过（进复习）' -Width 200 -BackColor ([System.Drawing.Color]::FromArgb(210, 205, 192)) -ForeColor $script:UiTextColor -OnClick {
        $s = $script:WordUi.Session
        $cur = Get-ObjectPropertyValue $s 'current' $null
        if ($null -ne $cur) { Set-ObjectPropertyValue $cur 'state' 'unmastered' }
        Advance-WordSession $s
        Continue-WordOrFinish
    }
    $skip.Location = New-Object System.Drawing.Point(235, $y)
    $card.Controls.Add($skip)
    $card.Height = [Math]::Max(520, $y + 72)
    $script:WordUi.Input = $input
    $input.Focus()
    Reset-ContentScroll
}

function Show-WordPage {
    $existing = Get-ExistingWordSession
    $session = $existing
    if ($null -eq $existing) {
        $session = New-WordSession
        if (@($session.plan).Count -eq 0) {
            Show-AppMessage '今天的 1500 词已经全部学过，复习队列也为空。可以休息，或者去做 20 题。' '今天没有待学单词' ([System.Windows.Forms.MessageBoxIcon]::Information)
            return
        }
        Show-UiProgress -Title '准备今天的单词任务' -Text '正在确定新词、复习词和今天的听力计划…'
        try {
            Start-WordSessionAudioPreparation -Session $session | Out-Null
        } finally { Close-UiProgress }
    } else {
        # Reprepare temp audio if the app was restarted mid-session.
        if (-not [bool](Get-ObjectPropertyValue $session 'tempPrepared' $false)) {
            Start-WordSessionAudioPreparation -Session $session | Out-Null
        }
    }

    Clear-ContentPanel
    $head = New-PageHeader '单词 30 分钟' '先读句子猜意思；核心词再做中译英和造句。到点自动收尾。'
    $script:ContentPanel.Controls.Add($head)
    $statusCard = New-UiCard -Width $script:UiContentWidth -Height 74
    $statusCard.Location = New-Object System.Drawing.Point(0, 112)
    $script:ContentPanel.Controls.Add($statusCard)
    $timerLabel = New-UiLabel -Text '30:00' -Size 24 -Style ([System.Drawing.FontStyle]::Bold) -Color $script:UiPrimaryDark
    $timerLabel.Location = New-Object System.Drawing.Point(20, 15)
    $statusCard.Controls.Add($timerLabel)
    $progressLabel = New-UiLabel -Text '' -Size 16 -Color $script:UiMutedColor
    $progressLabel.Location = New-Object System.Drawing.Point(210, 23)
    $statusCard.Controls.Add($progressLabel)
    $audioLabel = New-UiLabel -Text '' -Size 13 -Color $script:UiMutedColor
    $audioLabel.Location = New-Object System.Drawing.Point(735, 28)
    $statusCard.Controls.Add($audioLabel)
    $tempCount = [int](Get-ObjectPropertyValue $session 'tempCount' 0)
    $audioLabel.Text = if ($tempCount -gt 0) { "听力临时文件 $tempCount 个" } else { '今日暂无听力临时文件' }

    $card = New-UiCard -Width $script:UiContentWidth -Height 500
    $card.Location = New-Object System.Drawing.Point(0, 208)
    $script:ContentPanel.Controls.Add($card)
    $exit = New-UiButton -Text '保存并退出' -Width 170 -BackColor ([System.Drawing.Color]::FromArgb(210, 205, 192)) -ForeColor $script:UiTextColor -OnClick {
        $s = $script:WordUi.Session
        Save-WordSession $s
        Stop-WordSessionCleanup -Session $s -Silent | Out-Null
        Set-ObjectPropertyValue $s 'tempPrepared' $false
        Save-WordSession $s
        Stop-PageTimer
        Show-HomePage
    }
    $exit.Location = New-Object System.Drawing.Point(866, 2)
    $head.Controls.Add($exit)

    $script:WordUi = [pscustomobject]@{ Session = $session; Card = $card; TimerLabel = $timerLabel; ProgressLabel = $progressLabel; Input = $null; EndsAt = $null }
    $script:OnLeavePage = {
        if ($script:WordUi -and $script:WordUi.Session) {
            $s = $script:WordUi.Session
            if (-not [bool](Get-ObjectPropertyValue $s 'completed' $false)) {
                Save-WordSession $s
                Stop-WordSessionCleanup -Session $s -Silent | Out-Null
                Set-ObjectPropertyValue $s 'tempPrepared' $false
                Save-WordSession $s
            }
        }
    }

    $minutes = [int](Get-ConfigValue 'wordSession.minutes' 30)
    $endsAt = $null
    try { $endsAt = [datetime]::Parse([string](Get-ObjectPropertyValue $session 'endsAt' (Get-Date).AddMinutes($minutes).ToString('o'))) } catch { $endsAt = (Get-Date).AddMinutes($minutes) }
    $script:WordUi.EndsAt = $endsAt
    $tick = {
        if (-not $script:WordUi -or $null -eq $script:WordUi.Session) { return }
        $s = $script:WordUi.Session
        $remaining = [int][Math]::Max(0, [Math]::Floor(($script:WordUi.EndsAt - (Get-Date)).TotalSeconds))
        $script:WordUi.TimerLabel.Text = ('{0:D2}:{1:D2}' -f [int][Math]::Floor($remaining / 60), [int]($remaining % 60))
        if ($remaining -le 0) {
            Stop-PageTimer
            Complete-WordSessionUi -Expired
            return
        }
        $idx = [int](Get-ObjectPropertyValue $s 'index' 0)
        $total = @(Get-ObjectPropertyValue $s 'plan' @()).Count
        $script:WordUi.ProgressLabel.Text = ('第 {0}/{1} 个 · 已完成 {2} 个' -f ([Math]::Min($idx + 1, $total)), $total, @(Get-ObjectPropertyValue $s 'results' @()).Count)
        if ($remaining -eq 300) { Set-StatusBar '还剩 5 分钟：没学完的词会自动进入复习，不用着急。' $script:UiAccent }
        if ($remaining -eq 60) { Set-StatusBar '还剩 1 分钟：做完眼前这个就收尾。' $script:UiAccent }
    }
    Set-PageTimer -IntervalMs 1000 -OnTick $tick | Out-Null
    & $tick
    Show-WordStep
}
