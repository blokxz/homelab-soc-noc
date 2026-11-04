<#
.SYNOPSIS
    Reserva espacio en disco temporalmente para probar el trigger de espacio
    libre de Zabbix (Fase 6). Borra el archivo al terminar o si se interrumpe.

.PARAMETER Path
    Carpeta donde crear el archivo de prueba. Por defecto, la unidad del
    sistema (p. ej. C:\).

.PARAMETER GB
    Tamaño del archivo en GB. Calcular para dejar el disco por debajo del
    umbral del trigger (revisar el template: por defecto suele ser <10-20%
    libre), sin llenarlo del todo.

.PARAMETER Minutes
    Cuánto tiempo mantener el archivo antes de borrarlo. Por defecto 10.

.EXAMPLE
    .\disk-fill.ps1 -GB 20 -Minutes 15
#>
param(
    [string]$Path = "$env:SystemDrive\",
    [double]$GB = 10,
    [int]$Minutes = 10
)

$file = Join-Path $Path "zabbix-disk-test.tmp"
$bytes = [int64]($GB * 1GB)

$drive = (Get-PSDrive -Name $Path.Substring(0, 1))
if ($drive.Free -lt $bytes + 2GB) {
    Write-Error "No hay margen seguro: libre $([math]::Round($drive.Free / 1GB, 1)) GB, se pidieron $GB GB. Abortando."
    exit 1
}

Write-Host "Creando $file de $GB GB (espacio libre hoy: $([math]::Round($drive.Free / 1GB, 1)) GB)..."
$fsutil = fsutil file createnew $file $bytes
Write-Host $fsutil
Write-Host "Esperando $Minutes minuto(s) para que Zabbix detecte el problema..."

try {
    Start-Sleep -Seconds ($Minutes * 60)
} finally {
    Write-Host "Borrando $file..."
    Remove-Item -Path $file -Force -ErrorAction SilentlyContinue
    Write-Host "Listo. Verificar en Zabbix que el problema pasó a RESOLVED."
}
