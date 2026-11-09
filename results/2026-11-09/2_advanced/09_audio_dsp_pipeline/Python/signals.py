MIN_SAMPLE = -32768
MAX_SAMPLE = 32767
VALUES_PER_LINE = 16
MINSTD_MULTIPLIER = 48271
MINSTD_MODULUS = 2147483647


class Signal:
    def __init__(self, name, rate, samples, origin="input", ingredients=()):
        self.name = name
        self.rate = rate
        self.samples = samples
        self.origin = origin
        self.ingredients = list(ingredients)


class ClipCounter:
    def __init__(self):
        self.count = 0

    def saturate(self, value):
        limited = max(MIN_SAMPLE, min(MAX_SAMPLE, value))
        if limited != value:
            self.count += 1
        return limited


def rdiv(numerator, denominator):
    return (2 * numerator + denominator) // (2 * denominator)


def peak(samples):
    return max(abs(x) for x in samples)


def read_signals(path):
    with open(path) as file:
        lines = file.read().splitlines()
    signals = []
    index = 0
    while index < len(lines):
        header = lines[index].split(" ")
        count = int(header[3])
        index += 1
        samples = []
        while len(samples) < count:
            samples.extend(int(value) for value in lines[index].split(" "))
            index += 1
        signals.append(Signal(header[1], int(header[2]), samples))
    return signals


def format_signal(signal):
    samples = signal.samples
    lines = [f"SIGNAL {signal.name} {signal.rate} {len(samples)}"]
    for start in range(0, len(samples), VALUES_PER_LINE):
        lines.append(" ".join(str(x) for x in samples[start:start + VALUES_PER_LINE]))
    return lines


def impulse(count, position, amplitude):
    samples = [0] * count
    samples[position] = amplitude
    return samples


def step(count, position, amplitude):
    return [amplitude if i >= position else 0 for i in range(count)]


def noise(count, seed):
    samples = []
    state = seed
    for _ in range(count):
        state = MINSTD_MULTIPLIER * state % MINSTD_MODULUS
        samples.append(state % 65536 - 32768)
    return samples
