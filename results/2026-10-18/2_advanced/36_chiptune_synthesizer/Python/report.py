from math import isqrt
import zlib


SAMPLES_PER_LINE = 32


def hex_lines(samples):
    return [
        "".join(f"{sample:02X}" for sample in samples[start:start + SAMPLES_PER_LINE])
        for start in range(0, len(samples), SAMPLES_PER_LINE)
    ]


def adler32_text(values):
    return f"{zlib.adler32(bytes(values)):08X}"


def peak(values, center):
    return max((abs(value - center) for value in values), default=0)


def root_mean_square(values, center):
    return isqrt(sum((value - center) ** 2 for value in values) // len(values))


def zero_crossings(samples):
    return sum(
        (previous < 128) != (current < 128)
        for previous, current in zip(samples, samples[1:])
    )
