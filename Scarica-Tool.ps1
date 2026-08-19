# Scarica LibreHardwareMonitor e smartctl nelle cartella tools\ (portatili, niente install globale).
[CmdletBinding()]
param(
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Root = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$ToolsDir = Join-Path $Root 'tools'
$SrcDir = Join-Path $Root 'src'
New-Item -ItemType Directory -Force -Path $ToolsDir | Out-Null

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
}
catch { }

$Headers = @{ 'User-Agent' = 'LaptopDiagnostica' }

function Get-Download {
    param([string]$Url, [string]$OutFile)
    Write-Host ("    Download: {0}" -f $Url) -ForegroundColor DarkGray
    Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing -Headers $Headers
}

function Get-LhmZipUrl {
    try {
        $rel = Invoke-RestMethod -Uri 'https://api.github.com/repos/LibreHardwareMonitor/LibreHardwareMonitor/releases/latest' -Headers $Headers
        $asset = $rel.assets | Where-Object { $_.name -eq 'LibreHardwareMonitor.zip' } | Select-Object -First 1
        if ($asset) { return $asset.browser_download_url }
    }
    catch { }
    return 'https://github.com/LibreHardwareMonitor/LibreHardwareMonitor/releases/download/v0.9.6/LibreHardwareMonitor.zip'
}

function Install-LibreHardwareMonitor {
    $dest = Join-Path $ToolsDir 'LibreHardwareMonitor'
    $lib = Join-Path $dest 'LibreHardwareMonitorLib.dll'
    if ((Test-Path -LiteralPath $lib) -and -not $Force) {
        Write-Host '  LibreHardwareMonitor gia presente.' -ForegroundColor Green
        return $dest
    }

    Write-Host '  Scarico LibreHardwareMonitor...' -ForegroundColor Cyan
    $zip = Join-Path $ToolsDir 'LibreHardwareMonitor.zip'
    Get-Download -Url (Get-LhmZipUrl) -OutFile $zip

    if (Test-Path -LiteralPath $dest) {
        Remove-Item -LiteralPath $dest -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    Expand-Archive -LiteralPath $zip -DestinationPath $dest -Force
    Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue

    # Se lo zip ha una cartella unica, sposta il contenuto in dest
    $libCheck = Join-Path $dest 'LibreHardwareMonitorLib.dll'
    if (-not (Test-Path -LiteralPath $libCheck)) {
        $inner = Get-ChildItem -LiteralPath $dest -Directory | Select-Object -First 1
        if ($inner) {
            Get-ChildItem -LiteralPath $inner.FullName -Force | Move-Item -Destination $dest -Force
        }
    }

    if (-not (Test-Path -LiteralPath $libCheck)) {
        throw 'LibreHardwareMonitorLib.dll non trovato dopo l''estrazione.'
    }
    Write-Host '  LibreHardwareMonitor pronto.' -ForegroundColor Green
    return $dest
}

function Install-ReadSensors {
    param([string]$LhmDir)
    $exe = Join-Path $LhmDir 'ReadSensors.exe'
    if ((Test-Path -LiteralPath $exe) -and -not $Force) {
        Write-Host '  ReadSensors.exe gia compilato.' -ForegroundColor Green
        return
    }

    $csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
    if (-not (Test-Path -LiteralPath $csc)) {
        $csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe'
    }
    if (-not (Test-Path -LiteralPath $csc)) {
        Write-Host '  csc.exe non trovato: temperature dettagliate non disponibili.' -ForegroundColor Yellow
        return
    }

    $cs = Join-Path $SrcDir 'ReadSensors.cs'
    $lib = Join-Path $LhmDir 'LibreHardwareMonitorLib.dll'
    Write-Host '  Compilo ReadSensors.exe...' -ForegroundColor Cyan
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $csc
    $psi.Arguments = "/nologo /target:exe /out:`"$exe`" /reference:`"$lib`" `"$cs`""
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.WorkingDirectory = $LhmDir
    $p = [Diagnostics.Process]::Start($psi)
    $stdout = $p.StandardOutput.ReadToEnd()
    $stderr = $p.StandardError.ReadToEnd()
    $p.WaitForExit()
    if ($p.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $exe)) {
        Write-Host "  Compilazione ReadSensors fallita (exit $($p.ExitCode))." -ForegroundColor Yellow
        if ($stdout) { Write-Host $stdout -ForegroundColor DarkGray }
        if ($stderr) { Write-Host $stderr -ForegroundColor DarkGray }
        return
    }
    Write-Host '  ReadSensors.exe pronto.' -ForegroundColor Green
}

