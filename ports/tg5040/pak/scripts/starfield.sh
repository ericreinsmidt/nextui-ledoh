#!/bin/sh
# NAME: Starfield
# Starfield — TrimUI Brick per-LED animation
# Random LEDs twinkle white against darkness
#
# Daemon-ready: writes PID to /tmp/led_anim.pid for external management
# Launch detached:  /path/to/starfield.sh > /dev/null 2>&1 &
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

# Star brightness levels
O="000000"
S1="111111"
S2="333333"
S3="666666"
S4="999999"
S5="CCCCCC"
S6="FFFFFF"

# Occasional colored stars
SC1="AAAACC"
SC2="CCBBAA"
SC3="AACCAA"

# 24 hand-crafted frames
F01="$S4 $O  $O  $O  $O  $S2 $O  $O  $O  $O  $O  $O  $S1 $O"
F02="$O  $O  $S3 $O  $O  $O  $O  $S5 $O  $O  $O  $O  $O  $O"
F03="$O  $O  $O  $O  $S6 $O  $O  $O  $O  $S2 $O  $O  $O  $O"
F04="$O  $S2 $O  $O  $O  $O  $S3 $O  $O  $O  $O  $S1 $O  $O"
F05="$O  $O  $O  $SC1 $O $O  $O  $O  $S3 $O  $O  $O  $O  $O"
F06="$S3 $O  $O  $O  $O  $O  $O  $S4 $O  $O  $S2 $O  $O  $O"
F07="$O  $O  $S5 $O  $O  $S1 $O  $O  $O  $O  $O  $O  $O  $S2"
F08="$O  $O  $O  $O  $O  $O  $S2 $O  $O  $S4 $O  $O  $O  $O"
F09="$O  $S6 $O  $O  $O  $O  $O  $O  $O  $O  $O  $O  $S3 $O"
F10="$O  $O  $O  $O  $S3 $O  $O  $SC2 $O $O  $O  $S1 $O  $O"
F11="$S2 $O  $O  $O  $O  $S5 $O  $O  $O  $O  $O  $O  $O  $S1"
F12="$O  $O  $O  $S4 $O  $O  $O  $O  $S2 $O  $O  $O  $O  $O"
F13="$O  $O  $S1 $O  $O  $O  $S6 $O  $O  $O  $S1 $O  $O  $O"
F14="$O  $SC3 $O $O  $O  $O  $O  $S3 $O  $O  $O  $O  $S2 $O"
F15="$O  $O  $O  $O  $S2 $O  $O  $O  $O  $S5 $O  $O  $O  $O"
F16="$S5 $O  $O  $O  $O  $O  $S1 $O  $O  $O  $O  $S3 $O  $O"
F17="$O  $O  $S4 $O  $O  $O  $O  $O  $S1 $O  $O  $O  $O  $S2"
F18="$O  $O  $O  $O  $O  $S3 $O  $SC1 $O $O  $O  $O  $O  $O"
F19="$O  $S1 $O  $S5 $O  $O  $O  $O  $O  $O  $S2 $O  $O  $O"
F20="$O  $O  $O  $O  $O  $O  $O  $S2 $O  $S3 $O  $O  $S1 $O"
F21="$S3 $O  $O  $O  $SC2 $O $O  $O  $O  $O  $O  $O  $O  $S2"
F22="$O  $O  $O  $O  $O  $S4 $O  $O  $S2 $O  $O  $O  $O  $O"
F23="$O  $S3 $O  $O  $O  $O  $O  $S1 $O  $O  $O  $S2 $O  $O"
F24="$O  $O  $O  $S2 $O  $O  $S5 $O  $O  $O  $O  $O  $S3 $O"

while true; do
    write_frame "$F01"; write_frame "$F02"; write_frame "$F03"
    write_frame "$F04"; write_frame "$F05"; write_frame "$F06"
    write_frame "$F07"; write_frame "$F08"; write_frame "$F09"
    write_frame "$F10"; write_frame "$F11"; write_frame "$F12"
    write_frame "$F13"; write_frame "$F14"; write_frame "$F15"
    write_frame "$F16"; write_frame "$F17"; write_frame "$F18"
    write_frame "$F19"; write_frame "$F20"; write_frame "$F21"
    write_frame "$F22"; write_frame "$F23"; write_frame "$F24"
done
