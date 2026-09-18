#!/bin/bash

LOG="/tmp/dcon.log"

exec >> "$LOG" 2>&1

echo
echo "========== $(date) =========="
echo "DISPLAY=$DISPLAY"
echo "XAUTHORITY=$XAUTHORITY"
echo "USER=$USER"

echo "--- xrandr before ---"
xrandr --query

sleep 5

echo "--- xrandr after sleep ---"
xrandr --query

echo "--- Applying DP-1 ---"
xrandr --output DP-1 \
       --mode 2560x1440_120.00 \
       --primary \
       --pos 0x0

echo "DP exit code: $?"

if xrandr | grep -q "^HDMI-1 connected"; then
    echo "--- Applying HDMI-1 ---"

    xrandr --output HDMI-1 \
           --mode 1920x1080 \
           --right-of DP-1 \
           --rotate right

    echo "HDMI exit code: $?"
else
    echo "HDMI-1 not detected"
fi

echo "--- xrandr after configuration ---"
xrandr --query

echo "========== END =========="
