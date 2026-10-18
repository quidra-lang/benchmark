MODULUS = 2147483647
LANES = ((1000003, 11), (1500007, 23), (2750159, 37), (4194301, 53))
SHORT_LENGTH = 8


def digest(text):
    parts = []
    for base, initial in LANES:
        value = initial
        for character in text:
            value = (value * base + ord(character)) % MODULUS
        for extra in (len(text), 0, 0):
            value = (value * base + extra) % MODULUS
        parts.append(f"{value:08x}")
    return "".join(parts)


def merkle_root(hashes):
    level = list(hashes)
    while len(level) > 1:
        if len(level) % 2 == 1:
            level.append(level[-1])
        level = [digest(level[i] + level[i + 1]) for i in range(0, len(level), 2)]
    return level[0]


def short(value):
    return value[:SHORT_LENGTH]
