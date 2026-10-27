# Portable learning progress: export/import across app versions and question-bank updates.
# Identity is content-based (normalized stem + sorted option texts), not the database row id.

function Get-QuestionContentKey {
    param($Question)
    if ($null -eq $Question) { return '' }
    $stem = [string](Get-ObjectPropertyValue $Question 'stem' '')
    $stem = ([regex]::Replace($stem.ToLowerInvariant(), '[\s\p{P}\p{S}]+', ''))
    $opts = @()
    foreach ($o in @(Get-ObjectPropertyValue $Question 'options' @())) {
        $t = [string](Get-ObjectPropertyValue $o 'text' '')
        $opts += ([regex]::Replace($t.ToLowerInvariant(), '[\s\p{P}\p{S}]+', ''))
    }
    $opts = @($opts | Sort-Object)
    $raw = $stem + '|' + ($opts -join '|')
    if ([string]::IsNullOrWhiteSpace($raw)) { $raw = [string](Get-ObjectPropertyValue $Question 'id' '') }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($raw))
        return ([BitConverter]::ToString($bytes) -replace '-', '').ToLowerInvariant()
    } finally { $sha.Dispose() }
}

function Get-NormalizedStem {
    param([string]$Stem)
    return ([regex]::Replace($Stem.ToLowerInvariant(), '[\s\p{P}\p{S}]+', ''))
}

function Get-StemTokens {
    param([string]$Stem)
    $set = @{}
    foreach ($t in [regex]::Matches($Stem.ToLowerInvariant(), '[a-z0-9]+')) { $set[$t.Value] = $true }
    return $set
}

function Get-QuestionSnapshot {
    param($Question)
    if ($null -eq $Question) { return $null }
    $mat = Get-QuizMaterial $Question
    $matSnap = $null
    if ($null -ne $mat) {
        $matSnap = [ordered]@{
            id = [string](Get-ObjectPropertyValue $mat 'id' '')
            text = [string](Get-ObjectPropertyValue $mat 'text' '')
            transcript = [string](Get-ObjectPropertyValue $mat 'transcript' '')
        }
    } elseif ($null -ne (Get-ObjectPropertyValue $Question 'material_snapshot' $null)) {
        $matSnap = Get-ObjectPropertyValue $Question 'material_snapshot' $null
    }
    return [ordered]@{
        id = [string](Get-ObjectPropertyValue $Question 'id' '')
        contentKey = Get-QuestionContentKey $Question
        type = [string](Get-ObjectPropertyValue $Question 'type' '')
        year = Get-ObjectPropertyValue $Question 'year' 0
        month = Get-ObjectPropertyValue $Question 'month' 0
        paper_key = [string](Get-ObjectPropertyValue $Question 'paper_key' '')
        stem = [string](Get-ObjectPropertyValue $Question 'stem' '')
        options = @(Get-ObjectPropertyValue $Question 'options' @())
        answer = [string](Get-ObjectPropertyValue $Question 'answer' '')
        explanation = [string](Get-ObjectPropertyValue $Question 'explanation' '')
        point = Get-ObjectPropertyValue $Question 'point' 0
        focus = [bool](Get-ObjectPropertyValue $Question 'focus' $false)
        source = [string](Get-ObjectPropertyValue $Question 'source' '')
        material_snapshot = $matSnap
    }
}

function Get-ProgressOverlayPath {
    return (Get-CET4Path 'data/progress_overlay.json')
}

function Get-PortableProgressPath {
    $dir = Get-CET4Path (Get-ConfigValue 'paths.progress' 'data/progress')
    return (Join-Path $dir 'latest.cet4progress.json')
}

function Get-ProgressSeenPath {
    return (Get-CET4Path 'data/progress_seen.json')
}

