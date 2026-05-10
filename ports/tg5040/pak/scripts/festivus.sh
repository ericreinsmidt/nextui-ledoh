#!/bin/sh
# Festivus — TrimUI Brick per-LED animation
# Alternating red and green with gentle twinkling
# F1/F2 hold warm white, triggers alternate red/green
#
# Daemon-ready: writes PID to /tmp/led_anim.pid for external management
# Launch detached:  /path/to/festivus.sh > /dev/null 2>&1 &
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
echo 80 > /sys/class/led_anim/max_scale
echo 50 > /sys/class/led_anim/max_scale_f1f2
echo 50 > /sys/class/led_anim/max_scale_lr
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
RB="DD0000"  # Bright red
RD="881111"  # Dim red
GB="00CC00"  # Bright green
GD="118811"  # Dim green
TW="FFDDAA"  # Twinkle — warm white
WG="332211"  # Warm glow for F1/F2
SPEED=0.15

# 16 hand-crafted frames — alternating red/green with twinkle accents
# Each frame: top[1-8] F2 F1 L1 L2 R2 R1
# Pattern: even positions red, odd positions green, with brightness variation
# Occasional warm white twinkle on random positions

while true; do
    # Steady — classic alternating
    write_frame "$RB $GB $RB $GB $RB $GB $RB $GB $WG $WG $RD $GD $GD $RD" "$SPEED"
    write_frame "$RB $GB $RB $GB $RB $GB $RB $GB $WG $WG $RD $GD $GD $RD" "$SPEED"
    # Twinkle on pos 3
    write_frame "$RB $GB $TW $GB $RB $GB $RB $GB $WG $WG $RD $GD $GD $RD" "$SPEED"
    # Back to steady
    write_frame "$RB $GB $RB $GB $RB $GB $RB $GB $WG $WG $RD $GD $GD $RD" "$SPEED"
    # Dim phase
    write_frame "$RD $GD $RD $GD $RD $GD $RD $GD $WG $WG $RD $GD $GD $RD" 0.20
    # Brighten back
    write_frame "$RB $GB $RB $GB $RB $GB $RB $GB $WG $WG $RD $GD $GD $RD" "$SPEED"
    # Twinkle on pos 6
    write_frame "$RB $GB $RB $GB $RB $TW $RB $GB $WG $WG $RD $GD $GD $RD" "$SPEED"
    # Steady
    write_frame "$RB $GB $RB $GB $RB $GB $RB $GB $WG $WG $RD $GD $GD $RD" "$SPEED"
    # Swap! Green first now
    write_frame "$GB $RB $GB $RB $GB $RB $GB $RB $WG $WG $GD $RD $RD $GD" "$SPEED"
    write_frame "$GB $RB $GB $RB $GB $RB $GB $RB $WG $WG $GD $RD $RD $GD" "$SPEED"
    # Twinkle on pos 1
    write_frame "$TW $RB $GB $RB $GB $RB $GB $RB $WG $WG $GD $RD $RD $GD" "$SPEED"
    # Steady swapped
    write_frame "$GB $RB $GB $RB $GB $RB $GB $RB $WG $WG $GD $RD $RD $GD" "$SPEED"
    # Dim phase
    write_frame "$GD $RD $GD $RD $GD $RD $GD $RD $WG $WG $GD $RD $RD $GD" 0.20
    # Brighten
    write_frame "$GB $RB $GB $RB $GB $RB $GB $RB $WG $WG $GD $RD $RD $GD" "$SPEED"
    # Twinkle on pos 8
    write_frame "$GB $RB $GB $RB $GB $RB $GB $TW $WG $WG $GD $RD $RD $GD" "$SPEED"
    # Steady before loop
    write_frame "$GB $RB $GB $RB $GB $RB $GB $RB $WG $WG $GD $RD $RD $GD" "$SPEED"
done
