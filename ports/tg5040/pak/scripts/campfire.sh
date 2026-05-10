#!/bin/sh
# NAME: Campfire
# Campfire — TrimUI Brick per-LED animation
# Flickering warm fire on the top bar — reds, oranges, ambers, yellow tips
# Triggers glow steady amber like embers
# F1/F2 hold a warm glow
#
# Daemon-ready: writes PID to /tmp/led_anim.pid for external management
# Launch detached:  /path/to/campfire.sh > /dev/null 2>&1 &
# Stop externally:  kill $(cat /tmp/led_anim.pid)

F="/sys/class/led_anim/frame_hex"
E="/sys/class/led_anim/effect_enable"
PIDFILE="/tmp/led_anim.pid"
SPEED=0.07

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
echo 60 > /sys/class/led_anim/max_scale_f1f2
echo 55 > /sys/class/led_anim/max_scale_lr
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

# Fire palette — warm only, no greens
# Bright tips
H0="FFCC11"  # bright yellow tip
H1="FFBB22"  # golden yellow
H2="FFAA00"  # amber-yellow
# Core flames
F0="FF8800"  # bright orange
F1="FF6600"  # orange
F2="FF5500"  # orange-red
F3="FF4400"  # deep orange
F4="EE5500"  # warm orange
# Base / coals
R0="DD3300"  # red-orange
R1="CC2200"  # dark red
R2="BB1100"  # deep red
R3="991100"  # coal red
R4="881100"  # dark coal

# Ember glow for triggers and F1/F2
EMBER1="662200"  # L1/R1 — bright ember
EMBER2="441100"  # L2/R2 — dim ember
FGLOW="553300"   # F1/F2 — warm glow

# 20 hand-crafted frames — mix of bright flares, steady burn, and dark flickers
# Each frame: 8 top bar LEDs + F2 F1 L1 L2 R2 R1

while true; do
    # Steady burn
    write_frame "$F1 $F3 $F0 $H1 $F2 $F4 $F1 $F3 $FGLOW $FGLOW $EMBER1 $EMBER2 $EMBER2 $EMBER1"
    # Flare up on left
    write_frame "$H0 $H2 $F0 $F2 $R0 $F3 $F1 $F4 $FGLOW $FGLOW $EMBER1 $EMBER2 $EMBER2 $EMBER1"
    # Settle
    write_frame "$F0 $F1 $F3 $F1 $F2 $F0 $F4 $F2 $FGLOW $FGLOW $EMBER1 $EMBER2 $EMBER2 $EMBER1"
    # Dim flicker
    write_frame "$R0 $F3 $R1 $F4 $R0 $R2 $F3 $R1 $FGLOW $FGLOW $EMBER2 $EMBER2 $EMBER2 $EMBER2"
    # Bright center
    write_frame "$F2 $F0 $H1 $H0 $H2 $F0 $F2 $F4 $FGLOW $FGLOW $EMBER1 $EMBER2 $EMBER2 $EMBER1"
    # Flare right
    write_frame "$F4 $F2 $F1 $F3 $F0 $H2 $H1 $H0 $FGLOW $FGLOW $EMBER1 $EMBER2 $EMBER2 $EMBER1"
    # Dark moment
    write_frame "$R1 $R0 $R2 $F3 $R1 $R0 $R3 $R2 $FGLOW $FGLOW $EMBER2 $EMBER2 $EMBER2 $EMBER2"
    # Recovery
    write_frame "$F3 $F1 $F0 $F2 $F1 $F3 $F0 $F1 $FGLOW $FGLOW $EMBER1 $EMBER2 $EMBER2 $EMBER1"
    # Dancing tips
    write_frame "$F1 $H0 $F2 $F0 $H1 $F3 $F1 $H2 $FGLOW $FGLOW $EMBER1 $EMBER2 $EMBER2 $EMBER1"
    # Settle low
    write_frame "$F3 $F4 $R0 $F2 $F4 $R0 $F3 $F1 $FGLOW $FGLOW $EMBER1 $EMBER2 $EMBER2 $EMBER1"
    # Big flare
    write_frame "$H1 $F0 $H0 $H2 $F0 $H1 $F1 $F0 $FGLOW $FGLOW $EMBER1 $EMBER2 $EMBER2 $EMBER1"
    # Quick dim
    write_frame "$F2 $R0 $F3 $R1 $F4 $R0 $R2 $F3 $FGLOW $FGLOW $EMBER2 $EMBER2 $EMBER2 $EMBER2"
    # Coals glow
    write_frame "$R0 $R1 $R0 $R2 $R0 $R1 $R0 $R3 $FGLOW $FGLOW $EMBER2 $EMBER2 $EMBER2 $EMBER2"
    # Reignite
    write_frame "$F1 $F0 $F2 $H2 $F0 $F1 $F3 $F0 $FGLOW $FGLOW $EMBER1 $EMBER2 $EMBER2 $EMBER1"
    # Steady
    write_frame "$F0 $F2 $F1 $F0 $F3 $F1 $F0 $F2 $FGLOW $FGLOW $EMBER1 $EMBER2 $EMBER2 $EMBER1"
    # Left tip
    write_frame "$H2 $H0 $F0 $F3 $F1 $F4 $R0 $F3 $FGLOW $FGLOW $EMBER1 $EMBER2 $EMBER2 $EMBER1"
    # Flicker down
    write_frame "$F4 $R0 $F2 $R0 $F3 $R1 $F4 $R0 $FGLOW $FGLOW $EMBER2 $EMBER2 $EMBER2 $EMBER2"
    # Warm up
    write_frame "$F2 $F1 $F0 $F1 $F0 $F2 $F1 $F0 $FGLOW $FGLOW $EMBER1 $EMBER2 $EMBER2 $EMBER1"
    # Right flare
    write_frame "$F3 $F4 $F2 $F0 $H0 $H1 $H0 $F0 $FGLOW $FGLOW $EMBER1 $EMBER2 $EMBER2 $EMBER1"
    # Settle to coals
    write_frame "$R0 $F3 $F4 $R0 $F2 $F3 $R0 $R1 $FGLOW $FGLOW $EMBER2 $EMBER2 $EMBER2 $EMBER2"
done
