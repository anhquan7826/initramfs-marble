#!/bin/busybox ash
fb=/sys/class/graphics/fb0/blank
if [ -w "$fb" ]; then
  echo 1 > "$fb"
  sleep 1
  echo 0 > "$fb"
  sleep 1
fi
