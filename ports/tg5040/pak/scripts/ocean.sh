#!/bin/sh
# NAME: Ocean
# Ocean Waves — TrimUI Brick per-LED animation
# Slow drifting blue/teal/cyan gradient across the top bar
# Triggers hold deep ocean blue, F1/F2 pick up seafoam
#
# Daemon-ready: writes PID to /tmp/led_anim.pid for external management
# Launch detached:  /path/to/ocean.sh > /dev/null 2>&1 &
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
echo 80 > /sys/class/led_anim/max_scale
echo 60 > /sys/class/led_anim/max_scale_f1f2
echo 50 > /sys/class/led_anim/max_scale_lr
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

# Ocean palette — 20 colors forming a smooth wave loop
C00="002266"; C01="003377"; C02="004488"; C03="005599"
C04="0066AA"; C05="0077AA"; C06="0088AA"; C07="0099BB"
C08="00AACC"; C09="00BBCC"; C10="00CCBB"; C11="00BBAA"
C12="00AA99"; C13="009988"; C14="008877"; C15="007766"
C16="006655"; C17="005566"; C18="004477"; C19="003366"

DEEP="001133"
FOAM="004455"

get_color() {
    _idx=$(( $1 % 20 ))
    case $_idx in
        0) echo "$C00";; 1) echo "$C01";; 2) echo "$C02";; 3) echo "$C03";;
        4) echo "$C04";; 5) echo "$C05";; 6) echo "$C06";; 7) echo "$C07";;
        8) echo "$C08";; 9) echo "$C09";; 10) echo "$C10";; 11) echo "$C11";;
        12) echo "$C12";; 13) echo "$C13";; 14) echo "$C14";; 15) echo "$C15";;
        16) echo "$C16";; 17) echo "$C17";; 18) echo "$C18";; 19) echo "$C19";;
    esac
}

OFF1=0; OFF2=2; OFF3=5; OFF4=7; OFF5=10; OFF6=12; OFF7=15; OFF8=17

step=0
while true; do
    L1=$(get_color $(( step + OFF1 )) )
    L2=$(get_color $(( step + OFF2 )) )
    L3=$(get_color $(( step + OFF3 )) )
    L4=$(get_color $(( step + OFF4 )) )
    L5=$(get_color $(( step + OFF5 )) )
    L6=$(get_color $(( step + OFF6 )) )
    L7=$(get_color $(( step + OFF7 )) )
    L8=$(get_color $(( step + OFF8 )) )

    write_frame "$L1 $L2 $L3 $L4 $L5 $L6 $L7 $L8 $FOAM $FOAM $DEEP $DEEP $DEEP $DEEP"

    step=$(( step + 1 ))
    if [ $step -ge 2000 ]; then
        step=0
    fi
done
