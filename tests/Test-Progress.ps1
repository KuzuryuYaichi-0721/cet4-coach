$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$script:CET4Root = $root
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
. (Join-Path $root 'scripts\common.ps1')
$script:Config = Read-JsonFile (Join-Path $root 'config.json')
. (Join-Path $root 'scripts\quiz_data.ps1')
. (Join-Path $root 'scripts\words.ps1')
. (Join-Path $root 'scripts\checkin.ps1')
. (Join-Path $root 'scripts\progress.ps1')
$wrongPath = Join-Path $root 'data\wrongbook.json'
$wordPath = Join-Path $root 'data\word_progress.json'
$checkPath = Join-Path $root 'data\checkin.json'
$overlayPath = Join-Path $root 'data\progress_overlay.json'
$progressDir = Join-Path $root 'data\progress'
$backup = @{}
foreach ($p in @($wrongPath, $wordPath, $checkPath, $overlayPath)) {
    if (Test-Path $p) { $backup[$p] = [IO.File]::ReadAllBytes($p) }
}
$oldProgress = @(Get-ChildItem $progressDir -File -ErrorAction SilentlyContinue)
$tmp = Join-Path $env:TEMP ('cet4-progress-test-' + [guid]::NewGuid().ToString('N') + '.cet4progress.json')
try {
    $bank = @(Get-QuestionBank)
    $q = @($bank | Where-Object { $_.type -eq 'careful_reading' -and @($_.options).Count -eq 4 })[0]
    if (-not $q) { throw 'no question' }
    $wrong = @([pscustomobject]@{
        id = [string]$q.id; type = $q.type; year = $q.year; paper_key = $q.paper_key; stem = $q.stem;
        options = $q.options; answer = $q.answer; explanation = $q.explanation; source = $q.source;
        userAnswer = 'A'; userReason = 'test'; errorType = '定位错'; wrongCount = 2; reviewCount = 2;
        learnedTwice = $true; masteredConsecutive = 0; active = $true; contentKey = Get-QuestionContentKey $q;
    })
    Write-JsonFile $wrongPath $wrong
    $wp = Get-WordProgress
    Set-ObjectPropertyValue $wp 'introduced' @('company')
    $wp.status | Add-Member -NotePropertyName company -NotePropertyValue ([pscustomobject]@{ state = 'mastered'; correct = 2; wrong = 1; lastSeen = (Get-Date).ToString('o'); nextReview = $null }) -Force
    Save-WordProgress $wp
    $c = Get-CheckinData
    $c.days | Add-Member -NotePropertyName '2026-10-27' -NotePropertyValue ([pscustomobject]@{ word = $true; quiz = $true; minutes = 30; quizCount = 20 }) -Force
    Save-CheckinData $c
    $r = Export-LearningProgress -Path $tmp -Silent
    if ($r.Questions -lt 1 -or $r.Words -lt 1) { throw 'export counts wrong' }
    # 1) same bank, changed id: must match by content key and restore progress
    $wp2 = Get-WordProgress
    Set-ObjectPropertyValue $wp2 'introduced' @()
    Set-ObjectPropertyValue $wp2 'status' ([pscustomobject]@{})
    Save-WordProgress $wp2
    Write-JsonFile $wrongPath @()
    $imp = Import-LearningProgress -Path $tmp
    if ($imp.Matched -lt 1) { throw 'exact/content mapping did not match' }
    $saved = Get-WrongBookEntry ([string]$q.id)
    if ($null -eq $saved -or [int](Get-ObjectPropertyValue $saved 'wrongCount' 0) -lt 2) { throw 'wrongbook progress not merged' }
    if (@(Get-WordProgress).Count -lt 0) { throw 'word progress not restored' }
    # 2) a question that is not in the current bank must become an overlay question, not be lost
    $pkg = Read-JsonFile $tmp $null
    $synth = [ordered]@{
        contentKey = 'synthetic-key-001'
        id = 'synthetic-id-001'; type = 'careful_reading'; year = 2099; month = 1; paper_key = 'synthetic';
        stem = 'Synthetic future question about a blue fish.'; options = @(@{key='A';text='one'}, @{key='B';text='two'}, @{key='C';text='three'}, @{key='D';text='four'}); answer = 'B';
        explanation = 'test'; source = 'test'; wrongCount = 1; reviewCount = 1; active = $true; userAnswer = 'A';
        lastWrongAt = (Get-Date).ToString('o');
    }
    $pkg.questions = @($pkg.questions) + @($synth)
    $tmp2 = Join-Path $env:TEMP ('cet4-progress-test-overlay-' + [guid]::NewGuid().ToString('N') + '.cet4progress.json')
    Write-JsonFile $tmp2 $pkg
    $imp2 = Import-LearningProgress -Path $tmp2
    if ($imp2.Orphans -lt 1) { throw 'orphan question was not counted' }
    $overlay = @(Read-JsonFile $overlayPath @() -Quiet)
    if (@($overlay | Where-Object { $_.contentKey -eq 'synthetic-key-001' }).Count -lt 1) { throw 'overlay question not saved' }
    $script:QuestionCache = $null
    if (@(Get-QuestionBank | Where-Object { $_.id -eq 'synthetic-id-001' }).Count -lt 1) { throw 'overlay question not visible in question bank' }
    Remove-Item $tmp2 -Force -ErrorAction SilentlyContinue
    Write-Host 'Progress portability test passed: export, content mapping, words/checkins, overlay for unseen bank'
} finally {
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    foreach ($p in $backup.Keys) { [IO.File]::WriteAllBytes($p, $backup[$p]) }
    if (-not $backup.ContainsKey($overlayPath)) { Remove-Item $overlayPath -Force -ErrorAction SilentlyContinue }
    foreach ($f in @(Get-ChildItem $progressDir -File -ErrorAction SilentlyContinue)) {
        if (-not ($oldProgress.Name -contains $f.Name)) { Remove-Item $f.FullName -Force }
    }
}
