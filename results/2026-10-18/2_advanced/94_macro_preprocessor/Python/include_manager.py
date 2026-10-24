"""Header search and cached source files, guards, and inclusion counters."""

from pathlib import Path

from lexer import lex_source


STARTS = ("if", "ifdef", "ifndef")
BRANCHES = ("elif", "elifdef", "elifndef", "else")


def directive_name(tokens):
    if len(tokens) >= 2 and tokens[0].spelling == "#" and tokens[1].kind == "identifier":
        return tokens[1].spelling
    return None


def detect_guard(lines):
    nonempty = [line.tokens for line in lines if line.tokens]
    if not nonempty:
        return None
    first, last = nonempty[0], nonempty[-1]
    if len(first) != 3 or directive_name(first) != "ifndef" or first[2].kind != "identifier":
        return None
    if len(last) != 2 or directive_name(last) != "endif":
        return None
    depth = 0
    for index, tokens in enumerate(nonempty):
        name = directive_name(tokens)
        if name in BRANCHES and depth == 1:
            return None
        if name in STARTS:
            depth += 1
        elif name == "endif":
            depth -= 1
        if depth == 0 and index != len(nonempty) - 1:
            return None
    return first[2].spelling if depth == 0 else None


class SourceFile:
    def __init__(self, path, contents):
        self.path, self.physical_lines = path, contents.count("\n")
        self.lines = lex_source(contents)
        self.guard = detect_guard(self.lines)
        self.once = False
        self.entered, self.skipped, self.output_lines, self.skipped_lines = 0, 0, 0, 0


class IncludeManager:
    def __init__(self):
        self.files = {}

    def search(self, name, quoted):
        paths = [name, "include/" + name] if quoted else ["include/" + name]
        for path in paths:
            if Path("input", path).is_file():
                return path
        return None

    def load(self, path):
        if path not in self.files:
            contents = Path("input", path).read_bytes().decode("ascii")
            self.files[path] = SourceFile(path, contents)
        return self.files[path]
