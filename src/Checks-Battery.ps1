function Invoke-CheckBattery {
    Write-Step (T 'step.battery')

    $winBat = Invoke-SafeCim -ClassName 'Win32_Battery'
    $static = Invoke-SafeCim -ClassName 'BatteryStaticData' -Namespace 'root/wmi'
    $full = Invoke-SafeCim -ClassName 'BatteryFullChargedCapacity' -Namespace 'root/wmi'
    $cycles = Invoke-SafeCim -ClassName 'BatteryCycleCount' -Namespace 'root/wmi'
    $statusWmi = Invoke-SafeCim -ClassName 'BatteryStatus' -Namespace 'root/wmi'

    if (-not $winBat -and -not $static) {
        Add-Finding -Area 'Batteria' -Name (T 'bat.name') -Status 'info' -Value (T 'bat.not_found') -Detail (T 'bat.not_found_detail')
        Invoke-BatteryReport
        return
    }

    $designed = $null
    $fullCap = $null
    $cycleCount = $null
    $name = T 'bat.name'

    if ($static) {
        $s = $static | Select-Object -First 1
        if ($s.DesignedCapacity) { $designed = [int64]$s.DesignedCapacity }
        if ($s.DeviceName) { $name = [string]$s.DeviceName }
        elseif ($s.UniqueID) { $name = [string]$s.UniqueID }
    }
    if ($full) {
        $f = $full | Select-Object -First 1
        if ($f.FullChargedCapacity) { $fullCap = [int64]$f.FullChargedCapacity }
    }
    if ($cycles) {
        $c = $cycles | Select-Object -First 1
        if ($null -ne $c.CycleCount) { $cycleCount = [int]$c.CycleCount }
    }

    $wb = $winBat | Select-Object -First 1
    if ($wb) {
        if ($wb.Name) { $name = [string]$wb.Name }
        $chem = $wb.Chemistry
        $est = $wb.EstimatedChargeRemaining
        $stText = [string]$wb.BatteryStatus
        Add-Finding -Area 'Batteria' -Name (T 'bat.win_status') -Status 'info' -Value (T 'bat.charge' $est) -Detail (T 'bat.chem' $stText $chem)
    }

    if ($statusWmi) {
        $bs = $statusWmi | Select-Object -First 1
        $parts = @()
        if ($null -ne $bs.RemainingCapacity) { $parts += (T 'bat.remain' $bs.RemainingCapacity) }
        if ($null -ne $bs.ChargeRate -and $bs.ChargeRate -gt 0) { $parts += (T 'bat.charge_rate' $bs.ChargeRate) }
        if ($null -ne $bs.DischargeRate -and $bs.DischargeRate -gt 0) { $parts += (T 'bat.discharge' $bs.DischargeRate) }
        if ($null -ne $bs.Voltage) { $parts += (T 'bat.voltage' $bs.Voltage) }
        if ($parts.Count -gt 0) {
            Add-Finding -Area 'Batteria' -Name (T 'bat.instant') -Status 'info' -Value $name -Detail ($parts -join ' | ')
        }
    }

    if ($designed -and $designed -gt 0 -and $fullCap -and $fullCap -gt 0) {
        $wear = [math]::Round((1 - ($fullCap / [double]$designed)) * 100, 1)
        if ($wear -lt 0) { $wear = 0 }
        $st = 'ok'
        $adv = ''
        if ($wear -ge 50) {
            $st = 'critico'
            $adv = T 'bat.wear_crit'
        }
        elseif ($wear -ge 30) {
            $st = 'attenzione'
            $adv = T 'bat.wear_warn'
        }
        Add-Finding -Area 'Batteria' -Name (T 'bat.wear') -Status $st -Value ("{0}%" -f $wear) -Detail (
            T 'bat.wear_detail' $designed $fullCap
        ) -Advice $adv
    }
    else {
        Add-Finding -Area 'Batteria' -Name (T 'bat.wear') -Status 'info' -Value (T 'bat.wear_hidden') -Detail (T 'bat.wear_hidden_detail')
    }

    if ($null -ne $cycleCount) {
        $st = 'ok'
        $adv = ''
        if ($cycleCount -ge 1000) {
            $st = 'critico'
            $adv = T 'bat.cycles_crit'
        }
        elseif ($cycleCount -ge 800) {
            $st = 'attenzione'
            $adv = T 'bat.cycles_warn'
        }
        Add-Finding -Area 'Batteria' -Name (T 'bat.cycles') -Status $st -Value ([string]$cycleCount) -Advice $adv
    }
    else {
        Add-Finding -Area 'Batteria' -Name (T 'bat.cycles') -Status 'info' -Value (T 'bat.cycles_hidden') -Detail (T 'bat.cycles_hidden_detail')
    }

    Invoke-BatteryReport
    Write-Ok (T 'ok.battery')
}

function Invoke-BatteryReport {
    $out = Join-Path $global:Diag.ReportDir ("battery-report-{0}.html" -f $global:Diag.Stamp)
    try {
        & powercfg.exe /batteryreport /output $out /duration 14 2>$null | Out-Null
        if (Test-Path -LiteralPath $out) {
            Add-Finding -Area 'Batteria' -Name (T 'bat.powercfg') -Status 'info' -Value (T 'bat.powercfg_ok') -Detail $out -Advice (T 'bat.powercfg_advice')
            $global:Diag.BatteryReportPath = $out
        }
    }
    catch {
        Add-Finding -Area 'Batteria' -Name (T 'bat.powercfg') -Status 'info' -Value (T 'bat.powercfg_fail') -Detail $_.Exception.Message
    }
}
