"""Box data, atom display/type tables and scalable delimiter glyphs."""

from lexer import SYMBOL_COMMANDS


COMMAND_DISPLAY = {name: display for name, (display, kind) in SYMBOL_COMMANDS.items()}
COMMAND_TYPES = {name: kind for name, (display, kind) in SYMBOL_COMMANDS.items()}
SYMBOL_TYPES = {
    **dict.fromkeys("+-*", "binary"), **dict.fromkeys("=<>:", "relation"),
    **dict.fromkeys("([", "open"), **dict.fromkeys(")]!", "close"),
    **dict.fromkeys(",;", "punctuation"),
}
LARGE_GLYPHS = {
    r"\sum": ("\\--", " > ", "/--"),
    r"\prod": ("___", "| |", "| |"),
    r"\int": (" /", " |", "/ "),
}


class Box:
    def __init__(self, width, height, baseline, description):
        self.width = width
        self.height = height
        self.baseline = baseline
        self.description = description
        self.children = []
        self.strings = []

    @property
    def descent(self):
        return self.height - 1 - self.baseline

    def add(self, child, x, y, role=""):
        self.children.append((child, x, y, role))

    def draw(self, text, x=0, y=0):
        self.strings.append((text, x, y))


def delimiter_glyph(delimiter, height):
    if delimiter == ".":
        return []
    character = delimiter[-1]
    if height == 1:
        return [character]
    if delimiter in ("[", "]", "|"):
        return [delimiter] * height
    left = delimiter in ("(", r"\{")
    result = ["/" if left else "\\"] + ["|"] * (height - 2) + ["\\" if left else "/"]
    if delimiter in (r"\{", r"\}") and height >= 3:
        result[(height - 1) // 2] = "<" if left else ">"
    return result
