"""Amplitude/PSD spectra, real-packed windows, interpolation and median."""

import math

from fft import dft, packed_real, radix2
from windows import window


def median(values):
    ordered = sorted(values)
    size = len(ordered)
    if size % 2:
        return ordered[size // 2]
    return (ordered[size // 2 - 1] + ordered[size // 2]) / 2


def local_maximum(values, index):
    return (0 < index < len(values) - 1
            and values[index] > values[index - 1]
            and values[index] > values[index + 1])


def interpolate(values, index, logarithmic=True):
    """Parabolic interpolation of the log amplitudes or linear values."""
    if not local_maximum(values, index):
        return float(index), values[index]
    if logarithmic:
        left, middle, right = (math.log(values[index + j]) for j in (-1, 0, 1))
    else:
        left, middle, right = (values[index + j] for j in (-1, 0, 1))
    delta = (left - right) / (2 * (left - 2 * middle + right))
    fitted = middle - (left - right) * delta / 4
    return index + delta, math.exp(fitted) if logarithmic else fitted


def amplitude_spectrum(signal, name, length):
    weights = window(name, length)
    weighted = [signal[i] * weights[i] for i in range(length)]
    transformed = dft(weighted)
    s1 = sum(weights)
    magnitudes = []
    for k in range(length // 2 + 1):
        factor = 1 if k == 0 or 2 * k == length else 2
        magnitudes.append(factor * abs(transformed[k]) / s1)
    return weighted, transformed, magnitudes


def _packed_and_error(samples):
    packed = packed_real(samples)
    reference = radix2(samples)
    error = max(abs(packed[k] - reference[k])
                for k in range(len(samples) // 2 + 1))
    return packed, error


def welch_spectra(x, y, sample_rate, length, window_name):
    weights = window(window_name, length)
    energy = sum(weight * weight for weight in weights)
    step = length // 2
    segments = (len(x) - length) // step + 1
    count = length // 2 + 1
    pxx = [0.0] * count
    pyy = [0.0] * count
    pxy = [0j] * count
    packing_error = 0.0
    for block in range(segments):
        start = block * step
        values_x = [x[start + i] * weights[i] for i in range(length)]
        values_y = [y[start + i] * weights[i] for i in range(length)]
        x_fft, ex = _packed_and_error(values_x)
        y_fft, ey = _packed_and_error(values_y)
        packing_error = max(packing_error, ex, ey)
        for k in range(count):
            pxx[k] += abs(x_fft[k]) ** 2
            pyy[k] += abs(y_fft[k]) ** 2
            pxy[k] += x_fft[k].conjugate() * y_fft[k]
    psd, coherence, transfer = [], [], []
    for k in range(count):
        factor = 1 if k == 0 or k == length // 2 else 2
        psd.append(factor * pxx[k] / (segments * sample_rate * energy))
        coherence.append(abs(pxy[k]) ** 2 / (pxx[k] * pyy[k]))
        transfer.append(pxy[k] / pxx[k])
    return {
        "segments": segments, "psd": psd, "coherence": coherence,
        "transfer": transfer, "packing_error": packing_error,
    }


def spectrogram_magnitudes(signal, frame_length, hop, window_name):
    weights = window(window_name, frame_length)
    frames = (len(signal) - frame_length) // hop + 1
    grid = []
    maximum_error = 0.0
    for frame in range(frames):
        start = frame * hop
        samples = [signal[start + i] * weights[i] for i in range(frame_length)]
        transformed, error = _packed_and_error(samples)
        grid.append([abs(value) for value in transformed])
        maximum_error = max(maximum_error, error)
    return grid, maximum_error
