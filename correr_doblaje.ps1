# correr_doblaje.ps1 - Un click y se dobla el video completo (Windows)
# Uso: Click derecho -> Ejecutar con PowerShell
#   o desde terminal: powershell -ExecutionPolicy Bypass -File correr_doblaje.ps1

$ErrorActionPreference = "Continue"
$VIDEO_URL = "https://youtu.be/eOUfemUXMxk"
$REPO_DIR = "$HOME\IA"
$PROJECT_DIR = "$REPO_DIR\ai_video_dubbing"
$OUTPUT_NAME = "fogata_ryou_doblado"

Write-Host ""
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "   AI VIDEO DUBBING - Todo Automatico (Windows)" -ForegroundColor Cyan
Write-Host "   Video: La Fogata de Ryou" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host ""

# --- 1. Verificar Python ---
Write-Host "[1/6] Verificando Python..." -ForegroundColor Yellow
try {
    $pyVersion = python --version 2>&1
    Write-Host "  $pyVersion OK" -ForegroundColor Green
} catch {
    Write-Host "  ERROR: Python no esta instalado." -ForegroundColor Red
    Write-Host "  Descargalo de: https://www.python.org/downloads/" -ForegroundColor Red
    Write-Host "  IMPORTANTE: Marca 'Add Python to PATH' al instalar" -ForegroundColor Red
    Read-Host "Presiona Enter para salir"
    exit 1
}

# --- 2. Verificar/instalar ffmpeg ---
Write-Host "[2/6] Verificando ffmpeg..." -ForegroundColor Yellow
if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
    Write-Host "  Instalando ffmpeg con winget..." -ForegroundColor Yellow
    try {
        winget install --id Gyan.FFmpeg -e --accept-source-agreements --accept-package-agreements
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    } catch {
        Write-Host "  ERROR: No se pudo instalar ffmpeg automaticamente." -ForegroundColor Red
        Write-Host "  Descargalo de: https://ffmpeg.org/download.html" -ForegroundColor Red
        Read-Host "Presiona Enter para salir"
        exit 1
    }
}
Write-Host "  ffmpeg OK" -ForegroundColor Green

# --- 3. Instalar yt-dlp y paquetes Python ---
Write-Host "[3/6] Instalando paquetes de Python (puede tardar)..." -ForegroundColor Yellow
$ErrorActionPreference = "SilentlyContinue"
python -m pip install yt-dlp openai-whisper edge-tts moviepy 2>&1 | ForEach-Object { if ($_ -match "Successfully") { Write-Host "  $_" -ForegroundColor Green } }
$ErrorActionPreference = "Continue"
Write-Host "  Paquetes OK" -ForegroundColor Green

# --- 4. Clonar o actualizar repo ---
Write-Host "[4/6] Preparando el proyecto..." -ForegroundColor Yellow
if (Test-Path "$REPO_DIR\.git") {
    Write-Host "  Repo ya existe, actualizando..." -ForegroundColor Yellow
    Set-Location $REPO_DIR
    git pull origin claude/ai-video-dubbing-tool-Bj1MD 2>&1 | Out-Null
    git checkout claude/ai-video-dubbing-tool-Bj1MD 2>&1 | Out-Null
} else {
    Write-Host "  Clonando repo..." -ForegroundColor Yellow
    git clone -b claude/ai-video-dubbing-tool-Bj1MD https://github.com/corgipolloo/ia.git $REPO_DIR
}
Set-Location $PROJECT_DIR

# --- 5. Correr el pipeline ---
Write-Host ""
Write-Host "[5/6] Corriendo pipeline completo..." -ForegroundColor Yellow
Write-Host "  Descargando video..." -ForegroundColor Yellow
Write-Host "  Transcribiendo con Whisper..." -ForegroundColor Yellow
Write-Host "  Traduciendo y generando voz..." -ForegroundColor Yellow
Write-Host "  (esto puede tardar unos minutos)" -ForegroundColor Yellow
Write-Host ""

python run_pipeline.py $VIDEO_URL --output $OUTPUT_NAME

# --- 6. Resultado ---
$FINAL_VIDEO = "$PROJECT_DIR\output\$OUTPUT_NAME.mp4"

if (Test-Path $FINAL_VIDEO) {
    Write-Host ""
    Write-Host "==================================================" -ForegroundColor Green
    Write-Host "   LISTO! Video doblado generado:" -ForegroundColor Green
    Write-Host "   $FINAL_VIDEO" -ForegroundColor Green
    Write-Host "==================================================" -ForegroundColor Green
    Write-Host ""

    # Abrir el video
    Start-Process $FINAL_VIDEO

    # Abrir la carpeta
    explorer.exe (Split-Path $FINAL_VIDEO)
} else {
    Write-Host ""
    Write-Host "ERROR: No se genero el video final." -ForegroundColor Red
    Write-Host "Revisa los errores arriba." -ForegroundColor Red
}

Write-Host ""
Read-Host "Presiona Enter para cerrar"
