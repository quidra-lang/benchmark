LITERAL_DOLLAR = "\x01"
ESCAPES = {"\\": "\\", '"': '"', "n": "\n", "t": "\t", "$": LITERAL_DOLLAR}


class LogicalLine:
    def __init__(self, number):
        self.number = number
        self.segments = []
        self.error = None

    def fail(self, code, message):
        if self.error is None:
            self.error = (code, message)


def logical_lines(physical_lines):
    lines = []
    index = 0
    while index < len(physical_lines):
        line = LogicalLine(index + 1)
        source = physical_lines[index]
        index += 1
        position = 0
        quoted = False
        current = []
        while position < len(source):
            char = source[position]
            if char == "\\" and position == len(source) - 1:
                source = physical_lines[index].lstrip(" ")
                index += 1
                position = 0
            elif quoted and char == "\\":
                follower = source[position + 1]
                if follower in ESCAPES:
                    current.append(ESCAPES[follower])
                else:
                    line.fail("E_ESCAPE", "invalid escape sequence \\" + follower)
                position += 2
            elif char == '"':
                line.segments.append("".join(current))
                current = []
                quoted = not quoted
                position += 1
            elif not quoted and char in ";#":
                break
            else:
                current.append(char)
                position += 1
        if quoted:
            line.fail("E_UNTERMINATED", "unterminated string")
        line.segments.append("".join(current))
        lines.append(line)
    return lines
