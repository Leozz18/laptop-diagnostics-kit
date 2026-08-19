#Requires -Version 5.1
param(
    [string]$Language = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

$SrcDir = $PSScriptRoot
$Root = Split-Path -Parent $SrcDir
$ToolsDir = Join-Path $Root 'tools'
$ReportDir = Join-Path $Root 'reports'
$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'

New-Item -ItemType Directory -Force -Path $ToolsDir, $ReportDir | Out-Null

. (Join-Path $SrcDir 'I18n.ps1')
. (Join-Path $SrcDir 'Common.ps1')
. (Join-Path $SrcDir 'Checks-Hardware.ps1')
. (Join-Path $SrcDir 'Checks-Disk.ps1')
. (Join-Path $SrcDir 'Checks-Battery.ps1')
. (Join-Path $SrcDir 'Checks-Thermal.ps1')
. (Join-Path $SrcDir 'Checks-Windows.ps1')
. (Join-Path $SrcDir 'Checks-Drivers.ps1')
. (Join-Path $SrcDir 'Report.ps1')

$lang = Initialize-I18n -I18nDir (Join-Path $SrcDir 'i18n') -Requested $Language
Initialize-ReportState -Root $Root -ToolsDir $ToolsDir -ReportDir $ReportDir -Stamp $Stamp
$global:Diag.Language = $lang
$global:Diag.I18n = $global:I18nMap
$global:Diag.Meta.Language = $lang

try { $Host.UI.RawUI.WindowTitle = (T 'app.title') } catch { }
Write-Host ''
Write-Host '========================================' -ForegroundColor DarkCyan
Write-Host ("  {0}" -f (T 'app.banner')) -ForegroundColor White
Write-Host '========================================' -ForegroundColor DarkCyan
Write-Host ("  {0}  [{1}]" -f $Root, $lang) -ForegroundColor DarkGray
Write-Host ''

if (-not (Test-IsAdmin)) {
    Write-Host ("  {0}" -f (T 'warn.not_admin')) -ForegroundColor Yellow
    Write-Host ("  {0}" -f (T 'warn.use_bat')) -ForegroundColor Yellow
    Write-Host ''
}

Write-Step (T 'step.tools')
$needTools = $false
if (-not (Get-LhmDir)) { $needTools = $true }
if (-not (Get-SmartctlPath)) { $needTools = $true }
if ($needTools) {
    $downloader = Join-Path $Root 'Scarica-Tool.ps1'
    try {
        & $downloader
    }
    catch {
        Write-WarnLine (T 'warn.tools_download' $_.Exception.Message)
        Add-Finding -Area 'Hardware' -Name (T 'finding.tools') -Status 'info' -Value (T 'finding.tools_partial') -Detail $_.Exception.Message
    }
}
else {
    Write-Ok (T 'ok.tools')
}

Invoke-CheckHardware
Invoke-CheckDisk
Invoke-CheckBattery
Invoke-CheckThermal
Invoke-CheckWindows
Invoke-CheckDrivers

$htmlPath = Join-Path $ReportDir ("diagnostica-{0}.html" -f $Stamp)
$jsonPath = Join-Path $ReportDir ("diagnostica-{0}.json" -f $Stamp)

Export-DiagnosticaJson -Path $jsonPath
Export-DiagnosticaHtml -Path $htmlPath
Show-ConsoleSummary

Write-Host ''
Write-Host ("  {0}" -f (T 'report.html' $htmlPath)) -ForegroundColor Cyan
Write-Host ("  {0}" -f (T 'report.json' $jsonPath)) -ForegroundColor DarkGray
Write-Host ''

try {
    Start-Process $htmlPath
}
catch {
    Write-WarnLine (T 'warn.browser')
}

exit 0
