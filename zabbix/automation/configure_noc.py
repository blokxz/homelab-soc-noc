#!/usr/bin/env python3
"""Configura dependencias de triggers, ventana de mantenimiento, notificación,
auto-remediación y apertura de tickets en Zabbix para el NOC del homelab
(Fase 6 y Fase 11).

No usa el token de solo lectura `mcp-claude` de la Fase 5: hace falta un
usuario con rol Admin (o un token de ese usuario), porque crea objetos
(trigger.adddependencies, maintenance.create, mediatype.create, action.create).
Mantiene así la separación de la Fase 5: la IA sigue sin poder escribir en
Zabbix, y este script es un paso manual que corre una persona.

Uso:
    export ZABBIX_URL="http://192.168.1.39:8080"
    export ZABBIX_ADMIN_TOKEN="<token de un usuario Admin>"
    python3 configure_noc.py dependencies --dry-run      # revisar antes de aplicar
    python3 configure_noc.py dependencies                # aplicar
    python3 configure_noc.py maintenance --minutes 180   # abrir ventana antes de apagar el lab
    python3 configure_noc.py notify --telegram-token ... --telegram-chat-id ... --user Admin
    python3 configure_noc.py remediate --host WS01 --trigger-substr "Spooler" \\
        --command 'powershell -Command "Start-Service Spooler"' --dry-run   # Fase 11
    python3 configure_noc.py tickets --glpi-url http://IP-VM/apirest.php \\
        --glpi-app-token ... --dry-run                                      # Fase 11

Requisitos: Python 3.9+, `pip install requests`.
"""
import argparse
import json
import os
import sys
import time
import uuid

import requests

# Nombres de host tal como están dados de alta en Zabbix (ver README, tabla
# "Hosts monitoreados"). Ajustar si se usaron otros nombres.
HOST_FW01 = "FW01"
HOST_DC01 = "DC01"
HOST_WS01 = "WS01"
HOST_ZBXSRV = "Zabbix server"

# Fragmentos (no el texto completo) de la descripción de cada trigger relevante.
# Zabbix permite filtrar triggers por host; se busca por substring porque el
# texto completo varía un poco entre versiones de template.
TRIGGER_FW01_AGENT_DOWN = "agent is not available"
TRIGGER_NOCHECKS_SUBSTR = "checks are not available"
TRIGGER_NODATA_SUBSTR = "not available"
TRIGGER_MISSING_DATA_SUBSTR = "missing data"


