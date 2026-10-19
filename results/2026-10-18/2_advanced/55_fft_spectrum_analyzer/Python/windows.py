"""Periodic cosine windows and their calibration figures."""

import math

from fft import PI, rot


COEFFICIENTS = {
    "rectangular": (1.0,),
    "hann": (0.5, 0.5),
    "hamming": (0.54, 0.46),
    "blackman": (0.42, 0.5, 0.08),
    "flattop": (0.21557895, 0.41663158, 0.277263158, 0.083578947,
                0.006947368),
}
WINDOW_ORDER = tuple(COEFFICIENTS)


def window(name, length):
    coefficients = COEFFICIENTS[name]
    return [
        sum((-1) ** j * weight * math.cos(2 * PI * j * n / length)
            for j, weight in enumerate(coefficients))
        for n in range(length)
    ]


def figures(values, sample_rate):
    length = len(values)
    s1 = sum(values)
    s2 = sum(value * value for value in values)
    magnitude = abs(sum(values[n] * rot(PI * n / length)
                        for n in range(length)))
    enbw = length * s2 / (s1 * s1)
    return {
        "s1": s1,
        "s2": s2,
        "coherent_gain": s1 / length,
        "enbw_bins": enbw,
        "enbw_hz": enbw * sample_rate / length,
        "scalloping_db": -20 * math.log10(magnitude / s1),
    }
