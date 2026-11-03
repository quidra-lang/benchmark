'use strict';

const { readInput, writeLines } = require('./signal_io');
const { filterSignal } = require('./filters');
const { findPeaks, qrsWidth, initialLevels } = require('./detector');
const { sum, meanHeartRate, intervalStatistics, histogram, ranges } = require('./hrv');
const { rdiv, decimal2, decimal4, fraction, ratio, missing } = require('./report');
const LABELS = ['N', 'V', 'A'];
const CLASSES = ['qrs', 'searchback', 'twave', 'refractory', 'noise'];
const pad = (value, width) => String(value).padStart(width, ' ');
const numberOrNone = value => value === null ? 'none' : decimal2(value);

class Detector {
    constructor(signals, parameters) {
        this.peaks = findPeaks(signals);
        this.initial = initialLevels(signals);
        this.levels = { ...this.initial };
        this.parameters = parameters;
        this.length = signals.ecg.length;
        this.registered = [];
        this.last = null;
        this.intervals = [];
        this.average1 = this.average2 = 200;
    }

    thresholds() {
        const { spki, npki, spkf, npkf } = this.levels;
        return { integrated: npki + Math.floor((spki - npki) / 4), bandpass: npkf + Math.floor((spkf - npkf) / 4) };
    }

    update(peak, kind) {
        const signal = kind !== 'noise';
        const divisor = kind === 'searchback' ? 4 : 8;
        const i = signal ? 'spki' : 'npki';
        const f = signal ? 'spkf' : 'npkf';
        this.levels[i] = Math.floor((peak.peakI + (divisor - 1) * this.levels[i]) / divisor);
        this.levels[f] = Math.floor((peak.peakF + (divisor - 1) * this.levels[f]) / divisor);
    }

    register(peak) {
        if (this.last !== null) {
            const interval = peak.time - this.last.time;
            this.intervals.push(interval);
            if (this.intervals.length > 8) this.intervals.shift();
            this.average1 = Math.floor(sum(this.intervals) / this.intervals.length);
            if (92 * this.average1 <= 100 * interval && 100 * interval <= 116 * this.average1) this.average2 = this.average1;
        }
        this.last = peak;
        this.registered.push(peak);
    }

    searchBack(time) {
        while (true) {
            const previous = this.last?.time ?? 0;
            if (time - previous <= Math.floor(this.average2 * this.parameters.searchback_percent / 100)) return;
            const thresholds = this.thresholds();
            const lowI = Math.floor(thresholds.integrated / 2);
            const lowF = Math.floor(thresholds.bandpass / 2);
            let selected = null;
            for (const peak of this.peaks) {
                if (peak.kind !== 'noise' || peak.time <= previous || peak.time >= time || peak.peakI <= lowI || peak.peakF <= lowF) continue;
                if (selected === null || peak.peakI > selected.peakI) selected = peak;
            }
            if (selected === null) return;
            this.update(selected, 'searchback');
            selected.kind = 'searchback';
            this.register(selected);
        }
    }

    run() {
        const refractory = Math.floor(this.parameters.refractory_ms / 5);
        const twave = Math.floor(this.parameters.twave_ms / 5);
        for (const peak of this.peaks) {
            this.searchBack(peak.time);
            const thresholds = this.thresholds();
            peak.thresholdI = thresholds.integrated;
            peak.thresholdF = thresholds.bandpass;
            if (this.last !== null && peak.time - this.last.time < refractory) peak.kind = 'refractory';
            else if (peak.peakI > peak.thresholdI && peak.peakF > peak.thresholdF) {
                if (this.last !== null && peak.time - this.last.time < twave && 2 * peak.slope < this.last.slope) {
                    peak.kind = 'twave';
                    this.update(peak, 'noise');
                } else {
                    peak.kind = 'qrs';
                    this.update(peak, 'signal');
                    this.register(peak);
                }
            } else { peak.kind = 'noise'; this.update(peak, 'noise'); }
        }
        this.searchBack(this.length);
    }
}