function Add-ProgressSeen {
    param($Question, [string]$Selected = '', [bool]$Correct = $false)
    if ($null -eq $Question) { return }
    $p = Get-ProgressSeenPath
    $all = @(Read-JsonFile $p @() -Quiet)
    $key = Get-QuestionContentKey $Question
    $id = [string](Get-ObjectPropertyValue $Question 'id' '')
    $all = @($all | Where-Object { [string](Get-ObjectPropertyValue $_ 'contentKey' '') -ne $key })
    $all += [ordered]@{
        contentKey = $key
        id = $id
        date = (Get-TodayString)
        at = (Get-Date).ToString('o')
        selected = $Selected
        correct = [bool]$Correct
    }
    if (Test-Path (Split-Path -Parent $p)) { Write-JsonFile $p @($all) }
}
function Get-ProgressPackage {
    $wp = Get-WordProgress
    $status = @()
    if ($null -ne (Get-ObjectPropertyValue $wp 'status' $null)) {
        foreach ($p in $wp.status.PSObject.Properties) {
            $v = $p.Value
            $status += [ordered]@{
                word = [string]$p.Name
                state = [string](Get-ObjectPropertyValue $v 'state' 'new')
                correct = [int](Get-ObjectPropertyValue $v 'correct' 0)
                wrong = [int](Get-ObjectPropertyValue $v 'wrong' 0)
                lastSeen = Get-ObjectPropertyValue $v 'lastSeen' $null
                nextReview = Get-ObjectPropertyValue $v 'nextReview' $null
            }
        }
    }
    $checkin = Get-CheckinData
    $days = @()
    if ($null -ne (Get-ObjectPropertyValue $checkin 'days' $null)) {
        foreach ($p in $checkin.days.PSObject.Properties) {
            $v = $p.Value
            $days += [ordered]@{
                date = [string]$p.Name
                word = [bool](Get-ObjectPropertyValue $v 'word' $false)
                quiz = [bool](Get-ObjectPropertyValue $v 'quiz' $false)
                minutes = [int](Get-ObjectPropertyValue $v 'minutes' 0)
                quizCount = [int](Get-ObjectPropertyValue $v 'quizCount' 0)
            }
        }
    }
    $wrong = @(Read-JsonFile (Get-ConfigValue 'paths.wrongbook' 'data/wrongbook.json') @() -Quiet)
    $overlay = @(Read-JsonFile (Get-ProgressOverlayPath) @() -Quiet)
    $questions = @()
    $seen = @{}
    foreach ($w in @($wrong + $overlay)) {
        $snap = Get-QuestionSnapshot $w
        if ($null -eq $snap) { continue }
        $key = [string]$snap.contentKey
        if (-not $key) { $key = Get-QuestionContentKey $w }
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        $questions += [ordered]@{
            contentKey = $key
            id = [string](Get-ObjectPropertyValue $w 'id' (Get-ObjectPropertyValue $snap 'id' ''))
            type = $snap.type
            year = $snap.year
            month = $snap.month
            paper_key = $snap.paper_key
            stem = $snap.stem
            options = $snap.options
            answer = $snap.answer
            explanation = $snap.explanation
            point = $snap.point
            focus = $snap.focus
            source = $snap.source
            material_snapshot = $snap.material_snapshot
            wrongCount = [int](Get-ObjectPropertyValue $w 'wrongCount' 0)
            reviewCount = [int](Get-ObjectPropertyValue $w 'reviewCount' 0)
            learnedTwice = [bool](Get-ObjectPropertyValue $w 'learnedTwice' $false)
            masteredConsecutive = [int](Get-ObjectPropertyValue $w 'masteredConsecutive' 0)
            active = [bool](Get-ObjectPropertyValue $w 'active' $true)
            mastered = [bool](Get-ObjectPropertyValue $w 'mastered' $false)
            incomplete = [bool](Get-ObjectPropertyValue $w 'incomplete' $false)
            userAnswer = [string](Get-ObjectPropertyValue $w 'userAnswer' '')
            userReason = [string](Get-ObjectPropertyValue $w 'userReason' '')
            errorType = [string](Get-ObjectPropertyValue $w 'errorType' '')
            firstWrongAt = Get-ObjectPropertyValue $w 'firstWrongAt' $null
            lastWrongAt = Get-ObjectPropertyValue $w 'lastWrongAt' $null
            lastCorrectAt = Get-ObjectPropertyValue $w 'lastCorrectAt' $null
            technique = [string](Get-ObjectPropertyValue $w 'technique' '')
            deepFeedback = Get-ObjectPropertyValue $w 'deepFeedback' $null
        }
    }
    $bank = @(Get-QuestionBank)
    return [ordered]@{
        format = 'cet4coach-progress'
        schemaVersion = 2
        appVersion = [string](Get-ConfigValue 'version' '1.1.0')
        exportedAt = (Get-Date).ToString('o')
        bank = [ordered]@{ count = $bank.Count; fingerprint = (Get-QuestionContentKey ([pscustomobject]@{ stem = (($bank | ForEach-Object { $_.id }) -join ','); options = @() })) }
        words = [ordered]@{
            introduced = @(Get-ObjectPropertyValue $wp 'introduced' @())
            reviewQueue = @(Get-ObjectPropertyValue $wp 'reviewQueue' @())
            status = $status
            lastSessionDate = Get-ObjectPropertyValue $wp 'lastSessionDate' $null
        }
        checkins = [ordered]@{
            days = $days
            milestones = @(Get-ObjectPropertyValue $checkin 'milestones' @())
        }
        questions = @($questions)
        seen = @(Read-JsonFile (Get-ProgressSeenPath) @() -Quiet)
    }
}

