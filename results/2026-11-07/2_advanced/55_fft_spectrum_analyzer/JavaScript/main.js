'use strict';

const fs = require('node:fs');
const { readInput } = require('./signal_io');
const { PI, rot, conjugate, multiply, squared, magnitude, phase, asComplex, pow2, isPowerOfTwo,
  radix2, dft, idft, convolution, chirpZ } = require('./fft');
const { names: windowNames, makeWindow } = require('./windows');
const { localMaximum, interpolate, median, amplitudeSpectrum, segments, welch } = require('./spectral');
const { fixed, writeLines, writeCsv, shadeLines } = require('./report');

const sum = values => values.reduce((total, value) => total + value, 0);
const squareSum = values => sum(values.map(value => value * value));
const indices = (first, last) => Array.from({ length: last - first + 1 }, (_, i) => first + i);
const yesNo = value => value ? 'yes' : 'no';

function maximumIndex(values, candidates) {
  let best = candidates[0];
  for (const k of candidates) if (values[k] > values[best]) best = k;
  return best;
}

function strongestPeaks(values, count, eligible = () => true) {
  return indices(1, values.length - 2).filter(k => localMaximum(values, k) && eligible(k))
    .sort((a, b) => values[b] - values[a] || a - b).slice(0, count);
}

function preprocess(signal, sampleRate) {
  const n = signal.length;
  const mean = sum(signal) / n;
  const center = (n - 1) / 2;
  let numerator = 0;
  let denominator = 0;
  for (let i = 0; i < n; i++) {
    numerator += (i - center) * (signal[i] - mean);
    denominator += (i - center) * (i - center);
  }
  const slope = numerator / denominator;
  const values = signal.map((value, i) => value - mean - slope * (i - center));
  const squares = squareSum(values);
  const rms = Math.sqrt(squares / n);
  const third = sum(values.map(value => value * value * value));
  const fourth = sum(values.map(value => value * value * value * value));
  return { values, squares, mean, slope: slope * sampleRate, rms, min: Math.min(...signal), max: Math.max(...signal),
    crest: Math.max(...values.map(Math.abs)) / rms, skewness: (third / n) / (rms * rms * rms),
    kurtosis: (fourth / n) / (rms * rms * rms * rms) };
}

function levelHistory(first, second, length) {
  const blocks = [];
  for (let start = 0; start + length <= first.length; start += length) {
    const x = first.slice(start, start + length);
    const y = second.slice(start, start + length);
    blocks.push({ rms1: Math.sqrt(squareSum(x) / length), rms2: Math.sqrt(squareSum(y) / length), peak1: Math.max(...x.map(Math.abs)) });
  }
  let loudest = 0;
  for (let g = 1; g < blocks.length; g++) if (blocks[g].rms1 > blocks[loudest].rms1) loudest = g;
  return { blocks, loudest };
}

function windowComparisons(signal, params, sampleRate) {
  const center = params.fundamental * params.mainLength / sampleRate;
  const candidates = indices(1, Math.floor(params.mainLength / 2) - 1).filter(k => Math.abs(k - center) <= params.search);
  return windowNames.map(name => {
    const window = makeWindow(name, params.mainLength, sampleRate);
    const spectrum = amplitudeSpectrum(signal, window);
    const bin = maximumIndex(spectrum.amplitude, candidates);
    return { name, window, spectrum, bin, binAmplitude: spectrum.amplitude[bin],
      refinedAmplitude: interpolate(spectrum.amplitude, bin).value,
      floorDb: 20 * Math.log10(median(spectrum.amplitude.slice(1, -1))) };
  });
}

function harmonicAnalysis(amplitude, params, sampleRate) {
  const candidates = indices(1, amplitude.length - 2);
  const harmonics = [];
  for (let h = 1; h <= 10; h++) {
    const center = h * params.fundamental * params.mainLength / sampleRate;
    const bin = maximumIndex(amplitude, candidates.filter(k => Math.abs(k - center) <= params.search));
    const result = interpolate(amplitude, bin);
    harmonics.push({ h, bin, target: h * params.fundamental, refined: result.position * sampleRate / params.mainLength, amplitude: result.value });
  }
  const fundamental = harmonics[0].amplitude;
  for (const harmonic of harmonics) harmonic.levelDb = 20 * Math.log10(harmonic.amplitude / fundamental);
  const thd = Math.sqrt(sum(harmonics.slice(1).map(harmonic => harmonic.amplitude * harmonic.amplitude))) / fundamental;
  return { harmonics, thdPercent: 100 * thd, thdDb: 20 * Math.log10(thd) };
}

