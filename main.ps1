#requires -Version 5.1
# main.ps1 - CET4Coach local desktop entry point.

$ErrorActionPreference = 'Stop'
$script:CET4Root = $PSScriptRoot

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
# 必须在创建任何窗口/调用 EnableVisualStyles 之前设置 DPI 模式。
try { [System.Windows.Forms.Application]::SetHighDpiMode([System.Windows.Forms.HighDpiMode]::DpiUnaware) } catch { }
try { [System.Windows.Forms.Application]::EnableVisualStyles() } catch { }
try { [System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false) } catch { }

. (Join-Path $PSScriptRoot 'scripts\common.ps1')
$script:Config = Read-JsonFile (Join-Path $PSScriptRoot 'config.json') $null
if ($null -eq $script:Config) {
    [System.Windows.Forms.MessageBox]::Show("config.json 读取失败或不存在。请把整个 CET4Coach 文件夹完整复制后再运行。", '四级教练', 'OK', 'Error') | Out-Null
    exit 1
}
. (Join-Path $PSScriptRoot 'scripts\llm.ps1')
. (Join-Path $PSScriptRoot 'scripts\listening.ps1')
. (Join-Path $PSScriptRoot 'scripts\quiz_data.ps1')
. (Join-Path $PSScriptRoot 'scripts\quiz.ps1')
. (Join-Path $PSScriptRoot 'scripts\words.ps1')
. (Join-Path $PSScriptRoot 'scripts\import.ps1')
. (Join-Path $PSScriptRoot 'scripts\checkin.ps1')
. (Join-Path $PSScriptRoot 'scripts\progress.ps1')
. (Join-Path $PSScriptRoot 'scripts\study.ps1')
. (Join-Path $PSScriptRoot 'scripts\course.ps1')
. (Join-Path $PSScriptRoot 'scripts\ui.ps1')

Initialize-AppData
try { Resolve-ProgressOverlay | Out-Null } catch { }
try { Save-PortableProgress -Silent } catch { }
try { Clear-OldListeningTemp | Out-Null } catch { Write-CET4Log -Category 'startup' -Level 'WARN' -Message (Format-SafeError $_) }
Write-CET4Log -Category 'startup' -Message ('启动 CET4Coach v' + [string](Get-ConfigValue 'version' '1.0.0'))

$script:MainForm = New-MainWindow
$script:MainForm.Add_Shown({
    try {
        $state = Get-AppState
        if (-not [bool](Get-ObjectPropertyValue $state 'onboardingComplete' $false)) {
            Show-CoursePage
        } else {
            Show-HomePage
        }
        if (-not (Test-DeepSeekKeyPresent)) {
            Write-CET4Log -Category 'startup' -Level 'INFO' -Message '未设置 DEEPSEEK_API_KEY；使用本地判断。'
        }
        Show-StartupProgressDialog
    } catch {
        Show-AppMessage ('启动页面失败：' + (Format-SafeError $_)) '启动' ([System.Windows.Forms.MessageBoxIcon]::Error)
    }
})

try {
    [System.Windows.Forms.Application]::Run($script:MainForm)
} catch {
    try {
        [System.Windows.Forms.MessageBox]::Show(('程序遇到错误：' + (Format-SafeError $_) + "`n`n已写入 data/logs。"), '四级教练', 'OK', 'Error') | Out-Null
        Write-CET4Log -Category 'fatal' -Level 'ERROR' -Message (Format-SafeError $_)
    } catch { }
} finally {
    try { Stop-OwnPotPlayer } catch { }
    try { Stop-OwnMediaPlayer } catch { }
    try { if ($script:OnLeavePage) { & $script:OnLeavePage } } catch { }
    try { Close-UiProgress } catch { }
}
