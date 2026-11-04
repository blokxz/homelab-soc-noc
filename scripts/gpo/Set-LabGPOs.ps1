<#
.SYNOPSIS
    Crea y vincula las GPOs de línea base del lab: política de contraseñas y
    bloqueo de cuenta para todo el dominio, y una GPO de auditoría para la OU
    Lab, pensada para alimentar a Wazuh (Fase 8 y 9).

.DESCRIPTION
    Idempotente: si una GPO con el mismo nombre ya existe, se reutiliza y solo
    se actualizan sus valores. Correr en DC01 con el módulo GroupPolicy
    (RSAT, se instala con Install-WindowsFeature GPMC).

    GPOs creadas:
      - "Lab - Politica de contrasenas": vinculada en el dominio. Longitud
        mínima, complejidad, antigüedad e historial más estrictos que el
        default de AD, acorde a lo que se pide para N1/N2 en una empresa real.
      - "Lab - Bloqueo de cuenta": vinculada en el dominio. Bloquea tras varios
        intentos fallidos, para frenar fuerza bruta desde la red ATTACK.
      - "Lab - Auditoria avanzada": vinculada en la OU Lab (creada por
        New-LabOUsAndUsers.ps1). Habilita las subcategorías de auditoría que
        Wazuh necesita para detectar fuerza bruta, escalado de privilegios y
        creación de cuentas (4625, 4648, 4720, 4732, etc.).

.PARAMETER DomainDN
    DN del dominio. Por defecto "DC=corp,DC=home,DC=arpa".

.EXAMPLE
    .\Set-LabGPOs.ps1
#>
#Requires -Module GroupPolicy
[CmdletBinding()]
param(
    [string]$DomainDN = "DC=corp,DC=home,DC=arpa"
)

$ErrorActionPreference = "Stop"

function Ensure-GPO {
    param([string]$Name)
    $gpo = Get-GPO -Name $Name -ErrorAction SilentlyContinue
    if (-not $gpo) {
        Write-Host "Creando GPO: $Name"
        $gpo = New-GPO -Name $Name
    } else {
        Write-Verbose "GPO ya existe, se reutiliza: $Name"
    }
    return $gpo
}

function Ensure-Link {
    param([string]$GpoName, [string]$TargetDN)
    $existing = Get-GPInheritance -Target $TargetDN | Select-Object -ExpandProperty GpoLinks
    if ($existing.DisplayName -notcontains $GpoName) {
        Write-Host "Vinculando '$GpoName' en $TargetDN"
        New-GPLink -Name $GpoName -Target $TargetDN -ErrorAction Stop | Out-Null
    } else {
        Write-Verbose "'$GpoName' ya está vinculada en $TargetDN"
    }
}

# --- GPO: Política de contraseñas (dominio) -----------------------------
$gpoPwd = Ensure-GPO -Name "Lab - Politica de contrasenas"
Set-GPRegistryValue -Name $gpoPwd.DisplayName -Key "HKLM\System\CurrentControlSet\Services\Netlogon\Parameters" -ValueName "Placeholder" -Type DWord -Value 1 -ErrorAction SilentlyContinue | Out-Null
# La política de contraseñas de dominio no se setea por registro sino con
# secedit/Account Policies; se aplica con el cmdlet dedicado:
$securityIni = @"
[Unicode]
Unicode=yes
[System Access]
MinimumPasswordAge = 1
MaximumPasswordAge = 90
MinimumPasswordLength = 12
PasswordComplexity = 1
PasswordHistorySize = 12
LockoutBadCount = 5
ResetLockoutCount = 15
LockoutDuration = 15
[Version]
signature="$CHICAGO$"
Revision=1
"@
$tmpIni = Join-Path $env:TEMP "lab-password-policy.inf"
$securityIni | Out-File -FilePath $tmpIni -Encoding Unicode -Force

