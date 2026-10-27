# listening.ps1 - organize audio, split whole papers on explicit timepoints,
# temporary workspace lifecycle, and PotPlayer playback.

$script:ActivePotPlayerPid = $null
$script:ActivePotPlayerPath = $null

function Get-FFmpegInfo {
    $ffmpeg = [string](Get-ConfigValue 'listening.ffmpeg' 'ffmpeg')
    $ffprobe = [string](Get-ConfigValue 'listening.ffprobe' 'ffprobe')
    $ffmpegCmd = Get-Command $ffmpeg -ErrorAction SilentlyContinue
    $ffprobeCmd = Get-Command $ffprobe -ErrorAction SilentlyContinue
    $ffmpegPath = if ($ffmpegCmd) { $ffmpegCmd.Source } else { $null }
    $ffprobePath = if ($ffprobeCmd) { $ffprobeCmd.Source } else { $null }
    $msg = if ($ffmpegPath) { "ffmpeg: $ffmpegPath" } else { '没有找到 ffmpeg。请先安装 ffmpeg 并把它加入 PATH，或在 config.json 里写完整路径。' }
    return [pscustomobject]@{
        Available = [bool]$ffmpegPath
        Ffmpeg = $ffmpegPath
        Ffprobe = $ffprobePath
        Message = $msg
    }
}

function Resolve-PotPlayerPath {
    $configured = [string](Get-ConfigValue 'listening.potPlayer' 'auto')
    if ($configured -and $configured -ne 'auto' -and (Test-Path -LiteralPath $configured)) { return $configured }
    foreach ($p in (Get-ConfigValue 'listening.potPlayerCandidates' @())) {
        if ($p -and (Test-Path -LiteralPath $p)) { return $p }
    }
    return $null
}

function ConvertFrom-AudioFileName {
    param([Parameter(Mandatory)][string]$Path)
    $full = [System.IO.Path]::GetFullPath($Path)
    $name = [System.IO.Path]::GetFileNameWithoutExtension($full)
    $parent = Split-Path -Parent $full
    $context = ($parent + '\' + $name)
    $context = $context -replace '（', '(' -replace '）', ')' -replace '：', ':'
    $low = $context.ToLowerInvariant()

    $year = $null
    $month = $null
    $setNo = $null
    $section = $null

    $ym = [regex]::Match($name, '(20\d{2})\s*[年._\-/]\s*(0?[1-9]|1[0-2])(?:\s*月)?')
    if ($ym.Success) {
        $year = [int]$ym.Groups[1].Value
        $month = [int]$ym.Groups[2].Value
    } else {
        $ym2 = [regex]::Match($parent, '(20\d{2})\s*[年._\-/]\s*(0?[1-9]|1[0-2])(?:\s*月)?')
        if ($ym2.Success) {
            $year = [int]$ym2.Groups[1].Value
            $month = [int]$ym2.Groups[2].Value
        }
    }
    if ($null -eq $year) {
        $onlyYear = [regex]::Match($context, '(20\d{2})')
        if ($onlyYear.Success) { $year = [int]$onlyYear.Groups[1].Value }
    }
    if ($null -eq $month) {
        $mon = [regex]::Match($context, '(?:^|[._\-/\\\\])(0?[1-9]|1[0-2])(?:[._\-/\\\\]|月|套|$)')
        if ($mon.Success) { $month = [int]$mon.Groups[1].Value }
    }

    $setPatterns = @(
        '(?i)set[\s._\-]*0?([1-3])\b',
        '(?:第|set|套)\s*0?([1-3])\s*套?',
        '(?i)(?:^|[._\-])0?([1-3])(?:[._\-]|$)'
    )
    foreach ($pat in $setPatterns) {
        $m = [regex]::Match($name, $pat)
        if ($m.Success) { $setNo = [int]$m.Groups[1].Value; break }
    }
    if ($null -eq $setNo) {
        $m = [regex]::Match($parent, '(?:第|set|套)\s*0?([1-3])\s*套?', 'IgnoreCase')
        if ($m.Success) { $setNo = [int]$m.Groups[1].Value }
    }

    $secPatterns = @(
        '(?i)section[\s._\-]*([abc])\b',
        '(?i)(?:^|[._\-\s])([abc])(?:[._\-\s]|$)',
        '短篇新闻|新闻',
        '长对话',
        '听力篇章|篇章'
    )
    $m = [regex]::Match($name, $secPatterns[0])
    if ($m.Success) { $section = $m.Groups[1].Value.ToUpperInvariant() }
    if (-not $section) {
        $m = [regex]::Match($parent, '(?i)section[\s._\-]*([abc])\b|(?:^|[\\/])([abc])(?:[\\/]|$)')
        if ($m.Success) {
            if ($m.Groups[1].Success) { $section = $m.Groups[1].Value.ToUpperInvariant() }
            elseif ($m.Groups[2].Success) { $section = $m.Groups[2].Value.ToUpperInvariant() }
        }
    }
    if (-not $section) {
        if ($low -match '短篇新闻|news') { $section = 'A' }
        elseif ($low -match '长对话|conversation') { $section = 'B' }
        elseif ($low -match '听力篇章|passage') { $section = 'C' }
    }
    if (-not $section) {
        $m = [regex]::Match($name, '(?i)(?:^|[_\-])set[\s._\-]*0?[1-3][_\-]([abc])(?:[_\-.]|$)')
        if ($m.Success) { $section = $m.Groups[1].Value.ToUpperInvariant() }
    }

    $ok = ($null -ne $year) -and ($null -ne $month) -and ($null -ne $setNo)
    $suite = if ($ok) { '{0:D4}-{1:D2}-set{2}' -f $year, $month, $setNo } else { $null }
    return [pscustomobject]@{
        Ok = $ok
        Year = $year
        Month = $month
        SetNo = $setNo
        Section = $section
        Suite = $suite
        IsSectionFile = ($ok -and $section)
        SourcePath = $full
        Reason = if (-not $ok) { '文件名或目录里没有同时识别出年份、月份、套号' } else { '' }
    }
}

function Get-AudioFiles {
    param([string]$Root)
    if (-not (Test-Path -LiteralPath $Root)) { return @() }
    return @(Get-ChildItem -LiteralPath $Root -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -in @('.mp3', '.wav', '.m4a') })
}

