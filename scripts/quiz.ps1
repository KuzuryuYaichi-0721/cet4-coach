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

function Get-OptionTextByKey {
    param($Options, [string]$Key)
    foreach ($o in @($Options)) {
        if ([string](Get-ObjectPropertyValue $o 'key' '') -eq $Key) { return [string](Get-ObjectPropertyValue $o 'text' '') }
    }
    return ''
}

function Invoke-QuizEvaluation {
    param(
        $Question,
        [string]$Selected,
        [string]$Reason,
        [int]$ReplayCount,
        [bool]$LocalCorrect,
        $DisplayOptions,
        [string]$CorrectKey,
        $PreviousEntry
    )
    $opts = Format-QuestionOptionsForPrompt $DisplayOptions
    $selectedText = Get-OptionTextByKey $DisplayOptions $Selected
    $correctText = Get-OptionTextByKey $DisplayOptions $CorrectKey
    $previousText = ''
    if ($PreviousEntry) {
        $previousText = "上次选择：$([string](Get-ObjectPropertyValue $PreviousEntry 'userAnswer' ''))；上次错误类型：$([string](Get-ObjectPropertyValue $PreviousEntry 'errorType' ''))"
    }
    $system = '你是大肥鱼，DeepSeek 的鲸鱼娘：深蓝长发、女仆头饰，像第二张图那样爱笑会 wink，也像第四张图那样偶尔发呆。你说话像可爱少女，用“我/咱”，短句、软一点，但讲题要具体。不要用上位者的自称，也不要把对方当成被训的人。现在评价对方的选择题作答和一句话理由。只输出 JSON，不要 markdown。JSON 字段：reason_quality（好/一般/较差）、error_type（定位错/同义替换没认出/蒙对/没找到位置/没听到信号词/时间不够/无）、encouragement（不超过 20 字的中文鼓励）、misconception_hint（从对方的选择和理由看，可能卡在哪一步，一句话；不确定就写“需要看讲解”）。判断要具体，不要空泛。'
    $user = @"
题型：$(Get-TypeDisplayName $Question.type)
题干：$($Question.stem)
选项：
$opts
正确答案：$CorrectKey) $correctText
你选的：$Selected) $selectedText
你的理由：$Reason
回放次数：$ReplayCount
$previousText
"@
    try {
        $r = Invoke-DeepSeekChat -System $system -User $user -Purpose 'quiz_evaluation' -RequireJson -MaxTokens 320 -CacheParts $null -LogTag ('eval-' + $Question.id)
        $j = $r.Json
        if ($null -eq $j) { throw '没有解析出评估 JSON。' }
        $enc = [string](Get-ObjectPropertyValue $j 'encouragement' '')
        if ($enc.Length -gt 20) { $enc = $enc.Substring(0, 20) }
        return [pscustomobject]@{
            correct = $LocalCorrect
            reason_quality = [string](Get-ObjectPropertyValue $j 'reason_quality' '一般')
            error_type = [string](Get-ObjectPropertyValue $j 'error_type' '无')
            encouragement = $enc
            misconception_hint = [string](Get-ObjectPropertyValue $j 'misconception_hint' '')
            source = 'deepseek'
        }
    } catch {
        Write-CET4Log -Category 'quiz' -Level 'WARN' -Message ('作答评估失败，用本地判断: ' + (Format-SafeError $_))
        return [pscustomobject]@{
            correct = $LocalCorrect
            reason_quality = if ($LocalCorrect -and $Reason.Length -ge 6) { '一般（本地）' } else { '未评估' }
            error_type = if ($LocalCorrect) { '无' } elseif ($Reason.Length -lt 4) { '没找到位置' } else { '待复盘' }
            encouragement = if ($LocalCorrect) { '先稳住，再提速。' } else { '这题先记动作，不记答案。' }
            misconception_hint = if ($LocalCorrect) { '' } else { '从你的选项看，可能是定位到了词，但没确认它回答的是不是题目问的那件事。' }
            source = 'local'
        }
    }
}

function Get-LocalOptionGloss {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    if (-not (Get-Command Get-WordBank -ErrorAction SilentlyContinue)) { return '' }
    if ($null -eq $script:LocalGlossMap) {
        $script:LocalGlossMap = @{}
        foreach ($w in @(Get-WordBank)) {
            $k = ([string]$w.word).ToLowerInvariant()
            if ($k) { $script:LocalGlossMap[$k] = [string]$w.short_meaning }
        }
    }
    $stop = @{
        'the'='这/该'; 'a'='一个'; 'an'='一个'; 'is'='是'; 'are'='是'; 'was'='曾是'; 'were'='曾是';
        'it'='它'; 'its'='它的'; 'this'='这个'; 'that'='那个'; 'these'='这些'; 'those'='那些';
        'to'='去/向'; 'of'='的'; 'in'='在…里'; 'on'='在…上'; 'for'='为了'; 'with'='和'; 'by'='通过';
        'and'='和'; 'or'='或'; 'but'='但是'; 'not'='不'; 'no'='没有'; 'as'='作为'; 'at'='在';
        'be'='是'; 'been'='是'; 'being'='正在'; 'have'='有'; 'has'='有'; 'had'='有'; 'do'='做';
        'does'='做'; 'did'='做'; 'can'='能'; 'could'='能'; 'may'='可能'; 'might'='可能'; 'will'='将';
        'would'='会'; 'should'='应该'; 'from'='从'; 'than'='比'; 'more'='更'; 'most'='最';
        'what'='什么'; 'which'='哪个'; 'who'='谁'; 'when'='何时'; 'where'='哪里'; 'why'='为什么'; 'how'='如何'
    }
    $tokens = [regex]::Matches($Text, "[A-Za-z][A-Za-z'-]{1,}")
    $out = @()
    foreach ($m in $tokens) {
        if ($out.Count -ge 14) { break }
        $word = $m.Value.Trim("'-").ToLowerInvariant()
        if ($stop.ContainsKey($word)) { $out += ($word + '（' + $stop[$word] + '）'); continue }
        $meaning = $script:LocalGlossMap[$word]
        if (-not $meaning -and $word.Length -gt 4) {
            foreach ($suffix in @('ing','ed','es','s')) {
                if ($word.EndsWith($suffix)) {
                    $stem = $word.Substring(0, $word.Length - $suffix.Length)
                    $meaning = $script:LocalGlossMap[$stem]
                    if ($meaning) { break }
                }
            }
        }
        if ($meaning) {
            $first = ($meaning -split '[；;]')[0].Trim()
            $out += ($word + '（' + $first + '）')
        }
    }
    if ($out.Count -eq 0) { return '' }
    return '本地直译：' + ($out -join '；')
}