function Export-LearningProgress {
    param([string]$Path = '', [switch]$Silent)
    if ([string]::IsNullOrWhiteSpace($Path)) { $Path = Get-PortableProgressPath }
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $pkg = Get-ProgressPackage
    Write-JsonFile $Path $pkg
    if (-not $Silent) {
        Write-CET4Log -Category 'progress' -Message ('导出进度包: ' + $Path + '，题目记录 ' + @($pkg.questions).Count)
    }
    return [pscustomobject]@{ Path = $Path; Words = @($pkg.words.status).Count; Questions = @($pkg.questions).Count; Checkins = @($pkg.checkins.days).Count }
}

function Save-PortableProgress {
    param([switch]$Silent)
    try {
        $p = Get-PortableProgressPath
        Export-LearningProgress -Path $p -Silent:$Silent | Out-Null
        $backup = Join-Path (Split-Path -Parent $p) ('backup-' + (Get-Date).ToString('yyyyMMdd') + '.cet4progress.json')
        Copy-Item $p $backup -Force -ErrorAction SilentlyContinue
    } catch {
        Write-CET4Log -Category 'progress' -Level 'WARN' -Message ('自动保存进度包失败: ' + (Format-SafeError $_))
    }
}

function Save-DailyProgress {
    param([switch]$Silent)
    $p = Get-PortableProgressPath
    Save-PortableProgress -Silent:$Silent
    $dir = Split-Path -Parent $p
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $date = (Get-Date).ToString('yyyyMMdd')
    $backup = Join-Path $dir ('backup-' + $date + '.cet4progress.json')
    if (Test-Path -LiteralPath $p) { Copy-Item $p $backup -Force -ErrorAction SilentlyContinue }
    $marker = Join-Path $dir ('notified-' + $date + '.flag')
    $first = -not (Test-Path -LiteralPath $marker)
    if ($first) {
        try { Set-Content -LiteralPath $marker -Value (Get-Date).ToString('o') -Encoding ascii } catch { }
    }
    return [pscustomobject]@{ FirstTime = $first; Package = $p; Backup = $backup; Date = $date }
}

function Show-DailyProgressSaved {
    try {
        $r = Save-DailyProgress -Silent
        if (-not $r.FirstTime) { return }
        $text = @"
今天的进度已经自动保存：
$($r.Package)

同日备份：
$($r.Backup)

建议把整个 data 文件夹复制到 U 盘或网盘；换电脑时用“设置与诊断 → 学习进度包 → 导出/导入”。
"@
        Set-StatusBar '今日进度已保存，建议备份 data 文件夹。'
        Show-AppMessage $text '今日进度已保存' ([System.Windows.Forms.MessageBoxIcon]::Information)
    } catch {
        Write-CET4Log -Category 'progress' -Level 'WARN' -Message ('每日保存提醒失败: ' + (Format-SafeError $_))
    }
}


function Resolve-QuestionRecord {
    param($Record, $Bank, $ByKey, $ByStem)
    if ($null -eq $Record) { return $null }
    $key = [string](Get-ObjectPropertyValue $Record 'contentKey' '')
    if (-not $key) { $key = Get-QuestionContentKey $Record }
    if ($key -and $ByKey.ContainsKey($key)) { return $ByKey[$key] }
    $stem = Get-NormalizedStem ([string](Get-ObjectPropertyValue $Record 'stem' ''))
    if ($stem -and $ByStem.ContainsKey($stem)) { return $ByStem[$stem][0] }
    $tokens = Get-StemTokens ([string](Get-ObjectPropertyValue $Record 'stem' ''))
    if ($tokens.Count -eq 0) { return $null }
    $best = $null
    $bestScore = 0.0
    foreach ($q in @($Bank)) {
        $qt = Get-StemTokens ([string](Get-ObjectPropertyValue $q 'stem' ''))
        $inter = 0
        foreach ($k in $tokens.Keys) { if ($qt.ContainsKey($k)) { $inter++ } }
        $union = $tokens.Count + $qt.Count - $inter
        if ($union -le 0) { continue }
        $score = $inter / $union
        if ($score -gt $bestScore) { $bestScore = $score; $best = $q }
    }
    if ($best -and $bestScore -ge 0.82) { return $best }
    return $null
}

