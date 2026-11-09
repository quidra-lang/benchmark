from signals import ClipCounter, rdiv


Q14_ONE = 16384


def fir(samples, divisor, taps):
    counter = ClipCounter()
    output = []
    for n in range(len(samples)):
        total = 0
        for k in range(min(len(taps), n + 1)):
            total += taps[k] * samples[n - k]
        output.append(counter.saturate(total // divisor))
    return output, counter.count


def biquad(samples, sections):
    counter = ClipCounter()
    signal = samples
    for b0, b1, b2, a1, a2 in sections:
        output = []
        u1 = u2 = v1 = v2 = 0
        for u in signal:
            v = counter.saturate((b0 * u + b1 * u1 + b2 * u2 - a1 * v1 - a2 * v2) // Q14_ONE)
            output.append(v)
            u1, u2 = u, u1
            v1, v2 = v, v1
        signal = output
    return signal, counter.count


def moving_average(samples, width):
    output = []
    total = 0
    for n, x in enumerate(samples):
        total += x
        if n >= width:
            total -= samples[n - width]
        output.append(rdiv(total, width))
    return output


def dc_block(samples, num, den):
    counter = ClipCounter()
    output = []
    previous_input = 0
    previous_output = 0
    for x in samples:
        previous_output = counter.saturate(x - previous_input + rdiv(num * previous_output, den))
        previous_input = x
        output.append(previous_output)
    return output, counter.count
