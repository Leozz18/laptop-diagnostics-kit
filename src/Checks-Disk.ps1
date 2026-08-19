function Invoke-CheckDisk {
    Write-Step (T 'step.disk')

    $disks = @()
    try {
        $disks = @(Get-PhysicalDisk -ErrorAction Stop)
    }
    catch {
        $disks = Invoke-SafeCim -ClassName 'MSFT_PhysicalDisk' -Namespace 'root/microsoft/windows/storage'
    }

    if ($disks.Count -eq 0) {
        Add-Finding -Area 'Disco' -Name (T 'disk.physical') -Status 'attenzione' -Value (T 'disk.none') -Advice (T 'disk.none_advice')
    }

    foreach ($d in $disks) {
        $name = $d.FriendlyName
        if (-not $name) { $name = $d.DeviceId }
        $media = $d.MediaType
        $health = [string]$d.HealthStatus
        $op = [string]$d.OperationalStatus
        $size = Get-BytesText ([int64]$d.Size)

        $st = 'ok'
        $adv = ''
        if ($health -match 'Unhealthy|Failed') {
            $st = 'critico'
            $adv = T 'disk.unhealthy'
        }
        elseif ($health -match 'Warning') {
            $st = 'attenzione'
            $adv = T 'disk.warning'
        }

        $detail = T 'disk.detail' $media $op $size
        try {
            $rel = Get-StorageReliabilityCounter -PhysicalDisk $d -ErrorAction Stop
            if ($rel) {
                $parts = @()
                if ($null -ne $rel.Temperature) { $parts += (T 'disk.temp' $rel.Temperature) }
                if ($null -ne $rel.Wear) { $parts += (T 'disk.wear' $rel.Wear) }
                if ($null -ne $rel.ReadErrorsUncorrected -and $rel.ReadErrorsUncorrected -gt 0) {
                    $parts += (T 'disk.read_err' $rel.ReadErrorsUncorrected)
                    if ($st -eq 'ok') { $st = 'attenzione' }
                    $adv = T 'disk.read_advice'
                }
                if ($null -ne $rel.WriteErrorsUncorrected -and $rel.WriteErrorsUncorrected -gt 0) {
                    $parts += (T 'disk.write_err' $rel.WriteErrorsUncorrected)
                    if ($st -eq 'ok') { $st = 'attenzione' }
                }
                if ($null -ne $rel.PowerOnHours) { $parts += (T 'disk.hours' $rel.PowerOnHours) }
                if ($parts.Count -gt 0) { $detail = $detail + ' | ' + ($parts -join ' | ') }
                if ($rel.Wear -ge 90) {
                    $st = 'critico'
                    $adv = T 'disk.wear_crit'
                }
                elseif ($rel.Wear -ge 70 -and $st -ne 'critico') {
                    $st = 'attenzione'
                    $adv = T 'disk.wear_warn'
                }
            }
        }
        catch { }

        Add-Finding -Area 'Disco' -Name (T 'disk.name' $name) -Status $st -Value $health -Detail $detail -Advice $adv
    }

    $vols = @()
    try {
        $vols = @(Get-Volume -ErrorAction Stop | Where-Object { $_.DriveLetter -and $_.Size -gt 0 })
    }
    catch {
        $vols = Invoke-SafeCim -ClassName 'Win32_LogicalDisk' -Filter "DriveType=3"
    }

    foreach ($v in $vols) {
        $letter = $v.DriveLetter
        $label = $v.FileSystemLabel
        $size = [int64]$v.Size
        $free = [int64]$v.SizeRemaining
        if (-not $letter -and $v.DeviceID) {
            $letter = $v.DeviceID
            $size = [int64]$v.Size
            $free = [int64]$v.FreeSpace
            $label = $v.VolumeName
        }
        if ($size -le 0) { continue }
        $pct = [math]::Round(($free / $size) * 100, 1)
        $usedPct = 100 - $pct
        $st = 'ok'
        $adv = ''
        if ($pct -lt 10) {
            $st = 'critico'
            $adv = T 'disk.space_crit'
        }
        elseif ($pct -lt 15) {
            $st = 'attenzione'
            $adv = T 'disk.space_warn'
        }
        $name = if ($letter.ToString().Length -eq 1) { '{0}:' -f $letter } else { [string]$letter }
        Add-Finding -Area 'Disco' -Name (T 'disk.volume' $name) -Status $st -Value (T 'disk.free_pct' $pct) -Detail (
            T 'disk.volume_detail' $label (Get-BytesText $size) (Get-BytesText $free) $usedPct
        ) -Advice $adv
    }

    Invoke-SmartctlScan
    Write-Ok (T 'ok.disk')
}

