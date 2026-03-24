"""
PASO 4: Generar audio con voz IA usando Edge TTS (Microsoft, gratuito).
Cada segmento se genera con la duración correcta.
"""

import asyncio
import json
import os
import subprocess
import sys
import edge_tts
from config import TEMP_DIR, DEFAULT_VOICE, TTS_VOICES


async def generate_segment_audio(text: str, output_path: str, voice: str = None) -> str:
    """
    Genera audio TTS para un segmento de texto.

    Args:
        text: Texto a convertir en audio
        output_path: Ruta de salida del archivo MP3
        voice: Voz a usar (default: es-MX-JorgeNeural)
    """
    if voice is None:
        voice = DEFAULT_VOICE

    communicate = edge_tts.Communicate(text, voice)
    await communicate.save(output_path)
    return output_path


def get_audio_duration(audio_path: str) -> float:
    """Obtiene la duración de un archivo de audio usando ffprobe."""
    cmd = [
        "ffprobe", "-v", "quiet",
        "-show_entries", "format=duration",
        "-of", "csv=p=0",
        audio_path
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    return float(result.stdout.strip())


def adjust_audio_speed(input_path: str, output_path: str, target_duration: float) -> str:
    """
    Ajusta la velocidad del audio para que coincida con la duración objetivo.
    Usa ffmpeg atempo filter.
    """
    current_duration = get_audio_duration(input_path)

    if current_duration <= 0:
        return input_path

    speed_factor = current_duration / target_duration

    # atempo acepta valores entre 0.5 y 2.0
    # Para factores fuera de rango, encadenar filtros
    if speed_factor < 0.5:
        speed_factor = 0.5
    elif speed_factor > 2.0:
        speed_factor = 2.0

    cmd = [
        "ffmpeg", "-y",
        "-i", input_path,
        "-filter:a", f"atempo={speed_factor}",
        "-vn",
        output_path
    ]

    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"[!] Error ajustando velocidad: {result.stderr}")
        return input_path

    return output_path


async def generate_all_audio(segments: list, voice: str = None) -> list:
    """
    Genera audio para todos los segmentos y ajusta la duración.

    Args:
        segments: Lista de segmentos reescritos
        voice: Voz de Edge TTS a usar

    Returns:
        Lista de rutas a archivos de audio generados
    """
    audio_dir = os.path.join(TEMP_DIR, "audio_segments")
    os.makedirs(audio_dir, exist_ok=True)

    audio_files = []

    print(f"[*] Generando audio para {len(segments)} segmentos...")

    for i, seg in enumerate(segments):
        raw_path = os.path.join(audio_dir, f"segment_{i:04d}_raw.mp3")
        final_path = os.path.join(audio_dir, f"segment_{i:04d}.mp3")

        # Generar audio TTS
        await generate_segment_audio(seg["text"], raw_path, voice)

        # Ajustar velocidad para que coincida con el timing original
        target_duration = seg["end"] - seg["start"]
        if target_duration > 0.5:
            adjust_audio_speed(raw_path, final_path, target_duration)
        else:
            final_path = raw_path

        audio_files.append({
            "segment_id": seg["id"],
            "start": seg["start"],
            "end": seg["end"],
            "audio_path": final_path,
            "text": seg["text"],
        })

        print(f"  [{i+1}/{len(segments)}] Segmento generado: {seg['text'][:50]}...")

    # Guardar metadata
    meta_path = os.path.join(TEMP_DIR, "audio_metadata.json")
    with open(meta_path, "w", encoding="utf-8") as f:
        json.dump(audio_files, f, ensure_ascii=False, indent=2)

    print(f"[✓] Audio generado para todos los segmentos")
    return audio_files


def merge_audio_segments(audio_files: list, total_duration: float, output_path: str) -> str:
    """
    Combina todos los segmentos de audio en una sola pista,
    respetando los tiempos de inicio de cada segmento.
    """
    # Crear audio de silencio base
    silence_path = os.path.join(TEMP_DIR, "silence_base.wav")
    cmd = [
        "ffmpeg", "-y",
        "-f", "lavfi",
        "-i", f"anullsrc=r=44100:cl=mono",
        "-t", str(total_duration),
        silence_path
    ]
    subprocess.run(cmd, capture_output=True, text=True)

    # Construir filtro para mezclar todos los segmentos
    inputs = ["-i", silence_path]
    filter_parts = []

    for i, af in enumerate(audio_files):
        inputs.extend(["-i", af["audio_path"]])
        delay_ms = int(af["start"] * 1000)
        filter_parts.append(f"[{i+1}]adelay={delay_ms}|{delay_ms}[d{i}]")

    # Mezclar todo
    mix_inputs = "[0]" + "".join(f"[d{i}]" for i in range(len(audio_files)))
    filter_parts.append(f"{mix_inputs}amix=inputs={len(audio_files)+1}:duration=longest")

    filter_str = ";".join(filter_parts)

    cmd = ["ffmpeg", "-y"] + inputs + [
        "-filter_complex", filter_str,
        output_path
    ]

    print(f"[*] Combinando segmentos de audio...")
    result = subprocess.run(cmd, capture_output=True, text=True)

    if result.returncode != 0:
        print(f"[!] Error combinando audio: {result.stderr[:500]}")
        raise RuntimeError("Error al combinar audio")

    print(f"[✓] Audio combinado: {output_path}")
    return output_path


if __name__ == "__main__":
    json_path = os.path.join(TEMP_DIR, "rewritten_segments.json")

    if not os.path.exists(json_path):
        print("[!] No se encontró rewritten_segments.json. Ejecuta step3 primero.")
        sys.exit(1)

    with open(json_path, "r", encoding="utf-8") as f:
        segments = json.load(f)

    voice = sys.argv[1] if len(sys.argv) > 1 else None
    audio_files = asyncio.run(generate_all_audio(segments, voice))

    print(f"\n[✓] {len(audio_files)} segmentos de audio generados")
    print(f"\nVoces disponibles:")
    for name, voice_id in TTS_VOICES.items():
        print(f"  {name}: {voice_id}")
