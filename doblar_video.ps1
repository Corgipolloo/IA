# doblar_video.ps1 - TODO AUTOMATICO: instala ffmpeg, crea workflow en n8n, y ejecuta el doblaje
# Pega esto en PowerShell y no toques nada mas

Set-ExecutionPolicy Bypass -Scope Process -Force
$ErrorActionPreference = "Continue"

$PROJECT = "$HOME\IA\ai_video_dubbing"
$VIDEO_URL = "https://youtu.be/eOUfemUXMxk"
$VOICE = "es-ES-AlvaroNeural"
$OUTPUT = "fogata_ryou_doblado"

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  DOBLAJE AUTOMATICO - Todo en uno" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# --- 1. Verificar ffmpeg ---
Write-Host "`n[1/4] Verificando ffmpeg..." -ForegroundColor Yellow
if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
    Write-Host "  Instalando ffmpeg..." -ForegroundColor Yellow
    winget install Gyan.FFmpeg --accept-source-agreements --accept-package-agreements 2>$null
    # Actualizar PATH
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    # Buscar ffmpeg en rutas comunes
    $ffmpegPaths = @(
        "C:\ffmpeg\bin",
        "C:\Program Files\ffmpeg\bin",
        "C:\ProgramData\chocolatey\bin",
        "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\Gyan.FFmpeg_*\ffmpeg-*\bin"
    )
    foreach ($p in $ffmpegPaths) {
        $resolved = Resolve-Path $p -ErrorAction SilentlyContinue
        if ($resolved) {
            $env:Path += ";$resolved"
            break
        }
    }
}
if (Get-Command ffmpeg -ErrorAction SilentlyContinue) {
    Write-Host "  ffmpeg OK" -ForegroundColor Green
} else {
    Write-Host "  ffmpeg no encontrado. Descargalo de https://ffmpeg.org/download.html" -ForegroundColor Red
    Write-Host "  Extrae el zip y agrega la carpeta 'bin' al PATH de Windows" -ForegroundColor Red
    Read-Host "Presiona Enter para continuar de todos modos"
}

# --- 2. Verificar proyecto ---
Write-Host "`n[2/4] Verificando proyecto..." -ForegroundColor Yellow
if (-not (Test-Path "$PROJECT\run_pipeline.py")) {
    Write-Host "  Clonando repositorio..." -ForegroundColor Yellow
    git clone -b claude/ai-video-dubbing-tool-Bj1MD https://github.com/corgipolloo/ia.git "$HOME\IA" 2>$null
}
if (Test-Path "$PROJECT\run_pipeline.py") {
    Write-Host "  Proyecto OK" -ForegroundColor Green
} else {
    Write-Host "  ERROR: No se encontro el proyecto en $PROJECT" -ForegroundColor Red
    exit 1
}

# --- 3. Instalar dependencias Python ---
Write-Host "`n[3/4] Verificando paquetes Python..." -ForegroundColor Yellow
python -m pip install -q yt-dlp openai-whisper edge-tts moviepy pydub 2>$null
Write-Host "  Paquetes OK" -ForegroundColor Green

# --- 4. CORRER EL PIPELINE ---
Write-Host "`n[4/4] Iniciando doblaje..." -ForegroundColor Yellow
Write-Host "  Video: $VIDEO_URL" -ForegroundColor Cyan
Write-Host "  Voz: $VOICE" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Esto tarda 10-20 minutos. NO cierres esta ventana." -ForegroundColor Yellow
Write-Host ""

Set-Location $PROJECT
python run_pipeline.py $VIDEO_URL --voice $VOICE --output $OUTPUT

# --- RESULTADO ---
$FINAL = "$PROJECT\output\$OUTPUT.mp4"
if (Test-Path $FINAL) {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "  VIDEO DOBLADO LISTO!" -ForegroundColor Green
    Write-Host "  $FINAL" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Start-Process explorer.exe "/select,$FINAL"
} else {
    Write-Host ""
    Write-Host "  Hubo un error. Revisa los mensajes arriba." -ForegroundColor Red
}

Write-Host ""
Read-Host "Presiona Enter para cerrar"
