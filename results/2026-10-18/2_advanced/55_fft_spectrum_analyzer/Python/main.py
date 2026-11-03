"""Two-channel vibration analysis using directly implemented Fourier transforms.

Run from the task directory: python3 Python/main.py
All inputs come from input/ and all six outputs are written under output/.
"""

import math

from fft import PI, chirp_z, dft, idft, pow2, radix2, rot, convolution
from report import fields, real, shade_lines, write_csv, write_lines
from signal_io import read_params, read_signal
from spectral import (
    amplitude_spectrum, interpolate, local_maximum, median,
    spectrogram_magnitudes, welch_spectra,
)
from windows import WINDOW_ORDER, figures, window


def mean_square(values):
    """Compute the mean square without any external numeric dependencies."""
    return sum(value * value for value in values) / len(values)


def rms(values):
    return math.sqrt(mean_square(values))


def decibels(value, factor=20):
    return factor * math.log10(value)


def phase_degrees(value):
    return math.atan2(value.imag, value.real) * 180 / PI


def detrend(samples, sample_rate):
    """Remove the least-squares constant and straight-line components."""
    count = len(samples)
    center = (count - 1) / 2
    average = sum(samples) / count
    numerator = sum((i - center) * (sample - average)
                    for i, sample in enumerate(samples))
    denominator = sum((i - center) ** 2 for i in range(count))
    slope = numerator / denominator
    residual = [
        sample - average - slope * (i - center)
        for i, sample in enumerate(samples)
    ]
    level = rms(residual)
    return residual, {
        "mean": average,
        "slope": slope * sample_rate,
        "rms": level,
        "min": min(samples),
        "max": max(samples),
        "crest": max(abs(value) for value in residual) / level,
        "skewness": (sum(v ** 3 for v in residual) / count) / level ** 3,
        "kurtosis": (sum(v ** 4 for v in residual) / count) / level ** 4,
    }


