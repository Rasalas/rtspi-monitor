# RTSPi Monitor

Dieses Projekt richtet einen Raspberry Pi ein, um RTSP-Streams von Tapo-Kameras in HLS umzuwandeln und auf einer lokalen Website anzuzeigen. Die Website öffnet sich automatisch beim Start im Vollbildmodus.

## Installation

1. Klone die Repository auf deinen Raspberry Pi:

```bash
git clone https://github.com/Rasalas/rtspi-monitor.git
```

2. Wechsele in das Verzeichnis:

```bash
cd rtspi-monitor
```

3. Dupliziere die `cameras.example.conf` und entferne das `.example` aus dem Dateinamen:

```bash
cp cameras.example.conf cameras.conf
```

4. Führe das Installationsskript aus:

```bash
sudo ./install.sh
```


