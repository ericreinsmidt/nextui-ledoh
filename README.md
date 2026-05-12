<div align="center">

# LED'oh!

![LED'oh!](assets/logo.png)

[![Release](https://img.shields.io/github/v/release/ericreinsmidt/nextui-ledoh?style=for-the-badge&color=dd3333)](https://github.com/ericreinsmidt/nextui-ledoh/releases)
[![Downloads](https://img.shields.io/github/downloads/ericreinsmidt/nextui-ledoh/total?style=for-the-badge&color=22aa44)](https://github.com/ericreinsmidt/nextui-ledoh/releases)
[![License](https://img.shields.io/github/license/ericreinsmidt/nextui-ledoh?style=for-the-badge&color=3366cc)](LICENSE)

A graphical LED color controller for TrimUI Brick, Brick Hammer, and Smart Pro running NextUI.

</div>

## Features

- **Visual device view** — Front and back representations of your device with LED zones in their physical positions
- **2D HSL color picker** — Full-screen color field with crosshair cursor and live hardware preview
- **Per-zone settings** — Brightness, effect type, and animation speed for each LED zone
- **Real-time feedback** — Physical LEDs update instantly as you pick colors and adjust settings
- **LEDs Off/On toggle** — Turn all LEDs off with a single button press; toggle back on to resume your previous state (static colors or running animation)
- **Per-LED animations** — 11 animated LED patterns using per-LED frame control (Brick only)
- **Persistent animations** — Animations survive app exit and device reboots
- **Multi-device support** — Automatically detects Brick, Brick Hammer, or Smart Pro and adapts the UI
- **Random front images** — Device view randomly picks from available front image variants on each view flip (app start for Smart Pro)
- **NextUI compatible** — Reads and writes the same settings file as the built-in LED control

## LED Zones

### TrimUI Brick / Brick Hammer

| Zone | View | Description |
|------|------|-------------|
| FN1 Key | Front | Left function key LED |
| FN2 Key | Front | Right function key LED |
| Top Bar | Back | LED strip along the top edge |
| L/R Triggers | Back | Left and right trigger LEDs |

> **Note:** FN1 and FN2 share a brightness path — changing one changes the other.

### TrimUI Smart Pro

| Zone | View | Description |
|------|------|-------------|
| Joystick L | Front | Left joystick ring LED |
| Logo | Front | Triangle logo indicator LED |
| Joystick R | Front | Right joystick ring LED |

> **Note:** All Smart Pro zones share a single brightness path — changing brightness on any zone changes all of them.

## Screenshots

| | | |
|:---:|:---:|:---:|
| ![Brick Front](assets/screenshots/brick_front.png) | ![Brick Back](assets/screenshots/brick_back.png) | ![Smart Pro](assets/screenshots/smartpro.png) |
| Brick — Front | Brick — Back | Smart Pro |
| ![Color Picker](assets/screenshots/color_picker.png) | ![Zone Settings](assets/screenshots/zone_settings.png) | ![Menu](assets/screenshots/menu.png) |
| Color Picker | Zone Settings | Menu |

## Controls

### Device View

| Button | Action |
|--------|--------|
| D-pad L/R | Select zone (front view) |
| D-pad U/D | Select zone (back view, Brick only) |
| L1/R1 | Switch front/back view (Brick only) |
| A | Open color picker for selected zone |
| Y | Menu (zone settings, animations, about) |
| Menu | Toggle LEDs off/on |
| B | Save and quit |

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

## Animations (Brick Only)

Per-LED animation patterns that drive the Brick's 14 individually addressable LEDs via the `frame_hex` framebuffer. Animations run as background daemons that persist after the app exits and automatically restart on reboot.

Select animations from **Y → Menu → Animations**. While an animation is running, editing zone colors will pause the animation and resume it when you're done.

Animations are discovered dynamically from the `scripts/` folder inside the pak directory. You can add your own — see [Creating Custom Animations](#creating-custom-animations) below.

### Included Animations

| Animation | Description |
|-----------|-------------|
| Aurora | Slow-drifting greens, teals, and purples |
| Binary | Binary counter in LEDs |
| Campfire | Flickering warm firelight |
| Comet | Bright head with fading tail |
| EKG | Heartbeat pulse sweep |
| K.I.T.T. | Classic Knight Rider red sweep |
| Kessel Run | Stars streak outward from center to lightspeed |
| Morse | Blinks "NEXTUI" in Morse code |
| Ocean | Rolling blue-green waves |
| Police | Red and blue alternating flash |
| Pride | Rainbow flag color chase |

### Creating Custom Animations

Drop any `.sh` file into the `scripts/` folder inside the LED'oh! pak directory and it will automatically appear in the Animations menu. No recompilation needed.

**Location:** `Tools/tg5040/LED'oh!.pak/scripts/`

**Requirements:**

1. The script must be a POSIX shell script (starts with `#!/bin/sh`)
2. Add a `# NAME: Your Animation Name` line in the first 5 lines to set the display name (otherwise the filename is used)
3. The script must write all **14 LED positions** in every frame to avoid stale colors bleeding through
4. Use PID file management so the app can detect and stop your animation

**LED positions in frame_hex (space-separated hex colors):**

```
Position:  1    2    3    4    5    6    7    8    9    10   11   12   13   14
Zone:      |---------- Top Bar (8) ----------|  F2   F1   |-- L Trig --|-- R Trig --|
```

All 14 positions must be written in every frame, even if unused (set unused positions to `000000`).

**Template:**

```sh
#!/bin/sh
# NAME: My Animation
# Description of what it does
#
# Daemon-ready: writes PID to /tmp/led_anim.pid for external management

F="/sys/class/led_anim/frame_hex"
E="/sys/class/led_anim/effect_enable"
PIDFILE="/tmp/led_anim.pid"
SPEED=0.10  # seconds between frames

# --- PID management (required) ---
if [ -f "$PIDFILE" ]; then
    OLD_PID=$(cat "$PIDFILE")
    if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
        kill "$OLD_PID" 2>/dev/null
        sleep 0.5
    fi
    rm -f "$PIDFILE"
fi
echo $$ > "$PIDFILE"

# --- Setup (required) ---
# Set brightness for each zone (0-100)
echo 80 > /sys/class/led_anim/max_scale          # Top bar
echo 50 > /sys/class/led_anim/max_scale_f1f2     # FN1/FN2 buttons
echo 50 > /sys/class/led_anim/max_scale_lr       # L/R triggers
# Clear the effect system so frame_hex has full control
echo "000000 " > /sys/class/led_anim/effect_rgb_hex_m
echo "000000 " > /sys/class/led_anim/effect_rgb_hex_f1
echo "000000 " > /sys/class/led_anim/effect_rgb_hex_f2
echo "000000 " > /sys/class/led_anim/effect_rgb_hex_lr
echo 0 > /sys/class/led_anim/effect_m
echo 0 > /sys/class/led_anim/effect_f1
echo 0 > /sys/class/led_anim/effect_f2
echo 0 > /sys/class/led_anim/effect_lr
echo 0 > "$E"
sleep 0.3

# --- Cleanup on exit (required) ---
cleanup() {
    rm -f "$PIDFILE"
    echo 1 > "$E"
    echo 4 > /sys/class/led_anim/effect_m
    echo -1 > /sys/class/led_anim/effect_cycles_m
    echo 50 > /sys/class/led_anim/max_scale
    echo 50 > /sys/class/led_anim/max_scale_f1f2
    echo 50 > /sys/class/led_anim/max_scale_lr
    exit 0
}
trap cleanup INT TERM HUP

# --- Write one frame (required) ---
write_frame() {
    echo "$1 " > "$F"
    sleep $SPEED
    echo 1 > "$E"
    echo 0 > "$E"
}

# --- Your animation loop ---
while true; do
    # Build your frame as 14 space-separated 6-digit hex colors (RRGGBB)
    # Top bar (8) + F2 + F1 + TL + TL2 + TR2 + TR
    write_frame "FF0000 00FF00 0000FF FF0000 00FF00 0000FF FF0000 00FF00 000000 000000 000000 000000 000000 000000"
done
```

**Tips:**
- Colors are 6-digit hex (RRGGBB): `FF0000` = red, `00FF00` = green, `000000` = off
- `SPEED` controls frame timing — lower is faster (0.08 = fast, 0.20 = slow)
- Use shell arithmetic for patterns: `$(( step % 8 ))` for cycling
- The `write_frame` function handles the effect_enable toggle that flushes frame data to hardware
- Set `max_scale` to 0 for zones you want completely off (overrides any color)

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
- TrimUI Smart Pro

## Building

Requires Docker and the NextUI tg5040 toolchain image.

```bash
make build      # Build via Docker
make package    # Build + create distribution zip
make clean      # Remove build artifacts
```

The binary is cross-compiled using the `ghcr.io/loveretro/tg5040-toolchain` Docker image. No local cross-compiler setup required.

## Hardware Research

See [trimui_brick_led_research.md](trimui_brick_led_research.md) for per-LED framebuffer findings on the TrimUI Brick (14 individually addressable LEDs via `frame_hex`).

## Credits

- Built with [PakKit](https://github.com/ericreinsmidt/pakkit) and [Apostrophe](https://github.com/Helaas/Apostrophe)
- For [NextUI](https://github.com/LoveRetro/NextUI)

## License

MIT — see [LICENSE](LICENSE)
