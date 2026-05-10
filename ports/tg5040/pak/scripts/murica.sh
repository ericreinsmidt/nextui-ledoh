#!/bin/sh
# NAME: 'Murica!
# 'Murica! — TrimUI Brick per-LED animation
# Red, white, and blue chase across the top bar
# Triggers flash red and blue, F1/F2 hold white
#
# Daemon-ready: writes PID to /tmp/led_anim.pid for external management
# Launch detached:  /path/to/murica.sh > /dev/null 2>&1 &
# Stop externally:  kill $(cat /tmp/led_anim.pid)

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
echo 85 > /sys/class/led_anim/max_scale
echo 50 > /sys/class/led_anim/max_scale_f1f2
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

# Colors — Old Glory
R="CC0000"   # Red
W="FFFFFF"   # White
B="0022AA"   # Blue
DW="333333"  # Dim white for F1/F2

# 6-color repeating pattern: R W B R W B
get_color() {
    _idx=$(( $1 % 6 ))
    case $_idx in
        0) echo "$R";; 1) echo "$W";; 2) echo "$B";;
        3) echo "$R";; 4) echo "$W";; 5) echo "$B";;
    esac
}

# Trigger pattern alternates with the chase
get_triggers() {
    _idx=$(( $1 % 6 ))
    case $_idx in
        0) echo "$R $DW $DW $B";;
        1) echo "$R $DW $DW $B";;
        2) echo "$B $DW $DW $R";;
        3) echo "$B $DW $DW $R";;
        4) echo "$R $DW $DW $B";;
        5) echo "$B $DW $DW $R";;
    esac
}

step=0
while true; do
    L1=$(get_color $(( step + 0 )) )
    L2=$(get_color $(( step + 1 )) )
    L3=$(get_color $(( step + 2 )) )
    L4=$(get_color $(( step + 3 )) )
    L5=$(get_color $(( step + 4 )) )
    L6=$(get_color $(( step + 5 )) )
    L7=$(get_color $(( step + 6 )) )
    L8=$(get_color $(( step + 7 )) )

    TRIG=$(get_triggers $step)

    write_frame "$L1 $L2 $L3 $L4 $L5 $L6 $L7 $L8 $DW $DW $TRIG"

    step=$(( step + 1 ))
    if [ $step -ge 600 ]; then
        step=0
    fi
done
