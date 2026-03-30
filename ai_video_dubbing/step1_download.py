"""
PASO 1: Descargar video de YouTube u otra fuente.
Usa yt-dlp (gratuito, open source).
"""

import os
import subprocess
import sys
from config import DOWNLOADS_DIR


def download_video(url: str, output_name: str = "video_original") -> str:
    """
    Descarga un video de YouTube u otra plataforma.

    Args:
        url: URL del video (YouTube, Vimeo, etc.)
        output_name: Nombre del archivo de salida (sin extensin)

    Returns:
        Ruta al archivo descargado
    """
    output_path = os.path.join(DOWNLOADS_DIR, f"{output_name}.mp4")

    cmd = [
        "yt-dlp",
        "--no-check-certificates",
        "-f", "bestvideo[height<=720]+bestaudio/best[height<=720]",
        "--merge-output-format", "mp4",
        "-o", output_path,
        "--no-playlist",
        url
    ]

    print(f"[*] Descargando video: {url}")
    result = subprocess.run(cmd, capture_output=True, text=True)

    if result.returncode != 0:
        print(f"[!] Error descargando: {result.stderr}")
        # Intentar formato ms simple
        cmd_simple = [
            "yt-dlp",
            "--no-check-certificates",
            "-f", "best[height<=720]",
            "-o", output_path,
            "--no-playlist",
            url
        ]
        result = subprocess.run(cmd_simple, capture_output=True, text=True)
        if result.returncode != 0:
            raise RuntimeError(f"No se pudo descargar el video: {result.stderr}")

    print(f"[] Video descargado: {output_path}")
    return output_path


def extract_audio(video_path: str) -> str:
    """
    Extrae el audio de un video usando ffmpeg.

    Returns:
        Ruta al archivo de audio WAV
    """
    audio_path = video_path.rsplit(".", 1)[0] + ".wav"

    cmd = [
        "ffmpeg", "-y",
        "-i", video_path,
        "-vn",
        "-acodec", "pcm_s16le",
        "-ar", "16000",
        "-ac", "1",
        audio_path
    ]

    print(f"[*] Extrayendo audio...")
    result = subprocess.run(cmd, capture_output=True, text=True)

    if result.returncode != 0:
        raise RuntimeError(f"Error extrayendo audio: {result.stderr}")

    print(f"[] Audio extrado: {audio_path}")
    return audio_path


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Uso: python step1_download.py <URL_DEL_VIDEO>")
        sys.exit(1)

    video = download_video(sys.argv[1])
    audio = extract_audio(video)
    print(f"\nArchivos generados:")
    print(f"  Video: {video}")
    print(f"  Audio: {audio}")
