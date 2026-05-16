#!/bin/sh
# NAME: Morse
# PLATFORM: brick
# Morse Code — NEXTUI — TrimUI Brick per-LED animation
# Flashes "NEXTUI" in morse code using NextUI brand color (deeper magenta)
# N(-.) E(.) X(-..-) T(-) U(..-) I(..)
#
# Daemon-ready: writes PID to /tmp/led_anim.pid for external management
# Launch detached:  /path/to/morse.sh > /dev/null 2>&1 &
# Stop externally:  kill $(cat /tmp/led_anim.pid)

F="/sys/class/led_anim/frame_hex"
E="/sys/class/led_anim/effect_enable"
PIDFILE="/tmp/led_anim.pid"

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
echo 30 > /sys/class/led_anim/max_scale_f1f2
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
    sleep "$2"
    echo 1 > "$E"
    echo 0 > "$E"
}

# Colors — deeper magenta/mauve
ON="CC2266"
DIM="110510"
TX="331122"
O="000000"

# Timing
DOT=0.15
DASH=0.45
ELEM_GAP=0.15
LETTER_GAP=0.45
WORD_GAP=1.05

# Frames
BRIGHT="$ON $ON $ON $ON $ON $ON $ON $ON $DIM $DIM $TX $TX $TX $TX"
DARK="$O $O $O $O $O $O $O $O $DIM $DIM $TX $TX $TX $TX"
OFF="$O $O $O $O $O $O $O $O $O $O $O $O $O $O"

dot() {
    write_frame "$BRIGHT" "$DOT"
    write_frame "$DARK" "$ELEM_GAP"
}

dash() {
    write_frame "$BRIGHT" "$DASH"
    write_frame "$DARK" "$ELEM_GAP"
}

letter_gap() {
    write_frame "$DARK" 0.30
}

word_gap() {
    write_frame "$OFF" "$WORD_GAP"
}

while true; do
    # N: dash dot
    dash; dot
    letter_gap

    # E: dot
    dot
    letter_gap

    # X: dash dot dot dash
    dash; dot; dot; dash
    letter_gap

    # T: dash
    dash
    letter_gap

    # U: dot dot dash
    dot; dot; dash
    letter_gap

    # I: dot dot
    dot; dot

    # End of word
    word_gap
done