function Get-LocalTeacherFeedback {
    param(
        $Question,
        [string]$Selected,
        [bool]$Wrong,
        $DisplayOptions = $null,
        [string]$CorrectKey = '',
        $PreviousEntry = $null
    )
    if ($null -eq $DisplayOptions) { $DisplayOptions = @($Question.options) }
    if ([string]::IsNullOrWhiteSpace($CorrectKey)) { $CorrectKey = [string]$Question.answer }
    $analysis = [string]$Question.explanation
    if ($analysis.Length -gt 1600) { $analysis = $analysis.Substring(0, 1600) + '…' }
    $exam = switch -Wildcard ($Question.type) {
        'careful_reading' { '这题考回原文定位，再识别同义替换；不是考你背了多少生词。' }
        'listening_*' { '这题考预读选项，再抓信号词后的关键信息。' }
        'matching' { '这题考关键词定位，不需要逐字读完整段。' }
        'cloze' { '这题考词性和上下文搭配，先排除词性不对的词。' }
        default { '这题考定位和同义替换。' }
    }
    $optionAnalysis = @()
    foreach ($o in @($DisplayOptions)) {
        $key = [string](Get-ObjectPropertyValue $o 'key' '')
        $text = [string](Get-ObjectPropertyValue $o 'text' '')
        $verdict = '干扰项'
        $note = ''
        if ($key -eq $CorrectKey) {
            $verdict = '正确'
            $note = '这一项与原文/录音的定位句对应；重点看它和题干的同义替换，而不是只背字母。'
        } elseif ($key -eq $Selected) {
            $verdict = '你选的'
            $note = '你选了这个。它可能有原文原词，但没有回答题干问的那件事，或者把主语、范围、时态换掉了。'
        } else {
            $note = '不是本题答案。先判断它是否答非所问，再判断是否把原文的某个词偷换成了另一个意思。'
        }
        $optionAnalysis += [pscustomobject]@{ key = $key; text = $text; text_en = $text; text_zh = (Get-LocalOptionGloss $text); verdict = $verdict; analysis = $note }
    }
    $correctText = Get-OptionTextByKey $DisplayOptions $CorrectKey
    $userMis = if ($Wrong) {
        "从你的选择和理由看，可能卡在：把「出现了原文词」当成「回答了题干」。这次先回定位句，确认主语和转折词，再看选项。"
    } else { '' }
    $prev = ''
    if ($PreviousEntry) {
        $prev = "上次你选了 $([string](Get-ObjectPropertyValue $PreviousEntry 'userAnswer' ''))；这次请重点避免同一误区。"
    }
    return [pscustomobject]@{
        exam_point = $exam
        answer_choice = [pscustomobject]@{ key = $CorrectKey; text = $correctText; text_zh = (Get-LocalOptionGloss $correctText) }
        why_choose = if ($analysis) { $analysis } else { '正确答案对应原文/录音中的定位句；先找同义替换，再逐项排除。' }
        why_correct = if ($analysis) { $analysis } else { '正确答案对应原文/录音中的定位句；先找同义替换，再逐项排除。' }
        misconception = $userMis
        option_analysis = @($optionAnalysis)
        evidence = $analysis
        next_action = '下次先读题干圈关键词，再回原文/录音找同义替换；每个选项都要说出它错在哪。'
        technique = Get-TechniqueText $Question.type
        follow_up = @('不看答案，用一句话说出正确答案的依据。', '用一句话说出你上次选的选项为什么是陷阱。')
        source = 'local'
        deepUnavailable = $true
        previous_note = $prev
    }
}

function Get-StoredTeacherFeedback {
    param($Entry, $Question, [string]$Selected)
    if ($null -eq $Entry) { return $null }
    $stored = Get-ObjectPropertyValue $Entry 'deepFeedback' $null
    if ($null -ne $stored -and $null -ne (Get-ObjectPropertyValue $stored 'answer_choice' $null)) {
        $stored | Add-Member -NotePropertyName source -NotePropertyValue 'stored-deep' -Force
        return $stored
    }
    $local = Get-LocalTeacherFeedback -Question $Question -Selected $Selected -Wrong $true -DisplayOptions @($Question.options) -CorrectKey ([string]$Question.answer) -PreviousEntry $Entry
    $local.source = 'stored-summary'
    return $local
}

