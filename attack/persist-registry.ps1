<#
.SYNOPSIS
    Simula un paso de persistencia clásico (entrada en Run) en WS01, para
    generar el evento Sysmon 13 que Wazuh debería correlacionar con el logon
    de bruteforce-rdp.sh (Fase 10).

.DESCRIPTION
    Correr DENTRO de WS01, ya con una sesión (por ejemplo, la que abrió
    bruteforce-rdp.sh al encontrar la contraseña). Agrega una entrada
    inofensiva a HKCU\...\Run que solo abre el Bloc de notas, para no dejar
    nada dañino de verdad. Incluye -Revert para deshacerlo.

.EXAMPLE
    .\persist-registry.ps1
    .\persist-registry.ps1 -Revert
#>
param(
    [switch]$Revert
)

$keyPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
$valueName = "LabPersistenceDemo"

if ($Revert) {
    Remove-ItemProperty -Path $keyPath -Name $valueName -ErrorAction SilentlyContinue
    Write-Host "Entrada de persistencia '$valueName' eliminada de $keyPath."
    exit 0
}

Set-ItemProperty -Path $keyPath -Name $valueName -Value "notepad.exe" -Type String
Write-Host "Entrada de persistencia creada: $keyPath\$valueName = notepad.exe"
Write-Host "Esto debería aparecer en Wazuh como un evento Sysmon 13 (RegistryEvent)."
Write-Host "Revertir con: .\persist-registry.ps1 -Revert"
