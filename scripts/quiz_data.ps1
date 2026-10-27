# quiz_data.ps1 - question bank, selection constraints, plan/session storage,
# wrong-book operations.  Kept separate from quiz.ps1 so the UI code stays readable.

$script:QuestionCache = $null
$script:MaterialCache = $null
$script:TechniqueCache = $null

function Get-QuestionBank {
    if ($null -eq $script:QuestionCache) {
        $base = @(Read-JsonFile (Get-ConfigValue 'paths.questions' 'data/questions.json') @() -Quiet)
        $overlay = @(Read-JsonFile (Get-CET4Path 'data/progress_overlay.json') @() -Quiet)
        $ids = @{}
        $merged = @()
        foreach ($q in $base) {
            $id = [string](Get-ObjectPropertyValue $q 'id' '')
            if ($id) { $ids[$id] = $true }
            $merged += $q
        }
        foreach ($q in $overlay) {
            $id = [string](Get-ObjectPropertyValue $q 'id' '')
            if ($id -and -not $ids.ContainsKey($id)) {
                $ids[$id] = $true
                $merged += $q
            }
        }
        $script:QuestionCache = $merged
    }
    return $script:QuestionCache
}

function Get-MaterialIndex {
    if ($null -eq $script:MaterialCache) {
        $script:MaterialCache = @{}
        foreach ($m in @(Read-JsonFile (Get-ConfigValue 'paths.materials' 'data/materials.json') @() -Quiet)) {
            if ($m.id) { $script:MaterialCache[[string]$m.id] = $m }
        }
    }
    return $script:MaterialCache
}

function Get-TechniqueBank {
    if ($null -eq $script:TechniqueCache) {
        $script:TechniqueCache = @(Read-JsonFile (Get-ConfigValue 'paths.techniques' 'data/techniques.json') @() -Quiet)
    }
    return $script:TechniqueCache
}

function Get-TypeDisplayName {
    param([string]$Type)
    $names = @{
        careful_reading = '仔细阅读'; listening_passage = '听力篇章'; listening_news = '短篇新闻';
        listening_long = '长对话'; matching = '长篇匹配'; cloze = '选词填空';
        writing = '写作'; translation = '翻译'
    }
    if ($names.ContainsKey($Type)) { return $names[$Type] }
    return $Type
}

function Get-TechniqueForType {
    param([string]$Type)
    $all = @(Get-TechniqueBank)
    $map = @{
        careful_reading = 'reading-locate'; listening_passage = 'listening-signal';
        listening_news = 'listening-signal'; listening_long = 'listening-signal';
        matching = 'matching-scan'; cloze = 'cloze-pos'
    }
    $id = $map[$Type]
    $found = @($all | Where-Object { $_.id -eq $id })[0]
    if (-not $found) { $found = @($all | Select-Object -First 1)[0] }
    return $found
}

function Get-TechniqueText {
    param([string]$Type)
    $t = Get-TechniqueForType $Type
    if (-not $t) { return '技巧：先读题干，再回原文/录音定位，找同义替换。' }
    return ("技巧：{0}" -f $t.action)
}

function Test-QuestionAudioAvailable {
    param($Question)
    $audio = Get-ObjectPropertyValue $Question 'audio' $null
    if ($null -eq $audio) { return $true }
    $suite = [string](Get-ObjectPropertyValue $audio 'suite' '')
    $section = [string](Get-ObjectPropertyValue $audio 'section' '')
    if (-not $suite -or -not $section) { return $false }
    return ($null -ne (Find-ListeningAudio -Suite $suite -Section $section))
}