function describeBeats(detector, signals, parameters) {
    const beats = [];
    for (const peak of detector.registered) {
        const sample = Math.max(0, peak.position - 21);
        const previous = beats.at(-1);
        const rr = previous ? 5 * (sample - previous.sample) : null;
        const beat = { number: beats.length + 1, sample, rr, width: qrsWidth(signals.bandpass, peak.position),
            label: 'N', method: peak.kind === 'qrs' ? 'threshold' : 'searchback', reference: null, previousTotal: null, nn: false };
        if (beat.number >= 10) {
            beat.previousTotal = sum(beats.slice(-8).map(item => item.rr));
            if (800 * rr < parameters.premature_percent * beat.previousTotal) beat.label = beat.width > parameters.qrs_width_ms ? 'V' : 'A';
        }
        if (beat.number >= 3 && previous.label === 'N' && beat.label === 'N' && 5 * Math.abs(rr - previous.rr) <= previous.rr) beat.nn = true;
        beats.push(beat);
    }
    return beats;
}

function matchBeats(beats, annotations, tolerance) {
    for (const beat of beats) {
        let selected = null;
        let distance = tolerance + 1;
        for (const annotation of annotations) {
            if (annotation.beat !== null) continue;
            const candidate = Math.abs(annotation.sample - beat.sample);
            if (candidate <= tolerance && candidate < distance) { selected = annotation; distance = candidate; }
        }
        if (selected !== null) { selected.beat = beat; beat.reference = selected; }
    }
}

function makeSegments(length, parameters, beats, annotations, peaks) {
    const size = Math.floor(parameters.segment_ms / 5);
    const segments = [];
    for (let start = 0; start < length; start += size) {
        const end = Math.min(start + size, length);
        segments.push({ start: 5 * start, end: 5 * end,
            beats: beats.filter(beat => start <= beat.sample && beat.sample < end),
            annotations: annotations.filter(annotation => start <= annotation.sample && annotation.sample < end),
            peaks: peaks.filter(peak => start <= peak.time && peak.time < end) });
    }
    return segments;
}

function beatLines(beats) {
    return ['beat,sample,time_ms,rr_ms,hr_bpm,width_ms,label,method,ref_sample,ref_label', ...beats.map(beat =>
        [beat.number, beat.sample, 5 * beat.sample, missing(beat.rr), beat.rr === null ? '-' : decimal2(rdiv(6000000, beat.rr)),
            beat.width, beat.label, beat.method, missing(beat.reference?.sample), missing(beat.reference?.label)].join(','))];
}

function peakLines(peaks) {
    return ['peak,sample,r_sample,peak_i,peak_f,slope,thr_i,thr_f,class', ...peaks.map(peak =>
        [peak.number, peak.time, peak.position, peak.peakI, peak.peakF, peak.slope, peak.thresholdI, peak.thresholdF, peak.kind].join(','))];
}

function matchingLines(beats, annotations) {
    const entries = annotations.map(annotation => {
        const beat = annotation.beat;
        const line = beat === null ? `${annotation.sample},${annotation.label},-,-,-,-,FN,-`
            : `${annotation.sample},${annotation.label},${beat.number},${beat.sample},${beat.label},${5 * (beat.sample - annotation.sample)},TP,${beat.label === annotation.label ? 'yes' : 'no'}`;
        return { sample: annotation.sample, order: 0, line };
    });
    for (const beat of beats) if (beat.reference === null) entries.push({ sample: beat.sample, order: 1,
        line: `-,-,${beat.number},${beat.sample},${beat.label},-,FP,-` });
    entries.sort((a, b) => a.sample - b.sample || a.order - b.order);
    return ['ref_sample,ref_label,beat,beat_sample,beat_label,offset_ms,status,agree', ...entries.map(entry => entry.line)];
}

function signalLines(signals, parameters) {
    const names = ['ecg', 'lowpass', 'bandpass', 'derivative', 'squared', 'integrated'];
    const lines = ['sample,' + names.join(',')];
    for (let sample = 0; sample < Math.floor(parameters.excerpt_ms / 5); sample++)
        lines.push([sample, ...names.map(name => signals[name][sample])].join(','));
    return lines;
}

