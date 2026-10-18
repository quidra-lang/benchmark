from signals import MAX_SAMPLE, peak, rdiv


UNITY = 32768


def envelope(samples, attack, release):
    levels = []
    level = 0
    for x in samples:
        magnitude = min(abs(x), MAX_SAMPLE)
        coefficient = attack if magnitude > level else release
        level += rdiv((magnitude - level) * coefficient, UNITY)
        levels.append(level)
    return levels


def normalize(samples, target):
    source_peak = peak(samples)
    if source_peak == 0:
        return list(samples), source_peak
    return [rdiv(x * target, source_peak) for x in samples], source_peak


def gate(samples, threshold, hold):
    output = []
    muted = 0
    last_loud = None
    for i, x in enumerate(samples):
        if abs(x) >= threshold:
            last_loud = i
        if last_loud is not None and i - last_loud <= hold:
            output.append(x)
        else:
            output.append(0)
            muted += 1
    return output, muted


def compress(samples, threshold, ratio_num, ratio_den, attack, release):
    levels = envelope(samples, attack, release)
    output = []
    gains = []
    gain = UNITY
    for x, level in zip(samples, levels):
        if level > threshold:
            limited = threshold + rdiv((level - threshold) * ratio_den, ratio_num)
            target = rdiv(limited * UNITY, level)
        else:
            target = UNITY
        if target < gain:
            gain = target
        else:
            gain += rdiv((target - gain) * release, UNITY)
        gains.append(gain)
        output.append(rdiv(x * gain, UNITY))
    reduced = sum(1 for value in gains if value < UNITY)
    return output, min(gains), reduced