function Get-RecentQuizQuestionIds {
    param([int]$Days = 7)
    $ids = @{}
    $cutoff = (Get-Date).AddDays(-$Days)
    $sessionsDir = Get-CET4Path (Get-ConfigValue 'paths.sessions' 'data/sessions')
    if (Test-Path -LiteralPath $sessionsDir) {
        foreach ($f in @(Get-ChildItem -LiteralPath $sessionsDir -File -Filter 'quiz-*.json' -ErrorAction SilentlyContinue)) {
            try {
                if ($f.LastWriteTime -lt $cutoff) { continue }
                $s = Read-JsonFile $f.FullName $null -Quiet
                if ($null -eq $s) { continue }
                foreach ($id in @(Get-ObjectPropertyValue $s 'questionIds' @())) { $ids[[string]$id] = $true }
            } catch { }
        }
    }
    $seenPath = Get-CET4Path 'data/progress_seen.json'
    if (Test-Path -LiteralPath $seenPath) {
        foreach ($x in @(Read-JsonFile $seenPath @() -Quiet)) {
            $at = [string](Get-ObjectPropertyValue $x 'at' '')
            if ($at) {
                try { if ([datetime]::Parse($at) -lt $cutoff) { continue } } catch { }
            }
            $id = [string](Get-ObjectPropertyValue $x 'id' '')
            if ($id) { $ids[$id] = $true }
        }
    }
    return $ids
}

function Select-QuizPool {
    param(
        [string]$Type,
        [int]$Count,
        [hashtable]$Excluded,
        [hashtable]$Recent,
        [array]$WrongPriority = @(),
        [switch]$AllowRecent
    )
    if ($Count -le 0) { return @() }
    $all = @(Get-QuestionBank | Where-Object { $_.type -eq $Type })
    $chosen = @()
    foreach ($w in $WrongPriority) {
        if ($chosen.Count -ge $Count) { break }
        if ($null -ne $w -and -not $Excluded.ContainsKey([string]$w.id) -and $w.type -eq $Type) {
            if ($Type -like 'listening*' -and -not (Test-QuestionAudioAvailable $w)) { continue }
            $chosen += $w; $Excluded[[string]$w.id] = $true
        }
    }
    $byYear = @{}
    foreach ($q in $all) {
        if ($Excluded.ContainsKey([string]$q.id)) { continue }
        if ((-not $AllowRecent) -and $Recent.ContainsKey([string]$q.id)) { continue }
        if ($q.type -like 'listening*' -and -not (Test-QuestionAudioAvailable $q)) { continue }
        $y = [string]$q.year
        if (-not $byYear.ContainsKey($y)) { $byYear[$y] = @() }
        $byYear[$y] += $q
    }
    $years = @($byYear.Keys | Sort-Object)
    foreach ($y in $years) { $byYear[$y] = @($byYear[$y] | Get-Random -Count $byYear[$y].Count) }
    $guard = 0
    while ($chosen.Count -lt $Count -and $years.Count -gt 0 -and $guard -lt 500) {
        $guard++
        $added = $false
        foreach ($y in $years) {
            if ($chosen.Count -ge $Count) { break }
            if ($byYear[$y].Count -gt 0) {
                $q = $byYear[$y][0]
                $byYear[$y] = @($byYear[$y] | Select-Object -Skip 1)
                if (-not $Excluded.ContainsKey([string]$q.id)) {
                    $chosen += $q; $Excluded[[string]$q.id] = $true; $added = $true
                }
            }
        }
        if (-not $added) { break }
    }
    return @($chosen | Select-Object -First $Count)
}