function Merge-WordProgressPackage {
    param($Package)
    $wp = Get-WordProgress
    $introduced = @{}
    foreach ($w in @(Get-ObjectPropertyValue $wp 'introduced' @())) { $introduced[[string]$w] = $true }
    foreach ($w in @(Get-ObjectPropertyValue $Package.words 'introduced' @())) { $introduced[[string]$w] = $true }
    Set-ObjectPropertyValue $wp 'introduced' @($introduced.Keys)
    foreach ($s in @(Get-ObjectPropertyValue $Package.words 'status' @())) {
        $word = [string](Get-ObjectPropertyValue $s 'word' '')
        if (-not $word) { continue }
        $existing = $null
        $existingProp = $wp.status.PSObject.Properties[$word]
        if ($existingProp) { $existing = $existingProp.Value }
        if ($null -eq $existing) {
            $existing = [pscustomobject]@{ state = 'new'; correct = 0; wrong = 0; lastSeen = $null; nextReview = $null }
            $wp.status | Add-Member -NotePropertyName $word -NotePropertyValue $existing
        }
        $newSeen = [string](Get-ObjectPropertyValue $s 'lastSeen' '')
        $oldSeen = [string](Get-ObjectPropertyValue $existing 'lastSeen' '')
        if (-not $oldSeen -or ($newSeen -and $newSeen -gt $oldSeen)) {
            Set-ObjectPropertyValue $existing 'state' ([string](Get-ObjectPropertyValue $s 'state' 'new'))
            Set-ObjectPropertyValue $existing 'lastSeen' (Get-ObjectPropertyValue $s 'lastSeen' $null)
            Set-ObjectPropertyValue $existing 'nextReview' (Get-ObjectPropertyValue $s 'nextReview' $null)
        }
        Set-ObjectPropertyValue $existing 'correct' ([Math]::Max([int](Get-ObjectPropertyValue $existing 'correct' 0), [int](Get-ObjectPropertyValue $s 'correct' 0)))
        Set-ObjectPropertyValue $existing 'wrong' ([Math]::Max([int](Get-ObjectPropertyValue $existing 'wrong' 0), [int](Get-ObjectPropertyValue $s 'wrong' 0)))
    }
    $queue = @(@(Get-ObjectPropertyValue $wp 'reviewQueue' @()) + @(Get-ObjectPropertyValue $Package.words 'reviewQueue' @()))
    $byWord = @{}
    foreach ($q in $queue) {
        $word = [string](Get-ObjectPropertyValue $q 'word' $q)
        if (-not $word) { continue }
        if (-not $byWord.ContainsKey($word)) { $byWord[$word] = $q }
        else {
            $old = $byWord[$word]
            $oldAt = [string](Get-ObjectPropertyValue $old 'nextReview' '')
            $newAt = [string](Get-ObjectPropertyValue $q 'nextReview' '')
            if ($newAt -gt $oldAt) { $byWord[$word] = $q }
        }
    }
    Set-ObjectPropertyValue $wp 'reviewQueue' @($byWord.Values)
    $last = [string](Get-ObjectPropertyValue $Package.words 'lastSessionDate' '')
    if ($last -and $last -gt [string](Get-ObjectPropertyValue $wp 'lastSessionDate' '')) { Set-ObjectPropertyValue $wp 'lastSessionDate' $last }
    Save-WordProgress $wp
}

function Merge-CheckinPackage {
    param($Package)
    $c = Get-CheckinData
    foreach ($d in @(Get-ObjectPropertyValue $Package.checkins 'days' @())) {
        $date = [string](Get-ObjectPropertyValue $d 'date' '')
        if (-not $date) { continue }
        $existing = $null
        $prop = $c.days.PSObject.Properties[$date]
        if ($prop) { $existing = $prop.Value }
        if ($null -eq $existing) {
            $existing = [pscustomobject]@{ word = $false; quiz = $false; minutes = 0; quizCount = 0 }
            $c.days | Add-Member -NotePropertyName $date -NotePropertyValue $existing
        }
        if ([bool](Get-ObjectPropertyValue $d 'word' $false)) { Set-ObjectPropertyValue $existing 'word' $true }
        if ([bool](Get-ObjectPropertyValue $d 'quiz' $false)) { Set-ObjectPropertyValue $existing 'quiz' $true }
        Set-ObjectPropertyValue $existing 'minutes' ([Math]::Max([int](Get-ObjectPropertyValue $existing 'minutes' 0), [int](Get-ObjectPropertyValue $d 'minutes' 0)))
        Set-ObjectPropertyValue $existing 'quizCount' ([Math]::Max([int](Get-ObjectPropertyValue $existing 'quizCount' 0), [int](Get-ObjectPropertyValue $d 'quizCount' 0)))
    }
    $ms = @(@(Get-ObjectPropertyValue $c 'milestones' @()) + @(Get-ObjectPropertyValue $Package.checkins 'milestones' @()))
    Set-ObjectPropertyValue $c 'milestones' @($ms | Select-Object -Unique)
    Save-CheckinData $c
}