function Invoke-SmartctlScan {
    $smart = Get-SmartctlPath
    if (-not $smart) {
        Add-Finding -Area 'Disco' -Name (T 'disk.smart') -Status 'info' -Value (T 'disk.smart_na') -Detail (T 'disk.smart_na_detail')
        return
    }

    $scanOut = ''
    try {
        $scanOut = & $smart --scan 2>&1 | Out-String
    }
    catch {
        Add-Finding -Area 'Disco' -Name (T 'disk.smart') -Status 'attenzione' -Value (T 'disk.smart_start_err') -Detail $_.Exception.Message
        return
    }

    $devices = @()
    foreach ($line in ($scanOut -split "`r?`n")) {
        if ($line -match '^(/dev/\S+|pd\d+|\\\\\.\\PhysicalDrive\d+)\s') {
            $devices += $Matches[1]
        }
        elseif ($line -match '^(PD\d+)\s') {
            $devices += $Matches[1]
        }
    }
    if ($devices.Count -eq 0) {
        # Fallback Windows physical drives
        try {
            $pd = @(Get-CimInstance Win32_DiskDrive -ErrorAction SilentlyContinue)
            for ($i = 0; $i -lt $pd.Count; $i++) {
                $devices += ('/dev/pd{0}' -f $i)
            }
        }
        catch { }
        if ($devices.Count -eq 0) { $devices = @('/dev/sda', 'PD0') }
    }

    $seen = @{}
    foreach ($dev in $devices) {
        if ($seen.ContainsKey($dev)) { continue }
        $seen[$dev] = $true
        $raw = ''
        try {
            $raw = & $smart -H -A -n standby $dev 2>&1 | Out-String
        }
        catch {
            continue
        }
        if ($raw -match 'Permission denied|failed:|Unable to detect') {
            # retry without standby, NVMe path
            try { $raw = & $smart -H -A $dev 2>&1 | Out-String } catch { continue }
        }

        $model = $dev
        if ($raw -match 'Device Model:\s+(.+)') { $model = $Matches[1].Trim() }
        elseif ($raw -match 'Model Number:\s+(.+)') { $model = $Matches[1].Trim() }
        elseif ($raw -match 'Device:\s+(.+)') { $model = $Matches[1].Trim() }

        $healthLine = ''
        $st = 'ok'
        $adv = ''
        if ($raw -match 'SMART overall-health self-assessment test result:\s+(\w+)') {
            $healthLine = $Matches[1].Trim()
            if ($healthLine -notmatch 'PASSED|OK') {
                $st = 'critico'
                $adv = T 'disk.smart_failed'
            }
        }
        elseif ($raw -match 'SMART Health Status:\s+(.+)') {
            $healthLine = $Matches[1].Trim()
            if ($healthLine -notmatch 'OK|PASSED') {
                $st = 'critico'
                $adv = T 'disk.smart_not_ok'
            }
        }
        elseif ($raw -match 'PASSED') {
            $healthLine = 'PASSED'
        }
        else {
            $healthLine = T 'disk.smart_unread'
            $st = 'info'
        }

        $extra = @()
        if ($raw -match 'Reallocated_Sector_Ct\s+\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+(\d+)') {
            $n = [int]$Matches[1]
            $extra += (T 'disk.realloc' $n)
            if ($n -gt 100) { $st = 'critico'; $adv = T 'disk.realloc_crit' }
            elseif ($n -gt 0 -and $st -ne 'critico') { $st = 'attenzione'; $adv = T 'disk.realloc_warn' }
        }
        if ($raw -match 'Current_Pending_Sector\s+\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+\S+\s+(\d+)') {
            $n = [int]$Matches[1]
            if ($n -gt 0) {
                $extra += (T 'disk.pending' $n)
                if ($st -ne 'critico') { $st = 'attenzione' }
                $adv = T 'disk.pending_advice'
            }
        }
        if ($raw -match 'Percentage Used\s*:\s*(\d+)') {
            $n = [int]$Matches[1]
            $extra += (T 'disk.nvme_wear' $n)
            if ($n -ge 90) { $st = 'critico'; $adv = T 'disk.nvme_crit' }
            elseif ($n -ge 70 -and $st -ne 'critico') { $st = 'attenzione'; $adv = T 'disk.nvme_warn' }
        }
        if ($raw -match 'Available Spare\s*:\s*(\d+)') {
            $n = [int]$Matches[1]
            $extra += (T 'disk.nvme_spare' $n)
            if ($n -lt 10) { $st = 'critico'; $adv = T 'disk.spare_crit' }
            elseif ($n -lt 50 -and $st -ne 'critico') { $st = 'attenzione' }
        }
        if ($raw -match 'Temperature:\s+(\d+)') {
            $extra += (T 'disk.smart_temp' $Matches[1])
        }
        if ($raw -match 'Power_On_Hours.*?(\d+)\s*$') { }

        $detail = ($extra -join ' | ')
        if (-not $detail) {
            $snippet = ($raw -split "`r?`n" | Select-Object -First 8) -join ' '
            if ($snippet.Length -gt 240) { $snippet = $snippet.Substring(0, 240) + '...' }
            $detail = $snippet
        }
        Add-Finding -Area 'Disco' -Name (T 'disk.smart_name' $model) -Status $st -Value $healthLine -Detail $detail -Advice $adv
    }
}
