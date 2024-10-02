#!/bin/bash
# Wartezeit, um sicherzustellen, dass das Netzwerk verfügbar ist
sleep 10
xset s off
xset -dpms
xset s noblank
chromium-browser --noerrdialogs --disable-infobars --kiosk http://localhost