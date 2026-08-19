Set-StrictMode -Version Latest

function Resolve-DiagLanguage {
    param([string]$Requested = '')
    $supported = @('it', 'en', 'es', 'fr', 'de')
    $candidates = @()
    if ($Requested) { $candidates += $Requested }
    if ($env:LAPTOP_DIAG_LANG) { $candidates += $env:LAPTOP_DIAG_LANG }
    try { $candidates += [CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName } catch { }
    try { $candidates += $PSUICulture } catch { }
    foreach ($c in $candidates) {
        if (-not $c) { continue }
        $two = $c.ToString().ToLowerInvariant()
        if ($two.Length -gt 2) { $two = $two.Substring(0, 2) }
        if ($supported -contains $two) { return $two }
    }
    return 'en'
}

function ConvertTo-I18nMap {
    param($Object)
    $map = @{}
    if ($null -eq $Object) { return $map }
    foreach ($p in $Object.PSObject.Properties) {
        $map[$p.Name] = [string]$p.Value
    }
    return $map
}

function Import-I18nFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return @{} }
    $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    $obj = ConvertFrom-Json -InputObject $raw
    return (ConvertTo-I18nMap $obj)
}

function Initialize-I18n {
    param(
        [string]$I18nDir,
        [string]$Requested = ''
    )
    $lang = Resolve-DiagLanguage -Requested $Requested
    $enPath = Join-Path $I18nDir 'en.json'
    $langPath = Join-Path $I18nDir ($lang + '.json')
    $en = Import-I18nFile -Path $enPath
    $cur = @{}
    foreach ($k in $en.Keys) { $cur[$k] = $en[$k] }
    if ($lang -ne 'en') {
        $over = Import-I18nFile -Path $langPath
        foreach ($k in $over.Keys) { $cur[$k] = $over[$k] }
    }
    $global:I18nMap = $cur
    $global:I18nLang = $lang
    if (Get-Variable -Name Diag -Scope Global -ErrorAction SilentlyContinue) {
        if ($global:Diag -is [hashtable]) {
            $global:Diag.Language = $lang
            $global:Diag.I18n = $cur
        }
    }
    return $lang
}

function T {
    param(
        [Parameter(Mandatory, Position = 0)][string]$Key,
        [Parameter(ValueFromRemainingArguments = $true)][object[]]$FormatArgs
    )
    $map = $null
    if (Get-Variable -Name I18nMap -Scope Global -ErrorAction SilentlyContinue) {
        $map = $global:I18nMap
    }
    $fmt = $Key
    if ($map -and $map.ContainsKey($Key)) { $fmt = $map[$Key] }
    if ($FormatArgs -and $FormatArgs.Count -gt 0) {
        try { return ($fmt -f $FormatArgs) } catch { return $fmt }
    }
    return $fmt
}
