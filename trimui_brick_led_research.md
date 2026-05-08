# TrimUI Brick — Per-LED Hardware Research

- **Date:** May 7–8, 2026
- **Researcher:** Eric Reinsmidt using Claude
- **Device:** TrimUI Brick (tg5040)
- **Firmware:** Stock (stable NextUI)
- **Method:** Physical teardown + iterative sysfs testing via SSH terminal

---

## Summary

The TrimUI Brick has **14 individually addressable RGB LEDs** accessible via a single sysfs interface (`frame_hex`). The existing zone-based effect system (`effect_*`) groups these into 4 logical zones, but `frame_hex` bypasses zoning entirely and gives per-LED color control. Animation is possible via a toggle workaround that clears a driver write-block between frames.

This was discovered through physical teardown and systematic testing. The driver help file claims 23 LEDs — this is incorrect. The actual count is 14.

---

## Physical LED Layout

Confirmed via device teardown (back shell removed, PCB exposed):

```
FRONT VIEW (screen facing you, playing position):

Top bar (8 LEDs, evenly spaced):
  [1] [2] [3] [4] [5] [6] [7] [8]
   ←  left                right →

Front buttons:
  [F1]                    [F2]
  (pos 10)               (pos 9)

Triggers (back/sides of device):
  [L1] [L2]              [R2] [R1]
  (11)  (12)             (13)  (14)
```

**Total: 14 physical RGB LEDs**

---

## Complete `frame_hex` Position Map

| Position | Physical LED | Zone (effect system) | Notes |
|----------|-------------|---------------------|-------|
| 1 | Top bar — far left | m | |
| 2 | Top bar — 2nd from left | m | |
| 3 | Top bar — 3rd from left | m | |
| 4 | Top bar — 4th from left | m | |
| 5 | Top bar — 5th from left | m | |
| 6 | Top bar — 6th from left | m | |
| 7 | Top bar — 7th from left | m | |
| 8 | Top bar — far right | m | |
| 9 | F2 button | f2 | Note: F2 before F1 in position order |
| 10 | F1 button | f1 | |
| 11 | L1 trigger | lr (grouped) | Individually addressable via frame_hex |
| 12 | L2 trigger | lr (grouped) | Individually addressable via frame_hex |
| 13 | R2 trigger | lr (grouped) | Individually addressable via frame_hex |
| 14 | R1 trigger | lr (grouped) | Individually addressable via frame_hex |

### Key discoveries:
- **F2 comes before F1** in the position order (position 9 vs 10)
- **Trigger LEDs are 4 separate LEDs** (L1, L2, R2, R1) — the zone system groups them as "lr" but `frame_hex` can address each independently
- **Positions 15–23 do nothing** — the driver help file's claim of 23 LEDs is incorrect
- **The readback of `frame_hex` shows 7 values** — this is misleading; the interface accepts 8 (top bar) or 14 (all LEDs) values on write

---

## Driver Help File Accuracy

The help file at `/sys/class/led_anim/help` contains a mix of correct and incorrect information:

| Claim | Reality |
|-------|---------|
| "total 23 XRGB 32bpp data" | **Wrong** — 14 LEDs, positions 15–23 do nothing |
| `frame_hex` format (RRGGBB space-separated, trailing space) | **Correct** |
| `effect_lr`: "Left and right joystick LEDS" | **Wrong for Brick** — these are trigger LEDs, not joysticks. Help was written for Smart Pro |
| `effect_l` / `effect_r`: "joystick LEDS" | **Smart Pro zones** — exist in sysfs on Brick but Brick uses f1/f2/lr instead |
| `effect_m`: "middle LED" | **Partially correct** — top bar on Brick, logo on Smart Pro |
| `max_scale` limit "60" | **Soft limit** — values of 80+ work fine |
| "!!Did not finish yet!!" (anim_frames) | **Accurate** — `anim_frames` system non-functional, `frame_hex` blocks on second write without workaround |

The help file was clearly written for the Smart Pro and the LED count is simply wrong. The format descriptions and effect system documentation are mostly accurate.

---

## Sysfs Interface

### Path
```
/sys/class/led_anim/frame_hex
```

