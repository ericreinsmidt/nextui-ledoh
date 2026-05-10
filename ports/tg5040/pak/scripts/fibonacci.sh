#!/bin/sh
# Fibonacci — TrimUI Brick per-LED animation
# LEDs light up at fibonacci positions, then shift and evolve
# Golden/amber color scheme — mathematical beauty
# F1/F2 pulse on fibonacci hits, triggers hold dim gold
#
# Daemon-ready: writes PID to /tmp/led_anim.pid for external management
# Launch detached:  /path/to/fibonacci.sh > /dev/null 2>&1 &
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
echo 60 > /sys/class/led_anim/max_scale_f1f2
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

# Colors — golden/amber palette
GB="FFAA00"  # Golden bright — fibonacci position lit
GD="332200"  # Golden dim — background
GM="AA7700"  # Golden medium — fading
FG="554400"  # F1/F2 glow
TG="221100"  # Trigger dim gold
O="000000"   # Off

# Fibonacci sequence mod 8: positions that light up
# fib: 1 1 2 3 5 8 13 21 34 55 89 144...
# mod 8: 1 1 2 3 5 0 5 5 2 7 1 0 1 1 2 3 5 0 ... (period 12)
# Positions (0-indexed): 1,1,2,3,5,0,5,5,2,7,1,0

# We'll animate by building up the sequence one number at a time
# then sweeping it off and starting over

# Phase 1: Build up — light each fib position one at a time
# Phase 2: All lit positions glow together
# Phase 3: Fade out and restart

# Pre-computed fibonacci mod 8 sequence (12 steps before repeating)
# F1=1 F2=1 F3=2 F4=3 F5=5 F6=0 F7=5 F8=5 F9=2 F10=7 F11=1 F12=0
FIB_COUNT=12

get_fib_pos() {
    case $1 in
        0) echo 1;; 1) echo 1;; 2) echo 2;; 3) echo 3;;
        4) echo 5;; 5) echo 0;; 6) echo 5;; 7) echo 5;;
        8) echo 2;; 9) echo 7;; 10) echo 1;; 11) echo 0;;
    esac
}

# Build a frame with specific positions lit
# $1-$8 = color for each LED position (0-7)
make_frame() {
    echo "$1 $2 $3 $4 $5 $6 $7 $8 $FG $FG $TG $TG $TG $TG"
}

while true; do
    # --- Phase 1: Build up fibonacci positions one at a time ---
    # Track which positions are lit
    P0="$GD"; P1="$GD"; P2="$GD"; P3="$GD"
    P4="$GD"; P5="$GD"; P6="$GD"; P7="$GD"

    fib_step=0
    while [ $fib_step -lt $FIB_COUNT ]; do
        pos=$(get_fib_pos $fib_step)

        # Light up this position
        case $pos in
            0) P0="$GB";; 1) P1="$GB";; 2) P2="$GB";; 3) P3="$GB";;
            4) P4="$GB";; 5) P5="$GB";; 6) P6="$GB";; 7) P7="$GB";;
        esac

        FRAME=$(make_frame "$P0" "$P1" "$P2" "$P3" "$P4" "$P5" "$P6" "$P7")
        write_frame "$FRAME" 0.25

        fib_step=$(( fib_step + 1 ))
    done

    # --- Phase 2: All lit — hold and pulse ---
    FRAME=$(make_frame "$P0" "$P1" "$P2" "$P3" "$P4" "$P5" "$P6" "$P7")
    write_frame "$FRAME" 0.40

    # Bright pulse
    BRIGHT=$(make_frame "$GB" "$GB" "$GB" "$GB" "$GB" "$GB" "$GB" "$GB")
    write_frame "$BRIGHT" 0.15
    write_frame "$FRAME" 0.30

    # --- Phase 3: Fade out position by position (reverse order) ---
    fib_step=$(( FIB_COUNT - 1 ))
    while [ $fib_step -ge 0 ]; do
        pos=$(get_fib_pos $fib_step)

        # Dim this position to medium first
        case $pos in
            0) P0="$GM";; 1) P1="$GM";; 2) P2="$GM";; 3) P3="$GM";;
            4) P4="$GM";; 5) P5="$GM";; 6) P6="$GM";; 7) P7="$GM";;
        esac

        FRAME=$(make_frame "$P0" "$P1" "$P2" "$P3" "$P4" "$P5" "$P6" "$P7")
        write_frame "$FRAME" 0.10

        # Then to dim
        case $pos in
            0) P0="$GD";; 1) P1="$GD";; 2) P2="$GD";; 3) P3="$GD";;
            4) P4="$GD";; 5) P5="$GD";; 6) P6="$GD";; 7) P7="$GD";;
        esac

        FRAME=$(make_frame "$P0" "$P1" "$P2" "$P3" "$P4" "$P5" "$P6" "$P7")
        write_frame "$FRAME" 0.10

        fib_step=$(( fib_step - 1 ))
    done

    # All dim — brief pause before restart
    FRAME=$(make_frame "$GD" "$GD" "$GD" "$GD" "$GD" "$GD" "$GD" "$GD")
    write_frame "$FRAME" 0.50
done
