#!/bin/sh
# Descubrimiento de hosts y puertos en CORP, desde KALI01 (Fase 10).
# Uso: sh recon.sh [rango]   (por defecto 172.16.0.0/24)

RANGE=${1:-172.16.0.0/24}

case "$RANGE" in
    172.16.*) ;;
    *)
        echo "Este script solo apunta a redes del lab (172.16.0.0/16)." >&2
        echo "Rango recibido: $RANGE — abortando." >&2
        exit 1
        ;;
esac

if ! command -v nmap >/dev/null 2>&1; then
    echo "nmap no está instalado (sudo apt install nmap)." >&2
    exit 1
fi

echo "== Descubrimiento de hosts activos en $RANGE =="
nmap -sn "$RANGE"

echo
echo "== Escaneo de puertos comunes por host (puede tardar) =="
nmap -sS -T4 --top-ports 100 "$RANGE" -oN recon-$(date +%Y%m%d-%H%M).txt

echo
echo "Resultado guardado en recon-*.txt. Comparar las IPs/puertos contra lo"
echo "esperado (DC01 172.16.0.10, WS01 172.16.0.1xx, FW01 172.16.0.1)."
