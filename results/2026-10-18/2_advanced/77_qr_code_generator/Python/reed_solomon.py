"""QR Reed–Solomon encoding and bounded-distance correction over GF(256)."""

from functools import cache


EXP = [1] * 255
LOG = [0] * 256
for exponent in range(1, 255):
    doubled = EXP[exponent - 1] * 2
    EXP[exponent] = doubled ^ 0x11D if doubled >= 256 else doubled
for exponent, element in enumerate(EXP):
    LOG[element] = exponent


def multiply(left, right):
    if left == 0 or right == 0:
        return 0
    return EXP[(LOG[left] + LOG[right]) % 255]


def divide(numerator, denominator):
    if numerator == 0:
        return 0
    return EXP[(LOG[numerator] - LOG[denominator] + 255) % 255]


@cache
def generator(degree):
    coefficients = [1]
    for exponent in range(degree):
        product = [0] * (len(coefficients) + 1)
        for index, coefficient in enumerate(coefficients):
            product[index] ^= coefficient
            product[index + 1] ^= multiply(coefficient, EXP[exponent])
        coefficients = product
    return tuple(coefficients)


def parity(data, degree):
    polynomial = generator(degree)
    remainder = list(data) + [0] * degree
    for index in range(len(data)):
        leading = remainder[index]
        if leading:
            for offset, coefficient in enumerate(polynomial):
                remainder[index + offset] ^= multiply(leading, coefficient)
    return remainder[-degree:]


def syndromes(codewords, degree):
    values = []
    for exponent in range(degree):
        value = 0
        for codeword in codewords:
            value = multiply(value, EXP[exponent]) ^ codeword
        values.append(value)
    return values


def evaluate(coefficients, argument):
    """Evaluate coefficients stored in increasing degree order."""
    value = 0
    for coefficient in reversed(coefficients):
        value = multiply(value, argument) ^ coefficient
    return value


def correct(received, degree):
    original_syndromes = syndromes(received, degree)
    if not any(original_syndromes):
        return original_syndromes, list(received), []

    locator = [1] + [0] * degree
    previous = [1] + [0] * degree
    length = 0
    shift = 1
    beta = 1
    for step in range(degree):
        discrepancy = original_syndromes[step]
        for index in range(1, length + 1):
            discrepancy ^= multiply(locator[index], original_syndromes[step - index])
        if discrepancy == 0:
            shift += 1
            continue
        saved = locator[:]
        multiplier = divide(discrepancy, beta)
        for index in range(degree + 1 - shift):
            locator[index + shift] ^= multiply(multiplier, previous[index])
        if 2 * length <= step:
            length = step + 1 - length
            previous = saved
            beta = discrepancy
            shift = 1
        else:
            shift += 1
    if length > degree // 2:
        return original_syndromes, None, []

    locator = locator[:length + 1]
    positions = []
    count = len(received)
    for index in range(count):
        inverse = EXP[(255 - (count - 1 - index)) % 255]
        if evaluate(locator, inverse) == 0:
            positions.append(index)
    if len(positions) != length:
        return original_syndromes, None, []

    omega = [0] * degree
    for index, syndrome in enumerate(original_syndromes):
        for offset in range(min(length, degree - 1 - index) + 1):
            omega[index + offset] ^= multiply(syndrome, locator[offset])
    derivative = [0] * length
    for exponent in range(1, length + 1, 2):
        derivative[exponent - 1] = locator[exponent]
    corrected = list(received)
    for index in positions:
        location = EXP[(count - 1 - index) % 255]
        inverse = EXP[(255 - (count - 1 - index)) % 255]
        denominator = evaluate(derivative, inverse)
        if denominator == 0:
            return original_syndromes, None, []
        magnitude = multiply(location, divide(evaluate(omega, inverse), denominator))
        corrected[index] ^= magnitude
    if any(syndromes(corrected, degree)):
        return original_syndromes, None, []
    changed = [index for index in positions if corrected[index] != received[index]]
    return original_syndromes, corrected, changed
