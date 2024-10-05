#!/bin/bash

# Überprüfen, ob das Skript mit Root-Rechten ausgeführt wird
if [ "$EUID" -ne 0 ]; then
    echo "Bitte führen Sie das Skript mit sudo aus: sudo ./install.sh"
    exit
fi

echo "System wird aktualisiert..."
apt update && apt upgrade -y

echo "Installiere benötigte Pakete..."
apt install -y ffmpeg nginx chromium-browser

echo "Erstelle Verzeichnisse..."
mkdir -p /var/www/html/hls
mkdir -p /home/pi/scripts
mkdir -p /home/pi/services

echo "Kopiere Skripte und Website..."
cp -r scripts/* /home/pi/scripts/
cp -r website/* /var/www/html/
chown -R pi:pi /home/pi/scripts
chown -R www-data:www-data /var/www/html

echo "Lese Kamerakonfigurationen..."
CAMERAS_FILE="cameras.conf"
if [ ! -f "$CAMERAS_FILE" ]; then
    echo "Die Datei $CAMERAS_FILE wurde nicht gefunden!"
    exit 1
fi

while IFS='|' read -r CAM_NUM USERNAME PASSWORD IP_ADDRESS
do
    echo "Richte Kamera $CAM_NUM ein..."

    # Erstelle Verzeichnis für HLS-Stream
    mkdir -p /var/www/html/hls/cam$CAM_NUM
    chown -R www-data:www-data /var/www/html/hls/cam$CAM_NUM

    # Erstelle FFmpeg-Skript
    cat <<EOF > /home/pi/scripts/ffmpeg_cam$CAM_NUM.sh
#!/bin/bash
ffmpeg -i rtsp://$USERNAME:$PASSWORD@$IP_ADDRESS:554/stream1 -c:v copy -c:a copy -f hls -hls_time 2 -hls_list_size 5 -hls_flags delete_segments+append_list /var/www/html/hls/cam$CAM_NUM/stream.m3u8
EOF
    chmod +x /home/pi/scripts/ffmpeg_cam$CAM_NUM.sh

    # Erstelle Systemd-Dienst
    SERVICE_FILE="/etc/systemd/system/ffmpeg_cam$CAM_NUM.service"
    cp services/ffmpeg_cam.service.template $SERVICE_FILE
    sed -i "s/{{CAM_NUM}}/$CAM_NUM/g" $SERVICE_FILE
    sed -i "s#{{SCRIPT_PATH}}#/home/pi/scripts/ffmpeg_cam$CAM_NUM.sh#g" $SERVICE_FILE

    # Aktiviere und starte Dienst
    systemctl enable ffmpeg_cam$CAM_NUM.service
    systemctl start ffmpeg_cam$CAM_NUM.service

done < "$CAMERAS_FILE"

echo "Passe Website an..."
# Generiere dynamisch den HTML-Code basierend auf der Anzahl der Kameras
VIDEO_ELEMENTS=""
LOAD_SCRIPTS=""
while IFS='|' read -r CAM_NUM USERNAME PASSWORD IP_ADDRESS
do
    VIDEO_ELEMENTS+="    <!-- Kamera $CAM_NUM -->"$'\n'"    <video id=\"video$CAM_NUM\" controls autoplay muted></video>"$'\n'
    LOAD_SCRIPTS+="        loadStream('video$CAM_NUM', 'hls/cam$CAM_NUM/stream.m3u8');"$'\n'
done < "$CAMERAS_FILE"

# Aktualisiere index.html
INDEX_FILE="/var/www/html/index.html"

# Füge Video-Elemente ein
sed -i "/<!-- VIDEO ELEMENTS -->/r /dev/stdin" $INDEX_FILE <<< "$VIDEO_ELEMENTS"

# Füge JavaScript-Ladefunktionen ein
sed -i "/\/\/ LOAD STREAMS/a $LOAD_SCRIPTS" $INDEX_FILE

echo "Konfiguriere Autostart des Browsers..."
AUTOSTART_FILE="/home/pi/.config/lxsession/LXDE-pi/autostart"
mkdir -p $(dirname "$AUTOSTART_FILE")
if ! grep -Fxq "@/home/pi/scripts/start_browser.sh" "$AUTOSTART_FILE"
then
    echo "@/home/pi/scripts/start_browser.sh" >> "$AUTOSTART_FILE"
fi

echo "Aktiviere automatischen Login..."
raspi-config nonint do_boot_behaviour B4

echo "Installation abgeschlossen. Der Raspberry Pi wird neu gestartet..."
reboot