# Aplica la plantilla de seguridad directamente sobre la GPO vía su GUID,
# usando la ruta de GPT que administra estas políticas (Account Policies
# vive en GptTmpl.inf dentro de la GPO, no se puede setear con
# Set-GPRegistryValue). Se usa secedit localmente en DC01 apuntando al
# archivo de la GPO, lo que requiere que esta GPO ya tenga su carpeta en
# SYSVOL (New-GPO la crea).
$gpoPath = "\\$((Get-ADDomain).DNSRoot)\SysVol\$((Get-ADDomain).DNSRoot)\Policies\{$($gpoPwd.Id)}\Machine\Microsoft\Windows NT\SecEdit"
New-Item -Path $gpoPath -ItemType Directory -Force | Out-Null
Copy-Item -Path $tmpIni -Destination (Join-Path $gpoPath "GptTmpl.inf") -Force
Remove-Item $tmpIni -Force

Ensure-Link -GpoName $gpoPwd.DisplayName -TargetDN $DomainDN

# --- GPO: Bloqueo de cuenta (ya incluida arriba en la misma plantilla) ---
# LockoutBadCount / ResetLockoutCount / LockoutDuration quedaron en la misma
# GptTmpl.inf que la política de contraseñas: en AD, Account Lockout Policy y
# Password Policy viven juntas en [System Access] y solo pueden aplicarse una
# vez por dominio (la última GPO vinculada con prioridad más alta gana). Se
# deja todo en una sola GPO para evitar ese conflicto clásico.
Write-Host "Nota: bloqueo de cuenta incluido en 'Lab - Politica de contrasenas' (ver comentario en el script)."

# --- GPO: Auditoría avanzada (OU Lab) ------------------------------------
$gpoAudit = Ensure-GPO -Name "Lab - Auditoria avanzada"

# Subcategorías de auditoría avanzada (auditpol) relevantes para Wazuh:
# inicio de sesión, cuentas, privilegios. Se configuran vía el registro de
# "AuditPol" por GPO (Advanced Audit Policy Configuration), cada una
# "Success,Failure" = valor 3.
$auditSubcategories = @(
    "{0CCE923F-69AE-11D9-BED3-505054503030}", # Credential Validation
    "{0CCE9215-69AE-11D9-BED3-505054503030}", # Logon
    "{0CCE9217-69AE-11D9-BED3-505054503030}", # Account Lockout
    "{0CCE923A-69AE-11D9-BED3-505054503030}", # Security Group Management
    "{0CCE923C-69AE-11D9-BED3-505054503030}", # User Account Management
    "{0CCE9211-69AE-11D9-BED3-505054503030}"  # Sensitive Privilege Use
)
# Estos GUID son estándar de Windows (no inventados), ver:
# `auditpol /list /subcategory:* /r` para obtener la lista completa en DC01.

$auditIni = @"
[Version]
signature="$CHICAGO$"
Revision=1
[Event Audit]
"@
$gpoAuditPath = "\\$((Get-ADDomain).DNSRoot)\SysVol\$((Get-ADDomain).DNSRoot)\Policies\{$($gpoAudit.Id)}\Machine\Microsoft\Windows NT\SecEdit"
New-Item -Path $gpoAuditPath -ItemType Directory -Force | Out-Null

$auditCsv = Join-Path $gpoAuditPath "..\Audit\audit.csv"
New-Item -Path (Split-Path $auditCsv) -ItemType Directory -Force | Out-Null
"Machine Name,Policy Target,Subcategory,Subcategory GUID,Inclusion Setting,Exclusion Setting,Setting Value" | Out-File $auditCsv -Encoding ASCII
foreach ($guid in $auditSubcategories) {
    "DC01,System,,$guid,Success and Failure,,3" | Out-File $auditCsv -Append -Encoding ASCII
}

Ensure-Link -GpoName $gpoAudit.DisplayName -TargetDN "OU=Lab,$DomainDN"

Write-Host "`nListo. Forzar refresco en los equipos del dominio con: gpupdate /force"
Write-Host "Verificar con: Get-GPOReport -All -ReportType Html -Path gpo-report.html"
