# Red ATTACK: simulaciones y detección (Fase 10)

Scripts para correr **desde KALI01**, contra la red CORP (`172.16.0.0/24`),
dentro del lab propio. No apuntan a nada fuera de `172.16.0.0/24` /
`172.16.66.0/24` y no tocan la red de casa (`192.168.1.0/24`): la regla de
firewall "ATTACK → 192.168.0.0/16: Bloquear" del README principal debe estar
aplicada antes de correr cualquiera de estos scripts.

Cada script imprime lo que hace antes de hacerlo y no corre nada sin que el
operador lo invoque a propósito; ninguno es automático ni se dispara solo.

## Requisitos

- KALI01 encendida y con `172.16.66.10` en la red `attack`.
- Las reglas de FW01 que permiten `ATTACK -> CORP` aplicadas (ver README
  principal, tabla "Política de firewall").
- DC01 y WS01 con Sysmon y el agente de Wazuh instalados (Fase 9) para que
  haya algo que detectar.
- Un usuario de prueba en AD para el escenario de fuerza bruta (no usar una
  cuenta real del dominio): ver `scripts/ad-bulk/` (Fase 7) para crear uno.

## Escenarios

| Script | Qué simula | Qué debería detectar Wazuh |
|---|---|---|
| [`recon.sh`](recon.sh) | Descubrimiento de hosts y puertos en CORP (`nmap`) | Picos de conexiones nuevas desde una sola IP de ATTACK; no hay regla nativa, es la base para correlacionar con los siguientes pasos |
| [`bruteforce-rdp.sh`](bruteforce-rdp.sh) | Fuerza bruta de RDP contra WS01 con `hydra` y una wordlist chica | Múltiples 4625 (logon fallido) seguidos de un 4624 (logon exitoso) desde la misma IP → regla de fuerza bruta de Wazuh (`win_security_rules`, ids 60122/60204 o similar según versión) |
| [`persist-registry.ps1`](persist-registry.ps1) | Persistencia clásica: agrega una entrada a `Run` desde una sesión ya comprometida en WS01 | Evento Sysmon 13 (RegistryEvent) sobre `CurrentVersion\Run`, correlacionado con el logon de arriba |

## Orden sugerido

1. `recon.sh` desde KALI01 contra `172.16.0.0/24`.
2. `bruteforce-rdp.sh` contra WS01 con la wordlist incluida, hasta que
   acierte (la contraseña de prueba está en la wordlist a propósito).
3. Ya "dentro" de WS01 (sesión RDP con la contraseña encontrada), correr
   `persist-registry.ps1` para simular el paso de persistencia.
4. Completar [`informe-deteccion.md`](informe-deteccion.md) con lo que
   mostró el dashboard de Wazuh (*Threat hunting* → filtrar por `agent.name`)
   para cada paso: hora, evento, regla que disparó, y si disparó o no.

## Qué no hace esto

No hay aquí herramientas de explotación de vulnerabilidades (Metasploit,
EternalBlue, etc.) ni nada que deje persistencia real fuera de lo que el
propio script agrega y documenta cómo revertir. El objetivo es generar
telemetría para practicar detección, no comprometer las VMs de verdad.
