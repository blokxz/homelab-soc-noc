#!/bin/sh
# Restaura FW01 (OPNsense) a partir de un snapshot guardado por
# backup-config.sh (Fase 11, IaC).
#
# DESTRUCTIVO: reemplaza toda la configuración de FW01 por la del snapshot.
# OPNsense reinicia los servicios afectados (y puede cortar la sesión web)
# al restaurar. Pensado para volver atrás un cambio que salió mal, no para
# uso rutinario.
#
# El snapshot sanitizado (sin contraseñas/claves, ver backup-config.sh) NO
# SE PUEDE restaurar tal cual: OPNsense pisaría las credenciales reales por
# los placeholders [REDACTED]. Este script avisa y aborta si detecta esos
# placeholders, en vez de dejar el firewall sin usuarios funcionales.
#
# Uso: OPNSENSE_KEY=... OPNSENSE_SECRET=... sh restore-config.sh <snapshot.xml> [IP-FW01]

SNAPSHOT=$1
FW01=${2:-192.168.1.59}

if [ -z "$SNAPSHOT" ] || [ ! -f "$SNAPSHOT" ]; then
    echo "Uso: sh restore-config.sh <snapshot.xml> [IP-FW01]" >&2
    exit 1
fi

if [ -z "$OPNSENSE_KEY" ] || [ -z "$OPNSENSE_SECRET" ]; then
    echo "Definir OPNSENSE_KEY y OPNSENSE_SECRET (necesita un usuario con permiso de escritura, no el de solo lectura de los backups)." >&2
    exit 1
fi

if grep -q "REDACTED" "$SNAPSHOT"; then
    echo "Este snapshot está sanitizado (tiene [REDACTED]): restaurarlo deja" >&2
    echo "contraseñas/claves rotas. Usar un snapshot sin sanitizar, guardado" >&2
    echo "fuera del repo, o restaurar a mano desde la GUI y reponer los" >&2
    echo "secretos después." >&2
    exit 1
fi

echo "Esto va a REEMPLAZAR toda la configuración de FW01 ($FW01) por $SNAPSHOT."
printf "Escribir 'si' para confirmar: "
read -r CONFIRM
if [ "$CONFIRM" != "si" ]; then
    echo "Cancelado."
    exit 1
fi

curl -sk -u "$OPNSENSE_KEY:$OPNSENSE_SECRET" \
    -X POST "https://$FW01/api/core/backup/restore" \
    -F "conffile=@$SNAPSHOT"

echo
echo "Restauración enviada. OPNsense puede reiniciar servicios o cortar esta"
echo "sesión; verificar por consola si la WAN/LAN quedaron como se esperaba."
