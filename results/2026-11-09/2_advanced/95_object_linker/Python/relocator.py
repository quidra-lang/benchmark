TYPES = ("ABS32", "REL32", "ABS16", "HI16", "LO16", "GPREL16", "CALL24")
WIDTHS = {"ABS32": 4, "REL32": 4, "ABS16": 2, "HI16": 2, "LO16": 2, "GPREL16": 2, "CALL24": 3}
RANGES = {
    "ABS32": (-2**31, 2**32),
    "REL32": (-2**31, 2**31),
    "ABS16": (-2**15, 2**16),
    "HI16": (-2**31, 2**32),
    "GPREL16": (-2**15, 2**15),
    "CALL24": (-2**25, 2**25),
}


def unpaired_hi16(relocations, index):
    current = relocations[index]
    if current.type != "HI16":
        return False
    if index + 1 == len(relocations):
        return True
    following = relocations[index + 1]
    return not (following.type == "LO16" and following.symbol is current.symbol
                and following.addend == current.addend)


def calculate(type_name, symbol, addend, place, gp):
    value = symbol + addend
    if type_name in ("REL32", "CALL24"):
        value -= place
    elif type_name == "GPREL16":
        value -= gp
    if type_name == "HI16":
        field = ((value % 2**32 + 32768) // 65536) % 65536
    elif type_name == "CALL24":
        field = (value // 4) % 2**24
    else:
        field = value % 2**(8 * WIDTHS[type_name])
    within_range = type_name not in RANGES or RANGES[type_name][0] <= value < RANGES[type_name][1]
    return value, field, within_range
