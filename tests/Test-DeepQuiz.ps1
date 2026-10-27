$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$script:CET4Root = $root
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
. (Join-Path $root 'scripts\common.ps1')
$script:Config = Read-JsonFile (Join-Path $root 'config.json')
. (Join-Path $root 'scripts\llm.ps1')
. (Join-Path $root 'scripts\listening.ps1')
. (Join-Path $root 'scripts\quiz_data.ps1')
. (Join-Path $root 'scripts\quiz.ps1')
$wrongPath = Get-CET4Path (Get-ConfigValue 'paths.wrongbook' 'data/wrongbook.json')
$oldWrong = $null
if (Test-Path $wrongPath) { $oldWrong = [IO.File]::ReadAllBytes($wrongPath) }
try {
    $bank = @(Get-QuestionBank)
    $q = @($bank | Where-Object { $_.type -eq 'careful_reading' -and @($_.options).Count -eq 4 })[0]
    if (-not $q) { throw 'no 4-option reading question' }
    $originalKeys = (@($q.options | ForEach-Object { [string]$_.key }) -join ',')
    $entry = [pscustomobject]@{
        id = [string]$q.id; wrongCount = 1; reviewCount = 1; learnedTwice = $false;
        userAnswer = 'A'; userReason = 'test'; errorType = '定位错'; active = $true;
        explanation = ''; teacherExplanation = ''; technique = ''; source = $q.source;
    }
    Write-JsonFile $wrongPath @($entry)
    $display = Get-QuestionDisplayOptions -Question $q -Current ([pscustomobject]@{}) 
    if (-not $display.Shuffled) { throw 'options were not shuffled for a previously wrong question' }
    $newKeys = (@($display.Options | ForEach-Object { [string]$_.key }) -join ',')
    if ($newKeys -ne $originalKeys) { throw 'option keys should remain A-D after shuffle' }
    $answerText = (@($q.options | Where-Object { [string]$_.key -eq [string]$q.answer })[0].text)
    $mappedText = (@($display.Options | Where-Object { [string]$_.key -eq [string]$display.CorrectKey })[0].text)
    if ($answerText -ne $mappedText) { throw 'correctKey does not map to the original correct text' }
    $local = Get-LocalTeacherFeedback -Question $q -Selected 'A' -Wrong $true -DisplayOptions $display.Options -CorrectKey $display.CorrectKey
    if (@($local.option_analysis).Count -ne 4) { throw 'local feedback must analyze all four options' }
    $text = Get-FeedbackText $local
    if ($text -notmatch '逐项分析' -or $text -notmatch '你的误区') { throw 'feedback text missing deep fields' }
    Add-QuestionToWrongBook -Question $q -UserAnswer 'A' -UserReason 'test' -ErrorType '定位错' -Explanation $text -TeacherExplanation $text -Technique 'test' -SelectedText 'test' -CorrectKey ([string]$q.answer) -DeepFeedback $local
    $saved = Get-WrongBookEntry ([string]$q.id)
    if ($null -eq (Get-ObjectPropertyValue $saved 'deepFeedback' $null)) { throw 'deep feedback was not saved to wrongbook' }
    if ([int](Get-ObjectPropertyValue $saved 'reviewCount' 0) -lt 2) { throw 'second learning did not increment reviewCount' }
    if (-not [bool](Get-ObjectPropertyValue $saved 'learnedTwice' $false)) { throw 'learnedTwice not set after second learning' }
    $stored = Get-StoredTeacherFeedback -Entry $saved -Question $q -Selected 'A'
    if ($null -eq $stored -or [string](Get-ObjectPropertyValue $stored 'source' '') -ne 'stored-deep') { throw 'skip-repeat did not read saved deep feedback' }
    $histDir = Get-CET4Path (Get-ConfigValue 'paths.history' 'data/history')
    $before = @(Get-ChildItem $histDir -File -ErrorAction SilentlyContinue).Count
    $session = [pscustomobject]@{ date = '2099-01-01'; startedAt = (Get-Date).ToString('o'); results = @(); note = 'test'; summary = @{ answered = 0 } }
    Save-QuizRoundHistory -Session $session -Questions @($q)
    $after = @(Get-ChildItem $histDir -File -ErrorAction SilentlyContinue).Count
    if ($after -le $before) { throw 'history was not written' }
    Get-ChildItem $histDir -File | Where-Object { $_.Name -like 'quiz-2099-01-01-*' -or $_.Name -eq 'latest-quiz.json' } | Remove-Item -Force
    Write-Host 'Deep quiz test passed: shuffle, all-option analysis, history'
} finally {
    if ($null -eq $oldWrong) { Remove-Item $wrongPath -Force -ErrorAction SilentlyContinue }
    else { [IO.File]::WriteAllBytes($wrongPath, $oldWrong) }
}