function Get-QuizTeacherFeedback {
    param(
        $Question,
        [string]$Selected,
        [string]$UserReason,
        [int]$ReplayCount,
        [bool]$Correct,
        $DisplayOptions,
        [string]$CorrectKey,
        $PreviousEntry,
        [switch]$SkipDeep
    )
    $technique = Get-TechniqueForType $Question.type
    $techText = if ($technique) { [string]$technique.action } else { '先读题干，再回原文/录音定位，找同义替换。' }
    if ($Correct) {
        $local = Get-LocalTeacherFeedback -Question $Question -Selected $Selected -Wrong $false -DisplayOptions $DisplayOptions -CorrectKey $CorrectKey -PreviousEntry $PreviousEntry
        $local.technique = $techText
        $local.deepUnavailable = $false
        return $local
    }
    if ($SkipDeep) {
        $stored = Get-StoredTeacherFeedback -Entry $PreviousEntry -Question $Question -Selected $Selected
        if ($null -ne $stored) { return $stored }
    }
    if (Test-DeepSeekKeyPresent) {
        try {
            $material = Get-QuizMaterial $Question
            $passage = ''
            if ($material) { $passage = [string](Get-ObjectPropertyValue $material 'text' ''); if (-not $passage) { $passage = [string](Get-ObjectPropertyValue $material 'transcript' '') } }
            if ($passage.Length -gt 3600) { $passage = $passage.Substring(0, 3600) + '…' }
            $analysis = [string]$Question.explanation
            if ($analysis.Length -gt 2600) { $analysis = $analysis.Substring(0, 2600) + '…' }
            $opts = Format-QuestionOptionsForPrompt $DisplayOptions
            $selectedText = Get-OptionTextByKey $DisplayOptions $Selected
            $correctText = Get-OptionTextByKey $DisplayOptions $CorrectKey
            $previousText = ''
            if ($PreviousEntry) {
                $previousText = "上次选择：$([string](Get-ObjectPropertyValue $PreviousEntry 'userAnswer' ''))；上次理由：$([string](Get-ObjectPropertyValue $PreviousEntry 'userReason' ''))；上次错误类型：$([string](Get-ObjectPropertyValue $PreviousEntry 'errorType' ''))"
            }
            $system = '你是大肥鱼，DeepSeek 的鲸鱼娘：深蓝长发、女仆头饰，爱笑、会 wink、偶尔发呆，但讲题认真。你说话像可爱少女，用“我/咱”，先贴贴再指出一个具体问题；不要用上位者的自称，也不要把对方当成被训的人。你的任务不是简单对答案，而是做一次针对这道题的深度诊断：先判断题型和命题点，再还原对方为什么会选这个错误选项，最后逐项分析所有选项。只输出 JSON，不要 markdown。禁止编造原文、数据、论文；每条依据必须能在给出的材料或参考解析中找到。不要用“语义场”“图式理论”等术语。'
            $user = @"
题型：$(Get-TypeDisplayName $Question.type)
题干：$($Question.stem)
选项：
$opts
正确答案：$CorrectKey) $correctText
你选的：$Selected) $selectedText
你的理由：$UserReason
回放次数：$ReplayCount
$previousText
原文/材料：
$passage
题库参考解析：
$analysis
请深度思考后输出：
- answer_choice：先明确告诉对方这道题选什么。字段 key（正确选项字母）、text（正确选项完整英文）、text_zh（正确选项的准确中文翻译）。
- why_choose：为什么选它。先用一句话给结论，再引用原文/录音定位句和同义替换，讲清“为什么不是别的”。
- exam_point：这道题具体考什么，一句话，必须落到本题。
- why_correct：正确答案为什么对，引用定位句/信号词，解释同义替换。
- misconception：从对方的选择和理由出发，推断他为什么会被这个选项吸引；不确定就用“从你的选择看，可能……”，不要武断。
- option_analysis：对 A/B/C/D 每一个选项逐项分析。每项字段 key、text_en（完整英文选项，不能省略）、text_zh（与 text_en 对应的准确中文翻译，不能只写中文）、verdict（正确/干扰项/无关项/相反项）、analysis（为什么选/不选，和原文哪里对应或偷换）。
- evidence：原文/录音依据，必须引用给出的材料；没有材料就写“本题材料不足，按参考解析”。
- next_action：下次做同类题的一个具体动作。
- technique：一条技巧，直接写动作，并注明依据类型（官方大纲/历年真题统计/公开教材/经验性技巧），不得编造具体数据。
- follow_up：2 个检测自己是否真懂的小问题。
语言要具体、深入、耐心，避免空泛。选择题必须给出“选什么”和“为什么”；每个选项必须中英对译，英文完整保留，中文紧跟在后面。
"@
            $cacheKey = 'quiz-deep:{0}:{1}:{2}:v4' -f $Question.id, $Selected, $CorrectKey
            $deepModel = [string](Get-ConfigValue 'llm.explanationModel' 'deepseek-chat')
            $r = Invoke-DeepSeekChat -System $system -User $user -Purpose 'quiz_explanation_deep' -RequireJson -CacheKey $cacheKey -MaxTokens ([int](Get-ConfigValue 'llm.explanationMaxTokens' 2400)) -Temperature ([double](Get-ConfigValue 'llm.explanationTemperature' 0.2)) -Model $deepModel -LogTag ('deep-' + $Question.id)
            $j = $r.Json
            if ($null -ne $j) {
                $parsedOptions = @()
                foreach ($oa in @(Get-ObjectPropertyValue $j 'option_analysis' @())) {
                    $parsedOptions += [pscustomobject]@{
                        key = [string](Get-ObjectPropertyValue $oa 'key' '')
                        text_en = [string](Get-ObjectPropertyValue $oa 'text_en' (Get-ObjectPropertyValue $oa 'text' ''))
                        text_zh = [string](Get-ObjectPropertyValue $oa 'text_zh' '')
                        verdict = [string](Get-ObjectPropertyValue $oa 'verdict' '')
                        analysis = [string](Get-ObjectPropertyValue $oa 'analysis' '')
                    }
                }
                $keys = @($DisplayOptions | ForEach-Object { [string](Get-ObjectPropertyValue $_ 'key' '') })
                $missing = @($keys | Where-Object { $k = $_; -not ($parsedOptions | Where-Object { $_.key -eq $k }) })
                if ($missing.Count -gt 0) {
                    $local = Get-LocalTeacherFeedback -Question $Question -Selected $Selected -Wrong $true -DisplayOptions $DisplayOptions -CorrectKey $CorrectKey -PreviousEntry $PreviousEntry
                    $localMap = @{}
                    foreach ($lo in @($local.option_analysis)) { $localMap[[string]$lo.key] = $lo }
                    foreach ($k in $missing) {
                        $fallback = $localMap[$k]
                        $fallbackText = if ($fallback) { [string]$fallback.analysis } else { '模型没有逐项覆盖这一项；先按原文定位句自己对照。' }
                        $parsedOptions += [pscustomobject]@{ key = $k; text_en = if ($fallback) { [string]$fallback.text_en } else { '' }; text_zh = if ($fallback) { [string]$fallback.text_zh } else { '' }; verdict = '本地补充'; analysis = $fallbackText }
                    }
                }
                foreach ($po in $parsedOptions) {
                    if (-not $po.text_en) { $po.text_en = Get-OptionTextByKey $DisplayOptions $po.key }
                    if (-not $po.text_zh) { $po.text_zh = Get-LocalOptionGloss $po.text_en }
                }
                $parsedOptions = @($parsedOptions | Sort-Object key)
                $answerChoice = Get-ObjectPropertyValue $j 'answer_choice' $null
                if ($null -eq $answerChoice) {
                    $answerChoice = [pscustomobject]@{ key = $CorrectKey; text = $correctText; text_zh = '' }
                }
                if (-not [string](Get-ObjectPropertyValue $answerChoice 'text' '')) {
                    Set-ObjectPropertyValue $answerChoice 'text' $correctText
                }
                if (-not [string](Get-ObjectPropertyValue $answerChoice 'text_zh' '')) {
                    Set-ObjectPropertyValue $answerChoice 'text_zh' (Get-LocalOptionGloss ([string](Get-ObjectPropertyValue $answerChoice 'text' '')))
                }
                return [pscustomobject]@{
                    exam_point = [string](Get-ObjectPropertyValue $j 'exam_point' '这题考定位和同义替换。')
                    answer_choice = $answerChoice
                    why_choose = [string](Get-ObjectPropertyValue $j 'why_choose' (Get-ObjectPropertyValue $j 'why_correct' ''))
                    why_correct = [string](Get-ObjectPropertyValue $j 'why_correct' '')
                    misconception = [string](Get-ObjectPropertyValue $j 'misconception' '')
                    option_analysis = @($parsedOptions)
                    evidence = [string](Get-ObjectPropertyValue $j 'evidence' '')
                    next_action = [string](Get-ObjectPropertyValue $j 'next_action' $techText)
                    technique = [string](Get-ObjectPropertyValue $j 'technique' $techText)
                    follow_up = @(Get-ObjectPropertyValue $j 'follow_up' @())
                    source = if ($r.Cached) { 'deepseek-cache' } else { 'deepseek-deep' }
                    deepUnavailable = $false
                    previous_note = $previousText
                }
            }
        } catch {
            Write-CET4Log -Category 'quiz' -Level 'WARN' -Message ('深度讲解生成失败，用本地解析: ' + (Format-SafeError $_))
        }
    }
    $local = Get-LocalTeacherFeedback -Question $Question -Selected $Selected -Wrong $true -DisplayOptions $DisplayOptions -CorrectKey $CorrectKey -PreviousEntry $PreviousEntry
    $local.technique = $techText
    return $local
}