function Get-SevenZip {
    $cmds = @('7z.exe', '7za.exe', '7zr.exe')
    foreach ($c in $cmds) {
        $cmd = Get-Command $c -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Source }
    }
    $paths = @(
        (Join-Path ${env:ProgramFiles} '7-Zip\7z.exe'),
        (Join-Path ${env:ProgramFiles(x86)} '7-Zip\7z.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\NanaZip\7z.exe')
    )
    foreach ($p in $paths) {
        if (Test-Path -LiteralPath $p) { return $p }
    }
    return $null
}

function Install-Smartctl {
    $dest = Join-Path $ToolsDir 'smartmontools'
    $existing = $null
    if (Test-Path -LiteralPath $dest) {
        $existing = Get-ChildItem -LiteralPath $dest -Filter 'smartctl.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    }
    if ($existing -and -not $Force) {
        Write-Host '  smartctl gia presente.' -ForegroundColor Green
        return $existing.FullName
    }

    Write-Host '  Scarico smartmontools (pacchetto ufficiale, estrazione locale)...' -ForegroundColor Cyan
    $setup = Join-Path $ToolsDir 'smartmontools-setup.exe'
    $url = 'https://github.com/smartmontools/smartmontools/releases/download/RELEASE_7_5/smartmontools-7.5.win32-setup.exe'
    if (-not (Test-Path -LiteralPath $setup) -or $Force) {
        Get-Download -Url $url -OutFile $setup
    }

    New-Item -ItemType Directory -Force -Path $dest | Out-Null

    $extracted = $false
    $seven = Get-SevenZip
    if ($seven) {
        Write-Host ("  Estraggo con {0}" -f $seven) -ForegroundColor DarkGray
        & $seven x $setup "-o$dest" -y | Out-Host
        if ($LASTEXITCODE -eq 0) { $extracted = $true }
    }

    if (-not $extracted) {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            $shortDest = $dest
            try {
                $fso = New-Object -ComObject Scripting.FileSystemObject
                $shortDest = $fso.GetFolder($dest).ShortPath
            }
            catch { }
            $p = Start-Process -FilePath $setup -ArgumentList "/S /D=$shortDest" -Wait -PassThru -NoNewWindow
            if ($p.ExitCode -eq 0 -or $p.ExitCode -eq 1) { $extracted = $true }
        }
    }

    Remove-Item -LiteralPath $setup -Force -ErrorAction SilentlyContinue

    $found = Get-ChildItem -LiteralPath $dest -Filter 'smartctl.exe' -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.DirectoryName -match '\\bin$' } |
        Select-Object -First 1
    if (-not $found) {
        $found = Get-ChildItem -LiteralPath $dest -Filter 'smartctl.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    }

    if (-not $found) {
        Write-Host '  smartctl non estratto: lo scan usera i dati Windows Storage.' -ForegroundColor Yellow
        return $null
    }
    Write-Host '  smartctl pronto.' -ForegroundColor Green
    return $found.FullName
}

$lhmDir = Install-LibreHardwareMonitor
Install-ReadSensors -LhmDir $lhmDir
Install-Smartctl
Write-Host 'Tool pronti.' -ForegroundColor Green
