function Invoke-CheckDrivers {
    Write-Step (T 'step.drivers')

    $devs = @()
    try {
        $devs = @(Get-PnpDevice -ErrorAction Stop)
    }
    catch {
        Add-Finding -Area 'Driver' -Name (T 'drv.pnp') -Status 'attenzione' -Value (T 'drv.pnp_missing') -Detail $_.Exception.Message
        Write-WarnLine (T 'warn.pnp')
        return
    }

    $present = @($devs | Where-Object { $_.Present -eq $true })
    $problem = @($present | Where-Object {
            ($_.Status -eq 'Error' -or $_.Status -eq 'Degraded') -and
            $_.Problem -notin @('CM_PROB_DISABLED', 'CM_PROB_HARDWARE_DISABLED', 'CM_PROB_PHANTOM', 'CM_PROB_NONE') -and
            $_.FriendlyName -notmatch 'Risorse scheda madre|Motherboard resources|Kernel Debug'
        })

    if ($problem.Count -eq 0) {
        Add-Finding -Area 'Driver' -Name (T 'drv.problems') -Status 'ok' -Value (T 'drv.none') -Detail (T 'drv.present' $present.Count $devs.Count)
    }
    else {
        $st = 'attenzione'
        $adv = T 'drv.advice'
        if ($problem.Count -ge 5) { $st = 'critico' }
        Add-Finding -Area 'Driver' -Name (T 'drv.problems') -Status $st -Value (T 'drv.count' $problem.Count) -Advice $adv
        foreach ($d in ($problem | Select-Object -First 20)) {
            $status = 'attenzione'
            if ($d.Status -eq 'Error') { $status = 'critico' }
            $fname = $d.FriendlyName
            if (-not $fname) { $fname = $d.Class }
            if (-not $fname) { $fname = $d.InstanceId }
            Add-Finding -Area 'Driver' -Name $fname -Status $status -Value $d.Status -Detail (
                T 'drv.device_detail' $d.Class $d.Problem $d.InstanceId
            ) -Advice (T 'drv.device_advice')
        }
    }

    try {
        $net = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' -or $_.Status -eq 'Disconnected' })
        foreach ($n in $net) {
            $st = 'ok'
            $adv = ''
            if ($n.Status -eq 'Disconnected' -and $n.Name -match 'Wi-Fi|WiFi|Wireless') {
                $st = 'info'
            }
            Add-Finding -Area 'Driver' -Name (T 'drv.net' $n.Name) -Status $st -Value $n.Status -Detail (
                T 'drv.net_detail' $n.LinkSpeed $n.MacAddress $n.DriverVersion
            ) -Advice $adv
        }
    }
    catch { }

    Write-Ok (T 'ok.drivers')
}