function New-WrongBookEntryFromRecord {
    param($Record)
    $id = [string](Get-ObjectPropertyValue $Record 'id' '')
    if (-not $id) { $id = 'import-' + ([string](Get-ObjectPropertyValue $Record 'contentKey' '')).Substring(0, 12) }
    return [pscustomobject]@{
        id = $id
        type = [string](Get-ObjectPropertyValue $Record 'type' '')
        year = Get-ObjectPropertyValue $Record 'year' 0
        paper_key = [string](Get-ObjectPropertyValue $Record 'paper_key' '')
        stem = [string](Get-ObjectPropertyValue $Record 'stem' '')
        options = @(Get-ObjectPropertyValue $Record 'options' @())
        answer = [string](Get-ObjectPropertyValue $Record 'answer' '')
        explanation = [string](Get-ObjectPropertyValue $Record 'explanation' '')
        source = [string](Get-ObjectPropertyValue $Record 'source' 'portable-progress')
        userAnswer = [string](Get-ObjectPropertyValue $Record 'userAnswer' '')
        userReason = [string](Get-ObjectPropertyValue $Record 'userReason' '')
        errorType = [string](Get-ObjectPropertyValue $Record 'errorType' '')
        technique = [string](Get-ObjectPropertyValue $Record 'technique' '')
        wrongCount = [int](Get-ObjectPropertyValue $Record 'wrongCount' 0)
        reviewCount = [int](Get-ObjectPropertyValue $Record 'reviewCount' 0)
        learnedTwice = [bool](Get-ObjectPropertyValue $Record 'learnedTwice' $false)
        masteredConsecutive = [int](Get-ObjectPropertyValue $Record 'masteredConsecutive' 0)
        active = [bool](Get-ObjectPropertyValue $Record 'active' $true)
        mastered = [bool](Get-ObjectPropertyValue $Record 'mastered' $false)
        incomplete = [bool](Get-ObjectPropertyValue $Record 'incomplete' $false)
        firstWrongAt = Get-ObjectPropertyValue $Record 'firstWrongAt' $null
        lastWrongAt = Get-ObjectPropertyValue $Record 'lastWrongAt' $null
        lastCorrectAt = Get-ObjectPropertyValue $Record 'lastCorrectAt' $null
        deepFeedback = Get-ObjectPropertyValue $Record 'deepFeedback' $null
        contentKey = [string](Get-ObjectPropertyValue $Record 'contentKey' '')
        imported_progress = $true
    }
}

