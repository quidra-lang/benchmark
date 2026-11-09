from signals import ClipCounter, rdiv


def gain(samples, num, den):
    counter = ClipCounter()
    output = [counter.saturate(rdiv(x * num, den)) for x in samples]
    return output, counter.count


def mix(tracks, weights, den):
    counter = ClipCounter()
    output = []
    for i in range(max(len(track) for track in tracks)):
        total = 0
        for track, weight in zip(tracks, weights):
            if i < len(track):
                total += weight * track[i]
        output.append(counter.saturate(rdiv(total, den)))
    return output, counter.count


def delay(samples, count):
    return [0] * count + samples


def echo(samples, delay_length, num, den, tail):
    output = samples + [0] * tail
    counter = ClipCounter()
    for i in range(delay_length, len(output)):
        output[i] = counter.saturate(output[i] + rdiv(num * output[i - delay_length], den))
    return output, counter.count


def resampled_length(length, old_rate, new_rate):
    return (length - 1) * new_rate // old_rate + 1


def resample(samples, old_rate, new_rate):
    output = []
    for j in range(resampled_length(len(samples), old_rate, new_rate)):
        position, fraction = divmod(j * old_rate, new_rate)
        value = samples[position]
        if fraction > 0:
            value += rdiv((samples[position + 1] - value) * fraction, new_rate)
        output.append(value)
    return output


def fade(samples, fade_in, fade_out):
    length = len(samples)
    output = list(samples)
    for i in range(fade_in):
        output[i] = rdiv(output[i] * i, fade_in)
    for i in range(length - fade_out, length):
        output[i] = rdiv(output[i] * (length - 1 - i), fade_out)
    return output
