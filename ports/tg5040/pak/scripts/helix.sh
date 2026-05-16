#!/bin/sh
# NAME: Helix
# PLATFORM: smartpro
# Two colored dots chase each other around each ring, 180° apart
# Left ring = red/blue, Right ring = blue/red (mirrored)
#
# Smart Pro LED layout (23 total):
#   0       = Logo (GRB byte order)
#   1-11    = Left ring, 11 LEDs, 9 o'clock CCW
#   12-22   = Right ring, 11 LEDs, 9 o'clock CCW

F="/sys/class/led_anim/frame_hex"
E="/sys/class/led_anim/effect_enable"
PIDFILE="/tmp/led_anim.pid"
SPEED=0.07

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

# Colors
R="ff0000"
Rt="660000"
B="0000ff"
Bt="000066"
O="000000"

RING=11
HALF=5

step=0
while true; do
    # Dot positions
    d1=$step
    d1t=$(( (step - 1 + RING) % RING ))
    d2=$(( (step + HALF) % RING ))
    d2t=$(( (step + HALF - 1 + RING) % RING ))

    # Left ring: red dot + blue dot
    i=0
    lring=""
    while [ $i -lt $RING ]; do
        c="$O"
        [ $i -eq $d1t ] && c="$Rt"
        [ $i -eq $d2t ] && c="$Bt"
        [ $i -eq $d1 ] && c="$R"
        [ $i -eq $d2 ] && c="$B"
        lring="${lring}${c} "
        i=$((i + 1))
    done

    # Right ring: blue dot + red dot (swapped)
    i=0
    rring=""
    while [ $i -lt $RING ]; do
        c="$O"
        [ $i -eq $d1t ] && c="$Bt"
        [ $i -eq $d2t ] && c="$Rt"
        [ $i -eq $d1 ] && c="$B"
        [ $i -eq $d2 ] && c="$R"
        rring="${rring}${c} "
        i=$((i + 1))
    done

    # Logo alternates between purple blend
    logo="660066"
    echo "${logo} ${lring}${rring}" > "$F"
    sleep $SPEED

    step=$(( (step + 1) % RING ))
done