function Merge-QuestionPackage {
    param($Package, $Bank, $ByKey, $ByStem)
    $wrongPath = Get-ConfigValue 'paths.wrongbook' 'data/wrongbook.json'
    $all = @(Read-JsonFile $wrongPath @() -Quiet)
    $overlayPath = Get-ProgressOverlayPath
    $overlay = @(Read-JsonFile $overlayPath @() -Quiet)
    $overlayByKey = @{}
    foreach ($o in $overlay) { $overlayByKey[[string](Get-ObjectPropertyValue $o 'contentKey' '')] = $o }
    $resolved = 0; $orphans = 0
    foreach ($r in @(Get-ObjectPropertyValue $Package 'questions' @())) {
        $target = Resolve-QuestionRecord -Record $r -Bank $Bank -ByKey $ByKey -ByStem $ByStem
        $key = [string](Get-ObjectPropertyValue $r 'contentKey' '')
        if (-not $key) { $key = Get-QuestionContentKey $r }
        $entry = $null; $targetId = $null
        if ($null -ne $target) {
            $targetId = [string](Get-ObjectPropertyValue $target 'id' '')
            $entry = @($all | Where-Object { [string](Get-ObjectPropertyValue $_ 'id' '') -eq $targetId })[0]
            if ($null -eq $entry) { $entry = @($all | Where-Object { [string](Get-ObjectPropertyValue $_ 'contentKey' '') -eq $key })[0] }
        }
        if ($null -eq $entry) {
            $entry = @($all | Where-Object { [string](Get-ObjectPropertyValue $_ 'contentKey' '') -eq $key })[0]
        }
        if ($null -eq $entry) { $entry = New-WrongBookEntryFromRecord $r }
        if ($null -ne $target) {
            Set-ObjectPropertyValue $entry 'id' $targetId
            Set-ObjectPropertyValue $entry 'stem' ([string](Get-ObjectPropertyValue $target 'stem' ''))
            Set-ObjectPropertyValue $entry 'options' @(Get-ObjectPropertyValue $target 'options' @())
            Set-ObjectPropertyValue $entry 'answer' ([string](Get-ObjectPropertyValue $target 'answer' ''))
            Set-ObjectPropertyValue $entry 'type' ([string](Get-ObjectPropertyValue $target 'type' ''))
            Set-ObjectPropertyValue $entry 'imported_progress' $false
            $resolved++
        } else {
            Set-ObjectPropertyValue $entry 'id' ([string](Get-ObjectPropertyValue $r 'id' ('import-' + $key.Substring(0, [Math]::Min(12, $key.Length)))))
            Set-ObjectPropertyValue $entry 'imported_progress' $true
            $orphans++
            if (-not $overlayByKey.ContainsKey($key)) {
                $oq = [ordered]@{
                    id = [string](Get-ObjectPropertyValue $entry 'id' '')
                    contentKey = $key
                    type = [string](Get-ObjectPropertyValue $r 'type' '')
                    year = Get-ObjectPropertyValue $r 'year' 0
                    month = Get-ObjectPropertyValue $r 'month' 0
                    paper_key = [string](Get-ObjectPropertyValue $r 'paper_key' '')
                    stem = [string](Get-ObjectPropertyValue $r 'stem' '')
                    options = @(Get-ObjectPropertyValue $r 'options' @())
                    answer = [string](Get-ObjectPropertyValue $r 'answer' '')
                    explanation = [string](Get-ObjectPropertyValue $r 'explanation' '')
                    point = Get-ObjectPropertyValue $r 'point' 0
                    focus = [bool](Get-ObjectPropertyValue $r 'focus' $false)
                    source = 'portable-progress'
                    material_snapshot = Get-ObjectPropertyValue $r 'material_snapshot' $null
                    imported_progress = $true
                }
                $overlay += $oq
                $overlayByKey[$key] = $oq
            }
        }
        Set-ObjectPropertyValue $entry 'contentKey' $key
        Set-ObjectPropertyValue $entry 'wrongCount' ([Math]::Max([int](Get-ObjectPropertyValue $entry 'wrongCount' 0), [int](Get-ObjectPropertyValue $r 'wrongCount' 0)))
        Set-ObjectPropertyValue $entry 'reviewCount' ([Math]::Max([int](Get-ObjectPropertyValue $entry 'reviewCount' 0), [int](Get-ObjectPropertyValue $r 'reviewCount' 0)))
        Set-ObjectPropertyValue $entry 'learnedTwice' ([bool](Get-ObjectPropertyValue $entry 'learnedTwice' $false) -or [bool](Get-ObjectPropertyValue $r 'learnedTwice' $false))
        Set-ObjectPropertyValue $entry 'masteredConsecutive' ([Math]::Max([int](Get-ObjectPropertyValue $entry 'masteredConsecutive' 0), [int](Get-ObjectPropertyValue $r 'masteredConsecutive' 0)))
        Set-ObjectPropertyValue $entry 'active' ([bool](Get-ObjectPropertyValue $entry 'active' $true) -or [bool](Get-ObjectPropertyValue $r 'active' $true))
        if ([string](Get-ObjectPropertyValue $r 'lastWrongAt' '') -gt [string](Get-ObjectPropertyValue $entry 'lastWrongAt' '')) {
            Set-ObjectPropertyValue $entry 'userAnswer' ([string](Get-ObjectPropertyValue $r 'userAnswer' ''))
            Set-ObjectPropertyValue $entry 'userReason' ([string](Get-ObjectPropertyValue $r 'userReason' ''))
            Set-ObjectPropertyValue $entry 'errorType' ([string](Get-ObjectPropertyValue $r 'errorType' ''))
            Set-ObjectPropertyValue $entry 'lastWrongAt' (Get-ObjectPropertyValue $r 'lastWrongAt' $null)
        }
        if ([string](Get-ObjectPropertyValue $r 'deepFeedback' '') -and $null -eq (Get-ObjectPropertyValue $entry 'deepFeedback' $null)) {
            Set-ObjectPropertyValue $entry 'deepFeedback' (Get-ObjectPropertyValue $r 'deepFeedback' $null)
        }
        $all += $entry
    }
    $unique = @{}
    foreach ($e in $all) {
        $k = [string](Get-ObjectPropertyValue $e 'contentKey' '')
        if (-not $k) { $k = [string](Get-ObjectPropertyValue $e 'id' ([guid]::NewGuid().ToString())) }
        $unique[$k] = $e
    }
    $all = @($unique.Values)
    Write-JsonFile $wrongPath @($all)
    Write-JsonFile $overlayPath @($overlay)
    $script:QuestionCache = $null
    return [pscustomobject]@{ Resolved = $resolved; Orphans = $orphans; Overlay = @($overlay).Count }
}

