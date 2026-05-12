#!/bin/sh
# NAME: Kessel Run
# Jump to lightspeed — stars streak outward from center
# Streaks originate from center of top bar and race to edges
# Triggers sweep outward as streaks reach the bar edges
# F1/F2 stay off
#
# Daemon-ready: writes PID to /tmp/led_anim.pid for external management
# Launch detached:  /path/to/hyperspace.sh > /dev/null 2>&1 &
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
echo 95 > /sys/class/led_anim/max_scale
echo 0 > /sys/class/led_anim/max_scale_f1f2
echo 70 > /sys/class/led_anim/max_scale_lr
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
O="000000"
BG="020208"       # near-black space background
DIM="111133"      # dim blue-white star hint
T1="8888CC"       # trail dim
T2="BBBBEE"       # trail bright
BR="EEEEFF"      # bright star
WH="FFFFFF"       # full white flash

# Top bar layout: LEDs 1-8, center is between 4 and 5
# Outward from center: 4,5 → 3,6 → 2,7 → 1,8
# Triggers: positions 11,12=TL,TL2  13,14=TR2,TR
# F1/F2: positions 9,10 = always off

# --- Single streak: star appears at center, races outward ---
# $1 = speed (seconds per frame)
streak() {
    _spd=$1
    # Frame 1: spark at center
    write_frame "$BG $BG $BG $BR $BR $BG $BG $BG $O $O $BG $BG $BG $BG" "$_spd"
    # Frame 2: center fades, next ring lights
    write_frame "$BG $BG $T2 $T1 $T1 $T2 $BG $BG $O $O $BG $BG $BG $BG" "$_spd"
    # Frame 3: spreading
    write_frame "$BG $T2 $T1 $DIM $DIM $T1 $T2 $BG $O $O $BG $BG $BG $BG" "$_spd"
    # Frame 4: reaching edges
    write_frame "$T2 $T1 $DIM $BG $BG $DIM $T1 $T2 $O $O $BG $BG $BG $BG" "$_spd"
    # Frame 5: edges bright, triggers start inside
    write_frame "$BR $T1 $DIM $BG $BG $DIM $T1 $BR $O $O $BG $T2 $T2 $BG" "$_spd"
    # Frame 6: bar fading, triggers sweep outward
    write_frame "$T1 $DIM $BG $BG $BG $BG $DIM $T1 $O $O $T1 $T2 $T2 $T1" "$_spd"
    # Frame 7: triggers reaching outer
    write_frame "$DIM $BG $BG $BG $BG $BG $BG $DIM $O $O $BR $DIM $DIM $BR" "$_spd"
    # Frame 8: everything fading
    write_frame "$BG $BG $BG $BG $BG $BG $BG $BG $O $O $T1 $BG $BG $T1" "$_spd"
}

BLANK="$BG $BG $BG $BG $BG $BG $BG $BG $O $O $BG $BG $BG $BG"

while true; do
    # --- Phase 1: Slow scattered stars (building up) ---
    write_frame "$BLANK" 0.60
    streak 0.12
    write_frame "$BLANK" 0.50
    streak 0.11
    write_frame "$BLANK" 0.35
    streak 0.10

    # --- Phase 2: Getting faster, less gap ---
    write_frame "$BLANK" 0.20
    streak 0.08
    write_frame "$BLANK" 0.15
    streak 0.07
    write_frame "$BLANK" 0.10
    streak 0.06

    # --- Phase 3: Rapid fire ---
    streak 0.04
    streak 0.04
    streak 0.03
    streak 0.03
    streak 0.03
    streak 0.02
    streak 0.02

    # --- Phase 4: JUMP — full white flash ---
    write_frame "$WH $WH $WH $WH $WH $WH $WH $WH $O $O $WH $WH $WH $WH" 0.15
    write_frame "$BR $BR $BR $BR $BR $BR $BR $BR $O $O $BR $BR $BR $BR" 0.10
    write_frame "$T2 $T2 $T2 $T2 $T2 $T2 $T2 $T2 $O $O $T2 $T2 $T2 $T2" 0.08
    write_frame "$T1 $T1 $T1 $T1 $T1 $T1 $T1 $T1 $O $O $T1 $T1 $T1 $T1" 0.08
    write_frame "$DIM $DIM $DIM $DIM $DIM $DIM $DIM $DIM $O $O $DIM $DIM $DIM $DIM" 0.08
    write_frame "$BG $BG $BG $BG $BG $BG $BG $BG $O $O $BG $BG $BG $BG" 0.06

    # --- Blackout pause before next cycle ---
    write_frame "$BLANK" 1.50
done
