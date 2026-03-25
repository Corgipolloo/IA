#!/usr/bin/env bash
# sync_audio.sh
# Combines a muted video with individually timed audio segments into a dubbed video.
#
# Usage:
#   ./sync_audio.sh <muted_video> <audio_dir> <timestamps_json> [output_file]
#
# Arguments:
#   muted_video      Path to the video file (should have no audio or audio will be replaced)
#   audio_dir        Directory containing audio segment files (segment_001.wav, segment_002.wav, ...)
#   timestamps_json  JSON file with array: [{"file": "segment_001.wav", "start": 1.5}, ...]
#   output_file      Output path (default: video_dubbed.mp4 in same dir as muted_video)
#
# The timestamps JSON format:
#   [
#     {"file": "segment_001.wav", "start": 0.0},
#     {"file": "segment_002.wav", "start": 3.5},
#     ...
#   ]
#   "start" is in seconds - where this audio segment should begin in the timeline.

set -euo pipefail

# ── Logging ──────────────────────────────────────────────────────────────────
log()  { echo "[sync_audio] $(date '+%H:%M:%S') $*"; }
err()  { echo "[sync_audio] ERROR: $*" >&2; }
die()  { err "$@"; exit 1; }

# ── Argument parsing ─────────────────────────────────────────────────────────
if [[ $# -lt 3 ]]; then
    echo "Usage: $0 <muted_video> <audio_dir> <timestamps_json> [output_file]"
    exit 1
fi

MUTED_VIDEO="$1"
AUDIO_DIR="$2"
TIMESTAMPS_JSON="$3"
OUTPUT_FILE="${4:-$(dirname "$MUTED_VIDEO")/video_dubbed.mp4}"

[[ -f "$MUTED_VIDEO" ]] || die "Muted video not found: $MUTED_VIDEO"
[[ -d "$AUDIO_DIR" ]] || die "Audio directory not found: $AUDIO_DIR"
[[ -f "$TIMESTAMPS_JSON" ]] || die "Timestamps JSON not found: $TIMESTAMPS_JSON"

# Check for required tools
command -v ffmpeg >/dev/null 2>&1 || die "ffmpeg is required but not installed"
command -v python3 >/dev/null 2>&1 || die "python3 is required (for JSON parsing)"

log "Muted video:  $MUTED_VIDEO"
log "Audio dir:    $AUDIO_DIR"
log "Timestamps:   $TIMESTAMPS_JSON"
log "Output:       $OUTPUT_FILE"

mkdir -p "$(dirname "$OUTPUT_FILE")"

# ── Parse timestamps JSON using python3 ──────────────────────────────────────
# Outputs lines of: file_path start_ms
PARSED=$(python3 -c "
import json, sys, os

with open('$TIMESTAMPS_JSON', 'r') as f:
    segments = json.load(f)

if not isinstance(segments, list):
    print('ERROR: JSON root must be an array', file=sys.stderr)
    sys.exit(1)

audio_dir = '$AUDIO_DIR'
valid = 0

for seg in segments:
    fname = seg.get('file', '')
    start = seg.get('start', 0)

    if not fname:
        print(f'WARNING: skipping segment with no file name', file=sys.stderr)
        continue

    fpath = os.path.join(audio_dir, fname)
    if not os.path.isfile(fpath):
        print(f'WARNING: audio file not found: {fpath}', file=sys.stderr)
        continue

    # Convert start seconds to milliseconds for adelay
    start_ms = int(float(start) * 1000)
    print(f'{fpath}\t{start_ms}')
    valid += 1

print(f'TOTAL:{valid}', file=sys.stderr)
") || die "Failed to parse timestamps JSON"

if [[ -z "$PARSED" ]]; then
    die "No valid audio segments found. Check your timestamps JSON and audio files."
fi

# Read parsed segments into arrays
declare -a AUDIO_FILES=()
declare -a START_MS=()

while IFS=$'\t' read -r fpath ms; do
    AUDIO_FILES+=("$fpath")
    START_MS+=("$ms")
done <<< "$PARSED"

NUM_SEGMENTS=${#AUDIO_FILES[@]}
log "Found $NUM_SEGMENTS valid audio segments"

if [[ "$NUM_SEGMENTS" -eq 0 ]]; then
    die "No audio segments to process"
fi

# ── Get video properties ─────────────────────────────────────────────────────
VIDEO_DURATION=$(ffprobe -v error -show_entries format=duration \
    -of default=noprint_wrappers=1:nokey=1 "$MUTED_VIDEO")
log "Video duration: ${VIDEO_DURATION}s"

# Detect if video already has audio stream
HAS_AUDIO=$(ffprobe -v error -select_streams a -show_entries stream=index \
    -of csv=p=0 "$MUTED_VIDEO" 2>/dev/null | head -1)

# ── Build ffmpeg filter_complex ──────────────────────────────────────────────
# Strategy:
#   - Input 0: the muted video
#   - Inputs 1..N: each audio segment file
#   - For each audio input, apply adelay to position it at the right timestamp
#   - Mix all delayed audio streams into one
#   - Merge with video

build_ffmpeg_command() {
    local cmd="ffmpeg -y"

    # Input: video
    cmd+=" -i '$MUTED_VIDEO'"

    # Inputs: audio segments
    for i in "${!AUDIO_FILES[@]}"; do
        cmd+=" -i '${AUDIO_FILES[$i]}'"
    done

    # Build filter_complex
    local filter=""
    local mix_inputs=""

    for i in "${!AUDIO_FILES[@]}"; do
        local input_idx=$((i + 1))
        local delay="${START_MS[$i]}"
        local label="a${i}"

        # adelay: delay in ms, apply to all channels
        # aresample: ensure consistent sample rate before mixing
        # apad: pad shorter segments with silence so amix doesn't cut early
        filter+="[${input_idx}:a]aresample=44100,adelay=${delay}|${delay},apad[${label}];"
        mix_inputs+="[${label}]"
    done

    # Mix all audio streams
    # dropout_transition: seconds of silence before dropping a stream (set high to prevent cutoff)
    # normalize=0: don't normalize volume (preserve original levels)
    filter+="${mix_inputs}amix=inputs=${NUM_SEGMENTS}:duration=longest:dropout_transition=0:normalize=0[mixed_audio]"

    cmd+=" -filter_complex '${filter}'"

    # Map video from input 0, audio from our mixed output
    cmd+=" -map 0:v -map '[mixed_audio]'"

    # Encoding settings
    cmd+=" -c:v copy"   # don't re-encode video
    cmd+=" -c:a aac -b:a 192k"
    cmd+=" -shortest"   # end when the shortest stream ends (the video)

    cmd+=" '$OUTPUT_FILE'"

    echo "$cmd"
}

FFMPEG_CMD=$(build_ffmpeg_command)

# ── Handle very large segment counts ────────────────────────────────────────
# ffmpeg has limits on filter complexity. For >50 segments, we batch in groups.
BATCH_SIZE=50

if [[ "$NUM_SEGMENTS" -le "$BATCH_SIZE" ]]; then
    log "Running ffmpeg with $NUM_SEGMENTS audio inputs..."
    log "Command preview (truncated): ${FFMPEG_CMD:0:300}..."

    eval "$FFMPEG_CMD" 2>&1 | while IFS= read -r line; do
        # Show progress lines
        if [[ "$line" =~ frame= ]] || [[ "$line" =~ time= ]]; then
            printf "\r[sync_audio] %s" "$line"
        fi
    done
    echo ""  # newline after progress
else
    # Batch processing for large segment counts
    log "Large segment count ($NUM_SEGMENTS). Processing in batches of $BATCH_SIZE..."

    BATCH_DIR=$(mktemp -d /tmp/sync_audio_batch_XXXXXX)
    trap 'rm -rf "$BATCH_DIR"' EXIT

    batch_num=0
    batch_files=()

    for ((start_idx=0; start_idx<NUM_SEGMENTS; start_idx+=BATCH_SIZE)); do
        batch_num=$((batch_num + 1))
        end_idx=$((start_idx + BATCH_SIZE))
        if [[ $end_idx -gt $NUM_SEGMENTS ]]; then
            end_idx=$NUM_SEGMENTS
        fi

        log "  Batch $batch_num: segments $((start_idx+1))-${end_idx}"

        # Build a batch command
        local_cmd="ffmpeg -y"

        # Silent base track matching video duration
        local_cmd+=" -f lavfi -i anullsrc=channel_layout=stereo:sample_rate=44100:duration=${VIDEO_DURATION}"

        local_filter=""
        local_mix=""
        local_count=0

        for ((i=start_idx; i<end_idx; i++)); do
            local_cmd+=" -i '${AUDIO_FILES[$i]}'"
            local_input_idx=$((local_count + 1))
            local_delay="${START_MS[$i]}"
            local_label="a${local_count}"

            local_filter+="[${local_input_idx}:a]aresample=44100,adelay=${local_delay}|${local_delay},apad[${local_label}];"
            local_mix+="[${local_label}]"
            local_count=$((local_count + 1))
        done

        # Mix this batch (include the silent base as [0:a])
        local_filter+="[0:a]${local_mix}amix=inputs=$((local_count + 1)):duration=first:dropout_transition=0:normalize=0[out]"

        batch_output="${BATCH_DIR}/batch_${batch_num}.wav"
        local_cmd+=" -filter_complex '${local_filter}' -map '[out]' -c:a pcm_s16le '${batch_output}'"

        eval "$local_cmd" 2>/dev/null
        batch_files+=("$batch_output")
        log "  Batch $batch_num complete: $batch_output"
    done

    # Merge all batch audio files
    log "Merging ${#batch_files[@]} batch files..."
    merge_cmd="ffmpeg -y"
    merge_filter=""
    merge_inputs=""

    for i in "${!batch_files[@]}"; do
        merge_cmd+=" -i '${batch_files[$i]}'"
        merge_inputs+="[$i:a]"
    done

    merge_filter+="${merge_inputs}amix=inputs=${#batch_files[@]}:duration=longest:normalize=0[final_audio]"
    merged_audio="${BATCH_DIR}/merged_audio.wav"
    merge_cmd+=" -filter_complex '${merge_filter}' -map '[final_audio]' -c:a pcm_s16le '${merged_audio}'"
    eval "$merge_cmd" 2>/dev/null

    # Combine merged audio with video
    log "Combining video with merged audio..."
    ffmpeg -y -i "$MUTED_VIDEO" -i "$merged_audio" \
        -map 0:v -map 1:a \
        -c:v copy -c:a aac -b:a 192k \
        -shortest \
        "$OUTPUT_FILE" 2>/dev/null

    rm -rf "$BATCH_DIR"
fi

# ── Verify output ────────────────────────────────────────────────────────────
if [[ ! -f "$OUTPUT_FILE" ]]; then
    die "Output file was not created"
fi

OUTPUT_SIZE=$(du -h "$OUTPUT_FILE" | cut -f1)
OUTPUT_DURATION=$(ffprobe -v error -show_entries format=duration \
    -of default=noprint_wrappers=1:nokey=1 "$OUTPUT_FILE" 2>/dev/null || echo "unknown")

# Verify audio stream exists in output
OUTPUT_HAS_AUDIO=$(ffprobe -v error -select_streams a -show_entries stream=codec_name \
    -of default=noprint_wrappers=1:nokey=1 "$OUTPUT_FILE" 2>/dev/null | head -1)

if [[ -z "$OUTPUT_HAS_AUDIO" ]]; then
    die "Output file has no audio stream - something went wrong"
fi

log "Success!"
log "  Output:   $OUTPUT_FILE"
log "  Size:     $OUTPUT_SIZE"
log "  Duration: ${OUTPUT_DURATION}s"
log "  Audio:    $OUTPUT_HAS_AUDIO"
