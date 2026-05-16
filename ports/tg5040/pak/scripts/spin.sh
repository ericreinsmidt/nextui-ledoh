#!/bin/sh
# NAME: Spin
# PLATFORM: smartpro
# Counter-rotating rings — left ring spins CW, right ring spins CCW
#
# Smart Pro LED layout (23 total):
#   0       = Logo (GRB byte order)
#   1-11    = Left ring, 11 LEDs, 9 o'clock CCW
#   12-22   = Right ring, 11 LEDs, 9 o'clock CCW

F="/sys/class/led_anim/frame_hex"
E="/sys/class/led_anim/effect_enable"
PIDFILE="/tmp/led_anim.pid"
SPEED=0.05

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

# --- Colors: 3-LED arc ---
H="ff4400"   # bright head (orange)
T1="882200"  # tail 1
T2="331100"  # tail 2
O="000000"

RING=11

step=0
while true; do
    # Left ring: step goes forward (CCW on device)
    lh=$step
    lt1=$(( (step - 1 + RING) % RING ))
    lt2=$(( (step - 2 + RING) % RING ))

    # Right ring: step goes backward (CW on device = opposite)
    rh=$(( (RING - step) % RING ))
    rt1=$(( (RING - step + 1) % RING ))
    rt2=$(( (RING - step + 2) % RING ))

    # Build left ring
    i=0
    lring=""
    while [ $i -lt $RING ]; do
        c="$O"
        [ $i -eq $lt2 ] && c="$T2"
        [ $i -eq $lt1 ] && c="$T1"
        [ $i -eq $lh ] && c="$H"
        lring="${lring}${c} "
        i=$((i + 1))
    done

    # Build right ring
    i=0
    rring=""
    while [ $i -lt $RING ]; do
        c="$O"
        [ $i -eq $rt2 ] && c="$T2"
        [ $i -eq $rt1 ] && c="$T1"
        [ $i -eq $rh ] && c="$H"
        rring="${rring}${c} "
        i=$((i + 1))
    done

    logo="001100"
    echo "${logo} ${lring}${rring}" > "$F"
    sleep $SPEED

    step=$(( (step + 1) % RING ))
done
