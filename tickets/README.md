# GLPI (gestión de tickets) — Fase 11

Reemplaza el *acknowledge* manual en Zabbix (Fase 4) por un ticket real, con
asignación y seguimiento, para los problemas que lo justifican (severidad
alta). Corre en la misma VM Linux que Wazuh, no en la netbook — ver la nota
al principio de [`docker-compose.yml`](docker-compose.yml).

## Primer arranque

```bash
cp .env.example .env && nano .env
docker compose up -d
docker compose ps        # glpi puede tardar 1-2 min en el primer boot
```

Acceso: `http://IP-VM:8090`. Usuario/clave inicial `glpi`/`glpi` — el
instalador integrado de la imagen pide elegir el idioma y corre las
migraciones de base solo. Cambiar la clave en el primer login.

## Generar los tokens de API (para que Zabbix pueda abrir tickets)

GLPI no expone su API por defecto. Antes de correr
`zabbix/automation/configure_noc.py tickets`:

1. *Setup* → *General* → pestaña *API* → activar *Enable Rest API*.
2. En esa misma pestaña, *Add API client* → generar un **App token**.
3. *Administration* → *Users* → el usuario que va a crear los tickets →
   pestaña *Settings* → generar un **Personal token** (este es el
   `glpi-user-token` del script).
4. Confirmar que ese usuario tiene permiso para crear tickets en el
   *Entity* que corresponda (por defecto alcanza con el entity raíz).

```bash
python3 ../zabbix/automation/configure_noc.py tickets \
    --glpi-url http://IP-VM:8090/apirest.php \
    --glpi-app-token <el App token> \
    --glpi-user-token <el Personal token> \
    --dry-run
```

El media type que crea es un *webhook* de Zabbix: llama a `initSession` de
GLPI con esos dos tokens y abre el ticket con `POST /Ticket`. No se pudo
probar contra una instancia real de GLPI — antes de confiar en él, correr
el media type una vez desde *Alerts → Media types → GLPI - Lab NOC → Test*
en la GUI de Zabbix y revisar la respuesta.

## Qué no hace esto

No cierra el ticket solo cuando el problema se resuelve en Zabbix (eso
necesitaría un segundo webhook en la recuperación del evento, apuntando a
`PUT /Ticket/<id>` con el estado "Resuelto" — no está armado todavía,
porque primero hay que confirmar que la apertura funciona). Tampoco asigna
el ticket a una persona: queda en la cola general hasta que alguien lo
toma, como correspondería en una mesa de ayuda real antes de automatizar la
asignación.
