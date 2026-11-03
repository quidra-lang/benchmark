"""Directly implemented FFT variants, real packing, convolution and chirp-z."""

import math


PI = 3.141592653589793


def pow2(value):
    result = 1
    while result < value:
        result *= 2
    return result


def rot(angle):
    return complex(math.cos(angle), -math.sin(angle))


def radix2(data, inverse=False):
    """Iterative decimation-in-time radix-2 transform; returns a new list."""
    n = len(data)
    if n < 1 or n & (n - 1):
        raise ValueError("radix2 requires a power-of-two length")
    values = [complex(value) for value in data]
    bits = n.bit_length() - 1
    for i in range(1, n):
        reversed_index = 0
        t = i
        for _ in range(bits):
            reversed_index = reversed_index * 2 + t % 2
            t //= 2
        if i < reversed_index:
            values[i], values[reversed_index] = values[reversed_index], values[i]
    half = n // 2
    twiddle = [rot(2 * PI * k / n) for k in range(half)]
    if inverse:
        twiddle = [factor.conjugate() for factor in twiddle]
    size = 2
    while size <= n:
        stride = n // size
        half_size = size // 2
        for start in range(0, n, size):
            for j in range(half_size):
                t = twiddle[j * stride] * values[start + j + half_size]
                u = values[start + j]
                values[start + j] = u + t
                values[start + j + half_size] = u - t
        size *= 2
    if inverse:
        values = [value / n for value in values]
    return values


def bluestein(values):
    """Forward DFT of arbitrary positive length using chirp convolution."""
    m = len(values)
    q = pow2(2 * m - 1)
    chirp = [rot(PI * (n * n % (2 * m)) / m) for n in range(m)]
    a = [0j] * q
    b = [0j] * q
    for n in range(m):
        a[n] = values[n] * chirp[n]
        b[n] = chirp[n].conjugate()
        if n:
            b[q - n] = b[n]
    af = radix2(a)
    bf = radix2(b)
    convolution = radix2([af[k] * bf[k] for k in range(q)], inverse=True)
    return [chirp[k] * convolution[k] for k in range(m)]


def dft(values):
    if not values:
        raise ValueError("DFT of empty sequence")
    if len(values) & (len(values) - 1):
        return bluestein(values)
    return radix2(values)


def idft(values):
    if not values:
        raise ValueError("IDFT of empty sequence")
    if len(values) & (len(values) - 1):
        result = bluestein([complex(v).conjugate() for v in values])
        return [v.conjugate() / len(values) for v in result]
    return radix2(values, inverse=True)


def packed_real(values):
    """Nonredundant bins of a real DFT via one half-length complex FFT."""
    n = len(values)
    if n < 4 or n & (n - 1):
        raise ValueError("packed real DFT requires power of two >= 4")
    half = n // 2
    z = [complex(values[2 * i], values[2 * i + 1]) for i in range(half)]
    transformed = radix2(z)
    result = []
    for k in range(half + 1):
        za = transformed[k % half]
        zb = transformed[(half - k) % half].conjugate()
        even = (za + zb) / 2
        odd = (za - zb) / (2j)
        result.append(even + rot(2 * PI * k / n) * odd)
    return result


def convolution(a, b):
    """Real linear convolution, zero-padded and evaluated in the FFT domain."""
    n = len(a) + len(b) - 1
    q = pow2(n)
    af = radix2(list(a) + [0] * (q - len(a)))
    bf = radix2(list(b) + [0] * (q - len(b)))
    result = radix2([af[k] * bf[k] for k in range(q)], inverse=True)
    return [value.real for value in result[:n]]


def chirp_z(windowed, sample_rate, low, high, points):
    """Complex spectrum on a linearly spaced non-DFT frequency grid."""
    m = len(windowed)
    step = (high - low) / (points - 1)
    q = pow2(m + points - 1)
    a = [0j] * q
    b = [0j] * q
    for n, sample in enumerate(windowed):
        a[n] = (sample * rot(2 * PI * low * n / sample_rate)
                * rot(PI * step * n * n / sample_rate))
    for offset in range(-(m - 1), points):
        b[offset % q] = rot(PI * step * offset * offset / sample_rate).conjugate()
    af = radix2(a)
    bf = radix2(b)
    g = radix2([af[k] * bf[k] for k in range(q)], inverse=True)
    return [rot(PI * step * j * j / sample_rate) * g[j] for j in range(points)]
