function Invoke-CheckWindows {
    Write-Step (T 'step.windows')

    $pending = Test-PendingReboot
    if ($pending) {
        Add-Finding -Area 'Windows' -Name (T 'win.reboot') -Status 'attenzione' -Value (T 'win.yes') -Detail (T 'win.reboot_detail') -Advice (T 'win.reboot_advice')
    }
    else {
        Add-Finding -Area 'Windows' -Name (T 'win.reboot') -Status 'ok' -Value (T 'win.no')
    }

    $dismState = 'n/d'
    $dismSt = 'info'
    $dismAdv = ''
    $dismDetail = T 'win.dism_need_admin'
    if (Test-IsAdmin) {
        try {
            $img = Repair-WindowsImage -Online -CheckHealth -ErrorAction Stop
            $dismState = [string]$img.ImageHealthState
            $dismDetail = ("RestartNeeded: {0}" -f $img.RestartNeeded)
            if ($dismState -match 'Healthy') {
                $dismSt = 'ok'
            }
            elseif ($dismState -match 'Repairable') {
                $dismSt = 'attenzione'
                $dismAdv = T 'win.dism_repairable'
            }
            else {
                $dismSt = 'critico'
                $dismAdv = T 'win.dism_bad'
            }
        }
        catch {
            $dismDetail = $_.Exception.Message
            $dismSt = 'attenzione'
            $dismAdv = T 'win.dism_fail'
        }
    }
    Add-Finding -Area 'Windows' -Name (T 'win.dism') -Status $dismSt -Value $dismState -Detail $dismDetail -Advice $dismAdv

    # BSOD / Kernel-Power
    $bugchecks = @()
    $kernelPower = @()
    try {
        $bugchecks = @(Get-WinEvent -FilterHashtable @{
                LogName   = 'System'
                Id        = 1001
                StartTime = (Get-Date).AddDays(-30)
            } -ErrorAction SilentlyContinue -MaxEvents 15 |
            Where-Object { $_.ProviderName -match 'BugCheck|Windows Error Reporting|Wer-SystemErrorReporting' -or $_.Message -match 'bugcheck|Blue Screen' })
    }
    catch { }
    try {
        $kernelPower = @(Get-WinEvent -FilterHashtable @{
                LogName      = 'System'
                ProviderName = 'Microsoft-Windows-Kernel-Power'
                Id           = 41
                StartTime    = (Get-Date).AddDays(-30)
            } -ErrorAction SilentlyContinue -MaxEvents 15)
    }
    catch { }

    if ($bugchecks.Count -gt 0) {
        $last = $bugchecks | Select-Object -First 1
        $msg = $last.Message
        if ($msg.Length -gt 280) { $msg = $msg.Substring(0, 280) + '...' }
        Add-Finding -Area 'Windows' -Name (T 'win.bsod') -Status 'critico' -Value (T 'win.events' $bugchecks.Count) -Detail $msg -Advice (T 'win.bsod_advice')
    }
    else {
        Add-Finding -Area 'Windows' -Name (T 'win.bsod') -Status 'ok' -Value (T 'win.none')
    }

    if ($kernelPower.Count -ge 3) {
        Add-Finding -Area 'Windows' -Name (T 'win.kernel41') -Status 'critico' -Value (T 'win.kernel41_in' $kernelPower.Count) -Detail (T 'win.kernel41_detail') -Advice (T 'win.kernel41_crit')
    }
    elseif ($kernelPower.Count -gt 0) {
        Add-Finding -Area 'Windows' -Name (T 'win.kernel41') -Status 'attenzione' -Value (T 'win.kernel41_in' $kernelPower.Count) -Advice (T 'win.kernel41_warn')
    }
    else {
        Add-Finding -Area 'Windows' -Name (T 'win.kernel41') -Status 'ok' -Value (T 'win.none')
    }

    $crit = @()
    try {
        $crit = @(Get-WinEvent -FilterHashtable @{
                LogName   = 'System'
                Level     = 1, 2
                StartTime = (Get-Date).AddDays(-7)
            } -ErrorAction SilentlyContinue -MaxEvents 40)
    }
    catch { }
    $critCount = $crit.Count
    $st = 'ok'
    $adv = ''
    if ($critCount -ge 25) {
        $st = 'attenzione'
        $adv = T 'win.eventlog_advice'
    }
    $sample = ($crit | Select-Object -First 3 | ForEach-Object { '{0}: {1}' -f $_.TimeCreated.ToString('dd/MM HH:mm'), $_.ProviderName }) -join ' | '
    Add-Finding -Area 'Windows' -Name (T 'win.eventlog') -Status $st -Value (T 'win.events' $critCount) -Detail $sample -Advice $adv

    try {
        $hot = @(Get-HotFix -ErrorAction SilentlyContinue | Sort-Object InstalledOn -Descending | Select-Object -First 5)
        if ($hot.Count -gt 0) {
            $lines = foreach ($h in $hot) {
                $when = ''
                if ($h.InstalledOn) { $when = $h.InstalledOn.ToString('yyyy-MM-dd') }
                '{0} ({1})' -f $h.HotFixID, $when
            }
            Add-Finding -Area 'Windows' -Name (T 'win.hotfixes') -Status 'info' -Value ($lines[0]) -Detail ($lines -join ' | ')
        }
    }
    catch { }

    try {
        $av = Get-CimInstance -Namespace 'root/SecurityCenter2' -ClassName 'AntiVirusProduct' -ErrorAction SilentlyContinue
        foreach ($a in @($av)) {
            Add-Finding -Area 'Windows' -Name (T 'win.av') -Status 'ok' -Value $a.displayName -Detail ("State: {0}" -f $a.productState)
        }
        if (-not $av) {
            Add-Finding -Area 'Windows' -Name (T 'win.av') -Status 'attenzione' -Value (T 'win.av_missing') -Advice (T 'win.av_advice')
        }
    }
    catch { }

    Write-Ok (T 'ok.windows')
}

function Test-PendingReboot {
    $paths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired',
        'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\PendingFileRenameOperations'
    )
    foreach ($p in $paths[0..1]) {
        if (Test-Path -LiteralPath $p) { return $true }
    }
    try {
        $item = Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name 'PendingFileRenameOperations' -ErrorAction SilentlyContinue
        if ($item -and $item.PendingFileRenameOperations) { return $true }
    }
    catch { }
    return $false
}
