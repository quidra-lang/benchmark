from pathlib import Path

from awk_builtins import RuntimeIssue


def letter(character):
    return "a" <= character <= "z" or "A" <= character <= "Z"


def valid_name(name):
    return bool(name) and (letter(name[0]) or name[0] == "_") and all(
        letter(character) or "0" <= character <= "9" or character == "_" for character in name)


def valid_filename(name):
    return bool(name) and not name.startswith(".") and all(
        letter(character) or "0" <= character <= "9" or character in "._-" for character in name)


class Operand:
    def __init__(self, kind, name, value=None):
        self.kind, self.name, self.value = kind, name, value
        self.records = 0


def parse_arguments(text):
    options, operands = [], []
    for line in text.splitlines():
        if line.startswith("-F "):
            options.append(("FS", line[3:]))
        elif line.startswith("-v "):
            name, value = line[3:].split("=", 1)
            options.append((name, value))
        elif "=" in line and valid_name(line.split("=", 1)[0]):
            name, value = line.split("=", 1)
            operands.append(Operand("assignment", name, value))
        else:
            operands.append(Operand("file", line))
    return options, operands


def read_records(name):
    return Path("input", name).read_text(encoding="ascii").splitlines()


class Output:
    def __init__(self):
        self.parts = []
        self.open = False
        self.writes = 0

    def append(self, text):
        self.parts.append(text)
        self.writes += 1

    def content(self):
        return "".join(self.parts)


class GetlineInput:
    def __init__(self):
        self.open = False
        self.ever_opened = False
        self.lines = []
        self.position = 0
        self.reads = 0


class Streams:
    def __init__(self):
        self.stdout = Output()
        self.outputs = {}
        self.inputs = {}

    def write(self, text, name=None, mode=None, position=None):
        if name is None:
            self.stdout.append(text)
            return
        if not valid_filename(name) or name in ("stdout.txt", "stats.txt"):
            raise RuntimeIssue(position, "invalid output file name")
        if name not in self.outputs:
            self.outputs[name] = Output()
        output = self.outputs[name]
        if not output.open:
            output.open = True
            if mode == ">":
                output.parts = []
        output.append(text)

    def getline(self, name):
        if name not in self.inputs:
            self.inputs[name] = GetlineInput()
        source = self.inputs[name]
        if not source.open:
            if not valid_filename(name) or not Path("input", name).is_file():
                return -1, None
            source.lines = read_records(name)
            source.position = 0
            source.open = source.ever_opened = True
        if source.position == len(source.lines):
            return 0, None
        line = source.lines[source.position]
        source.position += 1
        source.reads += 1
        return 1, line

    def close(self, name):
        closed = False
        for table in (self.outputs, self.inputs):
            if name in table and table[name].open:
                table[name].open = False
                closed = True
        return 0 if closed else -1

    def save(self):
        output = Path("output")
        output.mkdir(exist_ok=True)
        (output / "stdout.txt").write_text(self.stdout.content(), encoding="ascii", newline="\n")
        for name, stream in self.outputs.items():
            (output / name).write_text(stream.content(), encoding="ascii", newline="\n")