function Get-MediaDurationSec {
    param([string]$Path)
    $probe = (Get-FFmpegInfo).Ffprobe
    if (-not $probe) { return 0 }
    try {
        $out = & $probe '-v' 'error' '-show_entries' 'format=duration' '-of' 'default=noprint_wrappers=1:nokey=1' $Path 2>$null
        $d = 0.0
        if ([double]::TryParse(([string]$out).Trim(), [ref]$d)) { return [math]::Round($d, 1) }
    } catch { }
    return 0
}

function Get-AudioFingerprintAt {
    param([string]$Root)
    if (-not (Test-Path -LiteralPath $Root)) {
        return [pscustomobject]@{ Exists = $false; Count = 0; TotalBytes = 0; Signature = 'missing'; Root = $Root }
    }
    $files = @(Get-AudioFiles $Root)
    $count = $files.Count
    $bytes = ($files | Measure-Object Length -Sum).Sum
    if ($null -eq $bytes) { $bytes = 0 }
    $signature = '{0}-{1}' -f $count, $bytes
    return [pscustomobject]@{ Exists = $true; Count = $count; TotalBytes = [long]$bytes; Signature = $signature; Root = $Root }
}

function Get-AudioLibraryFingerprint {
    $root = Get-CET4Path (Get-ConfigValue 'paths.libraryAudio' 'library/audio')
    return (Get-AudioFingerprintAt $root)
}

function Get-AudioSourceFingerprint {
    $root = Get-CET4Path (Get-ConfigValue 'paths.sourceAudio' 'library/source_audio')
    return (Get-AudioFingerprintAt $root)
}

