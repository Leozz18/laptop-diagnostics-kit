function Invoke-CheckThermal {
    Write-Step (T 'step.thermal')

    $exe = Get-ReadSensorsExe
    $sensors = @()
    if ($exe) {
        $jsonPath = Join-Path $global:Diag.ReportDir ("sensors-{0}.json" -f $global:Diag.Stamp)
        $lhmDir = Split-Path -Parent $exe
        try {
            $p = Start-Process -FilePath $exe -ArgumentList "`"$jsonPath`"" -WorkingDirectory $lhmDir -Wait -PassThru -WindowStyle Hidden
            if ((Test-Path -LiteralPath $jsonPath) -and $p.ExitCode -eq 0) {
                $raw = Get-Content -LiteralPath $jsonPath -Raw -Encoding UTF8
                if ($raw -and $raw.Trim().StartsWith('[')) {
                    $wrapped = '{"items":' + $raw.Trim() + '}'
                    $parsed = ConvertFrom-Json -InputObject $wrapped
                    $sensors = @($parsed.items)
                }
                elseif ($raw -match '"error"') {
                    Add-Finding -Area 'Temperature' -Name 'LibreHardwareMonitor' -Status 'attenzione' -Value (T 'th.lhm_read_err') -Detail $raw
                }
            }
            else {
                Add-Finding -Area 'Temperature' -Name 'LibreHardwareMonitor' -Status 'info' -Value (T 'th.lhm_exit' $p.ExitCode) -Detail (T 'th.lhm_exit_detail')
            }
        }
        catch {
            Add-Finding -Area 'Temperature' -Name 'LibreHardwareMonitor' -Status 'attenzione' -Value (T 'th.lhm_read_err') -Detail $_.Exception.Message
        }
    }
    else {
        Add-Finding -Area 'Temperature' -Name 'LibreHardwareMonitor' -Status 'info' -Value (T 'th.lhm_missing') -Detail (T 'th.lhm_missing_detail')
    }

    $global:Diag.Sensors = $sensors

    $temps = @()
    $fans = @()
    foreach ($s in @($sensors)) {
        $reading = Get-SensorReading $s
        if ($null -eq $reading) { continue }
        if ($s.sensorType -eq 'Temperature' -and $reading -ge 5 -and $reading -le 125) {
            $temps += $s
        }
        elseif ($s.sensorType -eq 'Fan') {
            $fans += $s
        }
    }
    $cpuTemps = @($temps | Where-Object { $_.hardwareType -eq 'Cpu' })
    $gpuTemps = @($temps | Where-Object { $_.hardwareType -match '^Gpu' })
    $ssdTemps = @($temps | Where-Object { $_.hardwareType -eq 'Storage' })

    if ($cpuTemps.Count -gt 0) {
        $maxCpu = Get-SensorMaximum $cpuTemps
        $pkg = @($cpuTemps | Where-Object { $_.sensor -match 'Package|Tctl|CCD|Average' }) | Select-Object -First 1
        $label = if ($pkg) { '{0}: {1:N0} C' -f $pkg.sensor, (Get-SensorReading $pkg) } else { '{0:N0} C' -f $maxCpu }
        $st = 'ok'
        $adv = ''
        if ($maxCpu -ge 95) {
            $st = 'critico'
            $adv = T 'th.cpu_crit'
        }
        elseif ($maxCpu -ge 85) {
            $st = 'attenzione'
            $adv = T 'th.cpu_warn'
        }
        Add-Finding -Area 'Temperature' -Name (T 'th.cpu_max') -Status $st -Value $label -Detail (
            T 'th.cpu_detail' $cpuTemps.Count $maxCpu
        ) -Advice $adv
    }
    elseif ($sensors.Count -gt 0) {
        Add-Finding -Area 'Temperature' -Name (T 'hw.cpu') -Status 'info' -Value (T 'th.cpu_hidden') -Detail (T 'th.cpu_hidden_detail') -Advice (T 'th.cpu_hidden_advice')
    }

    if ($gpuTemps.Count -gt 0) {
        $maxGpu = Get-SensorMaximum $gpuTemps
        $st = 'ok'
        $adv = ''
        if ($maxGpu -ge 90) {
            $st = 'critico'
            $adv = T 'th.gpu_crit'
        }
        elseif ($maxGpu -ge 80) {
            $st = 'attenzione'
            $adv = T 'th.gpu_warn'
        }
        Add-Finding -Area 'Temperature' -Name (T 'th.gpu_max') -Status $st -Value (('{0:0} C' -f $maxGpu)) -Advice $adv
    }

    if ($ssdTemps.Count -gt 0) {
        $maxSsd = Get-SensorMaximum $ssdTemps
        $st = 'ok'
        $adv = ''
        if ($maxSsd -ge 80) {
            $st = 'critico'
            $adv = T 'th.ssd_crit'
        }
        elseif ($maxSsd -ge 70) {
            $st = 'attenzione'
            $adv = T 'th.ssd_warn'
        }
        Add-Finding -Area 'Temperature' -Name (T 'th.ssd_max') -Status $st -Value (('{0:0} C' -f $maxSsd)) -Advice $adv
    }

    $boardTemps = @($temps | Where-Object { $_.hardwareType -eq 'Motherboard' }) | Select-Object -First 6
    foreach ($t in $boardTemps) {
        Add-Finding -Area 'Temperature' -Name (T 'th.board' $t.sensor) -Status 'info' -Value ('{0:N1} C' -f (Get-SensorReading $t))
    }

    if ($fans.Count -gt 0) {
        foreach ($f in $fans) {
            $rpm = [int](Get-SensorReading $f)
            $st = 'ok'
            $adv = ''
            if ($rpm -eq 0) {
                $st = 'attenzione'
                $adv = T 'th.fan_zero'
            }
            Add-Finding -Area 'Temperature' -Name (T 'th.fan' $f.sensor) -Status $st -Value ("{0} RPM" -f $rpm) -Detail $f.hardware -Advice $adv
        }
    }

    $deg = @(Get-SensorByType -Sensors $sensors -Type 'Level' | Where-Object { $_.sensor -match 'Degradation' } | Select-Object -First 1)
    if ($deg.Count -gt 0) {
        $wear = [double](Get-SensorReading $deg[0])
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
        Add-Finding -Area 'Batteria' -Name (T 'bat.lhm_wear') -Status $st -Value ('{0:N1}%' -f $wear) -Advice $adv
    }

    if ($temps.Count -eq 0) {
        $acpi = Invoke-SafeCim -ClassName 'MSAcpi_ThermalZoneTemperature' -Namespace 'root/wmi'
        $got = $false
        foreach ($z in $acpi) {
            if ($null -eq $z.CurrentTemperature) { continue }
            $celsius = ($z.CurrentTemperature / 10.0) - 273.15
            if ($celsius -lt 0 -or $celsius -gt 150) { continue }
            $got = $true
            $st = 'ok'
            $adv = ''
            if ($celsius -ge 95) { $st = 'critico'; $adv = T 'th.acpi_hot' }
            elseif ($celsius -ge 85) { $st = 'attenzione' }
            Add-Finding -Area 'Temperature' -Name (T 'th.acpi') -Status $st -Value ('{0:N0} C' -f $celsius) -Advice $adv
        }
        if (-not $got -and $gpuTemps.Count -eq 0) {
            Add-Finding -Area 'Temperature' -Name (T 'th.none') -Status 'info' -Value (T 'th.none_value') -Detail (T 'th.none_detail') -Advice (T 'th.none_advice')
        }
    }

    Write-Ok (T 'ok.thermal')
}

function Get-SensorByType {
    param($Sensors, [string]$Type)
    foreach ($s in @($Sensors)) {
        if ($s.sensorType -eq $Type) { $s }
    }
}

function Get-SensorReading {
    param($Sensor)
    if ($null -eq $Sensor) { return $null }
    $p = $Sensor.PSObject.Properties['reading']
    if ($p) { return [double]$p.Value }
    return $null
}

function Get-SensorMaximum {
    param($List)
    $max = $null
    foreach ($s in @($List)) {
        $v = Get-SensorReading $s
        if ($null -eq $v) { continue }
        if ($null -eq $max -or $v -gt $max) { $max = $v }
    }
    if ($null -eq $max) { return 0 }
    return $max
}
