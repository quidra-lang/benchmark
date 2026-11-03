'use strict';

const fs = require('fs');
const { read, reverseComplement } = require('./sequence_io');
const suffixArray = require('./suffix_array');
const { FMIndex } = require('./fm_index');
const { backtrack } = require('./search');
const { ratio, header, record, write } = require('./sam_writer');

const BASES = 'ACGT';
const positionOrder = (a, b) => a.r - b.r || a.pos - b.pos || a.strand - b.strand;
const increment = (map, key) => map.set(key, (map.get(key) || 0) + 1);
const total = values => values.reduce((sum, value) => sum + value, 0);
const gcCount = sequence => Array.from(sequence).filter(base => base === 'G' || base === 'C').length;

function textPosition(references, position) {
  for (let r = 0; r < references.length; r++) {
    const reference = references[r];
    if (position >= reference.offset && position < reference.offset + reference.sequence.length) {
      return { r, pos: position - reference.offset };
    }
  }
  return null;
}

function indexStatistics(references, params, forwardBuild, reverseBuild, forward, reverse) {
  const n = forward.text.length, checked = suffixArray.check(forward.text, forward.sa);
  const reverseChecked = suffixArray.check(reverse.text, reverse.sa), kmers = new Map();
  const namePosition = position => {
    const location = textPosition(references, position);
    return location ? `${references[location.r].name}:${location.pos + 1}` : '*';
  };
  for (const position of forward.sa) {
    if (position + params.SEED_LENGTH > n) continue;
    const kmer = forward.text.slice(position, position + params.SEED_LENGTH);
    if (Array.from(kmer).every(base => BASES.includes(base))) increment(kmers, kmer);
  }
  let occurrences = 0, unique = 0, maxOccurrence = 0;
  for (const count of kmers.values()) {
    occurrences += count;
    if (count === 1) unique++;
    maxOccurrence = Math.max(maxOccurrence, count);
  }
  let correct = 0, steps = 0, maxSteps = 0;
  for (let row = 0; row < n; row++) {
    const located = forward.locate(row);
    if (located.position === forward.sa[row]) correct++;
    steps += located.steps; maxSteps = Math.max(maxSteps, located.steps);
  }
  const bwtLine = index => {
    let runs = 0;
    for (let i = 0; i < n; i++) if (i === 0 || index.bwt[i] !== index.bwt[i - 1]) runs++;
    return `bwt runs ${runs} head ${index.bwt.slice(0, 60)}`;
  };
  const symbolValues = values => Array.from(suffixArray.SYMBOLS, (symbol, i) => `${symbol} ${values[i]}`).join(' ');
  const lines = [`text length ${n} sequences ${references.length}`];
  for (const reference of references) lines.push(`sequence ${reference.name} length ${reference.sequence.length} offset ${reference.offset} gc ${ratio(gcCount(reference.sequence), reference.sequence.length)} masked ${reference.masked}`);
  lines.push(`symbols ${symbolValues(forward.counts)}`, '', 'forward_index', `suffix_array rounds ${forwardBuild.rounds.length - 1}`);
  forwardBuild.rounds.forEach((classes, round) => lines.push(`round ${round} prefix_length ${2 ** round} classes ${classes}`));
  lines.push(`sa_check pairs ${n - 1} ordered ${checked.ordered} lcp_sum ${checked.lcpSum} mean_lcp ${ratio(checked.lcpSum, n - 1)} max_lcp ${checked.maximum}`,
    `longest_repeat ${checked.maximum} ${namePosition(forward.sa[checked.row - 1])} ${namePosition(forward.sa[checked.row])}`,
    `kmers length ${params.SEED_LENGTH} occurrences ${occurrences} distinct ${kmers.size} unique ${unique} max_occurrence ${maxOccurrence} unique_fraction ${ratio(unique, occurrences)}`,
    bwtLine(forward), `c_array ${symbolValues(forward.C)}`, `occ interval ${params.OCC_INTERVAL} checkpoints ${forward.checkpoints.length}`,
    `sa_sample interval ${params.SA_SAMPLE_INTERVAL} samples ${forward.samples.size}`,
    `locate rows ${n} correct ${correct} total_steps ${steps} max_steps ${maxSteps} mean_steps ${ratio(steps, n)}`,
    `inverse_bwt identical ${forward.inverse() === forward.text ? 'yes' : 'no'}`, '', 'reverse_index',
    `suffix_array rounds ${reverseBuild.rounds.length - 1}`, `sa_check pairs ${n - 1} ordered ${reverseChecked.ordered}`,
    bwtLine(reverse), `inverse_bwt identical ${reverse.inverse() === reverse.text ? 'yes' : 'no'}`, '', 'direct_sort');
  let directCount = 0;
  for (const reference of references) {
    if (reference.sequence.length > params.DIRECT_SORT_LIMIT) continue;
    const text = reference.sequence + '$', built = suffixArray.build(text), direct = suffixArray.direct(text);
    const identical = built.sa.every((position, i) => position === direct[i]);
    lines.push(`${reference.name} length ${text.length} rounds ${built.rounds.length - 1} identical ${identical ? 'yes' : 'no'}`);
    directCount++;
  }
  if (directCount === 0) lines.push('none');
  const occBytes = 24 * forward.checkpoints.length, sampleBytes = 4 * forward.samples.size;
  const bitmapBytes = Math.floor((n + 7) / 8), size = n + occBytes + sampleBytes + bitmapBytes;
  lines.push('', `index_size bwt_bytes ${n} occ_bytes ${occBytes} sample_bytes ${sampleBytes} bitmap_bytes ${bitmapBytes} total_bytes ${size} full_bytes ${5 * n} ratio ${ratio(size, 5 * n)}`);
  return lines;
}

