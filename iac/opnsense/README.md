# IaC para FW01 (OPNsense) — Fase 11

OPNsense no tiene un motor declarativo propio como Terraform. Acá se
combinan dos enfoques, de más simple/confiable a más expresivo:

## 1. Config versionado (lo que cubre todo)

[`backup-config.sh`](backup-config.sh) descarga el `config.xml` de FW01 por
su API REST, lo sanitiza (contraseñas, hashes, claves privadas quedan como
`[REDACTED]`) y lo deja en `config-snapshots/`, listo para comitear. Es el
mismo patrón "GitOps de config.xml" que usa buena parte de la comunidad de
OPNsense/pfSense: no permite aplicar un cambio puntual de forma declarativa,
pero sí ver exactamente qué cambió entre dos backups (`git diff`) y volver
atrás con [`restore-config.sh`](restore-config.sh) si algo salió mal.

```bash
export OPNSENSE_KEY=...      # API key de un usuario de solo lectura
export OPNSENSE_SECRET=...
sh backup-config.sh 192.168.1.59
git diff --no-index config-snapshots/config-<anterior>.xml config-snapshots/config-<nuevo>.xml
```

Correrlo después de cada cambio de reglas/interfaces en la GUI, como
quien hace `git commit` después de cada cambio de código. `restore-config.sh`
pide confirmación explícita y rechaza un snapshot sanitizado (restaurarlo
dejaría contraseñas rotas): ver los comentarios de cada script.

**Nunca comitear un snapshot sin pasar por `backup-config.sh`** (que es el
que sanitiza). `config-snapshots/*.raw.xml` está en `.gitignore` por si
algo falla a mitad de camino y queda un archivo sin sanitizar.

## 2. Ansible para cambios puntuales (ejemplo, sin probar)

[`ansible/`](ansible/) tiene un ejemplo de cómo describir *algunos*
recursos (alias de firewall) de forma declarativa con la colección
comunitaria [`ansibleguy.opnsense`](https://github.com/ansibleguy/collection_opnsense).
No se pudo instalar ni correr esa colección desde esta sesión, así que:

- Verificar que la colección sigue mantenida y qué versión de OPNsense
  soporta antes de usarla.
- Confirmar los nombres de los módulos (`ansibleguy.opnsense.alias`, etc.)
  contra su documentación actual: pueden haber cambiado de nombre entre
  versiones.
- Probar primero con `--check` (modo simulación de Ansible) contra FW01.

Esta colección no cubre todos los objetos de OPNsense (reglas de NAT
complejas, por ejemplo, tienen soporte limitado en varias versiones), por
eso el enfoque 1 (config versionado) es el que garantiza cobertura
completa, y Ansible queda para los recursos puntuales que sí soporta bien
(alias, reglas simples de firewall).

## Cómo se relaciona con el resto del lab

Esto completa la idea de "IaC" para todo el lab, no solo la red:

| Equipo | Qué lo describe como código |
|---|---|
| DC01 (AD, OUs, usuarios) | `scripts/ad-bulk/` (Fase 7) |
| DC01/WS01 (GPOs) | `scripts/gpo/` (Fase 8) |
| FW01 (OPNsense) | Esta carpeta (Fase 11) |
| Zabbix (triggers, mantenimiento, notificación, auto-remediación, tickets) | `zabbix/automation/` (Fases 6 y 11) |

Ninguno es Terraform/Ansible "puro" de punta a punta — son scripts contra la
API o la consola de cada sistema — pero todos comparten la misma idea: el
estado deseado vive en el repo, no solo en la memoria de quien hizo el
cambio por la GUI.
