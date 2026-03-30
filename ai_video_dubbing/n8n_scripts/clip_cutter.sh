#!/usr/bin/env bash
# clip_cutter.sh
# Splits a video into clips at silence points near 180-second boundaries.
# Adds "Parte X de Y" overlay to each clip.
#
# Usage:
#   ./clip_cutter.sh <input_video> <output_directory> [target_seconds]
#
# Arguments:
#   input_video     Path to the source video file
#   output_directory  Directory where clip_01.mp4, clip_02.mp4, ... will be written
#   target_seconds  Target clip length in seconds (default: 180)

set -euo pipefail

# ── Configuration ────────────────────────────────────────────────────────────
SILENCE_THRESHOLD="-30dB"   # dB threshold for silence detection
SILENCE_MIN_DURATION="0.5"  # minimum silence duration in seconds
SEARCH_WINDOW=30            # search for silence within +/- this many seconds of boundary
DEFAULT_TARGET=180

# ── Logging ──────────────────────────────────────────────────────────────────
log()  { echo "[clip_cutter] $(date '+%H:%M:%S') $*"; }
err()  { echo "[clip_cutter] ERROR: $*" >&2; }
die()  { err "$@"; exit 1; }

# ── Argument parsing ─────────────────────────────────────────────────────────
if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <input_video> <output_directory> [target_seconds]"
    exit 1
fi

INPUT_VIDEO="$1"
OUTPUT_DIR="$2"
TARGET_SECONDS="${3:-$DEFAULT_TARGET}"

[[ -f "$INPUT_VIDEO" ]] || die "Input video not found: $INPUT_VIDEO"

mkdir -p "$OUTPUT_DIR"
log "Input: $INPUT_VIDEO"
log "Output directory: $OUTPUT_DIR"
log "Target clip length: ${TARGET_SECONDS}s"

# ── Get video duration ───────────────────────────────────────────────────────
VIDEO_DURATION=$(ffprobe -v error -show_entries format=duration \
    -of default=noprint_wrappers=1:nokey=1 "$INPUT_VIDEO")

if [[ -z "$VIDEO_DURATION" ]] || [[ "$VIDEO_DURATION" == "N/A" ]]; then
    die "Could not determine video duration"
fi

# Strip decimal for integer comparison but keep full precision
VIDEO_DURATION_INT=$(printf "%.0f" "$VIDEO_DURATION")
log "Video duration: ${VIDEO_DURATION}s (${VIDEO_DURATION_INT}s rounded)"

# ── Detect silence points ───────────────────────────────────────────────────
log "Detecting silence points (threshold=${SILENCE_THRESHOLD}, min_duration=${SILENCE_MIN_DURATION}s)..."

SILENCE_LOG=$(mktemp /tmp/silence_XXXXXX.log)
trap 'rm -f "$SILENCE_LOG"' EXIT

ffmpeg -i "$INPUT_VIDEO" \
    -af "silencedetect=noise=${SILENCE_THRESHOLD}:d=${SILENCE_MIN_DURATION}" \
    -f null - 2>"$SILENCE_LOG"

# Extract silence_end timestamps (midpoint of each silence region is the ideal cut)
# Format: [silencedetect @ ...] silence_end: 45.123 | silence_duration: 0.8
SILENCE_POINTS=()
while IFS= read -r line; do
    if [[ "$line" =~ silence_start:\ ([0-9.]+) ]]; then
        s_start="${BASH_REMATCH[1]}"
    fi
    if [[ "$line" =~ silence_end:\ ([0-9.]+) ]]; then
        s_end="${BASH_REMATCH[1]}"
        # Use the midpoint of the silence region as the cut point
        if [[ -n "${s_start:-}" ]]; then
            midpoint=$(echo "scale=3; ($s_start + $s_end) / 2" | bc)
            SILENCE_POINTS+=("$midpoint")
        else
            SILENCE_POINTS+=("$s_end")
        fi
        s_start=""
    fi
done < "$SILENCE_LOG"

log "Found ${#SILENCE_POINTS[@]} silence points"

