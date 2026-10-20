import { readInput } from './signal_io.ts';
import { PI, complex, add, multiply, conjugate, scale, subtract, magnitude, squaredMagnitude, argument,
  rot, pow2, isPowerOfTwo, radix2, transform, convolution, chirpZ, type Complex } from './fft.ts';
import { windowNames, window, figures } from './windows.ts';
import { spectrum, frames, welch, interpolate, median, localMaximum, type Frame } from './spectral.ts';
import { real, shadeRows, writeLines, writeCsv } from './report.ts';

const sum = (values: readonly number[]): number => values.reduce((a, b) => a + b, 0);
const range = (first: number, last: number): number[] => Array.from({ length: Math.max(0, last - first + 1) }, (_, i) => first + i);
const squaredSum = (values: readonly number[]): number => sum(values.map(v => v * v));
const rms = (values: readonly number[]): number => Math.sqrt(squaredSum(values) / values.length);
const db20 = (value: number): number => 20 * Math.log10(value);
const db10 = (value: number): number => 10 * Math.log10(value);
function maximum(values: number[], candidates = range(0, values.length - 1)): number {
  let best = candidates[0]; for (const index of candidates) if (values[index] > values[best]) best = index; return best;
}
function rankedMaxima(values: number[], count: number): number[] {
  return range(1, values.length - 2).filter(k => localMaximum(values, k)).sort((a, b) => values[b] - values[a] || a - b).slice(0, count);
}
function detrend(signal: number[], sampleRate: number) {
  const count = signal.length, mean = sum(signal) / count, center = (count - 1) / 2;
  const slope = sum(signal.map((value, i) => (i - center) * (value - mean))) / sum(signal.map((_, i) => (i - center) ** 2));
  const values = signal.map((value, i) => value - mean - slope * (i - center)), level = rms(values);
  return { values, mean, slope: slope * sampleRate, rms: level, minimum: Math.min(...signal), maximum: Math.max(...signal),
    crest: Math.max(...values.map(Math.abs)) / level, skewness: (sum(values.map(v => v ** 3)) / count) / level ** 3,
    kurtosis: (sum(values.map(v => v ** 4)) / count) / level ** 4 };
}
function bandwidth(amplitudes: number[], k: number, sampleRate: number, length: number): number {
  const threshold = amplitudes[k] / Math.sqrt(2); let left = 0, right = amplitudes.length - 1;
  for (let j = k + 1; j < amplitudes.length; j++) if (amplitudes[j] <= threshold) {
    right = j - 1 + (amplitudes[j - 1] - threshold) / (amplitudes[j - 1] - amplitudes[j]); break;
  }
  for (let j = k - 1; j >= 0; j--) if (amplitudes[j] <= threshold) {
    left = j + 1 - (amplitudes[j + 1] - threshold) / (amplitudes[j + 1] - amplitudes[j]); break;
  }
  return (right - left) * sampleRate / length;
}
function correlationPeak(values: Complex[], limit: number, sampleRate: number) {
  const size = values.length, at = (lag: number): number => values[lag < 0 ? lag + size : lag].re;
  let lag = -limit;
  for (let candidate = -limit + 1; candidate <= limit; candidate++) {
    if (at(candidate) > at(lag) || (at(candidate) === at(lag)
      && (Math.abs(candidate) < Math.abs(lag) || (Math.abs(candidate) === Math.abs(lag) && candidate < lag)))) lag = candidate;
  }
  const interpolated = interpolate([at(lag - 1), at(lag), at(lag + 1)], 1, false), refined = lag + interpolated.position - 1;
  return { lag, refined, delay: 1000 * refined / sampleRate, value: at(lag) };
}
function main(): void {
  const data = readInput(), { settings: s, sampleRate: fs, count: n } = data, length = s.mainLength, lastBin = Math.floor(length / 2);
  const first = detrend(data.first, fs), second = detrend(data.second, fs), x = first.values, y = second.values;
  const mainWindow = window(s.mainWindow, length), windowFigures = figures(mainWindow, fs), main = spectrum(x, mainWindow);
  const amplitudes = main.amplitudes, bins = range(1, lastBin - 1), highest = Math.max(...amplitudes), floor = median(amplitudes.slice(1, -1));
  let packingError = 0, packingTransforms = 0;
  const observe = (frame: Frame): void => {
    const full = radix2(frame.weighted.map(value => complex(value))); packingTransforms++;
    frame.transformed.forEach((value, k) => { packingError = Math.max(packingError, magnitude(subtract(value, full[k]))); });
  };
  const welchResult = welch(x, y, window(s.welchWindow, s.welchLength), fs, observe);
  const peakBins = bins.filter(k => localMaximum(amplitudes, k) && db20(amplitudes[k] / highest) >= s.threshold)
    .sort((a, b) => amplitudes[b] - amplitudes[a] || a - b).slice(0, s.peakCount);
  const peaks = peakBins.map((k, index) => {
    const refined = interpolate(amplitudes, k), coherenceBin = Math.floor((2 * k * s.welchLength + length) / (2 * length));
    return { rank: index + 1, bin: k, position: refined.position, frequency: k * fs / length,
      refined: refined.position * fs / length, amplitude: refined.value, level: db20(amplitudes[k] / highest),
      phase: argument(main.transformed[k]) * 180 / PI, bandwidth: bandwidth(amplitudes, k, fs, length),
      snr: db20(amplitudes[k] / floor), coherence: welchResult.coherence[coherenceBin], label: 'other' };
  });
  for (const peak of peaks) {
    const harmonic = range(1, 10).find(h => Math.abs(peak.position - h * s.fundamental * length / fs) <= s.search);
    if (harmonic !== undefined) { peak.label = 'h' + harmonic; continue; }
    const mains = Math.floor(peak.refined / s.notch + 0.5);
    if (mains >= 1 && Math.abs(peak.refined - mains * s.notch) <= s.notchWidth) { peak.label = 'mains'; continue; }
    for (const parent of peaks) {
      if (parent === peak || amplitudes[parent.bin] <= amplitudes[peak.bin]) continue;
      if (peaks.some(other => other !== peak && other !== parent && amplitudes[parent.bin] > amplitudes[other.bin]
        && Math.abs(peak.position + other.position - 2 * parent.position) <= 1)) { peak.label = 'sideband' + parent.rank; break; }
    }
  }
  const harmonics = range(1, 10).map(h => {
    const target = h * s.fundamental * length / fs, k = maximum(amplitudes, bins.filter(k => Math.abs(k - target) <= s.search));
    const refined = interpolate(amplitudes, k); return { h, bin: k, frequency: refined.position * fs / length, amplitude: refined.value };
  });
  const fundamental = harmonics[0], thd = Math.sqrt(sum(harmonics.slice(1).map(h => h.amplitude * h.amplitude))) / fundamental.amplitude;
  const power = amplitudes.map(value => value * value / 2), rawPower = sum(bins.map(k => power[k])), totalPower = rawPower / windowFigures.enbwBins;
  const fundamentalPower = sum(bins.filter(k => Math.abs(k - fundamental.bin) <= s.search).map(k => power[k])) / windowFigures.enbwBins;
  const thdn = Math.sqrt((totalPower - fundamentalPower) / fundamentalPower), centroid = sum(bins.map(k => k * fs / length * power[k])) / rawPower;
  const spread = Math.sqrt(sum(bins.map(k => (k * fs / length - centroid) ** 2 * power[k])) / rawPower);
  let running = 0, rolloff = bins[bins.length - 1];
  for (const k of bins) { running += power[k]; if (running >= 0.85 * rawPower) { rolloff = k; break; } }
  const flatness = db10(Math.exp(sum(bins.map(k => Math.log(power[k]))) / (lastBin - 1)) / (rawPower / (lastBin - 1)));
  const bandPowers = s.bands.slice(0, -1).map((lower, i) => {
    const upper = s.bands[i + 1], bandPower = sum(bins.filter(k => lower * length <= k * fs && k * fs < upper * length).map(k => power[k])) / windowFigures.enbwBins;
    return { lower, upper, power: bandPower, percent: 100 * bandPower / totalPower };
  });
  const octaveBands = range(s.thirdLow, s.thirdHigh).map(band => {
    const center = 1000 * 2 ** (band / 3), lower = 1000 * 2 ** ((2 * band - 1) / 6), upper = 1000 * 2 ** ((2 * band + 1) / 6);
    const included = bins.filter(k => lower <= k * fs / length && k * fs / length < upper);
    return { band, center, lower, upper, bins: included.length, level: db10(sum(included.map(k => power[k])) / windowFigures.enbwBins) };
  });
  const windowComparisons = windowNames.map(name => {
    const w = window(name, length), stats = figures(w, fs), values = spectrum(x, w).amplitudes;
    const k = maximum(values, bins.filter(k => Math.abs(k - s.fundamental * length / fs) <= s.search));
    return { name, ...stats, bin: k, amplitude: values[k], refined: interpolate(values, k).value, floor: db20(median(values.slice(1, -1))) };
  });
  const spectrogram: number[][] = [];
  for (const frame of frames(x, window(s.spectrogramWindow, s.frameLength), s.hop)) { observe(frame); spectrogram.push(frame.transformed.map(magnitude)); }
  let spectrogramMaximum = 0;
  for (const frame of spectrogram) for (const value of frame) spectrogramMaximum = Math.max(spectrogramMaximum, value);
  const tracks = spectrogram.map(frame => maximum(frame, range(1, s.frameLength / 2 - 1)));
  const flux = spectrogram.map((frame, t) => t === 0 ? 0 : sum(frame.map((value, k) => Math.max(0, value - spectrogram[t - 1][k]))));
  const onsetThreshold = s.onsetFactor * median(flux.slice(1));
  const onsets = range(1, spectrogram.length - 1).filter(t => flux[t] > onsetThreshold && flux[t] > flux[t - 1]
    && (t === spectrogram.length - 1 || flux[t] > flux[t + 1]));
  const kurtosis = range(0, s.frameLength / 2).map(k => {
    const squares = sum(spectrogram.map(frame => frame[k] * frame[k]));
    return spectrogram.length * sum(spectrogram.map(frame => frame[k] ** 4)) / (squares * squares) - 2;
  });
  const kurtosisBin = maximum(kurtosis, range(1, s.frameLength / 2 - 1));
  const fullSpectrum = transform(x.map(value => complex(value)));
  let binsKept = 0, binsRemoved = 0;
  const passedSpectrum = fullSpectrum.map((value, k) => {
    const frequency = Math.min(k, n - k) * fs;
    if (s.bandLow * n <= frequency && frequency <= s.bandHigh * n) { binsKept++; return value; }
    return complex();
  });
  const notchedSpectrum = fullSpectrum.map((value, k) => {
    const frequency = Math.min(k, n - k) * fs, harmonic = Math.floor((2 * frequency + s.notch * n) / (2 * s.notch * n));
    if (harmonic >= 1 && Math.abs(frequency - harmonic * s.notch * n) <= s.notchWidth * n) { binsRemoved++; return complex(); }
    return value;
  });
  const bandpassed = transform(passedSpectrum, true).map(value => value.re), notched = transform(notchedSpectrum, true).map(value => value.re);
  const analytic = transform(fullSpectrum.map((value, k) => k >= 1 && k <= Math.floor((n - 1) / 2)
    && s.envelopeLow * n <= k * fs && k * fs <= s.envelopeHigh * n ? scale(value, 2) : complex()), true);
  const envelope = analytic.map(magnitude), envelopeMean = sum(envelope) / n;
  const envelopeSpectrum = transform(envelope.map(value => complex(value - envelopeMean))).map(value => 2 * magnitude(value) / n);
  const envelopeBin = maximum(envelopeSpectrum, range(1, Math.floor((s.envelopeHigh - s.envelopeLow) * n / (2 * fs))));
  const envelopePeak = interpolate(envelopeSpectrum, envelopeBin), envelopeDepth = envelopePeak.value / envelopeMean;
  const phases = analytic.map(argument), instantaneous = phases.slice(1).map((phase, i) => {
    let difference = phase - phases[i]; if (difference <= -PI) difference += 2 * PI; if (difference > PI) difference -= 2 * PI;
    return difference * fs / (2 * PI);
  });
  const instantaneousMean = sum(instantaneous) / (n - 1), instantaneousStd = Math.sqrt(sum(instantaneous.map(value => (value - instantaneousMean) ** 2)) / (n - 1));
  const smoothed = convolution(y, s.fir), dcGain = sum(s.fir);
  let filterGain = complex(); s.fir.forEach((value, j) => { filterGain = add(filterGain, scale(rot(2 * PI * s.fundamental * j / fs), value)); });
  const minimumLag = Math.floor((fs + s.pitchHigh - 1) / s.pitchHigh), maximumLag = Math.floor(fs / s.pitchLow);
  const hps = amplitudes.map(() => -Infinity), pitchCandidates = bins.filter(k => s.pitchLow * length <= k * fs && k * fs <= s.pitchHigh * length && 5 * k <= lastBin);
  for (const k of pitchCandidates) hps[k] = sum(range(1, 5).map(r => Math.log(amplitudes[r * k])));
  const hpsBin = maximum(hps, pitchCandidates), correlationSize = pow2(2 * n - 1);
  const padded = (values: number[]): Complex[] => Array.from({ length: correlationSize }, (_, i) => complex(values[i] ?? 0));
  const bandTransform = radix2(padded(bandpassed)), autocorrelation = radix2(bandTransform.map(value => complex(squaredMagnitude(value))), true).map(value => value.re);
  const autocorrelationLag = maximum(autocorrelation, range(minimumLag, maximumLag)), period = interpolate(autocorrelation, autocorrelationLag, false);
  let crossings = 0; for (let i = 1; i < n; i++) if (bandpassed[i - 1] < 0 && bandpassed[i] >= 0) crossings++;
  const zoomStep = (s.zoomHigh - s.zoomLow) / (s.zoomCount - 1), zoom = chirpZ(main.weighted, s.zoomLow, zoomStep, s.zoomCount, fs).map(value => 2 * magnitude(value) / main.total);
  const zoomPeaks = rankedMaxima(zoom, 3).map((k, i) => ({ rank: i + 1, ...interpolate(zoom, k) }));
  const fx = radix2(padded(x)), fy = radix2(padded(y)), crossSpectrum = fx.map((value, k) => multiply(conjugate(value), fy[k]));
  const correlation = correlationPeak(radix2(crossSpectrum, true), s.maxLag, fs);
  const phat = correlationPeak(radix2(crossSpectrum.map(value => {
    const length = magnitude(value); return complex(value.re / length, value.im / length);
  }), true), s.maxLag, fs);
  const correlationCoefficient = correlation.value / Math.sqrt(squaredSum(x) * squaredSum(y));
  const roundtrip = transform(main.transformed, true);
  const inverseError = Math.max(...roundtrip.map((value, i) => magnitude(subtract(value, complex(main.weighted[i])))));
  const mainEnergy = squaredSum(main.weighted), parsevalError = Math.abs(mainEnergy - sum(main.transformed.map(squaredMagnitude)) / length) / mainEnergy;
  let convolutionError = 0;
  for (let i = 0; i < smoothed.length; i++) {
    let direct = 0; for (let j = Math.max(0, i - s.fir.length + 1); j <= Math.min(n - 1, i); j++) direct += y[j] * s.fir[i - j];
    convolutionError = Math.max(convolutionError, Math.abs(smoothed[i] - direct));
  }
  let spotError = 0;
  for (const peak of peaks) {
    let direct = complex(); for (let i = 0; i < length; i++) direct = add(direct, scale(rot(2 * PI * (peak.bin * i % length) / length), main.weighted[i]));
    spotError = Math.max(spotError, magnitude(subtract(direct, main.transformed[peak.bin])));
  }
  const blocks = range(0, Math.floor(n / s.blockLength) - 1).map(g => {
    const a = x.slice(g * s.blockLength, (g + 1) * s.blockLength), b = y.slice(g * s.blockLength, (g + 1) * s.blockLength);
    return { g, rms1: rms(a), rms2: rms(b), peak: Math.max(...a.map(Math.abs)) };
  });
  const loudest = maximum(blocks.map(block => block.rms1));
  const welchPower = sum(welchResult.psd) * fs / s.welchLength, variance = first.rms * first.rms;
  const welchPeaks = rankedMaxima(welchResult.psd, 5), mainsPeak = peaks.find(peak => peak.label === 'mains');
  const misalignment = harmonics[1].amplitude / fundamental.amplitude, looseness = harmonics.slice(2).filter(h => db20(h.amplitude / fundamental.amplitude) >= -30).length;
  const findings = [misalignment >= 0.5, looseness >= 3, envelopeDepth >= 0.2, mainsPeak !== undefined && mainsPeak.level >= -20, onsets.length > 0];
  const findingCount = findings.filter(Boolean).length, yes = (value: boolean): string => value ? 'yes' : 'no';
  writeCsv('spectrum.csv', 'frequency,amplitude', amplitudes.map((value, k) => [real(k * fs / length), real(value)]));
  writeLines('peaks.txt', [`length=${length} window=${s.mainWindow} resolution=${real(fs / length)} threshold_db=${real(s.threshold)}`,
    `max_amplitude=${real(highest)} noise_floor=${real(floor)} noise_floor_db=${real(db20(floor))}`, `peaks=${peaks.length}`,
    ...peaks.map(p => `${p.rank} bin=${p.bin} frequency=${real(p.frequency)} refined=${real(p.refined)} amplitude=${real(p.amplitude)} level_db=${real(p.level)} phase=${real(p.phase)} bandwidth=${real(p.bandwidth)} snr_db=${real(p.snr)} coherence=${real(p.coherence)} label=${p.label}`)]);
  writeCsv('welch_psd.csv', 'frequency,psd_db', welchResult.psd.map((value, k) => [real(k * fs / s.welchLength), real(db10(value))]));
  writeLines('spectrogram.txt', [`frames=${spectrogram.length} bins=${s.frameLength / 2 + 1} frame_length=${s.frameLength} hop=${s.hop} window=${s.spectrogramWindow} band_db=${s.shadeDb} max_db=${real(db20(spectrogramMaximum))}`,
    ...shadeRows(spectrogram, spectrogramMaximum, fs, s.frameLength, s.shadeDb), 'track',
    ...tracks.map((k, t) => `frame=${t} time=${real(t * s.hop / fs)} frequency=${real(k * fs / s.frameLength)} level_db=${real(db20(spectrogram[t][k] / spectrogramMaximum))}`),
    `onsets=${onsets.length} threshold=${real(onsetThreshold)}`, ...onsets.map(t => `frame=${t} time=${real(t * s.hop / fs)} flux=${real(flux[t])}`),
    `kurtosis bin=${kurtosisBin} frequency=${real(kurtosisBin * fs / s.frameLength)} value=${real(kurtosis[kurtosisBin])}`]);
  writeCsv('filtered.csv', 'index,bandpass,notched,smoothed,envelope', x.map((_, i) => [i, real(bandpassed[i]), real(notched[i]), real(smoothed[i]), real(envelope[i])]));
  const report = ['[signal]', `sample_rate=${fs} samples=${n} duration=${real(n / fs)}`];
  [first, second].forEach((channel, i) => report.push(`channel=${i + 1} mean=${real(channel.mean)} slope=${real(channel.slope)} rms=${real(channel.rms)} min=${real(channel.minimum)} max=${real(channel.maximum)} crest=${real(channel.crest)} skewness=${real(channel.skewness)} kurtosis=${real(channel.kurtosis)}`));
  report.push('[levels]', `block_length=${s.blockLength} blocks=${blocks.length} loudest=${loudest}`,
    ...blocks.map(block => `block=${block.g} time=${real(block.g * s.blockLength / fs)} rms1=${real(block.rms1)} rms2=${real(block.rms2)} peak1=${real(block.peak)}`), '[windows]',
    ...windowComparisons.map(w => `name=${w.name} coherent_gain=${real(w.coherentGain)} enbw_bins=${real(w.enbwBins)} enbw_hz=${real(w.enbwHz)} scalloping_db=${real(w.scallopingDb)} fundamental_bin=${w.bin} bin_amplitude=${real(w.amplitude)} refined_amplitude=${real(w.refined)} floor_db=${real(w.floor)}`),
    '[main]', `length=${length} window=${s.mainWindow} method=${isPowerOfTwo(length) ? 'radix2' : 'bluestein'} transform_size=${isPowerOfTwo(length) ? length : pow2(2 * length - 1)} resolution=${real(fs / length)}`,
    `total_power=${real(totalPower)} centroid=${real(centroid)} spread=${real(spread)} rolloff=${real(rolloff * fs / length)} flatness_db=${real(flatness)}`, '[bands]',
    ...bandPowers.map(band => `range=${band.lower}-${band.upper} power=${real(band.power)} percent=${real(band.percent)}`), '[third_octave]',
    ...octaveBands.map(band => `band=${band.band} center=${real(band.center)} lower=${real(band.lower)} upper=${real(band.upper)} bins=${band.bins} level_db=${real(band.level)}`),
    '[harmonics]', `fundamental=${real(s.fundamental)} search=${s.search}`,
    ...harmonics.map(h => `h=${h.h} target=${real(h.h * s.fundamental)} bin=${h.bin} refined=${real(h.frequency)} amplitude=${real(h.amplitude)} level_db=${real(db20(h.amplitude / fundamental.amplitude))}`),
    `thd_percent=${real(100 * thd)} thd_db=${real(db20(thd))}`, `thdn_percent=${real(100 * thdn)} thdn_db=${real(db20(thdn))}`, '[pitch]',
    `range=${s.pitchLow}-${s.pitchHigh} lags=${minimumLag}-${maximumLag}`, `hps bin=${hpsBin} order=5 frequency=${real(hpsBin * fs / length)}`,
    `autocorrelation lag=${autocorrelationLag} period=${real(period.position)} frequency=${real(fs / period.position)} strength=${real(period.value / autocorrelation[0])}`,
    `zero_crossing count=${crossings} frequency=${real(crossings * fs / n)}`, '[zoom]', `band=${s.zoomLow}-${s.zoomHigh} points=${s.zoomCount} step=${real(zoomStep)}`,
    ...zoomPeaks.map(peak => `peak=${peak.rank} frequency=${real(s.zoomLow + peak.position * zoomStep)} amplitude=${real(peak.value)}`), '[welch]',
    `segment_length=${s.welchLength} segments=${welchResult.count} window=${s.welchWindow} resolution=${real(fs / s.welchLength)}`,
    `integrated_power=${real(welchPower)} variance=${real(variance)} ratio=${real(welchPower / variance)}`,
    ...welchPeaks.map((k, i) => `peak=${i + 1} frequency=${real(k * fs / s.welchLength)} psd_db=${real(db10(welchResult.psd[k]))} coherence=${real(welchResult.coherence[k])} gain=${real(magnitude(welchResult.transfer[k]))} phase=${real(argument(welchResult.transfer[k]) * 180 / PI)}`),
    '[filter]', `bandpass=${s.bandLow}-${s.bandHigh} bins_kept=${binsKept} rms=${real(rms(bandpassed))} energy_ratio=${real(squaredSum(bandpassed) / squaredSum(x))}`,
    `notch=${s.notch} width=${s.notchWidth} bins_removed=${binsRemoved} rms=${real(rms(notched))}`,
    `fir_taps=${s.fir.length} dc_gain=${real(dcGain)} gain_at_fundamental_db=${real(db20(magnitude(filterGain)))} rms=${real(Math.sqrt(squaredSum(smoothed.slice(0, n)) / n))}`,
    '[envelope]', `band=${s.envelopeLow}-${s.envelopeHigh} mean=${real(envelopeMean)} bin=${envelopeBin} frequency=${real(envelopePeak.position * fs / n)} amplitude=${real(envelopePeak.value)} depth=${real(envelopeDepth)}`,
    `instantaneous_frequency mean=${real(instantaneousMean)} std=${real(instantaneousStd)}`, '[correlation]',
    `max_lag=${s.maxLag} lag=${correlation.lag} refined_lag=${real(correlation.refined)} delay_ms=${real(correlation.delay)} coefficient=${real(correlationCoefficient)}`,
    `phat_lag=${phat.lag} refined_lag=${real(phat.refined)} delay_ms=${real(phat.delay)}`, '[checks]',
    `inverse_roundtrip=${inverseError <= 1e-6 ? 'ok' : 'failed'}`, `parseval=${parsevalError <= 1e-6 ? 'ok' : 'failed'}`,
    `real_packing=${packingError <= 1e-6 ? 'ok' : 'failed'} transforms=${packingTransforms}`, `fir_fft_vs_direct=${convolutionError <= 1e-6 ? 'ok' : 'failed'}`,
    `dft_spot_check=${spotError <= 1e-6 ? 'ok' : 'failed'} bins=${peaks.length}`, '[diagnosis]',
    `misalignment=${yes(findings[0])} ratio=${real(misalignment)}`, `looseness=${yes(findings[1])} harmonics=${looseness}`,
    `bearing=${yes(findings[2])} depth=${real(envelopeDepth)}`, `electrical=${yes(findings[3])} level_db=${mainsPeak === undefined ? 'none' : real(mainsPeak.level)}`,
    `transient=${yes(findings[4])} onsets=${onsets.length}`, `status=${findingCount === 0 ? 'normal' : findingCount === 1 ? 'warning' : 'alarm'} findings=${findingCount}`);
  writeLines('report.txt', report);
}
main();
