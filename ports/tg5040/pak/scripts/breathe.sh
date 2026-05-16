#!/bin/sh
# NAME: Breathe
# PLATFORM: smartpro
# Smooth breathing effect — all LEDs pulse together through warm colors
#
# Smart Pro LED layout (23 total):
#   0       = Logo (GRB byte order)
#   1-11    = Left ring, 11 LEDs
#   12-22   = Right ring, 11 LEDs

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
echo "000000 " > /sys/class/led_anim/effect_rgb_hex_m
echo "000000 " > /sys/class/led_anim/effect_rgb_hex_lr
echo 0 > /sys/class/led_anim/effect_m
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
    exit 0
}
trap cleanup INT TERM HUP

RING=11

make_frame() {
    rc="$1"
    logo="$2"
    ring=""
    i=0
    while [ $i -lt $RING ]; do
        ring="${ring}${rc} "
        i=$((i + 1))
    done
    echo "${logo} ${ring}${ring}" > "$F"
}

while true; do
    # Warm orange breathe cycle — ramp up
    make_frame "0a0200" "020a00"; sleep 0.08
    make_frame "1a0500" "051a00"; sleep 0.08
    make_frame "330a00" "0a3300"; sleep 0.08
    make_frame "4d1000" "104d00"; sleep 0.08
    make_frame "661500" "156600"; sleep 0.08
    make_frame "802000" "208000"; sleep 0.08
    make_frame "993000" "309900"; sleep 0.08
    make_frame "b34000" "40b300"; sleep 0.08
    make_frame "cc5500" "55cc00"; sleep 0.08
    make_frame "e66a00" "6ae600"; sleep 0.08
    make_frame "ff8000" "80ff00"; sleep 0.08

    # Hold at peak
    sleep 0.3

    # Ramp down
    make_frame "e66a00" "6ae600"; sleep 0.08
    make_frame "cc5500" "55cc00"; sleep 0.08
    make_frame "b34000" "40b300"; sleep 0.08
    make_frame "993000" "309900"; sleep 0.08
    make_frame "802000" "208000"; sleep 0.08
    make_frame "661500" "156600"; sleep 0.08
    make_frame "4d1000" "104d00"; sleep 0.08
    make_frame "330a00" "0a3300"; sleep 0.08
    make_frame "1a0500" "051a00"; sleep 0.08
    make_frame "0a0200" "020a00"; sleep 0.08
    make_frame "000000" "000000"; sleep 0.08

    # Hold at dark
    sleep 0.5
done
