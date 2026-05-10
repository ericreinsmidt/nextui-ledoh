#!/bin/sh
# NAME: Lava Lamp
# Lava Lamp — TrimUI Brick per-LED animation
# Slow, blobby warm color blobs that rise and merge
# Deep reds, oranges, and yellows bubbling upward
#
# Daemon-ready: writes PID to /tmp/led_anim.pid for external management
# Launch detached:  /path/to/lava.sh > /dev/null 2>&1 &
# Stop externally:  kill $(cat /tmp/led_anim.pid)

F="/sys/class/led_anim/frame_hex"
E="/sys/class/led_anim/effect_enable"
PIDFILE="/tmp/led_anim.pid"
SPEED=0.18

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
echo 90 > /sys/class/led_anim/max_scale
echo 40 > /sys/class/led_anim/max_scale_f1f2
echo 30 > /sys/class/led_anim/max_scale_lr
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

# Lava palette — 16 colors from deep red through orange to yellow and back
P00="440000"; P01="661000"; P02="882200"; P03="AA3300"
P04="CC4400"; P05="DD5500"; P06="EE6600"; P07="FF8800"
P08="FFAA00"; P09="FFCC22"; P10="FFDD44"; P11="FFBB11"
P12="EE7700"; P13="CC5500"; P14="993300"; P15="661100"

get_color() {
    _idx=$(( $1 % 16 ))
    case $_idx in
        0) echo "$P00";;  1) echo "$P01";;  2) echo "$P02";;  3) echo "$P03";;
        4) echo "$P04";;  5) echo "$P05";;  6) echo "$P06";;  7) echo "$P07";;
        8) echo "$P08";;  9) echo "$P09";; 10) echo "$P10";; 11) echo "$P11";;
       12) echo "$P12";; 13) echo "$P13";; 14) echo "$P14";; 15) echo "$P15";;
    esac
}

# Each LED moves through the palette at a different speed/offset
# creating the illusion of blobs rising at different rates
step=0
while true; do
    # Top bar — each LED at a prime-number offset for organic motion
    L1=$(get_color $(( (step * 3 + 0) / 2 )) )
    L2=$(get_color $(( (step * 2 + 5) / 2 )) )
    L3=$(get_color $(( (step * 5 + 2) / 3 )) )
    L4=$(get_color $(( (step * 3 + 11) / 2 )) )
    L5=$(get_color $(( (step * 7 + 4) / 4 )) )
    L6=$(get_color $(( (step * 2 + 9) / 2 )) )
    L7=$(get_color $(( (step * 4 + 7) / 3 )) )
    L8=$(get_color $(( (step * 3 + 14) / 2 )) )

    # Buttons glow deep red-orange
    BG=$(get_color $(( (step + 3) / 3 )) )

    # Triggers pulse slowly between deep red shades
    TG=$(get_color $(( step / 4 )) )

    write_frame "$L1 $L2 $L3 $L4 $L5 $L6 $L7 $L8 $BG $BG $TG $TG $TG $TG"

    step=$(( step + 1 ))
    if [ $step -ge 4800 ]; then
        step=0
    fi
done