# ── Choose cut points near target boundaries ─────────────────────────────────
find_best_silence_near() {
    local target="$1"
    local best=""
    local best_dist=999999

    local window_low
    local window_high
    window_low=$(echo "scale=3; $target - $SEARCH_WINDOW" | bc)
    window_high=$(echo "scale=3; $target + $SEARCH_WINDOW" | bc)

    for sp in "${SILENCE_POINTS[@]}"; do
        # Check if silence point is within the search window
        local in_window
        in_window=$(echo "$sp >= $window_low && $sp <= $window_high" | bc -l)
        if [[ "$in_window" -eq 1 ]]; then
            local dist
            dist=$(echo "scale=3; d=$sp - $target; if (d < 0) -d else d" | bc)
            local is_closer
            is_closer=$(echo "$dist < $best_dist" | bc -l)
            if [[ "$is_closer" -eq 1 ]]; then
                best_dist="$dist"
                best="$sp"
            fi
        fi
    done

    echo "$best"
}

CUT_POINTS=()
boundary="$TARGET_SECONDS"

while (( $(echo "$boundary < $VIDEO_DURATION" | bc -l) )); do
    best=$(find_best_silence_near "$boundary")
    if [[ -n "$best" ]]; then
        log "Boundary ~${boundary}s -> cut at ${best}s (silence)"
        CUT_POINTS+=("$best")
    else
        # No silence found near this boundary; use the exact boundary as fallback
        log "Boundary ~${boundary}s -> no silence found, cutting at ${boundary}s (fallback)"
        CUT_POINTS+=("$boundary")
    fi
    boundary=$(echo "scale=3; ${CUT_POINTS[-1]} + $TARGET_SECONDS" | bc)
done

TOTAL_CLIPS=$(( ${#CUT_POINTS[@]} + 1 ))
log "Splitting into $TOTAL_CLIPS clips"

# ── Split video at cut points ───────────────────────────────────────────────
split_clip() {
    local clip_num="$1"
    local start_time="$2"
    local end_time="$3"  # empty string means end of file
    local total="$4"
    local output_file="$5"

    local parte_text="Parte ${clip_num} de ${total}"
    log "Extracting clip ${clip_num}/${total}: ${start_time}s -> ${end_time:-END}s"

    # Build the drawtext filter for "Parte X de Y" overlay
    # Show it for the first 5 seconds of each clip, top-right corner
    local drawtext_filter
    drawtext_filter="drawtext=text='${parte_text}':"
    drawtext_filter+="fontcolor=white:fontsize=48:"
    drawtext_filter+="font=Arial:"
    drawtext_filter+="borderw=3:bordercolor=black:"
    drawtext_filter+="x=w-text_w-40:y=40:"
    drawtext_filter+="enable='between(t,0,5)':"
    drawtext_filter+="alpha='if(lt(t,0.5),t/0.5,if(gt(t,4.5),(5-t)/0.5,1))'"

    local duration_args=""
    if [[ -n "$end_time" ]]; then
        local dur
        dur=$(echo "scale=3; $end_time - $start_time" | bc)
        duration_args="-t $dur"
    fi

    ffmpeg -y -ss "$start_time" -i "$INPUT_VIDEO" \
        $duration_args \
        -vf "$drawtext_filter" \
        -c:v libx264 -preset fast -crf 18 \
        -c:a aac -b:a 192k \
        -avoid_negative_ts make_zero \
        "$output_file"

    if [[ -f "$output_file" ]]; then
        local size
        size=$(du -h "$output_file" | cut -f1)
        log "  -> $output_file ($size)"
    else
        err "Failed to create $output_file"
        return 1
    fi
}

clip_index=1
prev_cut="0"

for cut in "${CUT_POINTS[@]}"; do
    output_file=$(printf "%s/clip_%02d.mp4" "$OUTPUT_DIR" "$clip_index")
    split_clip "$clip_index" "$prev_cut" "$cut" "$TOTAL_CLIPS" "$output_file"
    prev_cut="$cut"
    clip_index=$((clip_index + 1))
done

# Last clip: from final cut point to end of video
output_file=$(printf "%s/clip_%02d.mp4" "$OUTPUT_DIR" "$clip_index")
split_clip "$clip_index" "$prev_cut" "" "$TOTAL_CLIPS" "$output_file"

# ── Summary ──────────────────────────────────────────────────────────────────
log "Done. Created $TOTAL_CLIPS clips in $OUTPUT_DIR:"
for f in "$OUTPUT_DIR"/clip_*.mp4; do
    dur=$(ffprobe -v error -show_entries format=duration \
        -of default=noprint_wrappers=1:nokey=1 "$f" 2>/dev/null || echo "?")
    echo "  $(basename "$f")  ${dur}s"
done
