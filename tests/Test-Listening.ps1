$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$script:CET4Root = $root
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
. (Join-Path $root 'scripts\common.ps1')
$script:Config = Read-JsonFile (Join-Path $root 'config.json')
. (Join-Path $root 'scripts\llm.ps1')
. (Join-Path $root 'scripts\listening.ps1')

$testRoot = Join-Path $root 'temp\audio-test'
if (Test-Path $testRoot) { Remove-Item $testRoot -Recurse -Force }
$sourceDir = Join-Path $testRoot 'source'
$libDir = Join-Path $testRoot 'library'
New-Item -ItemType Directory -Force -Path $sourceDir, $libDir | Out-Null
$tpPath = Join-Path $testRoot 'timepoints.json'
$idxPath = Join-Path $libDir 'index.json'
Write-JsonFile $tpPath ([ordered]@{
    '2099-01-set1' = [ordered]@{ SectionA = @(0, 1); SectionB = @(1, 2); SectionC = @(2, 3) }
    '2099-02-set1' = [ordered]@{ SectionA = @(0, 999); SectionB = @(0, 999); SectionC = @(0, 999) }
})
Set-ObjectPropertyValue $script:Config.paths 'sourceAudio' $sourceDir
Set-ObjectPropertyValue $script:Config.paths 'libraryAudio' $libDir
Set-ObjectPropertyValue $script:Config.paths 'audioIndex' $idxPath
Set-ObjectPropertyValue $script:Config.paths 'audioTimepoints' $tpPath

$whole = Join-Path $sourceDir '2099.01_set1.mp3'
$part = Join-Path $sourceDir '2099.02_set1_SectionA.mp3'
& ffmpeg -hide_banner -loglevel error -y -f lavfi -i 'sine=frequency=440:duration=3' -q:a 9 $whole
& ffmpeg -hide_banner -loglevel error -y -f lavfi -i 'sine=frequency=660:duration=1' -q:a 9 $part
if ($LASTEXITCODE -ne 0) { throw 'ffmpeg sample generation failed' }
$sourceCount = @(Get-ChildItem $sourceDir -File).Count
$sourceSig = Get-AudioLibraryFingerprint
$r = Import-ListeningLibrary -SourceDir $sourceDir
Write-Host "import: scanned=$($r.Scanned) copied=$($r.Copied) split=$($r.Split) missing=$(@($r.Missing).Count)"
$files = @(Get-ChildItem $libDir -Recurse -File | Where-Object { $_.Extension -in @('.mp3','.wav','.m4a') })
foreach ($f in $files) { Write-Host "lib: $($f.FullName) $($f.Length)" }
$idx = @(Get-AudioIndex)
Write-Host "index count: $($idx.Count)"
if ($idx.Count -ne 4) { throw "expected 4 index entries, got $($idx.Count)" }
if (@(Get-ChildItem $sourceDir -File).Count -ne $sourceCount) { throw 'source files changed' }

# Needed audio: one suite with all sections + one pre-split; copy and clean.
$needed = @(
    [pscustomobject]@{ suite='2099-01-set1'; section='A' },
    [pscustomobject]@{ suite='2099-01-set1'; section='B' },
    [pscustomobject]@{ suite='2099-02-set1'; section='A' }
)
$temp = Initialize-ListeningTempWorkspace -Date '2099-01-01' -NeededAudio $needed
Write-Host "temp items: $(@($temp.Manifest.items).Count), dir=$($temp.Dir)"
if (@($temp.Manifest.items).Count -ne 3) { throw 'temp items count mismatch' }
$before = Get-AudioLibraryFingerprint
$clean = Clear-ListeningTempWorkspace -Date '2099-01-01'
Write-Host "cleanup: deleted=$($clean.DeletedFiles) unchanged=$($clean.SourceUnchanged) msg=$($clean.Message)"
if (-not $clean.SourceUnchanged) { throw 'source fingerprint changed' }
if (Test-Path $temp.Dir) { throw 'temp dir still exists' }
Write-Host "parser checks:"
foreach ($name in @('2023.06_set1.mp3','2023年6月第1套.mp3','2023_06_set1_sectionA.mp3','cet4-2021-06-set-01.mp3')) {
    $p = Join-Path $testRoot $name
    $m = ConvertFrom-AudioFileName $p
    Write-Host "$name -> ok=$($m.Ok) suite=$($m.Suite) section=$($m.Section)"
}
if (Test-Path $testRoot) { Remove-Item $testRoot -Recurse -Force }
Write-Host 'Listening tests passed'