function performanceLines(detector, beats, annotations, segments) {
    const { parameters, peaks } = detector;
    const matched = beats.filter(beat => beat.reference !== null);
    const extra = beats.filter(beat => beat.reference === null);
    const missed = annotations.filter(annotation => annotation.beat === null);
    const thresholds = detector.thresholds();
    const levels = values => ['spki', 'npki', 'spkf', 'npkf'].map(name => `${name}=${values[name]}`).join(' ');
    const counts = values => LABELS.map(label => `${label}=${values.filter(value => value.label === label).length}`).join(' ');
    const lines = ['DETECTOR', 'samples ' + detector.length, 'duration_ms ' + 5 * detector.length,
        `peaks ${peaks.length} ` + CLASSES.map(kind => `${kind}=${peaks.filter(peak => peak.kind === kind).length}`).join(' '),
        'initial_levels ' + levels(detector.initial), 'final_levels ' + levels(detector.levels),
        `final_thresholds thr_i=${thresholds.integrated} thr_f=${thresholds.bandpass}`,
        `final_rr_averages rravg1_ms=${5 * detector.average1} rravg2_ms=${5 * detector.average2}`,
        'MATCHING', 'tolerance_ms ' + parameters.match_ms,
        `references ${annotations.length} ${counts(annotations)}`, `detections ${beats.length} ${counts(beats)}`,
        'true_positives ' + matched.length, 'false_positives ' + extra.length, 'false_negatives ' + missed.length,
        'sensitivity ' + ratio(matched.length, annotations.length), 'positive_predictivity ' + ratio(matched.length, beats.length),
        'detection_error_rate ' + ratio(extra.length + missed.length, annotations.length)];
    lines.push('by_method ' + ['threshold', 'searchback'].map(method =>
        `${method}=${matched.filter(beat => beat.method === method).length}/${beats.filter(beat => beat.method === method).length}`).join(' '));
    if (matched.length) {
        const offsets = matched.map(beat => 5 * (beat.sample - beat.reference.sample));
        lines.push(`offset_ms mean=${decimal2(rdiv(100 * sum(offsets), offsets.length))} mean_abs=${decimal2(rdiv(100 * sum(offsets.map(Math.abs)), offsets.length))} max_abs=${Math.max(...offsets.map(Math.abs))}`);
    } else lines.push('offset_ms none');
    lines.push('CONFUSION', 'ref  ' + LABELS.map(label => pad(label, 6)).join('') + '  miss');
    for (const label of LABELS) lines.push(label + '    ' + LABELS.map(predicted =>
        pad(matched.filter(beat => beat.reference.label === label && beat.label === predicted).length, 6)).join('')
        + pad(missed.filter(annotation => annotation.label === label).length, 6));
    lines.push('extra' + LABELS.map(label => pad(extra.filter(beat => beat.label === label).length, 6)).join(''));
    for (const [label, name] of [['V', 'veb'], ['A', 'sveb']]) {
        const hits = matched.filter(beat => beat.label === label && beat.reference.label === label).length;
        lines.push(name + '_sensitivity ' + ratio(hits, annotations.filter(annotation => annotation.label === label).length),
            name + '_positive_predictivity ' + ratio(hits, beats.filter(beat => beat.label === label).length));
    }
    lines.push(`SEGMENTS segment_ms=${parameters.segment_ms} segments=${segments.length}`);
    for (const segment of segments) {
        const tp = segment.annotations.filter(annotation => annotation.beat !== null).length;
        lines.push(`${pad(segment.start, 6)}-${pad(segment.end, 6)} refs=${segment.annotations.length} tp=${tp} fp=${segment.beats.filter(beat => beat.reference === null).length} fn=${segment.annotations.length - tp} noise_peaks=${segment.peaks.filter(peak => peak.kind === 'noise').length}`);
    }
    lines.push('ERRORS count=' + (extra.length + missed.length));
    const errors = extra.map(beat => ({ sample: beat.sample, order: 0,
        line: `false_positive beat=${beat.number} sample=${beat.sample} time_ms=${5 * beat.sample} label=${beat.label}` }));
    for (const annotation of missed) errors.push({ sample: annotation.sample, order: 1,
        line: `false_negative sample=${annotation.sample} time_ms=${5 * annotation.sample} label=${annotation.label}` });
    errors.sort((a, b) => a.sample - b.sample || a.order - b.order);
    lines.push(...errors.map(error => error.line));
    return lines;
}

function runLines(beats) {
    const runs = [];
    for (const label of ['V', 'A']) {
        for (const [start, end] of ranges(beats, beat => beat.label === label)) {
            const length = end - start + 1;
            const kind = length === 1 ? 'isolated' : length === 2 ? 'couplet' : 'run';
            runs.push({ start, line: `${label} ${kind} beats=${beats[start].number}-${beats[end].number} length=${length} start_ms=${5 * beats[start].sample}` });
        }
    }
    runs.sort((a, b) => a.start - b.start);
    return runs.map(run => run.line);
}