function powerAnalysis(spectrum, harmonics, params, sampleRate) {
  const amplitude = spectrum.amplitude;
  const bins = indices(1, amplitude.length - 2);
  const powers = amplitude.map(value => value * value / 2);
  const total = sum(bins.map(k => powers[k]));
  const enbw = spectrum.window.enbwBins;
  const totalPower = total / enbw;
  const fundamental = sum(bins.filter(k => Math.abs(k - harmonics[0].bin) <= params.search).map(k => powers[k])) / enbw;
  const thdn = Math.sqrt((totalPower - fundamental) / fundamental);
  const frequency = k => k * sampleRate / params.mainLength;
  const centroid = sum(bins.map(k => frequency(k) * powers[k])) / total;
  const spread = Math.sqrt(sum(bins.map(k => (frequency(k) - centroid) * (frequency(k) - centroid) * powers[k])) / total);
  let running = 0;
  let rolloff = 0;
  for (const k of bins) {
    running += powers[k];
    if (running >= 0.85 * total) { rolloff = frequency(k); break; }
  }
  const flatnessDb = 10 * Math.log10(Math.exp(sum(bins.map(k => Math.log(powers[k]))) / bins.length) / (total / bins.length));
  const bands = [];
  for (let i = 0; i + 1 < params.bands.length; i++) {
    const lower = params.bands[i];
    const upper = params.bands[i + 1];
    const selected = bins.filter(k => lower * params.mainLength <= k * sampleRate && k * sampleRate < upper * params.mainLength);
    const power = sum(selected.map(k => powers[k])) / enbw;
    bands.push({ lower, upper, power, percent: 100 * power / totalPower });
  }
  const thirdOctave = [];
  for (let b = params.thirdOctave[0]; b <= params.thirdOctave[1]; b++) {
    const center = 1000 * 2 ** (b / 3);
    const lower = 1000 * 2 ** ((2 * b - 1) / 6);
    const upper = 1000 * 2 ** ((2 * b + 1) / 6);
    const selected = bins.filter(k => lower <= frequency(k) && frequency(k) < upper);
    const power = sum(selected.map(k => powers[k])) / enbw;
    thirdOctave.push({ band: b, center, lower, upper, bins: selected.length, levelDb: 10 * Math.log10(power) });
  }
  return { totalPower, centroid, spread, rolloff, flatnessDb, bands, thirdOctave,
    thdnPercent: 100 * thdn, thdnDb: 20 * Math.log10(thdn) };
}

function peakAnalysis(spectrum, welchResult, params, sampleRate) {
  const amplitude = spectrum.amplitude;
  const last = amplitude.length - 1;
  const maximum = Math.max(...amplitude);
  const floor = median(amplitude.slice(1, -1));
  const bins = strongestPeaks(amplitude, params.peakCount, k => 20 * Math.log10(amplitude[k] / maximum) >= params.threshold);
  const peaks = bins.map((bin, i) => {
    const result = interpolate(amplitude, bin);
    const halfPower = amplitude[bin] / Math.sqrt(2);
    let right = last;
    let left = 0;
    for (let j = bin + 1; j <= last; j++) {
      if (amplitude[j] <= halfPower) {
        right = j - 1 + (amplitude[j - 1] - halfPower) / (amplitude[j - 1] - amplitude[j]);
        break;
      }
    }
    for (let j = bin - 1; j >= 0; j--) {
      if (amplitude[j] <= halfPower) {
        left = j + 1 - (amplitude[j + 1] - halfPower) / (amplitude[j + 1] - amplitude[j]);
        break;
      }
    }
    const coherenceBin = Math.floor((2 * bin * params.welchLength + params.mainLength) / (2 * params.mainLength));
    return { rank: i + 1, bin, position: result.position, frequency: bin * sampleRate / params.mainLength,
      refined: result.position * sampleRate / params.mainLength, amplitude: result.value,
      levelDb: 20 * Math.log10(amplitude[bin] / maximum), phase: phase(spectrum.transformed[bin]) * 180 / PI,
      bandwidth: (right - left) * sampleRate / params.mainLength, snrDb: 20 * Math.log10(amplitude[bin] / floor),
      coherence: welchResult.coherence[coherenceBin] };
  });
  for (const peak of peaks) {
    peak.label = 'other';
    for (let h = 1; h <= 10; h++) {
      if (Math.abs(peak.position - h * params.fundamental * params.mainLength / sampleRate) <= params.search) {
        peak.label = 'h' + h;
        break;
      }
    }
    if (peak.label !== 'other') continue;
    const [notchFrequency, notchWidth] = params.notch;
    const multiple = Math.floor(peak.refined / notchFrequency + 1 / 2);
    if (multiple >= 1 && Math.abs(peak.refined - multiple * notchFrequency) <= notchWidth) {
      peak.label = 'mains';
      continue;
    }
    for (const parent of peaks) {
      if (parent === peak || amplitude[parent.bin] <= amplitude[peak.bin]) continue;
      if (peaks.some(other => other !== peak && other !== parent && amplitude[parent.bin] > amplitude[other.bin]
        && Math.abs(peak.position + other.position - 2 * parent.position) <= 1)) {
        peak.label = 'sideband' + parent.rank;
        break;
      }
    }
  }
  return { peaks, maximum, floor };
}

