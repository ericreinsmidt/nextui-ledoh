<div align="center">

# LED'oh!

**LED color controller for NextUI**

[![Release](https://img.shields.io/github/v/release/ericreinsmidt/nextui-ledoh?style=for-the-badge&color=ff4444)](https://github.com/ericreinsmidt/nextui-ledoh/releases)
[![Downloads](https://img.shields.io/github/downloads/ericreinsmidt/nextui-ledoh/total?style=for-the-badge&color=ff4444)](https://github.com/ericreinsmidt/nextui-ledoh/releases)
[![License](https://img.shields.io/github/license/ericreinsmidt/nextui-ledoh?style=for-the-badge&color=ff4444)](LICENSE)

A graphical LED color controller for TrimUI Brick and Brick Hammer running NextUI.

</div>

## Features

- **Visual device view** — Front and back representations of your device with LED zones in their physical positions
- **2D HSL color picker** — Full-screen color field with crosshair cursor and live hardware preview
- **Per-zone settings** — Brightness, effect type, and animation speed for each LED zone
- **Real-time feedback** — Physical LEDs update instantly as you pick colors and adjust settings
- **NextUI compatible** — Reads and writes the same settings file as the built-in LED control
- **No network required** — Works completely offline

## LED Zones

### TrimUI Brick / Brick Hammer

| Zone | View | Description |
|------|------|-------------|
| FN1 Key | Front | Left function key LED |
| FN2 Key | Front | Right function key LED |
| Top Bar | Back | LED strip along the top edge |
| L/R Triggers | Back | Left and right trigger LEDs |

## Screenshots

*Coming soon*

## Controls

### Device View

| Button | Action |
|--------|--------|
| D-pad L/R | Select zone (front view) |
| D-pad U/D | Select zone (back view) |
| L1/R1 | Switch front/back view |
| A | Open color picker for selected zone |
| X | Quick save |
| Y | Menu (zone settings, reset, about) |
| B | Quit (prompts to save if unsaved changes) |

### Color Picker

| Button | Action |
|--------|--------|
| D-pad (8-direction) | Move cursor to pick color |
| A | Confirm color |
| B | Cancel (restore original color) |

### Zone Settings (via Y → Menu)

| Button | Action |
|--------|--------|
| D-pad U/D | Move between settings rows |
| D-pad L/R | Adjust value |
| L1/R1 + L/R | Fast adjust |
| A | Confirm |
| B | Cancel (restore original values) |

## Installation

### NextUI Pak Store

LED'oh! is available in the [NextUI Pak Store](https://github.com/NextUI-Paks). Install it directly from the store on your device.

### Manual Install

1. Download the latest release zip from [Releases](https://github.com/ericreinsmidt/nextui-ledoh/releases)
2. Extract to your SD card — the `LED'oh!.pak` folder goes in `Tools/tg5040/`
3. Launch from the Tools menu in NextUI

## Supported Devices

- TrimUI Brick
- TrimUI Brick Hammer

## Building

Requires Docker and the NextUI tg5040 toolchain image.

```bash
make build      # Build via Docker
make package    # Build + create distribution zip
make clean      # Remove build artifacts
```

The binary is cross-compiled using the `ghcr.io/loveretro/tg5040-toolchain` Docker image. No local cross-compiler setup required.

## Known Limitations

- **Quick-wake re-suspend (TrimUI Brick)** — If you press the power button to sleep and then press it again within approximately one second to wake, the device may briefly wake and then immediately re-suspend. This is a known TrimUI Brick firmware behavior that affects all apps using custom power handling. Waiting a few seconds before waking avoids the issue.

## Credits

- Built with [PakKit](https://github.com/ericreinsmidt/pakkit) and [Apostrophe](https://github.com/Helaas/Apostrophe)
- For [NextUI](https://github.com/LoveRetro/NextUI)

## License

MIT — see [LICENSE](LICENSE)
