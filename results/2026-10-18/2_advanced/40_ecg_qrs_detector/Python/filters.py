"""Five Pan-Tompkins signal processing stages with floor division."""


def filter_ecg(samples):
    """Return lowpass, bandpass, derivative, squared, integrated integer arrays."""
    n = len(samples)
    c = [0] * n
    low = [0] * n
    s = [0] * n
    band = [0] * n
    derivative = [0] * n
    squared = [0] * n
    integrated = [0] * n
    window_sum = 0

    def at(values, index):
        return values[index] if index >= 0 else 0

    for i in range(n):
        c[i] = (2 * at(c, i - 1) - at(c, i - 2)
                + samples[i] - 2 * at(samples, i - 6)
                + at(samples, i - 12))
        low[i] = c[i] // 32
        s[i] = at(s, i - 1) + low[i] - at(low, i - 32)
        band[i] = at(low, i - 16) - s[i] // 32
        derivative[i] = (
            2 * band[i] + at(band, i - 1)
            - at(band, i - 3) - 2 * at(band, i - 4)
        ) // 8
        squared[i] = derivative[i] * derivative[i]
        window_sum += squared[i]
        if i >= 30:
            window_sum -= squared[i - 30]
        integrated[i] = window_sum // 30
    return {
        "lowpass": low, "bandpass": band, "derivative": derivative,
        "squared": squared, "integrated": integrated,
    }