function bandedAlignment(sequence, reference, center, params) {
  const [match, mismatch, open, extend] = params.SCORES;
  const length = sequence.length, width = params.BAND_WIDTH, rows = [];
  const value = (cell, state) => cell ? cell[state] : null;
  const minus = (score, penalty) => score === null ? null : score - penalty;
  const maximum = candidates => {
    let best = null;
    for (const candidate of candidates) if (candidate !== null && (best === null || candidate > best)) best = candidate;
    return best;
  };
  for (let i = 0; i <= length; i++) {
    const row = new Map(); rows.push(row);
    const first = Math.max(0, i + center - width), last = Math.min(reference.length, i + center + width);
    for (let j = first; j <= last; j++) {
      if (i === 0) { row.set(j, { H: 0, E: null, F: null }); continue; }
      const above = rows[i - 1].get(j), left = row.get(j - 1), diagonal = rows[i - 1].get(j - 1);
      const F = maximum([minus(value(above, 'H'), open + extend), minus(value(above, 'F'), extend)]);
      const E = j === 0 ? null : maximum([minus(value(left, 'H'), open + extend), minus(value(left, 'E'), extend)]);
      const previous = value(diagonal, 'H');
      const paired = j === 0 || previous === null ? null : previous + (sequence[i - 1] === reference[j - 1] ? match : -mismatch);
      row.set(j, { H: maximum([paired, E, F]), E, F });
    }
  }
  let end = null, score = null;
  for (const [j, cell] of rows[length]) {
    if (cell.H !== null && (score === null || cell.H > score)) { end = j; score = cell.H; }
  }
  if (end === null) return null;
  let i = length, j = end, state = 'H';
  const operations = [];
  while (true) {
    if (state === 'H' && i === 0) break;
    const cell = rows[i].get(j);
    if (state === 'H') {
      const diagonal = j >= 1 ? value(rows[i - 1].get(j - 1), 'H') : null;
      if (diagonal !== null && cell.H === diagonal + (sequence[i - 1] === reference[j - 1] ? match : -mismatch)) {
        operations.push('M'); i--; j--;
      } else state = cell.F !== null && cell.H === cell.F ? 'I' : 'D';
    } else if (state === 'I') {
      operations.push('I');
      const previous = value(rows[i - 1].get(j), 'F');
      state = previous !== null && cell.F === previous - extend ? 'I' : 'H';
      i--;
    } else {
      operations.push('D');
      const previous = value(rows[i].get(j - 1), 'E');
      state = previous !== null && cell.E === previous - extend ? 'D' : 'H';
      j--;
    }
  }
  return { pos: j, ops: operations.reverse().join(''), score };
}