function eventLines(beats, parameters) {
    const lines = [];
    for (let i = 1; i < beats.length; i++) if (beats[i].rr > parameters.pause_ms)
        lines.push(`pause beats=${beats[i - 1].number}-${beats[i].number} rr_ms=${beats[i].rr} start_ms=${5 * beats[i - 1].sample}`);
    for (const [kind, predicate] of [
        ['bradycardia', beat => beat.rr !== null && beat.rr > parameters.brady_ms],
        ['tachycardia', beat => beat.rr !== null && beat.rr < parameters.tachy_ms]
    ]) {
        for (const [start, end] of ranges(beats, predicate)) {
            const count = end - start + 1;
            if (count < 3) continue;
            const rate = meanHeartRate(beats.slice(start, end + 1).map(beat => beat.rr));
            lines.push(`${kind} beats=${beats[start - 1].number}-${beats[end].number} intervals=${count} mean_hr=${decimal2(rate)} start_ms=${5 * beats[start - 1].sample}`);
        }
    }
    const ventricular = beats.map((beat, index) => beat.label === 'V' ? index : -1).filter(index => index >= 0);
    for (const [kind, spacing] of [['bigeminy', 2], ['trigeminy', 3]]) {
        let sequence = [];
        const finish = () => {
            if (sequence.length >= 3) lines.push(`${kind} beats=${beats[sequence[0]].number}-${beats[sequence.at(-1)].number} cycles=${sequence.length} start_ms=${5 * beats[sequence[0]].sample}`);
        };
        for (const index of ventricular) {
            const previous = sequence.at(-1);
            const linked = sequence.length > 0 && index === previous + spacing && beats.slice(previous + 1, index).every(beat => beat.label === 'N');
            if (!linked) { finish(); sequence = []; }
            sequence.push(index);
        }
        finish();
    }
    return lines;
}

function hrvLines(beats, segments, parameters) {
    const rr = beats.slice(1).map(beat => beat.rr);
    const nn = beats.filter(beat => beat.nn).map(beat => beat.rr);
    const pairs = [];
    for (let i = 1; i < beats.length; i++) if (beats[i - 1].nn && beats[i].nn) pairs.push([beats[i - 1].rr, beats[i].rr]);
    const stats = intervalStatistics(rr, nn, pairs);
    const lines = ['RR', 'beats ' + beats.length, 'intervals ' + rr.length, 'mean_rr_ms ' + numberOrNone(stats.meanRR)];
    if (rr.length) {
        let shortest = beats[1];
        let longest = beats[1];
        for (const beat of beats.slice(2)) {
            if (beat.rr < shortest.rr) shortest = beat;
            if (beat.rr > longest.rr) longest = beat;
        }
        lines.push(`min_rr_ms ${shortest.rr} beat=${shortest.number}`, `max_rr_ms ${longest.rr} beat=${longest.number}`);
    } else lines.push('min_rr_ms none', 'max_rr_ms none');
    lines.push('mean_hr_bpm ' + numberOrNone(stats.meanHR), 'NN', 'intervals ' + nn.length,
        'mean_nn_ms ' + numberOrNone(stats.meanNN), 'sdnn_ms ' + numberOrNone(stats.sdnn), 'differences ' + pairs.length,
        'rmssd_ms ' + numberOrNone(stats.rmssd), 'sdsd_ms ' + numberOrNone(stats.sdsd), 'nn50 ' + stats.nn50,
        'pnn50 ' + (stats.pnn50 === null ? 'none' : decimal2(stats.pnn50) + '%'),
        'sd1_ms ' + numberOrNone(stats.sd1), 'sd2_ms ' + numberOrNone(stats.sd2));
    const bins = histogram(nn);
    const maximum = bins.length ? Math.max(...bins.map(([, count]) => count)) : 0;
    lines.push(`HISTOGRAM bin_ms=7.8125 bins=${bins.length} max=${maximum}`);
    for (const [bin, count] of bins) lines.push(`${pad(decimal4(78125 * bin), 10)} ${pad(decimal4(78125 * (bin + 1)), 10)} ${pad(count, 3)} |${'#'.repeat(count)}`);
    lines.push('triangular_index ' + (nn.length ? `${fraction(nn.length, maximum)} ${decimal2(rdiv(100 * nn.length, maximum))}` : 'none'));
    const premature = beats.filter(beat => beat.label !== 'N');
    lines.push(`PREMATURE count=${premature.length} V=${premature.filter(beat => beat.label === 'V').length} A=${premature.filter(beat => beat.label === 'A').length}`);
    for (const beat of premature) {
        const next = beats[beat.number];
        const total = beat.previousTotal;
        let compensation = '-';
        if (next) {
            const pair = beat.rr + next.rr;
            compensation = 10 * Math.abs(4 * pair - total) <= total ? 'full' : 4 * pair < total ? 'partial' : 'long';
        }
        lines.push(`beat=${beat.number} sample=${beat.sample} label=${beat.label} rr_ms=${beat.rr} next_rr_ms=${missing(next?.rr)} mean_ms=${decimal2(rdiv(100 * total, 8))} prematurity=${decimal2(rdiv(80000 * beat.rr, total))}% compensation=${compensation} width_ms=${beat.width} ref=${missing(beat.reference?.label)}`);
    }
    const runs = runLines(beats);
    lines.push('RUNS count=' + runs.length, ...runs);
    const events = eventLines(beats, parameters);
    lines.push('EVENTS count=' + events.length, ...events);
    lines.push(`TREND segment_ms=${parameters.segment_ms} segments=${segments.length}`);
    for (const segment of segments) {
        const intervals = segment.beats.filter(beat => beat.rr !== null).map(beat => beat.rr);
        const prefix = `${pad(segment.start, 6)}-${pad(segment.end, 6)} beats=${segment.beats.length}`;
        if (intervals.length) {
            const mean = meanHeartRate(intervals);
            lines.push(`${prefix} mean_hr=${decimal2(mean)} min_hr=${decimal2(rdiv(6000000, Math.max(...intervals)))} max_hr=${decimal2(rdiv(6000000, Math.min(...intervals)))} |${'#'.repeat(rdiv(mean, 500))}`);
        } else lines.push(prefix + ' mean_hr=none min_hr=none max_hr=none |');
    }
    return lines;
}

