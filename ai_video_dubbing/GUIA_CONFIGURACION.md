# Guia de Configuracion - AI Video Dubbing (n8n)

## APIs gratuitas que necesitas configurar

### 1. YouTube Data API v3 (GRATIS)
1. Ve a https://console.cloud.google.com
2. Crea un proyecto nuevo
3. Habilita "YouTube Data API v3"
4. Crea una API Key en Credenciales
5. Limite: 10,000 unidades/dia (suficiente para ~100 busquedas)

En n8n: Pega la API key en el nodo "YouTube Search" en el header.

### 2. Groq API - Whisper (GRATIS)
1. Registrate en https://console.groq.com
2. Genera una API Key
3. Modelo: whisper-large-v3
4. Limite: generoso free tier

En n8n: Configura en el nodo "Transcribe Audio" como Bearer token.

### 3. Google Gemini 1.5 Flash (GRATIS)
1. Ve a https://aistudio.google.com/apikey
2. Genera una API Key
3. Modelo: gemini-1.5-flash
4. Limite: 1,500 requests/dia, 1M tokens/mes

En n8n: Configura en el nodo "Rewrite Dialogues" como parametro de URL.

### 4. ElevenLabs (GRATIS - opcional)
1. Registrate en https://elevenlabs.io
2. Genera una API Key
3. Voz recomendada: "Adam" (id: pNInz6obpgDQGcFmaJgB)
4. Limite: 10,000 caracteres/mes

Alternativa gratuita ilimitada: Kokoro TTS (local, ver setup_server.sh)

### 5. Google Drive API (GRATIS)
1. En Google Cloud Console, habilita "Google Drive API"
2. Crea credenciales OAuth2 (tipo Desktop)
3. Descarga el JSON de credenciales

En n8n: Usa el nodo de Google Drive con OAuth2.

### 6. Telegram Bot (GRATIS)
1. Abre Telegram, busca @BotFather
2. Envia /newbot y sigue las instrucciones
3. Guarda el token del bot
4. Obtén tu chat_id enviando un mensaje al bot y visitando:
   https://api.telegram.org/bot<TOKEN>/getUpdates

En n8n: Configura el nodo Telegram con el token.

### 7. Google Sheets (GRATIS)
1. Crea un Google Sheet con estas columnas:
   - A: fecha
   - B: videoId
   - C: canal_origen
   - D: titulo
   - E: clips_generados
   - F: duracion_total
   - G: estado
2. Comparte el Sheet con la cuenta de servicio de Google

## Hosting gratuito para n8n

### Opcion A: Railway.app
1. Crea cuenta en https://railway.app
2. Deploy n8n desde template
3. Incluye 500 horas/mes gratis
4. Instala yt-dlp y ffmpeg en el Dockerfile

### Opcion B: Render.com
1. Crea cuenta en https://render.com
2. Deploy como Docker service
3. Free tier disponible

### Opcion C: Local (tu PC)
```bash
npm install -g n8n
n8n start
```

## Dockerfile para deploy

```dockerfile
FROM n8nio/n8n:latest

USER root

RUN apk add --no-cache \
    ffmpeg \
    python3 \
    py3-pip

RUN pip3 install yt-dlp

USER node
```

## Variables de entorno requeridas

```env
YOUTUBE_API_KEY=tu_key_aqui
GROQ_API_KEY=tu_key_aqui
GEMINI_API_KEY=tu_key_aqui
ELEVENLABS_API_KEY=tu_key_aqui  # opcional
TELEGRAM_BOT_TOKEN=tu_token_aqui
TELEGRAM_CHAT_ID=tu_chat_id_aqui
```

En n8n, configura estas como variables de entorno o como credenciales.

## Limites gratuitos diarios (resumen)

| Servicio | Limite diario | Videos que puedes procesar |
|----------|--------------|---------------------------|
| YouTube API | 10,000 unidades | ~100 busquedas |
| Groq Whisper | Generoso | ~50 transcripciones |
| Gemini Flash | 1,500 requests | ~15 videos |
| ElevenLabs | 10,000 chars/mes | ~1-2 videos/mes |
| Kokoro TTS | Ilimitado (local) | Ilimitado |
| Google Drive | 15 GB | ~150 videos |

**Recomendacion:** Usa Kokoro TTS local para no depender de ElevenLabs.
El workflow esta limitado a 3 videos/ejecucion para respetar las cuotas.