def level_history(x, y, block_length):
    """Measure channel energy in non-overlapping complete blocks."""
    history = []
    for block in range(len(x) // block_length):
        start = block * block_length
        stop = start + block_length
        left = x[start:stop]
        right = y[start:stop]
        history.append({
            "number": block,
            "rms1": rms(left),
            "rms2": rms(right),
            "peak1": max(abs(value) for value in left),
        })
    loudest = max(range(len(history)), key=lambda g: (history[g]["rms1"], -g))
    return history, loudest


def strongest_local_maxima(values, limit):
    """Rank strict interior maxima by decreasing value then increasing bin."""
    candidates = [
        k for k in range(1, len(values) - 1)
        if local_maximum(values, k)
    ]
    candidates.sort(key=lambda k: (-values[k], k))
    return candidates[:limit]


def amplitude_bandwidth(amplitudes, k):
    """Interpolate both half-power crossing points around an FFT peak."""
    last = len(amplitudes) - 1
    cutoff = amplitudes[k] / math.sqrt(2)
    crossing_right = next((j for j in range(k + 1, last + 1)
                           if amplitudes[j] <= cutoff), None)
    if crossing_right is None:
        right = float(last)
    else:
        j = crossing_right
        right = j - 1 + (amplitudes[j - 1] - cutoff) / (
            amplitudes[j - 1] - amplitudes[j])
    crossing_left = next((j for j in range(k - 1, -1, -1)
                          if amplitudes[j] <= cutoff), None)
    if crossing_left is None:
        left = 0.0
    else:
        j = crossing_left
        left = j + 1 - (amplitudes[j + 1] - cutoff) / (
            amplitudes[j + 1] - amplitudes[j])
    return right - left


def label_peak(peak, peaks, parameters, sample_rate, main_length):
    """Classify harmonics, line-frequency peaks and modulation sidebands."""
    nominal, width = parameters["fundamental"]
    notch_frequency, notch_width = parameters["notch"]
    position = peak["position"]
    for harmonic in range(1, 11):
        target = harmonic * nominal * main_length / sample_rate
        if abs(position - target) <= width:
            return f"h{harmonic}"
    frequency = position * sample_rate / main_length
    multiple = math.floor(frequency / notch_frequency + 0.5)
    if multiple >= 1 and abs(frequency - multiple * notch_frequency) <= notch_width:
        return "mains"
    for pivot in peaks:
        if pivot is peak or pivot["bin_amplitude"] <= peak["bin_amplitude"]:
            continue
        for other in peaks:
            if other is peak or other is pivot:
                continue
            if pivot["bin_amplitude"] <= other["bin_amplitude"]:
                continue
            if abs(position + other["position"] - 2 * pivot["position"]) <= 1:
                return f"sideband{pivot['rank']}"
    return "other"


def main_peaks(amplitudes, transformed, parameters, sample_rate, welch):
    """Find peaks, interpolate and annotate them with cross-channel coherence."""
    main_length = parameters["main_length"]
    segment_length = parameters["welch"][0]
    threshold = parameters["peak_threshold_db"]
    maximum = max(amplitudes)
    noise_floor = median(amplitudes[1:-1])
    candidates = [
        k for k in strongest_local_maxima(amplitudes, len(amplitudes))
        if decibels(amplitudes[k] / maximum) >= threshold
    ][:parameters["peak_count"]]
    peaks = []
    for rank, k in enumerate(candidates, 1):
        position, amplitude = interpolate(amplitudes, k)
        coherence_bin = (2 * k * segment_length + main_length) // (2 * main_length)
        peaks.append({
            "rank": rank,
            "bin": k,
            "position": position,
            "bin_amplitude": amplitudes[k],
            "frequency": k * sample_rate / main_length,
            "refined": position * sample_rate / main_length,
            "amplitude": amplitude,
            "level_db": decibels(amplitudes[k] / maximum),
            "phase": phase_degrees(transformed[k]),
            "bandwidth": amplitude_bandwidth(amplitudes, k) * sample_rate / main_length,
            "snr_db": decibels(amplitudes[k] / noise_floor),
            "coherence": welch["coherence"][coherence_bin],
        })
    for peak in peaks:
        peak["label"] = label_peak(peak, peaks, parameters, sample_rate, main_length)
    return peaks, maximum, noise_floor


def harmonic_analysis(amplitudes, parameters, sample_rate):
    """Inspect ten harmonics with deterministic bin selection and interpolation."""
    main_length = parameters["main_length"]
    nominal, width = parameters["fundamental"]
    interior = range(1, main_length // 2)
    harmonics = []
    for harmonic in range(1, 11):
        center = harmonic * nominal * main_length / sample_rate
        targets = [k for k in interior if abs(k - center) <= width]
        bin_number = max(targets, key=lambda k: (amplitudes[k], -k))
        position, amplitude = interpolate(amplitudes, bin_number)
        harmonics.append({
            "number": harmonic,
            "target": harmonic * nominal,
            "bin": bin_number,
            "position": position,
            "frequency": position * sample_rate / main_length,
            "amplitude": amplitude,
        })
    primary = harmonics[0]["amplitude"]
    for entry in harmonics:
        entry["level_db"] = decibels(entry["amplitude"] / primary)
    thd = math.sqrt(sum(entry["amplitude"] ** 2 for entry in harmonics[1:])) / primary
    return harmonics, {
        "thd_percent": 100 * thd,
        "thd_db": decibels(thd),
    }


def power_analysis(amplitudes, sample_rate, parameters, harmonics, enbw_bins):
    """Compute broadband and harmonic powers and spectral-shape measures."""
    main_length = parameters["main_length"]
    half = main_length // 2
    power = [amplitude * amplitude / 2 for amplitude in amplitudes]
    interior = range(1, half)
    sum_power = sum(power[k] for k in interior)
    total_power = sum_power / enbw_bins
    first_bin = harmonics[0]["bin"]
    width = parameters["fundamental"][1]
    primary = sum(power[k] for k in interior if abs(k - first_bin) <= width)
    primary /= enbw_bins
    thdn = math.sqrt((total_power - primary) / primary)
    centroid = (sum(k * sample_rate / main_length * power[k] for k in interior)
                / sum_power)
    spread = math.sqrt(
        sum((k * sample_rate / main_length - centroid) ** 2 * power[k]
            for k in interior) / sum_power
    )
    cumulative = 0.0
    rolloff = 0.0
    for k in interior:
        cumulative += power[k]
        if cumulative >= 0.85 * sum_power:
            rolloff = k * sample_rate / main_length
            break
    average_power = sum_power / (half - 1)
    flatness_db = 10 * math.log10(
        math.exp(sum(math.log(power[k]) for k in interior) / (half - 1))
        / average_power
    )
    return power, {
        "total_power": total_power,
        "centroid": centroid,
        "spread": spread,
        "rolloff": rolloff,
        "flatness_db": flatness_db,
        "thdn_percent": 100 * thdn,
        "thdn_db": decibels(thdn),
    }


def calculate_bands(power, parameters, sample_rate, enbw, total_power):
    """Calculate exact-bin frequency bands and fractional-octave bands."""
    main_length = parameters["main_length"]
    half = main_length // 2
    interior = range(1, half)
    boundaries = parameters["bands"]
    bands = []
    for lower, upper in zip(boundaries, boundaries[1:]):
        value = sum(power[k] for k in interior
                    if lower * main_length <= k * sample_rate < upper * main_length)
        value /= enbw
        bands.append((lower, upper, value, 100 * value / total_power))
    first, last = parameters["third_octave"]
    third_octaves = []
    for band in range(first, last + 1):
        center = 1000 * 2 ** (band / 3)
        lower = 1000 * 2 ** ((2 * band - 1) / 6)
        upper = 1000 * 2 ** ((2 * band + 1) / 6)
        indices = [k for k in interior
                   if lower <= k * sample_rate / main_length < upper]
        band_power = sum(power[k] for k in indices) / enbw
        third_octaves.append({
            "band": band, "center": center, "lower": lower, "upper": upper,
            "bins": len(indices), "level_db": decibels(band_power, 10),
        })
    return bands, third_octaves


def compare_windows(signal, parameters, sample_rate):
    """Calculate calibration, fundamental amplitude and floor for all windows."""
    main_length = parameters["main_length"]
    nominal, width = parameters["fundamental"]
    first_center = nominal * main_length / sample_rate
    comparison = []
    for name in WINDOW_ORDER:
        calibration = figures(window(name, main_length), sample_rate)
        _, _, amplitudes = amplitude_spectrum(signal, name, main_length)
        indices = [k for k in range(1, main_length // 2)
                   if abs(k - first_center) <= width]
        strongest = max(indices, key=lambda k: (amplitudes[k], -k))
        _, value = interpolate(amplitudes, strongest)
        comparison.append({
            "name": name,
            **calibration,
            "fundamental_bin": strongest,
            "bin_amplitude": amplitudes[strongest],
            "refined_amplitude": value,
            "floor_db": decibels(median(amplitudes[1:-1])),
        })
    return comparison


def analyze_welch(x, y, parameters, sample_rate):
    """Compute PSD summary and report its five strongest interior peaks."""
    length, name = parameters["welch"]
    data = welch_spectra(x, y, sample_rate, length, name)
    spectrum = data["psd"]
    integrated = sum(spectrum) * sample_rate / length
    variance = mean_square(x)
    peaks = []
    for rank, k in enumerate(strongest_local_maxima(spectrum, 5), 1):
        transfer = data["transfer"][k]
        peaks.append({
            "rank": rank,
            "frequency": k * sample_rate / length,
            "psd_db": decibels(spectrum[k], 10),
            "coherence": data["coherence"][k],
            "gain": abs(transfer),
            "phase": phase_degrees(transfer),
        })
    data.update({
        "length": length, "window": name,
        "integrated_power": integrated,
        "variance": variance,
        "ratio": integrated / variance,
        "peaks": peaks,
    })
    return data


def analyze_spectrogram(signal, parameters, sample_rate):
    """Make a real-packed STFT and extract time-frequency diagnostics."""
    length, hop, band_db, name = parameters["spectrogram"]
    grid, packing_error = spectrogram_magnitudes(signal, length, hop, name)
    frames = len(grid)
    maximum = max(value for row in grid for value in row)
    dominant = []
    for t, spectrum in enumerate(grid):
        bin_number = max(range(1, length // 2),
                         key=lambda k: (spectrum[k], -k))
        dominant.append({
            "frame": t,
            "time": t * hop / sample_rate,
            "frequency": bin_number * sample_rate / length,
            "level_db": decibels(spectrum[bin_number] / maximum),
        })
    flux = [0.0]
    for t in range(1, frames):
        flux.append(sum(max(0.0, grid[t][k] - grid[t - 1][k])
                        for k in range(length // 2 + 1)))
    threshold = parameters["onset_factor"] * median(flux[1:])
    onsets = [
        t for t in range(1, frames)
        if flux[t] > threshold and flux[t] > flux[t - 1]
        and (t == frames - 1 or flux[t] > flux[t + 1])
    ]
    kurtosis = []
    for k in range(length // 2 + 1):
        second = sum(row[k] ** 2 for row in grid)
        fourth = sum(row[k] ** 4 for row in grid)
        kurtosis.append(frames * fourth / (second * second) - 2)
    top_kurtosis = max(range(1, length // 2),
                       key=lambda k: (kurtosis[k], -k))
    return {
        "grid": grid, "frames": frames, "maximum": maximum,
        "length": length, "hop": hop, "band_db": band_db, "window": name,
        "dominant": dominant, "flux": flux, "onsets": onsets,
        "onset_threshold": threshold, "kurtosis": kurtosis,
        "top_kurtosis": top_kurtosis, "packing_error": packing_error,
    }


def filtered_waveforms(x, y, parameters, sample_rate):
    """Compute spectral band-pass/notch, analytic envelope and FIR smoothing."""
    n = len(x)
    spectrum = dft(x)
    low, high = parameters["bandpass"]
    notch, width = parameters["notch"]
    filtered = []
    notched = []
    kept = 0
    removed = 0
    for k, value in enumerate(spectrum):
        frequency_numerator = min(k, n - k) * sample_rate
        in_passband = low * n <= frequency_numerator <= high * n
        kept += in_passband
        filtered.append(value if in_passband else 0j)
        nearest = (2 * frequency_numerator + notch * n) // (2 * notch * n)
        is_notched = (nearest >= 1
                      and abs(frequency_numerator - nearest * notch * n) <= width * n)
        removed += is_notched
        notched.append(0j if is_notched else value)
    bandpassed = [value.real for value in idft(filtered)]
    notch_result = [value.real for value in idft(notched)]

    envelope_low, envelope_high = parameters["envelope_band"]
    analytic_spectrum = [0j] * n
    for k in range(1, (n - 1) // 2 + 1):
        if envelope_low * n <= k * sample_rate <= envelope_high * n:
            analytic_spectrum[k] = 2 * spectrum[k]
    analytic = idft(analytic_spectrum)
    envelope = [abs(value) for value in analytic]
    envelope_mean = sum(envelope) / n
    envelope_fft = dft([value - envelope_mean for value in envelope])
    modulation = [2 * abs(value) / n for value in envelope_fft]
    stop = ((envelope_high - envelope_low) * n) // (2 * sample_rate)
    envelope_bin = max(range(1, stop + 1),
                       key=lambda k: (modulation[k], -k))
    envelope_position, envelope_amplitude = interpolate(modulation, envelope_bin)

    instantaneous = []
    for i in range(1, n):
        delta = math.atan2(analytic[i].imag, analytic[i].real)
        delta -= math.atan2(analytic[i - 1].imag, analytic[i - 1].real)
        if delta <= -PI:
            delta += 2 * PI
        if delta > PI:
            delta -= 2 * PI
        instantaneous.append(delta * sample_rate / (2 * PI))
    frequency_mean = sum(instantaneous) / len(instantaneous)
    frequency_std = math.sqrt(
        sum((value - frequency_mean) ** 2 for value in instantaneous)
        / len(instantaneous)
    )

    taps = parameters["fir"]
    smoothed = convolution(y, taps)
    gain = sum(taps[j] * rot(2 * PI * parameters["fundamental"][0] * j / sample_rate)
               for j in range(len(taps)))
    fir_direct = [
        sum(y[j] * taps[i - j] for j in range(max(0, i - len(taps) + 1),
                                             min(n - 1, i) + 1))
        for i in range(n + len(taps) - 1)
    ]
    return {
        "bandpassed": bandpassed, "notched": notch_result,
        "smoothed": smoothed, "envelope": envelope,
        "bins_kept": kept, "bins_removed": removed,
        "bandpass_rms": rms(bandpassed),
        "notch_rms": rms(notch_result),
        "bandpass_ratio": sum(v * v for v in bandpassed) / sum(v * v for v in x),
        "fir_taps": len(taps), "dc_gain": sum(taps),
        "gain_at_fundamental_db": decibels(abs(gain)),
        "fir_rms": math.sqrt(sum(smoothed[i] ** 2 for i in range(n)) / n),
        "fir_error": max(abs(a - b) for a, b in zip(smoothed, fir_direct)),
        "envelope_band": (envelope_low, envelope_high),
        "envelope_mean": envelope_mean, "envelope_bin": envelope_bin,
        "envelope_frequency": envelope_position * sample_rate / n,
        "envelope_amplitude": envelope_amplitude,
        "envelope_depth": envelope_amplitude / envelope_mean,
        "instantaneous_mean": frequency_mean, "instantaneous_std": frequency_std,
    }


def estimate_pitch(amplitudes, bandpassed, parameters, sample_rate):
    """Estimate pitch by harmonic product spectrum, ACF and zero crossings."""
    main_length = parameters["main_length"]
    lower, upper = parameters["pitch_range"]
    half = main_length // 2
    lag_min = (sample_rate + upper - 1) // upper
    lag_max = sample_rate // lower
    hps_candidates = [
        k for k in range(1, half + 1)
        if lower * main_length <= k * sample_rate <= upper * main_length
        and 5 * k <= half
    ]
    hps_values = {
        k: sum(math.log(amplitudes[multiple * k]) for multiple in range(1, 6))
        for k in hps_candidates
    }
    hps_bin = max(hps_candidates, key=lambda k: (hps_values[k], -k))
    n = len(bandpassed)
    q = pow2(2 * n - 1)
    transformed = radix2(bandpassed + [0.0] * (q - n))
    correlation = radix2([complex(abs(v) ** 2) for v in transformed],
                         inverse=True)
    acf = [value.real for value in correlation]
    lag = max(range(lag_min, lag_max + 1), key=lambda k: (acf[k], -k))
    interpolated, strength_value = interpolate(acf, lag, logarithmic=False)
    crossings = sum(bandpassed[i - 1] < 0 <= bandpassed[i]
                    for i in range(1, n))
    return {
        "lag_min": lag_min, "lag_max": lag_max, "hps_bin": hps_bin,
        "hps_frequency": hps_bin * sample_rate / main_length,
        "acf_lag": lag, "acf_period": interpolated,
        "acf_frequency": sample_rate / interpolated,
        "acf_strength": strength_value / acf[0],
        "crossings": crossings,
        "crossing_frequency": crossings * sample_rate / n,
    }


def analyze_zoom(weighted, coherent_sum, parameters, sample_rate):
    """Evaluate chirp-z zoom amplitudes and interpolate their strongest peaks."""
    low, high, points = parameters["zoom"]
    step = (high - low) / (points - 1)
    spectrum = chirp_z(weighted, sample_rate, low, high, points)
    amplitudes = [2 * abs(value) / coherent_sum for value in spectrum]
    peaks = []
    for rank, j in enumerate(strongest_local_maxima(amplitudes, 3), 1):
        position, amplitude = interpolate(amplitudes, j)
        peaks.append({
            "rank": rank, "frequency": low + position * step,
            "amplitude": amplitude,
        })
    return {"low": low, "high": high, "points": points,
            "step": step, "peaks": peaks}


def choose_lag(sequence, limit):
    """Resolve correlation ties by shorter lag and then by negative sign."""
    size = len(sequence)
    lag = max(range(-limit, limit + 1),
              key=lambda ell: (sequence[ell % size], -abs(ell), -ell))
    neighborhood = [sequence[(lag + offset) % size] for offset in (-1, 0, 1)]
    position, _ = interpolate(neighborhood, 1, logarithmic=False)
    return lag, lag + position - 1


def analyze_correlation(x, y, max_lag, sample_rate):
    """Compare ordinary cross-correlation and phase-only GCC-PHAT."""
    n = len(x)
    q = pow2(2 * n - 1)
    fx = radix2(x + [0.0] * (q - n))
    fy = radix2(y + [0.0] * (q - n))
    cross = [fx[k].conjugate() * fy[k] for k in range(q)]
    raw = [value.real for value in radix2(cross, inverse=True)]
    phased = [value / abs(value) for value in cross]
    phat = [value.real for value in radix2(phased, inverse=True)]
    lag, refined = choose_lag(raw, max_lag)
    phat_lag, phat_refined = choose_lag(phat, max_lag)
    return {
        "lag": lag, "refined_lag": refined,
        "delay_ms": 1000 * refined / sample_rate,
        "coefficient": raw[lag % q] / math.sqrt(
            sum(v * v for v in x) * sum(v * v for v in y)),
        "phat_lag": phat_lag, "phat_refined": phat_refined,
        "phat_delay_ms": 1000 * phat_refined / sample_rate,
    }


def verify_transforms(weighted, transformed, peaks, filters, welch, spectrogram):
    """Evaluate all five numerical consistency checks with the given tolerance."""
    size = len(weighted)
    inverse = idft(transformed)
    inverse_error = max(abs(value - weighted[i]) for i, value in enumerate(inverse))
    time_energy = sum(value * value for value in weighted)
    frequency_energy = sum(abs(value) ** 2 for value in transformed) / size
    parseval_error = abs(time_energy - frequency_energy) / time_energy
    packing_error = max(welch["packing_error"], spectrogram["packing_error"])
    spot_error = 0.0
    for peak in peaks:
        k = peak["bin"]
        direct = sum(
            weighted[n] * rot(2 * PI * ((k * n) % size) / size)
            for n in range(size)
        )
        spot_error = max(spot_error, abs(direct - transformed[k]))
    tolerance = 1e-6
    return {
        "inverse_roundtrip": inverse_error <= tolerance,
        "parseval": parseval_error <= tolerance,
        "real_packing": packing_error <= tolerance,
        "fir_fft_vs_direct": filters["fir_error"] <= tolerance,
        "dft_spot_check": spot_error <= tolerance,
    }


def diagnosis(peaks, harmonics, filters, spectrogram):
    """Interpret the peaks as mechanical or electrical warning signatures."""
    amplitude_ratio = harmonics[1]["amplitude"] / harmonics[0]["amplitude"]
    looseness_count = sum(entry["level_db"] >= -30 for entry in harmonics[2:])
    mains_peak = next((peak for peak in peaks if peak["label"] == "mains"), None)
    electrical_level = None if mains_peak is None else mains_peak["level_db"]
    symptoms = {
        "misalignment": amplitude_ratio >= 0.5,
        "looseness": looseness_count >= 3,
        "bearing": filters["envelope_depth"] >= 0.2,
        "electrical": mains_peak is not None and electrical_level >= -20,
        "transient": bool(spectrogram["onsets"]),
    }
    findings = sum(symptoms.values())
    return {
        "symptoms": symptoms, "findings": findings,
        "status": "normal" if findings == 0 else "warning" if findings == 1 else "alarm",
        "amplitude_ratio": amplitude_ratio, "looseness_count": looseness_count,
        "electrical_level": electrical_level,
    }


def render_peaks(peaks, maximum, noise_floor, parameters, sample_rate):
    """Create the complete peak listing with four-place formatting."""
    length = parameters["main_length"]
    lines = [
        fields(length=length, window=parameters["main_window"],
               resolution=sample_rate / length,
               threshold_db=parameters["peak_threshold_db"]),
        fields(max_amplitude=maximum, noise_floor=noise_floor,
               noise_floor_db=decibels(noise_floor)),
        fields(peaks=len(peaks)),
    ]
    for peak in peaks:
        lines.append(
            str(peak["rank"]) + " " +
            fields(bin=peak["bin"], frequency=peak["frequency"],
                   refined=peak["refined"], amplitude=peak["amplitude"],
                   level_db=peak["level_db"], phase=peak["phase"],
                   bandwidth=peak["bandwidth"], snr_db=peak["snr_db"],
                   coherence=peak["coherence"], label=peak["label"])
        )
    return lines


def render_spectrogram(spectrogram, sample_rate):
    """Construct shades, per-frame tracks, onsets and the kurtosis maximum."""
    data = spectrogram
    length = data["length"]
    lines = [
        fields(frames=data["frames"], bins=length // 2 + 1,
               frame_length=length, hop=data["hop"],
               window=data["window"], band_db=data["band_db"],
               max_db=decibels(data["maximum"])),
    ]
    lines.extend(shade_lines(data["grid"], sample_rate, length, data["band_db"]))
    lines.append("track")
    for row in data["dominant"]:
        lines.append(fields(frame=row["frame"], time=row["time"],
                            frequency=row["frequency"],
                            level_db=row["level_db"]))
    lines.append(fields(onsets=len(data["onsets"]), threshold=data["onset_threshold"]))
    for frame in data["onsets"]:
        lines.append(fields(frame=frame, time=frame * data["hop"] / sample_rate,
                            flux=data["flux"][frame]))
    k = data["top_kurtosis"]
    lines.append("kurtosis " + fields(bin=k, frequency=k * sample_rate / length,
                                       value=data["kurtosis"][k]))
    return lines


def signal_report(lines, sample_rate, n, first, second):
    lines.extend([
        "[signal]",
        fields(sample_rate=sample_rate, samples=n, duration=n / sample_rate),
    ])
    for number, values in enumerate((first, second), 1):
        lines.append(fields(channel=number, **values))


def history_report(lines, history, loudest, parameters, sample_rate):
    block_length = parameters["block_length"]
    lines.extend(["[levels]", fields(block_length=block_length,
                                    blocks=len(history), loudest=loudest)])
    for row in history:
        lines.append(fields(block=row["number"],
                            time=row["number"] * block_length / sample_rate,
                            rms1=row["rms1"], rms2=row["rms2"],
                            peak1=row["peak1"]))


def window_report(lines, comparison):
    lines.append("[windows]")
    for item in comparison:
        lines.append(fields(
            name=item["name"], coherent_gain=item["coherent_gain"],
            enbw_bins=item["enbw_bins"], enbw_hz=item["enbw_hz"],
            scalloping_db=item["scalloping_db"],
            fundamental_bin=item["fundamental_bin"],
            bin_amplitude=item["bin_amplitude"],
            refined_amplitude=item["refined_amplitude"],
            floor_db=item["floor_db"],
        ))


def main_spectrum_report(lines, parameters, sample_rate, powers):
    main_length = parameters["main_length"]
    is_power_two = main_length & (main_length - 1) == 0
    lines.extend([
        "[main]",
        fields(length=main_length, window=parameters["main_window"],
               method="radix2" if is_power_two else "bluestein",
               transform_size=main_length if is_power_two else pow2(2 * main_length - 1),
               resolution=sample_rate / main_length),
        fields(total_power=powers["total_power"], centroid=powers["centroid"],
               spread=powers["spread"], rolloff=powers["rolloff"],
               flatness_db=powers["flatness_db"]),
    ])


def band_report(lines, bands, third_octaves):
    lines.append("[bands]")
    for lower, upper, power, percent in bands:
        lines.append(fields(range=f"{lower}-{upper}", power=power, percent=percent))
    lines.append("[third_octave]")
    for item in third_octaves:
        lines.append(fields(**item))


def harmonic_report(lines, harmonics, powers, thd, parameters):
    nominal, width = parameters["fundamental"]
    lines.extend(["[harmonics]", fields(fundamental=nominal, search=width)])
    for harmonic in harmonics:
        lines.append(fields(h=harmonic["number"], target=harmonic["target"],
                            bin=harmonic["bin"], refined=harmonic["frequency"],
                            amplitude=harmonic["amplitude"],
                            level_db=harmonic["level_db"]))
    lines.append(fields(thd_percent=thd["thd_percent"], thd_db=thd["thd_db"]))
    lines.append(fields(thdn_percent=powers["thdn_percent"],
                        thdn_db=powers["thdn_db"]))


def pitch_report(lines, pitch, parameters):
    low, high = parameters["pitch_range"]
    lines.extend([
        "[pitch]",
        fields(range=f"{low}-{high}",
               lags=f"{pitch['lag_min']}-{pitch['lag_max']}"),
        "hps " + fields(bin=pitch["hps_bin"], order=5,
                        frequency=pitch["hps_frequency"]),
        "autocorrelation " + fields(lag=pitch["acf_lag"],
                                    period=pitch["acf_period"],
                                    frequency=pitch["acf_frequency"],
                                    strength=pitch["acf_strength"]),
        "zero_crossing " + fields(count=pitch["crossings"],
                                  frequency=pitch["crossing_frequency"]),
    ])


def zoom_report(lines, zoom):
    lines.extend(["[zoom]", fields(
        band=f"{zoom['low']}-{zoom['high']}",
        points=zoom["points"], step=zoom["step"],
    )])
    for item in zoom["peaks"]:
        lines.append(fields(peak=item["rank"], frequency=item["frequency"],
                            amplitude=item["amplitude"]))


def welch_report(lines, welch, sample_rate):
    lines.extend([
        "[welch]",
        fields(segment_length=welch["length"], segments=welch["segments"],
               window=welch["window"], resolution=sample_rate / welch["length"]),
        fields(integrated_power=welch["integrated_power"], variance=welch["variance"],
               ratio=welch["ratio"]),
    ])
    for item in welch["peaks"]:
        lines.append(fields(peak=item["rank"], frequency=item["frequency"],
                            psd_db=item["psd_db"], coherence=item["coherence"],
                            gain=item["gain"], phase=item["phase"]))


def filter_report(lines, filters, parameters):
    lower, upper = parameters["bandpass"]
    notch_frequency, notch_width = parameters["notch"]
    envelope_low, envelope_high = filters["envelope_band"]
    lines.extend([
        "[filter]",
        fields(bandpass=f"{lower}-{upper}",
               bins_kept=filters["bins_kept"], rms=filters["bandpass_rms"],
               energy_ratio=filters["bandpass_ratio"]),
        fields(notch=notch_frequency, width=notch_width,
               bins_removed=filters["bins_removed"], rms=filters["notch_rms"]),
        fields(fir_taps=filters["fir_taps"], dc_gain=filters["dc_gain"],
               gain_at_fundamental_db=filters["gain_at_fundamental_db"],
               rms=filters["fir_rms"]),
        "[envelope]",
        fields(band=f"{envelope_low}-{envelope_high}",
               mean=filters["envelope_mean"], bin=filters["envelope_bin"],
               frequency=filters["envelope_frequency"],
               amplitude=filters["envelope_amplitude"],
               depth=filters["envelope_depth"]),
        "instantaneous_frequency " +
        fields(mean=filters["instantaneous_mean"], std=filters["instantaneous_std"]),
    ])


def correlation_report(lines, correlation, max_lag):
    lines.extend([
        "[correlation]",
        fields(max_lag=max_lag, lag=correlation["lag"],
               refined_lag=correlation["refined_lag"],
               delay_ms=correlation["delay_ms"],
               coefficient=correlation["coefficient"]),
        fields(phat_lag=correlation["phat_lag"],
               refined_lag=correlation["phat_refined"],
               delay_ms=correlation["phat_delay_ms"]),
    ])


def checks_report(lines, checks, welch, spectrogram, peaks):
    lines.append("[checks]")
    for name in ("inverse_roundtrip", "parseval", "real_packing",
                 "fir_fft_vs_direct", "dft_spot_check"):
        status = "ok" if checks[name] else "failed"
        if name == "real_packing":
            transforms = 2 * welch["segments"] + spectrogram["frames"]
            lines.append(fields(real_packing=status, transforms=transforms))
        elif name == "dft_spot_check":
            lines.append(fields(dft_spot_check=status, bins=len(peaks)))
        else:
            lines.append(fields(**{name: status}))


def diagnosis_report(lines, diagnosis_data, spectrogram, filters):
    symptoms = diagnosis_data["symptoms"]
    electrical_level = diagnosis_data["electrical_level"]
    lines.extend([
        "[diagnosis]",
        fields(misalignment="yes" if symptoms["misalignment"] else "no",
               ratio=diagnosis_data["amplitude_ratio"]),
        fields(looseness="yes" if symptoms["looseness"] else "no",
               harmonics=diagnosis_data["looseness_count"]),
        fields(bearing="yes" if symptoms["bearing"] else "no",
               depth=filters["envelope_depth"]),
        fields(electrical="yes" if symptoms["electrical"] else "no",
               level_db="none" if electrical_level is None else real(electrical_level)),
        fields(transient="yes" if symptoms["transient"] else "no",
               onsets=len(spectrogram["onsets"])),
        fields(status=diagnosis_data["status"],
               findings=diagnosis_data["findings"]),
    ])


def render_report(sample_rate, x, first_stats, second_stats, history, loudest,
                  comparison, powers, bands, octaves, harmonics, thd,
                  pitch, zoom, welch, spectrogram, filters, correlation,
                  checks, diagnosis_data, peaks, parameters):
    """Build all required report sections in the specification's exact order."""
    lines = []
    signal_report(lines, sample_rate, len(x), first_stats, second_stats)
    history_report(lines, history, loudest, parameters, sample_rate)
    window_report(lines, comparison)
    main_spectrum_report(lines, parameters, sample_rate, powers)
    band_report(lines, bands, octaves)
    harmonic_report(lines, harmonics, powers, thd, parameters)
    pitch_report(lines, pitch, parameters)
    zoom_report(lines, zoom)
    welch_report(lines, welch, sample_rate)
    filter_report(lines, filters, parameters)
    correlation_report(lines, correlation, parameters["max_lag"])
    checks_report(lines, checks, welch, spectrogram, peaks)
    diagnosis_report(lines, diagnosis_data, spectrogram, filters)
    return lines


def main():
    """Run the complete pipeline and write six files, without console output."""
    sample_rate, raw_x, raw_y = read_signal()
    parameters = read_params()
    n = len(raw_x)
    main_length = parameters["main_length"]
    x, stats_x = detrend(raw_x, sample_rate)
    y, stats_y = detrend(raw_y, sample_rate)
    history, loudest = level_history(x, y, parameters["block_length"])

    weighted, transformed, amplitudes = amplitude_spectrum(
        x, parameters["main_window"], main_length
    )
    main_window = window(parameters["main_window"], main_length)
    calibration = figures(main_window, sample_rate)

    welch = analyze_welch(x, y, parameters, sample_rate)
    peaks, maximum, noise_floor = main_peaks(
        amplitudes, transformed, parameters, sample_rate, welch
    )
    harmonics, thd = harmonic_analysis(amplitudes, parameters, sample_rate)
    bin_power, powers = power_analysis(
        amplitudes, sample_rate, parameters,
        harmonics, calibration["enbw_bins"],
    )
    bands, octaves = calculate_bands(
        bin_power, parameters, sample_rate,
        calibration["enbw_bins"], powers["total_power"],
    )
    comparison = compare_windows(x, parameters, sample_rate)

    spectrogram = analyze_spectrogram(x, parameters, sample_rate)
    filters = filtered_waveforms(x, y, parameters, sample_rate)
    pitch = estimate_pitch(amplitudes, filters["bandpassed"], parameters, sample_rate)
    zoom = analyze_zoom(weighted, calibration["s1"], parameters, sample_rate)
    correlation = analyze_correlation(
        x, y, parameters["max_lag"], sample_rate
    )
    checks = verify_transforms(
        weighted, transformed, peaks, filters, welch, spectrogram
    )
    diagnosis_data = diagnosis(peaks, harmonics, filters, spectrogram)

    half = main_length // 2
    write_csv(
        "spectrum.csv", "frequency,amplitude",
        [(k * sample_rate / main_length, amplitudes[k]) for k in range(half + 1)],
    )
    write_lines(
        "peaks.txt",
        render_peaks(peaks, maximum, noise_floor, parameters, sample_rate),
    )
    length = welch["length"]
    write_csv(
        "welch_psd.csv", "frequency,psd_db",
        [(k * sample_rate / length, decibels(value, 10))
         for k, value in enumerate(welch["psd"])],
    )
    write_lines(
        "spectrogram.txt", render_spectrogram(spectrogram, sample_rate)
    )
    write_csv(
        "filtered.csv", "index,bandpass,notched,smoothed,envelope",
        [(i, filters["bandpassed"][i], filters["notched"][i],
          filters["smoothed"][i], filters["envelope"][i]) for i in range(n)],
    )
    report_lines = render_report(
        sample_rate, x, stats_x, stats_y, history, loudest,
        comparison, powers, bands, octaves, harmonics, thd,
        pitch, zoom, welch, spectrogram, filters, correlation,
        checks, diagnosis_data, peaks, parameters,
    )
    write_lines("report.txt", report_lines)


if __name__ == "__main__":
    main()
