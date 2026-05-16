#!/bin/sh
# NAME: Fill
# PLATFORM: smartpro
# Rings fill up from 6 o'clock (bottom), then drain back down
#
# Smart Pro LED layout (23 total):
#   0       = Logo (GRB byte order)
#   1-11    = Left ring, 11 LEDs, 9 o'clock CCW
#   12-22   = Right ring, 11 LEDs, 9 o'clock CCW
#
# Ring position mapping (approximate clock positions):
#   LED 0  = 9 o'clock     LED 6  = 3 o'clock
#   LED 1  = 8 o'clock     LED 7  = 2 o'clock
#   LED 2  = 7 o'clock     LED 8  = 1 o'clock
#   LED 3  = 6 o'clock     LED 9  = 12 o'clock (top)
#   LED 4  = 5 o'clock     LED 10 = 11 o'clock
#   LED 5  = 4 o'clock
#
# Fill order (bottom up, symmetric):
#   Step 0: 3              (6 o'clock)
#   Step 1: 2, 4           (7, 5)
#   Step 2: 1, 5           (8, 4)
#   Step 3: 0, 6           (9, 3)
#   Step 4: 10, 7          (11, 2)
#   Step 5: 9, 8           (12, 1)

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

C="0066ff"  # fill color (blue)
O="000000"

# Fill order: LED indices per step
# Left ring: starts slightly left of 6 o'clock (index 3)
# Right ring: starts slightly right of 6 o'clock (index 4) — mirrored
LF_0="3"        RF_0="4"
LF_1="2 4"      RF_1="3 5"
LF_2="1 5"      RF_2="2 6"
LF_3="0 6"      RF_3="1 7"
LF_4="10 7"     RF_4="0 8"
LF_5="9 8"      RF_5="10 9"

# Build ring frame from a "lit" set
write_ring() {
    lit=" $* "
    ring=""
    i=0
    while [ $i -lt 11 ]; do
        case "$lit" in
            *" $i "*) ring="${ring}${C} " ;;
            *)        ring="${ring}${O} " ;;
        esac
        i=$((i + 1))
    done
    echo "$ring"
}

write_frame() {
    # $1 = logo color, $2 = left lit indices, $3 = right lit indices
    lring=$(write_ring $2)
    rring=$(write_ring $3)
    echo "$1 ${lring}${rring}" > "$F"
}

while true; do
    # --- Fill up ---
    write_frame "$O" "$LF_0" "$RF_0";                                         sleep $SPEED
    write_frame "$O" "$LF_0 $LF_1" "$RF_0 $RF_1";                             sleep $SPEED
    write_frame "$O" "$LF_0 $LF_1 $LF_2" "$RF_0 $RF_1 $RF_2";                sleep $SPEED
    write_frame "$O" "$LF_0 $LF_1 $LF_2 $LF_3" "$RF_0 $RF_1 $RF_2 $RF_3";   sleep $SPEED
    write_frame "$O" "$LF_0 $LF_1 $LF_2 $LF_3 $LF_4" "$RF_0 $RF_1 $RF_2 $RF_3 $RF_4"; sleep $SPEED

    # Full — flash logo too
    write_frame "0066ff" "$LF_0 $LF_1 $LF_2 $LF_3 $LF_4 $LF_5" "$RF_0 $RF_1 $RF_2 $RF_3 $RF_4 $RF_5"
    sleep 0.5

    # --- Drain down ---
    write_frame "$O" "$LF_0 $LF_1 $LF_2 $LF_3 $LF_4" "$RF_0 $RF_1 $RF_2 $RF_3 $RF_4"; sleep $SPEED
    write_frame "$O" "$LF_0 $LF_1 $LF_2 $LF_3" "$RF_0 $RF_1 $RF_2 $RF_3";   sleep $SPEED
    write_frame "$O" "$LF_0 $LF_1 $LF_2" "$RF_0 $RF_1 $RF_2";                sleep $SPEED
    write_frame "$O" "$LF_0 $LF_1" "$RF_0 $RF_1";                             sleep $SPEED
    write_frame "$O" "$LF_0" "$RF_0";                                         sleep $SPEED

    # Empty
    write_frame "$O" "" ""
    sleep 0.5
done
