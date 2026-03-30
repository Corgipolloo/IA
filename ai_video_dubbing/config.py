"""
Configuración del proyecto AI Video Dubbing.
Todas las herramientas son GRATUITAS.
"""

import os

# Directorios de trabajo
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
DOWNLOADS_DIR = os.path.join(BASE_DIR, "downloads")
OUTPUT_DIR = os.path.join(BASE_DIR, "output")
TEMP_DIR = os.path.join(BASE_DIR, "temp")

# Crear directorios si no existen
for d in [DOWNLOADS_DIR, OUTPUT_DIR, TEMP_DIR]:
    os.makedirs(d, exist_ok=True)

# Configuración de Whisper (transcripción gratuita, local)
WHISPER_MODEL = "base"  # opciones: tiny, base, small, medium, large

# Configuración de Edge TTS (text-to-speech gratuito de Microsoft)
# Voces en español disponibles:
TTS_VOICES = {
    "es_male": "es-MX-JorgeNeural",
    "es_female": "es-MX-DaliaNeural",
    "es_narrator": "es-ES-AlvaroNeural",
}
DEFAULT_VOICE = "es-MX-JorgeNeural"

# Configuración de subtítulos
SUBTITLE_FONT = "Arial"
SUBTITLE_FONTSIZE = 24
SUBTITLE_COLOR = "white"
SUBTITLE_BG_COLOR = "black"
SUBTITLE_BG_OPACITY = 0.6

# Configuración de video
MAX_VIDEO_DURATION = 600  # 10 minutos máximo para procesamiento rápido
VIDEO_FORMAT = "mp4"