function Import-ListeningLibrary {
    param(
        [string]$SourceDir = '',
        [switch]$DryRun
    )
    $ff = Get-FFmpegInfo
    if (-not $ff.Available) {
        throw $ff.Message
    }
    if ([string]::IsNullOrWhiteSpace($SourceDir)) {
        $SourceDir = Get-CET4Path (Get-ConfigValue 'paths.sourceAudio' 'library/source_audio')
    }
    if (-not (Test-Path -LiteralPath $SourceDir)) {
        throw "原始素材目录不存在：$SourceDir。请把听力文件放到这里，或在 config.json 中修改 paths.sourceAudio。"
    }
    $libraryDir = Get-CET4Path (Get-ConfigValue 'paths.libraryAudio' 'library/audio')
    if (-not (Test-Path -LiteralPath $libraryDir)) { New-Item -ItemType Directory -Force -Path $libraryDir | Out-Null }
    $timepointsPath = Get-CET4Path (Get-ConfigValue 'paths.audioTimepoints' 'data/audio_timepoints.json')
    $timepoints = Read-JsonFile $timepointsPath @{} -Quiet
    $files = Get-AudioFiles $SourceDir
    $index = @{}
    $messages = @()
    $missing = @{}
    $copied = 0
    $split = 0
    $skipped = 0

    foreach ($f in $files) {
        if ($script:CET4ProgressActive) { Set-UiProgressText ("正在整理：" + $f.Name) }
        $meta = ConvertFrom-AudioFileName $f.FullName
        if (-not $meta.Ok) {
            $messages += ('[跳过] {0}：{1}' -f $f.FullName, $meta.Reason)
            continue
        }
        if (-not $missing.ContainsKey($meta.Suite)) {
            $missing[$meta.Suite] = [ordered]@{ A = $false; B = $false; C = $false; reasons = @() }
        }

        if ($meta.IsSectionFile) {
            $destDir = Join-Path $libraryDir $meta.Suite
            if ($DryRun) { $messages += ('[计划复制] {0} -> {1}' -f $f.FullName, $destDir); continue }
            if (-not (Test-Path -LiteralPath $destDir)) { New-Item -ItemType Directory -Force -Path $destDir | Out-Null }
            $ext = $f.Extension.ToLowerInvariant()
            $dest = Join-Path $destDir ('Section{0}{1}' -f $meta.Section, $ext)
            $doCopy = $true
            if (Test-Path -LiteralPath $dest) {
                $srcHash = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash
                $dstHash = (Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash
                if ($srcHash -eq $dstHash) { $doCopy = $false; $skipped++ }
            }
            if ($doCopy) {
                Copy-Item -LiteralPath $f.FullName -Destination $dest -Force
                $copied++
            }
            $audioId = '{0}-Section{1}' -f $meta.Suite, $meta.Section
            $index[$audioId] = [ordered]@{
                audio_id = $audioId
                suite = $meta.Suite
                year = $meta.Year
                month = $meta.Month
                set_no = $meta.SetNo
                section = $meta.Section
                path = $dest
                duration_sec = (Get-MediaDurationSec $dest)
                source = $f.FullName
                source_kind = 'pre-split'
                created_at = (Get-Date).ToString('o')
            }
            $missing[$meta.Suite][$meta.Section] = $true
            continue
        }

        # Whole-paper file: require explicit timepoints. Never guess.
        $key = $meta.Suite
        $tp = Get-ObjectPropertyValue $timepoints $key $null
        if ($null -eq $tp) {
            $altKeys = @($key, $key -replace '-0(\d)-', '-$1-', $meta.Suite)
            foreach ($ak in $altKeys) {
                if ($ak -ne $key) {
                    $candidate = Get-ObjectPropertyValue $timepoints $ak $null
                    if ($null -ne $candidate) { $tp = $candidate; break }
                }
            }
        }
        if ($null -eq $tp) {
            $missing[$meta.Suite].reasons += '整卷文件需要 data/audio_timepoints.json 中该套卷的起止秒；没有猜测切分。'
            $messages += ('[缺时间点] {0}（套卷 {1}）。请在 audio_timepoints.json 补充 A/B/C 起止秒后再整理。' -f $f.Name, $meta.Suite)
            continue
        }
        $ext = $f.Extension.ToLowerInvariant()
        $destDir = Join-Path $libraryDir $meta.Suite
        if (-not $DryRun -and -not (Test-Path -LiteralPath $destDir)) { New-Item -ItemType Directory -Force -Path $destDir | Out-Null }
        foreach ($sec in @('A', 'B', 'C')) {
            $range = Get-ObjectPropertyValue $tp ('Section' + $sec) $null
            if ($null -eq $range -or $range.Count -lt 2) {
                $missing[$meta.Suite].reasons += ('缺少 Section{0} 时间点' -f $sec)
                continue
            }
            $start = [double]$range[0]
            $end = [double]$range[1]
            if ($end -le $start -or $start -lt 0) {
                $missing[$meta.Suite].reasons += ('Section{0} 时间点无效：{1}-{2}' -f $sec, $start, $end)
                continue
            }
            $dest = Join-Path $destDir ('Section{0}{1}' -f $sec, $ext)
            if ($DryRun) { $messages += ('[计划切分] {0} {1}-{2}s -> {3}' -f $f.Name, $start, $end, $dest); continue }
            try {
                if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Force }
                & $ff.Ffmpeg '-hide_banner' '-loglevel' 'error' '-y' '-ss' ([string]$start) '-to' ([string]$end) '-i' $f.FullName '-c' 'copy' $dest 2>$null
                if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $dest)) {
                    throw ('ffmpeg 退出码 {0}' -f $LASTEXITCODE)
                }
                $split++
                $audioId = '{0}-Section{1}' -f $meta.Suite, $sec
                $index[$audioId] = [ordered]@{
                    audio_id = $audioId; suite = $meta.Suite; year = $meta.Year; month = $meta.Month;
                    set_no = $meta.SetNo; section = $sec; path = $dest;
                    duration_sec = (Get-MediaDurationSec $dest); source = $f.FullName;
                    source_kind = 'split'; created_at = (Get-Date).ToString('o')
                }
                $missing[$meta.Suite][$sec] = $true
            } catch {
                $messages += ('[切分失败] {0} Section{1}：{2}' -f $f.Name, $sec, (Format-SafeError $_))
            }
        }
    }

    if (-not $DryRun) {
        # Rebuild index from the library itself so a repeated import cannot duplicate entries.
        $existingById = @{}
        foreach ($entry in @(Read-JsonFile (Get-ConfigValue 'paths.audioIndex' 'library/audio/index.json') @() -Quiet)) {
            if ($entry -and $entry.audio_id) { $existingById[[string]$entry.audio_id] = $entry }
        }
        foreach ($k in $index.Keys) { $existingById[$k] = $index[$k] }
        $all = @($existingById.Values | Sort-Object suite, section)
        Write-JsonFile (Get-ConfigValue 'paths.audioIndex' 'library/audio/index.json') $all
    }

    $gap = @()
    foreach ($suite in $missing.Keys) {
        $m = $missing[$suite]
        $miss = @()
        foreach ($sec in @('A', 'B', 'C')) { if (-not $m[$sec]) { $miss += ('Section' + $sec) } }
        if ($miss.Count -gt 0) {
            $gap += [pscustomobject]@{
                suite = $suite
                missing_sections = $miss
                reason = ($m.reasons | Select-Object -Unique) -join '；'
                hint = '把缺的 Section 单独文件放进原始素材目录，或在 audio_timepoints.json 补时间点后重新整理。'
            }
        }
    }
    if (-not $DryRun) {
        Write-JsonFile (Get-CET4Path 'data/audio_missing_report.json') @($gap)
    }
    return [pscustomobject]@{
        Ok = $true
        SourceDir = $SourceDir
        Scanned = $files.Count
        Copied = $copied
        Split = $split
        AlreadyPresent = $skipped
        Missing = @($gap)
        Messages = @($messages)
        LibraryFingerprint = Get-AudioLibraryFingerprint
    }
}

