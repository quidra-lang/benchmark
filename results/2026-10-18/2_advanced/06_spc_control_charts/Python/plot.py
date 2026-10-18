from math import floor


WIDTH = 61
LAST = 60
MIDDLE = 30


def new_band():
    return ["."] * WIDTH


def place(band, position, symbol):
    band[min(LAST, max(0, position))] = symbol


def framed_band(center):
    band = new_band()
    place(band, 0, ":")
    place(band, LAST, ":")
    place(band, center, "|")
    return band


def limits_band(limits, value, signalled):
    span = limits.ucl - limits.lcl
    band = framed_band(floor(60 * ((limits.cl - limits.lcl) / span) + 0.5))
    place(band, floor(60 * ((value - limits.lcl) / span) + 0.5), "*" if signalled else "o")
    return "".join(band)


def cusum_band(upper, lower, threshold, upper_signal, lower_signal):
    band = framed_band(MIDDLE)
    if lower > 0:
        offset = min(30, floor(30 * (lower / threshold) + 0.5))
        place(band, MIDDLE - offset, "*" if lower_signal else "-")
    if upper > 0:
        offset = min(30, floor(30 * (upper / threshold) + 0.5))
        place(band, MIDDLE + offset, "*" if upper_signal else "+")
    return "".join(band)


def width_band(scale, width, value, center, signalled):
    band = new_band()
    edge = min(30, floor(30 * (width / scale) + 0.5))
    place(band, MIDDLE, "|")
    place(band, MIDDLE - edge, ":")
    place(band, MIDDLE + edge, ":")
    deviation = (value - center) / scale
    place(band, MIDDLE + floor(30 * deviation + 0.5), "*" if signalled else "o")
    return "".join(band)


def standard_band(z, ok):
    band = framed_band(MIDDLE)
    place(band, MIDDLE + floor(10 * z + 0.5), "o" if ok else "*")
    return "".join(band)
