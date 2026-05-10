#!/bin/sh
# Aurora Borealis — TrimUI Brick per-LED animation
# Slow-drifting greens, teals, and purples across the top bar
# Triggers glow soft green like distant ground light
# F1/F2 pick up ambient aurora color
#
# Daemon-ready: writes PID to /tmp/led_anim.pid for external management
# Launch detached:  /path/to/aurora.sh > /dev/null 2>&1 &
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

# Aurora palette — 24 colors forming a smooth loop
C00="00CC44"; C01="00BB55"; C02="00AA66"; C03="009977"
C04="008888"; C05="007799"; C06="0066AA"; C07="1155BB"
C08="2244BB"; C09="4433AA"; C10="6622AA"; C11="8811AA"
C12="9911AA"; C13="AA1199"; C14="992288"; C15="883377"
C16="774466"; C17="665555"; C18="447744"; C19="339944"
C20="22AA44"; C21="11BB44"; C22="00CC55"; C23="00CC44"

TL="0A3318"; TR="0A3318"; TL2="082A14"; TR2="082A14"

get_color() {
    _idx=$(( $1 % 24 ))
    case $_idx in
        0) echo "$C00";; 1) echo "$C01";; 2) echo "$C02";; 3) echo "$C03";;
        4) echo "$C04";; 5) echo "$C05";; 6) echo "$C06";; 7) echo "$C07";;
        8) echo "$C08";; 9) echo "$C09";; 10) echo "$C10";; 11) echo "$C11";;
        12) echo "$C12";; 13) echo "$C13";; 14) echo "$C14";; 15) echo "$C15";;
        16) echo "$C16";; 17) echo "$C17";; 18) echo "$C18";; 19) echo "$C19";;
        20) echo "$C20";; 21) echo "$C21";; 22) echo "$C22";; 23) echo "$C23";;
    esac
}

OFF1=0; OFF2=3; OFF3=6; OFF4=9; OFF5=12; OFF6=15; OFF7=18; OFF8=21

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

    BF2="$L8"
    BF1="$L1"

    write_frame "$L1 $L2 $L3 $L4 $L5 $L6 $L7 $L8 $BF2 $BF1 $TL $TL2 $TR2 $TR"

    step=$(( step + 1 ))
    if [ $step -ge 2400 ]; then
        step=0
    fi
done
