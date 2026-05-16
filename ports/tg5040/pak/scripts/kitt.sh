#!/bin/sh
# NAME: K.I.T.T.
# PLATFORM: brick
# K.I.T.T. Scanner — TrimUI Brick per-LED animation
# Classic Knight Rider red sweep with brightness tail — top bar only
#
# Daemon-ready: writes PID to /tmp/led_anim.pid for external management
# Launch detached:  /path/to/kitt.sh > /dev/null 2>&1 &
# Stop externally:  kill $(cat /tmp/led_anim.pid)

F="/sys/class/led_anim/frame_hex"
E="/sys/class/led_anim/effect_enable"
PIDFILE="/tmp/led_anim.pid"
SPEED=0.08

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
echo 0 > /sys/class/led_anim/max_scale_f1f2
echo 0 > /sys/class/led_anim/max_scale_lr
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
    sleep $SPEED
    echo 1 > "$E"
    echo 0 > "$E"
}

# Colors
B="FF0000"  # bright head
M="880000"  # medium tail
D="330000"  # dim tail
O="000000"  # off

while true; do
    # --- Sweep right (pos 0 to 7) ---
    write_frame "$B $O $O $O $O $O $O $O $O $O $O $O $O $O"
    write_frame "$M $B $O $O $O $O $O $O $O $O $O $O $O $O"
    write_frame "$D $M $B $O $O $O $O $O $O $O $O $O $O $O"
    write_frame "$O $D $M $B $O $O $O $O $O $O $O $O $O $O"
    write_frame "$O $O $D $M $B $O $O $O $O $O $O $O $O $O"
    write_frame "$O $O $O $D $M $B $O $O $O $O $O $O $O $O"
    write_frame "$O $O $O $O $D $M $B $O $O $O $O $O $O $O"
    write_frame "$O $O $O $O $O $D $M $B $O $O $O $O $O $O"

    # --- Sweep left (pos 6 down to 1) ---
    write_frame "$O $O $O $O $O $O $B $M $O $O $O $O $O $O"
    write_frame "$O $O $O $O $O $B $M $D $O $O $O $O $O $O"
    write_frame "$O $O $O $O $B $M $D $O $O $O $O $O $O $O"
    write_frame "$O $O $O $B $M $D $O $O $O $O $O $O $O $O"
    write_frame "$O $O $B $M $D $O $O $O $O $O $O $O $O $O"
    write_frame "$O $B $M $D $O $O $O $O $O $O $O $O $O $O"
done
