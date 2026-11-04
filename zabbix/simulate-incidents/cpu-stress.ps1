<#
.SYNOPSIS
    Genera carga de CPU en DC01 o WS01 durante un tiempo fijo, para probar el
    trigger "CPU utilization" de Zabbix y validar el ciclo completo: problema
    -> acknowledge -> resolución automática (Fase 6).

.PARAMETER Minutes
    Duración de la carga, en minutos. Por defecto 5.

.PARAMETER Cores
    Cantidad de hilos de carga. Por defecto, todos los núcleos lógicos.

.EXAMPLE
    .\cpu-stress.ps1 -Minutes 10
#>
param(
    [int]$Minutes = 5,
    [int]$Cores = [Environment]::ProcessorCount
)

Write-Host "Generando carga de CPU en $Cores hilos durante $Minutes minuto(s)..."
Write-Host "Ctrl+C cancela antes de tiempo (los jobs se limpian igual)."

$jobs = 1..$Cores | ForEach-Object {
    Start-Job -ScriptBlock {
        $end = (Get-Date).AddMinutes($using:Minutes)
        while ((Get-Date) -lt $end) {
            # Busy loop simple: no usa librerías externas ni descarga nada.
            $x = 0
            for ($i = 0; $i -lt 1000000; $i++) { $x += $i * $i }
        }
    }
}

try {
    Wait-Job -Job $jobs | Out-Null
} finally {
    Remove-Job -Job $jobs -Force
    Write-Host "Carga terminada. Verificar en Zabbix: Monitoring -> Problems -> CPU utilization."
}
