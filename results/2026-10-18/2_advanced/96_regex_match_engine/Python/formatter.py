"""ASCII display, literal/class rendering, instruction notation and quoting."""


def display(character):
    code = ord(character)
    if 33 <= code <= 126 and character not in "\\]^-":
        return character
    return f"\\x{code:02X}"


def set_notation(codes, negated=False):
    ordered = sorted(codes)
    pieces = []
    position = 0
    while position < len(ordered):
        end = position
        while (end + 1 < len(ordered)
               and ordered[end + 1] == ordered[end] + 1):
            end += 1
        first = display(chr(ordered[position]))
        last = display(chr(ordered[end]))
        length = end - position + 1
        if length == 1:
            pieces.append(first)
        elif length == 2:
            pieces.append(first + last)
        else:
            pieces.append(first + "-" + last)
        position = end + 1
    return "[" + ("^" if negated else "") + "".join(pieces) + "]"


def instruction_notation(ins):
    op = ins["op"]
    if op == "CHAR":
        return "CHAR " + display(ins["char"])
    if op == "CLASS":
        return "CLASS " + set_notation(ins["set"], ins["neg"])
    if op == "SPLIT":
        return f"SPLIT {ins['x']}, {ins['y']}"
    if op == "JMP":
        return f"JMP {ins['x']}"
    if op == "SAVE":
        return f"SAVE {ins['slot']}"
    if op == "ASSERT":
        return "ASSERT " + ins["kind"]
    if op == "BACKREF":
        return f"BACKREF {ins['group']}"
    if op == "LOOK":
        return f"LOOK {ins['kind']} {ins['x']}"
    return op


def quoted(text):
    replaced = (text.replace("\\", "\\\\")
                .replace('"', '\\"')
                .replace("\n", "\\n")
                .replace("\t", "\\t"))
    return '"' + replaced + '"'


def decode_quoted(text):
    result = []
    index = 1
    while index < len(text) - 1:
        current = text[index]
        if current != "\\":
            result.append(current)
            index += 1
        else:
            index += 1
            code = text[index]
            result.append({"n": "\n", "t": "\t",
                           "\\": "\\", '"': '"'}[code])
            index += 1
    return "".join(result)
