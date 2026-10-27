# generate-word-sentences.ps1 - one-time, resumable batch pre-generation of
# fun/proverb sentences. Runtime study never calls the model for these.
# Usage: powershell -ExecutionPolicy Bypass -File tools\Generate-WordSentences.ps1 -BatchSize 30

param(
    [int]$BatchSize = 30,
    [int]$Limit = 0,
    [switch]$AllowOverBudget
)

$ErrorActionPreference = 'Stop'
$script:CET4Root = Split-Path -Parent $PSScriptRoot
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
. (Join-Path $script:CET4Root 'scripts\common.ps1')
$script:Config = Read-JsonFile (Join-Path $script:CET4Root 'config.json')
. (Join-Path $script:CET4Root 'scripts\llm.ps1')

if (-not (Test-DeepSeekKeyPresent)) {
    Write-Host '未设置 DEEPSEEK_API_KEY。请先设置环境变量再运行。'
    exit 1
}
$wordsPath = Get-CET4Path (Get-ConfigValue 'paths.words' 'data/words.json')
$sentPath = Get-CET4Path (Get-ConfigValue 'paths.wordSentences' 'data/word_sentences.json')
$words = @(Read-JsonFile $wordsPath @())
$sentences = @(Read-JsonFile $sentPath @())
if ($words.Count -eq 0) { throw 'words.json 为空。' }

$needs = @()
foreach ($w in $words) {
    $hasDeepSeek = @($sentences | Where-Object { $_.word -eq $w.word -and $_.sentence_type -ne '真题' -and $_.source -eq 'deepseek' }).Count -gt 0
    if (-not $hasDeepSeek) { $needs += $w }
}
if ($Limit -gt 0) { $needs = @($needs | Select-Object -First $Limit) }
Write-Host ("需要预生成的单词：{0} 个；每批 {1} 个；预计 {2} 次调用。" -f $needs.Count, $BatchSize, [Math]::Ceiling($needs.Count / $BatchSize))
if ($needs.Count -eq 0) { Write-Host '已有完整的 DeepSeek 趣味句，无需生成。'; exit 0 }

$system = '你是大学英语四级词汇老师，为中文母语的低基础学生写趣味记忆句。只输出 JSON 数组，不要 markdown。每项字段：word、en、zh、target_meaning、sentence_type（只能是“趣味”或“谚语”）。要求：en 是 8-20 个词的自然的英文句子，必须包含目标词；zh 是准确的中文翻译；target_meaning 是目标词在该句中的中文意思；句子浅显、有画面感，不要复杂从句；不要写中文解释。'
$done = 0
for ($start = 0; $start -lt $needs.Count; $start += $BatchSize) {
    $batch = @($needs | Select-Object -Skip $start -First $BatchSize)
    $list = @($batch | ForEach-Object { '- {0} | {1} | {2}' -f $_.word, $_.meaning, $_.short_meaning }) -join "`n"
    $user = "请为下面每个词写一句趣味/谚语记忆句：`n$list`n返回 JSON 数组，顺序与输入一致，数量必须为 $($batch.Count)。"
    try {
        $r = Invoke-DeepSeekChat -System $system -User $user -Purpose 'word_sentence_pregeneration' -RequireJson -MaxTokens 2600 -CacheKey ('pregenerate:' + (($batch | ForEach-Object { $_.word }) -join ',')) -BypassBudget:$AllowOverBudget -LogTag 'pregenerate'
        $arr = @($r.Json)
        if ($arr.Count -eq 1 -and $arr[0] -is [System.Array]) { $arr = @($arr[0]) }
        $byWord = @{}
        foreach ($item in $arr) {
            $w = [string](Get-ObjectPropertyValue $item 'word' '')
            if ($w) { $byWord[$w.ToLowerInvariant()] = $item }
        }
        foreach ($w in $batch) {
            $item = $byWord[$w.word.ToLowerInvariant()]
            if ($null -eq $item) { continue }
            $en = [string](Get-ObjectPropertyValue $item 'en' '')
            $zh = [string](Get-ObjectPropertyValue $item 'zh' '')
            if (-not $en -or -not $zh) { continue }
            $sentences = @($sentences | Where-Object { -not ($_.word -eq $w.word -and $_.sentence_type -ne '真题') })
            $sentences += [pscustomobject]@{
                word = $w.word; en = $en; zh = $zh;
                target_meaning = [string](Get-ObjectPropertyValue $item 'target_meaning' $w.short_meaning);
                sentence_type = [string](Get-ObjectPropertyValue $item 'sentence_type' '趣味');
                source = 'deepseek'; material_id = $null
            }
            $done++
        }
        Write-JsonFile $sentPath @($sentences)
        Write-Host ("批量 {0}-{1} 完成，累计替换 {2} 个。" -f ($start + 1), ($start + $batch.Count), $done)
    } catch {
        Write-Host ("批量 {0}-{1} 失败：{2}" -f ($start + 1), ($start + $batch.Count), (Format-SafeError $_))
        Write-Host '已保留现有趣味句；下次运行会从缺失的单词继续。'
        break
    }
}
Write-Host "完成。共替换 $done 个词的趣味句。"
