COMMAND_FORMS = {
    "ALLOC": ("number", "number"),
    "PUSH": ("source",),
    "LOAD": ("number", "number"),
    "POP": ("number",),
    "SET": ("number", "number", "source"),
    "OVERWRITE": ("number", "source"),
    "CHECKPOINT": ("label",),
}
COMMAND_NAMES = tuple(COMMAND_FORMS)
DIGITS = "0123456789"
LABEL_CHARACTERS = "abcdefghijklmnopqrstuvwxyz0123456789_"
MAX_NUMBER_LENGTH = 4
MAX_LABEL_LENGTH = 16
MAX_POINTERS = 6
MAX_DATA = 24


class CollectorEntry:
    def __init__(self, name, algorithm, young, age):
        self.name = name
        self.algorithm = algorithm
        self.young = young
        self.age = age


class Config:
    def __init__(self):
        self.heap_size = 0
        self.collectors = []
        self.maps = []
        self.windows = []
        self.width = 0


class Command:
    def __init__(self, line, name):
        self.line = line
        self.name = name
        self.pointers = 0
        self.data = 0
        self.slot = 0
        self.field = 0
        self.source = None
        self.count = 0
        self.label = ""


def read_lines(path):
    with open(path) as handle:
        return handle.read().split("\n")[:-1]


def read_config(path):
    config = Config()
    for line in read_lines(path):
        tokens = line.split(" ")
        keyword = tokens[0]
        if keyword == "HEAP":
            config.heap_size = int(tokens[1])
        elif keyword == "COLLECTOR":
            young = int(tokens[3]) if len(tokens) > 3 else 0
            age = int(tokens[4]) if len(tokens) > 4 else 0
            config.collectors.append(CollectorEntry(tokens[1], tokens[2], young, age))
        elif keyword == "MAPS":
            config.maps = tokens[1:]
        elif keyword == "MMU":
            config.windows = [int(token) for token in tokens[1:]]
        elif keyword == "WIDTH":
            config.width = int(tokens[1])
    return config


def read_script(path):
    return [parse_line(line, text) for line, text in enumerate(read_lines(path), 1)]


def is_number(token):
    if not 1 <= len(token) <= MAX_NUMBER_LENGTH:
        return False
    if len(token) > 1 and token[0] == "0":
        return False
    return all(char in DIGITS for char in token)


def is_label(token):
    if not 1 <= len(token) <= MAX_LABEL_LENGTH:
        return False
    return all(char in LABEL_CHARACTERS for char in token)


def token_matches(kind, token):
    if kind == "number":
        return is_number(token)
    if kind == "source":
        return token == "-" or is_number(token)
    return is_label(token)


def source_value(token):
    return None if token == "-" else int(token)


def build_command(line, tokens):
    name = tokens[0]
    command = Command(line, name)
    if name == "ALLOC":
        command.pointers = int(tokens[1])
        command.data = int(tokens[2])
    elif name == "PUSH":
        command.source = source_value(tokens[1])
    elif name == "LOAD":
        command.slot = int(tokens[1])
        command.field = int(tokens[2])
    elif name == "POP":
        command.count = int(tokens[1])
    elif name == "SET":
        command.slot = int(tokens[1])
        command.field = int(tokens[2])
        command.source = source_value(tokens[3])
    elif name == "OVERWRITE":
        command.slot = int(tokens[1])
        command.source = source_value(tokens[2])
    else:
        command.label = tokens[1]
    return command


def parse_line(line, text):
    tokens = text.split(" ")
    form = COMMAND_FORMS.get(tokens[0])
    if form is None or len(tokens) != len(form) + 1:
        return None, "syntax"
    for kind, token in zip(form, tokens[1:]):
        if not token_matches(kind, token):
            return None, "syntax"
    command = build_command(line, tokens)
    if command.name == "ALLOC" and (command.pointers > MAX_POINTERS or command.data > MAX_DATA):
        return None, "range"
    if command.name == "POP" and command.count == 0:
        return None, "range"
    return command, None
