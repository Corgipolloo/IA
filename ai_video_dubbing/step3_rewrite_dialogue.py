"""
PASO 3: Reescribir los diálogos manteniendo el mismo timing.
Cambia las palabras pero mantiene el significado y la duración similar.
"""

import json
import os
import sys
import re
from config import TEMP_DIR


def estimate_speech_duration(text: str, chars_per_second: float = 14.0) -> float:
    """Estima cuántos segundos toma decir un texto en español."""
    return len(text) / chars_per_second


def rewrite_segment(text: str, target_duration: float, style: str = "narrador") -> str:
    """
    Reescribe un segmento de diálogo para que tenga duración similar.
    Usa sinónimos y paráfrasis para cambiar el texto.

    Args:
        text: Texto original
        target_duration: Duración objetivo en segundos
        style: Estilo de reescritura
    """
    # Diccionario de sinónimos/reemplazos comunes en español
    replacements = {
        # Pronombres y referencias
        "él": "este sujeto",
        "ella": "esta persona",
        "ellos": "estos individuos",
        "este señor": "este sujeto",
        "este hombre": "este individuo",
        "esta mujer": "esta persona",
        "el protagonista": "nuestro personaje",
        "la protagonista": "nuestra protagonista",

        # Verbos comunes
        "sabía que": "tenía conocimiento de que",
        "dijo que": "mencionó que",
        "fue a": "se dirigió a",
        "quería": "deseaba",
        "tenía": "poseía",
        "podía": "era capaz de",
        "hacía": "realizaba",
        "veía": "observaba",
        "comía": "se alimentaba",
        "vivía": "residía",
        "trabajaba": "laboraba",
        "pensaba": "reflexionaba",
        "sentía": "experimentaba",
        "llamaba": "denominaba",
        "encontró": "halló",
        "descubrió": "se percató de",
        "decidió": "optó por",
        "intentó": "trató de",
        "logró": "consiguió",
        "murió": "falleció",
        "mató": "eliminó",
        "escapó": "huyó",
        "llegó": "arribó",
        "salió": "partió",

        # Sustantivos
        "casa": "hogar",
        "dinero": "capital",
        "problema": "inconveniente",
        "amigo": "compañero",
        "enemigo": "adversario",
        "familia": "núcleo familiar",
        "pueblo": "localidad",
        "ciudad": "metrópoli",
        "país": "nación",
        "mundo": "planeta",
        "vida": "existencia",
        "muerte": "deceso",
        "guerra": "conflicto bélico",
        "pelea": "confrontación",
        "amor": "afecto",
        "miedo": "temor",
        "peligro": "riesgo",

        # Adjetivos
        "grande": "enorme",
        "pequeño": "diminuto",
        "bueno": "favorable",
        "malo": "desfavorable",
        "importante": "relevante",
        "difícil": "complicado",
        "fácil": "sencillo",
        "rápido": "veloz",
        "lento": "pausado",
        "fuerte": "robusto",
        "débil": "frágil",
        "rico": "adinerado",
        "pobre": "humilde",
        "viejo": "anciano",
        "joven": "juvenil",
        "nuevo": "reciente",

        # Conectores y expresiones
        "pero": "sin embargo",
        "porque": "debido a que",
        "entonces": "en consecuencia",
        "después": "posteriormente",
        "antes": "previamente",
        "mientras": "entre tanto",
        "también": "además",
        "sin embargo": "no obstante",
        "por eso": "por tal motivo",
        "al final": "finalmente",
        "de repente": "súbitamente",
        "en ese momento": "en aquel instante",
        "por ejemplo": "a modo de ejemplo",
        "es decir": "en otras palabras",
    }

    rewritten = text.lower()

    # Aplicar reemplazos (ordenados por longitud para evitar conflictos)
    sorted_replacements = sorted(replacements.items(), key=lambda x: len(x[0]), reverse=True)

    for original, replacement in sorted_replacements:
        # Usar regex con word boundaries para reemplazar palabras completas
        pattern = re.compile(r'\b' + re.escape(original) + r'\b', re.IGNORECASE)
        rewritten = pattern.sub(replacement, rewritten)

    # Capitalizar primera letra
    if rewritten:
        rewritten = rewritten[0].upper() + rewritten[1:]

    # Ajustar longitud si es muy diferente a la duración objetivo
    estimated_duration = estimate_speech_duration(rewritten)

    if estimated_duration > target_duration * 1.3:
        # Texto muy largo, acortar manteniendo palabras completas
        words = rewritten.split()
        target_chars = int(target_duration * 14.0)
        result_words = []
        current_len = 0
        for word in words:
            if current_len + len(word) + 1 > target_chars and len(result_words) >= 3:
                break
            result_words.append(word)
            current_len += len(word) + 1
        rewritten = " ".join(result_words)
        if not rewritten.endswith((".", "!", "?")):
            rewritten += "."

    return rewritten


def rewrite_all_segments(segments: list, style: str = "narrador") -> list:
    """
    Reescribe todos los segmentos de diálogo.

    Args:
        segments: Lista de segmentos con start, end, text
        style: Estilo de narración

    Returns:
        Lista de segmentos reescritos con el mismo timing
    """
    print(f"[*] Reescribiendo {len(segments)} segmentos...")

    rewritten_segments = []
    for seg in segments:
        duration = seg["end"] - seg["start"]
        new_text = rewrite_segment(seg["text"], duration, style)

        rewritten_segments.append({
            "id": seg["id"],
            "start": seg["start"],
            "end": seg["end"],
            "original_text": seg["text"],
            "text": new_text,
        })

    # Guardar segmentos reescritos
    json_path = os.path.join(TEMP_DIR, "rewritten_segments.json")
    with open(json_path, "w", encoding="utf-8") as f:
        json.dump(rewritten_segments, f, ensure_ascii=False, indent=2)

    print(f"[✓] Diálogos reescritos guardados: {json_path}")
    return rewritten_segments


if __name__ == "__main__":
    # Cargar transcripción existente
    json_path = os.path.join(TEMP_DIR, "transcription.json")

    if not os.path.exists(json_path):
        print("[!] No se encontró transcription.json. Ejecuta step2 primero.")
        sys.exit(1)

    with open(json_path, "r", encoding="utf-8") as f:
        data = json.load(f)

    style = sys.argv[1] if len(sys.argv) > 1 else "narrador"
    rewritten = rewrite_all_segments(data["segments"], style)

    print(f"\nComparación de diálogos:")
    print("-" * 60)
    for seg in rewritten:
        print(f"[{seg['start']:.1f}s - {seg['end']:.1f}s]")
        print(f"  Original:   {seg['original_text']}")
        print(f"  Reescrito:  {seg['text']}")
        print()