function packingInspector() {
  const result = { error: 0, transforms: 0 };
  result.inspect = segment => {
    const reference = radix2(asComplex(segment.windowed));
    for (let k = 0; k < segment.transformed.length; k++) {
      const actual = segment.transformed[k];
      const error = magnitude([actual[0] - reference[k][0], actual[1] - reference[k][1]]);
      result.error = Math.max(result.error, error);
    }
    result.transforms++;
  };
  return result;
}

function welchAnalysis(first, second, firstStatistics, params, sampleRate, inspect) {
  const window = makeWindow(params.welchWindow, params.welchLength, sampleRate);
  const result = welch(first, second, window, sampleRate, inspect);
  const integratedPower = sum(result.psd) * sampleRate / params.welchLength;
  const variance = firstStatistics.rms * firstStatistics.rms;
  const peaks = strongestPeaks(result.psd, 5).map((bin, index) => ({ rank: index + 1,
    frequency: bin * sampleRate / params.welchLength, psdDb: 10 * Math.log10(result.psd[bin]),
    coherence: result.coherence[bin], gain: magnitude(result.transfer[bin]), phase: phase(result.transfer[bin]) * 180 / PI }));
  return { ...result, integratedPower, variance, ratio: integratedPower / variance, peaks };
}

function spectrogramAnalysis(signal, params, sampleRate, inspect) {
  const window = makeWindow(params.frameWindow, params.frameLength, sampleRate);
  const frames = [];
  let maximum = 0;
  for (const segment of segments(signal, window, params.hop)) {
    inspect(segment);
    const values = segment.transformed.map(magnitude);
    maximum = Math.max(maximum, ...values);
    frames.push(values);
  }
  const levels = frames.map(frame => frame.map(value => {
    const decibels = 20 * Math.log10(value / maximum);
    return Math.max(0, 9 - Math.floor(-decibels / params.shadeWidth));
  }));
  const candidates = indices(1, params.frameLength / 2 - 1);
  const track = frames.map(frame => {
    const bin = maximumIndex(frame, candidates);
    return { frequency: bin * sampleRate / params.frameLength, levelDb: 20 * Math.log10(frame[bin] / maximum) };
  });
  const flux = [0];
  for (let t = 1; t < frames.length; t++) flux.push(sum(frames[t].map((value, k) => Math.max(0, value - frames[t - 1][k]))));
  const threshold = params.onsetFactor * median(flux.slice(1));
  const onsets = indices(1, frames.length - 1).filter(t => flux[t] > threshold && flux[t] > flux[t - 1]
    && (t === frames.length - 1 || flux[t] > flux[t + 1]));
  const kurtosis = indices(0, params.frameLength / 2).map(k => {
    let second = 0;
    let fourth = 0;
    for (const frame of frames) {
      second += frame[k] * frame[k];
      fourth += frame[k] * frame[k] * frame[k] * frame[k];
    }
    return frames.length * fourth / (second * second) - 2;
  });
  const kurtosisBin = maximumIndex(kurtosis, candidates);
  return { frames: frames.length, maximum, levels, track, flux, threshold, onsets, kurtosisBin, kurtosis: kurtosis[kurtosisBin] };
}

