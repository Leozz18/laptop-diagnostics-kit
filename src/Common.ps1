Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Initialize-ReportState {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$ToolsDir,
        [Parameter(Mandatory)][string]$ReportDir,
        [Parameter(Mandatory)][string]$Stamp
    )
    $global:Diag = @{
        Findings          = @()
        Meta              = [ordered]@{
            ComputerName = $env:COMPUTERNAME
            UserName     = $env:USERNAME
            GeneratedAt  = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
            IsAdmin      = (Test-IsAdmin)
            Root         = $Root
            Stamp        = $Stamp
            Language     = $(if ($global:I18nLang) { $global:I18nLang } else { 'en' })
        }
        Root              = $Root
        ToolsDir          = $ToolsDir
        ReportDir         = $ReportDir
        Stamp             = $Stamp
        BatteryReportPath = $null
        Sensors           = @()
    }
}

function Add-Finding {
    param(
        [Parameter(Mandatory)][string]$Area,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][ValidateSet('ok', 'attenzione', 'critico', 'info')][string]$Status,
        [string]$Value = '',
        [string]$Detail = '',
        [string]$Advice = ''
    )
    $global:Diag.Findings += [pscustomobject]@{
        Area    = $Area
        Name    = $Name
        Status  = $Status
        Value   = $Value
        Detail  = $Detail
        Advice  = $Advice
    }
}

function Get-OverallStatus {
    $hasCritico = $false
    $hasAttenzione = $false
    foreach ($f in $global:Diag.Findings) {
        if ($f.Status -eq 'critico') { $hasCritico = $true }
        elseif ($f.Status -eq 'attenzione') { $hasAttenzione = $true }
    }
    if ($hasCritico) { return 'critico' }
    if ($hasAttenzione) { return 'attenzione' }
    return 'ok'
}

function ConvertTo-HtmlEncode {
    param([string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return '' }
    return [System.Net.WebUtility]::HtmlEncode($Text)
}

function Get-BytesText {
    param([long]$Bytes)
    if ($Bytes -lt 0) { return (T 'nd') }
    if ($Bytes -ge 1TB) { return ('{0:N1} TB' -f ($Bytes / 1TB)) }
    if ($Bytes -ge 1GB) { return ('{0:N1} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N0} MB' -f ($Bytes / 1MB)) }
    return ('{0:N0} B' -f $Bytes)
}

function Invoke-SafeCim {
    param(
        [string]$ClassName,
        [string]$Namespace = 'root/cimv2',
        [string]$Filter = $null
    )
    try {
        $params = @{ ClassName = $ClassName; Namespace = $Namespace; ErrorAction = 'Stop' }
        if ($Filter) { $params.Filter = $Filter }
        return @(Get-CimInstance @params)
    }
    catch {
        return @()
    }
}

function Get-ShortPath {
    param([string]$Path)
    try {
        $fso = New-Object -ComObject Scripting.FileSystemObject
        if (Test-Path -LiteralPath $Path -PathType Container) {
            return $fso.GetFolder($Path).ShortPath
        }
        if (Test-Path -LiteralPath $Path -PathType Leaf) {
            return $fso.GetFile($Path).ShortPath
        }
    }
    catch { }
    return $Path
}

function Write-Step {
    param([string]$Message)
    Write-Host ("  > {0}" -f $Message) -ForegroundColor Cyan
}

function Write-Ok {
    param([string]$Message)
    Write-Host ("    OK  {0}" -f $Message) -ForegroundColor Green
}

function Write-WarnLine {
    param([string]$Message)
    Write-Host ("    !!  {0}" -f $Message) -ForegroundColor Yellow
}

function Get-SmartctlPath {
    $candidates = @(
        (Join-Path $global:Diag.ToolsDir 'smartmontools\bin\smartctl.exe'),
        (Join-Path $global:Diag.ToolsDir 'smartmontools\smartctl.exe')
    )
    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath $c) { return $c }
    }
    $smartDir = Join-Path $global:Diag.ToolsDir 'smartmontools'
    if (-not (Test-Path -LiteralPath $smartDir)) { return $null }
    $found = Get-ChildItem -LiteralPath $smartDir -Filter 'smartctl.exe' -Recurse -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($found) { return $found.FullName }
    return $null
}

function Get-LhmDir {
    $dir = Join-Path $global:Diag.ToolsDir 'LibreHardwareMonitor'
    if (Test-Path -LiteralPath (Join-Path $dir 'LibreHardwareMonitorLib.dll')) { return $dir }
    if (Test-Path -LiteralPath (Join-Path $dir 'LibreHardwareMonitor.exe')) { return $dir }
    return $null
}

function Get-ReadSensorsExe {
    $lhm = Get-LhmDir
    if (-not $lhm) { return $null }
    $exe = Join-Path $lhm 'ReadSensors.exe'
    if (Test-Path -LiteralPath $exe) { return $exe }
    return $null
}