function Get-OrCreateDailyQuizPlan {
    param([switch]$Quiet)
    $date = Get-TodayString
    $planDir = Get-CET4Path 'data/plans'
    if (-not (Test-Path -LiteralPath $planDir)) { New-Item -ItemType Directory -Force -Path $planDir | Out-Null }
    $planPath = Join-Path $planDir ('quiz-' + $date + '.json')
    $existing = Read-JsonFile $planPath $null -Quiet
    if ($null -ne $existing -and @(Get-ObjectPropertyValue $existing 'questions' @()).Count -gt 0) { return $existing }
    if (-not $Quiet) { Show-UiProgress -Title '准备今天的 20 题' -Text '正在按题型比例、年份和 7 天去重规则选题…' }
    try {
        $all = @(Get-QuestionBank)
        if ($all.Count -eq 0) { throw '题库为空。请先导入 questions.json。' }
        $wrong = @(Read-JsonFile (Get-ConfigValue 'paths.wrongbook' 'data/wrongbook.json') @() -Quiet | Where-Object { [bool](Get-ObjectPropertyValue $_ 'active' $false) })
        $wrongQuestions = @()
        foreach ($w in $wrong) {
            $q = @($all | Where-Object { $_.id -eq [string](Get-ObjectPropertyValue $w 'id' '') })[0]
            if ($q) { $wrongQuestions += $q }
        }
        $recent = Get-RecentQuizQuestionIds -Days ([int](Get-ConfigValue 'quiz.recentDays' 7))
        $excluded = @{}
        $selected = @()
        $allowedTypes = @()
        $listeningAvailable = @($all | Where-Object { $_.type -eq 'listening_passage' -and (Test-QuestionAudioAvailable $_) }).Count -gt 0
        $note = ''
        if ($listeningAvailable) {
            $main = if ([int](Get-Date).Day % 2 -eq 0) { 'listening_passage' } else { 'careful_reading' }
            $secondary = if ($main -eq 'careful_reading') { 'listening_passage' } else { 'careful_reading' }
            $mix = if ([int](Get-Date).Day % 2 -eq 0) { 'matching' } else { 'cloze' }
            $allowedTypes = @($main, $secondary, $mix)
            $selected += @(Select-QuizPool -Type $main -Count 7 -Excluded $excluded -Recent $recent -WrongPriority $wrongQuestions)
            $selected += @(Select-QuizPool -Type $secondary -Count 7 -Excluded $excluded -Recent $recent -WrongPriority $wrongQuestions)
            $selected += @(Select-QuizPool -Type $mix -Count 6 -Excluded $excluded -Recent $recent -WrongPriority $wrongQuestions)
            $note = '含仔细阅读/听力篇章重点题型；本日混合题型：' + (Get-TypeDisplayName $mix)
        } else {
            $allowedTypes = @('careful_reading', 'matching', 'cloze')
            $note = '听力音频库为空或缺少篇章音频，已按规则跳过听力，改以仔细阅读为重点并混入两种阅读题型。'
            $selected += @(Select-QuizPool -Type 'careful_reading' -Count 14 -Excluded $excluded -Recent $recent -WrongPriority $wrongQuestions)
            $selected += @(Select-QuizPool -Type 'matching' -Count 3 -Excluded $excluded -Recent $recent -WrongPriority $wrongQuestions)
            $selected += @(Select-QuizPool -Type 'cloze' -Count 3 -Excluded $excluded -Recent $recent -WrongPriority $wrongQuestions)
        }
        if ($selected.Count -lt 20) {
            $need = 20 - $selected.Count
            foreach ($t in $allowedTypes) {
                if ($selected.Count -ge 20) { break }
                $extra = @(Select-QuizPool -Type $t -Count $need -Excluded $excluded -Recent $recent -WrongPriority @() -AllowRecent)
                $selected += $extra
                $need = 20 - $selected.Count
            }
            $note += ' 题库较小，部分题按「7 天后可重出」规则复用。'
        }
        if ($selected.Count -lt 20) { throw ("只选出 {0} 题，题库不足。请先导入题库。" -f $selected.Count) }
        $selected = @($selected | Select-Object -First 20 | Get-Random -Count 20)
        $focusCount = @($selected | Where-Object { $_.focus }).Count
        $typeCounts = @{}
        foreach ($q in $selected) {
            if (-not $typeCounts.ContainsKey($q.type)) { $typeCounts[$q.type] = 0 }
            $typeCounts[$q.type]++
        }
        $mainType = [string](@($typeCounts.GetEnumerator() | Sort-Object Value -Descending)[0].Key)
        $mainCount = [int]$typeCounts[$mainType]
        $plan = [ordered]@{
            date = $date
            createdAt = (Get-Date).ToString('o')
            questions = @($selected)
            type_counts = $typeCounts
            focus_count = $focusCount
            main_type = $mainType
            main_count = $mainCount
            note = $note
            recent_filter_days = 7
        }
        Write-JsonFile $planPath $plan
        return [pscustomobject]$plan
    } finally {
        if (-not $Quiet) { Close-UiProgress }
    }
}

