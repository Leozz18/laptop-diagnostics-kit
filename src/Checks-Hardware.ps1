function Invoke-CheckHardware {
    Write-Step (T 'step.hardware')

    $cs = Invoke-SafeCim -ClassName 'Win32_ComputerSystem' | Select-Object -First 1
    $bios = Invoke-SafeCim -ClassName 'Win32_BIOS' | Select-Object -First 1
    $board = Invoke-SafeCim -ClassName 'Win32_BaseBoard' | Select-Object -First 1
    $os = Invoke-SafeCim -ClassName 'Win32_OperatingSystem' | Select-Object -First 1
    $cpus = Invoke-SafeCim -ClassName 'Win32_Processor'
    $rams = Invoke-SafeCim -ClassName 'Win32_PhysicalMemory'
    $gpus = Invoke-SafeCim -ClassName 'Win32_VideoController'

    $model = ''
    if ($cs) { $model = ('{0} {1}' -f $cs.Manufacturer, $cs.Model).Trim() }
    $serial = T 'nd'
    if ($bios -and $bios.SerialNumber) { $serial = $bios.SerialNumber }
    Add-Finding -Area 'Hardware' -Name (T 'hw.computer') -Status 'info' -Value $model -Detail (T 'hw.bios_serial' $serial)

    if ($board) {
        Add-Finding -Area 'Hardware' -Name (T 'hw.motherboard') -Status 'info' -Value ("{0} {1}" -f $board.Manufacturer, $board.Product)
    }

    $osName = ''
    $uptime = ''
    if ($os) {
        $osName = ('{0} (build {1})' -f $os.Caption.Trim(), $os.BuildNumber)
        try {
            $boot = [Management.ManagementDateTimeConverter]::ToDateTime($os.LastBootUpTime)
        }
        catch {
            $boot = $os.LastBootUpTime
        }
        if ($boot) {
            $span = (Get-Date) - [datetime]$boot
            $uptime = T 'hw.uptime_fmt' ([int]$span.TotalDays) $span.Hours $span.Minutes
        }
    }
    Add-Finding -Area 'Hardware' -Name (T 'hw.os') -Status 'info' -Value $osName -Detail (T 'hw.uptime' $uptime)

    foreach ($cpu in $cpus) {
        $load = $cpu.LoadPercentage
        $status = 'ok'
        $advice = ''
        if ($load -ge 95) {
            $status = 'attenzione'
            $advice = T 'hw.cpu_hot'
        }
        Add-Finding -Area 'Hardware' -Name (T 'hw.cpu') -Status $status -Value $cpu.Name.Trim() -Detail (
            T 'hw.cpu_detail' $cpu.NumberOfLogicalProcessors $cpu.MaxClockSpeed $load
        ) -Advice $advice
    }

    $ramTotal = 0L
    $slotIndex = 0
    foreach ($m in $rams) {
        $slotIndex++
        $cap = [int64]$m.Capacity
        $ramTotal += $cap
        $speed = $m.Speed
        $part = $m.PartNumber
        if ($part) { $part = $part.ToString().Trim() }
        Add-Finding -Area 'Hardware' -Name (T 'hw.ram_module' $slotIndex) -Status 'info' -Value (Get-BytesText $cap) -Detail (
            T 'hw.ram_detail' $speed $m.BankLabel $part
        )
    }
    $ramTotalBytes = 0L
    if ($cs) { $ramTotalBytes = [int64]$cs.TotalPhysicalMemory }
    if ($ramTotalBytes -le 0) { $ramTotalBytes = $ramTotal }

    $freeRam = 0L
    $usedPct = 0
    if ($os) {
        $freeRam = [int64]$os.FreePhysicalMemory * 1KB
        if ($ramTotalBytes -gt 0) {
            $usedPct = [math]::Round((($ramTotalBytes - $freeRam) / $ramTotalBytes) * 100, 1)
        }
    }
    $ramStatus = 'ok'
    $ramAdvice = ''
    if ($usedPct -ge 92) {
        $ramStatus = 'critico'
        $ramAdvice = T 'hw.ram_crit'
    }
    elseif ($usedPct -ge 85) {
        $ramStatus = 'attenzione'
        $ramAdvice = T 'hw.ram_warn'
    }
    Add-Finding -Area 'Hardware' -Name (T 'hw.ram_total') -Status $ramStatus -Value (Get-BytesText $ramTotalBytes) -Detail (
        T 'hw.ram_used' $usedPct (Get-BytesText $freeRam)
    ) -Advice $ramAdvice

    foreach ($gpu in $gpus) {
        if (-not $gpu.Name) { continue }
        $vram = ''
        if ($gpu.AdapterRAM -and $gpu.AdapterRAM -gt 0) {
            $vram = Get-BytesText ([int64]$gpu.AdapterRAM)
        }
        Add-Finding -Area 'Hardware' -Name (T 'hw.gpu') -Status 'info' -Value $gpu.Name -Detail (
            T 'hw.gpu_detail' $vram $gpu.DriverVersion $gpu.DriverDate
        )
    }

    try {
        $top = Get-Process -ErrorAction SilentlyContinue |
            Sort-Object -Property WorkingSet64 -Descending |
            Select-Object -First 6
        $lines = foreach ($p in $top) {
            '{0} ({1})' -f $p.ProcessName, (Get-BytesText $p.WorkingSet64)
        }
        Add-Finding -Area 'Hardware' -Name (T 'hw.processes') -Status 'info' -Value ($lines -join ' | ')
    }
    catch { }

    try {
        $schemeOut = & powercfg.exe /getactivescheme 2>$null
        $scheme = ($schemeOut | Out-String).Trim()
        $schemeName = $scheme
        if ($scheme -match '\(([^)]+)\)\s*$') { $schemeName = $Matches[1].Trim() }
        $status = 'ok'
        $advice = ''
        if ($schemeName -match '^(Risparmio energia|Power saver|Power Saver)$') {
            $status = 'attenzione'
            $advice = T 'hw.power_saver'
        }
        Add-Finding -Area 'Hardware' -Name (T 'hw.power_plan') -Status $status -Value $schemeName -Detail $scheme -Advice $advice
    }
    catch { }

    $memEvents = @()
    try {
        $memEvents = @(Get-WinEvent -FilterHashtable @{
                LogName      = 'System'
                ProviderName = 'Microsoft-Windows-MemoryDiagnostics-Results'
                StartTime    = (Get-Date).AddDays(-90)
            } -ErrorAction SilentlyContinue -MaxEvents 5)
    }
    catch { }
    if ($memEvents.Count -gt 0) {
        $last = $memEvents | Select-Object -First 1
        $msg = $last.Message
        $st = 'ok'
        $adv = ''
        if ($msg -match 'hardware error|error|fail|non riuscit|errori|fehler|erreur') {
            $st = 'critico'
            $adv = T 'hw.memdiag_fail'
        }
        Add-Finding -Area 'Hardware' -Name (T 'hw.memdiag') -Status $st -Value $last.TimeCreated.ToString('yyyy-MM-dd') -Detail $msg -Advice $adv
    }
    else {
        Add-Finding -Area 'Hardware' -Name (T 'hw.memdiag') -Status 'info' -Value (T 'hw.memdiag_none') -Detail (T 'hw.memdiag_none_detail') -Advice (T 'hw.memdiag_advice')
    }

    $whea = @()
    try {
        $whea = @(Get-WinEvent -FilterHashtable @{
                LogName      = 'System'
                ProviderName = 'Microsoft-Windows-WHEA-Logger'
                StartTime    = (Get-Date).AddDays(-30)
            } -ErrorAction SilentlyContinue -MaxEvents 20)
    }
    catch { }
    if ($whea.Count -ge 5) {
        Add-Finding -Area 'Hardware' -Name (T 'hw.whea') -Status 'critico' -Value (T 'hw.whea_events' $whea.Count) -Detail (T 'hw.whea_detail') -Advice (T 'hw.whea_crit')
    }
    elseif ($whea.Count -gt 0) {
        Add-Finding -Area 'Hardware' -Name (T 'hw.whea') -Status 'attenzione' -Value (T 'hw.whea_events' $whea.Count) -Advice (T 'hw.whea_warn')
    }
    else {
        Add-Finding -Area 'Hardware' -Name (T 'hw.whea') -Status 'ok' -Value (T 'hw.whea_none')
    }

    Write-Ok (T 'ok.hardware')
}
