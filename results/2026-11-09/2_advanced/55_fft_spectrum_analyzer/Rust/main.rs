mod signal_io;
mod fft;
mod windows;
mod spectral;
mod report;

use fft::{Complex, PI};
use report::real;
use std::io;

struct Statistics {
    mean: f64,
    slope: f64,
    rms: f64,
    minimum: f64,
    maximum: f64,
    crest: f64,
    skewness: f64,
    kurtosis: f64,
    detrended: Vec<f64>,
}

fn statistics(values: &[f64], rate: usize) -> Statistics {
    let n = values.len() as f64;
    let mean = values.iter().sum::<f64>() / n;
    let center = (n - 1.0) / 2.0;
    let numerator = values.iter().enumerate().map(|(i, &s)| (i as f64 - center) * (s - mean)).sum::<f64>();
    let denominator = (0..values.len()).map(|i| (i as f64 - center) * (i as f64 - center)).sum::<f64>();
    let slope = numerator / denominator;
    let detrended: Vec<f64> = values.iter().enumerate().map(|(i, &s)| s - mean - slope * (i as f64 - center)).collect();
    let rms = rms(&detrended);
    Statistics { mean, slope: slope * rate as f64, rms, minimum: values.iter().copied().fold(f64::INFINITY, f64::min), maximum: values.iter().copied().fold(f64::NEG_INFINITY, f64::max),
        crest: detrended.iter().map(|d| d.abs()).fold(0.0, f64::max) / rms,
        skewness: (detrended.iter().map(|d| d * d * d).sum::<f64>() / n) / (rms * rms * rms),
        kurtosis: (detrended.iter().map(|d| d * d * d * d).sum::<f64>() / n) / (rms * rms * rms * rms), detrended }
}

fn energy(values: &[f64]) -> f64 {
    values.iter().map(|x| x * x).sum()
}

fn rms(values: &[f64]) -> f64 {
    (energy(values) / values.len() as f64).sqrt()
}

fn maximum(values: &[f64], candidates: impl IntoIterator<Item = usize>) -> usize {
    let mut winner = None;
    for k in candidates {
        if winner.map_or(true, |j| values[k] > values[j]) { winner = Some(k); }
    }
    winner.unwrap()
}

fn peaks(values: &[f64], count: usize) -> Vec<usize> {
    let mut result: Vec<usize> = (1..values.len() - 1).filter(|&k| spectral::local_maximum(values, k)).collect();
    result.sort_by(|&a, &b| values[b].partial_cmp(&values[a]).unwrap().then(a.cmp(&b)));
    result.truncate(count);
    result
}

fn padded(values: &[f64], length: usize) -> Vec<Complex> {
    let mut result = vec![Complex::default(); length];
    for (i, &x) in values.iter().enumerate() { result[i].re = x; }
    result
}

struct Peak {
    bin: usize,
    position: f64,
    amplitude: f64,
    label: String,
}

fn bandwidth(values: &[f64], k: usize) -> f64 {
    let threshold = values[k] / 2.0f64.sqrt();
    let mut right = (values.len() - 1) as f64;
    for j in k + 1..values.len() {
        if values[j] <= threshold { right = (j - 1) as f64 + (values[j - 1] - threshold) / (values[j - 1] - values[j]); break; }
    }
    let mut left = 0.0;
    for j in (0..k).rev() {
        if values[j] <= threshold { left = (j + 1) as f64 - (values[j + 1] - threshold) / (values[j + 1] - values[j]); break; }
    }
    right - left
}

fn correlation_peak(values: &[f64], maximum_lag: usize, rate: usize) -> (i64, f64, f64) {
    let q = values.len() as i64;
    let mut winner = -(maximum_lag as i64);
    for lag in -(maximum_lag as i64)..=maximum_lag as i64 {
        let value = values[lag.rem_euclid(q) as usize];
        let best = values[winner.rem_euclid(q) as usize];
        if value > best || (value == best && (lag.abs(), lag) < (winner.abs(), winner)) { winner = lag; }
    }
    let local = [values[(winner - 1).rem_euclid(q) as usize], values[winner.rem_euclid(q) as usize], values[(winner + 1).rem_euclid(q) as usize]];
    let position = spectral::interpolate(&local, 1, false).0;
    let delta = position - 1.0;
    let refined = winner as f64 + delta;
    (winner, refined, 1000.0 * refined / rate as f64)
}