### Write Format
```
RRGGBB RRGGBB RRGGBB ... RRGGBB 
```
Space-separated hex RGB values, trailing space. 14 values for all LEDs, or 8 for top bar only. **The trailing space is required.**

### Read Format
Returns 7 values (always — even when 8 or 14 were written). The readback is unreliable/misleading.

### Related Files
| File | Purpose | Notes |
|------|---------|-------|
| `effect_enable` | Toggle zone-based effect system | Must be 0 for `frame_hex` to take effect |
| `max_scale` | Top bar brightness | Must be > 0 to see top bar LEDs |
| `max_scale_f1f2` | F1/F2 brightness | Must be > 0 to see F1/F2 LEDs |
| `max_scale_lr` | Trigger brightness | Must be > 0 to see trigger LEDs |
| `effect_rgb_hex_m` | Zone color for top bar | Set to `000000` before animation to prevent flash |
| `effect_rgb_hex_f1` | Zone color for F1 | Set to `000000` before animation |
| `effect_rgb_hex_f2` | Zone color for F2 | Set to `000000` before animation |
| `effect_rgb_hex_lr` | Zone color for triggers | Set to `000000` before animation |

---

## Animation: The Toggle Workaround

### The Problem
The driver blocks on the **second consecutive write** to `frame_hex` when `effect_enable=0`. The write hangs at the kernel level and **cannot be interrupted with Ctrl+C**. This caused system instability during testing.

### The Solution
Toggle `effect_enable` back to 1 and then to 0 between each frame write. This clears whatever internal lock the driver holds.

### Animation Loop Pattern
```bash
# Setup (once)
echo 80 > /sys/class/led_anim/max_scale
echo 80 > /sys/class/led_anim/max_scale_f1f2              # if using f1/f2
echo 80 > /sys/class/led_anim/max_scale_lr                # if using triggers
echo "000000 " > /sys/class/led_anim/effect_rgb_hex_m     # prevent flash
echo "000000 " > /sys/class/led_anim/effect_rgb_hex_f1    # prevent flash
echo "000000 " > /sys/class/led_anim/effect_rgb_hex_f2    # prevent flash
echo "000000 " > /sys/class/led_anim/effect_rgb_hex_lr    # prevent flash
echo 4 > /sys/class/led_anim/effect_m
echo 4 > /sys/class/led_anim/effect_f1
echo 4 > /sys/class/led_anim/effect_f2
echo 4 > /sys/class/led_anim/effect_lr
echo 0 > /sys/class/led_anim/effect_enable
sleep 0.3

# Per-frame (repeat)
echo "RRGGBB RRGGBB ... " > /sys/class/led_anim/frame_hex  # write frame
sleep $FRAME_DELAY                                         # hold frame
echo 1 > /sys/class/led_anim/effect_enable                 # clear block
echo 0 > /sys/class/led_anim/effect_enable                 # re-disable for next write

# Cleanup (once, on exit)
echo 1 > /sys/class/led_anim/effect_enable
echo 4 > /sys/class/led_anim/effect_m
echo -1 > /sys/class/led_anim/effect_cycles_m
echo 50 > /sys/class/led_anim/max_scale
echo 50 > /sys/class/led_anim/max_scale_f1f2
echo 50 > /sys/class/led_anim/max_scale_lr
```

### Why It Works
1. `effect_enable=0` suspends the zone-based effect system, allowing `frame_hex` to drive LEDs directly
2. The driver accepts one `frame_hex` write, then blocks on the next (internal lock/semaphore not released)
3. Setting `effect_enable=1` re-activates the zone system, which releases the lock
4. Setting `effect_enable=0` again suspends the zone system, ready for the next `frame_hex` write
5. Setting zone colors to `000000` prevents a visible flash during the brief `effect_enable=1` moment

### Performance
- Shell script (`sh`) with `sleep 0.06`–`0.08` between frames works well for sweep animations
- The toggle overhead adds some latency but is not visually noticeable
- Smooth enough for K.I.T.T. scanner, rainbow chases, and similar effects

---

## Confirmed Working: K.I.T.T. Scanner

