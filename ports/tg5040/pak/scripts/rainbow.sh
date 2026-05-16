#!/bin/sh
# NAME: Rainbow
# PLATFORM: smartpro
# 8-color rainbow that slowly rotates around the joystick rings
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
SPEED=0.10

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

# --- 8-color rainbow palette ---
C0="ff0000"  # red
C1="ff8800"  # orange
C2="ffff00"  # yellow
C3="00ff00"  # green
C4="0088ff"  # cyan-blue
C5="0000ff"  # blue
C6="8800ff"  # purple
C7="ff00ff"  # magenta

RING=11
COLORS=8

step=0
while true; do
    # Build one ring: each LED picks a color from the rainbow
    # offset by step to create rotation
    ring=""
    i=0
    while [ $i -lt $RING ]; do
        idx=$(( (i + step) % COLORS ))
        case $idx in
            0) c="$C0" ;;
            1) c="$C1" ;;
            2) c="$C2" ;;
            3) c="$C3" ;;
            4) c="$C4" ;;
            5) c="$C5" ;;
            6) c="$C6" ;;
            7) c="$C7" ;;
        esac
        ring="${ring}${c} "
        i=$((i + 1))
    done

    # Logo cycles through rainbow too (GRB byte order)
    lidx=$(( step % COLORS ))
    case $lidx in
        0) logo="00ff00" ;;
        1) logo="88ff00" ;;
        2) logo="ffff00" ;;
        3) logo="ff0000" ;;
        4) logo="88000f" ;;
        5) logo="0000ff" ;;
        6) logo="008800" ;;
        7) logo="00ff00" ;;
    esac

    echo "${logo} ${ring}${ring}" > "$F"
    sleep $SPEED

    step=$(( (step + 1) % COLORS ))
done