function Get-QuizPlanPath {
    param([string]$Date = (Get-TodayString))
    return (Get-CET4Path (Join-Path 'data/plans' ('quiz-' + $Date + '.json')))
}

function Get-QuizSessionPath {
    param([string]$Date = (Get-TodayString))
    return (Get-CET4Path (Join-Path (Get-ConfigValue 'paths.sessions' 'data/sessions') ('quiz-' + $Date + '.json')))
}

function New-QuizSession {
    param($Plan)
    $minutes = [int](Get-ConfigValue 'quiz.minutes' 30)
    $now = Get-Date
    $session = [ordered]@{
        version = 1
        date = (Get-TodayString)
        startedAt = $now.ToString('o')
        endsAt = $now.AddMinutes($minutes).ToString('o')
        minutes = $minutes
        questionIds = @($Plan.questions | ForEach-Object { $_.id })
        index = 0
        results = @()
        current = $null
        completed = $false
        quizAwarded = $false
        tempPrepared = $false
        note = [string](Get-ObjectPropertyValue $Plan 'note' '')
    }
    Write-JsonFile (Get-QuizSessionPath) $session
    return [pscustomobject]$session
}

function Get-ExistingQuizSession {
    $s = Read-JsonFile (Get-QuizSessionPath) $null -Quiet
    if ($null -eq $s) { return $null }
    if ([bool](Get-ObjectPropertyValue $s 'completed' $false)) { return $null }
    return $s
}

function Save-QuizSession {
    param($Session)
    if ($null -eq $Session) { return }
    Write-JsonFile (Get-QuizSessionPath ([string](Get-ObjectPropertyValue $Session 'date' (Get-TodayString)))) $Session
    if (Get-Command Save-PortableProgress -ErrorAction SilentlyContinue) { try { Save-PortableProgress -Silent } catch { } }
}

function Get-QuizQuestionById {
    param([string]$Id)
    return @(Get-QuestionBank | Where-Object { $_.id -eq $Id })[0]
}

function Get-QuizMaterial {
    param($Question)
    if ($null -eq $Question) { return $null }
    $snap = Get-ObjectPropertyValue $Question 'material_snapshot' $null
    if ($null -ne $snap) { return $snap }
    $mid = [string](Get-ObjectPropertyValue $Question 'material_id' '')
    $idx = Get-MaterialIndex
    if ($idx.ContainsKey($mid)) { return $idx[$mid] }
    return $null
}

function Get-QuizAudioPath {
    param($Question)
    $audio = Get-ObjectPropertyValue $Question 'audio' $null
    if ($null -eq $audio) { return $null }
    $suite = [string](Get-ObjectPropertyValue $audio 'suite' '')
    $section = [string](Get-ObjectPropertyValue $audio 'section' '')
    $dir = Get-ListeningTempDir
    if (Test-Path -LiteralPath $dir) {
        $manifest = Read-JsonFile (Join-Path $dir 'manifest.json') $null -Quiet
        foreach ($item in @(Get-ObjectPropertyValue $manifest 'items' @())) {
            if ([string](Get-ObjectPropertyValue $item 'suite' '') -eq $suite -and [string](Get-ObjectPropertyValue $item 'section' '') -eq $section) {
                $p = [string](Get-ObjectPropertyValue $item 'temp_path' '')
                if ($p -and (Test-Path -LiteralPath $p)) { return $p }
            }
        }
    }
    return $null
}