A full 8-LED Knight Rider scanner was implemented and tested successfully using the toggle workaround. Features:
- Sweeps left-to-right and back across all 8 top bar LEDs
- 3-level brightness tail (bright head `FF0000`, medium `880000`, dim `330000`)
- Runs in an infinite loop at ~0.06s per frame
- Visually smooth and recognizable as the K.I.T.T. scanner effect

### Working Script
```bash
#!/bin/sh
F="/sys/class/led_anim/frame_hex"
E="/sys/class/led_anim/effect_enable"
SPEED=0.06
B="FF0000"; M="880000"; D="330000"; O="000000"

echo 0 > /sys/class/led_anim/max_scale_f1f2
echo 0 > /sys/class/led_anim/max_scale_lr
echo 80 > /sys/class/led_anim/max_scale
echo "000000 " > /sys/class/led_anim/effect_rgb_hex_m
echo 4 > /sys/class/led_anim/effect_m
echo 0 > "$E"
sleep 0.3

write_frame() {
    echo "$1 " > "$F"
    sleep $SPEED
    echo 1 > "$E"
    echo 0 > "$E"
}

while true; do
    write_frame "$B $O $O $O $O $O $O $O"
    write_frame "$M $B $O $O $O $O $O $O"
    write_frame "$D $M $B $O $O $O $O $O"
    write_frame "$O $D $M $B $O $O $O $O"
    write_frame "$O $O $D $M $B $O $O $O"
    write_frame "$O $O $O $D $M $B $O $O"
    write_frame "$O $O $O $O $D $M $B $O"
    write_frame "$O $O $O $O $O $D $M $B"
    write_frame "$O $O $O $O $O $O $B $M"
    write_frame "$O $O $O $O $O $B $M $D"
    write_frame "$O $O $O $O $B $M $D $O"
    write_frame "$O $O $O $B $M $D $O $O"
    write_frame "$O $O $B $M $D $O $O $O"
    write_frame "$O $B $M $D $O $O $O $O"
    write_frame "$B $M $D $O $O $O $O $O"
done
```

---

## Confirmed Working: Rainbow Chase (Top Bar)

An 8-color rainbow that rotates across the top bar LEDs. Tested and working.

### Working Script
```bash
#!/bin/sh
F="/sys/class/led_anim/frame_hex"
E="/sys/class/led_anim/effect_enable"
SPEED=0.06

echo 0 > /sys/class/led_anim/max_scale_f1f2
echo 0 > /sys/class/led_anim/max_scale_lr
echo 80 > /sys/class/led_anim/max_scale
echo "000000 " > /sys/class/led_anim/effect_rgb_hex_m
echo 4 > /sys/class/led_anim/effect_m
echo 0 > "$E"
sleep 0.3

A="FF0000"; B="FF8800"; C="FFFF00"; D="00FF00"
E2="00FFFF"; F2="0000FF"; G="8800FF"; H="FF00FF"

write_frame() {
    echo "$1 " > "$F"
    sleep $SPEED
    echo 1 > "$E"
    echo 0 > "$E"
}

while true; do
    write_frame "$A $B $C $D $E2 $F2 $G $H"
    write_frame "$H $A $B $C $D $E2 $F2 $G"
    write_frame "$G $H $A $B $C $D $E2 $F2"
    write_frame "$F2 $G $H $A $B $C $D $E2"
    write_frame "$E2 $F2 $G $H $A $B $C $D"
    write_frame "$D $E2 $F2 $G $H $A $B $C"
    write_frame "$C $D $E2 $F2 $G $H $A $B"
    write_frame "$B $C $D $E2 $F2 $G $H $A"
done
```

---

## Confirmed Working: Rainbow Chase (Top Bar + Triggers)

12-LED rainbow chase spanning top bar and trigger LEDs, skipping F1/F2. **Not yet confirmed on device** — uses `${C10}`, `${C11}`, `${C12}` shell variable syntax which may not work on the device's `sh`.

