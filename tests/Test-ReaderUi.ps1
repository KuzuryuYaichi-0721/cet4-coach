$ErrorActionPreference='Stop'
$root = Split-Path -Parent $PSScriptRoot
$script:CET4Root = $root
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
. (Join-Path $root 'scripts\common.ps1')
$script:Config = Read-JsonFile (Join-Path $root 'config.json')
. (Join-Path $root 'scripts\study.ps1')
$sample = "The company offers flexible hours to its employees. Researchers have found that people who sleep well are more productive at work.`n`nMany students feel tired in the morning because they stay up late. A short walk after lunch can help them focus in the afternoon."
Show-ReaderForm -Title '全屏阅读 · 大肥鱼' -Text $sample -AutoCloseMs 1200 -TestWidth 760 -TestHeight 600 -ScreenshotPath (Join-Path $root 'tests\reader.png')
Write-Host 'reader test done'
