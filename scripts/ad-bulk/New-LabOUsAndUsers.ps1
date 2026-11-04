<#
.SYNOPSIS
    Crea la estructura de OUs del dominio CORP y da de alta usuarios en bloque
    desde un CSV (Fase 7, DC01 - Parte 3). Reemplaza el alta manual por ADUC.

.DESCRIPTION
    Idempotente: si una OU o un usuario ya existen, los deja como están y
    sigue. Pensado para correr en DC01, con el módulo ActiveDirectory
    (RSAT, ya instalado junto con AD DS).

    Estructura de OUs creada bajo el dominio:
        CORP.home.arpa
        └── Lab
            ├── Soporte
            ├── Redes
            └── Seguridad

    Cada fila del CSV cae en la OU indicada en la columna "OU" (debe ser una
    de las de arriba). El usuario se crea deshabilitado y con "cambiar
    contraseña en el próximo inicio de sesión", igual que en el alta manual
    documentada en el README.

.PARAMETER CsvPath
    Ruta al CSV de usuarios. Columnas esperadas: Nombre, Apellido,
    SamAccountName, OU, Titulo, Departamento. Ver usuarios.csv.example.

.PARAMETER DomainDN
    DN del dominio. Por defecto "DC=corp,DC=home,DC=arpa".

.PARAMETER DefaultPasswordLength
    Longitud de la contraseña aleatoria inicial que se genera para cada
    usuario nuevo (se descarta: queda forzado el cambio en el primer login).

.EXAMPLE
    .\New-LabOUsAndUsers.ps1 -CsvPath .\usuarios.csv
#>
#Requires -Module ActiveDirectory
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$CsvPath,

    [string]$DomainDN = "DC=corp,DC=home,DC=arpa",

    [int]$DefaultPasswordLength = 16
)

$ErrorActionPreference = "Stop"

function New-RandomPassword {
    param([int]$Length = 16)
    # Mezcla de clases de caracteres para cumplir la política de contraseñas
    # por defecto de AD (ver Fase 8: longitud, complejidad).
    $chars = 'abcdefghijklmnopqrstuvwxyz' + 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' + '0123456789' + '!@#$%^&*-_='
    -join (1..$Length | ForEach-Object { $chars[(Get-Random -Maximum $chars.Length)] })
}

function Ensure-OU {
    param([string]$Name, [string]$ParentDN)
    $dn = "OU=$Name,$ParentDN"
    if (-not (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$dn'" -ErrorAction SilentlyContinue)) {
        Write-Host "Creando OU: $dn"
        New-ADOrganizationalUnit -Name $Name -Path $ParentDN -ProtectedFromAccidentalDeletion $true
    } else {
        Write-Verbose "OU ya existe: $dn"
    }
    return $dn
}

# --- Estructura de OUs -------------------------------------------------
$labDN = Ensure-OU -Name "Lab" -ParentDN $DomainDN
$ouMap = @{
    "Soporte"   = Ensure-OU -Name "Soporte"   -ParentDN $labDN
    "Redes"     = Ensure-OU -Name "Redes"     -ParentDN $labDN
    "Seguridad" = Ensure-OU -Name "Seguridad" -ParentDN $labDN
}

# --- Alta masiva de usuarios --------------------------------------------
if (-not (Test-Path $CsvPath)) {
    throw "No se encontró el CSV: $CsvPath"
}

$rows = Import-Csv -Path $CsvPath
$created = 0
$skipped = 0

foreach ($row in $rows) {
    $sam = $row.SamAccountName.Trim()
    if ([string]::IsNullOrWhiteSpace($sam)) {
        Write-Warning "Fila sin SamAccountName, se omite: $($row | Out-String)"
        continue
    }

    if (-not $ouMap.ContainsKey($row.OU)) {
        Write-Warning "OU '$($row.OU)' no reconocida para $sam, se omite. Usar: $($ouMap.Keys -join ', ')"
        continue
    }

    if (Get-ADUser -Filter "SamAccountName -eq '$sam'" -ErrorAction SilentlyContinue) {
        Write-Verbose "Usuario ya existe, se omite: $sam"
        $skipped++
        continue
    }

    $password = ConvertTo-SecureString -String (New-RandomPassword -Length $DefaultPasswordLength) -AsPlainText -Force
    $displayName = "$($row.Nombre) $($row.Apellido)"
    $upn = "$sam@corp.home.arpa"

    New-ADUser `
        -Name $displayName `
        -GivenName $row.Nombre `
        -Surname $row.Apellido `
        -SamAccountName $sam `
        -UserPrincipalName $upn `
        -Path $ouMap[$row.OU] `
        -Title $row.Titulo `
        -Department $row.Departamento `
        -AccountPassword $password `
        -ChangePasswordAtLogon $true `
        -Enabled $false `
        -Description "Creado por New-LabOUsAndUsers.ps1 el $(Get-Date -Format 'yyyy-MM-dd')"

    Write-Host "Usuario creado (deshabilitado): $upn en $($ouMap[$row.OU])"
    $created++
}

Write-Host "`nListo: $created usuario(s) creado(s), $skipped ya existían."
Write-Host "Habilitarlos con Enable-ADAccount tras verificarlos en ADUC, o agregar -Enabled `$true arriba si se confía en el CSV."
