# AI Video Dubbing Tool

Pipeline de doblaje de videos con IA — **100% GRATUITO**.

## Dos modos de uso

### Modo 1: Script Python (manual)
Ejecuta el pipeline paso a paso desde la terminal.

```bash
cd ai_video_dubbing
pip install -r requirements.txt

# Demo
python run_pipeline.py --demo

# Con un video real
python run_pipeline.py "https://youtube.com/watch?v=XXXXX"
python run_pipeline.py "URL" --voice es-ES-AlvaroNeural --output mi_video
```

### Modo 2: Workflow n8n (automatizado)
Workflow completo que se ejecuta cada 24h automáticamente.

```bash
# 1. Setup del servidor
chmod +x n8n_scripts/setup_server.sh
./n8n_scripts/setup_server.sh

# 2. Importar workflow en n8n
# Abre n8n → Settings → Import Workflow → selecciona n8n_workflow.json

# 3. Configurar credenciales (ver GUIA_CONFIGURACION.md)
```

## Stack tecnológico (todo gratuito)

| Herramienta | Función | Límite gratuito |
|-------------|---------|-----------------|
| **yt-dlp** | Descarga videos | Ilimitado |
| **Whisper (Groq)** | Transcripción | Generoso free tier |
| **Gemini 1.5 Flash** | Reescritura de diálogos | 1M tokens/mes |
| **Edge TTS / Kokoro** | Voz IA | Ilimitado (local) |
| **ElevenLabs** | Voz premium (opcional) | 10,000 chars/mes |
| **FFmpeg** | Edición de video | Ilimitado |
| **n8n** | Automatización | Self-hosted gratis |
| **Google Drive** | Almacenamiento | 15 GB |
| **Telegram Bot** | Notificaciones | Ilimitado |

## Estructura del proyecto

```
ai_video_dubbing/
├── run_pipeline.py          # Pipeline manual completo
├── config.py                # Configuración general
├── step1_download.py        # Descarga de video
├── step2_transcribe.py      # Transcripción con Whisper
├── step3_rewrite_dialogue.py # Reescritura de diálogos
├── step4_generate_audio.py  # Generación de voz IA
├── step5_compose_video.py   # Composición del video final
├── requirements.txt         # Dependencias Python
├── n8n_workflow.json        # Workflow de n8n (importar)
├── n8n_scripts/
│   ├── setup_server.sh      # Instala todo en el servidor
│   ├── circular_structure.js # Estructura narrativa circular
│   ├── clip_cutter.sh       # Corte en clips de 3 min
│   ├── sync_audio.sh        # Sincronización audio/video
│   └── speaking_rate_calculator.js # Cálculo de velocidad TTS
└── GUIA_CONFIGURACION.md    # Guía paso a paso
```

## Flujo del workflow n8n

```
Schedule (24h)
    ↓
YouTube Search (API v3)
    ↓
Check duplicados (Google Sheets)
    ↓
Filter (max 3 videos)
    ↓
Download (yt-dlp)
    ↓
Transcribe (Groq Whisper)
    ↓
Rewrite (Gemini Flash)
    ↓
TTS (Kokoro/ElevenLabs)
    ↓
Sync A/V (FFmpeg)
    ↓
Estructura circular (Code)
    ↓
Corte en clips 3min (FFmpeg)
    ↓
Upload (Google Drive)
    ↓
Notify (Telegram)
    ↓
Log (Google Sheets)
```

## Voces disponibles

- `es-MX-JorgeNeural` — Hombre mexicano (Edge TTS)
- `es-MX-DaliaNeural` — Mujer mexicana (Edge TTS)
- `es-ES-AlvaroNeural` — Narrador español (Edge TTS)
- `am_adam` — Voz masculina (Kokoro TTS, local)
- `Adam` — Voz masculina premium (ElevenLabs, 10k chars gratis)