function Get-WrongBookEntry {
    param([string]$Id)
    if (-not $Id) { return $null }
    $all = @(Read-JsonFile (Get-ConfigValue 'paths.wrongbook' 'data/wrongbook.json') @() -Quiet)
    return @($all | Where-Object { [string](Get-ObjectPropertyValue $_ 'id' '') -eq $Id })[0]
}

function Get-QuestionDisplayOptions {
    param($Question, $Current)
    if ($null -eq $Question) { return $null }
    $existing = Get-ObjectPropertyValue $Current 'optionOrder' $null
    if ($null -ne $existing -and @($existing).Count -gt 0) {
        return [pscustomobject]@{
            Options = @($existing)
            CorrectKey = [string](Get-ObjectPropertyValue $Current 'correctKey' $Question.answer)
            Shuffled = [bool](Get-ObjectPropertyValue $Current 'shuffled' $false)
        }
    }
    $options = @($Question.options)
    $previous = Get-WrongBookEntry ([string]$Question.id)
    $wrongBefore = $false
    if ($null -ne $previous) {
        $wrongBefore = ([int](Get-ObjectPropertyValue $previous 'wrongCount' 0) -ge 1)
    }
    $shuffled = $false
    $correctKey = [string]$Question.answer
    if ($wrongBefore -and $options.Count -ge 2 -and $options.Count -le 4) {
        $originalAnswer = [string]$Question.answer
        $answerText = ''
        foreach ($o in $options) {
            if ([string](Get-ObjectPropertyValue $o 'key' '') -eq $originalAnswer) { $answerText = [string](Get-ObjectPropertyValue $o 'text' '') }
        }
        if ([string]::IsNullOrWhiteSpace($answerText)) { $wrongBefore = $false }
    }
    if ($wrongBefore -and $options.Count -ge 2 -and $options.Count -le 4) {
        $originalAnswer = [string]$Question.answer
        $answerText = ''
        foreach ($o in $options) {
            if ([string](Get-ObjectPropertyValue $o 'key' '') -eq $originalAnswer) { $answerText = [string](Get-ObjectPropertyValue $o 'text' '') }
        }
        $shuffledOptions = @($options | Get-Random -Count $options.Count)
        $originalTextOrder = (@($options | ForEach-Object { [string](Get-ObjectPropertyValue $_ 'text' '') }) -join '||')
        $newTextOrder = (@($shuffledOptions | ForEach-Object { [string](Get-ObjectPropertyValue $_ 'text' '') }) -join '||')
        if ($shuffledOptions.Count -gt 1 -and $originalTextOrder -eq $newTextOrder) {
            $shuffledOptions = @($shuffledOptions | Select-Object -Skip 1) + @($shuffledOptions[0])
        }
        $keys = @('A', 'B', 'C', 'D')
        $newOptions = @()
        $idx = 0
        foreach ($o in $shuffledOptions) {
            $newKey = $keys[$idx]
            $text = [string](Get-ObjectPropertyValue $o 'text' '')
            $newOptions += [ordered]@{ key = $newKey; text = $text }
            if ($text -eq $answerText) { $correctKey = $newKey }
            $idx++
        }
        $options = $newOptions
        $shuffled = $true
    }
    return [pscustomobject]@{ Options = @($options); CorrectKey = $correctKey; Shuffled = $shuffled; Previous = $previous }
}