### Script (untested)
```bash
#!/bin/sh
F="/sys/class/led_anim/frame_hex"
E="/sys/class/led_anim/effect_enable"
SPEED=0.06
O="000000"

echo 80 > /sys/class/led_anim/max_scale
echo 0 > /sys/class/led_anim/max_scale_f1f2
echo 80 > /sys/class/led_anim/max_scale_lr
echo "000000 " > /sys/class/led_anim/effect_rgb_hex_m
echo "000000 " > /sys/class/led_anim/effect_rgb_hex_f1
echo "000000 " > /sys/class/led_anim/effect_rgb_hex_f2
echo "000000 " > /sys/class/led_anim/effect_rgb_hex_lr
echo 4 > /sys/class/led_anim/effect_m
echo 4 > /sys/class/led_anim/effect_f1
echo 4 > /sys/class/led_anim/effect_f2
echo 4 > /sys/class/led_anim/effect_lr
echo 0 > "$E"
sleep 0.3

C01="FF0000"; C02="FF6600"; C03="FFCC00"; C04="66FF00"
C05="00FF00"; C06="00FF88"; C07="00FFFF"; C08="0066FF"
C09="0000FF"; C10="8800FF"; C11="FF00FF"; C12="FF0066"

write_frame() {
    echo "$1 " > "$F"
    sleep $SPEED
    echo 1 > "$E"
    echo 0 > "$E"
}

while true; do
    write_frame "$C01 $C02 $C03 $C04 $C05 $C06 $C07 $C08 $O $O ${C12} ${C11} ${C10} $C09"
    write_frame "$C12 $C01 $C02 $C03 $C04 $C05 $C06 $C07 $O $O ${C11} ${C10} $C09 $C08"
    write_frame "$C11 $C12 $C01 $C02 $C03 $C04 $C05 $C06 $O $O ${C10} $C09 $C08 $C07"
    write_frame "$C10 $C11 $C12 $C01 $C02 $C03 $C04 $C05 $O $O $C09 $C08 $C07 $C06"
    write_frame "$C09 $C10 $C11 $C12 $C01 $C02 $C03 $C04 $O $O $C08 $C07 $C06 $C05"
    write_frame "$C08 $C09 $C10 $C11 $C12 $C01 $C02 $C03 $O $O $C07 $C06 $C05 $C04"
    write_frame "$C07 $C08 $C09 $C10 $C11 $C12 $C01 $C02 $O $O $C06 $C05 $C04 $C03"
    write_frame "$C06 $C07 $C08 $C09 $C10 $C11 $C12 $C01 $O $O $C05 $C04 $C03 $C02"
    write_frame "$C05 $C06 $C07 $C08 $C09 $C10 $C11 $C12 $O $O $C04 $C03 $C02 $C01"
    write_frame "$C04 $C05 $C06 $C07 $C08 $C09 $C10 $C11 $O $O $C03 $C02 $C01 $C12"
    write_frame "$C03 $C04 $C05 $C06 $C07 $C08 $C09 $C10 $O $O $C02 $C01 $C12 $C11"
    write_frame "$C02 $C03 $C04 $C05 $C06 $C07 $C08 $C09 $O $O $C01 $C12 $C11 $C10"
done
```

---

## Confirmed Working: Rainbow Chase (All 14 LEDs)

Full-device rainbow chase across all 14 LEDs in clockwise physical order. **Not yet confirmed on device** — uses `build_frame` function with `${11}`+ positional parameters which may not work on the device's `sh`.

