#!/bin/sh
# NAME: Pulse
# PLATFORM: smartpro
# Alternating ring pulses — left ring brightens while right dims, then swap
#
# Smart Pro LED layout (23 total):
#   0       = Logo (GRB byte order)
#   1-11    = Left ring, 11 LEDs
#   12-22   = Right ring, 11 LEDs

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

O="000000"
RING=11

# Brightness steps: ramp up then down (purple/cyan)
# 8 steps up, 8 steps down
LEVELS_P="1a0033 330066 4d0099 6600cc 8000ff 6600cc 4d0099 330066"
LEVELS_C="001a33 003366 004d99 0066cc 0080ff 0066cc 004d99 003366"

# Build a full ring of one color
make_ring() {
    c="$1"
    ring=""
    i=0
    while [ $i -lt $RING ]; do
        ring="${ring}${c} "
        i=$((i + 1))
    done
    echo "$ring"
}

while true; do
    # Left brightens (purple), right dims (cyan)
    for lc in $LEVELS_P; do
        # Reverse index for right ring
        lring=$(make_ring "$lc")

        # Right does opposite phase — pick from cyan levels
        # Use a counter to get the opposite position
        rring=$(make_ring "$O")

        echo "${O} ${lring}${rring}" > "$F"
        sleep 0.06
    done

    # Right brightens (cyan), left dims (purple)
    for rc in $LEVELS_C; do
        rring=$(make_ring "$rc")
        lring=$(make_ring "$O")

        echo "${O} ${lring}${rring}" > "$F"
        sleep 0.06
    done
done
