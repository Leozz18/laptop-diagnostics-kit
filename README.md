# Laptop diagnostics kit

Portable Windows 11 health checker: CPU, RAM, disk SMART, battery, temperatures, Windows, drivers. No system-wide installer. Languages: **Italian, English, Spanish, French, German** (auto-detected).

Original design: [SCHEMA.md](SCHEMA.md)

![Laptop diagnostics kit in action](docs/kit-in-action.gif)

## Quick start

1. Double-click **`Avvia-Diagnostica.bat`** or **`Run-Diagnostics.bat`**
2. Accept the administrator prompt (needed for SMART, battery, DISM)
3. First run downloads LibreHardwareMonitor + smartctl into `tools\`
4. An HTML report opens; copies stay in `reports\`

Force a language:

```bat
Avvia-Diagnostica.bat en
Avvia-Diagnostica.bat it
```

Or set `LAPTOP_DIAG_LANG=en`.

## Italiano

Kit locale per controllare la sanita del laptop. Tutto resta in questa cartella.

- Doppio clic su `Avvia-Diagnostica.bat`, accetta UAC
- Lingua: quella di Windows, oppure `Avvia-Diagnostica.bat en`
- Schema iniziale: [SCHEMA.md](SCHEMA.md)

`sfc /scannow` non parte da solo. Il report lo consiglia solo se serve.

## What is checked

| Area | Details |
|------|---------|
| Hardware | CPU, RAM, GPU, motherboard, WHEA, Memory Diagnostic, power plan |
| Disk | Windows health, free space, SMART via smartctl |
| Battery | Wear, cycles, powercfg history |
| Temperatures | CPU/GPU/SSD/fans via LibreHardwareMonitor |
| Windows | DISM CheckHealth, pending reboot, BSOD, Kernel-Power 41 |
| Drivers | Present PnP devices in Error (ignores disabled ghosts) |

## Layout

```
Avvia-Diagnostica.bat / Run-Diagnostics.bat
Scarica-Tool.ps1
SCHEMA.md
src/          scripts + i18n
reports/      generated HTML/JSON (gitignored)
tools/        downloaded binaries (gitignored)
```

## License

MIT for this kit. Downloaded tools keep their own licenses (LibreHardwareMonitor MPL, smartmontools GPL).
