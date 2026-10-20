import { readInput, writeReports, type Label, type Settings } from './signal_io.ts';
import { filter, type Signals } from './filters.ts';
import { findPeaks, initialLevels, qrsWidth, type Peak, type Levels } from './detector.ts';
import { sum, statistics, histogram, ranges } from './hrv.ts';
import { div, rdiv, decimal2, decimal4, fraction, ratio, missing } from './report.ts';

const LABELS: readonly Label[] = ['N', 'V', 'A'];
type Input = ReturnType<typeof readInput>;
interface Beat { number: number; peak: Peak; sample: number; rr: number | null; width: number; label: Label; method: 'threshold' | 'searchback'; reference: number | null }
interface Detection { peaks: Peak[]; registered: Peak[]; initial: Levels; levels: Levels; ra1: number; ra2: number }
const pad = (value: number | string, width: number): string => String(value).padStart(width);
const decimalOrNone = (value: number | null): string => value === null ? 'none' : decimal2(value);
function thresholds(levels: Levels): [number, number] {
  return [levels.npki + div(levels.spki - levels.npki, 4), levels.npkf + div(levels.spkf - levels.npkf, 4)];
}
function detect(signals: Signals, settings: Settings): Detection {
  const peaks = findPeaks(signals), initial = initialLevels(signals), levels = { ...initial }, registered: Peak[] = [];
  const state: { last: Peak | null; rr: number[]; ra1: number; ra2: number } = { last: null, rr: [], ra1: 200, ra2: 200 };
  const register = (peak: Peak): void => {
    if (state.last) {
      const interval = peak.time - state.last.time;
      state.rr.push(interval);
      if (state.rr.length > 8) state.rr.shift();
      state.ra1 = div(sum(state.rr), state.rr.length);
      if (92 * state.ra1 <= 100 * interval && 100 * interval <= 116 * state.ra1) state.ra2 = state.ra1;
    }
    registered.push(peak); state.last = peak;
  };
  const signalUpdate = (peak: Peak, divisor: number): void => {
    levels.spki = div(peak.integrated + (divisor - 1) * levels.spki, divisor);
    levels.spkf = div(peak.filtered + (divisor - 1) * levels.spkf, divisor);
  };
  const noiseUpdate = (peak: Peak): void => {
    levels.npki = div(peak.integrated + 7 * levels.npki, 8);
    levels.npkf = div(peak.filtered + 7 * levels.npkf, 8);
  };
  const searchBack = (time: number): void => {
    for (;;) {
      const previous = state.last?.time ?? 0;
      if (time - previous <= div(state.ra2 * settings.searchback, 100)) return;
      const [thresholdI, thresholdF] = thresholds(levels);
      let candidate: Peak | null = null;
      for (const peak of peaks) if (peak.kind === 'noise' && peak.time > previous && peak.time < time
        && peak.integrated > div(thresholdI, 2) && peak.filtered > div(thresholdF, 2)
        && (candidate === null || peak.integrated > candidate.integrated)) candidate = peak;
      if (candidate === null) return;
      signalUpdate(candidate, 4); candidate.kind = 'searchback'; register(candidate);
    }
  };
  for (const peak of peaks) {
    searchBack(peak.time);
    [peak.thresholdI, peak.thresholdF] = thresholds(levels);
    if (state.last && peak.time - state.last.time < div(settings.refractory, 5)) peak.kind = 'refractory';
    else if (peak.integrated > peak.thresholdI && peak.filtered > peak.thresholdF) {
      if (state.last && peak.time - state.last.time < div(settings.twave, 5) && 2 * peak.slope < state.last.slope) {
        peak.kind = 'twave'; noiseUpdate(peak);
      } else { peak.kind = 'qrs'; signalUpdate(peak, 8); register(peak); }
    } else { peak.kind = 'noise'; noiseUpdate(peak); }
  }
  searchBack(signals.integrated.length);
  return { peaks, registered, initial, levels, ra1: state.ra1, ra2: state.ra2 };
}
function makeBeats(detection: Detection, signals: Signals, settings: Settings): Beat[] {
  const beats: Beat[] = [];
  for (const peak of detection.registered) {
    const i = beats.length, sample = Math.max(0, peak.r - 21), rr = i ? 5 * (sample - beats[i - 1].sample) : null;
    const width = qrsWidth(signals.bandpass, peak.r);
    const previous = i >= 9 ? sum(beats.slice(i - 8, i).map(beat => beat.rr!)) : 0;
    const premature = i >= 9 && 800 * rr! < settings.premature * previous;
    beats.push({ number: i + 1, peak, sample, rr, width, label: premature ? width > settings.qrsWidth ? 'V' : 'A' : 'N',
      method: peak.kind === 'searchback' ? 'searchback' : 'threshold', reference: null });
  }
  return beats;
}
function matchBeats(input: Input, beats: Beat[]): number[] {
  const matches = input.annotations.map(() => -1), tolerance = div(input.settings.match, 5);
  beats.forEach((beat, index) => {
    let best = -1, distance = tolerance + 1;
    input.annotations.forEach((annotation, reference) => {
      const delta = Math.abs(annotation.sample - beat.sample);
      if (matches[reference] < 0 && delta <= tolerance && delta < distance) { best = reference; distance = delta; }
    });
    if (best >= 0) { matches[best] = index; beat.reference = best; }
  });
  return matches;
}
function analyze(input: Input, detection: Detection, beats: Beat[], matches: number[]) {
  const rr = beats.slice(1).map(beat => beat.rr!);
  const nnFlags = beats.map((beat, i) => i >= 2 && beats[i - 1].label === 'N' && beat.label === 'N'
    && 5 * Math.abs(beat.rr! - beats[i - 1].rr!) <= beats[i - 1].rr!);
  const nn = beats.filter((_, i) => nnFlags[i]).map(beat => beat.rr!), pairs: [number, number][] = [];
  for (let i = 3; i < beats.length; i++) if (nnFlags[i - 1] && nnFlags[i]) pairs.push([beats[i - 1].rr!, beats[i].rr!]);
  const segments = [];
  const width = div(input.settings.segment, 5);
  for (let start = 0; start < input.signal.length; start += width) {
    const end = Math.min(input.signal.length, start + width);
    const references = input.annotations.map((a, i) => ({ annotation: a, matched: matches[i] >= 0 })).filter(r => start <= r.annotation.sample && r.annotation.sample < end);
    const localBeats = beats.filter(b => start <= b.sample && b.sample < end);
    segments.push({ start: 5 * start, end: 5 * end, references, beats: localBeats,
      noise: detection.peaks.filter(p => start <= p.time && p.time < end && p.kind === 'noise').length });
  }
  const bins = histogram(nn), binMax = Math.max(0, ...bins.map(([, count]) => count));
  const tp = beats.filter(b => b.reference !== null).length;
  return { rr, nn, pairs, segments, bins, binMax, statistics: statistics(rr, nn, pairs), tp,
    fp: beats.length - tp, fn: input.annotations.length - tp };
}
type Analysis = ReturnType<typeof analyze>;
function beatRows(input: Input, beats: Beat[]): string[] {
  return ['beat,sample,time_ms,rr_ms,hr_bpm,width_ms,label,method,ref_sample,ref_label', ...beats.map(beat => {
    const reference = beat.reference === null ? null : input.annotations[beat.reference];
    return [beat.number, beat.sample, 5 * beat.sample, missing(beat.rr), beat.rr === null ? '-' : decimal2(rdiv(6000000, beat.rr)),
      beat.width, beat.label, beat.method, reference?.sample ?? '-', reference?.label ?? '-'].join(',');
  })];
}
function matchingRows(input: Input, beats: Beat[], matches: number[]): string[] {
  const rows = input.annotations.map((annotation, i) => {
    const beat = matches[i] < 0 ? null : beats[matches[i]];
    return { key: annotation.sample, order: 0, text: beat
      ? `${annotation.sample},${annotation.label},${beat.number},${beat.sample},${beat.label},${5 * (beat.sample - annotation.sample)},TP,${beat.label === annotation.label ? 'yes' : 'no'}`
      : `${annotation.sample},${annotation.label},-,-,-,-,FN,-` };
  });
  for (const beat of beats) if (beat.reference === null) rows.push({ key: beat.sample, order: 1,
    text: `-,-,${beat.number},${beat.sample},${beat.label},-,FP,-` });
  rows.sort((a, b) => a.key - b.key || a.order - b.order);
  return ['ref_sample,ref_label,beat,beat_sample,beat_label,offset_ms,status,agree', ...rows.map(row => row.text)];
}
function performanceRows(input: Input, detection: Detection, beats: Beat[], matches: number[], analysis: Analysis): string[] {
  const { tp, fp, fn } = analysis, [thresholdI, thresholdF] = thresholds(detection.levels);
  const counts = (values: readonly Label[]) => LABELS.map(label => `${label}=${values.filter(v => v === label).length}`).join(' ');
  const levels = (value: Levels) => `spki=${value.spki} npki=${value.npki} spkf=${value.spkf} npkf=${value.npkf}`;
  const classes = (['qrs', 'searchback', 'twave', 'refractory', 'noise'] as const).map(kind => `${kind}=${detection.peaks.filter(p => p.kind === kind).length}`).join(' ');
  const rows = ['DETECTOR', `samples ${input.signal.length}`, `duration_ms ${5 * input.signal.length}`, `peaks ${detection.peaks.length} ${classes}`,
    'initial_levels ' + levels(detection.initial), 'final_levels ' + levels(detection.levels), `final_thresholds thr_i=${thresholdI} thr_f=${thresholdF}`,
    `final_rr_averages rravg1_ms=${5 * detection.ra1} rravg2_ms=${5 * detection.ra2}`, 'MATCHING', `tolerance_ms ${input.settings.match}`,
    `references ${input.annotations.length} ${counts(input.annotations.map(a => a.label))}`, `detections ${beats.length} ${counts(beats.map(b => b.label))}`,
    `true_positives ${tp}`, `false_positives ${fp}`, `false_negatives ${fn}`, `sensitivity ${ratio(tp, tp + fn)}`,
    `positive_predictivity ${ratio(tp, tp + fp)}`, `detection_error_rate ${ratio(fp + fn, input.annotations.length)}`,
    'by_method ' + (['threshold', 'searchback'] as const).map(method => {
      const group = beats.filter(b => b.method === method); return `${method}=${group.filter(b => b.reference !== null).length}/${group.length}`;
    }).join(' ')];
  const offsets = beats.filter(b => b.reference !== null).map(b => 5 * (b.sample - input.annotations[b.reference!].sample));
  rows.push(tp ? `offset_ms mean=${decimal2(rdiv(100 * sum(offsets), tp))} mean_abs=${decimal2(rdiv(100 * sum(offsets.map(Math.abs)), tp))} max_abs=${Math.max(...offsets.map(Math.abs))}` : 'offset_ms none',
    'CONFUSION', 'ref  ' + LABELS.map(label => pad(label, 6)).join('') + '  miss');
  for (const label of LABELS) {
    const references = input.annotations.map((a, i) => ({ annotation: a, match: matches[i] })).filter(r => r.annotation.label === label);
    rows.push(label + '    ' + LABELS.map(predicted => pad(references.filter(r => r.match >= 0 && beats[r.match].label === predicted).length, 6)).join('')
      + pad(references.filter(r => r.match < 0).length, 6));
  }
  rows.push('extra' + LABELS.map(label => pad(beats.filter(b => b.label === label && b.reference === null).length, 6)).join(''));
  for (const [label, name] of [['V', 'veb'], ['A', 'sveb']] as const) {
    const hits = beats.filter(b => b.label === label && b.reference !== null && input.annotations[b.reference].label === label).length;
    rows.push(`${name}_sensitivity ${ratio(hits, input.annotations.filter(a => a.label === label).length)}`,
      `${name}_positive_predictivity ${ratio(hits, beats.filter(b => b.label === label).length)}`);
  }
  rows.push(`SEGMENTS segment_ms=${input.settings.segment} segments=${analysis.segments.length}`);
  for (const segment of analysis.segments) {
    const matched = segment.references.filter(r => r.matched).length;
    rows.push(`${pad(segment.start, 6)}-${pad(segment.end, 6)} refs=${segment.references.length} tp=${matched} fp=${segment.beats.filter(b => b.reference === null).length} fn=${segment.references.length - matched} noise_peaks=${segment.noise}`);
  }
  const errors = beats.filter(b => b.reference === null).map(b => ({ sample: b.sample, order: 0,
    text: `false_positive beat=${b.number} sample=${b.sample} time_ms=${5 * b.sample} label=${b.label}` }));
  input.annotations.forEach((annotation, i) => { if (matches[i] < 0) errors.push({ sample: annotation.sample, order: 1,
    text: `false_negative sample=${annotation.sample} time_ms=${5 * annotation.sample} label=${annotation.label}` }); });
  errors.sort((a, b) => a.sample - b.sample || a.order - b.order);
  rows.push(`ERRORS count=${fp + fn}`, ...errors.map(error => error.text));
  return rows;
}
function eventRows(input: Input, beats: Beat[]): string[] {
  const rows: string[] = [];
  beats.forEach((beat, i) => { if (i > 0 && beat.rr! > input.settings.pause)
    rows.push(`pause beats=${i}-${i + 1} rr_ms=${beat.rr} start_ms=${5 * beats[i - 1].sample}`); });
  for (const [kind, predicate] of [
    ['bradycardia', (v: number) => v > input.settings.brady], ['tachycardia', (v: number) => v < input.settings.tachy],
  ] as const) for (const range of ranges(beats, (beat, i) => i >= 1 && predicate(beat.rr!))) {
    const count = range.end - range.start + 1;
    if (count >= 3) rows.push(`${kind} beats=${range.start}-${range.end + 1} intervals=${count} mean_hr=${decimal2(rdiv(6000000 * count,
      sum(beats.slice(range.start, range.end + 1).map(b => b.rr!))))} start_ms=${5 * beats[range.start - 1].sample}`);
  }
  const ventricular = beats.flatMap((beat, i) => beat.label === 'V' ? [i] : []);
  for (const [kind, gap] of [['bigeminy', 2], ['trigeminy', 3]] as const) {
    for (let i = 0; i < ventricular.length;) {
      const start = i++;
      while (i < ventricular.length && ventricular[i] === ventricular[i - 1] + gap
        && beats.slice(ventricular[i - 1] + 1, ventricular[i]).every(b => b.label === 'N')) i++;
      if (i - start >= 3) rows.push(`${kind} beats=${ventricular[start] + 1}-${ventricular[i - 1] + 1} cycles=${i - start} start_ms=${5 * beats[ventricular[start]].sample}`);
    }
  }
  return rows;
}
function hrvRows(input: Input, beats: Beat[], analysis: Analysis): string[] {
  const { rr, nn, pairs, bins, binMax, statistics: stats } = analysis;
  let shortest: Beat | null = null, longest: Beat | null = null;
  for (const beat of beats.slice(1)) {
    if (shortest === null || beat.rr! < shortest.rr!) shortest = beat;
    if (longest === null || beat.rr! > longest.rr!) longest = beat;
  }
  const rows = ['RR', `beats ${beats.length}`, `intervals ${rr.length}`, `mean_rr_ms ${decimalOrNone(stats.meanRR)}`,
    shortest ? `min_rr_ms ${shortest.rr} beat=${shortest.number}` : 'min_rr_ms none',
    longest ? `max_rr_ms ${longest.rr} beat=${longest.number}` : 'max_rr_ms none', `mean_hr_bpm ${decimalOrNone(stats.meanHR)}`,
    'NN', `intervals ${nn.length}`, `mean_nn_ms ${decimalOrNone(stats.meanNN)}`, `sdnn_ms ${decimalOrNone(stats.sdnn)}`, `differences ${pairs.length}`,
    `rmssd_ms ${decimalOrNone(stats.rmssd)}`, `sdsd_ms ${decimalOrNone(stats.sdsd)}`, `nn50 ${stats.nn50}`,
    stats.pnn50 === null ? 'pnn50 none' : `pnn50 ${decimal2(stats.pnn50)}%`, `sd1_ms ${decimalOrNone(stats.sd1)}`, `sd2_ms ${decimalOrNone(stats.sd2)}`,
    `HISTOGRAM bin_ms=7.8125 bins=${bins.length} max=${binMax}`];
  for (const [bin, count] of bins) rows.push(`${pad(decimal4(78125 * bin), 10)} ${pad(decimal4(78125 * (bin + 1)), 10)} ${pad(count, 3)} |${'#'.repeat(count)}`);
  rows.push(nn.length ? `triangular_index ${fraction(nn.length, binMax)} ${decimal2(rdiv(100 * nn.length, binMax))}` : 'triangular_index none');
  const premature = beats.filter(b => b.label !== 'N');
  rows.push(`PREMATURE count=${premature.length} V=${premature.filter(b => b.label === 'V').length} A=${premature.filter(b => b.label === 'A').length}`);
  for (const beat of premature) {
    const i = beat.number - 1, previous = sum(beats.slice(i - 8, i).map(b => b.rr!)), next = beats[i + 1]?.rr ?? null;
    const total = beat.rr! + (next ?? 0), compensation = next === null ? '-' : 10 * Math.abs(4 * total - previous) <= previous ? 'full' : 4 * total < previous ? 'partial' : 'long';
    rows.push(`beat=${beat.number} sample=${beat.sample} label=${beat.label} rr_ms=${beat.rr} next_rr_ms=${missing(next)} mean_ms=${decimal2(rdiv(100 * previous, 8))} prematurity=${decimal2(rdiv(80000 * beat.rr!, previous))}% compensation=${compensation} width_ms=${beat.width} ref=${beat.reference === null ? '-' : input.annotations[beat.reference].label}`);
  }
  const runs = (['V', 'A'] as const).flatMap(label => ranges(beats, b => b.label === label).map(range => ({ ...range, label }))).sort((a, b) => a.start - b.start);
  rows.push(`RUNS count=${runs.length}`);
  for (const run of runs) {
    const length = run.end - run.start + 1;
    rows.push(`${run.label} ${length === 1 ? 'isolated' : length === 2 ? 'couplet' : 'run'} beats=${run.start + 1}-${run.end + 1} length=${length} start_ms=${5 * beats[run.start].sample}`);
  }
  const events = eventRows(input, beats);
  rows.push(`EVENTS count=${events.length}`, ...events, `TREND segment_ms=${input.settings.segment} segments=${analysis.segments.length}`);
  for (const segment of analysis.segments) {
    const intervals = segment.beats.flatMap(b => b.rr === null ? [] : [b.rr]);
    const prefix = `${pad(segment.start, 6)}-${pad(segment.end, 6)} beats=${segment.beats.length}`;
    if (!intervals.length) rows.push(prefix + ' mean_hr=none min_hr=none max_hr=none |');
    else {
      const mean = rdiv(6000000 * intervals.length, sum(intervals));
      rows.push(`${prefix} mean_hr=${decimal2(mean)} min_hr=${decimal2(rdiv(6000000, Math.max(...intervals)))} max_hr=${decimal2(rdiv(6000000, Math.min(...intervals)))} |${'#'.repeat(rdiv(mean, 500))}`);
    }
  }
  return rows;
}
function scale(value: number, top: number, bottom: number, rows: number): number {
  return top === bottom ? 0 : rdiv((top - value) * (rows - 1), top - bottom);
}
function waveform(high: number[], low: number[], height: number): string[] {
  const top = Math.max(...high), bottom = Math.min(...low), zero = bottom <= 0 && top >= 0 ? scale(0, top, bottom, height) : -1;
  return Array.from({ length: height }, (_, row) => {
    const label = row === 0 ? top : row === height - 1 ? bottom : row === zero ? 0 : '';
    const cells = high.map((value, column) => scale(value, top, bottom, height) <= row && row <= scale(low[column], top, bottom, height) ? '#' : row === zero ? '-' : ' ').join('');
    return `${pad(label, 6)} |${cells}|`;
  });
}
const axis = (columns: number, marked: (column: number) => boolean): string => '       +'
  + Array.from({ length: columns }, (_, column) => marked(column) ? '+' : '-').join('') + '+';
