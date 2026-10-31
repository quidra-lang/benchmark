from values_fields import number, string, to_number, to_string


class RuntimeIssue(Exception):
    def __init__(self, position, message):
        super().__init__(message)
        self.position, self.message = position, message


def format_output(arguments, position):
    fmt = to_string(arguments[0])
    pieces = []
    index, argument_index = 0, 1
    while index < len(fmt):
        if fmt[index] != "%":
            pieces.append(fmt[index])
            index += 1
            continue
        index += 1
        if index < len(fmt) and fmt[index] == "%":
            pieces.append("%")
            index += 1
            continue
        flags = set()
        while index < len(fmt) and fmt[index] in "-0":
            flags.add(fmt[index])
            index += 1
        start = index
        while index < len(fmt) and "0" <= fmt[index] <= "9":
            index += 1
        width = int(fmt[start:index]) if start < index else 0
        precision = None
        if index < len(fmt) and fmt[index] == ".":
            index += 1
            start = index
            while index < len(fmt) and "0" <= fmt[index] <= "9":
                index += 1
            precision = int(fmt[start:index]) if start < index else 0
        if index == len(fmt) or fmt[index] not in "discxo":
            raise RuntimeIssue(position, "invalid format")
        conversion = fmt[index]
        index += 1
        if argument_index == len(arguments):
            raise RuntimeIssue(position, "not enough arguments")
        value = arguments[argument_index]
        argument_index += 1
        numeric = conversion in "dixo"
        if numeric:
            integer = to_number(value)
            base = "d" if conversion in "di" else conversion
            digits = format(abs(integer), base)
            if precision is not None:
                digits = "" if precision == 0 and integer == 0 else digits.rjust(precision, "0")
            body = ("-" if integer < 0 else "") + digits
        elif conversion == "s":
            body = to_string(value)
            if precision is not None:
                body = body[:precision]
        else:
            if value.kind in ("number", "strnum"):
                code = to_number(value)
                if code != 10 and not 32 <= code <= 126:
                    raise RuntimeIssue(position, "invalid character code")
                body = chr(code)
            else:
                body = to_string(value)[:1]
        missing = width - len(body)
        if missing > 0:
            if "-" in flags:
                body += " " * missing
            elif numeric and "0" in flags and precision is None:
                if body.startswith("-"):
                    body = "-" + "0" * missing + body[1:]
                else:
                    body = "0" * missing + body
            else:
                body = " " * missing + body
        pieces.append(body)
    return "".join(pieces)


def invoke(name, arguments, position):
    if name == "sprintf":
        return string(format_output(arguments, position))
    if name == "int":
        return number(to_number(arguments[0]))
    text = to_string(arguments[0])
    if name == "substr":
        start = to_number(arguments[1])
        end = start + to_number(arguments[2]) if len(arguments) == 3 else len(text) + 1
        start, end = max(start, 1), min(end, len(text) + 1)
        return string(text[start - 1:end - 1] if end > start else "")
    if name == "index":
        sought = to_string(arguments[1])
        return number(text.find(sought) + 1 if sought else 0)
    if name == "toupper":
        return string("".join(chr(ord(character) - 32) if "a" <= character <= "z" else character for character in text))
    if name == "tolower":
        return string("".join(chr(ord(character) + 32) if "A" <= character <= "Z" else character for character in text))
    raise ValueError(name)