function Add-QuestionToWrongBook {
    param(
        $Question,
        [string]$UserAnswer,
        [string]$UserReason,
        [string]$ErrorType,
        [string]$Explanation,
        [string]$TeacherExplanation,
        [string]$Technique,
        [string]$SelectedText = '',
        [string]$CorrectKey = '',
        $DeepFeedback = $null,
        [switch]$Incomplete
    )
    if ($null -eq $Question) { return }
    $path = Get-ConfigValue 'paths.wrongbook' 'data/wrongbook.json'
    $all = @(Read-JsonFile $path @() -Quiet)
    $id = [string]$Question.id
    $entry = @($all | Where-Object { [string](Get-ObjectPropertyValue $_ 'id' '') -eq $id })[0]
    $now = (Get-Date).ToString('o')
    if ($null -eq $entry) {
        $entry = [pscustomobject]@{
            id = $id; type = $Question.type; year = $Question.year; paper_key = $Question.paper_key;
            stem = $Question.stem; options = $Question.options; answer = $Question.answer;
            userAnswer = $UserAnswer; userReason = $UserReason; errorType = $ErrorType;
            explanation = $Explanation; teacherExplanation = $TeacherExplanation; technique = $Technique;
            lastSelectedText = $SelectedText; lastCorrectKey = $CorrectKey; deepFeedback = $DeepFeedback;
            source = $Question.source; wrongCount = 1; firstWrongAt = $now; lastWrongAt = $now;
            masteredConsecutive = 0; active = $true; incomplete = [bool]$Incomplete;
            reviewCount = 1; learnedTwice = $false;
        }
        $all += $entry
    } else {
        Set-ObjectPropertyValue $entry 'userAnswer' $UserAnswer
        Set-ObjectPropertyValue $entry 'userReason' $UserReason
        Set-ObjectPropertyValue $entry 'errorType' $ErrorType
        Set-ObjectPropertyValue $entry 'explanation' $Explanation
        Set-ObjectPropertyValue $entry 'teacherExplanation' $TeacherExplanation
        Set-ObjectPropertyValue $entry 'technique' $Technique
        Set-ObjectPropertyValue $entry 'lastSelectedText' $SelectedText
        Set-ObjectPropertyValue $entry 'lastCorrectKey' $CorrectKey
        Set-ObjectPropertyValue $entry 'deepFeedback' $DeepFeedback
        Set-ObjectPropertyValue $entry 'lastWrongAt' $now
        Set-ObjectPropertyValue $entry 'wrongCount' ([int](Get-ObjectPropertyValue $entry 'wrongCount' 0) + 1)
        $newReviewCount = [int](Get-ObjectPropertyValue $entry 'reviewCount' 0) + 1
        Set-ObjectPropertyValue $entry 'reviewCount' $newReviewCount
        Set-ObjectPropertyValue $entry 'learnedTwice' ($newReviewCount -ge 2)
        Set-ObjectPropertyValue $entry 'masteredConsecutive' 0
        Set-ObjectPropertyValue $entry 'active' $true
        Set-ObjectPropertyValue $entry 'incomplete' ([bool]$Incomplete)
    }
    Write-JsonFile $path @($all)
}

function Register-CorrectWrongBookAnswer {
    param($Question, [bool]$ReasonOk = $true)
    if ($null -eq $Question) { return }
    $path = Get-ConfigValue 'paths.wrongbook' 'data/wrongbook.json'
    $all = @(Read-JsonFile $path @() -Quiet)
    $id = [string]$Question.id
    $entry = @($all | Where-Object { [string](Get-ObjectPropertyValue $_ 'id' '') -eq $id })[0]
    if ($null -eq $entry) { return }
    if (-not [bool](Get-ObjectPropertyValue $entry 'active' $false)) { return }
    $entry.reviewCount = [int](Get-ObjectPropertyValue $entry 'reviewCount' 0) + 1
    $entry.learnedTwice = ([int]$entry.reviewCount -ge 2)
    if (-not $ReasonOk) {
        Write-JsonFile $path @($all)
        return
    }
    $entry.masteredConsecutive = [int](Get-ObjectPropertyValue $entry 'masteredConsecutive' 0) + 1
    $entry.lastCorrectAt = (Get-Date).ToString('o')
    if ([int]$entry.masteredConsecutive -ge 2) {
        $entry.active = $false
        $entry.mastered = $true
        $entry.conqueredAt = (Get-Date).ToString('o')
    } else {
        $entry.active = $true
        $entry.conqueredOnce = $true
    }
    Write-JsonFile $path @($all)
}