const scale = (value, top, bottom, height) => top > bottom ? rdiv((top - value) * (height - 1), top - bottom) : 0;

function waveform(highs, lows, height) {
    const top = Math.max(...highs);
    const bottom = Math.min(...lows);
    const zero = bottom <= 0 && top >= 0 ? scale(0, top, bottom, height) : null;
    const highRows = highs.map(value => scale(value, top, bottom, height));
    const lowRows = lows.map(value => scale(value, top, bottom, height));
    return Array.from({ length: height }, (_, row) => {
        const label = row === 0 ? top : row === height - 1 ? bottom : row === zero ? 0 : '';
        const cells = highRows.map((high, column) => high <= row && row <= lowRows[column] ? '#' : row === zero ? '-' : ' ');
        return `${pad(label, 6)} |${cells.join('')}|`;
    });
}

function axisRow(width, marked) {
    return '       +' + Array.from({ length: width }, (_, column) => marked(column) ? '+' : '-').join('') + '+';
}

function labelRow(heading, labels) {
    let line = pad(heading, 6);
    for (const [column, value] of labels) line = line.padEnd(8 + column, ' ') + value;
    return line;
}

function intervalCharts(beats, parameters) {
    const rr = beats.slice(1).map(beat => beat.rr);
    if (rr.length === 0) return ['TACHOGRAM intervals=0', 'POINCARE points=0'];
    const low = Math.min(...rr);
    const high = Math.max(...rr);
    const height = parameters.chart_rows;
    const lines = [`TACHOGRAM intervals=${rr.length} min_ms=${low} max_ms=${high} rows=${height}`];
    const scaled = rr.map(value => scale(value, high, low, height));
    for (let row = 0; row < height; row++) {
        const label = row === 0 ? high : row === height - 1 ? low : '';
        lines.push(`${pad(label, 6)} |${scaled.map(position => position === row ? '*' : ' ').join('')}|`);
    }
    const labels = [];
    for (let column = 0; column < rr.length; column++) if ((column + 2) % 10 === 0) labels.push([column, column + 2]);
    lines.push(axisRow(rr.length, column => (column + 2) % 10 === 0), labelRow('beat', labels), ' label |' + beats.slice(1).map(beat => beat.label).join('') + '|');
    const size = parameters.poincare_size;
    const cells = Array.from({ length: size }, () => Array(size).fill(0));
    for (let i = 0; i + 1 < rr.length; i++) {
        const column = high > low ? rdiv((rr[i] - low) * (size - 1), high - low) : 0;
        const row = scale(rr[i + 1], high, low, size);
        cells[row][column]++;
    }
    lines.push(`POINCARE points=${beats.length - 2} size=${size} min_ms=${low} max_ms=${high}`);
    for (let row = 0; row < size; row++) {
        const label = row === 0 ? high : row === size - 1 ? low : '';
        lines.push(`${pad(label, 6)} |${cells[row].map(count => count === 0 ? '.' : count <= 9 ? String(count) : '#').join('')}|`);
    }
    lines.push('       +' + '-'.repeat(size) + '+', ('        ' + low).padEnd(8 + size - String(high).length, ' ') + high);
    return lines;
}

