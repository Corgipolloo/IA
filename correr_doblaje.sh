#!/usr/bin/env bash
# correr_doblaje.sh - Un click y se dobla el video completo
# Uso: bash correr_doblaje.sh

set -euo pipefail

VIDEO_URL="https://youtu.be/eOUfemUXMxk"
REPO_DIR="$HOME/IA"
PROJECT_DIR="$REPO_DIR/ai_video_dubbing"
OUTPUT_NAME="fogata_ryou_doblado"

echo ""
echo "=================================================="
echo "   AI VIDEO DUBBING - Todo Automatico"
echo "   Video: La Fogata de Ryou"
echo "=================================================="
echo ""

# --- 1. Verificar e instalar dependencias del sistema ---
echo "[1/6] Verificando dependencias del sistema..."

if ! command -v ffmpeg &>/dev/null; then
    echo "  Instalando ffmpeg..."
    if command -v brew &>/dev/null; then
        brew install ffmpeg
    elif command -v apt &>/dev/null; then
        sudo apt update && sudo apt install -y ffmpeg
    elif command -v pacman &>/dev/null; then
        sudo pacman -S --noconfirm ffmpeg
    else
        echo "ERROR: No se pudo instalar ffmpeg. Instalalo manualmente."
        exit 1
    fi
fi
echo "  ffmpeg OK"

if ! command -v yt-dlp &>/dev/null; then
    echo "  Instalando yt-dlp..."
    pip install yt-dlp
fi
echo "  yt-dlp OK"

if ! command -v python3 &>/dev/null; then
    echo "ERROR: Necesitas Python 3. Instalalo primero."
    exit 1
fi
echo "  python3 OK"

# --- 2. Clonar o actualizar repo ---
echo ""
echo "[2/6] Preparando el proyecto..."

if [ -d "$REPO_DIR/.git" ]; then
    echo "  Repo ya existe, actualizando..."
    cd "$REPO_DIR"
    git pull origin claude/ai-video-dubbing-tool-Bj1MD || true
    git checkout claude/ai-video-dubbing-tool-Bj1MD || true
else
    echo "  Clonando repo..."
    git clone -b claude/ai-video-dubbing-tool-Bj1MD https://github.com/corgipolloo/ia.git "$REPO_DIR"
fi

cd "$PROJECT_DIR"

# --- 3. Instalar dependencias de Python ---
echo ""
echo "[3/6] Instalando paquetes de Python..."
pip install -q -r requirements.txt 2>&1 | tail -1
echo "  Dependencias OK"

# --- 4. Correr el pipeline ---
echo ""
echo "[4/6] Descargando video de YouTube..."
echo "[5/6] Transcribiendo, traduciendo, generando voz..."
echo "[6/6] Componiendo video final..."
echo ""
echo "  (esto puede tardar unos minutos dependiendo de tu internet y CPU)"
echo ""

python3 run_pipeline.py "$VIDEO_URL" --output "$OUTPUT_NAME"

# --- Resultado ---
FINAL_VIDEO="$PROJECT_DIR/output/${OUTPUT_NAME}.mp4"

if [ -f "$FINAL_VIDEO" ]; then
    echo ""
    echo "=================================================="
    echo "   LISTO! Video doblado generado:"
    echo "   $FINAL_VIDEO"
    echo "=================================================="
    echo ""

    # Intentar abrir el video
    if command -v xdg-open &>/dev/null; then
        xdg-open "$FINAL_VIDEO" &
    elif command -v open &>/dev/null; then
        open "$FINAL_VIDEO"
    else
        echo "  Abre el archivo manualmente: $FINAL_VIDEO"
    fi
else
    echo ""
    echo "ERROR: No se genero el video final."
    echo "Revisa los errores arriba."
    exit 1
fi
