<#
.SYNOPSIS
    Detiene (o arranca) un servicio de Windows en DC01/WS01 a propósito, para
    probar la auto-remediación de la Fase 11 (zabbix/automation/configure_noc.py
    remediate) sin tener que esperar a que falle algo de verdad.

.PARAMETER Name
    Nombre del servicio (ver Get-Service). Por defecto "Spooler" (Cola de
    impresión): existe en toda instalación de Windows y detenerlo no afecta
    nada crítico del lab.

.PARAMETER Stop
    Detener el servicio. Sin este flag, el script lo arranca (por si la
    auto-remediación no llegó a actuar y hay que revertir a mano).

.EXAMPLE
    .\toggle-service.ps1 -Stop                  # dispara el trigger
    .\toggle-service.ps1                         # lo arranca de nuevo a mano
#>
param(
    [string]$Name = "Spooler",
    [switch]$Stop
)

$service = Get-Service -Name $Name -ErrorAction SilentlyContinue
if (-not $service) {
    Write-Error "No existe el servicio '$Name' en este equipo."
    exit 1
}

if ($Stop) {
    Write-Host "Deteniendo '$Name'..."
    Stop-Service -Name $Name -Force
    Write-Host "Detenido. Si la auto-remediación de la Fase 11 está configurada,"
    Write-Host "Zabbix debería volver a arrancarlo solo en los próximos minutos."
    Write-Host "Verificar con: Get-Service $Name"
} else {
    Write-Host "Arrancando '$Name'..."
    Start-Service -Name $Name
    Write-Host "Arrancado."
}