function templateCharts(ecg, beats, parameters) {
    const lines = [];
    for (const label of LABELS) {
        const selected = beats.filter(beat => beat.label === label && beat.sample >= 60 && beat.sample <= ecg.length - 100);
        if (selected.length === 0) { lines.push(`TEMPLATE ${label} beats=0`); continue; }
        const baselines = selected.map(beat => sum(ecg.slice(beat.sample - 60, beat.sample - 50)));
        const values = Array.from({ length: 160 }, (_, index) => {
            let total = 0;
            for (let k = 0; k < selected.length; k++) total += 10 * ecg[selected[k].sample + index - 60] - baselines[k];
            return rdiv(total, 10 * selected.length);
        });
        const top = Math.max(...values);
        const bottom = Math.min(...values);
        const highs = [];
        const lows = [];
        for (let i = 0; i < 160; i += 2) { highs.push(Math.max(values[i], values[i + 1])); lows.push(Math.min(values[i], values[i + 1])); }
        lines.push(`TEMPLATE ${label} beats=${selected.length} max_uv=${top} max_ms=${5 * (values.indexOf(top) - 60)} min_uv=${bottom} min_ms=${5 * (values.indexOf(bottom) - 60)} rows=${parameters.chart_rows}`,
            ...waveform(highs, lows, parameters.chart_rows), axisRow(80, column => column % 10 === 0),
            labelRow('ms', Array.from({ length: 8 }, (_, index) => [10 * index, 100 * index - 300])));
    }
    return lines;
}

function rhythmLines(ecg, beats, annotations, parameters) {
    const start = Math.floor(parameters.strip_start_ms / 5);
    const length = Math.floor(parameters.strip_ms / 5);
    const width = Math.floor(length / 10);
    const highs = [];
    const lows = [];
    for (let column = 0; column < width; column++) {
        const values = ecg.slice(start + 10 * column, start + 10 * column + 10);
        highs.push(Math.max(...values));
        lows.push(Math.min(...values));
    }
    const labels = [];
    for (let column = 0; column < width; column += 20) labels.push([column, Math.floor((parameters.strip_start_ms + 50 * column) / 1000)]);
    const beatMarks = Array(width).fill(' ');
    const referenceMarks = Array(width).fill(' ');
    for (const beat of beats) if (start <= beat.sample && beat.sample < start + length) beatMarks[Math.floor((beat.sample - start) / 10)] = beat.label;
    for (const annotation of annotations) if (start <= annotation.sample && annotation.sample < start + length) referenceMarks[Math.floor((annotation.sample - start) / 10)] = annotation.label;
    return [`RHYTHM start_ms=${parameters.strip_start_ms} end_ms=${parameters.strip_start_ms + parameters.strip_ms} columns=${width} rows=${parameters.strip_rows} max_uv=${Math.max(...highs)} min_uv=${Math.min(...lows)}`,
        ...waveform(highs, lows, parameters.strip_rows), axisRow(width, column => column % 20 === 0), labelRow('s', labels),
        ' beats |' + beatMarks.join('') + '|', '  refs |' + referenceMarks.join('') + '|'];
}

function main() {
    const { ecg, annotations, parameters } = readInput();
    const signals = filterSignal(ecg);
    const detector = new Detector(signals, parameters);
    detector.run();
    const beats = describeBeats(detector, signals, parameters);
    matchBeats(beats, annotations, Math.floor(parameters.match_ms / 5));
    const segments = makeSegments(ecg.length, parameters, beats, annotations, detector.peaks);
    const outputs = new Map([
        ['beats.csv', beatLines(beats)], ['peaks.csv', peakLines(detector.peaks)], ['matching.csv', matchingLines(beats, annotations)],
        ['signals_excerpt.csv', signalLines(signals, parameters)], ['performance.txt', performanceLines(detector, beats, annotations, segments)],
        ['hrv.txt', hrvLines(beats, segments, parameters)],
        ['charts.txt', [...intervalCharts(beats, parameters), ...templateCharts(ecg, beats, parameters)]],
        ['rhythm_strip.txt', rhythmLines(ecg, beats, annotations, parameters)]
    ]);
    for (const [name, lines] of outputs) writeLines(name, lines);
}

if (require.main === module) main();