function Get-FeedbackText {
    param($Feedback)
    if ($null -eq $Feedback) { return '' }
    $lines = @()
    $ac = Get-ObjectPropertyValue $Feedback 'answer_choice' $null
    if ($null -ne $ac) {
        $ak = [string](Get-ObjectPropertyValue $ac 'key' '')
        $at = [string](Get-ObjectPropertyValue $ac 'text' '')
        $az = [string](Get-ObjectPropertyValue $ac 'text_zh' '')
        if ($ak) { $lines += ('这道题选：{0}) {1}' -f $ak, $at) }
        if ($az) { $lines += ('中文：' + $az) }
    }
    $why = Get-ObjectPropertyValue $Feedback 'why_choose' ''
    if (-not $why) { $why = Get-ObjectPropertyValue $Feedback 'why_correct' '' }
    if ($why) { $lines += ('为什么选它：' + [string]$why) }
    if (Get-ObjectPropertyValue $Feedback 'exam_point' '') { $lines += ('这道题考什么：' + [string](Get-ObjectPropertyValue $Feedback 'exam_point' '')) }
    if (Get-ObjectPropertyValue $Feedback 'misconception' '') { $lines += ('你的误区：' + [string](Get-ObjectPropertyValue $Feedback 'misconception' '')) }
    $oa = @(Get-ObjectPropertyValue $Feedback 'option_analysis' @())
    if ($oa.Count -gt 0) {
        $lines += '逐项分析：'
        foreach ($o in $oa) {
            $k = [string](Get-ObjectPropertyValue $o 'key' '')
            $v = [string](Get-ObjectPropertyValue $o 'verdict' '')
            $a = [string](Get-ObjectPropertyValue $o 'analysis' '')
            $en = [string](Get-ObjectPropertyValue $o 'text_en' (Get-ObjectPropertyValue $o 'text' ''))
            $zh = [string](Get-ObjectPropertyValue $o 'text_zh' '')
            if ($en) { $lines += ("  {0}) 【{1}】{2}" -f $k, $v, $en) } else { $lines += ("  {0}) 【{1}】" -f $k, $v) }
            if ($zh) { $lines += ('     中文：' + $zh) }
            if ($a) { $lines += ('     为什么：' + $a) }
        }
    }
    if (Get-ObjectPropertyValue $Feedback 'evidence' '') { $lines += ('原文依据：' + [string](Get-ObjectPropertyValue $Feedback 'evidence' '')) }
    if (Get-ObjectPropertyValue $Feedback 'next_action' '') { $lines += ('下次动作：' + [string](Get-ObjectPropertyValue $Feedback 'next_action' '')) }
    if (Get-ObjectPropertyValue $Feedback 'technique' '') { $lines += ('技巧：' + [string](Get-ObjectPropertyValue $Feedback 'technique' '')) }
    $fu = @(Get-ObjectPropertyValue $Feedback 'follow_up' @())
    if ($fu.Count -gt 0) {
        $lines += '自测追问：'
        $i = 0
        foreach ($f in $fu) { $i++; $lines += ("  {0}. {1}" -f $i, [string]$f) }
    }
    if ([bool](Get-ObjectPropertyValue $Feedback 'deepUnavailable' $false)) {
        $lines += '说明：本次没有联网生成深度讲解，以上为本地解析。设置 DEEPSEEK_API_KEY 后，错题会调用深度讲解。'
    }
    return ($lines -join "`n`n")
}