function filterAnalysis(first, second, params, sampleRate) {
  const n = first.length;
  const transformed = dft(asComplex(first));
  let binsKept = 0;
  let binsRemoved = 0;
  const bandSpectrum = transformed.map((value, k) => {
    const frequencyNumerator = Math.min(k, n - k) * sampleRate;
    if (params.bandpass[0] * n <= frequencyNumerator && frequencyNumerator <= params.bandpass[1] * n) {
      binsKept++;
      return value;
    }
    return [0, 0];
  });
  const [notchFrequency, notchWidth] = params.notch;
  const notchSpectrum = transformed.map((value, k) => {
    const frequencyNumerator = Math.min(k, n - k) * sampleRate;
    const multiple = Math.floor((2 * frequencyNumerator + notchFrequency * n) / (2 * notchFrequency * n));
    if (multiple >= 1 && Math.abs(frequencyNumerator - multiple * notchFrequency * n) <= notchWidth * n) {
      binsRemoved++;
      return [0, 0];
    }
    return value;
  });
  const bandpassed = idft(bandSpectrum).map(value => value[0]);
  const notched = idft(notchSpectrum).map(value => value[0]);
  const envelopeSpectrum = transformed.map((value, k) => k >= 1 && k <= Math.floor((n - 1) / 2)
    && params.envelope[0] * n <= k * sampleRate && k * sampleRate <= params.envelope[1] * n
    ? [2 * value[0], 2 * value[1]] : [0, 0]);
  const analytic = idft(envelopeSpectrum);
  const envelope = analytic.map(magnitude);
  const envelopeMean = sum(envelope) / n;
  const modulation = dft(asComplex(envelope.map(value => value - envelopeMean))).map(value => 2 * magnitude(value) / n);
  const upper = Math.floor((params.envelope[1] - params.envelope[0]) * n / (2 * sampleRate));
  const envelopeBin = maximumIndex(modulation, indices(1, upper));
  const interpolated = interpolate(modulation, envelopeBin);
  const phases = analytic.map(phase);
  const instantaneous = [];
  for (let i = 1; i < n; i++) {
    let difference = phases[i] - phases[i - 1];
    if (difference <= -PI) difference += 2 * PI;
    if (difference > PI) difference -= 2 * PI;
    instantaneous.push(difference * sampleRate / (2 * PI));
  }
  const instantaneousMean = sum(instantaneous) / (n - 1);
  const instantaneousStd = Math.sqrt(sum(instantaneous.map(value => (value - instantaneousMean) * (value - instantaneousMean))) / (n - 1));
  const smoothed = convolution(second, params.fir);
  const gain = [0, 0];
  for (let j = 0; j < params.fir.length; j++) {
    const rotation = rot(2 * PI * params.fundamental * j / sampleRate);
    gain[0] += params.fir[j] * rotation[0];
    gain[1] += params.fir[j] * rotation[1];
  }
  const bandSquares = squareSum(bandpassed);
  return { bandpassed, notched, smoothed, envelope, binsKept, binsRemoved,
    bandRms: Math.sqrt(bandSquares / n), energyRatio: bandSquares / squareSum(first), notchRms: Math.sqrt(squareSum(notched) / n),
    firDcGain: sum(params.fir), firGainDb: 20 * Math.log10(magnitude(gain)), firRms: Math.sqrt(squareSum(smoothed.slice(0, n)) / n),
    envelopeMean, envelopeBin, envelopeFrequency: interpolated.position * sampleRate / n,
    envelopeAmplitude: interpolated.value, depth: interpolated.value / envelopeMean, instantaneousMean, instantaneousStd };
}

function pitchAnalysis(amplitude, bandpassed, params, sampleRate) {
  const [low, high] = params.pitch;
  const lagLow = Math.floor((sampleRate + high - 1) / high);
  const lagHigh = Math.floor(sampleRate / low);
  const scores = Array(amplitude.length).fill(0);
  const candidates = [];
  for (let k = 1; 5 * k <= amplitude.length - 1; k++) {
    if (low * params.mainLength > k * sampleRate || k * sampleRate > high * params.mainLength) continue;
    for (let r = 1; r <= 5; r++) scores[k] += Math.log(amplitude[r * k]);
    candidates.push(k);
  }
  const hpsBin = maximumIndex(scores, candidates);
  const transformed = radix2(asComplex(bandpassed, pow2(2 * bandpassed.length - 1)));
  const correlation = radix2(transformed.map(value => [squared(value), 0]), true).map(value => value[0]);
  const lag = maximumIndex(correlation, indices(lagLow, lagHigh));
  const refined = interpolate(correlation, lag, false);
  let crossings = 0;
  for (let i = 1; i < bandpassed.length; i++) if (bandpassed[i - 1] < 0 && bandpassed[i] >= 0) crossings++;
  return { lagLow, lagHigh, hpsBin, hpsFrequency: hpsBin * sampleRate / params.mainLength,
    lag, period: refined.position, frequency: sampleRate / refined.position, strength: refined.value / correlation[0],
    crossings, crossingFrequency: crossings * sampleRate / bandpassed.length };
}

