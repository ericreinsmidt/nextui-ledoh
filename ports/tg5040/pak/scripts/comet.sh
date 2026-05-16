#!/bin/sh
# NAME: Comet
# PLATFORM: brick
# Comet — TrimUI Brick per-LED animation
# Bright white head with blue fading tail
# Wraps around all 14 LEDs
#
# Daemon-ready: writes PID to /tmp/led_anim.pid for external management
# Launch detached:  /path/to/comet.sh > /dev/null 2>&1 &
# Stop externally:  kill $(cat /tmp/led_anim.pid)

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
echo 85 > /sys/class/led_anim/max_scale
echo 70 > /sys/class/led_anim/max_scale_f1f2
echo 60 > /sys/class/led_anim/max_scale_lr
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

# Comet colors
H="FFFFFF"
T1="AABBFF"
T2="6688DD"
T3="3355AA"
T4="1A3377"
T5="0D1A44"
O="000000"

get_led_color() {
    _head=$1
    _pos=$2
    _dist=$(( (_head - _pos + 14) % 14 ))
    case $_dist in
        0) echo "$H";;
        1) echo "$T1";;
        2) echo "$T2";;
        3) echo "$T3";;
        4) echo "$T4";;
        5) echo "$T5";;
        *) echo "$O";;
    esac
}

head_pos=0
while true; do
    P1=$(get_led_color $head_pos 0)
    P2=$(get_led_color $head_pos 1)
    P3=$(get_led_color $head_pos 2)
    P4=$(get_led_color $head_pos 3)
    P5=$(get_led_color $head_pos 4)
    P6=$(get_led_color $head_pos 5)
    P7=$(get_led_color $head_pos 6)
    P8=$(get_led_color $head_pos 7)
    P9=$(get_led_color $head_pos 8)
    P10=$(get_led_color $head_pos 9)
    P11=$(get_led_color $head_pos 10)
    P12=$(get_led_color $head_pos 11)
    P13=$(get_led_color $head_pos 12)
    P14=$(get_led_color $head_pos 13)

    write_frame "$P1 $P2 $P3 $P4 $P5 $P6 $P7 $P8 $P9 $P10 $P11 $P12 $P13 $P14"

    head_pos=$(( (head_pos + 1) % 14 ))
done
