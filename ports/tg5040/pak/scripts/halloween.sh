#!/bin/sh
# Halloween — TrimUI Brick per-LED animation
# Spooky orange and purple with occasional white lightning flash
# Triggers hold eerie green, F1/F2 dim purple
#
# Daemon-ready: writes PID to /tmp/led_anim.pid for external management
# Launch detached:  /path/to/halloween.sh > /dev/null 2>&1 &
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
echo 85 > /sys/class/led_anim/max_scale
echo 50 > /sys/class/led_anim/max_scale_f1f2
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
    sleep "$2"
    echo 1 > "$E"
    echo 0 > "$E"
}

# Colors
OB="FF6600"  # Bright orange
OD="993300"  # Dim orange
PB="8800CC"  # Bright purple
PD="440066"  # Dim purple
W="FFFFFF"   # Lightning white
EG="003311"  # Eerie green for triggers
DP="220033"  # Dim purple for F1/F2
O="000000"   # Off

SPEED=0.12
FLASH=0.03

# Frame layout: top[1-8] F2 F1 L1 L2 R2 R1

while true; do
    # Slow alternating orange/purple
    write_frame "$OB $PB $OB $PB $OB $PB $OB $PB $DP $DP $EG $EG $EG $EG" "$SPEED"
    write_frame "$OB $PB $OB $PB $OB $PB $OB $PB $DP $DP $EG $EG $EG $EG" "$SPEED"
    write_frame "$OB $PB $OB $PB $OB $PB $OB $PB $DP $DP $EG $EG $EG $EG" "$SPEED"

    # Dim down — creepy
    write_frame "$OD $PD $OD $PD $OD $PD $OD $PD $DP $DP $EG $EG $EG $EG" 0.20
    write_frame "$OD $PD $OD $PD $OD $PD $OD $PD $DP $DP $EG $EG $EG $EG" 0.20

    # Brighten
    write_frame "$OB $PB $OB $PB $OB $PB $OB $PB $DP $DP $EG $EG $EG $EG" "$SPEED"
    write_frame "$OB $PB $OB $PB $OB $PB $OB $PB $DP $DP $EG $EG $EG $EG" "$SPEED"

    # LIGHTNING FLASH!
    write_frame "$W $W $W $W $W $W $W $W $W $W $W $W $W $W" "$FLASH"
    write_frame "$O $O $O $O $O $O $O $O $O $O $O $O $O $O" "$FLASH"
    write_frame "$W $W $W $W $W $W $W $W $W $W $W $W $W $W" "$FLASH"
    write_frame "$O $O $O $O $O $O $O $O $O $O $O $O $O $O" 0.08

    # Recover from flash — dim
    write_frame "$OD $PD $OD $PD $OD $PD $OD $PD $DP $DP $EG $EG $EG $EG" 0.20

    # Swap pattern — purple first
    write_frame "$PB $OB $PB $OB $PB $OB $PB $OB $DP $DP $EG $EG $EG $EG" "$SPEED"
    write_frame "$PB $OB $PB $OB $PB $OB $PB $OB $DP $DP $EG $EG $EG $EG" "$SPEED"
    write_frame "$PB $OB $PB $OB $PB $OB $PB $OB $DP $DP $EG $EG $EG $EG" "$SPEED"

    # Dim
    write_frame "$PD $OD $PD $OD $PD $OD $PD $OD $DP $DP $EG $EG $EG $EG" 0.20
    write_frame "$PD $OD $PD $OD $PD $OD $PD $OD $DP $DP $EG $EG $EG $EG" 0.20

    # Brighten
    write_frame "$PB $OB $PB $OB $PB $OB $PB $OB $DP $DP $EG $EG $EG $EG" "$SPEED"

    # Another quick flash — single bolt
    write_frame "$W $W $W $W $W $W $W $W $W $W $W $W $W $W" "$FLASH"
    write_frame "$O $O $O $O $O $O $O $O $O $O $O $O $O $O" 0.10

    # Settle back
    write_frame "$OB $PB $OB $PB $OB $PB $OB $PB $DP $DP $EG $EG $EG $EG" "$SPEED"
    write_frame "$OB $PB $OB $PB $OB $PB $OB $PB $DP $DP $EG $EG $EG $EG" "$SPEED"
done