function zoomAnalysis(spectrum, params, sampleRate) {
  const [low, high, count] = params.zoom;
  const step = (high - low) / (count - 1);
  const transformed = chirpZ(spectrum.windowed, low, step, count, sampleRate);
  const amplitude = transformed.map(value => 2 * magnitude(value) / spectrum.window.s1);
  const peaks = strongestPeaks(amplitude, 3).map((bin, i) => {
    const result = interpolate(amplitude, bin);
    return { rank: i + 1, frequency: low + result.position * step, amplitude: result.value };
  });
  return { step, peaks };
}

function correlationPeak(values, maximumLag, sampleRate) {
  const at = lag => values[lag < 0 ? lag + values.length : lag];
  let lag = -maximumLag;
  for (let candidate = -maximumLag + 1; candidate <= maximumLag; candidate++) {
    if (at(candidate) > at(lag) || at(candidate) === at(lag)
      && (Math.abs(candidate) < Math.abs(lag) || Math.abs(candidate) === Math.abs(lag) && candidate < lag)) lag = candidate;
  }
  const refined = interpolate([at(lag - 1), at(lag), at(lag + 1)], 1, false);
  const delta = refined.position - 1;
  const refinedLag = lag + delta;
  return { lag, refinedLag, delayMs: 1000 * refinedLag / sampleRate, value: at(lag) };
}

function crossCorrelation(first, second, params, sampleRate) {
  const length = pow2(2 * first.length - 1);
  const x = radix2(asComplex(first, length));
  const y = radix2(asComplex(second, length));
  const cross = x.map((value, k) => multiply(conjugate(value), y[k]));
  const normalized = cross.map(value => {
    const length = magnitude(value);
    return [value[0] / length, value[1] / length];
  });
  const raw = radix2(cross, true).map(value => value[0]);
  const phat = radix2(normalized, true).map(value => value[0]);
  const ordinary = correlationPeak(raw, params.maxLag, sampleRate);
  ordinary.coefficient = ordinary.value / Math.sqrt(squareSum(first) * squareSum(second));
  return { ordinary, phat: correlationPeak(phat, params.maxLag, sampleRate) };
}

function checkCalculations(spectrum, peaks, second, smoothed, params, packing) {
  const inverse = idft(spectrum.transformed);
  let inverseError = 0;
  for (let n = 0; n < inverse.length; n++) {
    inverseError = Math.max(inverseError, magnitude([inverse[n][0] - spectrum.windowed[n], inverse[n][1]]));
  }
  const timePower = squareSum(spectrum.windowed);
  const parsevalError = Math.abs(timePower - sum(spectrum.transformed.map(squared)) / params.mainLength) / timePower;
  let firError = 0;
  for (let n = 0; n < smoothed.length; n++) {
    let direct = 0;
    for (let j = Math.max(0, n - params.fir.length + 1); j <= Math.min(second.length - 1, n); j++) direct += second[j] * params.fir[n - j];
    firError = Math.max(firError, Math.abs(direct - smoothed[n]));
  }
  let spotError = 0;
  for (const peak of peaks) {
    const direct = [0, 0];
    for (let n = 0; n < params.mainLength; n++) {
      const rotation = rot(2 * PI * ((peak.bin * n) % params.mainLength) / params.mainLength);
      direct[0] += spectrum.windowed[n] * rotation[0];
      direct[1] += spectrum.windowed[n] * rotation[1];
    }
    const transformed = spectrum.transformed[peak.bin];
    spotError = Math.max(spotError, magnitude([direct[0] - transformed[0], direct[1] - transformed[1]]));
  }
  const status = error => error <= 1e-6 ? 'ok' : 'failed';
  return { inverse: status(inverseError), parseval: status(parsevalError), packing: status(packing.error),
    transforms: packing.transforms, fir: status(firError), spot: status(spotError) };
}