function mapRead(read, references, params, forward, reverse, searchStats, seedStats) {
  let length = read.sequence.length;
  while (length > 0 && read.qualities[length - 1] < params.TRIM_QUALITY) length--;
  read.length = length; read.trimmed = read.sequence.length - length;
  if (length < params.MIN_READ_LENGTH) return { reason: 'SHORT' };
  const core = read.sequence.slice(0, length), oriented = [core, reverseComplement(core)];
  const exact = oriented.map(sequence => forward.backward(sequence));
  const maximum = exact.some(([lo, hi]) => lo < hi) ? 1 : params.MAX_MISMATCHES;
  const hits = [];
  for (let strand = 0; strand < 2; strand++) {
    const searched = backtrack(oriented[strand], maximum, forward, reverse);
    searchStats.calls++; searchStats.nodes += searched.nodes;
    searchStats.leaves += searched.leaves.length; searchStats.positions += searched.hits;
    for (const leaf of searched.leaves) for (let row = leaf.lo; row < leaf.hi; row++) {
      const location = textPosition(references, forward.locate(row).position);
      hits.push({ ...location, strand, mm: leaf.mismatches, ops: 'M'.repeat(length) });
    }
  }
  if (hits.length > 0) {
    hits.sort((a, b) => a.mm - b.mm || positionOrder(a, b));
    const best = hits[0].mm, x0 = hits.filter(hit => hit.mm === best).length;
    const x1 = hits.filter(hit => hit.mm === best + 1).length;
    const mapq = x0 >= 2 ? 0 : x1 === 0 ? 60 - 12 * best : Math.max(30 - 12 * best - 3 * x1, 1);
    return { alignments: hits.filter(hit => hit.mm <= best + 1), x0, x1, mapq,
      score: (length - best) * params.SCORES[0] - best * params.SCORES[1], method: best === 0 ? 'EXACT' : 'MISMATCH' };
  }
  if (length < params.SEED_LENGTH) return { reason: 'NOHIT' };
  seedStats.reads++;
  const candidates = new Map();
  for (let strand = 0; strand < 2; strand++) {
    const sequence = oriented[strand];
    for (let offset = 0; offset + params.SEED_LENGTH <= length; offset += params.SEED_STEP) {
      seedStats.seeds++;
      const seed = sequence.slice(offset, offset + params.SEED_LENGTH);
      if (seed.includes('N')) { seedStats.withN++; continue; }
      const [lo, hi] = forward.backward(seed);
      if (hi - lo > params.MAX_SEED_HITS) { seedStats.repetitive++; continue; }
      if (lo >= hi) { seedStats.withoutHit++; continue; }
      for (let row = lo; row < hi; row++) {
        const location = textPosition(references, forward.locate(row).position), c = location.pos - offset;
        candidates.set(`${strand}/${location.r}/${c}`, { strand, r: location.r, c });
      }
    }
  }
  const ordered = Array.from(candidates.values()).sort((a, b) => a.strand - b.strand || a.r - b.r || a.c - b.c);
  seedStats.candidates += ordered.length;
  const accepted = new Map();
  for (const candidate of ordered) {
    const aligned = bandedAlignment(oriented[candidate.strand], references[candidate.r].sequence, candidate.c, params);
    if (!aligned || 100 * aligned.score < params.MIN_SCORE_PERCENT * params.SCORES[0] * length) continue;
    const alignment = { ...aligned, r: candidate.r, strand: candidate.strand };
    const key = `${alignment.r}/${alignment.pos}/${alignment.strand}`, previous = accepted.get(key);
    if (!previous || alignment.score > previous.score) accepted.set(key, alignment);
  }
  seedStats.passing += accepted.size;
  if (accepted.size === 0) return { reason: 'NOHIT' };
  const alignments = Array.from(accepted.values()).sort((a, b) => b.score - a.score || positionOrder(a, b));
  const score = alignments[0].score, x0 = alignments.filter(alignment => alignment.score === score).length;
  const x1 = alignments.length - x0, second = x1 === 0 ? 0 : alignments[x0].score;
  return { alignments, score, x0, x1, mapq: x0 >= 2 ? 0 : Math.floor(60 * (score - second) / score), method: 'SEED' };
}