function Merge-SeenPackage {
    param($Package, $Bank, $ByKey, $ByStem)
    $p = Get-ProgressSeenPath
    $all = @(Read-JsonFile $p @() -Quiet)
    $byKey = @{}
    foreach ($x in $all) { $byKey[[string](Get-ObjectPropertyValue $x 'contentKey' '')] = $x }
    foreach ($x in @(Get-ObjectPropertyValue $Package 'seen' @())) {
        $key = [string](Get-ObjectPropertyValue $x 'contentKey' '')
        if (-not $key) { $key = Get-QuestionContentKey $x }
        if (-not $key) { continue }
        $target = Resolve-QuestionRecord -Record $x -Bank $Bank -ByKey $ByKey -ByStem $ByStem
        $id = if ($target) { [string](Get-ObjectPropertyValue $target 'id' '') } else { [string](Get-ObjectPropertyValue $x 'id' '') }
        $byKey[$key] = [ordered]@{
            contentKey = $key
            id = $id
            date = [string](Get-ObjectPropertyValue $x 'date' '')
            at = [string](Get-ObjectPropertyValue $x 'at' '')
            selected = [string](Get-ObjectPropertyValue $x 'selected' '')
            correct = [bool](Get-ObjectPropertyValue $x 'correct' $false)
        }
    }
    Write-JsonFile $p @($byKey.Values)
}
function Import-LearningProgress {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { throw '找不到进度包文件。' }
    $pkg = Read-JsonFile $Path $null -Quiet
    if ($null -eq $pkg -or [string](Get-ObjectPropertyValue $pkg 'format' '') -ne 'cet4coach-progress') { throw '这不是 CET4Coach 进度包，或文件已损坏。' }
    $schema = [int](Get-ObjectPropertyValue $pkg 'schemaVersion' 1)
    if ($schema -lt 1) { throw '进度包版本无法识别。' }
    Merge-WordProgressPackage $pkg
    Merge-CheckinPackage $pkg
    $bank = @(Get-QuestionBank)
    $byKey = @{}; $byStem = @{}
    foreach ($q in $bank) {
        $k = Get-QuestionContentKey $q
        if ($k) { $byKey[$k] = $q }
        $s = Get-NormalizedStem ([string](Get-ObjectPropertyValue $q 'stem' ''))
        if ($s) {
            if (-not $byStem.ContainsKey($s)) { $byStem[$s] = @() }
            $byStem[$s] += $q
        }
    }
    Merge-SeenPackage -Package $pkg -Bank $bank -ByKey $byKey -ByStem $byStem
    $r = Merge-QuestionPackage -Package $pkg -Bank $bank -ByKey $byKey -ByStem $byStem
    Save-PortableProgress -Silent
    Write-CET4Log -Category 'progress' -Message ('导入进度包: ' + $Path + '，匹配 ' + $r.Resolved + '，保留 ' + $r.Orphans)
    return [pscustomobject]@{ Matched = $r.Resolved; Orphans = $r.Orphans; Overlay = $r.Overlay; Words = @($pkg.words.status).Count; Checkins = @($pkg.checkins.days).Count }
}

