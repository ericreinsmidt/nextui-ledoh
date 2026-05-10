#!/bin/sh
# Police Lights — TrimUI Brick per-LED animation
# Alternating red/blue flash across all 14 LEDs
#
# Daemon-ready: writes PID to /tmp/led_anim.pid for external management
# Launch detached:  /path/to/police.sh > /dev/null 2>&1 &
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
echo 70 > /sys/class/led_anim/max_scale_f1f2
echo 70 > /sys/class/led_anim/max_scale_lr
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
R="FF0000"
B="0000FF"
O="000000"

FLASH=0.06
DARK=0.04
PAUSE=0.12

while true; do
    # RED LEFT / BLUE RIGHT — double flash
    write_frame "$R $R $R $R $B $B $B $B $B $R $R $R $B $B" "$FLASH"
    write_frame "$O $O $O $O $O $O $O $O $O $O $O $O $O $O" "$DARK"
    write_frame "$R $R $R $R $B $B $B $B $B $R $R $R $B $B" "$FLASH"
    write_frame "$O $O $O $O $O $O $O $O $O $O $O $O $O $O" "$PAUSE"

    # BLUE LEFT / RED RIGHT — double flash
    write_frame "$B $B $B $B $R $R $R $R $R $B $B $B $R $R" "$FLASH"
    write_frame "$O $O $O $O $O $O $O $O $O $O $O $O $O $O" "$DARK"
    write_frame "$B $B $B $B $R $R $R $R $R $B $B $B $R $R" "$FLASH"
    write_frame "$O $O $O $O $O $O $O $O $O $O $O $O $O $O" "$PAUSE"
done