function describeAlignment(read, alignment, references) {
  const core = read.sequence.slice(0, read.length), sequence = alignment.strand === 0 ? core : reverseComplement(core);
  const reference = references[alignment.r].sequence, runs = [], pairs = [], md = [];
  for (const operation of alignment.ops) {
    if (runs.length && runs[runs.length - 1].operation === operation) runs[runs.length - 1].length++;
    else runs.push({ operation, length: 1 });
  }
  let i = 0, j = alignment.pos, matches = 0, nm = 0;
  for (const run of runs) {
    if (run.operation === 'I') { i += run.length; nm += run.length; continue; }
    if (run.operation === 'D') {
      md.push(`${matches}^${reference.slice(j, j + run.length)}`); matches = 0;
      j += run.length; nm += run.length; continue;
    }
    for (let k = 0; k < run.length; k++) {
      const cycle = alignment.strand === 0 ? i + 1 : read.length - i, match = sequence[i] === reference[j];
      pairs.push({ refPos: j, base: sequence[i], reference: reference[j], cycle, quality: read.qualities[cycle - 1], match });
      if (match) matches++;
      else { md.push(`${matches}${reference[j]}`); matches = 0; nm++; }
      i++; j++;
    }
  }
  md.push(String(matches));
  let cigar = runs.map(run => `${run.length}${run.operation}`).join('');
  if (read.trimmed > 0) cigar = alignment.strand === 0 ? cigar + `${read.trimmed}S` : `${read.trimmed}S` + cigar;
  Object.assign(alignment, { runs, pairs, cigar, md: md.join(''), nm });
}

function tallyCoverage(reads, results, references, params) {
  const coverage = references.map(reference => ({ depth: Array(reference.sequence.length).fill(0),
    starts: Array(reference.sequence.length).fill(0), pileup: Array.from({ length: reference.sequence.length }, () => Array(8).fill(0)) }));
  for (let index = 0; index < reads.length; index++) {
    const result = results[index];
    if (result.reason) continue;
    const primary = result.alignments[0], target = coverage[primary.r];
    if (result.mapq === 0) target.starts[primary.pos]++;
    if (result.mapq < params.COVERAGE_MIN_MAPQ) continue;
    for (const pair of primary.pairs) {
      target.depth[pair.refPos]++;
      if (pair.base !== 'N' && pair.quality >= params.VARIANTS[1]) target.pileup[pair.refPos][4 * primary.strand + BASES.indexOf(pair.base)]++;
    }
  }
  return coverage;
}

