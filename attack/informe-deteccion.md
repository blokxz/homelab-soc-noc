# Informe de detección — Fase 10

> Plantilla. Completar una copia por ejercicio (sugerido:
> `informe-deteccion-AAAAMMDD.md`, sin subir al repo si tiene datos reales
> del lab que no quieras publicar — agregarlo al `.gitignore` si hace falta).

## Datos del ejercicio

- **Fecha:**
- **Operador:**
- **Origen (KALI01):** 172.16.66.10
- **Objetivo(s):**
- **Scripts corridos:** `recon.sh` / `bruteforce-rdp.sh` / `persist-registry.ps1`

## Línea de tiempo

| Hora | Paso | Host | Evento esperado | ¿Detectado? |
|---|---|---|---|---|
| | Recon (nmap) | CORP | — (no hay alerta nativa) | |
| | Fuerza bruta RDP | WS01 | 4625 x N → 4624 | |
| | Persistencia (Run key) | WS01 | Sysmon 13 | |

## Hallazgos

- **Qué se vio en el dashboard de Wazuh (*Threat hunting*):**
- **Reglas que dispararon (id y nombre):**
- **Qué no se detectó y por qué (regla ausente, agente no instalado, log no llegó):**

## Causa raíz (si aplica)

Igual que en el runbook de la Fase 5: ordenar los eventos cronológicamente y
señalar cuál es la causa y cuáles son consecuencia, en vez de tratar cada
alerta como un incidente separado.

## Acciones de seguimiento

- [ ] Regla nueva o ajustada en Wazuh (`local_rules.xml`), si hizo falta.
- [ ] Ajuste a `sysmonconfig.xml` si faltó o sobró telemetría.
- [ ] Reversión confirmada (`persist-registry.ps1 -Revert`, cuentas de
      prueba deshabilitadas de nuevo).
