$files = Get-ChildItem (Join-Path (Split-Path -Parent $PSScriptRoot) '*.ps1') -Recurse -Filter *.ps1
$bad = 0
foreach ($f in $files) {
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$tokens, [ref]$errors) | Out-Null
    if ($errors.Count -gt 0) {
        $bad++
        Write-Host ('ERR ' + $f.FullName)
        foreach ($e in $errors) { Write-Host ("  {0}:{1} {2}" -f $e.Extent.StartLineNumber, $e.Extent.StartColumnNumber, $e.Message) }
    } else {
        Write-Host ('OK ' + $f.FullName.Substring($f.FullName.LastIndexOf('\') + 1))
    }
}
if ($bad -gt 0) { exit 1 }
