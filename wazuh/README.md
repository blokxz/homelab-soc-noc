# Wazuh 4.9 (SOC) — Fase 9

Corre en una VM Linux dedicada en el host de VMware (no en la netbook: ver la
nota al principio de [`docker-compose.yml`](docker-compose.yml) y el problema
#10 del README principal). Pila: OpenSearch (indexer), wazuh-manager y el
dashboard, los tres oficiales de [wazuh-docker](https://github.com/wazuh/wazuh-docker).

## Primer arranque

```bash
sudo sysctl -w vm.max_map_count=262144
echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf

cp .env.example .env && nano .env     # tres contraseñas propias

docker compose -f generate-certs.yml run --rm generator
docker compose up -d
docker compose ps                     # wazuh.indexer, wazuh.manager, wazuh.dashboard
```

Dashboard: `https://IP-VM:443` (usuario `admin`, la contraseña de `.env`).

Para borrar todo: `docker compose down -v && sudo rm -rf data config/certs`.

## Agentes

DC01 y WS01 ya reportan a Zabbix con el agente activo; agregarles el agente
de Wazuh es una instalación aparte (no reemplaza a Zabbix: métricas y
seguridad quedan separadas, ver Decisiones de diseño del README principal).

1. Dashboard de Wazuh → *Agents* → *Deploy new agent* → copiar el comando MSI
   que genera (apunta a `wazuh.manager` por su IP en la red `corp`... **ojo**:
   DC01/WS01 están detrás del NAT de FW01, igual que con Zabbix. Opciones:
   - Exponer 1514/1515/TCP de la VM de Wazuh en la red de casa y que FW01
     haga NAT hacia ella desde CORP (regla simétrica a la de Zabbix 10051).
   - O correr la VM de Wazuh directamente en la red `corp` de VMware
     (recomendado): así los agentes la alcanzan sin pasar por NAT, igual que
     DC01 y WS01 entre sí.
2. Tras instalar el agente, cargar la configuración de Sysmon (ver abajo)
   *antes* de instalar Sysmon, para que las reglas de decodificación del
   manager ya estén esperando esos eventos.

### Sysmon en DC01 y WS01

```powershell
# Descargar Sysmon de Microsoft (sysinternals.com) a cada VM, luego:
.\Sysmon64.exe -accepteula -i sysmonconfig.xml
```

[`sysmon/sysmonconfig.xml`](sysmon/sysmonconfig.xml) es una base acotada:
creación de procesos, conexiones de red, cambios de registro sensibles,
creación remota de hilos y carga de drivers — los eventos que después arman
las reglas de fuerza bruta/escalado de la Fase 10. Para un detalle mucho más
fino (y más ruido), reemplazarla por la de la comunidad:
[SwiftOnSecurity/sysmon-config](https://github.com/SwiftOnSecurity/sysmon-config)
u [Olaf Hartong/sysmon-modular](https://github.com/olafhartong/sysmon-modular).

El manager de Wazuh ya trae decodificadores de Sysmon; no hace falta
configuración adicional del lado del manager para empezar a verlos en
*Threat hunting*.

### Syslog de FW01 (OPNsense)

OPNsense → *System* → *Settings* → *Logging / targets* → agregar un target
Syslog apuntando a la IP de la VM de Wazuh, puerto 514/UDP, con los logs del
firewall y, si está instalado, Suricata. El manager de Wazuh ya escucha en
514/UDP (puerto publicado en `docker-compose.yml`).

## Qué falta validar en el hardware real

Este `docker-compose.yml` y los archivos de configuración no se probaron
contra una instalación real (no hay acceso a las VMs del lab desde esta
sesión). Antes de confiar en él:

- Confirmar los tags de imagen vigentes en el [release de wazuh-docker](https://github.com/wazuh/wazuh-docker/releases)
  (4.9.2 es el que se documenta acá, pero puede haber una versión más nueva).
- `docker-compose.yml` monta cada certificado como archivo individual desde
  `./config/certs/<nodo>/<nodo>.pem` y `<nodo>-key.pem`, más `root-ca.pem` en
  la raíz, que es como `wazuh-certs-generator:0.0.2` los deja hoy. Si una
  versión más nueva del generador cambia esos nombres o esa estructura de
  carpetas, ajustar las rutas antes de levantar los contenedores.
- La configuración corre con los valores por defecto de cada imagen: no hay
  `opensearch.yml`, `ossec.conf` ni `opensearch_dashboards.yml` propios
  todavía. Para endurecerla, copiar las plantillas de referencia del repo
  `wazuh-docker` (`single-node/config/`) como base y agregar los `volumes`
  correspondientes.
