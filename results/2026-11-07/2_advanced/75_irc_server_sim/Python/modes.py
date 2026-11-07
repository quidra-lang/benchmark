from protocol import digits


def channel_items(mode, arguments):
    items = []
    sign = "+"
    position = 0
    for character in mode:
        if character in "+-":
            sign = character
            continue
        argument = None
        if character in "ovbk" or character == "l" and sign == "+":
            if position < len(arguments):
                argument = arguments[position]
                position += 1
        if character == "k" and sign == "-":
            argument = "*"
        elif character == "l" and sign == "+":
            if argument is None or not digits(argument) or len(argument) > 4 or int(argument) < 1:
                argument = None
        items.append((sign, character, argument))
    return items


def change_string(changes):
    mode = ""
    arguments = []
    previous = None
    for sign, character, argument in changes:
        if sign != previous:
            mode += sign
            previous = sign
        mode += character
        if argument is not None:
            arguments.append(argument)
    return mode + "".join(" " + argument for argument in arguments)
