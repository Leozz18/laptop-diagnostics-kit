function Export-DiagnosticaJson {
    param([string]$Path)
    try {
        $overall = [string](Get-OverallStatus)
        $rows = New-Object System.Collections.ArrayList
        foreach ($f in $global:Diag.Findings) {
            [void]$rows.Add([pscustomobject]@{
                    Area   = [string]$f.Area
                    Name   = [string]$f.Name
                    Status = [string]$f.Status
                    Value  = [string]$f.Value
                    Detail = [string]$f.Detail
                    Advice = [string]$f.Advice
                })
        }
        $payload = [pscustomobject]@{
            computer    = [string]$global:Diag.Meta.ComputerName
            user        = [string]$global:Diag.Meta.UserName
            generatedAt = [string]$global:Diag.Meta.GeneratedAt
            isAdmin     = [bool]$global:Diag.Meta.IsAdmin
            language    = [string]$global:Diag.Language
            overall     = $overall
            findings    = @($rows)
        }
        $json = ConvertTo-Json -InputObject $payload -Depth 6
        [System.IO.File]::WriteAllText($Path, $json, (New-Object System.Text.UTF8Encoding $true))
    }
    catch {
        Write-WarnLine (T 'report.json_fail' $_.Exception.Message)
    }
}

function Export-DiagnosticaHtml {
    param([string]$Path)

    $overall = Get-OverallStatus
    $overallLabel = T ("status.overall_{0}" -f $overall)
    if ($overallLabel -eq ("status.overall_{0}" -f $overall)) { $overallLabel = $overall.ToUpper() }

    $areas = @('Hardware', 'Disco', 'Batteria', 'Temperature', 'Windows', 'Driver')
    $cards = New-Object System.Text.StringBuilder
    foreach ($area in $areas) {
        $items = @($global:Diag.Findings | Where-Object { $_.Area -eq $area })
        $areaStatus = 'ok'
        foreach ($i in $items) {
            if ($i.Status -eq 'critico') { $areaStatus = 'critico'; break }
            if ($i.Status -eq 'attenzione' -and $areaStatus -ne 'critico') { $areaStatus = 'attenzione' }
        }
        $nBad = @($items | Where-Object { $_.Status -eq 'critico' -or $_.Status -eq 'attenzione' }).Count
        $n = $items.Count
        $areaTitle = T ("area.{0}" -f $area)
        [void]$cards.AppendLine(@"
<div class="card status-$areaStatus">
  <div class="card-kicker">$areaTitle</div>
  <div class="card-status">$((Get-StatusLabel $areaStatus))</div>
  <div class="card-meta">$(T 'report.items_meta' $n $nBad)</div>
</div>
"@)
    }

    $sections = New-Object System.Text.StringBuilder
    foreach ($area in $areas) {
        $items = @($global:Diag.Findings | Where-Object { $_.Area -eq $area })
        if ($items.Count -eq 0) { continue }
        $areaTitle = T ("area.{0}" -f $area)
        [void]$sections.AppendLine("<section><h2>$areaTitle</h2><table><thead><tr><th>$(T 'report.th_status')</th><th>$(T 'report.th_name')</th><th>$(T 'report.th_value')</th><th>$(T 'report.th_detail')</th></tr></thead><tbody>")
        foreach ($i in $items) {
            $name = ConvertTo-HtmlEncode $i.Name
            $val = ConvertTo-HtmlEncode $i.Value
            $det = ConvertTo-HtmlEncode $i.Detail
            if ($i.Advice) {
                $det = $det + '<div class="advice">' + (ConvertTo-HtmlEncode $i.Advice) + '</div>'
            }
            $lab = Get-StatusLabel $i.Status
            [void]$sections.AppendLine("<tr class='row-$($i.Status)'><td><span class='pill pill-$($i.Status)'>$lab</span></td><td>$name</td><td>$val</td><td>$det</td></tr>")
        }
        [void]$sections.AppendLine('</tbody></table></section>')
    }

    $adviceItems = @($global:Diag.Findings | Where-Object { $_.Advice -and $_.Status -in @('attenzione', 'critico') })
    $adviceHtml = ''
    if ($adviceItems.Count -gt 0) {
        $lis = foreach ($a in $adviceItems) {
            '<li><strong>' + (ConvertTo-HtmlEncode $a.Name) + ':</strong> ' + (ConvertTo-HtmlEncode $a.Advice) + '</li>'
        }
        $adviceHtml = '<section class="advice-box"><h2>' + (ConvertTo-HtmlEncode (T 'report.what_now')) + '</h2><ol>' + ($lis -join "`n") + '</ol></section>'
    }
    else {
        $adviceHtml = '<section class="advice-box ok"><h2>' + (ConvertTo-HtmlEncode (T 'report.what_now')) + '</h2><p>' + (ConvertTo-HtmlEncode (T 'report.no_issues')) + '</p></section>'
    }

    $adminNote = if ($global:Diag.Meta.IsAdmin) { T 'report.admin_yes' } else { T 'report.admin_no' }
    $battLink = ''
    if ($global:Diag.BatteryReportPath -and (Test-Path -LiteralPath $global:Diag.BatteryReportPath)) {
        $href = ([Uri]$global:Diag.BatteryReportPath).AbsoluteUri
        $battLink = '<p class="sub"><a href="' + $href + '">' + (ConvertTo-HtmlEncode (T 'report.battery_link')) + '</a></p>'
    }

    $htmlLang = 'en'
    if ($global:Diag.Language) { $htmlLang = $global:Diag.Language }
    $pageTitle = (T 'report.title') + ' - ' + $global:Diag.Meta.ComputerName
    $h1 = T 'report.title'
    $overallText = T 'report.overall' $overallLabel

    $html = @"
<!DOCTYPE html>
<html lang="$htmlLang">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<title>$pageTitle</title>
<style>
  :root {
    --bg: #0f1419;
    --panel: #171e27;
    --text: #e8eef4;
    --muted: #93a0ae;
    --line: #2a3542;
    --ok: #3dd68c;
    --ok-bg: rgba(61,214,140,.12);
    --warn: #f5c542;
    --warn-bg: rgba(245,197,66,.12);
    --crit: #ff6b6b;
    --crit-bg: rgba(255,107,107,.12);
    --info: #7ab8ff;
  }
  * { box-sizing: border-box; }
  body {
    margin: 0; font-family: "Segoe UI", system-ui, sans-serif;
    background: var(--bg); color: var(--text); line-height: 1.45;
  }
  header {
    padding: 28px 32px 18px; border-bottom: 1px solid var(--line);
    background: linear-gradient(180deg, #1a2430, var(--bg));
  }
  h1 { margin: 0 0 6px; font-size: 26px; font-weight: 650; }
  .sub { color: var(--muted); margin: 4px 0; }
  .badge {
    display: inline-block; margin-top: 12px; padding: 6px 12px; border-radius: 999px;
    font-weight: 700; letter-spacing: .04em; font-size: 13px;
  }
  .badge-ok { background: var(--ok-bg); color: var(--ok); }
  .badge-attenzione { background: var(--warn-bg); color: var(--warn); }
  .badge-critico { background: var(--crit-bg); color: var(--crit); }
  main { padding: 24px 32px 48px; max-width: 1200px; }
  .grid {
    display: grid; grid-template-columns: repeat(auto-fit, minmax(160px, 1fr));
    gap: 12px; margin: 8px 0 28px;
  }
  .card {
    background: var(--panel); border: 1px solid var(--line); border-radius: 12px;
    padding: 14px 14px 12px; border-top: 3px solid var(--line);
  }
  .card.status-ok { border-top-color: var(--ok); }
  .card.status-attenzione { border-top-color: var(--warn); }
  .card.status-critico { border-top-color: var(--crit); }
  .card-kicker { color: var(--muted); font-size: 12px; text-transform: uppercase; letter-spacing: .08em; }
  .card-status { font-size: 18px; font-weight: 700; margin: 6px 0 4px; }
  .card-meta { color: var(--muted); font-size: 12px; }
  section { margin-bottom: 28px; }
  h2 { font-size: 18px; margin: 0 0 10px; }
  table { width: 100%; border-collapse: collapse; background: var(--panel); border-radius: 12px; overflow: hidden; }
  th, td { text-align: left; padding: 10px 12px; vertical-align: top; font-size: 13px; }
  th { color: var(--muted); font-weight: 600; border-bottom: 1px solid var(--line); font-size: 12px; text-transform: uppercase; letter-spacing: .04em; }
  tr + tr td { border-top: 1px solid var(--line); }
  .pill { display: inline-block; padding: 2px 8px; border-radius: 999px; font-size: 11px; font-weight: 700; }
  .pill-ok { background: var(--ok-bg); color: var(--ok); }
  .pill-attenzione { background: var(--warn-bg); color: var(--warn); }
  .pill-critico { background: var(--crit-bg); color: var(--crit); }
  .pill-info { background: rgba(122,184,255,.12); color: var(--info); }
  .advice { margin-top: 6px; color: var(--warn); font-size: 12px; }
  .row-critico { background: rgba(255,107,107,.05); }
  .advice-box { background: var(--panel); border: 1px solid var(--line); border-radius: 12px; padding: 16px 20px; }
  .advice-box.ok { border-color: var(--ok); }
  .advice-box ol { margin: 8px 0 0; padding-left: 20px; }
  a { color: var(--info); }
  code { background: #0b0f14; padding: 1px 6px; border-radius: 6px; }
</style>
</head>
<body>
<header>
  <h1>$h1</h1>
  <p class="sub">$($global:Diag.Meta.ComputerName) | $($global:Diag.Meta.UserName) | $($global:Diag.Meta.GeneratedAt)</p>
  <p class="sub">$adminNote</p>
  $battLink
  <div class="badge badge-$overall">$overallText</div>
</header>
<main>
  <div class="grid">
    $($cards.ToString())
  </div>
  $adviceHtml
  $($sections.ToString())
</main>
</body>
</html>
"@

    [System.IO.File]::WriteAllText($Path, $html, (New-Object System.Text.UTF8Encoding $true))
}

function Get-StatusLabel {
    param([string]$Status)
    $k = "status.$Status"
    $lab = T $k
    if ($lab -eq $k) { return $Status }
    return $lab
}

function Show-ConsoleSummary {
    $overall = Get-OverallStatus
    $color = 'Green'
    if ($overall -eq 'attenzione') { $color = 'Yellow' }
    if ($overall -eq 'critico') { $color = 'Red' }
    Write-Host ''
    Write-Host ('  {0}' -f (T 'report.overall' (Get-StatusLabel $overall))) -ForegroundColor $color
    $bad = @($global:Diag.Findings | Where-Object { $_.Status -in @('attenzione', 'critico') })
    foreach ($b in $bad) {
        $c = if ($b.Status -eq 'critico') { 'Red' } else { 'Yellow' }
        Write-Host ('  [{0}] {1}: {2}' -f $b.Area, $b.Name, $b.Value) -ForegroundColor $c
        if ($b.Advice) { Write-Host ('      {0}' -f $b.Advice) -ForegroundColor DarkGray }
    }
    if ($bad.Count -eq 0) {
        Write-Host ('  {0}' -f (T 'console.no_issues')) -ForegroundColor Green
    }
}
