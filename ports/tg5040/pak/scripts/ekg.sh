#!/bin/sh
# NAME: EKG
# PLATFORM: brick
# Heartbeat Monitor — TrimUI Brick per-LED animation
# EKG-style blip sweeps across the top bar against a dim baseline
# All LEDs hold a dim glow, bright green blip travels right to left
# Pause between beats like a real heart monitor
#
# Daemon-ready: writes PID to /tmp/led_anim.pid for external management
# Launch detached:  /path/to/heartbeat.sh > /dev/null 2>&1 &
# Stop externally:  kill $(cat /tmp/led_anim.pid)

F="/sys/class/led_anim/frame_hex"
E="/sys/class/led_anim/effect_enable"
PIDFILE="/tmp/led_anim.pid"

# --- PID management ---
if [ -f "$PIDFILE" ]; then
    OLD_PID=$(cat "$PIDFILE")
    if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
        kill "$OLD_PID" 2>/dev/null
        sleep 0.5
    fi
    rm -f "$PIDFILE"
fi
echo $$ > "$PIDFILE"

# --- Setup ---
echo 90 > /sys/class/led_anim/max_scale
echo 50 > /sys/class/led_anim/max_scale_f1f2
echo 40 > /sys/class/led_anim/max_scale_lr
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

# --- Cleanup on exit ---
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

# --- Write one frame ---
write_frame() {
    echo "$1 " > "$F"
    sleep "$2"
    echo 1 > "$E"
    echo 0 > "$E"
}

# Colors
O="000000"       # off
DIM="002200"     # dim green baseline on top bar
DDIM="001100"    # very dim green for F1/F2/triggers
B="00FF00"       # bright blip
T1="00AA00"      # trail 1
T2="005500"      # trail 2

# Timing
SWEEP=0.04       # blip sweep speed
REST=0.60        # pause between beats

# Baseline frame — everything dim
BASE="$DIM $DIM $DIM $DIM $DIM $DIM $DIM $DIM $DDIM $DDIM $DDIM $DDIM $DDIM $DDIM"

while true; do
    # --- Flat baseline (pre-beat) ---
    write_frame "$BASE" "$REST"

    # --- Blip sweeps right to left across top bar ---
    # pos 8: blip at LED 8
    write_frame "$DIM $DIM $DIM $DIM $DIM $DIM $DIM $B $DDIM $DDIM $DDIM $DDIM $DDIM $DDIM" "$SWEEP"
    # pos 7
    write_frame "$DIM $DIM $DIM $DIM $DIM $DIM $B $T1 $DDIM $DDIM $DDIM $DDIM $DDIM $DDIM" "$SWEEP"
    # pos 6 — building up to the spike
    write_frame "$DIM $DIM $DIM $DIM $DIM $B $T1 $T2 $DDIM $DDIM $DDIM $DDIM $DDIM $DDIM" "$SWEEP"
    # pos 5 — THE SPIKE — all LEDs flash bright
    write_frame "$DIM $DIM $DIM $B $B $T1 $T2 $T2 $B $B $T1 $T2 $T2 $T1" "$SWEEP"
    # pos 4 — spike falloff
    write_frame "$DIM $DIM $DIM $B $T1 $T2 $T2 $DIM $T2 $T2 $DDIM $DDIM $DDIM $DDIM" "$SWEEP"
    # pos 3
    write_frame "$DIM $DIM $B $T1 $T2 $T2 $DIM $DIM $DDIM $DDIM $DDIM $DDIM $DDIM $DDIM" "$SWEEP"
    # pos 2
    write_frame "$DIM $B $T1 $T2 $T2 $DIM $DIM $DIM $DDIM $DDIM $DDIM $DDIM $DDIM $DDIM" "$SWEEP"
    # pos 1
    write_frame "$B $T1 $T2 $T2 $DIM $DIM $DIM $DIM $DDIM $DDIM $DDIM $DDIM $DDIM $DDIM" "$SWEEP"
    # fade out
    write_frame "$T1 $T2 $T2 $DIM $DIM $DIM $DIM $DIM $DDIM $DDIM $DDIM $DDIM $DDIM $DDIM" "$SWEEP"
    write_frame "$T2 $T2 $DIM $DIM $DIM $DIM $DIM $DIM $DDIM $DDIM $DDIM $DDIM $DDIM $DDIM" "$SWEEP"
    # back to baseline
    write_frame "$BASE" "$SWEEP"
done
