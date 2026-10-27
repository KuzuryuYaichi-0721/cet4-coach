# import.ps1 - read the real cet-practice seed database or JSON exports,
# adapt their actual field names, deduplicate by stem+options hash, and
# write the local question bank plus a gap report.

$script:Cet4SqliteTypeReady = $false

function Initialize-Cet4Sqlite {
    if ($script:Cet4SqliteTypeReady -and ('CET4SqliteNative' -as [type])) { return }
    $code = @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public static class CET4SqliteNative {
  [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_open_v2(byte[] filename, out IntPtr db, int flags, IntPtr vfs);
  [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_prepare_v2(IntPtr db, byte[] sql, int nByte, out IntPtr stmt, IntPtr tail);
  [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_step(IntPtr stmt);
  [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)] static extern IntPtr sqlite3_column_text(IntPtr stmt, int i);
  [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_column_count(IntPtr stmt);
  [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_finalize(IntPtr stmt);
  [DllImport("winsqlite3.dll", CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_close(IntPtr db);
  static string Utf8(IntPtr p) {
    if (p == IntPtr.Zero) return null;
    int len = 0;
    while (Marshal.ReadByte(p, len) != 0) len++;
    byte[] bytes = new byte[len];
    Marshal.Copy(p, bytes, 0, len);
    return System.Text.Encoding.UTF8.GetString(bytes);
  }
  public static string[][] Query(string path, string sql) {
    IntPtr db, stmt;
    if (sqlite3_open_v2(System.Text.Encoding.UTF8.GetBytes(path + "\0"), out db, 1, IntPtr.Zero) != 0) throw new Exception("无法打开数据库: " + path);
    var list = new List<string[]>();
    try {
      if (sqlite3_prepare_v2(db, System.Text.Encoding.UTF8.GetBytes(sql + "\0"), -1, out stmt, IntPtr.Zero) != 0) throw new Exception("SQL 准备失败");
      try {
        while (sqlite3_step(stmt) == 100) {
          int n = sqlite3_column_count(stmt);
          var vals = new string[n];
          for (int i = 0; i < n; i++) {
            IntPtr p = sqlite3_column_text(stmt, i);
            vals[i] = Utf8(p);
          }
          list.Add(vals);
        }
      } finally { sqlite3_finalize(stmt); }
    } finally { sqlite3_close(db); }
    return list.ToArray();
  }
}
'@
    Add-Type -TypeDefinition $code -Language CSharp
    $script:Cet4SqliteTypeReady = $true
}

function Invoke-Cet4SqliteQuery {
    param([string]$DbPath, [string]$Sql)
    Initialize-Cet4Sqlite
    $rows = [CET4SqliteNative]::Query($DbPath, $Sql)
    Write-Output -NoEnumerate $rows
}

function ConvertTo-QuestionHash {
    param([string]$Stem, $Options)
    $norm = { param($s) ([regex]::Replace([string]$s, '\s+', ' ')).Trim().ToLowerInvariant() }
    $parts = @(& $norm $Stem)
    foreach ($o in @($Options)) {
        $k = Get-ObjectPropertyValue $o 'key' ''
        $t = Get-ObjectPropertyValue $o 'text' ''
        $parts += ('{0}:{1}' -f $k, (& $norm $t))
    }
    return (Get-Sha256Hex ($parts -join '|'))
}

function Get-QuestionTypeFromRecord {
    param([string]$Section, [int]$QNo)
    switch ($Section) {
        'listening' {
            if ($QNo -le 7) { return @{ Type = 'listening_news'; Point = 7.1; AudioSection = 'A' } }
            elseif ($QNo -le 15) { return @{ Type = 'listening_long'; Point = 7.1; AudioSection = 'B' } }
            else { return @{ Type = 'listening_passage'; Point = 14.2; AudioSection = 'C' } }
        }
        'reading1' { return @{ Type = 'careful_reading'; Point = 14.2; AudioSection = $null } }
        'reading2' { return @{ Type = 'careful_reading'; Point = 14.2; AudioSection = $null } }
        'matching' { return @{ Type = 'matching'; Point = 7.1; AudioSection = $null } }
        'cloze'    { return @{ Type = 'cloze'; Point = 3.55; AudioSection = $null } }
        default    { return $null }
    }
}

function ConvertFrom-CetPracticeRecord {
    param(
        [Parameter(Mandatory)]$Record,
        [hashtable]$Paper,
        [hashtable]$Materials,
        [hashtable]$SeenHashes
    )
    $section = [string](Get-ObjectPropertyValue $Record 'section' '')
    $qtypeInfo = Get-QuestionTypeFromRecord -Section $section -QNo ([int](Get-ObjectPropertyValue $Record 'q_no' 0))
    if ($null -eq $qtypeInfo) { return $null }
    $stem = [string](Get-ObjectPropertyValue $Record 'stem' '')
    $analysis = [string](Get-ObjectPropertyValue $Record 'analysis_text' '')
    if ([string]::IsNullOrWhiteSpace($stem) -and $section -eq 'listening') {
        $m = [regex]::Match($analysis, '【题目】\s*(.+?)(?:\n|【)', 'Singleline')
        if ($m.Success) { $stem = $m.Groups[1].Value.Trim() } else { $stem = '请听录音，回答第 ' + [string](Get-ObjectPropertyValue $Record 'q_no' '') + ' 题。' }
    }
    $optionsRaw = Get-ObjectPropertyValue $Record 'options_json' $null
    $options = @()
    if ($optionsRaw -is [string]) {
        if (-not [string]::IsNullOrWhiteSpace($optionsRaw)) {
            try {
                $parsed = ConvertFrom-Json -InputObject ([string]$optionsRaw)
                $options = @($parsed)
                if ($options.Count -eq 1 -and $options[0] -is [System.Array]) { $options = @($options[0]) }
            } catch { $options = @() }
        }
    } elseif ($null -ne $optionsRaw) {
        $options = @($optionsRaw)
        if ($options.Count -eq 1 -and $options[0] -is [System.Array]) { $options = @($options[0]) }
    }
    if (-not $options -or $options.Count -eq 0) {
        $optsField = Get-ObjectPropertyValue $Record 'options' $null
        if ($optsField) {
            $options = @($optsField)
            if ($options.Count -eq 1 -and $options[0] -is [System.Array]) { $options = @($options[0]) }
        }
    }
    $paperKey = [string](Get-ObjectPropertyValue $Record 'paper_key' (Get-ObjectPropertyValue $Paper 'paper_key' ''))
    $groupKey = [string](Get-ObjectPropertyValue $Record 'group_key' '')
    if ($section -eq 'matching' -and $options.Count -eq 0 -and $Materials.ContainsKey(('{0}:matching:{1}' -f $paperKey, $groupKey))) {
        $mat = $Materials[('{0}:matching:{1}' -f $paperKey, $groupKey)]
        foreach ($m in [regex]::Matches([string]$mat.text, '(?m)^([A-O])\)\s*(.*)$')) {
            $options += [pscustomobject]@{ key = $m.Groups[1].Value; text = $m.Groups[2].Value.Trim() }
        }
    }
    if ($options.Count -eq 0) { return $null }
    $answer = ([string](Get-ObjectPropertyValue $Record 'answer' '')).Trim().ToUpperInvariant()
    if (-not $answer) { return $null }
    $hash = ConvertTo-QuestionHash -Stem $stem -Options $options
    if ($SeenHashes.ContainsKey($hash)) { return $null }
    $SeenHashes[$hash] = $true
    $year = [int](Get-ObjectPropertyValue $Paper 'year' 0)
    $month = [int](Get-ObjectPropertyValue $Paper 'month' 0)
    $setNo = [int](Get-ObjectPropertyValue $Paper 'set_no' 0)
    if ($year -le 0 -or $month -le 0 -or $setNo -le 0) {
        $ym = [regex]::Match($paperKey, '(20\d{2})[-_](\d{1,2})[-_](\d)')
        if ($ym.Success) { $year = [int]$ym.Groups[1].Value; $month = [int]$ym.Groups[2].Value; $setNo = [int]$ym.Groups[3].Value }
    }
    $audio = $null
    if ($section -eq 'listening') {
        $suite = '{0:D4}-{1:D2}-set{2}' -f $year, $month, $setNo
        $audio = [ordered]@{ required = $true; suite = $suite; section = $qtypeInfo.AudioSection; audio_id = "$suite-Section$($qtypeInfo.AudioSection)" }
    }
    $materialId = $null
    if ($section -eq 'listening') { $materialId = '{0}:listening:{1}' -f $paperKey, $groupKey }
    else { $materialId = '{0}:{1}:{2}' -f $paperKey, $section, $groupKey }
    $uid = [string](Get-ObjectPropertyValue $Record 'uid' '')
    if (-not $uid) { $uid = '{0}:{1}:{2}' -f $paperKey, $section, (Get-ObjectPropertyValue $Record 'q_no' '') }
    return [ordered]@{
        id = $uid
        paper_key = $paperKey
        year = $year
        month = $month
        set_no = $setNo
        section = $section
        type = $qtypeInfo.Type
        q_no = [int](Get-ObjectPropertyValue $Record 'q_no' 0)
        group_key = $groupKey
        stem = $stem.Trim()
        options = @($options | ForEach-Object { [ordered]@{ key = [string](Get-ObjectPropertyValue $_ 'key' ''); text = [string](Get-ObjectPropertyValue $_ 'text' '') } })
        answer = $answer
        material_id = $materialId
        audio = $audio
        point = $qtypeInfo.Point
        focus = ($qtypeInfo.Type -in @('careful_reading', 'listening_passage'))
        explanation = $analysis.Trim()
        answer_source = [string](Get-ObjectPropertyValue $Record 'answer_source' '')
        source = 'cet-practice adapter (actual DB/JSON fields)'
        source_file = [string](Get-ObjectPropertyValue $Record 'source_file' '')
        hash = $hash
    }
}

function Get-MaterialsFromCetPracticeDb {
    param([string]$DbPath)
    $rows = Invoke-Cet4SqliteQuery $DbPath @'
select m.paper_id, m.section, m.group_key, m.content_json, p.paper_key
from section_materials m join papers p on p.id=m.paper_id
where p.exam_type='cet4' and p.year between 2020 and 2025
'@
    $materials = @{}
    foreach ($row in $rows) {
        if (-not $row -or $row.Count -lt 5) { continue }
        $paperKey = [string]$row[4]
        $section = [string]$row[1]
        $groupKey = [string]$row[2]
        $content = $null
        try { $content = ($row[3] | ConvertFrom-Json) } catch { continue }
        if ($section -eq 'listening') {
            foreach ($g in @(Get-ObjectPropertyValue $content 'groups' @())) {
                $gkey = [string](Get-ObjectPropertyValue $g 'key' '')
                if (-not $gkey) { $gkey = 'g' + [string](Get-ObjectPropertyValue $g 'from' '') }
                $lines = @(Get-ObjectPropertyValue $g 'lines' @())
                $transcript = (@($lines | ForEach-Object {
                    $sp = [string](Get-ObjectPropertyValue $_ 'speaker' '')
                    $en = [string](Get-ObjectPropertyValue $_ 'en' '')
                    if ($sp) { "$sp`: $en" } else { $en }
                }) -join "`n").Trim()
                $mid = '{0}:listening:{1}' -f $paperKey, $gkey
                $materials[$mid] = [ordered]@{
                    id = $mid; paper_key = $paperKey; section = 'listening'; group_key = $gkey
                    title = '听力材料'; kind = 'transcript'; text = ''; transcript = $transcript
                }
            }
        } elseif ($section -eq 'matching') {
            $title = [string](Get-ObjectPropertyValue $content 'title' '')
            $paras = @(Get-ObjectPropertyValue $content 'paragraphs' @())
            $body = (@($paras | ForEach-Object { ('{0}) {1}' -f (Get-ObjectPropertyValue $_ 'label' ''), (Get-ObjectPropertyValue $_ 'text' '')) }) -join "`n`n")
            $mid = '{0}:matching:{1}' -f $paperKey, $groupKey
            $materials[$mid] = [ordered]@{ id = $mid; paper_key = $paperKey; section = 'matching'; group_key = $groupKey; title = $title; kind = 'matching'; text = ($title + "`n`n" + $body).Trim(); transcript = '' }
        } else {
            $passage = [string](Get-ObjectPropertyValue $content 'passage' '')
            $mid = '{0}:{1}:{2}' -f $paperKey, $section, $groupKey
            $materials[$mid] = [ordered]@{ id = $mid; paper_key = $paperKey; section = $section; group_key = $groupKey; title = $section; kind = 'passage'; text = $passage.Trim(); transcript = '' }
        }
    }
    return $materials
}

function Import-CetPracticeData {
    param(
        [Parameter(Mandatory)][string]$SourcePath,
        [switch]$IncludeOtherYears,
        [switch]$NoWrite
    )
    $src = [System.IO.Path]::GetFullPath($SourcePath)
    if (-not (Test-Path -LiteralPath $src)) { throw "导入源不存在：$src" }
    $questionsPath = Get-CET4Path (Get-ConfigValue 'paths.questions' 'data/questions.json')
    $materialsPath = Get-CET4Path (Get-ConfigValue 'paths.materials' 'data/materials.json')
    $existingQuestions = @(Read-JsonFile $questionsPath @() -Quiet)
    $existingMaterials = @(Read-JsonFile $materialsPath @() -Quiet)
    $yearMin = if ($IncludeOtherYears) { 2000 } else { 2020 }
    $yearMax = if ($IncludeOtherYears) { 2099 } else { 2025 }

    $seenHashes = @{}
    foreach ($q in $existingQuestions) {
        if ($q.hash) { $seenHashes[[string]$q.hash] = $true }
    }
    $materials = @{}
    foreach ($m in $existingMaterials) { if ($m.id) { $materials[[string]$m.id] = $m } }
    $newQuestions = @()

    if ($src -match '\.db$') {
        Show-UiProgress -Title '导入 cet-practice 数据库' -Text '正在读取 papers / questions / section_materials…'
        try {
            $papers = @{}
            foreach ($row in (Invoke-Cet4SqliteQuery $src "select paper_key,exam_type,year,month,set_no from papers where exam_type='cet4'")) {
                $p = @{ paper_key = [string]$row[0]; exam_type = [string]$row[1]; year = [int]$row[2]; month = [int]$row[3]; set_no = [int]$row[4] }
                if ($p.year -lt $yearMin -or $p.year -gt $yearMax) { continue }
                $papers[[string]$row[0]] = $p
            }
            $dbMaterials = Get-MaterialsFromCetPracticeDb $src
            foreach ($k in $dbMaterials.Keys) {
                if (-not $materials.ContainsKey($k)) { $materials[$k] = $dbMaterials[$k] }
            }
            $rows = Invoke-Cet4SqliteQuery $src "select q.uid,q.paper_id,q.section,q.q_no,q.group_key,q.stem,q.options_json,q.answer,q.analysis_text,q.answer_source,q.source_file,p.paper_key from questions q join papers p on p.id=q.paper_id where p.exam_type='cet4' and q.section in ('listening','cloze','matching','reading1','reading2')"
            foreach ($row in $rows) {
                if (-not $row -or $row.Count -lt 12) { continue }
                $paperKey = [string]$row[11]
                if (-not $papers.ContainsKey($paperKey)) { continue }
                $rec = [pscustomobject]@{
                    uid = $row[0]; section = $row[2]; q_no = $row[3]; group_key = $row[4]; stem = $row[5];
                    options_json = $row[6]; answer = $row[7]; analysis_text = $row[8]; answer_source = $row[9]; source_file = $row[10]
                }
                $q = ConvertFrom-CetPracticeRecord -Record $rec -Paper $papers[$paperKey] -Materials $materials -SeenHashes $seenHashes
                if ($q) { $newQuestions += $q }
            }
        } finally { Close-UiProgress }
    } else {
        Show-UiProgress -Title '导入 JSON 题库' -Text '正在扫描 JSON 并识别字段…'
        try {
            $files = @()
            if ((Get-Item -LiteralPath $src).PSIsContainer) {
                $files = @(Get-ChildItem -LiteralPath $src -Recurse -File -Filter '*.json' -ErrorAction SilentlyContinue)
            } else { $files = @(Get-Item -LiteralPath $src) }
            foreach ($f in $files) {
                Set-UiProgressText ("正在读取：" + $f.Name)
                $obj = Read-JsonFile $f.FullName $null -Quiet
                if ($null -eq $obj) { continue }
                $papers = @{}
                $records = @()
                if ($obj.questions) {
                    $paperKey = [string](Get-ObjectPropertyValue $obj 'paper_key' ([System.IO.Path]::GetFileNameWithoutExtension($f.Name)))
                    $papers[$paperKey] = @{
                        paper_key = $paperKey
                        year = [int](Get-ObjectPropertyValue $obj 'year' 0)
                        month = [int](Get-ObjectPropertyValue $obj 'month' 0)
                        set_no = [int](Get-ObjectPropertyValue $obj 'set_no' 0)
                    }
                    $records = @($obj.questions)
                } elseif ($obj -is [System.Array]) {
                    foreach ($item in $obj) {
                        if ($item.questions) {
                            $pk = [string](Get-ObjectPropertyValue $item 'paper_key' '')
                            $papers[$pk] = @{ paper_key = $pk; year = [int](Get-ObjectPropertyValue $item 'year' 0); month = [int](Get-ObjectPropertyValue $item 'month' 0); set_no = [int](Get-ObjectPropertyValue $item 'set_no' 0) }
                            $records += @($item.questions)
                        } elseif ((Get-ObjectPropertyValue $item 'section' '') -and (Get-ObjectPropertyValue $item 'paper_key' '')) {
                            $records += $item
                        }
                    }
                }
                foreach ($rec in $records) {
                    $pk = [string](Get-ObjectPropertyValue $rec 'paper_key' '')
                    if (-not $pk -and $papers.Count -eq 1) { $pk = @($papers.Keys)[0] }
                    $paper = if ($papers.ContainsKey($pk)) { $papers[$pk] } else { @{ paper_key = $pk; year = 0; month = 0; set_no = 0 } }
                    $q = ConvertFrom-CetPracticeRecord -Record $rec -Paper $paper -Materials $materials -SeenHashes $seenHashes
                    if ($q) {
                        if ($q.year -lt $yearMin -or $q.year -gt $yearMax) { continue }
                        $newQuestions += $q
                    }
                }
            }
        } finally { Close-UiProgress }
    }

    $all = @($existingQuestions + $newQuestions)
    # Remove accidental duplicate IDs while keeping the newest.
    $byId = [ordered]@{}
    foreach ($q in $all) {
        if (-not $q.id) { continue }
        $byId[[string]$q.id] = $q
    }
    $all = @($byId.Values | Sort-Object year, month, set_no, section, q_no)

    $byType = [ordered]@{}
    foreach ($type in @('careful_reading','listening_passage','listening_news','listening_long','matching','cloze')) {
        $byType[$type] = @($all | Where-Object { $_.type -eq $type }).Count
    }
    $focus = @($all | Where-Object { $_.focus }).Count
    $targetQuestions = [int](Get-ConfigValue 'quiz.questionCount' 20) * [int](Get-ConfigValue 'plan.days' 90)
    $targetFocus = [int](Get-ConfigValue 'quiz.focusMin' 12) * [int](Get-ConfigValue 'plan.days' 90)
    $gap = @()
    if ($focus -lt $targetFocus) {
        $gap += [pscustomobject]@{
            kind = 'focus_questions'
            have = $focus
            need_slots = $targetFocus
            message = '2020-2025 的仔细阅读+听力篇章唯一题量少于 90 天×12 的题位目标。系统会用「7 天后可重复」做间隔复习；如要更多新题，需补 2015-2019 或 2026 年题目。'
            suggested_sources = @('catteacher0515/cet4-download（PDF/音频，需人工转成 JSON）', 'o-Sakurajimamai-o/cet-practice 的其他年份数据')
        }
    }
    if ($all.Count -lt $targetQuestions) {
        $gap += [pscustomobject]@{
            kind = 'total_questions'
            have = $all.Count
            need_slots = $targetQuestions
            message = '题库唯一题量低于 90 天×20 的题位数量；可依赖 7 天后间隔重出。'
        }
    }
    $report = [ordered]@{
        generated_at = (Get-Date).ToString('o')
        source = $src
        imported_new = $newQuestions.Count
        total_questions = $all.Count
        materials = $materials.Count
        by_type = $byType
        focus_questions = $focus
        target_question_slots = $targetQuestions
        target_focus_slots = $targetFocus
        duplicates_removed = ($existingQuestions.Count + $newQuestions.Count) - $all.Count
        gap_report = @($gap)
        note = '按题干+选项 SHA256 去重；不重复导入。题位不足时按 7 天后可重出规则滚动，不假装题库有 1800 道唯一题。'
    }
    if (-not $NoWrite) {
        $backupDir = Get-CET4Path 'data/backup'
        if (-not (Test-Path -LiteralPath $backupDir)) { New-Item -ItemType Directory -Force -Path $backupDir | Out-Null }
        if (Test-Path -LiteralPath $questionsPath) {
            Copy-Item -LiteralPath $questionsPath -Destination (Join-Path $backupDir ('questions-{0}.json' -f (Get-Date).ToString('yyyyMMdd-HHmmss'))) -Force
        }
        Write-JsonFile $questionsPath @($all)
        Write-JsonFile $materialsPath @($materials.Values | Sort-Object id)
        Write-JsonFile (Get-CET4Path 'data/import_report.json') $report
    }
    return [pscustomobject]$report
}
