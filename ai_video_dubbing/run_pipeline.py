#!/usr/bin/env python3
"""
🎬 AI VIDEO DUBBING PIPELINE - 100% GRATUITO
=============================================
Workflow completo para doblar videos con IA:

1. Descarga video de YouTube (yt-dlp)
2. Transcribe audio (Whisper - local, gratis)
3. Reescribe diálogos (motor de sinónimos local)
4. Genera nueva voz (Edge TTS - Microsoft, gratis)
5. Compone video final con subtítulos (ffmpeg)

Uso:
    python run_pipeline.py <URL_VIDEO> [--voice VOICE] [--output NOMBRE]

Ejemplo:
    python run_pipeline.py "https://youtube.com/watch?v=XXXXX"
    python run_pipeline.py "https://youtube.com/watch?v=XXXXX" --voice es-ES-AlvaroNeural
"""

import argparse
import asyncio
import json
import os
import sys
import time

# Agregar directorio actual al path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from config import TEMP_DIR, OUTPUT_DIR, TTS_VOICES
from step1_download import download_video, extract_audio
from step2_transcribe import transcribe_audio, segments_to_srt
from step3_rewrite_dialogue import rewrite_all_segments
from step4_generate_audio import generate_all_audio, merge_audio_segments, get_audio_duration
from step5_compose_video import create_subtitle_file, compose_final_video, get_video_duration


def print_banner():
    print("""
╔═══════════════════════════════════════════════════╗
║        🎬 AI VIDEO DUBBING TOOL                  ║
║        100% GRATUITO - Sin APIs de pago           ║
╠═══════════════════════════════════════════════════╣
║  Whisper  → Transcripción (local, gratis)         ║
║  Edge TTS → Voz IA (Microsoft, gratis)            ║
║  ffmpeg   → Edición de video (open source)        ║
║  yt-dlp   → Descarga de videos (open source)      ║
╚═══════════════════════════════════════════════════╝
""")


def run_pipeline(url: str, voice: str = None, output_name: str = "video_doblado"):
    """Ejecuta todo el pipeline de doblaje."""

    print_banner()
    start_time = time.time()

    # ═══ PASO 1: Descargar video ═══
    print("\n" + "=" * 50)
    print("📥 PASO 1/5: Descargando video...")
    print("=" * 50)
    video_path = download_video(url, "video_original")
    audio_path = extract_audio(video_path)
    video_duration = get_video_duration(video_path)
    print(f"   Duración del video: {video_duration:.1f} segundos")

    # ═══ PASO 2: Transcribir ═══
    print("\n" + "=" * 50)
    print("🎤 PASO 2/5: Transcribiendo audio con Whisper...")
    print("=" * 50)
    segments = transcribe_audio(audio_path)
    srt_original = segments_to_srt(segments)
    print(f"   {len(segments)} segmentos de diálogo encontrados")

    # ═══ PASO 3: Reescribir diálogos ═══
    print("\n" + "=" * 50)
    print("✍️ PASO 3/5: Reescribiendo diálogos...")
    print("=" * 50)
    rewritten = rewrite_all_segments(segments, style="narrador")

    print("\n   Comparación de diálogos:")
    for seg in rewritten[:5]:  # Mostrar primeros 5
        print(f"   Original:  {seg['original_text'][:60]}")
        print(f"   Nuevo:     {seg['text'][:60]}")
        print()

    # ═══ PASO 4: Generar audio ═══
    print("\n" + "=" * 50)
    print("🔊 PASO 4/5: Generando voz con IA (Edge TTS)...")
    print("=" * 50)
    audio_files = asyncio.run(generate_all_audio(rewritten, voice))

    # Combinar segmentos de audio
    dubbed_audio_path = os.path.join(TEMP_DIR, "dubbed_audio.wav")
    merge_audio_segments(audio_files, video_duration, dubbed_audio_path)

    # ═══ PASO 5: Componer video final ═══
    print("\n" + "=" * 50)
    print("🎬 PASO 5/5: Componiendo video final...")
    print("=" * 50)
    subtitle_path = create_subtitle_file(rewritten)
    final_video = compose_final_video(
        video_path, dubbed_audio_path, subtitle_path, output_name
    )

    # ═══ RESULTADO ═══
    elapsed = time.time() - start_time
    print("\n" + "=" * 50)
    print("✅ ¡PROCESO COMPLETADO!")
    print("=" * 50)
    print(f"   Video final: {final_video}")
    print(f"   Subtítulos:  {subtitle_path}")
    print(f"   Tiempo total: {elapsed:.1f} segundos")
    print(f"   Duración video: {video_duration:.1f} segundos")

    return final_video


def demo_mode():
    """Modo demo: muestra cómo funciona sin descargar un video."""
    print_banner()
    print("🎯 MODO DEMO - Mostrando el flujo del pipeline\n")

    # Crear segmentos de ejemplo
    demo_segments = [
        {"id": 0, "start": 0.0, "end": 3.5,
         "text": "Este señor sabía que él comía en las praderas"},
        {"id": 1, "start": 3.5, "end": 7.0,
         "text": "Pero ella tenía miedo de ir a la ciudad grande"},
        {"id": 2, "start": 7.0, "end": 11.5,
         "text": "Entonces él decidió escapar porque tenía un problema"},
        {"id": 3, "start": 11.5, "end": 15.0,
         "text": "Al final encontró a su viejo amigo en el pueblo"},
        {"id": 4, "start": 15.0, "end": 19.0,
         "text": "Y después de la guerra ellos vivían en una casa pequeña"},
    ]

    print("📝 Diálogos originales vs reescritos:\n")
    print("-" * 60)

    from step3_rewrite_dialogue import rewrite_all_segments
    rewritten = rewrite_all_segments(demo_segments)

    for seg in rewritten:
        duration = seg["end"] - seg["start"]
        print(f"⏱️  [{seg['start']:.1f}s - {seg['end']:.1f}s] ({duration:.1f}s)")
        print(f"  📌 Original:  {seg['original_text']}")
        print(f"  🔄 Reescrito: {seg['text']}")
        print()

    print("\nVoces disponibles para el doblaje:")
    for name, voice_id in TTS_VOICES.items():
        print(f"  🎙️  {name}: {voice_id}")

    print("\n💡 Para ejecutar con un video real:")
    print("   python run_pipeline.py 'https://youtube.com/watch?v=XXXXX'")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="AI Video Dubbing - Dobla videos con IA (100% gratis)"
    )
    parser.add_argument(
        "url", nargs="?", default=None,
        help="URL del video a doblar (YouTube, etc.)"
    )
    parser.add_argument(
        "--voice", "-v", default=None,
        help=f"Voz de Edge TTS (default: {TTS_VOICES['es_male']})"
    )
    parser.add_argument(
        "--output", "-o", default="video_doblado",
        help="Nombre del archivo de salida"
    )
    parser.add_argument(
        "--demo", action="store_true",
        help="Ejecutar en modo demo sin descargar video"
    )

    args = parser.parse_args()

    if args.demo or args.url is None:
        demo_mode()
    else:
        run_pipeline(args.url, args.voice, args.output)