def api_call(url, token, method, params):
    payload = {
        "jsonrpc": "2.0",
        "method": method,
        "params": params,
        "id": str(uuid.uuid4()),
    }
    headers = {"Content-Type": "application/json-rpc"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    resp = requests.post(url + "/api_jsonrpc.php", json=payload, headers=headers, timeout=15)
    resp.raise_for_status()
    body = resp.json()
    if "error" in body:
        raise RuntimeError(f"Zabbix API error en {method}: {body['error']}")
    return body["result"]


def get_host_id(url, token, name):
    hosts = api_call(url, token, "host.get", {"filter": {"host": [name]}, "output": ["hostid", "host"]})
    if not hosts:
        # Puede estar dado de alta con el "visible name" distinto del "host".
        hosts = api_call(url, token, "host.get", {"search": {"name": name}, "output": ["hostid", "host"]})
    if not hosts:
        raise RuntimeError(f"No se encontró el host '{name}' en Zabbix")
    return hosts[0]["hostid"]


def get_triggers(url, token, hostid):
    return api_call(
        url, token, "trigger.get",
        {"hostids": [hostid], "output": ["triggerid", "description"], "expandDescription": 1},
    )


def find_trigger(triggers, substr):
    for t in triggers:
        if substr.lower() in t["description"].lower():
            return t
    return None


def cmd_dependencies(args):
    url, token = args.url, args.token
    fw01 = get_host_id(url, token, HOST_FW01)
    dc01 = get_host_id(url, token, HOST_DC01)
    ws01 = get_host_id(url, token, HOST_WS01)
    zbxsrv = get_host_id(url, token, HOST_ZBXSRV)

    fw01_triggers = get_triggers(url, token, fw01)
    dc01_triggers = get_triggers(url, token, dc01)
    ws01_triggers = get_triggers(url, token, ws01)
    zbxsrv_triggers = get_triggers(url, token, zbxsrv)

    upstream = find_trigger(fw01_triggers, TRIGGER_FW01_AGENT_DOWN)
    if not upstream:
        print("No se encontró el trigger 'Zabbix agent is not available' en FW01.", file=sys.stderr)
        print("Triggers disponibles en FW01:", [t["description"] for t in fw01_triggers], file=sys.stderr)
        sys.exit(1)

    downstream = []
    for host_label, triggers in (("DC01", dc01_triggers), ("WS01", ws01_triggers)):
        for substr in (TRIGGER_NOCHECKS_SUBSTR, TRIGGER_NODATA_SUBSTR):
            t = find_trigger(triggers, substr)
            if t and t["triggerid"] != upstream["triggerid"]:
                downstream.append((host_label, t))

    missing_data = find_trigger(zbxsrv_triggers, TRIGGER_MISSING_DATA_SUBSTR)

    print(f"Trigger raíz (FW01): {upstream['description']} [{upstream['triggerid']}]")
    seen = set()
    deps = []
    for host_label, t in downstream:
        if t["triggerid"] in seen:
            continue
        seen.add(t["triggerid"])
        print(f"  depende de la raíz <- {host_label}: {t['description']} [{t['triggerid']}]")
        deps.append({"triggerid": t["triggerid"], "dependsOnTriggerid": upstream["triggerid"]})

    if missing_data:
        print(f"  depende de la raíz <- Zabbix server: {missing_data['description']} [{missing_data['triggerid']}]")
        deps.append({"triggerid": missing_data["triggerid"], "dependsOnTriggerid": upstream["triggerid"]})
        for host_label, t in downstream:
            deps.append({"triggerid": missing_data["triggerid"], "dependsOnTriggerid": t["triggerid"]})

    if args.dry_run:
        print("\n--dry-run: no se aplicó nada. Payload de trigger.adddependencies por trigger:")
        print(json.dumps(deps, indent=2))
        return

    # trigger.adddependencies pide un dependencyid por trigger (puede agrupar
    # las dependencias de un mismo trigger en un solo llamado).
    by_trigger = {}
    for d in deps:
        by_trigger.setdefault(d["triggerid"], []).append({"dependsOnTriggerid": d["dependsOnTriggerid"]})
    for triggerid, dependencies in by_trigger.items():
        api_call(url, token, "trigger.adddependencies", {"triggerid": triggerid, "dependsOnTriggerid": [d["dependsOnTriggerid"] for d in dependencies]})
    print(f"\nListo: {len(by_trigger)} trigger(s) actualizados con dependencias.")


def cmd_maintenance(args):
    url, token = args.url, args.token
    hostids = [get_host_id(url, token, h) for h in (HOST_FW01, HOST_DC01, HOST_WS01)]
    now = int(time.time())
    end = now + args.minutes * 60
    params = {
        "name": f"Apagado planificado del lab ({time.strftime('%Y-%m-%d %H:%M')})",
        "active_since": now,
        "active_till": end,
        "hostids": hostids,
        "tags_evaltype": 0,
        "timeperiods": [
            {
                "timeperiod_type": 0,  # una sola vez
                "start_date": now,
                "period": args.minutes * 60,
            }
        ],
        # 0 = sin recolectar datos durante la ventana (evita "nodata" después).
        "maintenance_type": 0,
    }
    if args.dry_run:
        print("--dry-run: payload de maintenance.create:")
        print(json.dumps(params, indent=2))
        return
    result = api_call(url, token, "maintenance.create", params)
    print(f"Ventana de mantenimiento creada: {result}")
    print(f"Dura {args.minutes} min desde ahora. Correr esto como paso 0, antes de apagar FW01/DC01/WS01.")


def cmd_notify(args):
    url, token = args.url, args.token
    mediatype_params = {
        "name": "Telegram - Lab NOC",
        "type": 4,  # webhook
        "script": TELEGRAM_WEBHOOK_SCRIPT,
        "parameters": [
            {"name": "bot_token", "value": args.telegram_token},
            {"name": "chat_id", "value": args.telegram_chat_id},
            {"name": "alert_subject", "value": "{ALERT.SUBJECT}"},
            {"name": "alert_message", "value": "{ALERT.MESSAGE}"},
        ],
        "process_tags": 1,
        "message_templates": [
            {
                "eventsource": 0,  # trigger
                "recovery": 0,  # problema
                "subject": "PROBLEMA: {EVENT.NAME}",
                "message": "{EVENT.SEVERITY}: {EVENT.NAME}\nHost: {HOST.NAME}\nHora: {EVENT.TIME} {EVENT.DATE}",
            },
            {
                "eventsource": 0,
                "recovery": 1,  # resuelto
                "subject": "RESUELTO: {EVENT.NAME}",
                "message": "Resuelto en {HOST.NAME} a las {EVENT.RECOVERY.TIME}",
            },
        ],
    }
    if args.dry_run:
        print("--dry-run: payload de mediatype.create:")
        print(json.dumps(mediatype_params, indent=2))
    else:
        mediatype = api_call(url, token, "mediatype.create", mediatype_params)
        mediatypeid = mediatype["mediatypeids"][0]
        print(f"Media type creado: {mediatypeid}")

        users = api_call(url, token, "user.get", {"filter": {"username": [args.user]}, "output": ["userid"]})
        if not users:
            raise RuntimeError(f"No se encontró el usuario Zabbix '{args.user}'")
        userid = users[0]["userid"]
        api_call(url, token, "user.update", {
            "userid": userid,
            "medias": [{
                "mediatypeid": mediatypeid,
                "sendto": [args.telegram_chat_id],
                "active": 0,
                "severity": 60,  # Average, High y Disaster (bits 2+3+4)
                "period": "1-7,00:00-24:00",
            }],
        })
        print(f"Medio de notificación asociado al usuario '{args.user}'.")

    action_params = {
        "name": "Notificar fallas criticas del NOC",
        "eventsource": 0,
        "status": 0,
        "esc_period": "1h",
        "pause_suppressed": 1,  # respeta las ventanas de mantenimiento
        "notify_if_canceled": 1,
        "conditions": [
            {"conditiontype": 4, "operator": 5, "value": "3"},  # severity >= High (3)
        ],
        "operations": [
            {
                "operationtype": 0,  # enviar mensaje
                "esc_step_from": 1,
                "esc_step_to": 1,
                "evaltype": 0,
                "opmessage": {"default_msg": 1, "mediatypeid": "0"},
                "opmessage_grp": [],
                "opmessage_usr": [{"userid": "<completar con user.get>"}],
            }
        ],
    }
    if args.dry_run:
        print("\n--dry-run: payload de action.create (completar userid antes de aplicar):")
        print(json.dumps(action_params, indent=2))
        return
    print("\nPara crear la Action, completar opmessage_usr.userid con el id de "
          f"'{args.user}' y correr action.create manualmente (o editar este script "
          "y volver a ejecutar con --execute-action una vez verificado el media type).")


TELEGRAM_WEBHOOK_SCRIPT = """
// Mismo script que trae el media type "Telegram" por defecto de Zabbix >= 5.0.
// Se referencia aquí en vez de copiarlo para no desincronizarse: al crear el
// media type a mano en la GUI (Alerts -> Media types -> Telegram), exportarlo
// y pegar su "script" acá, o dejar que mediatype.create falle y crear el
// media type desde el template integrado y solo correr `notify --dry-run`
// para ver los parámetros a copiar.
return 'ver Alerts -> Media types -> Telegram en la GUI de Zabbix';
""".strip()


def cmd_remediate(args):
    """Fase 11: auto-remediación. Crea una action que, cuando dispara un
    trigger puntual en un host puntual, corre un comando remoto en ese mismo
    host en vez de (o antes de) avisar a una persona.

    OJO — esto es código ejecutándose solo, sin que nadie lo apruebe en el
    momento. Antes de usarlo:
      1. El agente del host de destino necesita `EnableRemoteCommands=1` en
         su configuración (zabbix_agent2.conf / zabbix_agentd.conf). Viene
         en 0 por defecto a propósito: habilitarlo le da a quien controle el
         servidor Zabbix ejecución de comandos en ese host. Es la misma
         lógica de defensa en profundidad de la Fase 5, pero al revés: ahí
         se restringía qué puede hacer la IA; acá hay que restringir qué
         puede hacer Zabbix.
      2. Usar esto solo para fallas idempotentes y de bajo riesgo (reiniciar
         un servicio que ya sabés que es seguro reiniciar), nunca para
         apagar/reiniciar un host entero ni para producción fuera del lab.
      3. `esc_period`/`esc_step_to` dejan el remote command en el paso 1
         nada más: si el servicio vuelve a estar caído después de
         intentarlo una vez, pasa al paso 2 (notificar a una persona) en vez
         de reintentar en bucle.
    """
    url, token = args.url, args.token
    hostid = get_host_id(url, token, args.host)
    triggers = get_triggers(url, token, hostid)
    trigger = find_trigger(triggers, args.trigger_substr)
    if not trigger:
        print(f"No se encontró un trigger en {args.host} que contenga '{args.trigger_substr}'.", file=sys.stderr)
        print("Triggers disponibles:", [t["description"] for t in triggers], file=sys.stderr)
        sys.exit(1)

    action_params = {
        "name": f"Auto-remediar: {args.host} - {trigger['description']}",
        "eventsource": 0,
        "status": 0,
        "esc_period": "5m",
        "pause_suppressed": 1,  # no reintentar durante una ventana de mantenimiento
        "notify_if_canceled": 1,
        "conditions": [
            {"conditiontype": 16, "operator": 0, "value": hostid},  # host puntual
        ],
        "operations": [
            {
                "operationtype": 1,  # comando remoto
                "esc_step_from": 1,
                "esc_step_to": 1,  # un solo intento, nunca reintenta en bucle
                "evaltype": 0,
                "opcommand": {
                    "type": 0,  # custom script, vía el agente del propio host
                    "command": args.command,
                },
                "opcommand_hst": [{"hostid": hostid}],
            },
            {
                # si sigue fallando después del paso 1, recién ahí se avisa
                "operationtype": 0,
                "esc_step_from": 2,
                "esc_step_to": 2,
                "evaltype": 0,
                "opmessage": {"default_msg": 1, "mediatypeid": "0"},
                "opmessage_grp": [],
                "opmessage_usr": [{"userid": "<completar con user.get, igual que en notify>"}],
            },
        ],
    }

    print(f"Trigger objetivo: {trigger['description']} [{trigger['triggerid']}] en {args.host}")
    print(f"Comando a ejecutar en el host cuando dispare: {args.command}")
    if args.dry_run:
        print("\n--dry-run: payload de action.create (completar userid del paso 2 antes de aplicar):")
        print(json.dumps(action_params, indent=2))
        return

    print("\nEl paso 2 (notificación de respaldo) necesita el userid de un usuario real.")
    print("Completarlo a mano y correr action.create, o usar notify primero para tener el media type/userid.")


def cmd_tickets(args):
    """Fase 11: integra Zabbix con GLPI (ver tickets/README.md) para que un
    problema de severidad alta abra un ticket solo, en vez de depender de
    que alguien lo cree a mano.

    Necesita un API token de GLPI ya generado (Configuración -> General ->
    API, crear un "API client" con "App token" habilitado, y un usuario con
    un "Personal token" propio). GLPI documenta esto en su propia consola;
    no se puede automatizar desde este script porque GLPI todavía no tiene
    nada desplegado en el momento de correr esto.
    """
    url, token = args.url, args.token

    mediatype_params = {
        "name": "GLPI - Lab NOC",
        "type": 4,  # webhook
        "script": GLPI_WEBHOOK_SCRIPT,
        "parameters": [
            {"name": "glpi_url", "value": args.glpi_url},
            {"name": "glpi_app_token", "value": args.glpi_app_token},
            {"name": "glpi_user_token", "value": args.glpi_user_token},
            {"name": "event_name", "value": "{EVENT.NAME}"},
            {"name": "event_host", "value": "{HOST.NAME}"},
            {"name": "event_severity", "value": "{EVENT.SEVERITY}"},
        ],
        "process_tags": 1,
    }

    if args.dry_run:
        print("--dry-run: payload de mediatype.create:")
        print(json.dumps(mediatype_params, indent=2))
        print("\n--dry-run: después de crear el media type, asociarlo a un usuario (ver 'notify')")
        print("y crear una action con condición de severidad, igual que la de Telegram.")
        return

    mediatype = api_call(url, token, "mediatype.create", mediatype_params)
    print(f"Media type de GLPI creado: {mediatype['mediatypeids'][0]}")
    print("Asociarlo a un usuario y crear la action de severidad alta (ver 'notify' como referencia).")


GLPI_WEBHOOK_SCRIPT = """
// Crea un ticket en GLPI vía su API REST cuando se dispara este media type.
// Parámetros esperados (definidos en mediatype.create): glpi_url,
// glpi_app_token, glpi_user_token, event_name, event_host, event_severity.
//
// No probado contra una instancia real de GLPI: antes de confiar en esto,
// correrlo una vez desde Zabbix (Alerts -> Media types -> Test) y revisar
// la respuesta. GLPI puede rechazar la sesión si el Personal Token expiró.
try {
    var params = JSON.parse(value),
        initResp = JSON.parse(HttpRequest.get(
            params.glpi_url + '/initSession',
            'Authorization: user_token ' + params.glpi_user_token + '\\r\\nApp-Token: ' + params.glpi_app_token
        )),
        sessionToken = initResp.session_token,
        req = new HttpRequest();

    req.addHeader('Content-Type: application/json');
    req.addHeader('Session-Token: ' + sessionToken);
    req.addHeader('App-Token: ' + params.glpi_app_token);

    var body = JSON.stringify({
        input: {
            name: '[' + params.event_severity + '] ' + params.event_name,
            content: 'Host: ' + params.event_host + '\\nAbierto automaticamente por Zabbix.',
            urgency: 3
        }
    });

    var resp = req.post(params.glpi_url + '/Ticket', body);
    return 'OK: ' + resp;
} catch (error) {
    Zabbix.log(4, '[GLPI webhook] ' + error);
    throw 'GLPI webhook failed: ' + error;
}
""".strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", default=os.environ.get("ZABBIX_URL"), help="URL base de Zabbix (sin /api_jsonrpc.php)")
    parser.add_argument("--token", default=os.environ.get("ZABBIX_ADMIN_TOKEN"), help="Token de un usuario Admin")
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_dep = sub.add_parser("dependencies", help="Crear dependencias de triggers (FW01 como raíz)")
    p_dep.add_argument("--dry-run", action="store_true")
    p_dep.set_defaults(func=cmd_dependencies)

    p_maint = sub.add_parser("maintenance", help="Abrir una ventana de mantenimiento puntual")
    p_maint.add_argument("--minutes", type=int, default=180)
    p_maint.add_argument("--dry-run", action="store_true")
    p_maint.set_defaults(func=cmd_maintenance)

    p_notify = sub.add_parser("notify", help="Crear media type de Telegram y la action de severidad alta")
    p_notify.add_argument("--telegram-token", required=True)
    p_notify.add_argument("--telegram-chat-id", required=True)
    p_notify.add_argument("--user", default="Admin", help="Usuario Zabbix que recibe la notificación")
    p_notify.add_argument("--dry-run", action="store_true")
    p_notify.set_defaults(func=cmd_notify)

    p_remediate = sub.add_parser("remediate", help="Fase 11: auto-remediación (comando remoto al disparar un trigger)")
    p_remediate.add_argument("--host", required=True, help="Host de Zabbix, ej. WS01")
    p_remediate.add_argument("--trigger-substr", required=True, help="Substring del trigger a atender")
    p_remediate.add_argument("--command", required=True, help='Comando a correr en el host, ej. "powershell -Command \\"Start-Service Spooler\\""')
    p_remediate.add_argument("--dry-run", action="store_true")
    p_remediate.set_defaults(func=cmd_remediate)

    p_tickets = sub.add_parser("tickets", help="Fase 11: media type que abre un ticket en GLPI")
    p_tickets.add_argument("--glpi-url", required=True, help="Ej. http://IP-VM/apirest.php")
    p_tickets.add_argument("--glpi-app-token", required=True)
    p_tickets.add_argument("--glpi-user-token", required=True)
    p_tickets.add_argument("--dry-run", action="store_true")
    p_tickets.set_defaults(func=cmd_tickets)

    args = parser.parse_args()
    if not args.url or not args.token:
        parser.error("Falta ZABBIX_URL/--url o ZABBIX_ADMIN_TOKEN/--token")
    args.url = args.url.rstrip("/")
    args.func(args)


if __name__ == "__main__":
    main()
