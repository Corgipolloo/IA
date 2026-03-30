"""
PASO 2: Transcribir el audio usando Whisper (OpenAI, gratuito y local).
Genera subttulos con timestamps exactos.
"""

import os
import json
import sys
import whisper
from config import TEMP_DIR, WHISPER_MODEL


def transcribe_audio(audio_path: str, language: str = None) -> list:
    """
    Transcribe audio usando Whisper y devuelve segmentos con timestamps.

    Args:
        audio_path: Ruta al archivo de audio
        language: Idioma del audio (None para autodetectar)

    Returns:
        Lista de segmentos: [{"start": float, "end": float, "text": str}, ...]
    """
    print(f"[*] Cargando modelo Whisper '{WHISPER_MODEL}'...")
    model = whisper.load_model(WHISPER_MODEL)

    print(f"[*] Transcribiendo audio...")
    options = {"verbose": False}
    if language:
        options["language"] = language

    result = model.transcribe(audio_path, **options)

    segments = []
    for seg in result["segments"]:
        segments.append({
            "id": seg["id"],
            "start": round(seg["start"], 2),
            "end": round(seg["end"], 2),
            "text": seg["text"].strip(),
        })

    detected_lang = result.get("language", "desconocido")
    print(f"[] Transcripcin completa. Idioma detectado: {detected_lang}")
    print(f"[] {len(segments)} segmentos encontrados")

    # Guardar transcripcin como JSON
    json_path = os.path.join(TEMP_DIR, "transcription.json")
    with open(json_path, "w", encoding="utf-8") as f:
        json.dump({
            "language": detected_lang,
            "segments": segments,
            "full_text": result["text"]
        }, f, ensure_ascii=False, indent=2)

    print(f"[] Transcripcin guardada: {json_path}")
    return segments


def segments_to_srt(segments: list, output_path: str = None) -> str:
    """
    Convierte segmentos a formato SRT de subttulos.
    """
    if output_path is None:
        output_path = os.path.join(TEMP_DIR, "subtitles_original.srt")

    def format_time(seconds: float) -> str:
        h = int(seconds // 3600)
        m = int((seconds % 3600) // 60)
        s = int(seconds % 60)
        ms = int((seconds % 1) * 1000)
        return f"{h:02d}:{m:02d}:{s:02d},{ms:03d}"

    lines = []
    for i, seg in enumerate(segments, 1):
        lines.append(str(i))
        lines.append(f"{format_time(seg['start'])} --> {format_time(seg['end'])}")
        lines.append(seg["text"])
        lines.append("")

    with open(output_path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))

    print(f"[] Subttulos SRT guardados: {output_path}")
    return output_path


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Uso: python step2_transcribe.py <RUTA_AUDIO>")
        sys.exit(1)

    segments = transcribe_audio(sys.argv[1])
    srt_path = segments_to_srt(segments)

    print(f"\nTranscripcin:")
    for seg in segments:
        print(f"  [{seg['start']:.1f}s - {seg['end']:.1f}s] {seg['text']}")
