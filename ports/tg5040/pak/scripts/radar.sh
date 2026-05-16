#!/bin/sh
# NAME: Radar
# PLATFORM: smartpro
# Single radar sweep — bright head with fading tail on each joystick ring
#
# Smart Pro LED layout (23 total):
#   0       = Logo (GRB byte order)
#   1-11    = Left ring, 11 LEDs, 9 o'clock CCW
#   12-22   = Right ring, 11 LEDs, 9 o'clock CCW
#
# Daemon-ready: writes PID to /tmp/led_anim.pid for external management

F="/sys/class/led_anim/frame_hex"
E="/sys/class/led_anim/effect_enable"
PIDFILE="/tmp/led_anim.pid"
SPEED=0.06

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

# --- Colors ---
H="00ff00"   # bright head
T1="009900"  # tail 1
T2="004400"  # tail 2
T3="001a00"  # tail 3
O="000000"   # off

RING=11

step=0
while true; do
    h=$step
    t1=$(( (step - 1 + RING) % RING ))
    t2=$(( (step - 2 + RING) % RING ))
    t3=$(( (step - 3 + RING) % RING ))

    i=0
    ring=""
    while [ $i -lt $RING ]; do
        c="$O"
        [ $i -eq $t3 ] && c="$T3"
        [ $i -eq $t2 ] && c="$T2"
        [ $i -eq $t1 ] && c="$T1"
        [ $i -eq $h ] && c="$H"
        ring="${ring}${c} "
        i=$((i + 1))
    done

    logo="001a00"
    echo "${logo} ${ring}${ring}" > "$F"
    sleep $SPEED

    step=$(( (step + 1) % RING ))
done
