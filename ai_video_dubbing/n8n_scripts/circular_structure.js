// circular_structure.js
// n8n Code Node: Reorders video segments into a circular narrative structure.
//
// Input (from previous node items):
//   - $input.first().json.video_duration  (float, total seconds)
//   - $input.first().json.segments        (array of {id, start, end, text})
//   - $input.first().json.input_video     (string, path to source video)
//   - $input.first().json.output_video    (string, path for final output)
//
// Output:
//   - ffmpeg_commands: array of shell command strings ready to execute
//   - structure_info: metadata about the chosen structure

const LOG_PREFIX = "[circular_structure]";

function log(msg) {
  console.log(`${LOG_PREFIX} ${msg}`);
}

function validateInputs(data) {
  const required = ["video_duration", "segments", "input_video", "output_video"];
  const missing = required.filter((k) => data[k] === undefined || data[k] === null);
  if (missing.length > 0) {
    throw new Error(`Missing required inputs: ${missing.join(", ")}`);
  }
  if (!Array.isArray(data.segments) || data.segments.length === 0) {
    throw new Error("segments must be a non-empty array");
  }
  if (typeof data.video_duration !== "number" || data.video_duration <= 0) {
    throw new Error("video_duration must be a positive number");
  }
}

function findHookSegment(segments, videoDuration) {
  // Hook point: between 75% and 90% of the video - the most dramatic moment
  const hookStartMin = videoDuration * 0.75;
  const hookStartMax = videoDuration * 0.90;

  // Find the segment closest to the midpoint of the hook window
  const hookMidpoint = (hookStartMin + hookStartMax) / 2;

  let bestSegment = null;
  let bestDistance = Infinity;

  for (const seg of segments) {
    const segMid = (seg.start + seg.end) / 2;
    if (segMid >= hookStartMin && segMid <= hookStartMax) {
      const distance = Math.abs(segMid - hookMidpoint);
      if (distance < bestDistance) {
        bestDistance = distance;
        bestSegment = seg;
      }
    }
  }

  // Fallback: if no segment falls in the window, pick the one closest to 80%
  if (!bestSegment) {
    const target80 = videoDuration * 0.80;
    for (const seg of segments) {
      const distance = Math.abs(seg.start - target80);
      if (distance < bestDistance) {
        bestDistance = distance;
        bestSegment = seg;
      }
    }
  }

  return bestSegment;
}

function findClosingStart(videoDuration) {
  // Last 30 seconds for closing
  return Math.max(0, videoDuration - 30);
}

function formatTimestamp(seconds) {
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  const s = (seconds % 60).toFixed(3);
  return `${String(h).padStart(2, "0")}:${String(m).padStart(2, "0")}:${s.padStart(6, "0")}`;
}