function diagnose(harmonics, peaks, filters, spectrogram) {
  const ratio = harmonics[1].amplitude / harmonics[0].amplitude;
  const harmonicCount = harmonics.slice(2).filter(harmonic => harmonic.levelDb >= -30).length;
  const mains = peaks.find(peak => peak.label === 'mains');
  const misalignment = ratio >= 0.5;
  const looseness = harmonicCount >= 3;
  const bearing = filters.depth >= 0.2;
  const electrical = mains !== undefined && mains.levelDb >= -20;
  const transient = spectrogram.onsets.length > 0;
  const findings = [misalignment, looseness, bearing, electrical, transient].filter(Boolean).length;
  return { ratio, harmonicCount, mains, misalignment, looseness, bearing, electrical, transient, findings,
    status: findings === 0 ? 'normal' : findings === 1 ? 'warning' : 'alarm' };
}

function peaksLines(result, params, sampleRate) {
  const lines = [
    `length=${params.mainLength} window=${params.mainWindow} resolution=${fixed(sampleRate / params.mainLength)} threshold_db=${fixed(params.threshold)}`,
    `max_amplitude=${fixed(result.maximum)} noise_floor=${fixed(result.floor)} noise_floor_db=${fixed(20 * Math.log10(result.floor))}`,
    'peaks=' + result.peaks.length
  ];
  for (const peak of result.peaks) {
    lines.push(`${peak.rank} bin=${peak.bin} frequency=${fixed(peak.frequency)} refined=${fixed(peak.refined)} amplitude=${fixed(peak.amplitude)} level_db=${fixed(peak.levelDb)} phase=${fixed(peak.phase)} bandwidth=${fixed(peak.bandwidth)} snr_db=${fixed(peak.snrDb)} coherence=${fixed(peak.coherence)} label=${peak.label}`);
  }
  return lines;
}

function spectrogramLines(result, params, sampleRate) {
  const lines = [
    `frames=${result.frames} bins=${params.frameLength / 2 + 1} frame_length=${params.frameLength} hop=${params.hop} window=${params.frameWindow} band_db=${params.shadeWidth} max_db=${fixed(20 * Math.log10(result.maximum))}`,
    ...shadeLines(result.levels, sampleRate, params.frameLength), 'track'
  ];
  result.track.forEach((frame, t) => {
    lines.push(`frame=${t} time=${fixed(t * params.hop / sampleRate)} frequency=${fixed(frame.frequency)} level_db=${fixed(frame.levelDb)}`);
  });
  lines.push(`onsets=${result.onsets.length} threshold=${fixed(result.threshold)}`);
  for (const t of result.onsets) lines.push(`frame=${t} time=${fixed(t * params.hop / sampleRate)} flux=${fixed(result.flux[t])}`);
  lines.push(`kurtosis bin=${result.kurtosisBin} frequency=${fixed(result.kurtosisBin * sampleRate / params.frameLength)} value=${fixed(result.kurtosis)}`);
  return lines;
}

