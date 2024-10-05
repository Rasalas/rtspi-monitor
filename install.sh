#!/bin/bash

# Überprüfen, ob das Skript mit Root-Rechten ausgeführt wird
if [ "$EUID" -ne 0 ]; then
    echo "Bitte führen Sie das Skript mit sudo aus: sudo ./install.sh"
    exit
fi

# Ermitteln des aktuellen Benutzernamens und Home-Verzeichnisses
USERNAME=$(logname)
HOME_DIR="/home/$USERNAME"

# Ermitteln des Skript-Verzeichnisses
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "System wird aktualisiert..."
apt update && apt upgrade -y

echo "Installiere benötigte Pakete..."
apt install -y ffmpeg nginx chromium-browser

echo "Erstelle Verzeichnisse..."
mkdir -p /var/www/html/hls
mkdir -p "$HOME_DIR/scripts"
mkdir -p "$HOME_DIR/services"

echo "Kopiere Skripte und Website..."
cp -r "$SCRIPT_DIR/scripts/"* "$HOME_DIR/scripts/"
cp -r "$SCRIPT_DIR/website/"* /var/www/html/
chown -R "$USERNAME:$USERNAME" "$HOME_DIR/scripts"
chown -R www-data:www-data /var/www/html

echo "Lese Kamerakonfigurationen..."
CAMERAS_FILE="$SCRIPT_DIR/cameras.conf"
if [ ! -f "$CAMERAS_FILE" ]; then
    echo "Die Datei $CAMERAS_FILE wurde nicht gefunden!"
    exit 1
fi

while IFS='|' read -r CAM_NUM USERNAME_CAM PASSWORD IP_ADDRESS
do
    # Überspringe leere Zeilen oder Zeilen, die mit '#' beginnen
    if [[ -z "$CAM_NUM" ]] || [[ "$CAM_NUM" =~ ^\s*# ]]; then
        continue
    fi

    echo "Richte Kamera $CAM_NUM ein..."

    # Erstelle Verzeichnis für HLS-Stream
    mkdir -p /var/www/html/hls/cam$CAM_NUM
    chown -R www-data:www-data /var/www/html/hls/cam$CAM_NUM

    # Erstelle FFmpeg-Skript
    cat <<EOF > "$HOME_DIR/scripts/ffmpeg_cam$CAM_NUM.sh"
#!/bin/bash
ffmpeg -i rtsp://$USERNAME_CAM:$PASSWORD@$IP_ADDRESS:554/stream1 -c:v copy -c:a copy -f hls -hls_time 2 -hls_list_size 5 -hls_flags delete_segments+append_list /var/www/html/hls/cam$CAM_NUM/stream.m3u8
EOF
    chmod +x "$HOME_DIR/scripts/ffmpeg_cam$CAM_NUM.sh"

    # Erstelle Systemd-Dienst
    SERVICE_FILE="/etc/systemd/system/ffmpeg_cam$CAM_NUM.service"
    cp "$SCRIPT_DIR/services/ffmpeg_cam.service.template" $SERVICE_FILE
    sed -i "s/{{CAM_NUM}}/$CAM_NUM/g" $SERVICE_FILE
    sed -i "s#{{SCRIPT_PATH}}#$HOME_DIR/scripts/ffmpeg_cam$CAM_NUM.sh#g" $SERVICE_FILE
    sed -i "s/{{USERNAME}}/$USERNAME/g" $SERVICE_FILE

    # Aktiviere und starte Dienst
    systemctl daemon-reload
    systemctl enable ffmpeg_cam$CAM_NUM.service
    systemctl start ffmpeg_cam$CAM_NUM.service

done < "$CAMERAS_FILE"

echo "Passe Website an..."
# Generiere dynamisch den HTML-Code basierend auf der Anzahl der Kameras
VIDEO_ELEMENTS=""
LOAD_SCRIPTS=""
while IFS='|' read -r CAM_NUM USERNAME_CAM PASSWORD IP_ADDRESS
do
    # Überspringe leere Zeilen oder Zeilen, die mit '#' beginnen
    if [[ -z "$CAM_NUM" ]] || [[ "$CAM_NUM" =~ ^\s*# ]]; then
        continue
    fi

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
AUTOSTART_FILE="$HOME_DIR/.config/lxsession/LXDE-pi/autostart"
mkdir -p "$(dirname "$AUTOSTART_FILE")"
if ! grep -Fxq "@$HOME_DIR/scripts/start_browser.sh" "$AUTOSTART_FILE"
then
    echo "@$HOME_DIR/scripts/start_browser.sh" >> "$AUTOSTART_FILE"
fi

echo "Aktiviere automatischen Login..."
raspi-config nonint do_boot_behaviour B4

echo "Installation abgeschlossen. Der Raspberry Pi wird neu gestartet..."
reboot