function coverageReport(references, coverage, params) {
  const lines = [`window ${params.COVERAGE_WINDOW} min_mapq ${params.COVERAGE_MIN_MAPQ}`];
  references.forEach((reference, r) => {
    const { depth, starts } = coverage[r], length = reference.sequence.length;
    let sum = 0, maximum = 0, covered = 0;
    for (const value of depth) { sum += value; maximum = Math.max(maximum, value); if (value > 0) covered++; }
    const histogram = Array(maximum + 1).fill(0);
    for (const value of depth) histogram[value]++;
    lines.push(`reference ${reference.name} length ${length} covered ${covered} breadth ${ratio(covered, length)} mean_depth ${ratio(sum, length)} max_depth ${maximum}`,
      `depth_histogram ${histogram.map((count, value) => `${value}:${count}`).join(' ')}`);
    for (let first = 0; first < length; first += params.COVERAGE_WINDOW) {
      const end = Math.min(first + params.COVERAGE_WINDOW, length), width = end - first;
      let windowSum = 0, windowMaximum = 0, zero = 0, mapq0 = 0;
      for (let j = first; j < end; j++) {
        windowSum += depth[j]; windowMaximum = Math.max(windowMaximum, depth[j]);
        if (depth[j] === 0) zero++;
        mapq0 += starts[j];
      }
      lines.push(`${reference.name} ${first + 1} ${end} gc ${ratio(gcCount(reference.sequence.slice(first, end)), width)} sum ${windowSum} mean ${ratio(windowSum, width)} max ${windowMaximum} zero ${zero} mapq0 ${mapq0} |${'#'.repeat(Math.floor(10 * windowSum / width))}`);
    }
  });
  return lines;
}

function variantReport(references, coverage, params) {
  const [minDepth, quality, percent, homPercent] = params.VARIANTS;
  const lines = [`min_depth ${minDepth} min_base_quality ${quality} min_alt_percent ${percent} hom_percent ${homPercent}`];
  let callable = 0, heterozygous = 0, homozygous = 0;
  references.forEach((reference, r) => {
    for (let j = 0; j < reference.sequence.length; j++) {
      const pileup = coverage[r].pileup[j], counts = Array.from({ length: 4 }, (_, base) => pileup[base] + pileup[base + 4]);
      const depth = total(counts);
      if (depth < minDepth) continue;
      callable++;
      let alternative = -1;
      for (let base = 0; base < 4; base++) {
        if (BASES[base] !== reference.sequence[j] && (alternative < 0 || counts[base] > counts[alternative])) alternative = base;
      }
      const count = counts[alternative];
      if (count < 2 || 100 * count < percent * depth) continue;
      const homo = 100 * count >= homPercent * depth;
      if (homo) homozygous++; else heterozygous++;
      lines.push(`${reference.name} ${j + 1} ${reference.sequence[j]}>${BASES[alternative]} depth ${depth} alt ${count} fraction ${ratio(count, depth)} genotype ${homo ? '1/1' : '0/1'} strands ${pileup[alternative]} ${pileup[alternative + 4]} counts ${counts.join(' ')}`);
    }
  });
  lines.push(`callable ${callable} variants ${heterozygous + homozygous} heterozygous ${heterozygous} homozygous ${homozygous}`);
  return lines;
}