function analysisReport(analysis) {
  const { input, channels, levels, windows, harmonic, power, welchResult, filters, pitch, zoom, correlation, checks, diagnosis, spectrogram, peaks } = analysis;
  const { params, sampleRate, count } = input;
  const lines = ['[signal]', `sample_rate=${sampleRate} samples=${count} duration=${fixed(count / sampleRate)}`];
  channels.forEach((channel, i) => {
    lines.push(`channel=${i + 1} mean=${fixed(channel.mean)} slope=${fixed(channel.slope)} rms=${fixed(channel.rms)} min=${fixed(channel.min)} max=${fixed(channel.max)} crest=${fixed(channel.crest)} skewness=${fixed(channel.skewness)} kurtosis=${fixed(channel.kurtosis)}`);
  });
  lines.push('[levels]', `block_length=${params.blockLength} blocks=${levels.blocks.length} loudest=${levels.loudest}`);
  levels.blocks.forEach((block, g) => {
    lines.push(`block=${g} time=${fixed(g * params.blockLength / sampleRate)} rms1=${fixed(block.rms1)} rms2=${fixed(block.rms2)} peak1=${fixed(block.peak1)}`);
  });
  lines.push('[windows]');
  for (const comparison of windows) {
    const window = comparison.window;
    lines.push(`name=${comparison.name} coherent_gain=${fixed(window.coherentGain)} enbw_bins=${fixed(window.enbwBins)} enbw_hz=${fixed(window.enbwHz)} scalloping_db=${fixed(window.scallopingDb)} fundamental_bin=${comparison.bin} bin_amplitude=${fixed(comparison.binAmplitude)} refined_amplitude=${fixed(comparison.refinedAmplitude)} floor_db=${fixed(comparison.floorDb)}`);
  }
  const radix = isPowerOfTwo(params.mainLength);
  lines.push('[main]',
    `length=${params.mainLength} window=${params.mainWindow} method=${radix ? 'radix2' : 'bluestein'} transform_size=${radix ? params.mainLength : pow2(2 * params.mainLength - 1)} resolution=${fixed(sampleRate / params.mainLength)}`,
    `total_power=${fixed(power.totalPower)} centroid=${fixed(power.centroid)} spread=${fixed(power.spread)} rolloff=${fixed(power.rolloff)} flatness_db=${fixed(power.flatnessDb)}`, '[bands]');
  for (const band of power.bands) lines.push(`range=${band.lower}-${band.upper} power=${fixed(band.power)} percent=${fixed(band.percent)}`);
  lines.push('[third_octave]');
  for (const band of power.thirdOctave) {
    lines.push(`band=${band.band} center=${fixed(band.center)} lower=${fixed(band.lower)} upper=${fixed(band.upper)} bins=${band.bins} level_db=${fixed(band.levelDb)}`);
  }
  lines.push('[harmonics]', `fundamental=${fixed(params.fundamental)} search=${params.search}`);
  for (const item of harmonic.harmonics) {
    lines.push(`h=${item.h} target=${fixed(item.target)} bin=${item.bin} refined=${fixed(item.refined)} amplitude=${fixed(item.amplitude)} level_db=${fixed(item.levelDb)}`);
  }
  lines.push(`thd_percent=${fixed(harmonic.thdPercent)} thd_db=${fixed(harmonic.thdDb)}`,
    `thdn_percent=${fixed(power.thdnPercent)} thdn_db=${fixed(power.thdnDb)}`, '[pitch]',
    `range=${params.pitch[0]}-${params.pitch[1]} lags=${pitch.lagLow}-${pitch.lagHigh}`,
    `hps bin=${pitch.hpsBin} order=5 frequency=${fixed(pitch.hpsFrequency)}`,
    `autocorrelation lag=${pitch.lag} period=${fixed(pitch.period)} frequency=${fixed(pitch.frequency)} strength=${fixed(pitch.strength)}`,
    `zero_crossing count=${pitch.crossings} frequency=${fixed(pitch.crossingFrequency)}`, '[zoom]',
    `band=${params.zoom[0]}-${params.zoom[1]} points=${params.zoom[2]} step=${fixed(zoom.step)}`);
  for (const peak of zoom.peaks) lines.push(`peak=${peak.rank} frequency=${fixed(peak.frequency)} amplitude=${fixed(peak.amplitude)}`);
  lines.push('[welch]',
    `segment_length=${params.welchLength} segments=${welchResult.segments} window=${params.welchWindow} resolution=${fixed(sampleRate / params.welchLength)}`,
    `integrated_power=${fixed(welchResult.integratedPower)} variance=${fixed(welchResult.variance)} ratio=${fixed(welchResult.ratio)}`);
  for (const peak of welchResult.peaks) {
    lines.push(`peak=${peak.rank} frequency=${fixed(peak.frequency)} psd_db=${fixed(peak.psdDb)} coherence=${fixed(peak.coherence)} gain=${fixed(peak.gain)} phase=${fixed(peak.phase)}`);
  }
  lines.push('[filter]',
    `bandpass=${params.bandpass[0]}-${params.bandpass[1]} bins_kept=${filters.binsKept} rms=${fixed(filters.bandRms)} energy_ratio=${fixed(filters.energyRatio)}`,
    `notch=${params.notch[0]} width=${params.notch[1]} bins_removed=${filters.binsRemoved} rms=${fixed(filters.notchRms)}`,
    `fir_taps=${params.fir.length} dc_gain=${fixed(filters.firDcGain)} gain_at_fundamental_db=${fixed(filters.firGainDb)} rms=${fixed(filters.firRms)}`, '[envelope]',
    `band=${params.envelope[0]}-${params.envelope[1]} mean=${fixed(filters.envelopeMean)} bin=${filters.envelopeBin} frequency=${fixed(filters.envelopeFrequency)} amplitude=${fixed(filters.envelopeAmplitude)} depth=${fixed(filters.depth)}`,
    `instantaneous_frequency mean=${fixed(filters.instantaneousMean)} std=${fixed(filters.instantaneousStd)}`, '[correlation]');
  const ordinary = correlation.ordinary;
  const phat = correlation.phat;
  lines.push(`max_lag=${params.maxLag} lag=${ordinary.lag} refined_lag=${fixed(ordinary.refinedLag)} delay_ms=${fixed(ordinary.delayMs)} coefficient=${fixed(ordinary.coefficient)}`,
    `phat_lag=${phat.lag} refined_lag=${fixed(phat.refinedLag)} delay_ms=${fixed(phat.delayMs)}`, '[checks]',
    'inverse_roundtrip=' + checks.inverse, 'parseval=' + checks.parseval,
    `real_packing=${checks.packing} transforms=${checks.transforms}`, 'fir_fft_vs_direct=' + checks.fir,
    `dft_spot_check=${checks.spot} bins=${peaks.peaks.length}`, '[diagnosis]',
    `misalignment=${yesNo(diagnosis.misalignment)} ratio=${fixed(diagnosis.ratio)}`,
    `looseness=${yesNo(diagnosis.looseness)} harmonics=${diagnosis.harmonicCount}`,
    `bearing=${yesNo(diagnosis.bearing)} depth=${fixed(filters.depth)}`,
    `electrical=${yesNo(diagnosis.electrical)} level_db=${diagnosis.mains === undefined ? 'none' : fixed(diagnosis.mains.levelDb)}`,
    `transient=${yesNo(diagnosis.transient)} onsets=${spectrogram.onsets.length}`,
    `status=${diagnosis.status} findings=${diagnosis.findings}`);
  return lines;
}