### Script (untested)
```bash
#!/bin/sh
F="/sys/class/led_anim/frame_hex"
E="/sys/class/led_anim/effect_enable"
SPEED=0.06

echo 80 > /sys/class/led_anim/max_scale
echo 80 > /sys/class/led_anim/max_scale_f1f2
echo 80 > /sys/class/led_anim/max_scale_lr
echo "000000 " > /sys/class/led_anim/effect_rgb_hex_m
echo "000000 " > /sys/class/led_anim/effect_rgb_hex_f1
echo "000000 " > /sys/class/led_anim/effect_rgb_hex_f2
echo "000000 " > /sys/class/led_anim/effect_rgb_hex_lr
echo 4 > /sys/class/led_anim/effect_m
echo 4 > /sys/class/led_anim/effect_f1
echo 4 > /sys/class/led_anim/effect_f2
echo 4 > /sys/class/led_anim/effect_lr
echo 0 > "$E"
sleep 0.3

C01="FF0000"; C02="FF6600"; C03="FFCC00"; C04="88FF00"
C05="00FF00"; C06="00FF88"; C07="00FFFF"; C08="0088FF"
C09="0000FF"; C10="8800FF"; C11="FF00FF"; C12="FF0088"
C13="FF4444"; C14="FFAA00"

write_frame() {
    echo "$1 " > "$F"
    sleep $SPEED
    echo 1 > "$E"
    echo 0 > "$E"
}

build_frame() {
    # Args: 14 colors in chase order (top1-8, r1, r2, f2, f1, l2, l1)
    # Output: 14 colors in frame_hex order (top1-8, f2, f1, l1, l2, r2, r1)
    echo "$1 $2 $3 $4 $5 $6 $7 $8 ${11} ${12} ${14} ${13} ${10} $9"
}

while true; do
    write_frame "$(build_frame $C01 $C02 $C03 $C04 $C05 $C06 $C07 $C08 $C09 $C10 $C11 $C12 $C13 $C14)"
    write_frame "$(build_frame $C14 $C01 $C02 $C03 $C04 $C05 $C06 $C07 $C08 $C09 $C10 $C11 $C12 $C13)"
    write_frame "$(build_frame $C13 $C14 $C01 $C02 $C03 $C04 $C05 $C06 $C07 $C08 $C09 $C10 $C11 $C12)"
    write_frame "$(build_frame $C12 $C13 $C14 $C01 $C02 $C03 $C04 $C05 $C06 $C07 $C08 $C09 $C10 $C11)"
    write_frame "$(build_frame $C11 $C12 $C13 $C14 $C01 $C02 $C03 $C04 $C05 $C06 $C07 $C08 $C09 $C10)"
    write_frame "$(build_frame $C10 $C11 $C12 $C13 $C14 $C01 $C02 $C03 $C04 $C05 $C06 $C07 $C08 $C09)"
    write_frame "$(build_frame $C09 $C10 $C11 $C12 $C13 $C14 $C01 $C02 $C03 $C04 $C05 $C06 $C07 $C08)"
    write_frame "$(build_frame $C08 $C09 $C10 $C11 $C12 $C13 $C14 $C01 $C02 $C03 $C04 $C05 $C06 $C07)"
    write_frame "$(build_frame $C07 $C08 $C09 $C10 $C11 $C12 $C13 $C14 $C01 $C02 $C03 $C04 $C05 $C06)"
    write_frame "$(build_frame $C06 $C07 $C08 $C09 $C10 $C11 $C12 $C13 $C14 $C01 $C02 $C03 $C04 $C05)"
    write_frame "$(build_frame $C05 $C06 $C07 $C08 $C09 $C10 $C11 $C12 $C13 $C14 $C01 $C02 $C03 $C04)"
    write_frame "$(build_frame $C04 $C05 $C06 $C07 $C08 $C09 $C10 $C11 $C12 $C13 $C14 $C01 $C02 $C03)"
    write_frame "$(build_frame $C03 $C04 $C05 $C06 $C07 $C08 $C09 $C10 $C11 $C12 $C13 $C14 $C01 $C02)"
    write_frame "$(build_frame $C02 $C03 $C04 $C05 $C06 $C07 $C08 $C09 $C10 $C11 $C12 $C13 $C14 $C01)"
done
```

---

## Hazards & Recovery

### ⚠️ DANGER: Second `frame_hex` write blocks
If you write to `frame_hex` twice without toggling `effect_enable` in between, the second write **blocks at the kernel level**. This is an uninterruptible sleep — **Ctrl+C will not work**. The shell process becomes unkillable from the same session.

### Recovery procedures (in order of preference):
1. **From another terminal session:** `killall sh` then run the restore commands
2. **Hard power cycle:** Hold power button 10+ seconds
3. **SD card pull:** Remove SD card, delete any stale PID/lock files, reinsert

### Restore commands (run after killing animation):
```bash
echo 1 > /sys/class/led_anim/effect_enable
echo 4 > /sys/class/led_anim/effect_m
echo -1 > /sys/class/led_anim/effect_cycles_m
echo 50 > /sys/class/led_anim/max_scale
echo 50 > /sys/class/led_anim/max_scale_f1f2
echo 50 > /sys/class/led_anim/max_scale_lr
```

---

## Comparison: Zone Effect System vs frame_hex

