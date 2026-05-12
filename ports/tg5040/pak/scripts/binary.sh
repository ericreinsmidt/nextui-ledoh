#!/bin/sh
# NAME: Binary
# Binary Counter — TrimUI Brick per-LED animation
# 8 top bar LEDs represent 8 bits counting from 0 to 255
# Bright = 1, dark = 0. Counts up, resets, repeat.
# Triggers show dim blue, F1/F2 off
#
# Daemon-ready: writes PID to /tmp/led_anim.pid for external management
# Launch detached:  /path/to/binary.sh > /dev/null 2>&1 &
# Stop externally:  kill $(cat /tmp/led_anim.pid)

F="/sys/class/led_anim/frame_hex"
E="/sys/class/led_anim/effect_enable"
PIDFILE="/tmp/led_anim.pid"
SPEED=0.12

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
echo 0 > /sys/class/led_anim/max_scale_f1f2
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
    sleep $SPEED
    echo 1 > "$E"
    echo 0 > "$E"
}

# Colors
ON="00CCFF"   # Bright cyan = 1
OFF="001122"  # Very dim blue = 0
DB="001133"   # Dim blue for triggers

# Get bit color: $1=number, $2=bit position (7=MSB, 0=LSB)
bit_color() {
    _val=$1
    _bit=$2
    _mask=$(( 1 << _bit ))
    if [ $(( _val & _mask )) -ne 0 ]; then
        echo "$ON"
    else
        echo "$OFF"
    fi
}

count=0
while true; do
    # LED 1 = bit 0 (LSB, left), LED 8 = bit 7 (MSB, right)
    L1=$(bit_color $count 0)
    L2=$(bit_color $count 1)
    L3=$(bit_color $count 2)
    L4=$(bit_color $count 3)
    L5=$(bit_color $count 4)
    L6=$(bit_color $count 5)
    L7=$(bit_color $count 6)
    L8=$(bit_color $count 7)

    write_frame "$L1 $L2 $L3 $L4 $L5 $L6 $L7 $L8 000000 000000 $DB $DB $DB $DB"

    count=$(( count + 1 ))
    if [ $count -ge 256 ]; then
        # Flash all on at 255, pause, then reset
        write_frame "$ON $ON $ON $ON $ON $ON $ON $ON 000000 000000 $DB $DB $DB $DB"
        sleep 0.5
        write_frame "$OFF $OFF $OFF $OFF $OFF $OFF $OFF $OFF 000000 000000 $DB $DB $DB $DB"
        sleep 0.3
        count=0
    fi
done