function labelRow(heading: string, pairs: [number, string][]): string {
  let row = pad(heading, 6) + '  ';
  for (const [column, label] of pairs) row += ' '.repeat(8 + column - row.length) + label;
  return row.trimEnd();
}
function chartRows(input: Input, beats: Beat[], analysis: Analysis): string[] {
  const rows: string[] = [], rr = analysis.rr, height = input.settings.chartRows;
  if (!rr.length) rows.push('TACHOGRAM intervals=0', 'POINCARE points=0');
  else {
    const low = Math.min(...rr), high = Math.max(...rr), size = input.settings.poincareSize;
    rows.push(`TACHOGRAM intervals=${rr.length} min_ms=${low} max_ms=${high} rows=${height}`);
    for (let r = 0; r < height; r++) rows.push(`${pad(r === 0 ? high : r === height - 1 ? low : '', 6)} |${rr.map(value => scale(value, high, low, height) === r ? '*' : ' ').join('')}|`);
    rows.push(axis(rr.length, j => (j + 2) % 10 === 0), labelRow('beat', rr.flatMap((_, j): [number, string][] => (j + 2) % 10 === 0 ? [[j, String(j + 2)]] : [])),
      ' label |' + beats.slice(1).map(b => b.label).join('') + '|');
    const grid = Array.from({ length: size }, () => Array<number>(size).fill(0));
    for (let i = 1; i < rr.length; i++) {
      const column = high === low ? 0 : rdiv((rr[i - 1] - low) * (size - 1), high - low);
      grid[scale(rr[i], high, low, size)][column]++;
    }
    rows.push(`POINCARE points=${beats.length - 2} size=${size} min_ms=${low} max_ms=${high}`);
    grid.forEach((cells, r) => rows.push(`${pad(r === 0 ? high : r === size - 1 ? low : '', 6)} |${cells.map(count => count === 0 ? '.' : count < 10 ? String(count) : '#').join('')}|`));
    rows.push('       +' + '-'.repeat(size) + '+', '        ' + low + ' '.repeat(size - String(low).length - String(high).length) + high);
  }
  for (const label of LABELS) {
    const selected = beats.filter(b => b.label === label && b.sample >= 60 && b.sample <= input.signal.length - 100);
    if (!selected.length) { rows.push(`TEMPLATE ${label} beats=0`); continue; }
    const baselines = selected.map(b => sum(input.signal.slice(b.sample - 60, b.sample - 50)));
    const values = Array.from({ length: 160 }, (_, j) => rdiv(sum(selected.map((b, i) => 10 * input.signal[b.sample + j - 60] - baselines[i])), 10 * selected.length));
    const maximum = Math.max(...values), minimum = Math.min(...values);
    rows.push(`TEMPLATE ${label} beats=${selected.length} max_uv=${maximum} max_ms=${5 * (values.indexOf(maximum) - 60)} min_uv=${minimum} min_ms=${5 * (values.indexOf(minimum) - 60)} rows=${height}`,
      ...waveform(Array.from({ length: 80 }, (_, i) => Math.max(values[2 * i], values[2 * i + 1])),
        Array.from({ length: 80 }, (_, i) => Math.min(values[2 * i], values[2 * i + 1])), height),
      axis(80, i => i % 10 === 0), labelRow('ms', Array.from({ length: 8 }, (_, i) => [10 * i, String(100 * i - 300)])));
  }
  return rows;
}
function stripRows(input: Input, beats: Beat[]): string[] {
  const s = input.settings, start = div(s.stripStart, 5), length = div(s.stripLength, 5), columns = div(length, 10);
  const samples = input.signal.slice(start, start + length), groups = Array.from({ length: columns }, (_, i) => samples.slice(10 * i, 10 * i + 10));
  const marks = Array<string>(columns).fill(' '), references = marks.slice();
  for (const beat of beats) if (start <= beat.sample && beat.sample < start + length) marks[div(beat.sample - start, 10)] = beat.label;
  for (const annotation of input.annotations) if (start <= annotation.sample && annotation.sample < start + length) references[div(annotation.sample - start, 10)] = annotation.label;
  return [`RHYTHM start_ms=${s.stripStart} end_ms=${s.stripStart + s.stripLength} columns=${columns} rows=${s.stripRows} max_uv=${Math.max(...samples)} min_uv=${Math.min(...samples)}`,
    ...waveform(groups.map(group => Math.max(...group)), groups.map(group => Math.min(...group)), s.stripRows), axis(columns, i => i % 20 === 0),
    labelRow('s', groups.flatMap((_, i): [number, string][] => i % 20 === 0 ? [[i, String(div(s.stripStart + 50 * i, 1000))]] : [])),
    ' beats |' + marks.join('') + '|', '  refs |' + references.join('') + '|'];
}
function main(): void {
  const input = readInput(), signals = filter(input.signal), detection = detect(signals, input.settings);
  const beats = makeBeats(detection, signals, input.settings), matches = matchBeats(input, beats), analysis = analyze(input, detection, beats, matches);
  const peaks = ['peak,sample,r_sample,peak_i,peak_f,slope,thr_i,thr_f,class', ...detection.peaks.map((peak, i) =>
    [i + 1, peak.time, peak.r, peak.integrated, peak.filtered, peak.slope, peak.thresholdI, peak.thresholdF, peak.kind].join(','))];
  const excerpt = ['sample,ecg,lowpass,bandpass,derivative,squared,integrated', ...input.signal.slice(0, div(input.settings.excerpt, 5)).map((value, i) =>
    [i, value, signals.lowpass[i], signals.bandpass[i], signals.derivative[i], signals.squared[i], signals.integrated[i]].join(','))];
  writeReports({ 'beats.csv': beatRows(input, beats), 'peaks.csv': peaks, 'matching.csv': matchingRows(input, beats, matches),
    'signals_excerpt.csv': excerpt, 'performance.txt': performanceRows(input, detection, beats, matches, analysis),
    'hrv.txt': hrvRows(input, beats, analysis), 'charts.txt': chartRows(input, beats, analysis), 'rhythm_strip.txt': stripRows(input, beats) });
}
main();