fn main() -> io::Result<()> {
    let input = signal_io::read()?;
    let p = &input.params;
    let rate = input.rate;
    let fs = rate as f64;
    let n = input.first.len();
    let first = statistics(&input.first, rate);
    let second = statistics(&input.second, rate);
    let x = &first.detrended;
    let y = &second.detrended;
    let m = p.main_length;
    let kmax = m / 2;
    let main_window = windows::values(m, &p.main_window);
    let figures = windows::figures(&main_window, rate);
    let main = spectral::amplitude(x, &main_window);
    let amplitudes = &main.amplitude;
    let amax = amplitudes.iter().copied().fold(0.0, f64::max);
    let floor = spectral::median(&amplitudes[1..kmax]);
    let welch = spectral::welch(x, y, p.welch_length, &p.welch_window, rate);
    let mut bins: Vec<usize> = (1..kmax).filter(|&k| spectral::local_maximum(amplitudes, k) && 20.0 * (amplitudes[k] / amax).log10() >= p.threshold).collect();
    bins.sort_by(|&a, &b| amplitudes[b].partial_cmp(&amplitudes[a]).unwrap().then(a.cmp(&b)));
    bins.truncate(p.peak_count);
    let mut detected: Vec<Peak> = bins.iter().map(|&bin| {
        let (position, amplitude) = spectral::interpolate(amplitudes, bin, true);
        Peak { bin, position, amplitude, label: "other".into() }
    }).collect();
    for i in 0..detected.len() {
        let position = detected[i].position;
        let harmonic = (1..=10).find(|&h| (position - h as f64 * p.fundamental * m as f64 / fs).abs() <= p.search as f64);
        if let Some(h) = harmonic { detected[i].label = format!("h{}", h); continue; }
        let frequency = position * fs / m as f64;
        let mains = (frequency / p.notch[0] as f64 + 0.5).floor() as usize;
        if mains >= 1 && (frequency - (mains * p.notch[0]) as f64).abs() <= p.notch[1] as f64 { detected[i].label = "mains".into(); continue; }
        'search: for center in 0..detected.len() {
            for other in 0..detected.len() {
                if i != center && i != other && center != other && amplitudes[detected[center].bin] > amplitudes[detected[i].bin]
                    && amplitudes[detected[center].bin] > amplitudes[detected[other].bin]
                    && (position + detected[other].position - 2.0 * detected[center].position).abs() <= 1.0 {
                    detected[i].label = format!("sideband{}", center + 1);
                    break 'search;
                }
            }
        }
    }
    let mut peak_lines = vec![format!("length={} window={} resolution={} threshold_db={}", m, p.main_window, real(fs / m as f64), real(p.threshold)),
        format!("max_amplitude={} noise_floor={} noise_floor_db={}", real(amax), real(floor), real(20.0 * floor.log10())), format!("peaks={}", detected.len())];
    for (rank, peak) in detected.iter().enumerate() {
        let coherence_bin = (2 * peak.bin * p.welch_length + m) / (2 * m);
        peak_lines.push(format!("{} bin={} frequency={} refined={} amplitude={} level_db={} phase={} bandwidth={} snr_db={} coherence={} label={}", rank + 1, peak.bin,
            real(peak.bin as f64 * fs / m as f64), real(peak.position * fs / m as f64), real(peak.amplitude), real(20.0 * (amplitudes[peak.bin] / amax).log10()),
            real(main.transform[peak.bin].arg() * 180.0 / PI), real(bandwidth(amplitudes, peak.bin) * fs / m as f64), real(20.0 * (amplitudes[peak.bin] / floor).log10()), real(welch.coherence[coherence_bin]), peak.label));
    }
    let harmonics: Vec<(usize, f64, f64)> = (1..=10).map(|h| {
        let target = h as f64 * p.fundamental * m as f64 / fs;
        let bin = maximum(amplitudes, (1..kmax).filter(|&k| (k as f64 - target).abs() <= p.search as f64));
        let (position, amplitude) = spectral::interpolate(amplitudes, bin, true);
        (bin, position, amplitude)
    }).collect();
    let fundamental_amplitude = harmonics[0].2;
    let thd = (harmonics[1..].iter().map(|h| h.2 * h.2).sum::<f64>()).sqrt() / fundamental_amplitude;
    let power: Vec<f64> = amplitudes.iter().map(|a| a * a / 2.0).collect();
    let summed_power = power[1..kmax].iter().sum::<f64>();
    let total_power = summed_power / figures.enbw_bins;
    let fundamental_power = (1..kmax).filter(|&k| k.abs_diff(harmonics[0].0) <= p.search).map(|k| power[k]).sum::<f64>() / figures.enbw_bins;
    let thdn = ((total_power - fundamental_power) / fundamental_power).sqrt();
    let centroid = (1..kmax).map(|k| k as f64 * fs / m as f64 * power[k]).sum::<f64>() / summed_power;
    let spread = ((1..kmax).map(|k| {
        let difference = k as f64 * fs / m as f64 - centroid;
        difference * difference * power[k]
    }).sum::<f64>() / summed_power).sqrt();
    let mut running = 0.0;
    let mut rolloff = 1;
    for k in 1..kmax { running += power[k]; if running >= 0.85 * summed_power { rolloff = k; break; } }
    let flatness = 10.0 * ((power[1..kmax].iter().map(|v| v.ln()).sum::<f64>() / (kmax - 1) as f64).exp() / (summed_power / (kmax - 1) as f64)).log10();
    let transform = fft::real(x);
    let mut band_transform = transform.clone();
    let mut notch_transform = transform.clone();
    let mut envelope_transform = vec![Complex::default(); n];
    let (mut bins_kept, mut bins_removed) = (0, 0);
    for k in 0..n {
        let g = k.min(n - k) * rate;
        if p.bandpass[0] * n <= g && g <= p.bandpass[1] * n { bins_kept += 1; } else { band_transform[k] = Complex::default(); }
        let j = (2 * g + p.notch[0] * n) / (2 * p.notch[0] * n);
        if j >= 1 && g.abs_diff(j * p.notch[0] * n) <= p.notch[1] * n { notch_transform[k] = Complex::default(); bins_removed += 1; }
        if k >= 1 && k <= (n - 1) / 2 && p.envelope[0] * n <= k * rate && k * rate <= p.envelope[1] * n { envelope_transform[k] = transform[k].scale(2.0); }
    }
    let bandpassed: Vec<f64> = fft::transform(&band_transform, true).iter().map(|v| v.re).collect();
    let notched: Vec<f64> = fft::transform(&notch_transform, true).iter().map(|v| v.re).collect();
    let analytic = fft::transform(&envelope_transform, true);
    let envelope: Vec<f64> = analytic.iter().map(|v| v.abs()).collect();
    let envelope_mean = envelope.iter().sum::<f64>() / n as f64;
    let centered_envelope: Vec<f64> = envelope.iter().map(|v| v - envelope_mean).collect();
    let envelope_spectrum: Vec<f64> = fft::real(&centered_envelope).iter().map(|v| 2.0 * v.abs() / n as f64).collect();
    let envelope_bin = maximum(&envelope_spectrum, 1..=((p.envelope[1] - p.envelope[0]) * n / (2 * rate)));
    let (envelope_position, envelope_amplitude) = spectral::interpolate(&envelope_spectrum, envelope_bin, true);
    let envelope_depth = envelope_amplitude / envelope_mean;
    let phases: Vec<f64> = analytic.iter().map(|v| v.arg()).collect();
    let instantaneous: Vec<f64> = phases.windows(2).map(|p| {
        let mut difference = p[1] - p[0];
        if difference <= -PI { difference += 2.0 * PI; }
        if difference > PI { difference -= 2.0 * PI; }
        difference * fs / (2.0 * PI)
    }).collect();
    let instantaneous_mean = instantaneous.iter().sum::<f64>() / (n - 1) as f64;
    let instantaneous_std = (instantaneous.iter().map(|v| (v - instantaneous_mean) * (v - instantaneous_mean)).sum::<f64>() / (n - 1) as f64).sqrt();
    let smoothed = fft::convolution(y, &p.fir);
    let fir_dc = p.fir.iter().sum::<f64>();
    let mut fir_response = Complex::default();
    for (j, &h) in p.fir.iter().enumerate() { fir_response = fir_response + fft::rot(2.0 * PI * p.fundamental * j as f64 / fs).scale(h); }
    let lag_min = (rate + p.pitch[1] - 1) / p.pitch[1];
    let lag_max = rate / p.pitch[0];
    let mut hps = vec![f64::NEG_INFINITY; kmax + 1];
    let hps_candidates: Vec<usize> = (1..=kmax / 5).filter(|&k| p.pitch[0] * m <= k * rate && k * rate <= p.pitch[1] * m).collect();
    for &k in &hps_candidates { hps[k] = (1..=5).map(|r| amplitudes[r * k].ln()).sum(); }
    let hps_bin = maximum(&hps, hps_candidates);
    let q = fft::pow2(2 * n - 1);
    let band_fft = fft::radix2(&padded(&bandpassed, q), false);
    let band_power: Vec<Complex> = band_fft.iter().map(|v| Complex::new(v.norm2(), 0.0)).collect();
    let autocorrelation: Vec<f64> = fft::radix2(&band_power, true).iter().map(|v| v.re).collect();
    let lag = maximum(&autocorrelation, lag_min..=lag_max);
    let (period, correlation_strength) = spectral::interpolate(&autocorrelation, lag, false);
    let crossings = bandpassed.windows(2).filter(|p| p[0] < 0.0 && p[1] >= 0.0).count();
    let zoom_step = (p.zoom[1] - p.zoom[0]) as f64 / (p.zoom[2] - 1) as f64;
    let zoom_transform = fft::chirp_z(&main.windowed, p.zoom[0] as f64, zoom_step, p.zoom[2], fs);
    let zoom_amplitude: Vec<f64> = zoom_transform.iter().map(|v| 2.0 * v.abs() / main.sum).collect();
    let zoom_peaks = peaks(&zoom_amplitude, 3);
    let frames = spectral::frames(x, p.frame_length, p.hop, &p.frame_window);
    let frame_count = frames.magnitude.len();
    let maximum_frame = frames.magnitude.iter().flat_map(|r| r.iter().copied()).fold(0.0, f64::max);
    let dominant: Vec<usize> = frames.magnitude.iter().map(|r| maximum(r, 1..p.frame_length / 2)).collect();
    let mut flux = vec![0.0; frame_count];
    for t in 1..frame_count { flux[t] = (0..=p.frame_length / 2).map(|k| (frames.magnitude[t][k] - frames.magnitude[t - 1][k]).max(0.0)).sum(); }
    let onset_threshold = p.onset * spectral::median(&flux[1..]);
    let onsets: Vec<usize> = (1..frame_count).filter(|&t| flux[t] > onset_threshold && flux[t] > flux[t - 1] && (t == frame_count - 1 || flux[t] > flux[t + 1])).collect();
    let spectral_kurtosis: Vec<f64> = (0..=p.frame_length / 2).map(|k| {
        let fourth = frames.magnitude.iter().map(|r| r[k] * r[k] * r[k] * r[k]).sum::<f64>();
        let second = frames.magnitude.iter().map(|r| r[k] * r[k]).sum::<f64>();
        frame_count as f64 * fourth / (second * second) - 2.0
    }).collect();
    let kurtosis_bin = maximum(&spectral_kurtosis, 1..p.frame_length / 2);
    let fx = fft::radix2(&padded(x, q), false);
    let fy = fft::radix2(&padded(y, q), false);
    let cross: Vec<Complex> = fx.iter().zip(&fy).map(|(&a, &b)| a.conj() * b).collect();
    let phat: Vec<Complex> = cross.iter().map(|&v| v / v.abs()).collect();
    let correlation: Vec<f64> = fft::radix2(&cross, true).iter().map(|v| v.re).collect();
    let phat_correlation: Vec<f64> = fft::radix2(&phat, true).iter().map(|v| v.re).collect();
    let (correlation_lag, refined_lag, delay) = correlation_peak(&correlation, p.lag, rate);
    let (phat_lag, phat_refined, phat_delay) = correlation_peak(&phat_correlation, p.lag, rate);
    let coefficient = correlation[correlation_lag.rem_euclid(q as i64) as usize] / (energy(x) * energy(y)).sqrt();
    let inverse = fft::transform(&main.transform, true);
    let inverse_error = inverse.iter().zip(&main.windowed).map(|(&v, &u)| (v - Complex::new(u, 0.0)).abs()).fold(0.0, f64::max);
    let u_energy = energy(&main.windowed);
    let parseval_error = (u_energy - main.transform.iter().map(|v| v.norm2()).sum::<f64>() / m as f64).abs() / u_energy;
    let mut fir_error: f64 = 0.0;
    for i in 0..smoothed.len() {
        let start = i.saturating_sub(p.fir.len() - 1);
        let end = i.min(n - 1);
        let direct = (start..=end).map(|j| y[j] * p.fir[i - j]).sum::<f64>();
        fir_error = fir_error.max((smoothed[i] - direct).abs());
    }
    let mut spot_error: f64 = 0.0;
    for peak in &detected {
        let mut direct = Complex::default();
        for i in 0..m { direct = direct + fft::rot(2.0 * PI * ((peak.bin * i) % m) as f64 / m as f64).scale(main.windowed[i]); }
        spot_error = spot_error.max((direct - main.transform[peak.bin]).abs());
    }
    let mut report_lines = vec!["[signal]".into(), format!("sample_rate={} samples={} duration={}", rate, n, real(n as f64 / fs))];
    for (channel, stats) in [(1, &first), (2, &second)] {
        report_lines.push(format!("channel={} mean={} slope={} rms={} min={} max={} crest={} skewness={} kurtosis={}", channel, real(stats.mean), real(stats.slope), real(stats.rms), real(stats.minimum), real(stats.maximum), real(stats.crest), real(stats.skewness), real(stats.kurtosis)));
    }
    let blocks = n / p.block;
    let block_rms: Vec<f64> = (0..blocks).map(|g| rms(&x[g * p.block..(g + 1) * p.block])).collect();
    let loudest = maximum(&block_rms, 0..blocks);
    report_lines.extend(["[levels]".into(), format!("block_length={} blocks={} loudest={}", p.block, blocks, loudest)]);
    for g in 0..blocks {
        let start = g * p.block;
        let end = start + p.block;
        report_lines.push(format!("block={} time={} rms1={} rms2={} peak1={}", g, real(start as f64 / fs), real(block_rms[g]), real(rms(&y[start..end])), real(x[start..end].iter().map(|v| v.abs()).fold(0.0, f64::max))));
    }
    report_lines.push("[windows]".into());
    for name in windows::NAMES {
        let window = windows::values(m, name);
        let figures = windows::figures(&window, rate);
        let spectrum = spectral::amplitude(x, &window);
        let target = p.fundamental * m as f64 / fs;
        let bin = maximum(&spectrum.amplitude, (1..kmax).filter(|&k| (k as f64 - target).abs() <= p.search as f64));
        let refined = spectral::interpolate(&spectrum.amplitude, bin, true).1;
        report_lines.push(format!("name={} coherent_gain={} enbw_bins={} enbw_hz={} scalloping_db={} fundamental_bin={} bin_amplitude={} refined_amplitude={} floor_db={}", name,
            real(figures.gain), real(figures.enbw_bins), real(figures.enbw_hz), real(figures.scalloping), bin, real(spectrum.amplitude[bin]), real(refined), real(20.0 * spectral::median(&spectrum.amplitude[1..kmax]).log10())));
    }
    report_lines.extend(["[main]".into(), format!("length={} window={} method={} transform_size={} resolution={}", m, p.main_window, if m.is_power_of_two() { "radix2" } else { "bluestein" },
        if m.is_power_of_two() { m } else { fft::pow2(2 * m - 1) }, real(fs / m as f64)), format!("total_power={} centroid={} spread={} rolloff={} flatness_db={}", real(total_power), real(centroid), real(spread), real(rolloff as f64 * fs / m as f64), real(flatness)), "[bands]".into()]);
    for band in p.bands.windows(2) {
        let band_power = (1..kmax).filter(|&k| band[0] * m <= k * rate && k * rate < band[1] * m).map(|k| power[k]).sum::<f64>() / figures.enbw_bins;
        report_lines.push(format!("range={}-{} power={} percent={}", band[0], band[1], real(band_power), real(100.0 * band_power / total_power)));
    }
    report_lines.push("[third_octave]".into());
    for b in p.thirds[0]..=p.thirds[1] {
        let center = 1000.0 * 2.0f64.powf(b as f64 / 3.0);
        let lower = 1000.0 * 2.0f64.powf((2 * b - 1) as f64 / 6.0);
        let upper = 1000.0 * 2.0f64.powf((2 * b + 1) as f64 / 6.0);
        let bins: Vec<usize> = (1..kmax).filter(|&k| lower <= (k as f64 * fs / m as f64) && (k as f64 * fs / m as f64) < upper).collect();
        let band_power = bins.iter().map(|&k| power[k]).sum::<f64>() / figures.enbw_bins;
        report_lines.push(format!("band={} center={} lower={} upper={} bins={} level_db={}", b, real(center), real(lower), real(upper), bins.len(), real(10.0 * band_power.log10())));
    }
    report_lines.extend(["[harmonics]".into(), format!("fundamental={} search={}", real(p.fundamental), p.search)]);
    for (i, &(bin, position, amplitude)) in harmonics.iter().enumerate() {
        report_lines.push(format!("h={} target={} bin={} refined={} amplitude={} level_db={}", i + 1, real((i + 1) as f64 * p.fundamental), bin, real(position * fs / m as f64), real(amplitude), real(20.0 * (amplitude / fundamental_amplitude).log10())));
    }
    report_lines.extend([format!("thd_percent={} thd_db={}", real(100.0 * thd), real(20.0 * thd.log10())), format!("thdn_percent={} thdn_db={}", real(100.0 * thdn), real(20.0 * thdn.log10())),
        "[pitch]".into(), format!("range={}-{} lags={}-{}", p.pitch[0], p.pitch[1], lag_min, lag_max), format!("hps bin={} order=5 frequency={}", hps_bin, real(hps_bin as f64 * fs / m as f64)),
        format!("autocorrelation lag={} period={} frequency={} strength={}", lag, real(period), real(fs / period), real(correlation_strength / autocorrelation[0])),
        format!("zero_crossing count={} frequency={}", crossings, real(crossings as f64 * fs / n as f64)), "[zoom]".into(), format!("band={}-{} points={} step={}", p.zoom[0], p.zoom[1], p.zoom[2], real(zoom_step))]);
    for (rank, &j) in zoom_peaks.iter().enumerate() {
        let (position, amplitude) = spectral::interpolate(&zoom_amplitude, j, true);
        report_lines.push(format!("peak={} frequency={} amplitude={}", rank + 1, real(p.zoom[0] as f64 + position * zoom_step), real(amplitude)));
    }
    let integrated_power = welch.psd.iter().sum::<f64>() * fs / p.welch_length as f64;
    report_lines.extend(["[welch]".into(), format!("segment_length={} segments={} window={} resolution={}", p.welch_length, welch.count, p.welch_window, real(fs / p.welch_length as f64)),
        format!("integrated_power={} variance={} ratio={}", real(integrated_power), real(first.rms * first.rms), real(integrated_power / (first.rms * first.rms)))]);
    for (rank, &bin) in peaks(&welch.psd, 5).iter().enumerate() {
        report_lines.push(format!("peak={} frequency={} psd_db={} coherence={} gain={} phase={}", rank + 1, real(bin as f64 * fs / p.welch_length as f64), real(10.0 * welch.psd[bin].log10()),
            real(welch.coherence[bin]), real(welch.transfer[bin].abs()), real(welch.transfer[bin].arg() * 180.0 / PI)));
    }
    report_lines.extend(["[filter]".into(), format!("bandpass={}-{} bins_kept={} rms={} energy_ratio={}", p.bandpass[0], p.bandpass[1], bins_kept, real(rms(&bandpassed)), real(energy(&bandpassed) / energy(x))),
        format!("notch={} width={} bins_removed={} rms={}", p.notch[0], p.notch[1], bins_removed, real(rms(&notched))),
        format!("fir_taps={} dc_gain={} gain_at_fundamental_db={} rms={}", p.fir.len(), real(fir_dc), real(20.0 * fir_response.abs().log10()), real(rms(&smoothed[..n]))),
        "[envelope]".into(), format!("band={}-{} mean={} bin={} frequency={} amplitude={} depth={}", p.envelope[0], p.envelope[1], real(envelope_mean), envelope_bin, real(envelope_position * fs / n as f64), real(envelope_amplitude), real(envelope_depth)),
        format!("instantaneous_frequency mean={} std={}", real(instantaneous_mean), real(instantaneous_std)), "[correlation]".into(),
        format!("max_lag={} lag={} refined_lag={} delay_ms={} coefficient={}", p.lag, correlation_lag, real(refined_lag), real(delay), real(coefficient)),
        format!("phat_lag={} refined_lag={} delay_ms={}", phat_lag, real(phat_refined), real(phat_delay)), "[checks]".into()]);
    let check = |error: f64| if error <= 1e-6 { "ok" } else { "failed" };
    report_lines.extend([format!("inverse_roundtrip={}", check(inverse_error)), format!("parseval={}", check(parseval_error)), format!("real_packing={} transforms={}", check(welch.packing_error.max(frames.packing_error)), 2 * welch.count + frame_count),
        format!("fir_fft_vs_direct={}", check(fir_error)), format!("dft_spot_check={} bins={}", check(spot_error), detected.len()), "[diagnosis]".into()]);
    let harmonic_ratio = harmonics[1].2 / fundamental_amplitude;
    let third_count = harmonics[2..].iter().filter(|h| 20.0 * (h.2 / fundamental_amplitude).log10() >= -30.0).count();
    let electrical = detected.iter().find(|p| p.label == "mains").map(|p| 20.0 * (amplitudes[p.bin] / amax).log10());
    let findings = [harmonic_ratio >= 0.5, third_count >= 3, envelope_depth >= 0.2, electrical.map_or(false, |v| v >= -20.0), !onsets.is_empty()];
    let yes = |v| if v { "yes" } else { "no" };
    let finding_count = findings.iter().filter(|&&v| v).count();
    report_lines.extend([format!("misalignment={} ratio={}", yes(findings[0]), real(harmonic_ratio)), format!("looseness={} harmonics={}", yes(findings[1]), third_count),
        format!("bearing={} depth={}", yes(findings[2]), real(envelope_depth)), format!("electrical={} level_db={}", yes(findings[3]), electrical.map_or("none".into(), real)),
        format!("transient={} onsets={}", yes(findings[4]), onsets.len()), format!("status={} findings={}", match finding_count { 0 => "normal", 1 => "warning", _ => "alarm" }, finding_count)]);
    let mut spectrum_lines = vec!["frequency,amplitude".into()];
    for k in 0..=kmax { spectrum_lines.push(format!("{},{}", real(k as f64 * fs / m as f64), real(amplitudes[k]))); }
    let mut welch_lines = vec!["frequency,psd_db".into()];
    for k in 0..=p.welch_length / 2 { welch_lines.push(format!("{},{}", real(k as f64 * fs / p.welch_length as f64), real(10.0 * welch.psd[k].log10()))); }
    let mut spectrogram = vec![format!("frames={} bins={} frame_length={} hop={} window={} band_db={} max_db={}", frame_count, p.frame_length / 2 + 1, p.frame_length, p.hop, p.frame_window, p.shade, real(20.0 * maximum_frame.log10()))];
    for k in (0..=p.frame_length / 2).rev() { spectrogram.push(report::shade_line(k as f64 * fs / p.frame_length as f64, &frames.magnitude, k, maximum_frame, p.shade)); }
    spectrogram.push("track".into());
    for t in 0..frame_count { spectrogram.push(format!("frame={} time={} frequency={} level_db={}", t, real((t * p.hop) as f64 / fs), real(dominant[t] as f64 * fs / p.frame_length as f64), real(20.0 * (frames.magnitude[t][dominant[t]] / maximum_frame).log10()))); }
    spectrogram.push(format!("onsets={} threshold={}", onsets.len(), real(onset_threshold)));
    for &t in &onsets { spectrogram.push(format!("frame={} time={} flux={}", t, real((t * p.hop) as f64 / fs), real(flux[t]))); }
    spectrogram.push(format!("kurtosis bin={} frequency={} value={}", kurtosis_bin, real(kurtosis_bin as f64 * fs / p.frame_length as f64), real(spectral_kurtosis[kurtosis_bin])));
    let mut filtered = vec!["index,bandpass,notched,smoothed,envelope".into()];
    for i in 0..n { filtered.push(format!("{},{},{},{},{}", i, real(bandpassed[i]), real(notched[i]), real(smoothed[i]), real(envelope[i]))); }
    for (name, lines) in [("spectrum.csv", spectrum_lines), ("peaks.txt", peak_lines), ("welch_psd.csv", welch_lines), ("spectrogram.txt", spectrogram), ("filtered.csv", filtered), ("report.txt", report_lines)] { report::write(name, &lines)?; }
    Ok(())
}