function main() {
  const input = readInput();
  const { sampleRate, params, count } = input;
  const channels = input.channels.map(signal => preprocess(signal, sampleRate));
  const [first, second] = channels.map(channel => channel.values);
  const levels = levelHistory(first, second, params.blockLength);
  const windows = windowComparisons(first, params, sampleRate);
  const spectrum = windows.find(comparison => comparison.name === params.mainWindow).spectrum;
  const harmonic = harmonicAnalysis(spectrum.amplitude, params, sampleRate);
  const power = powerAnalysis(spectrum, harmonic.harmonics, params, sampleRate);
  const packing = packingInspector();
  const welchResult = welchAnalysis(first, second, channels[0], params, sampleRate, packing.inspect);
  const peaks = peakAnalysis(spectrum, welchResult, params, sampleRate);
  const spectrogram = spectrogramAnalysis(first, params, sampleRate, packing.inspect);
  const filters = filterAnalysis(first, second, params, sampleRate);
  const pitch = pitchAnalysis(spectrum.amplitude, filters.bandpassed, params, sampleRate);
  const zoom = zoomAnalysis(spectrum, params, sampleRate);
  const correlation = crossCorrelation(first, second, params, sampleRate);
  const checks = checkCalculations(spectrum, peaks.peaks, second, filters.smoothed, params, packing);
  const diagnosis = diagnose(harmonic.harmonics, peaks.peaks, filters, spectrogram);
  const report = analysisReport({ input, channels, levels, windows, spectrum, harmonic, power, peaks,
    welchResult, spectrogram, filters, pitch, zoom, correlation, checks, diagnosis });
  fs.mkdirSync('output', { recursive: true });
  writeCsv('spectrum.csv', [['frequency', 'amplitude'], ...spectrum.amplitude.map((value, k) =>
    [fixed(k * sampleRate / params.mainLength), fixed(value)])]);
  writeLines('peaks.txt', peaksLines(peaks, params, sampleRate));
  writeCsv('welch_psd.csv', [['frequency', 'psd_db'], ...welchResult.psd.map((value, k) =>
    [fixed(k * sampleRate / params.welchLength), fixed(10 * Math.log10(value))])]);
  writeLines('spectrogram.txt', spectrogramLines(spectrogram, params, sampleRate));
  writeCsv('filtered.csv', [['index', 'bandpass', 'notched', 'smoothed', 'envelope'], ...indices(0, count - 1).map(i =>
    [i, fixed(filters.bandpassed[i]), fixed(filters.notched[i]), fixed(filters.smoothed[i]), fixed(filters.envelope[i])])]);
  writeLines('report.txt', report);
}

main();
