// speaking_rate_calculator.js
// n8n Code Node: Calculates optimal speaking rate for Spanish TTS dubbing.
//
// Input (from previous node):
//   $input.first().json.segments = [
//     { start: 0.0, end: 3.5, text: "original text", new_text: "translated Spanish text" },
//     ...
//   ]
//
// Output:
//   segments[] with added fields:
//     - speaking_rate      (float, multiplier: 1.0 = normal, 1.2 = 20% faster)
//     - target_duration    (float, seconds available for this segment)
//     - estimated_syllables (int)
//     - syllables_per_second (float)
//     - warnings           (array of strings, if any)

const LOG_PREFIX = "[speaking_rate]";

function log(msg) {
  console.log(`${LOG_PREFIX} ${msg}`);
}

// ── Spanish syllable estimation ─────────────────────────────────────────────
// Uses simplified Spanish phonological rules. Spanish is highly regular:
//   - Each vowel cluster (diphthong/triphthong) generally = 1 syllable
//   - Handle common diphthongs (ai, ei, oi, au, eu, ou, ia, ie, io, iu, ua, ue, uo, ui)
//   - Hiatus: two strong vowels (a, e, o) next to each other = 2 syllables

function countSpanishSyllables(text) {
  if (!text || typeof text !== "string") return 0;

  // Normalize: lowercase, remove punctuation except apostrophes
  let clean = text
    .toLowerCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "") // strip accents for syllable counting
    .replace(/[^a-z\s']/g, " ")
    .replace(/\s+/g, " ")
    .trim();

  if (clean.length === 0) return 0;

  const words = clean.split(" ").filter((w) => w.length > 0);
  let totalSyllables = 0;

  const strongVowels = new Set(["a", "e", "o"]);
  const weakVowels = new Set(["i", "u"]);
  const allVowels = new Set(["a", "e", "i", "o", "u"]);

  for (const word of words) {
    let syllables = 0;
    let i = 0;

    while (i < word.length) {
      const ch = word[i];
      if (!allVowels.has(ch)) {
        // Consonant: skip
        i++;
        continue;
      }

      // Found a vowel: start of a syllable
      syllables++;

      // Consume vowel cluster according to Spanish rules
      const isStrong = strongVowels.has(ch);
      i++;

      while (i < word.length && allVowels.has(word[i])) {
        const nextIsStrong = strongVowels.has(word[i]);

        if (isStrong && nextIsStrong) {
          // Two strong vowels = hiatus = separate syllables
          break;
        }
        // Diphthong or triphthong: same syllable
        i++;
      }
    }

    // Minimum 1 syllable per word
    totalSyllables += Math.max(syllables, 1);
  }

  return totalSyllables;
}

// ── Speaking rate calculation ───────────────────────────────────────────────
// Normal Spanish speaking rate: ~4.5-5.5 syllables/second (conversational)
// TTS sweet spot: 4.0-6.5 syl/s before it sounds unnatural
// We compute the required syl/s and derive a rate multiplier.

const NORMAL_RATE_SYLS_PER_SEC = 5.0; // baseline for rate=1.0
const MIN_RATE = 0.75;                 // don't go slower than this
const MAX_RATE = 1.35;                 // don't go faster than this
const PADDING_SECONDS = 0.15;          // small buffer at segment edges for natural pauses

function calculateSpeakingRate(segment) {
  const { start, end, new_text } = segment;
  const warnings = [];

  // Available duration for this segment
  const rawDuration = end - start;
  const targetDuration = Math.max(0.1, rawDuration - PADDING_SECONDS * 2);

  const estimatedSyllables = countSpanishSyllables(new_text);

  if (estimatedSyllables === 0) {
    return {
      speaking_rate: 1.0,
      target_duration: targetDuration,
      estimated_syllables: 0,
      syllables_per_second: 0,
      warnings: ["Empty or unparseable text; using default rate"],
    };
  }

  // Required syllables per second to fit in the available time
  const requiredSylsPerSec = estimatedSyllables / targetDuration;

  // Speaking rate multiplier: how much faster/slower than normal
  let speakingRate = requiredSylsPerSec / NORMAL_RATE_SYLS_PER_SEC;

  // Clamp and warn
  if (speakingRate < MIN_RATE) {
    warnings.push(
      `Rate ${speakingRate.toFixed(2)} below minimum ${MIN_RATE}; clamped. ` +
      `Text may finish early (${estimatedSyllables} syls in ${targetDuration.toFixed(1)}s).`
    );
    speakingRate = MIN_RATE;
  }

  if (speakingRate > MAX_RATE) {
    warnings.push(
      `Rate ${speakingRate.toFixed(2)} above maximum ${MAX_RATE}; clamped. ` +
      `Text may overflow segment (${estimatedSyllables} syls in ${targetDuration.toFixed(1)}s). ` +
      `Consider shortening the translation.`
    );
    speakingRate = MAX_RATE;
  }

  // Warn if the required rate is in the uncomfortable zone
  if (requiredSylsPerSec > 6.5) {
    warnings.push(
      `High syllable density: ${requiredSylsPerSec.toFixed(1)} syl/s ` +
      `(comfortable range: 4.0-6.5). Audio may sound rushed.`
    );
  }

  if (requiredSylsPerSec < 3.0 && estimatedSyllables > 0) {
    warnings.push(
      `Low syllable density: ${requiredSylsPerSec.toFixed(1)} syl/s. ` +
      `Consider adding filler or extending the translation.`
    );
  }

  return {
    speaking_rate: Math.round(speakingRate * 100) / 100,
    target_duration: Math.round(targetDuration * 1000) / 1000,
    estimated_syllables: estimatedSyllables,
    syllables_per_second: Math.round(requiredSylsPerSec * 100) / 100,
    warnings,
  };
}

// ── Main execution ──────────────────────────────────────────────────────────
try {
  const data = $input.first().json;

  if (!data.segments || !Array.isArray(data.segments)) {
    throw new Error("Input must contain a 'segments' array");
  }

  const segments = data.segments;
  log(`Processing ${segments.length} segments`);

  let warningCount = 0;

  const enrichedSegments = segments.map((seg, idx) => {
    if (typeof seg.start !== "number" || typeof seg.end !== "number") {
      throw new Error(`Segment ${idx}: 'start' and 'end' must be numbers`);
    }
    if (seg.end <= seg.start) {
      throw new Error(`Segment ${idx}: 'end' (${seg.end}) must be greater than 'start' (${seg.start})`);
    }
    if (!seg.new_text && !seg.text) {
      log(`Segment ${idx}: no text provided, skipping rate calculation`);
    }

    // Use new_text (translated) if available, fall back to text (original)
    const textForCalc = seg.new_text || seg.text || "";

    const rateInfo = calculateSpeakingRate({
      start: seg.start,
      end: seg.end,
      new_text: textForCalc,
    });

    if (rateInfo.warnings.length > 0) {
      warningCount += rateInfo.warnings.length;
      rateInfo.warnings.forEach((w) => log(`  Segment ${idx} [${seg.start}-${seg.end}s]: ${w}`));
    }

    return {
      ...seg,
      ...rateInfo,
    };
  });

  // Summary statistics
  const rates = enrichedSegments.map((s) => s.speaking_rate).filter((r) => r > 0);
  const avgRate = rates.length > 0 ? rates.reduce((a, b) => a + b, 0) / rates.length : 1.0;
  const minRate = rates.length > 0 ? Math.min(...rates) : 1.0;
  const maxRate = rates.length > 0 ? Math.max(...rates) : 1.0;
  const totalSyls = enrichedSegments.reduce((sum, s) => sum + s.estimated_syllables, 0);

  log(`Summary: ${enrichedSegments.length} segments, ${totalSyls} total syllables`);
  log(`  Rate range: ${minRate.toFixed(2)} - ${maxRate.toFixed(2)}, avg: ${avgRate.toFixed(2)}`);
  log(`  Warnings: ${warningCount}`);

  return [
    {
      json: {
        segments: enrichedSegments,
        summary: {
          total_segments: enrichedSegments.length,
          total_estimated_syllables: totalSyls,
          average_speaking_rate: Math.round(avgRate * 100) / 100,
          min_speaking_rate: minRate,
          max_speaking_rate: maxRate,
          segments_with_warnings: enrichedSegments.filter((s) => s.warnings.length > 0).length,
        },
      },
    },
  ];
} catch (err) {
  log(`ERROR: ${err.message}`);
  throw err;
}