function summaryReport(reads, results, references, searchStats, seedStats) {
  const count = { trimmed: 0, trimmedBases: 0, SHORT: 0, NOHIT: 0, mapped: 0, unique: 0, multi: 0,
    EXACT: 0, MISMATCH: 0, SEED: 0, forward: 0, reverse: 0, nReads: 0, nBases: 0, nMapped: 0 };
  const refStats = references.map(() => ({ mapped: 0, unique: 0, forward: 0, reverse: 0 }));
  const bins = new Map(), targets = new Map(), mapqHistogram = new Map(), nmHistogram = new Map();
  const substitutions = Array.from({ length: 4 }, () => Array(5).fill(0));
  const maxLength = Math.max(...reads.map(read => read.sequence.length));
  const cycles = Array.from({ length: maxLength }, () => ({ aligned: 0, mismatches: 0 }));
  const qualityBins = Array.from({ length: 5 }, () => ({ aligned: 0, mismatches: 0 }));
  const error = { aligned: 0, mismatches: 0, matchedQuality: 0, mismatchedQuality: 0 };
  const cigar = { M: 0, I: 0, D: 0, S: 0 }, indels = { I: { events: 0, bases: 0 }, D: { events: 0, bases: 0 } };
  for (let index = 0; index < reads.length; index++) {
    const read = reads[index], result = results[index], lo = 10 * Math.floor(read.length / 10);
    if (!bins.has(lo)) bins.set(lo, { reads: 0, mapped: 0, unique: 0 });
    const bin = bins.get(lo); bin.reads++;
    if (read.trimmed > 0) count.trimmed++;
    count.trimmedBases += read.trimmed;
    const nBases = Array.from(read.sequence).filter(base => base === 'N').length;
    if (nBases > 0) { count.nReads++; count.nBases += nBases; if (!result.reason) count.nMapped++; }
    if (result.reason) { count[result.reason]++; continue; }
    count.mapped++; count[result.method]++; bin.mapped++;
    const primary = result.alignments[0], ref = refStats[primary.r], strand = primary.strand === 0 ? 'forward' : 'reverse';
    const unique = result.x0 === 1;
    count[strand]++; ref[strand]++; ref.mapped++;
    if (unique) { count.unique++; ref.unique++; bin.unique++; }
    else {
      count.multi++;
      const names = Array.from(new Set(result.alignments.slice(0, result.x0).map(alignment => alignment.r)))
        .sort((a, b) => a - b).map(r => references[r].name).join('+');
      increment(targets, names);
    }
    increment(mapqHistogram, result.mapq); increment(nmHistogram, primary.nm);
    for (const run of primary.runs) {
      cigar[run.operation] += run.length;
      if (unique && run.operation !== 'M') { indels[run.operation].events++; indels[run.operation].bases += run.length; }
    }
    cigar.S += read.trimmed;
    if (!unique) continue;
    for (const pair of primary.pairs) {
      const cycle = cycles[pair.cycle - 1], qualityBin = qualityBins[Math.min(4, Math.floor(pair.quality / 10))];
      error.aligned++; cycle.aligned++; qualityBin.aligned++;
      substitutions[BASES.indexOf(pair.reference)]['ACGTN'.indexOf(pair.base)]++;
      if (pair.match) error.matchedQuality += pair.quality;
      else { error.mismatches++; cycle.mismatches++; qualityBin.mismatches++; error.mismatchedQuality += pair.quality; }
    }
  }
  const lines = [`reads total ${reads.length} trimmed ${count.trimmed} trimmed_bases ${count.trimmedBases} short ${count.SHORT}`,
    `mapped ${count.mapped} rate ${ratio(count.mapped, reads.length)} unique ${count.unique} multi ${count.multi} unmapped ${count.SHORT + count.NOHIT}`,
    `unmapped short ${count.SHORT} nohit ${count.NOHIT}`, `method exact ${count.EXACT} mismatch ${count.MISMATCH} seed ${count.SEED}`,
    `strand forward ${count.forward} reverse ${count.reverse}`];
  references.forEach((reference, r) => {
    const stats = refStats[r];
    lines.push(`reference ${reference.name} mapped ${stats.mapped} unique ${stats.unique} forward ${stats.forward} reverse ${stats.reverse}`);
  });
  lines.push('length_bins');
  const minBin = Math.min(...bins.keys()), maxBin = Math.max(...bins.keys());
  for (let lo = minBin; lo <= maxBin; lo += 10) {
    const bin = bins.get(lo) || { reads: 0, mapped: 0, unique: 0 };
    lines.push(`${lo}-${lo + 9} reads ${bin.reads} mapped ${bin.mapped} unique ${bin.unique}`);
  }
  lines.push(`n_reads ${count.nReads} n_bases ${count.nBases} mapped ${count.nMapped}`, 'multi_targets');
  if (targets.size === 0) lines.push('none');
  else for (const name of Array.from(targets.keys()).sort()) lines.push(`${name} ${targets.get(name)}`);
  lines.push('mapq_histogram');
  for (const mapq of Array.from(mapqHistogram.keys()).sort((a, b) => b - a)) lines.push(`${mapq} ${mapqHistogram.get(mapq)}`);
  lines.push('nm_histogram');
  for (const nm of Array.from(nmHistogram.keys()).sort((a, b) => a - b)) lines.push(`${nm} ${nmHistogram.get(nm)}`);
  lines.push(`error_profile aligned_bases ${error.aligned} mismatches ${error.mismatches} rate ${ratio(error.mismatches, error.aligned)}`,
    'substitutions', 'ref A C G T N');
  for (let base = 0; base < 4; base++) lines.push(`${BASES[base]} ${substitutions[base].join(' ')}`);
  lines.push('mismatch_by_cycle');
  cycles.forEach((cycle, i) => lines.push(`cycle ${i + 1} aligned ${cycle.aligned} mismatches ${cycle.mismatches} rate ${ratio(cycle.mismatches, cycle.aligned)}`));
  lines.push(`quality matched ${error.aligned - error.mismatches} mean ${ratio(error.matchedQuality, error.aligned - error.mismatches)} mismatched ${error.mismatches} mean ${ratio(error.mismatchedQuality, error.mismatches)}`, 'quality_bins');
  qualityBins.forEach((bin, i) => lines.push(`${['0-9', '10-19', '20-29', '30-39', '40-'][i]} aligned ${bin.aligned} mismatches ${bin.mismatches} rate ${ratio(bin.mismatches, bin.aligned)}`));
  lines.push(`cigar M ${cigar.M} I ${cigar.I} D ${cigar.D} S ${cigar.S}`,
    `indels insertions ${indels.I.events} ${indels.I.bases} deletions ${indels.D.events} ${indels.D.bases}`,
    `search dfs_calls ${searchStats.calls} dfs_nodes ${searchStats.nodes} dfs_leaves ${searchStats.leaves} dfs_positions ${searchStats.positions}`,
    `seeds reads ${seedStats.reads} seeds ${seedStats.seeds} with_n ${seedStats.withN} repetitive ${seedStats.repetitive} without_hit ${seedStats.withoutHit} candidates ${seedStats.candidates} passing ${seedStats.passing}`);
  return lines;
}

