"""
PASO 3: Reescribir los dilogos manteniendo el mismo timing.
Cambia las palabras pero mantiene el significado y la duracin similar.
"""

import json
import os
import sys
import re
from config import TEMP_DIR


def estimate_speech_duration(text: str, chars_per_second: float = 14.0) -> float:
    """Estima cuntos segundos toma decir un texto en espaol."""
    return len(text) / chars_per_second


def rewrite_segment(text: str, target_duration: float, style: str = "narrador") -> str:
    """
    Reescribe un segmento de dilogo para que tenga duracin similar.
    Usa sinnimos y parfrasis para cambiar el texto.

    Args:
        text: Texto original
        target_duration: Duracin objetivo en segundos
        style: Estilo de reescritura
    """
    # Diccionario de sinnimos/reemplazos comunes en espaol
    replacements = {
        # Pronombres y referencias
        "l": "este sujeto",
        "ella": "esta persona",
        "ellos": "estos individuos",
        "este seor": "este sujeto",
        "este hombre": "este individuo",
        "esta mujer": "esta persona",
        "el protagonista": "nuestro personaje",
        "la protagonista": "nuestra protagonista",

        # Verbos comunes
        "saba que": "tena conocimiento de que",
        "dijo que": "mencion que",
        "fue a": "se dirigi a",
        "quera": "deseaba",
        "tena": "posea",
        "poda": "era capaz de",
        "haca": "realizaba",
        "vea": "observaba",
        "coma": "se alimentaba",
        "viva": "resida",
        "trabajaba": "laboraba",
        "pensaba": "reflexionaba",
        "senta": "experimentaba",
        "llamaba": "denominaba",
        "encontr": "hall",
        "descubri": "se percat de",
        "decidi": "opt por",
        "intent": "trat de",
        "logr": "consigui",
        "muri": "falleci",
        "mat": "elimin",
        "escap": "huy",
        "lleg": "arrib",
        "sali": "parti",

        # Sustantivos
        "casa": "hogar",
        "dinero": "capital",
        "problema": "inconveniente",
        "amigo": "compaero",
        "enemigo": "adversario",
        "familia": "ncleo familiar",
        "pueblo": "localidad",
        "ciudad": "metrpoli",
        "pas": "nacin",
        "mundo": "planeta",
        "vida": "existencia",
        "muerte": "deceso",
        "guerra": "conflicto blico",
        "pelea": "confrontacin",
        "amor": "afecto",
        "miedo": "temor",
        "peligro": "riesgo",

        # Adjetivos
        "grande": "enorme",
        "pequeo": "diminuto",
        "bueno": "favorable",
        "malo": "desfavorable",
        "importante": "relevante",
        "difcil": "complicado",
        "fcil": "sencillo",
        "rpido": "veloz",
        "lento": "pausado",
        "fuerte": "robusto",
        "dbil": "frgil",
        "rico": "adinerado",
        "pobre": "humilde",
        "viejo": "anciano",
        "joven": "juvenil",
        "nuevo": "reciente",

        # Conectores y expresiones
        "pero": "sin embargo",
        "porque": "debido a que",
        "entonces": "en consecuencia",
        "despus": "posteriormente",
        "antes": "previamente",
        "mientras": "entre tanto",
        "tambin": "adems",
        "sin embargo": "no obstante",
        "por eso": "por tal motivo",
        "al final": "finalmente",
        "de repente": "sbitamente",
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

    # Ajustar longitud si es muy diferente a la duracin objetivo
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
    Reescribe todos los segmentos de dilogo.

    Args:
        segments: Lista de segmentos con start, end, text
        style: Estilo de narracin

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

    print(f"[] Dilogos reescritos guardados: {json_path}")
    return rewritten_segments


if __name__ == "__main__":
    # Cargar transcripcin existente
    json_path = os.path.join(TEMP_DIR, "transcription.json")

    if not os.path.exists(json_path):
        print("[!] No se encontr transcription.json. Ejecuta step2 primero.")
        sys.exit(1)

    with open(json_path, "r", encoding="utf-8") as f:
        data = json.load(f)

    style = sys.argv[1] if len(sys.argv) > 1 else "narrador"
    rewritten = rewrite_all_segments(data["segments"], style)

    print(f"\nComparacin de dilogos:")
    print("-" * 60)
    for seg in rewritten:
        print(f"[{seg['start']:.1f}s - {seg['end']:.1f}s]")
        print(f"  Original:   {seg['original_text']}")
        print(f"  Reescrito:  {seg['text']}")
        print()