function Clear-TodayProgress {
    $today = (Get-Date).ToString('yyyy-MM-dd')
    $stamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
    $backupRoot = Join-Path (Get-CET4Path 'backup') ('clear-today-' + $stamp)
    New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null
    $paths = @('data/state.json','data/word_progress.json','data/checkin.json','data/wrongbook.json','data/progress_seen.json')
    foreach ($rel in $paths) {
        $p = Get-CET4Path $rel
        if (Test-Path -LiteralPath $p) {
            $dest = Join-Path $backupRoot ($rel -replace 'data/','')
            $destDir = Split-Path -Parent $dest
            if (-not (Test-Path -LiteralPath $destDir)) { New-Item -ItemType Directory -Force -Path $destDir | Out-Null }
            Copy-Item -LiteralPath $p -Destination $dest -Force
        }
    }
    foreach ($sub in @('data/sessions','data/plans','data/history','data/progress')) {
        $p = Get-CET4Path $sub
        if (Test-Path -LiteralPath $p) {
            $dest = Join-Path $backupRoot ($sub -replace 'data/','')
            Copy-Item -LiteralPath $p -Destination $dest -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    $counts = [ordered]@{ sessions = 0; plans = 0; history = 0; checkins = 0; wrongbook = 0; seen = 0; words = 0 }

    foreach ($sub in @('data/sessions','data/plans','data/history')) {
        $dir = Get-CET4Path $sub
        if (-not (Test-Path -LiteralPath $dir)) { continue }
        foreach ($f in @(Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue)) {
            if ($f.Name -like ('*' + $today + '*')) {
                Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue
                if ($sub -like '*sessions*') { $counts.sessions++ }
                elseif ($sub -like '*plans*') { $counts.plans++ }
                else { $counts.history++ }
            }
        }
    }

    $wordPath = Get-CET4Path 'data/word_progress.json'
    if (Test-Path -LiteralPath $wordPath) {
        $wp = Read-JsonFile $wordPath $null -Quiet
        if ($wp) {
            $status = Get-ObjectPropertyValue $wp 'status' $null
            $todayWords = @()
            if ($status) {
                foreach ($prop in @($status.PSObject.Properties)) {
                    $entry = $prop.Value
                    $rawSeen = Get-ObjectPropertyValue $entry 'lastSeen' ''
                    $seenDate = ''
                    if ($rawSeen -is [datetime]) { $seenDate = $rawSeen.ToString('yyyy-MM-dd') }
                    elseif ($rawSeen) {
                        $txt = [string]$rawSeen
                        if ($txt.Length -ge 10) { $seenDate = $txt.Substring(0, 10) }
                    }
                    $sessions = [int](Get-ObjectPropertyValue $entry 'sessions' 0)
                    if ($seenDate -eq $today -and $sessions -le 1) {
                        $todayWords += [string]$prop.Name
                        $status.PSObject.Properties.Remove($prop.Name)
                    }
                }
            }
            if ($todayWords.Count -gt 0) {
                $introduced = @(Get-ObjectPropertyValue $wp 'introduced' @() | Where-Object { $todayWords -notcontains [string]$_ })
                $review = @(Get-ObjectPropertyValue $wp 'reviewQueue' @() | Where-Object { $todayWords -notcontains [string]$_ })
                Set-ObjectPropertyValue $wp 'introduced' $introduced
                Set-ObjectPropertyValue $wp 'reviewQueue' $review
                $counts.words = $todayWords.Count
                Write-JsonFile $wordPath $wp
            }
        }
    }

    $checkinPath = Get-CET4Path 'data/checkin.json'
    if (Test-Path -LiteralPath $checkinPath) {
        $ci = Read-JsonFile $checkinPath ([pscustomobject]@{ days = [pscustomobject]@{}; milestones = @() }) -Quiet
        $days = Get-ObjectPropertyValue $ci 'days' $null
        if ($days -is [System.Collections.IDictionary]) {
            if ($days.Contains($today)) { $days.Remove($today); $counts.checkins++ }
        } elseif ($days) {
            if ($days.PSObject.Properties[$today]) { $days.PSObject.Properties.Remove($today); $counts.checkins++ }
        }
        $milestones = @(Get-ObjectPropertyValue $ci 'milestones' @() | Where-Object { [string](Get-ObjectPropertyValue $_ 'date' '') -ne $today })
        Set-ObjectPropertyValue $ci 'milestones' $milestones
        Write-JsonFile $checkinPath $ci
    }

    $wrongPath = Get-CET4Path 'data/wrongbook.json'
    if (Test-Path -LiteralPath $wrongPath) {
        $all = @(Read-JsonFile $wrongPath @() -Quiet)
        $keep = @($all | Where-Object {
            $raw = Get-ObjectPropertyValue $_ 'firstWrongAt' ''
            $firstDate = ''
            if ($raw -is [datetime]) { $firstDate = $raw.ToString('yyyy-MM-dd') }
            elseif ($raw) {
                $txt = [string]$raw
                if ($txt.Length -ge 10) { $firstDate = $txt.Substring(0, 10) }
            }
            $firstDate -ne $today
        })
        $counts.wrongbook = $all.Count - $keep.Count
        Write-JsonFile $wrongPath @($keep)
    }

    $seenPath = Get-CET4Path 'data/progress_seen.json'
    if (Test-Path -LiteralPath $seenPath) {
        $seen = @(Read-JsonFile $seenPath @() -Quiet)
        $keep = @($seen | Where-Object { [string](Get-ObjectPropertyValue $_ 'date' '') -ne $today })
        $counts.seen = $seen.Count - $keep.Count
        Write-JsonFile $seenPath @($keep)
    }

    $latest = Get-PortableProgressPath
    if (Test-Path -LiteralPath $latest) { Remove-Item -LiteralPath $latest -Force -ErrorAction SilentlyContinue }
    Save-PortableProgress -Silent
    return [pscustomobject]@{ Date = $today; Backup = $backupRoot; Counts = [pscustomobject]$counts }
}

function Resolve-ProgressOverlay {
    $overlayPath = Get-ProgressOverlayPath
    $overlay = @(Read-JsonFile $overlayPath @() -Quiet)
    if ($overlay.Count -eq 0) { return 0 }
    $authoritative = @(Read-JsonFile (Get-ConfigValue 'paths.questions' 'data/questions.json') @() -Quiet)
    $byKey = @{}
    foreach ($q in $authoritative) { $byKey[(Get-QuestionContentKey $q)] = $q }
    $wrongPath = Get-ConfigValue 'paths.wrongbook' 'data/wrongbook.json'
    $wrong = @(Read-JsonFile $wrongPath @() -Quiet)
    $keep = @()
    $moved = 0
    foreach ($o in $overlay) {
        $k = [string](Get-ObjectPropertyValue $o 'contentKey' '')
        if ($byKey.ContainsKey($k)) {
            $target = $byKey[$k]
            $tid = [string](Get-ObjectPropertyValue $target 'id' '')
            foreach ($w in $wrong) {
                if ([string](Get-ObjectPropertyValue $w 'contentKey' '') -eq $k) { Set-ObjectPropertyValue $w 'id' $tid; Set-ObjectPropertyValue $w 'imported_progress' $false; $moved++ }
            }
        } else { $keep += $o }
    }
    Write-JsonFile $overlayPath @($keep)
    Write-JsonFile $wrongPath @($wrong)
    $script:QuestionCache = $null
    return $moved
}
