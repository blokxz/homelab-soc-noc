#!/bin/sh
# Descarga la configuración actual de FW01 (OPNsense) vía su API REST y la
# guarda versionada en config-snapshots/ (Fase 11, IaC).
#
# OPNsense no tiene un modelo declarativo completo como Terraform: lo que
# hay acá es el patrón más simple y confiable que soporta de forma nativa,
# "versionar el config.xml exportado", que cumple el mismo objetivo que
# pide la Fase 11 (poder ver qué cambió y volver atrás) sin depender de
# ningún proveedor de terceros.
#
# Requisitos:
#   - Una API key/secret de FW01: System -> Access -> Users -> el usuario ->
#     "API keys" -> Add. Las credenciales dan los mismos permisos que ese
#     usuario tiene en la GUI, así que crear un usuario dedicado de solo
#     lectura para backups en vez de usar las de administración.
#   - curl, jq.
#
# Uso: OPNSENSE_KEY=... OPNSENSE_SECRET=... sh backup-config.sh [IP-FW01]

FW01=${1:-192.168.1.59}
OUT_DIR="$(dirname "$0")/config-snapshots"
STAMP=$(date +%Y%m%d-%H%M%S)
OUT_RAW="$OUT_DIR/config-$STAMP.raw.xml"
OUT_CLEAN="$OUT_DIR/config-$STAMP.xml"

if [ -z "$OPNSENSE_KEY" ] || [ -z "$OPNSENSE_SECRET" ]; then
    echo "Definir OPNSENSE_KEY y OPNSENSE_SECRET (API key/secret de un usuario de solo lectura)." >&2
    exit 1
fi

mkdir -p "$OUT_DIR"

echo "Descargando config.xml de https://$FW01/api/core/backup/download/this ..."
curl -sk -u "$OPNSENSE_KEY:$OPNSENSE_SECRET" \
    "https://$FW01/api/core/backup/download/this" -o "$OUT_RAW"

if ! grep -q "<opnsense>" "$OUT_RAW"; then
    echo "La respuesta no parece un config.xml válido. Revisar credenciales/IP." >&2
    echo "Contenido recibido:" >&2
    head -c 500 "$OUT_RAW" >&2
    rm -f "$OUT_RAW"
    exit 1
fi

# Sanitizar antes de versionar: nunca comitear contraseñas, hashes ni
# certificados/claves privadas, aunque estén en la propia VM de FW01.
sed -E \
    -e 's#(<password>).*(</password>)#\1[REDACTED]\2#g' \
    -e 's#(<bcrypt-hash>).*(</bcrypt-hash>)#\1[REDACTED]\2#g' \
    -e 's#(<crypto_password>).*(</crypto_password>)#\1[REDACTED]\2#g' \
    "$OUT_RAW" > "$OUT_CLEAN"

# Las claves privadas vienen como bloques PEM de varias líneas: borrarlas
# aparte, porque el sed de arriba es línea por línea.
python3 - "$OUT_CLEAN" <<'PYEOF'
import re, sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
text = re.sub(
    r"-----BEGIN (RSA )?PRIVATE KEY-----.*?-----END (RSA )?PRIVATE KEY-----",
    "[REDACTED PRIVATE KEY]",
    text,
    flags=re.DOTALL,
)
open(path, "w", encoding="utf-8").write(text)
PYEOF

rm -f "$OUT_RAW"
echo "Guardado (sanitizado): $OUT_CLEAN"
echo "Revisar el diff contra el snapshot anterior antes de comitear:"
echo "  git diff --no-index \$(ls -t $OUT_DIR/*.xml | sed -n 2p) $OUT_CLEAN"
