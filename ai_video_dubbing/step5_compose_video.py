"""
PASO 5: Componer el video final.
- Reemplaza el audio original con el nuevo doblaje
- Agrega subtítulos quemados en el video
- Exporta el resultado final
"""

import json
import os
import subprocess
import sys
from config import (
    TEMP_DIR, OUTPUT_DIR, DOWNLOADS_DIR,
    SUBTITLE_FONT, SUBTITLE_FONTSIZE, SUBTITLE_COLOR
)


def create_subtitle_file(segments: list, output_path: str = None) -> str:
    """Crea archivo SRT con los diálogos reescritos."""
    if output_path is None:
        output_path = os.path.join(TEMP_DIR, "subtitles_new.srt")

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

    print(f"[✓] Subtítulos creados: {output_path}")
    return output_path


def get_video_duration(video_path: str) -> float:
    """Obtiene la duración del video."""
    cmd = [
        "ffprobe", "-v", "quiet",
        "-show_entries", "format=duration",
        "-of", "csv=p=0",
        video_path
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    return float(result.stdout.strip())


def compose_final_video(
    video_path: str,
    new_audio_path: str,
    subtitle_path: str,
    output_name: str = "video_doblado"
) -> str:
    """
    Compone el video final con nuevo audio y subtítulos.

    Args:
        video_path: Ruta al video original
        new_audio_path: Ruta al audio del nuevo doblaje
        subtitle_path: Ruta al archivo SRT de subtítulos
        output_name: Nombre del archivo de salida
    """
    output_path = os.path.join(OUTPUT_DIR, f"{output_name}.mp4")

    # Escapar la ruta de subtítulos para el filtro de ffmpeg
    sub_path_escaped = subtitle_path.replace("\\", "/").replace(":", "\\:")

    # Componer video: video original + nuevo audio + subtítulos quemados
    cmd = [
        "ffmpeg", "-y",
        "-i", video_path,
        "-i", new_audio_path,
        "-map", "0:v:0",       # Video del primer input
        "-map", "1:a:0",       # Audio del segundo input
        "-c:v", "libx264",
        "-preset", "fast",
        "-crf", "23",
        "-vf", (
            f"subtitles={sub_path_escaped}:"
            f"force_style='FontName={SUBTITLE_FONT},"
            f"FontSize={SUBTITLE_FONTSIZE},"
            f"PrimaryColour=&H00FFFFFF,"
            f"OutlineColour=&H00000000,"
            f"BorderStyle=3,"
            f"Outline=1,"
            f"Shadow=0,"
            f"BackColour=&H80000000,"
            f"MarginV=30'"
        ),
        "-c:a", "aac",
        "-b:a", "192k",
        "-shortest",
        output_path
    ]

    print(f"[*] Componiendo video final...")
    print(f"    Video: {video_path}")
    print(f"    Audio: {new_audio_path}")
    print(f"    Subtítulos: {subtitle_path}")

    result = subprocess.run(cmd, capture_output=True, text=True)

    if result.returncode != 0:
        print(f"[!] Error con subtítulos quemados, intentando sin subtítulos...")
        # Fallback: sin subtítulos quemados, copiar SRT aparte
        cmd_simple = [
            "ffmpeg", "-y",
            "-i", video_path,
            "-i", new_audio_path,
            "-map", "0:v:0",
            "-map", "1:a:0",
            "-c:v", "libx264",
            "-preset", "fast",
            "-crf", "23",
            "-c:a", "aac",
            "-b:a", "192k",
            "-shortest",
            output_path
        ]
        result = subprocess.run(cmd_simple, capture_output=True, text=True)

        if result.returncode != 0:
            raise RuntimeError(f"Error componiendo video: {result.stderr}")

        # Copiar subtítulos junto al video
        srt_output = os.path.join(OUTPUT_DIR, f"{output_name}.srt")
        subprocess.run(["cp", subtitle_path, srt_output])
        print(f"[✓] Subtítulos copiados: {srt_output}")

    print(f"[✓] Video final: {output_path}")
    return output_path


def compose_without_new_audio(
    video_path: str,
    subtitle_path: str,
    output_name: str = "video_subtitulado"
) -> str:
    """
    Versión simplificada: solo agrega subtítulos al video original.
    """
    output_path = os.path.join(OUTPUT_DIR, f"{output_name}.mp4")
    sub_path_escaped = subtitle_path.replace("\\", "/").replace(":", "\\:")

    cmd = [
        "ffmpeg", "-y",
        "-i", video_path,
        "-vf", f"subtitles={sub_path_escaped}:force_style='FontSize={SUBTITLE_FONTSIZE}'",
        "-c:v", "libx264",
        "-preset", "fast",
        "-c:a", "copy",
        output_path
    ]

    print(f"[*] Agregando subtítulos al video...")
    result = subprocess.run(cmd, capture_output=True, text=True)

    if result.returncode != 0:
        raise RuntimeError(f"Error: {result.stderr}")

    print(f"[✓] Video subtitulado: {output_path}")
    return output_path


if __name__ == "__main__":
    # Buscar archivos necesarios
    segments_path = os.path.join(TEMP_DIR, "rewritten_segments.json")
    audio_meta_path = os.path.join(TEMP_DIR, "audio_metadata.json")

    if not os.path.exists(segments_path):
        print("[!] Ejecuta los pasos anteriores primero.")
        sys.exit(1)

    with open(segments_path, "r", encoding="utf-8") as f:
        segments = json.load(f)

    # Crear subtítulos
    srt_path = create_subtitle_file(segments)

    # Buscar video original
    video_path = None
    for f in os.listdir(DOWNLOADS_DIR):
        if f.endswith(".mp4"):
            video_path = os.path.join(DOWNLOADS_DIR, f)
            break

    if not video_path:
        print("[!] No se encontró el video original en downloads/")
        sys.exit(1)

    # Buscar audio combinado
    audio_path = os.path.join(TEMP_DIR, "dubbed_audio.wav")

    if os.path.exists(audio_path):
        compose_final_video(video_path, audio_path, srt_path)
    else:
        print("[!] No se encontró audio doblado, usando solo subtítulos")
        compose_without_new_audio(video_path, srt_path)