function Get-IncompleteReviewIds {
    $w = @(Read-JsonFile (Get-ConfigValue 'paths.wrongbook' 'data/wrongbook.json') @() -Quiet)
    return @($w | Where-Object { [bool](Get-ObjectPropertyValue $_ 'incomplete' $false) -and [bool](Get-ObjectPropertyValue $_ 'active' $false) } | ForEach-Object { [string]$_.id })
}

function Format-QuestionOptionsForPrompt {
    param($Options)
    return (@($Options | ForEach-Object { '{0}) {1}' -f (Get-ObjectPropertyValue $_ 'key' ''), (Get-ObjectPropertyValue $_ 'text' '') }) -join "`n")
}

function Save-QuizRoundHistory {
    param($Session, $Questions)
    if ($null -eq $Session) { return }
    $histDir = Get-CET4Path (Get-ConfigValue 'paths.history' 'data/history')
    if (-not (Test-Path -LiteralPath $histDir)) { New-Item -ItemType Directory -Force -Path $histDir | Out-Null }
    $results = @(Get-ObjectPropertyValue $Session 'results' @())
    $qIndex = @{}
    foreach ($q in @($Questions)) { if ($q.id) { $qIndex[[string]$q.id] = $q } }
    $items = @()
    foreach ($r in $results) {
        $q = $qIndex[[string](Get-ObjectPropertyValue $r 'questionId' '')]
        if ($null -eq $q) { continue }
        $items += [ordered]@{
            questionId = $q.id
            type = $q.type
            year = $q.year
            paper_key = $q.paper_key
            stem = $q.stem
            options = $q.options
            answer = $q.answer
            selected = [string](Get-ObjectPropertyValue $r 'selected' '')
            reason = [string](Get-ObjectPropertyValue $r 'reason' '')
            correct = [bool](Get-ObjectPropertyValue $r 'correct' $false)
            answered = [bool](Get-ObjectPropertyValue $r 'answered' $false)
            errorType = [string](Get-ObjectPropertyValue $r 'errorType' '')
            reasonQuality = [string](Get-ObjectPropertyValue $r 'reasonQuality' '')
            replayCount = [int](Get-ObjectPropertyValue $r 'replayCount' 0)
            correctKey = [string](Get-ObjectPropertyValue $r 'correctKey' $q.answer)
            selectedText = [string](Get-ObjectPropertyValue $r 'selectedText' '')
            feedbackSource = [string](Get-ObjectPropertyValue $r 'feedbackSource' '')
            misconception = [string](Get-ObjectPropertyValue $r 'misconception' '')
            teacherExplanation = [string](Get-ObjectPropertyValue $r 'teacherExplanation' '')
            technique = [string](Get-ObjectPropertyValue $r 'technique' '')
            optionAnalysis = @(Get-ObjectPropertyValue $r 'optionAnalysis' @())
        }
    }
    $payload = [ordered]@{
        version = 1
        kind = 'quiz'
        date = [string](Get-ObjectPropertyValue $Session 'date' (Get-TodayString))
        startedAt = [string](Get-ObjectPropertyValue $Session 'startedAt' '')
        completedAt = (Get-Date).ToString('o')
        minutes = [int](Get-ConfigValue 'quiz.minutes' 30)
        summary = Get-ObjectPropertyValue $Session 'summary' $null
        results = $items
        note = [string](Get-ObjectPropertyValue $Session 'note' '')
    }
    $name = 'quiz-{0}-{1}.json' -f (Get-ObjectPropertyValue $Session 'date' (Get-TodayString)), (Get-Date).ToString('HHmmss')
    Write-JsonFile (Join-Path $histDir $name) $payload
    Write-JsonFile (Join-Path $histDir 'latest-quiz.json') $payload
}
