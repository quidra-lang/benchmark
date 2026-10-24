from protocol import fold


def matches(mask, value):
    mask = fold(mask)
    value = fold(value)
    pattern = position = 0
    star = -1
    restart = 0
    while position < len(value):
        if pattern < len(mask) and mask[pattern] == "*":
            star = pattern
            pattern += 1
            restart = position
        elif pattern < len(mask) and (mask[pattern] == "?" or mask[pattern] == value[position]):
            pattern += 1
            position += 1
        elif star != -1:
            restart += 1
            position = restart
            pattern = star + 1
        else:
            return False
    while pattern < len(mask) and mask[pattern] == "*":
        pattern += 1
    return pattern == len(mask)


def normalize(argument):
    if "!" in argument and "@" in argument:
        return argument
    if "@" in argument:
        return "*!" + argument
    if "!" in argument:
        return argument + "@*"
    if "." in argument:
        return "*!*@" + argument
    return argument + "!*@*"
