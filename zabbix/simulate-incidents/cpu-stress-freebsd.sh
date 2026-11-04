#!/bin/sh
# Genera carga de CPU en FW01 (OPNsense/FreeBSD) para probar el item calculado
# cpu.util.total y el trigger asociado (Fase 6).
#
# Correr desde la shell de OPNsense (Diagnostics -> Backup... no; usar el
# acceso por consola/SSH, opción 8 "Shell" del menú de consola).
#
# Uso: sh cpu-stress-freebsd.sh [minutos] [hilos]

MINUTES=${1:-5}
THREADS=${2:-$(sysctl -n hw.ncpu)}
SECONDS=$((MINUTES * 60))

echo "Generando carga en $THREADS hilo(s) durante $MINUTES minuto(s)..."

pids=""
i=0
while [ "$i" -lt "$THREADS" ]; do
    # yes a /dev/null es liviano de escribir y pesado de generar: satura un
    # núcleo sin tocar disco ni red.
    yes > /dev/null &
    pids="$pids $!"
    i=$((i + 1))
done

trap 'kill $pids 2>/dev/null' EXIT INT TERM
sleep "$SECONDS"
kill $pids 2>/dev/null

echo "Carga terminada. Verificar en Zabbix el item calculado cpu.util.total de FW01."
