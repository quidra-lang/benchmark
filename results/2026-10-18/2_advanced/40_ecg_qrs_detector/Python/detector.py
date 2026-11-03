"""Integrated ECG peak detection, R-wave measurement, and QRS widths."""


def find_peaks(signals):
    integrated = signals["integrated"]
    band = signals["bandpass"]
    derivative = signals["derivative"]
    n = len(integrated)
    peaks = []
    for time, value in enumerate(integrated):
        if value <= 0:
            continue
        if any(integrated[j] >= value
               for j in range(max(0, time - 20), time)):
            continue
        if any(integrated[j] > value
               for j in range(time + 1, min(n, time + 21))):
            continue
        first_r = max(0, time - 30)
        r = max(range(first_r, time + 1), key=lambda j: (abs(band[j]), -j))
        slope = max(abs(derivative[j])
                    for j in range(max(0, time - 29), time + 1))
        peaks.append({
            "time": time, "r": r,
            "peak_i": value, "peak_f": abs(band[r]),
            "slope": slope,
            "thr_i": None, "thr_f": None, "class": None,
        })
    return peaks


def initial_levels(signals):
    integrated = signals["integrated"][:400]
    band = [abs(value) for value in signals["bandpass"][:400]]
    return {
        "spki": max(integrated) // 3,
        "npki": sum(integrated) // 800,
        "spkf": max(band) // 3,
        "npkf": sum(band) // 800,
    }


def thresholds(levels):
    thi1 = levels["npki"] + (levels["spki"] - levels["npki"]) // 4
    thf1 = levels["npkf"] + (levels["spkf"] - levels["npkf"]) // 4
    return {
        "thi1": thi1, "thi2": thi1 // 2,
        "thf1": thf1, "thf2": thf1 // 2,
    }


def width_ms(band, r):
    peak = abs(band[r])
    samples = [
        j for j in range(max(0, r - 25), min(len(band), r + 26))
        if 4 * abs(band[j]) >= peak
    ]
    return 5 * (samples[-1] - samples[0] + 1)