| Feature | Zone Effects (`effect_*`) | `frame_hex` |
|---------|--------------------------|-------------|
| Granularity | 4 zones (m, f1, f2, lr) | 14 individual LEDs |
| Built-in effects | 7 (linear, breathe, sniff, static, blink×3) | None — manual frame-by-frame |
| Animation | Hardware-driven | Software-driven (toggle workaround) |
| Stability | Stable, production-ready | Works but requires workaround; driver unfinished |
| Brightness control | Per-zone (`max_scale*`) | Same `max_scale*` paths still apply |
| Concurrent use | Normal operation | Must disable `effect_enable` — mutually exclusive |
| Color byte order | RGB (except Smart Pro m zone = GRB) | RGB (confirmed) |

---

## NextUI Hooks (Future Integration)

NextUI nightly v6.11.0a (alpha, not yet in stable) introduced pak hooks:

| Hook | Directory | Trigger |
|------|-----------|---------|
| `boot.d` | `.hooks/boot.d/` | System startup |
| `pre-launch.d` | `.hooks/pre-launch.d/` | Before ROM/pak launch |
| `post-launch.d` | `.hooks/post-launch.d/` | After ROM/pak exit |
| `pre-sleep.d` | `.hooks/pre-sleep.d/` | Before suspend |
| `post-resume.d` | `.hooks/post-resume.d/` | After wake |

Scripts go in `/mnt/SDCARD/.userdata/tg5040/.hooks/<hook-type>/`. Launch hooks receive `HOOK_TYPE`, `HOOK_EMU_PATH`, `HOOK_ROM_PATH`, `HOOK_LAST` environment variables. Scripts run async by default, or sync with `.sync.sh` suffix.

**Status:** Gated on hooks landing in stable NextUI. LED'oh! could install/uninstall hook scripts from its menu to trigger LED animations on game launch, sleep, wake, etc.

---

## Reference: Driver Help File

`/mnt/SDCARD # cat /sys/class/led_anim/help`

```bash
[TRIMUI LED Animation driver] 
    max_scale : maxium LED brightness in dec [0 ~ tg5040 limit brightness 60] 
    frame     : raw frames for total 23 XRGB 32bpp data 
    frame_hex : frames for total 23 XRGB 32bpp data in hex format "RRGGBB RRGGBB RRGGBB ... RRGGBB " end with space. 
    
[usage of anim to function] 
    effect_lr: Left and right joystick LEDS effect type. 
    effect_l: Left joystick LEDS effect type. 
    effect_r: Right joystick LEDS effect type. 
    effect_m : middle LED effect type. 
   (effect_x for a trigger of effect start) 
    effect_names : show the effect types description. 
    effect_duration_lr: Left and right joystick LEDS animation durations. 
    effect_duration_l: Left joystick LEDS animation durations. 
    effect_duration_r: Right joystick LEDS animation durations. 
    effect_duration_m : middle LED effect duration. 
    effect_rgb_hex_lr: Left and right LED all target color in format "RRGGBB " end with space. 
    effect_rgb_hex_l: Left LED all target color in format "RRGGBB " end with space. 
    effect_rgb_hex_r: Left LED all target color in format "RRGGBB " end with space. 
    effect_rgb_hex_m: Middle LED target color in format "RRGGBB " end with space. 
    effect_cycles_lr: Left and right joystick LEDS animation loops. 
    effect_cycles_l: Left joystick LEDS animation loops. 
    effect_cycles_r: Right joystick LEDS animation loops. 
    effect_cycles_m : middle LED effect loops. 
   (cycles value: 0 for stop, -1 for endless loop, > 0 for loop times) 
    effect_enable   : toggle of anim to function 
         
[usage of framebuffer animation function !!Did not finish yet!!] 
    anim_frames:       raw frames for total XRGB 32bpp data, buffer length 10 sec@60fps, 23 data per frame. 
    anim_frames_hex:   same as anim_frames and use hex format "RRGGBB RRGGBB RRGGBB ... RRGGBB " end with space. 
    anim_frames_cycle: animation loops count 
    anim_frames_enable : toggle of frames anim function 
    anim_frames_override_m_enable: toggle of middle LED in frames anim function. 
```