function Add-ResultToSession {
    param($Session, $Question, [string]$Selected, [string]$Reason, [int]$ReplayCount, [bool]$Correct, $Evaluation, $Feedback, [string]$CorrectKey = '', $DisplayOptions = $null)
    $results = @(Get-ObjectPropertyValue $Session 'results' @())
    $results = @($results | Where-Object { [string](Get-ObjectPropertyValue $_ 'questionId' '') -ne [string]$Question.id })
    $results += [ordered]@{
        questionId = $Question.id
        type = $Question.type
        selected = $Selected
        answer = $Question.answer
        correctKey = $(if ($CorrectKey) { $CorrectKey } else { $Question.answer })
        selectedText = Get-OptionTextByKey $DisplayOptions $Selected
        optionOrder = @($DisplayOptions)
        reason = $Reason
        replayCount = $ReplayCount
        correct = $Correct
        answered = $true
        errorType = [string](Get-ObjectPropertyValue $Evaluation 'error_type' '')
        reasonQuality = [string](Get-ObjectPropertyValue $Evaluation 'reason_quality' '')
        feedbackSource = [string](Get-ObjectPropertyValue $Feedback 'source' '')
        misconception = [string](Get-ObjectPropertyValue $Feedback 'misconception' '')
        teacherExplanation = Get-FeedbackText $Feedback
        technique = [string](Get-ObjectPropertyValue $Feedback 'technique' '')
        optionAnalysis = @(Get-ObjectPropertyValue $Feedback 'option_analysis' @())
    }
    if (Get-Command Add-ProgressSeen -ErrorAction SilentlyContinue) { try { Add-ProgressSeen -Question $Question -Selected $Selected -Correct $Correct } catch { } }
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
    $head = New-PageHeader '20 题 · 30 分钟' '先选答案，再用一句话说理由；大肥鱼会把错题拆开讲给你听。'
    $script:ContentPanel.Controls.Add($head)
    $status = New-UiCard -Width $script:UiContentWidth -Height 78
    $status.Location = New-Object System.Drawing.Point(0, 112)
    $script:ContentPanel.Controls.Add($status)
    $timer = New-UiLabel -Text '30:00' -Size 24 -Style ([System.Drawing.FontStyle]::Bold) -Color $script:UiPrimaryDark
    $timer.Location = New-Object System.Drawing.Point(18, 15)
    $status.Controls.Add($timer)
    $progress = New-UiLabel -Text '' -Size 16 -Color $script:UiMutedColor
    $progress.Location = New-Object System.Drawing.Point(200, 24)
    $status.Controls.Add($progress)
    $focus = New-UiLabel -Text ("重点题 {0}/20 · 主攻 {1}" -f [int](Get-ObjectPropertyValue $plan 'focus_count' 0), (Get-TypeDisplayName ([string](Get-ObjectPropertyValue $plan 'main_type' '')))) -Size 13 -Color $script:UiMutedColor
    $focus.Location = New-Object System.Drawing.Point(735, 28)
    $status.Controls.Add($focus)
    $card = New-UiCard -Width $script:UiContentWidth -Height 680
    $card.Location = New-Object System.Drawing.Point(0, 208)
    $script:ContentPanel.Controls.Add($card)
    $exit = New-UiButton -Text '保存并退出' -Width 160 -BackColor ([System.Drawing.Color]::FromArgb(210, 205, 192)) -ForeColor $script:UiTextColor -OnClick {
        $s = $script:QuizUi.Session
        Save-QuizSession $s
        try { Clear-ListeningTempWorkspace -Silent | Out-Null; Set-ObjectPropertyValue $s 'tempPrepared' $false; Save-QuizSession $s } catch { }
        Stop-PageTimer
        Show-HomePage
    }
    $exit.Location = New-Object System.Drawing.Point(866, 2)
    $head.Controls.Add($exit)

    $script:QuizUi = [pscustomobject]@{
        Session = $session; Plan = $plan; Questions = $questions; Card = $card;
        TimerLabel = $timer; ProgressLabel = $progress; ReminderLabel = $null;
        OptionControls = $null; ReasonBox = $null; EndsAt = $null; ShownFeedback = $false;
        SkipRepeatCheck = $null;
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
            optionOrder = $null; correctKey = $null; shuffled = $false
        }
        Set-ObjectPropertyValue $s 'current' $cur
        Set-ObjectPropertyValue $s 'index' $idx
        Save-QuizSession $s
    }
    if ([bool](Get-ObjectPropertyValue $cur 'submitted' $false)) {
        Show-QuizFeedback
        return
    }
    $display = Get-QuestionDisplayOptions -Question $q -Current $cur
    if ($null -eq (Get-ObjectPropertyValue $cur 'optionOrder' $null)) {
        Set-ObjectPropertyValue $cur 'optionOrder' @($display.Options)
        Set-ObjectPropertyValue $cur 'correctKey' $display.CorrectKey
        Set-ObjectPropertyValue $cur 'shuffled' $display.Shuffled
        Save-QuizSession $s
    }
    $displayOptions = @($display.Options)
    $currentCorrectKey = [string](Get-ObjectPropertyValue $cur 'correctKey' $display.CorrectKey)
    $previous = Get-WrongBookEntry ([string]$q.id)
    $prevWrong = $false
    if ($previous) { $prevWrong = ([int](Get-ObjectPropertyValue $previous 'wrongCount' 0) -ge 1) }
    $learnedTwice = $false
    if ($previous) { $learnedTwice = [bool](Get-ObjectPropertyValue $previous 'learnedTwice' $false) }

    $ui.Card.Controls.Clear()
    $ui.SkipRepeatCheck = $null
    $ui.ShownFeedback = $false
    $y = 16
    $title = New-UiLabel -Text ("第 {0} 题 · {1} · {2} 分" -f ($idx + 1), (Get-TypeDisplayName $q.type), $q.point) -Size 21 -Style ([System.Drawing.FontStyle]::Bold) -Color $script:UiPrimaryDark
    $title.Location = New-Object System.Drawing.Point(20, $y)
    $ui.Card.Controls.Add($title)
    $source = New-UiLabel -Text ("{0} 年 {1} 月 · {2}" -f $q.year, $q.month, (Get-TypeDisplayName $q.type)) -Size 12 -Color $script:UiMutedColor
    $source.Location = New-Object System.Drawing.Point -ArgumentList 790, ($y + 6)
    $ui.Card.Controls.Add($source)
    $y += 42
    if ($previous -and $prevWrong) {
        $prevAnswer = [string](Get-ObjectPropertyValue $previous 'userAnswer' '')
        $prevError = [string](Get-ObjectPropertyValue $previous 'errorType' '')
        $prevLine = "上次你选了 $prevAnswer" + $(if ($prevError) { "（$prevError）" } else { '' }) + "。这次先重新定位，不要背上次的字母。"
        $prevLabel = New-UiLabel -Text $prevLine -Size 14 -Color $script:UiDanger -MaxWidth $script:UiInnerWidth
        $prevLabel.Location = New-Object System.Drawing.Point(22, $y)
        $ui.Card.Controls.Add($prevLabel)
        $y += [Math]::Max(28, $prevLabel.PreferredHeight + 8)
    }
    if ($display.Shuffled) {
        $shuffleLabel = New-UiLabel -Text '这次选项顺序已打乱：注意选项内容，不要按上次的 A/B/C/D 记答案。' -Size 14 -Color $script:UiAccent -MaxWidth $script:UiInnerWidth
        $shuffleLabel.Location = New-Object System.Drawing.Point(22, $y)
        $ui.Card.Controls.Add($shuffleLabel)
        $y += [Math]::Max(28, $shuffleLabel.PreferredHeight + 8)
    }

    $mat = Get-QuizMaterial $q
    if ($q.type -notlike 'listening*' -and $mat) {
        $passage = [string](Get-ObjectPropertyValue $mat 'text' '')
        if ($passage.Length -gt 0) {
            $pb = New-Object System.Windows.Forms.RichTextBox
            $pb.Location = New-Object System.Drawing.Point(20, $y)
            $pb.Width = $script:UiInnerWidth; $pb.Height = 175
            $pb.ReadOnly = $true; $pb.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
            $pb.BackColor = [System.Drawing.Color]::FromArgb(252, 250, 244); $pb.ForeColor = $script:UiTextColor
            $pb.Font = New-Object System.Drawing.Font($script:UiFontName, 14)
            $pb.Text = $passage
            $ui.Card.Controls.Add($pb)
            $pb.Add_DoubleClick({
                $s2 = $script:QuizUi.Session
                $q2 = $script:QuizUi.Questions[[int](Get-ObjectPropertyValue $s2 'index' 0)]
                Show-QuestionReadingWindow -Question $q2
            })
            $y += 188
        }
    }
    if ($q.type -like 'listening*') {
        $info = New-UiLabel -Text '先播放听力，听完再显示选项。有原音频用原音频；没有时用内置英语语音在本地生成 WAV（失败再尝试在线下载），PotPlayer 本地播放，播放结束自动删除。播放次数会记录。' -Size 15 -Color $script:UiMutedColor -MaxWidth ($script:UiContentWidth - 170)
        $info.Location = New-Object System.Drawing.Point(20, $y)
        $ui.Card.Controls.Add($info)
        $y += [Math]::Max(30, $info.PreferredHeight + 8)
        $play = New-UiButton -Text '播放听力' -Width 190 -Height 48 -OnClick {
            $s = $script:QuizUi.Session
            $cur = Get-ObjectPropertyValue $s 'current' $null
            $q = $script:QuizUi.Questions[[int](Get-ObjectPropertyValue $s 'index' 0)]
            $path = Get-QuizAudioPath $q
            $src = '原音频'
            $text = ''
            if (-not $path) {
                $text = Get-QuestionTranscript $q
                if (-not $text) {
                    Show-AppMessage '这道题没有听力原文，无法下载语音。' '听力音频' ([System.Windows.Forms.MessageBoxIcon]::Warning)
                    return
                }
                Show-UiProgress -Title '正在准备本地听力音频' -Text '用内置英语语音生成 WAV，再用 PotPlayer 本地播放；播放结束自动删除。'
                try {
                    $path = New-ListeningLocalAudio $q
                    if ($path) {
                        $src = '本地合成语音'
                    } else {
                        $path = New-ListeningDownloadedAudio $q
                        $src = '在线下载语音'
                    }
                } catch {
                    Close-UiProgress
                    Show-AppMessage ('听力音频准备失败：' + (Format-SafeError $_)) '听力音频' ([System.Windows.Forms.MessageBoxIcon]::Warning)
                    return
                } finally {
                    Close-UiProgress
                }
            }
            try {
                $playback = Start-ListeningPlayback -Path $path -DeleteAfterPlay:($src -ne '原音频')
                if ($src -ne '原音频' -and $playback.Process) { Register-ListeningFileCleanup -Path $path -ProcessId ([int]$playback.Process.Id) }
                $cur.replayCount = [int](Get-ObjectPropertyValue $cur 'replayCount' 0) + 1
                Set-ObjectPropertyValue $cur 'replayCount' $cur.replayCount
                Set-ObjectPropertyValue $s 'current' $cur
                Save-QuizSession $s
                $script:QuizUi.PlayCountLabel.Text = ('已播放 {0} 次' -f $cur.replayCount)
                Set-StatusBar ('已播放（{1}）；本次是第 {0} 次回放。' -f $cur.replayCount, $src)
            } catch {
                if ($src -ne '原音频') { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue }
                Show-AppMessage ('播放失败：' + (Format-SafeError $_)) '播放' ([System.Windows.Forms.MessageBoxIcon]::Warning)
            }
        }
        $play.Location = New-Object System.Drawing.Point(20, $y)
        $ui.Card.Controls.Add($play)
        $playCount = New-UiLabel -Text ('已播放 {0} 次' -f [int](Get-ObjectPropertyValue $cur 'replayCount' 0)) -Size 14 -Color $script:UiMutedColor
        $playCount.Location = New-Object System.Drawing.Point -ArgumentList 230, ($y + 12)
        $ui.Card.Controls.Add($playCount)
        $script:QuizUi | Add-Member -NotePropertyName PlayCountLabel -NotePropertyValue $playCount -Force
        $showOpts = New-UiButton -Text '我已听完，显示选项' -Width 230 -Height 48 -BackColor $script:UiAccent -OnClick {
            $s = $script:QuizUi.Session
            $cur = Get-ObjectPropertyValue $s 'current' $null
            Set-ObjectPropertyValue $cur 'optionsShown' $true
            Set-ObjectPropertyValue $s 'current' $cur
            Save-QuizSession $s
            Show-QuizQuestion
        }
        $showOpts.Location = New-Object System.Drawing.Point(440, $y)
        $ui.Card.Controls.Add($showOpts)
        $y += 62
        if (-not [bool](Get-ObjectPropertyValue $cur 'optionsShown' $false)) {
            $hint = New-UiLabel -Text '选项暂时隐藏。听力原文不会提前显示。' -Size 14 -Color $script:UiMutedColor
            $hint.Location = New-Object System.Drawing.Point(20, $y)
            $ui.Card.Controls.Add($hint)
            $ui.OptionControls = $null
            $ui.ReasonBox = $null
            $ui.Card.Height = [Math]::Max(520, $y + 40)
            Reset-ContentScroll
            return
        }
    }
    $stemLabel = New-UiLabel -Text ([string]$q.stem) -Size 18 -Style ([System.Drawing.FontStyle]::Bold) -Color $script:UiTextColor -MaxWidth $script:UiInnerWidth
    $stemLabel.Location = New-Object System.Drawing.Point(20, $y)
    $ui.Card.Controls.Add($stemLabel)
    $y += [Math]::Max(38, $stemLabel.PreferredHeight + 10)
    $opts = @($displayOptions)
    if ($opts.Count -le 4) {
        $flow = New-Object System.Windows.Forms.FlowLayoutPanel
        $flow.Location = New-Object System.Drawing.Point(20, $y)
        $flow.Width = $script:UiInnerWidth; $flow.Height = 170
        $flow.FlowDirection = [System.Windows.Forms.FlowDirection]::TopDown
        $flow.WrapContents = $false
        $flow.AutoScroll = $true
        foreach ($o in $opts) {
            $rb = New-Object System.Windows.Forms.RadioButton
            $rb.Text = ('{0}) {1}' -f (Get-ObjectPropertyValue $o 'key' ''), (Get-ObjectPropertyValue $o 'text' ''))
            $rb.Tag = [string](Get-ObjectPropertyValue $o 'key' '')
            $rb.Font = New-Object System.Drawing.Font($script:UiFontName, 15)
            $rb.AutoSize = $true
            $rb.MaximumSize = New-Object System.Drawing.Size(980, 0)
            $rb.Margin = New-Object System.Windows.Forms.Padding(0, 4, 0, 4)
            $flow.Controls.Add($rb)
        }
        $ui.Card.Controls.Add($flow)
        $ui.OptionControls = $flow
        $y += 180
    } else {
        $combo = New-Object System.Windows.Forms.ComboBox
        $combo.Location = New-Object System.Drawing.Point(20, $y)
        $combo.Width = $script:UiInnerWidth
        $combo.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
        $combo.Font = New-Object System.Drawing.Font($script:UiFontName, 15)
        foreach ($o in $opts) {
            $label = ('{0}) {1}' -f (Get-ObjectPropertyValue $o 'key' ''), (Get-ObjectPropertyValue $o 'text' ''))
            if ($label.Length -gt 140) { $label = $label.Substring(0, 140) + '…' }
            [void]$combo.Items.Add($label)
        }
        $combo.SelectedIndex = -1
        $ui.Card.Controls.Add($combo)
        $ui.OptionControls = $combo
        $y += 54
    }
    $reasonLabel = New-UiLabel -Text '用一句话说理由，例如「我选 B，因为原文 however 后面说……」。' -Size 14 -Color $script:UiMutedColor -MaxWidth $script:UiInnerWidth
    $reasonLabel.Location = New-Object System.Drawing.Point(20, $y)
    $ui.Card.Controls.Add($reasonLabel)
    $y += [Math]::Max(26, $reasonLabel.PreferredHeight + 6)
    $reasonBox = New-Object System.Windows.Forms.TextBox
    $reasonBox.Location = New-Object System.Drawing.Point(20, $y)
    $reasonBox.Width = $script:UiInnerWidth; $reasonBox.Height = 58; $reasonBox.Multiline = $true
    $reasonBox.Font = New-Object System.Drawing.Font($script:UiFontName, 15)
    $reasonBox.Text = [string](Get-ObjectPropertyValue $cur 'reason' '')
    $ui.Card.Controls.Add($reasonBox)
    $ui.ReasonBox = $reasonBox
    $y += 70
    $reminder = New-UiLabel -Text '' -Size 14 -Color $script:UiAccent -MaxWidth $script:UiInnerWidth
    $reminder.Location = New-Object System.Drawing.Point(20, $y)
    $reminder.Visible = $false
    $ui.Card.Controls.Add($reminder)
    $ui.ReminderLabel = $reminder
    $skipCheck = $null
    if ($learnedTwice) {
        $skipCheck = New-Object System.Windows.Forms.CheckBox
        $skipCheck.Text = '这题已学习两遍：跳过重复的逐项讲解，只看保存的要点（省钱、省时）'
        $skipCheck.Font = New-Object System.Drawing.Font($script:UiFontName, 14)
        $skipCheck.ForeColor = $script:UiPrimaryDark
        $skipCheck.AutoSize = $true
        $skipCheck.MaximumSize = New-Object System.Drawing.Size(1000, 0)
        $skipCheck.Checked = $true
        $skipCheck.Location = New-Object System.Drawing.Point(20, $y)
        $ui.Card.Controls.Add($skipCheck)
        $ui.SkipRepeatCheck = $skipCheck
        $y += [Math]::Max(32, $skipCheck.PreferredSize.Height + 8)
    }
    $submit = New-UiButton -Text '提交答案和理由' -Width 240 -Height 50 -OnClick {
        $s = $script:QuizUi.Session
        $cur = Get-ObjectPropertyValue $s 'current' $null
        $q = $script:QuizUi.Questions[[int](Get-ObjectPropertyValue $s 'index' 0)]
        $selected = Get-SelectedQuizOption
        $reason = [string]$script:QuizUi.ReasonBox.Text.Trim()
        if (-not $selected) { Show-AppMessage '先选一个答案。不会也先选一个，后面看讲解。' '还没选答案'; return }
        if ([string]::IsNullOrWhiteSpace($reason) -or $reason.Length -lt 4) { Show-AppMessage '用一句话说说为什么选它，哪怕理由是“我听到 but 后面像答案”。' '还差一句理由'; return }
        Set-ObjectPropertyValue $cur 'selected' $selected
        Set-ObjectPropertyValue $cur 'reason' $reason
        Save-QuizSession $s
        $displayOptions = @(Get-ObjectPropertyValue $cur 'optionOrder' @($q.options))
        $correctKey = [string](Get-ObjectPropertyValue $cur 'correctKey' $q.answer)
        $localCorrect = ($selected -eq $correctKey)
        $replay = [int](Get-ObjectPropertyValue $cur 'replayCount' 0)
        $previous = Get-WrongBookEntry ([string]$q.id)
        $skipDeep = $false
        if ($script:QuizUi.SkipRepeatCheck -and $script:QuizUi.SkipRepeatCheck.Checked) { $skipDeep = $true }
        Show-UiProgress -Title '大肥鱼正在看这道题' -Text '先判断对错，再还原你的思路并逐项分析…'
        try {
            $evaluation = Invoke-QuizEvaluation -Question $q -Selected $selected -Reason $reason -ReplayCount $replay -LocalCorrect $localCorrect -DisplayOptions $displayOptions -CorrectKey $correctKey -PreviousEntry $previous
            $feedback = Get-QuizTeacherFeedback -Question $q -Selected $selected -UserReason $reason -ReplayCount $replay -Correct $localCorrect -DisplayOptions $displayOptions -CorrectKey $correctKey -PreviousEntry $previous -SkipDeep:$skipDeep
            if ($localCorrect) {
                $reasonQ = [string](Get-ObjectPropertyValue $evaluation 'reason_quality' '')
                $reasonOk = ($reasonQ -notin @('较差', '未评估', ''))
                Register-CorrectWrongBookAnswer -Question $q -ReasonOk $reasonOk
            } else {
                Add-QuestionToWrongBook -Question $q -UserAnswer $selected -UserReason $reason -ErrorType ([string](Get-ObjectPropertyValue $evaluation 'error_type' '')) -Explanation (Get-FeedbackText $feedback) -TeacherExplanation (Get-FeedbackText $feedback) -Technique (Get-TechniqueText $q.type) -SelectedText (Get-OptionTextByKey $displayOptions $selected) -CorrectKey $correctKey -DeepFeedback $feedback
            }
            Add-ResultToSession -Session $s -Question $q -Selected $selected -Reason $reason -ReplayCount $replay -Correct $localCorrect -Evaluation $evaluation -Feedback $feedback -CorrectKey $correctKey -DisplayOptions $displayOptions
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
    $submit.Location = New-Object System.Drawing.Point(20, $y)
    $ui.Card.Controls.Add($submit)
    $skip = New-UiButton -Text '先跳过（记入待复习）' -Width 240 -Height 50 -BackColor ([System.Drawing.Color]::FromArgb(210, 205, 192)) -ForeColor $script:UiTextColor -OnClick {
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
    $skip.Location = New-Object System.Drawing.Point(280, $y)
    $ui.Card.Controls.Add($skip)
    $studyLabel = if ($q.type -like 'listening*') { '听不懂？逐词讲解' } else { '我不会，逐词讲解' }
    $study = New-UiButton -Text $studyLabel -Width 230 -Height 50 -BackColor ([System.Drawing.Color]::FromArgb(255, 209, 102)) -ForeColor $script:UiPrimaryDark -OnClick {
        $s2 = $script:QuizUi.Session
        $cur2 = Get-ObjectPropertyValue $s2 'current' $null
        $q2 = $script:QuizUi.Questions[[int](Get-ObjectPropertyValue $s2 'index' 0)]
        if ($cur2) { Set-ObjectPropertyValue $cur2 'usedHelp' $true; Set-ObjectPropertyValue $s2 'current' $cur2; Save-QuizSession $s2 }
        Show-QuestionStudyWindow -Question $q2
    }
    if ($script:UiContentWidth -lt 1020) { $study.Location = New-Object System.Drawing.Point(20, ($y + 60)) } else { $study.Location = New-Object System.Drawing.Point(540, $y) }
    $ui.Card.Controls.Add($study)
    $read = New-UiButton -Text '全屏阅读' -Width 170 -Height 50 -BackColor ([System.Drawing.Color]::FromArgb(224, 232, 255)) -ForeColor $script:UiPrimaryDark -OnClick {
        $s2 = $script:QuizUi.Session
        $q2 = $script:QuizUi.Questions[[int](Get-ObjectPropertyValue $s2 'index' 0)]
        Show-QuestionReadingWindow -Question $q2
    }
    if ($script:UiContentWidth -lt 1020) { $read.Location = New-Object System.Drawing.Point(270, ($y + 60)) } else { $read.Location = New-Object System.Drawing.Point(790, $y) }
    $ui.Card.Controls.Add($read)
    $ui.Card.Height = [Math]::Max(680, $y + $(if ($script:UiContentWidth -lt 1020) { 132 } else { 78 }))
    Reset-ContentScroll
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
    $mascot = New-MascotPicture $(if ($correct) { 'happy' } else { 'encourage' }) 104
    if ($mascot) { $mascot.Location = New-Object System.Drawing.Point(($script:UiContentWidth - 130), 12); $ui.Card.Controls.Add($mascot) }
    $ui.ShownFeedback = $true
    $y = 16
    $bannerColor = if ($correct) { $script:UiGood } else { $script:UiDanger }
    $title = New-UiLabel -Text $(if ($correct) { '诶嘿，答对啦 · 第 ' + ($idx + 1) + ' 题' } else { '唔…这题先记个小动作 · 第 ' + ($idx + 1) + ' 题' }) -Size 23 -Style ([System.Drawing.FontStyle]::Bold) -Color $bannerColor -MaxWidth ($script:UiContentWidth - 170)
    $title.Location = New-Object System.Drawing.Point(20, $y)
    $ui.Card.Controls.Add($title)
    $y += 42
    $enc = [string](Get-ObjectPropertyValue $ev 'encouragement' '')
    $reasonQ = [string](Get-ObjectPropertyValue $ev 'reason_quality' '')
    $err = [string](Get-ObjectPropertyValue $ev 'error_type' '')
    $correctKey = [string](Get-ObjectPropertyValue $cur 'correctKey' $q.answer)
    $summary = "你的答案：$(Get-ObjectPropertyValue $cur 'selected' '') · 正确答案：$correctKey · 理由质量：$reasonQ · 错误类型：$err"
    $sl = New-UiLabel -Text $summary -Size 15 -Color $script:UiMutedColor -MaxWidth ($script:UiContentWidth - 170)
    $sl.Location = New-Object System.Drawing.Point(20, $y)
    $ui.Card.Controls.Add($sl)
    $y += [Math]::Max(28, $sl.PreferredHeight + 6)
    if ($enc) {
        $el = New-UiLabel -Text ('大肥鱼：' + $enc) -Size 16 -Color $script:UiPrimaryDark -MaxWidth ($script:UiContentWidth - 170)
        $el.Location = New-Object System.Drawing.Point(20, $y)
        $ui.Card.Controls.Add($el)
        $y += [Math]::Max(28, $el.PreferredHeight + 6)
    }
    $prev = Get-WrongBookEntry ([string]$q.id)
    $learnedTwice = $false
    if ($prev) { $learnedTwice = [bool](Get-ObjectPropertyValue $prev 'learnedTwice' $false) }
    if ($learnedTwice) {
        $repeatLabel = New-UiLabel -Text '这题已学习两遍；下面保留要点。可以直接点「跳过重复内容」进入下一题，或用「下一题」正常继续。' -Size 14 -Color $script:UiAccent -MaxWidth ($script:UiContentWidth - 170)
        $repeatLabel.Location = New-Object System.Drawing.Point(20, $y)
        $ui.Card.Controls.Add($repeatLabel)
        $y += [Math]::Max(30, $repeatLabel.PreferredHeight + 6)
    }
    $box = New-Object System.Windows.Forms.RichTextBox
    $box.Location = New-Object System.Drawing.Point(20, $y)
    $box.Width = $script:UiInnerWidth; $box.Height = 330
    $box.ReadOnly = $true; $box.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $box.BackColor = [System.Drawing.Color]::FromArgb(252, 250, 244)
    $box.Font = New-Object System.Drawing.Font($script:UiFontName, 15)
    $text = Get-FeedbackText $fb
    if (-not $text) { $text = '这题没有额外解析。先记住动作：先读题干，再回原文/录音定位，找同义替换。' }
    $box.Text = $text
    $ui.Card.Controls.Add($box)
    $y += 344
    $srcLabel = New-UiLabel -Text ("讲解来源：{0} · 回放 {1} 次 · 本题选项{2}" -f (Get-ObjectPropertyValue $fb 'source' 'local'), (Get-ObjectPropertyValue $cur 'replayCount' 0), $(if ([bool](Get-ObjectPropertyValue $cur 'shuffled' $false)) { '已打乱' } else { '原顺序' })) -Size 12 -Color $script:UiMutedColor
    $srcLabel.Location = New-Object System.Drawing.Point(20, $y)
    $ui.Card.Controls.Add($srcLabel)
    $y += 30
    $next = New-UiButton -Text '下一题' -Width 200 -Height 50 -OnClick {
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
    $next.Location = New-Object System.Drawing.Point(20, $y)
    $ui.Card.Controls.Add($next)
    if ($learnedTwice) {
        $skipRepeat = New-UiButton -Text '跳过重复内容' -Width 220 -Height 50 -BackColor ([System.Drawing.Color]::FromArgb(210, 205, 192)) -ForeColor $script:UiTextColor -OnClick {
            $s = $script:QuizUi.Session
            Set-ObjectPropertyValue $s 'current' $null
            Set-ObjectPropertyValue $s 'index' ([int](Get-ObjectPropertyValue $s 'index' 0) + 1)
            Save-QuizSession $s
            if ([int](Get-ObjectPropertyValue $s 'index' 0) -ge $script:QuizUi.Questions.Count) { Complete-QuizRound } else { Show-QuizQuestion }
        }
        $skipRepeat.Location = New-Object System.Drawing.Point(235, $y)
        $ui.Card.Controls.Add($skipRepeat)
    }
    $ui.Card.Height = [Math]::Max(700, $y + 74)
    Reset-ContentScroll
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
    try { Save-QuizRoundHistory -Session $s -Questions $ui.Questions } catch { Write-CET4Log -Category 'quiz' -Level 'WARN' -Message ('保存本轮学习记录失败: ' + (Format-SafeError $_)) }
    if ($award) { try { Show-DailyProgressSaved } catch { } }
    Clear-ContentPanel
    $head = New-PageHeader '这一轮结束了' '先看结果，再看错题画像。错题已经在错题本里，次日会优先重出。'
    $script:ContentPanel.Controls.Add($head)
    $card = New-UiCard -Width $script:UiContentWidth -Height 430
    $card.Location = New-Object System.Drawing.Point(0, 112)
    $script:ContentPanel.Controls.Add($card)
    $l1 = New-UiLabel -Text ("答对 {0} / 已答 {1}" -f $summary.Correct, $summary.Answered) -Size 28 -Style ([System.Drawing.FontStyle]::Bold) -Color $script:UiPrimaryDark
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
    Reset-ContentScroll
}