function main() {
  const { references, reads, params } = read();
  let offset = 0;
  for (const reference of references) { reference.offset = offset; offset += reference.sequence.length + 1; }
  const text = references.map(reference => reference.sequence).join('#') + '$';
  const reverseText = Array.from(text.slice(0, -1)).reverse().join('') + '$';
  const forwardBuild = suffixArray.build(text), reverseBuild = suffixArray.build(reverseText);
  const forward = new FMIndex(text, forwardBuild.sa, params.OCC_INTERVAL, params.SA_SAMPLE_INTERVAL);
  const reverse = new FMIndex(reverseText, reverseBuild.sa, params.OCC_INTERVAL);
  const indexLines = indexStatistics(references, params, forwardBuild, reverseBuild, forward, reverse);
  const searchStats = { calls: 0, nodes: 0, leaves: 0, positions: 0 };
  const seedStats = { reads: 0, seeds: 0, withN: 0, repetitive: 0, withoutHit: 0, candidates: 0, passing: 0 };
  const results = reads.map(read => mapRead(read, references, params, forward, reverse, searchStats, seedStats));
  results.forEach((result, i) => {
    if (!result.reason) for (const alignment of result.alignments) describeAlignment(reads[i], alignment, references);
  });
  const coverage = tallyCoverage(reads, results, references, params);
  const sam = header(references);
  reads.forEach((read, i) => sam.push(record(read, results[i], references, params.MAX_ALT_HITS)));
  fs.mkdirSync('output', { recursive: true });
  write('output/alignments.sam', sam);
  write('output/coverage.txt', coverageReport(references, coverage, params));
  write('output/variants.txt', variantReport(references, coverage, params));
  write('output/index_stats.txt', indexLines);
  write('output/summary.txt', summaryReport(reads, results, references, searchStats, seedStats));
}

main();