function escapeShell(str) {
  return str.replace(/'/g, "'\\''");
}

function buildCommands(inputVideo, outputVideo, hookSegment, videoDuration) {
  const tmpDir = outputVideo.replace(/[^/]+$/, "tmp_circular");
  const commands = [];

  // 0. Create temp directory
  commands.push(`mkdir -p '${escapeShell(tmpDir)}'`);

  // 1. Extract hook segment (the dramatic opening teaser)
  const hookStart = formatTimestamp(hookSegment.start);
  const hookDuration = (hookSegment.end - hookSegment.start).toFixed(3);
  const partHook = `${tmpDir}/part_01_hook.mp4`;
  commands.push(
    `ffmpeg -y -i '${escapeShell(inputVideo)}' ` +
    `-ss ${hookStart} -t ${hookDuration} ` +
    `-c:v libx264 -preset fast -crf 18 -c:a aac -b:a 192k ` +
    `-avoid_negative_ts make_zero ` +
    `'${escapeShell(partHook)}'`
  );

  // 2. Generate transition title card: "Pero todo empezo asi..."
  const transitionDuration = 3;
  const partTransition = `${tmpDir}/part_02_transition.mp4`;

  // We need to know the video resolution. Extract it from the source or assume 1920x1080.
  // Use a two-pass approach: first detect, then generate. For simplicity in the pipeline
  // we generate at 1920x1080 and let the concat filter scale if needed.
  commands.push(
    `ffmpeg -y ` +
    `-f lavfi -i color=c=black:s=1920x1080:d=${transitionDuration}:r=30 ` +
    `-f lavfi -i anullsrc=channel_layout=stereo:sample_rate=44100 ` +
    `-vf "drawtext=text='Pero todo empezo asi...':` +
    `fontcolor=white:fontsize=72:` +
    `font=Arial:` +
    `x=(w-text_w)/2:y=(h-text_h)/2:` +
    `alpha='if(lt(t,0.5),t/0.5,if(gt(t,${transitionDuration - 0.5}),(${transitionDuration}-t)/0.5,1))'" ` +
    `-t ${transitionDuration} ` +
    `-c:v libx264 -preset fast -crf 18 -c:a aac -b:a 192k ` +
    `-shortest ` +
    `'${escapeShell(partTransition)}'`
  );

  // 3. Extract from beginning up to where the hook starts
  const partBeginning = `${tmpDir}/part_03_beginning.mp4`;
  const beginningEnd = formatTimestamp(hookSegment.start);
  commands.push(
    `ffmpeg -y -i '${escapeShell(inputVideo)}' ` +
    `-ss 00:00:00.000 -to ${beginningEnd} ` +
    `-c:v libx264 -preset fast -crf 18 -c:a aac -b:a 192k ` +
    `-avoid_negative_ts make_zero ` +
    `'${escapeShell(partBeginning)}'`
  );

  // 4. Extract closing: last 30 seconds (from after hook to end)
  const closingStart = formatTimestamp(findClosingStart(videoDuration));
  const partClosing = `${tmpDir}/part_04_closing.mp4`;
  commands.push(
    `ffmpeg -y -i '${escapeShell(inputVideo)}' ` +
    `-ss ${closingStart} ` +
    `-c:v libx264 -preset fast -crf 18 -c:a aac -b:a 192k ` +
    `-avoid_negative_ts make_zero ` +
    `'${escapeShell(partClosing)}'`
  );

  // 5. Build concat file
  const concatFile = `${tmpDir}/concat_list.txt`;
  const concatContent = [
    `file '${partHook}'`,
    `file '${partTransition}'`,
    `file '${partBeginning}'`,
    `file '${partClosing}'`,
  ].join("\\n");

  commands.push(`printf '${concatContent}' > '${escapeShell(concatFile)}'`);

  // 6. Concatenate all parts into final output
  commands.push(
    `ffmpeg -y -f concat -safe 0 ` +
    `-i '${escapeShell(concatFile)}' ` +
    `-c:v libx264 -preset fast -crf 18 -c:a aac -b:a 192k ` +
    `'${escapeShell(outputVideo)}'`
  );

  // 7. Cleanup temp directory (optional, comment out to debug)
  commands.push(`rm -rf '${escapeShell(tmpDir)}'`);

  return commands;
}

// ── Main execution ──────────────────────────────────────────────────────────
try {
  const data = $input.first().json;
  validateInputs(data);

  const { video_duration, segments, input_video, output_video } = data;

  log(`Video duration: ${video_duration}s, Segments: ${segments.length}`);
  log(`Hook window: ${(video_duration * 0.75).toFixed(1)}s - ${(video_duration * 0.90).toFixed(1)}s`);

  const hookSegment = findHookSegment(segments, video_duration);
  if (!hookSegment) {
    throw new Error("Could not identify a suitable hook segment");
  }
  log(`Selected hook segment: id=${hookSegment.id}, start=${hookSegment.start}s, end=${hookSegment.end}s`);

  const closingStartSec = findClosingStart(video_duration);
  const ffmpegCommands = buildCommands(input_video, output_video, hookSegment, video_duration);

  log(`Generated ${ffmpegCommands.length} ffmpeg commands`);

  return [
    {
      json: {
        ffmpeg_commands: ffmpegCommands,
        structure_info: {
          hook_segment_id: hookSegment.id,
          hook_start: hookSegment.start,
          hook_end: hookSegment.end,
          hook_text: hookSegment.text || "",
          transition_text: "Pero todo empezo asi...",
          transition_duration: 3,
          beginning_end: hookSegment.start,
          closing_start: closingStartSec,
          total_parts: 4,
          narrative_order: [
            "hook_teaser",
            "transition_card",
            "chronological_body",
            "closing",
          ],
        },
        input_video,
        output_video,
      },
    },
  ];
} catch (err) {
  log(`ERROR: ${err.message}`);
  throw err;
}