function Get-AudioIndex {
    $idx = Read-JsonFile (Get-ConfigValue 'paths.audioIndex' 'library/audio/index.json') @() -Quiet
    return @($idx)
}

function Get-QuestionTranscript {
    param($Question)
    if ($null -eq $Question) { return '' }
    $mat = Get-QuizMaterial $Question
    if ($null -eq $mat) { return '' }
    $t = [string](Get-ObjectPropertyValue $mat 'transcript' '')
    if (-not $t) { $t = [string](Get-ObjectPropertyValue $mat 'text' '') }
    return $t
}

function Test-ListeningSpeechAvailable {
    # 无原音频时用浏览器 speechSynthesis 朗读；Windows 10/11 自带 Edge/Chrome 即可。
    return $true
}

function Start-BrowserListening {
    param(
        [Parameter(Mandatory)][string]$Text,
        [string]$QuestionId = ''
    )
    if ([string]::IsNullOrWhiteSpace($Text)) { throw '没有可朗读的听力文本。' }
    $dir = Get-ListeningTempDir
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $safe = ($QuestionId -replace '[^A-Za-z0-9_-]', '_')
    if (-not $safe) { $safe = 'listening' }
    $htmlPath = Join-Path $dir ('speech-' + $safe + '.html')
    $jsonText = (ConvertTo-Json -InputObject $Text -Compress).Replace('</','<\/')
    $htmlTemplate = @'
<!doctype html>
<html lang="zh-CN"><head><meta charset="utf-8">
<title>大肥鱼听力</title>
<style>
body{margin:0;background:#0f1d46;color:#eef4ff;font:16px/1.6 'Microsoft YaHei',sans-serif;display:flex;min-height:100vh;align-items:center;justify-content:center}
.card{width:min(580px,92vw);background:#16295e;border:1px solid #4d6bfe;border-radius:18px;padding:26px 30px;box-shadow:0 18px 50px #0008}
h1{font-size:22px;margin:0 0 8px;color:#fff}
p{margin:0 0 12px;color:#b9c8ef;min-height:24px}
.hint{font-size:13px;color:#8fa5d8;margin:14px 0 0}
button{border:0;border-radius:10px;padding:11px 18px;font-size:15px;margin:0 10px 10px 0;cursor:pointer;background:#4d6bfe;color:#fff}
button.primary{font-size:18px;padding:14px 26px}
button.ghost{background:#263c7a}
</style></head><body><div class="card">
<h1>🎧 大肥鱼听力</h1>
<p id="status">正在准备语音…</p>
<button class="primary" onclick="start()">▶ 开始播放</button>
<button class="ghost" onclick="stopAll()">停止</button>
<button class="ghost" onclick="window.close()">关闭</button>
<div class="hint">浏览器需要一次点击才允许播放。若自动播放被拦截，点“开始播放”即可。</div>
</div>
<script>
const text = __TEXT__;
let chunks = [], idx = 0, playing = false, watchdog = null, voice = null, lastEvent = Date.now();
function setStatus(s) { document.getElementById('status').textContent = s; }
function splitText(t) {
  t = (t || '').replace(/\s+/g, ' ').trim();
  if (!t) return [];
  const sentences = t.match(/[^.!?]+[.!?]+["']?|\S[^.!?]*$/g) || [t];
  const out = [];
  for (let sentence of sentences) {
    sentence = sentence.trim();
    if (!sentence) continue;
    if (sentence.length <= 180) { out.push(sentence); continue; }
    let words = sentence.split(' '), cur = '';
    for (let w of words) {
      if ((cur + ' ' + w).trim().length > 180) { if (cur) out.push(cur.trim()); cur = w; }
      else { cur = (cur + ' ' + w).trim(); }
    }
    if (cur) out.push(cur.trim());
  }
  return out.filter(Boolean);
}
function pickVoice() {
  if (!('speechSynthesis' in window)) return;
  const voices = speechSynthesis.getVoices() || [];
  voice = voices.find(v => /^en[-_]/i.test(v.lang) && /US|United States|Zira|Aria|Jenny|Guy/i.test(v.name + ' ' + v.lang))
       || voices.find(v => /^en[-_]/i.test(v.lang)) || null;
}
function finish() {
  playing = false; if (watchdog) { clearInterval(watchdog); watchdog = null; }
  setStatus('播放结束，可以回答题页了');
}
function nextChunk() {
  if (!playing) return;
  if (idx >= chunks.length) { finish(); return; }
  lastEvent = Date.now();
  const u = new SpeechSynthesisUtterance(chunks[idx]);
  u.lang = 'en-US'; u.rate = 0.90; u.pitch = 1.0; u.volume = 1.0;
  if (voice) u.voice = voice;
  u.onstart = () => { lastEvent = Date.now(); setStatus('正在朗读（' + (idx + 1) + '/' + chunks.length + '）'); };
  u.onend = () => { if (!playing) return; lastEvent = Date.now(); idx++; setTimeout(nextChunk, 180); };
  u.onerror = (e) => {
    if (!playing) return;
    if (e && e.error === 'interrupted') return;
    lastEvent = Date.now(); idx++; setTimeout(nextChunk, 220);
  };
  try { speechSynthesis.speak(u); } catch (e) { finish(); setStatus('浏览器无法朗读，请改用逐词讲解看原文。'); }
}
function start() {
  if (!('speechSynthesis' in window)) { setStatus('这个浏览器不支持语音朗读，请用逐词讲解看原文。'); return; }
  speechSynthesis.cancel();
  playing = true; idx = 0; lastEvent = Date.now();
  setStatus('正在启动语音…');
  if (watchdog) clearInterval(watchdog);
  watchdog = setInterval(() => {
    if (!playing || !('speechSynthesis' in window)) return;
    if (speechSynthesis.paused) { try { speechSynthesis.resume(); } catch (e) { } }
    if (!speechSynthesis.speaking && !speechSynthesis.pending && Date.now() - lastEvent > 8000 && idx < chunks.length) {
      idx++; lastEvent = Date.now(); nextChunk();
    }
  }, 2500);
  setTimeout(() => { if (playing && idx === 0 && !speechSynthesis.speaking) setStatus('自动播放被拦截了，请点“开始播放”。'); }, 1600);
  nextChunk();
}
function stopAll() {
  playing = false;
  if (watchdog) { clearInterval(watchdog); watchdog = null; }
  try { speechSynthesis.cancel(); } catch (e) { }
  setStatus('已停止');
}
window.onload = () => {
  chunks = splitText(text);
  if ('speechSynthesis' in window) {
    pickVoice();
    speechSynthesis.onvoiceschanged = pickVoice;
  }
  setStatus(chunks.length ? ('准备播放，共 ' + chunks.length + ' 段') : '没有可朗读的文本');
  setTimeout(() => { if (chunks.length) start(); }, 400);
};
</script></body></html>
'@
    $html = $htmlTemplate.Replace('__TEXT__', $jsonText)
    [IO.File]::WriteAllText($htmlPath, $html, (New-Object Text.UTF8Encoding($false)))
    $edgeCandidates = @()
    if ($env:ProgramFiles) { $edgeCandidates += (Join-Path $env:ProgramFiles 'Microsoft\Edge\Application\msedge.exe') }
    if (${env:ProgramFiles(x86)}) { $edgeCandidates += (Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe') }
    $edge = @($edgeCandidates | Where-Object { Test-Path -LiteralPath $_ }) | Select-Object -First 1
    $uri = ([uri]$htmlPath).AbsoluteUri
    if ($edge) {
        return (Start-Process -FilePath $edge -ArgumentList @("--app=$uri", '--window-size=620,360') -PassThru)
    }
    return (Start-Process -FilePath $htmlPath -PassThru)
}

function Split-ListeningText {
    param([string]$Text, [int]$MaxChars = 180)
    if ([string]::IsNullOrWhiteSpace($Text)) { return @() }
    $clean = ($Text -replace '\s+', ' ').Trim()
    $sentences = [regex]::Split($clean, '(?<=[.!?])\s+')
    $parts = New-Object System.Collections.Generic.List[string]
    $cur = ''
    foreach ($sentence in $sentences) {
        $s = $sentence.Trim()
        if (-not $s) { continue }
        if ($cur -and (($cur + ' ' + $s).Length -le $MaxChars)) { $cur = $cur + ' ' + $s; continue }
        if ($cur) { $parts.Add($cur.Trim()); $cur = '' }
        if ($s.Length -le $MaxChars) { $cur = $s; continue }
        $words = $s -split '\s+'
        foreach ($w in $words) {
            $next = if ($cur) { $cur + ' ' + $w } else { $w }
            if ($next.Length -gt $MaxChars) {
                if ($cur) { $parts.Add($cur.Trim()) }
                $cur = $w
            } else { $cur = $next }
        }
    }
    if ($cur) { $parts.Add($cur.Trim()) }
    return @($parts)
}
function Test-DownloadedAudioFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $len = (Get-Item -LiteralPath $Path).Length
    if ($len -lt 900) { return $false }
    try {
        $fs = [IO.File]::OpenRead($Path)
        $b = New-Object byte[] 4
        [void]$fs.Read($b, 0, 4); $fs.Dispose()
        if ($b[0] -eq 0x49 -and $b[1] -eq 0x44 -and $b[2] -eq 0x33) { return $true } # ID3
        if ($b[0] -eq 0x52 -and $b[1] -eq 0x49 -and $b[2] -eq 0x46 -and $b[3] -eq 0x46) { return $true } # RIFF
        if ($b[0] -eq 0xFF -and ($b[1] -band 0xE0) -eq 0xE0) { return $true } # MPEG frame
    } catch { }
    return $false
}

function New-ListeningDownloadedAudio {
    param($Question)
    $text = Get-QuestionTranscript $Question
    if ([string]::IsNullOrWhiteSpace($text)) { throw '这道题没有听力原文，无法下载语音。' }
    $segments = @(Split-ListeningText $text 180)
    if ($segments.Count -eq 0) { throw '听力原文为空。' }
    $dir = Join-Path (Get-ListeningTempDir) 'downloaded'
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $sha = [Security.Cryptography.SHA256]::Create()
    $hash = ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($text)))).Replace('-','').ToLowerInvariant().Substring(0,16)
    $sha.Dispose()
    $out = Join-Path $dir ('tts-' + $hash + '.mp3')
    if ((Test-Path -LiteralPath $out) -and (Test-DownloadedAudioFile $out)) { return $out }

    $providers = @(
        @{ Name = 'youdao'; Url = 'https://dict.youdao.com/dictvoice?audio={0}&type=2' },
        @{ Name = 'baidu'; Url = 'https://fanyi.baidu.com/gettts?lan=en&text={0}&spd=3&source=web' },
        @{ Name = 'google'; Url = 'https://translate.google.com/translate_tts?ie=UTF-8&client=tw-ob&tl=en&q={0}' },
        @{ Name = 'streamelements'; Url = 'https://api.streamelements.com/kappa/v2/speech?voice=Brian&text={0}' }
    )
    $parts = @()
    $deadline = (Get-Date).AddSeconds(60)
    $i = 0
    foreach ($seg in $segments) {
        if ((Get-Date) -gt $deadline) { throw '下载超时（60 秒）。请检查网络，或先把听力音频放进 library/audio。' }
        $i++
        $part = Join-Path $dir ('tts-' + $hash + ('-{0}.mp3' -f $i))
        $got = $false
        foreach ($p in $providers) {
            if ($got) { break }
            try {
                $enc = [uri]::EscapeDataString($seg)
                $url = [string]$p.Url -f $enc
                if (Test-Path -LiteralPath $part) { Remove-Item -LiteralPath $part -Force -ErrorAction SilentlyContinue }
                Invoke-WebRequest -Uri $url -OutFile $part -TimeoutSec 15 -UseBasicParsing -Headers @{
                    'User-Agent' = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'
                    'Referer' = 'https://www.youdao.com/'
                } | Out-Null
                if (Test-DownloadedAudioFile $part) { $got = $true; $parts += $part }
            } catch { }
        }
        if (-not $got) {
            throw ('第 {0} 段语音下载失败。请检查网络，或先把听力音频放进 library/audio 再整理。' -f $i)
        }
    }
    if ($parts.Count -eq 1) {
        Move-Item -LiteralPath $parts[0] -Destination $out -Force
    } else {
        $ff = Get-FFmpegInfo
        if ($ff.Available) {
            $list = Join-Path $dir ('list-' + $hash + '.txt')
            $lines = @()
            foreach ($part in $parts) {
                $escaped = $part.Replace("'", "'\''")
                $lines += ("file '{0}'" -f $escaped)
            }
            [IO.File]::WriteAllLines($list, $lines, (New-Object Text.UTF8Encoding($false)))
            & $ff.Ffmpeg '-hide_banner' '-loglevel' 'error' '-y' '-f' 'concat' '-safe' '0' '-i' $list '-c' 'copy' $out 2>$null
            if (-not (Test-DownloadedAudioFile $out)) { throw '语音合并失败。' }
            Remove-Item -LiteralPath $list -Force -ErrorAction SilentlyContinue
        } else {
            $bytes = New-Object System.Collections.Generic.List[byte]
            foreach ($part in $parts) { $bytes.AddRange([IO.File]::ReadAllBytes($part)) }
            [IO.File]::WriteAllBytes($out, $bytes.ToArray())
        }
        foreach ($part in $parts) { Remove-Item -LiteralPath $part -Force -ErrorAction SilentlyContinue }
    }
    if (-not (Test-DownloadedAudioFile $out)) { throw '语音文件下载后校验失败。' }
    return $out
}

function Register-ListeningFileCleanup {
    param([string]$Path, [int]$ProcessId)
    if (-not $Path) { return }
    $cleanupScript = "Wait-Process -Id $ProcessId -ErrorAction SilentlyContinue; Remove-Item -LiteralPath '$Path' -Force -ErrorAction SilentlyContinue"
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($cleanupScript))
    try {
        Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-WindowStyle','Hidden','-EncodedCommand',$encoded) -WindowStyle Hidden | Out-Null
    } catch { }
}


function Find-ListeningAudio {
    param([string]$Suite, [string]$Section)
    $want = ('{0}-Section{1}' -f $Suite, $Section).ToLowerInvariant()
    foreach ($a in (Get-AudioIndex)) {
        if ([string]$a.audio_id -and ([string]$a.audio_id).ToLowerInvariant() -eq $want) {
            if (Test-Path -LiteralPath ([string]$a.path)) { return $a }
        }
    }
    # Also accept an index entry whose suite/section fields match.
    foreach ($a in (Get-AudioIndex)) {
        if ([string]$a.suite -eq $Suite -and [string]$a.section -eq $Section -and (Test-Path -LiteralPath ([string]$a.path))) {
            return $a
        }
    }
    return $null
}

function Get-ListeningTempRoot {
    $base = Join-Path ([System.IO.Path]::GetTempPath()) 'CET4Coach'
    return $base
}

function Get-ListeningTempDir {
    param([string]$Date = (Get-TodayString))
    return (Join-Path (Get-ListeningTempRoot) ('listening_' + $Date))
}

function Initialize-ListeningTempWorkspace {
    param(
        [string]$Date = (Get-TodayString),
        [array]$NeededAudio = @()
    )
    $root = Get-ListeningTempRoot
    if (-not (Test-Path -LiteralPath $root)) { New-Item -ItemType Directory -Force -Path $root | Out-Null }
    $dir = Get-ListeningTempDir $Date
    if (Test-Path -LiteralPath $dir) { Remove-Item -LiteralPath $dir -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $items = @()
    $missing = @()
    foreach ($need in @($NeededAudio)) {
        if (-not $need) { continue }
        $suite = [string](Get-ObjectPropertyValue $need 'suite' '')
        $section = [string](Get-ObjectPropertyValue $need 'section' '')
        if (-not $suite -or -not $section) { continue }
        $found = Find-ListeningAudio -Suite $suite -Section $section
        if (-not $found) {
            $missing += ('{0} Section{1}' -f $suite, $section)
            continue
        }
        $src = [string]$found.path
        $targetDir = Join-Path $dir $suite
        if (-not (Test-Path -LiteralPath $targetDir)) { New-Item -ItemType Directory -Force -Path $targetDir | Out-Null }
        $target = Join-Path $targetDir ('Section' + $section + [System.IO.Path]::GetExtension($src))
        Copy-Item -LiteralPath $src -Destination $target -Force
        $hash = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
        $items += [ordered]@{
            audio_id = [string]$found.audio_id
            suite = $suite
            section = $section
            source = $src
            temp_path = $target
            sha256 = $hash
            size = (Get-Item -LiteralPath $target).Length
        }
    }
    $sourceFp = Get-AudioLibraryFingerprint
    $manifest = [ordered]@{
        version = 1
        created_at = (Get-Date).ToString('o')
        date = $Date
        items = $items
        missing = $missing
        source_fingerprint = $sourceFp
        note = '临时听力文件只用于今天。单词任务结束时会删除，源音频库不会变动。'
    }
    Write-JsonFile (Join-Path $dir 'manifest.json') $manifest
    return [pscustomobject]@{ Dir = $dir; Manifest = $manifest; Missing = $missing }
}

function Clear-ListeningTempWorkspace {
    param(
        [string]$Date = (Get-TodayString),
        [switch]$Silent
    )
    $dir = Get-ListeningTempDir $Date
    $before = Get-AudioLibraryFingerprint
    $sourceBefore = Get-AudioSourceFingerprint
    $deleted = 0
    if (Test-Path -LiteralPath $dir) {
        $files = @(Get-ChildItem -LiteralPath $dir -Recurse -File -ErrorAction SilentlyContinue)
        $deleted = $files.Count
        # Only touch the per-day temp directory, never library/audio.
        $full = [System.IO.Path]::GetFullPath($dir)
        $tempRoot = [System.IO.Path]::GetFullPath((Join-Path ([System.IO.Path]::GetTempPath()) 'CET4Coach'))
        if (-not $full.StartsWith($tempRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw '拒绝清理：目标不在临时目录内。'
        }
        Remove-Item -LiteralPath $full -Recurse -Force -ErrorAction SilentlyContinue
    }
    $after = Get-AudioLibraryFingerprint
    $sourceAfter = Get-AudioSourceFingerprint
    $unchanged = ($before.Signature -eq $after.Signature) -and ($sourceBefore.Signature -eq $sourceAfter.Signature)
    $msg = if ($unchanged) {
        '已删除临时文件 {0} 个，源音频目录未变动（临时区与原始素材均只读校验通过）。' -f $deleted
    } else {
        '已删除临时文件 {0} 个；注意：源目录的指纹发生了变化（library {1}->{2}；source {3}->{4}）。程序没有删除源目录，请检查是否有其他程序改动。' -f $deleted, $before.Signature, $after.Signature, $sourceBefore.Signature, $sourceAfter.Signature
    }
    $logDir = Get-CET4Path (Get-ConfigValue 'paths.logs' 'data/logs')
    if (-not (Test-Path -LiteralPath $logDir)) { New-Item -ItemType Directory -Force -Path $logDir | Out-Null }
    $logFile = Join-Path $logDir ('cleanup-{0}.log' -f $Date)
    $line = '[{0}] {1} 临时目录={2} 删除文件={3} library前={4} library后={5} source前={6} source后={7}' -f (Get-NowStamp), $msg, $dir, $deleted, $before.Signature, $after.Signature, $sourceBefore.Signature, $sourceAfter.Signature
    [System.IO.File]::AppendAllText($logFile, $line + [Environment]::NewLine, [System.Text.Encoding]::UTF8)
    if (-not $Silent) { Set-StatusBar $msg }
    return [pscustomobject]@{
        DeletedFiles = $deleted
        Directory = $dir
        SourceBefore = $before
        SourceAfter = $after
        SourceAudioBefore = $sourceBefore
        SourceAudioAfter = $sourceAfter
        SourceUnchanged = $unchanged
        Message = $msg
        LogFile = $logFile
    }
}

function Clear-OldListeningTemp {
    $root = Get-ListeningTempRoot
    if (-not (Test-Path -LiteralPath $root)) { return @() }
    $cutoff = (Get-Date).AddHours(-1 * [int](Get-ConfigValue 'listening.cleanupOlderThanHours' 24))
    $removed = @()
    foreach ($d in @(Get-ChildItem -LiteralPath $root -Directory -Filter 'listening_*' -ErrorAction SilentlyContinue)) {
        if ($d.LastWriteTime -lt $cutoff) {
            $datePart = $d.Name -replace '^listening_', ''
            try {
                $res = Clear-ListeningTempWorkspace -Date $datePart -Silent
                $removed += $res
            } catch {
                Write-CET4Log -Category 'cleanup' -Level 'WARN' -Message ('清理旧临时目录失败 {0}: {1}' -f $d.FullName, (Format-SafeError $_))
            }
        }
    }
    return $removed
}

function Start-ListeningPlayback {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { throw "找不到要播放的临时音频：$Path" }
    $player = Resolve-PotPlayerPath
    if (-not $player) {
        throw '没有找到 PotPlayer。请安装 PotPlayer，或在 config.json 的 listening.potPlayer 里填写 PotPlayerMini64.exe 的完整路径。'
    }
    Stop-OwnPotPlayer
    $proc = Start-Process -FilePath $player -ArgumentList @(('"' + $Path + '"'), '/close') -PassThru
    $script:ActivePotPlayerPid = $proc.Id
    $script:ActivePotPlayerPath = $player
    return $proc
}

function Stop-OwnPotPlayer {
    $pidToStop = $script:ActivePotPlayerPid
    $playerPath = $script:ActivePotPlayerPath
    $script:ActivePotPlayerPid = $null
    if (-not $pidToStop) { return }
    try {
        $p = Get-Process -Id $pidToStop -ErrorAction Stop
        $ok = $true
        try {
            if ($playerPath -and $p.Path -and ($p.Path -ne $playerPath)) { $ok = $false }
        } catch { }
        if ($ok) { Stop-Process -Id $pidToStop -Force -ErrorAction SilentlyContinue }
    } catch { }
}

function Get-NeededAudioFromPlan {
    param($Plan)
    $needed = @()
    if ($null -eq $Plan) { return $needed }
    foreach ($q in @($Plan.questions)) {
        if ($null -eq $q) { continue }
        $audio = Get-ObjectPropertyValue $q 'audio' $null
        if ($null -eq $audio) { continue }
        if ([string](Get-ObjectPropertyValue $audio 'suite' '')) {
            $needed += [pscustomobject]@{
                suite = [string](Get-ObjectPropertyValue $audio 'suite' '')
                section = [string](Get-ObjectPropertyValue $audio 'section' '')
                audio_id = [string](Get-ObjectPropertyValue $audio 'audio_id' '')
            }
        }
    }
    return @($needed | Sort-Object suite, section -Unique)
}
