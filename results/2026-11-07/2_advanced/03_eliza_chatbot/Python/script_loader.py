GLOBAL_DIRECTIVES = (
    "INITIAL", "FINAL", "QUIT", "STOP", "DEFAULT", "QUESTION", "REPEAT",
    "MEMSIZE", "PERSIST", "PRE", "POST", "SYNON",
)
TEXT_DIRECTIVES = ("INITIAL", "FINAL", "DEFAULT", "QUESTION", "REPEAT")
RULE_DIRECTIVES = ("DECOMP", "MEMORY")
ITEM_DIRECTIVES = ("REASM", "GOTO", "NEWKEY", "RESTATE")
MOVE_DIRECTIVES = ("GOTO", "NEWKEY", "RESTATE")
DIRECTIVES = GLOBAL_DIRECTIVES + ("KEY",) + RULE_DIRECTIVES + ITEM_DIRECTIVES
UNIQUE_DIRECTIVES = ("KEY", "SYNON", "PRE", "POST", "PERSIST")
PERSIST_OPTIONS = ("cycles", "memory")
WORD_CHARACTERS = "abcdefghijklmnopqrstuvwxyz0123456789'"
DEFAULT_MEMSIZE = 3
MAX_MEMSIZE = 20


def is_word(text):
    if not text or text[0] == "'" or text[-1] == "'":
        return False
    return all(character in WORD_CHARACTERS for character in text)


def is_number(text):
    return len(text) <= 2 and text.isdigit()


def is_reference(text):
    return len(text) == 3 and text[0] == "(" and text[1].isdigit() and text[2] == ")"


def is_element(text):
    if text in ("*", "#"):
        return True
    if text.startswith("@"):
        return is_word(text[1:])
    return is_word(text)


def well_formed(name, arguments):
    count = len(arguments)
    if name in TEXT_DIRECTIVES or name == "REASM":
        return count >= 1
    if name in ("QUIT", "STOP"):
        return count >= 1 and all(is_word(argument) for argument in arguments)
    if name == "MEMSIZE":
        return count == 1 and is_number(arguments[0]) and 1 <= int(arguments[0]) <= MAX_MEMSIZE
    if name == "PERSIST":
        return count == 1 and arguments[0] in PERSIST_OPTIONS
    if name in ("PRE", "SYNON"):
        return count >= 2 and all(is_word(argument) for argument in arguments)
    if name == "POST":
        return count >= 2 and is_word(arguments[0])
    if name == "KEY":
        return count == 2 and is_word(arguments[0]) and is_number(arguments[1])
    if name in RULE_DIRECTIVES:
        return count >= 1 and all(is_element(argument) for argument in arguments)
    if name == "GOTO":
        return count == 1 and is_word(arguments[0])
    if name == "NEWKEY":
        return count == 0
    return count >= 2 and is_word(arguments[0]) and all(
        is_word(argument) or is_reference(argument) for argument in arguments[1:]
    )


def definition_key(name, arguments):
    if name == "MEMSIZE":
        return name
    if name in UNIQUE_DIRECTIVES:
        return name + " " + arguments[0]
    return None


class Diagnostic:
    def __init__(self, line_number, code, message):
        self.line_number = line_number
        self.code = code
        self.message = message


class Substitution:
    def __init__(self, source, replacement, line_number):
        self.source = source
        self.replacement = replacement
        self.line_number = line_number


class Group:
    def __init__(self, name, members, line_number):
        self.name = name
        self.members = members
        self.line_number = line_number


class Item:
    def __init__(self, kind, text, arguments, line_number, index):
        self.kind = kind
        self.text = text
        self.arguments = arguments
        self.line_number = line_number
        self.index = index


class Rule:
    def __init__(self, kind, pattern, line_number, index):
        self.kind = kind
        self.pattern = pattern
        self.line_number = line_number
        self.index = index
        self.items = []


class Keyword:
    def __init__(self, word, rank, line_number, index):
        self.word = word
        self.rank = rank
        self.line_number = line_number
        self.index = index
        self.memories = []
        self.decomps = []


class Script:
    def __init__(self, lines):
        self.lines = lines
        self.texts = {name: [] for name in TEXT_DIRECTIVES}
        self.quit_words = set()
        self.stop_words = set()
        self.memsize = DEFAULT_MEMSIZE
        self.persist = set()
        self.pres = []
        self.posts = []
        self.pre_table = {}
        self.post_table = {}
        self.groups = []
        self.group_words = {}
        self.keywords = []
        self.keyword_map = {}
        self.rules = []
        self.items = []
        self.diagnostics = []


class ScriptLoader:
    def __init__(self, lines):
        self.script = Script(lines)
        self.keyword = None
        self.rule = None
        self.ignoring = False
        self.first_lines = {}

    def update_structure(self, name):
        if name in GLOBAL_DIRECTIVES or name == "KEY":
            self.keyword = None
            self.rule = None
            self.ignoring = False
        elif name in RULE_DIRECTIVES or name in ITEM_DIRECTIVES:
            if self.ignoring:
                return False
            if name in RULE_DIRECTIVES:
                self.rule = None
        return True

    def problem(self, name, arguments):
        if name not in DIRECTIVES:
            return "SYNTAX", "unknown directive " + name
        if not well_formed(name, arguments):
            return "SYNTAX", "bad arguments for " + name
        if name in RULE_DIRECTIVES and self.keyword is None:
            return "ORPHAN", name + " without KEY"
        if name == "REASM" and self.rule is None:
            return "ORPHAN", "REASM without DECOMP or MEMORY"
        if name in MOVE_DIRECTIVES and (self.rule is None or self.rule.kind == "MEMORY"):
            return "ORPHAN", name + " without DECOMP"
        key = definition_key(name, arguments)
        if key is not None and key in self.first_lines:
            return "DUPLICATE", f"{key} first defined at line {self.first_lines[key]}"
        return None

    def load(self, number, name, arguments, text):
        script = self.script
        key = definition_key(name, arguments)
        if key is not None:
            self.first_lines[key] = number
        if name in TEXT_DIRECTIVES:
            script.texts[name].append(text)
        elif name == "QUIT":
            script.quit_words.update(arguments)
        elif name == "STOP":
            script.stop_words.update(arguments)
        elif name == "MEMSIZE":
            script.memsize = int(arguments[0])
        elif name == "PERSIST":
            script.persist.add(arguments[0])
        elif name == "PRE":
            script.pres.append(Substitution(arguments[0], arguments[1:], number))
            script.pre_table[arguments[0]] = arguments[1:]
        elif name == "POST":
            script.posts.append(Substitution(arguments[0], arguments[1:], number))
            script.post_table[arguments[0]] = arguments[1:]
        elif name == "SYNON":
            script.groups.append(Group(arguments[0], arguments, number))
            script.group_words[arguments[0]] = set(arguments)
        elif name == "KEY":
            keyword = Keyword(arguments[0], int(arguments[1]), number, len(script.keywords))
            script.keywords.append(keyword)
            script.keyword_map[keyword.word] = keyword
            self.keyword = keyword
        elif name in RULE_DIRECTIVES:
            rule = Rule(name, arguments, number, len(script.rules))
            script.rules.append(rule)
            if name == "DECOMP":
                self.keyword.decomps.append(rule)
            else:
                self.keyword.memories.append(rule)
            self.rule = rule
        else:
            item = Item(name, text, arguments, number, len(script.items))
            script.items.append(item)
            self.rule.items.append(item)

    def load_line(self, number, line):
        name, _, text = line.partition(" ")
        arguments = text.split()
        if not self.update_structure(name):
            return
        problem = self.problem(name, arguments)
        if problem is None:
            self.load(number, name, arguments, text)
            return
        code, message = problem
        self.script.diagnostics.append(Diagnostic(number, code, message))
        if code == "DUPLICATE" and name == "KEY":
            self.ignoring = True


def load_script(path):
    with open(path) as file:
        lines = file.read().splitlines()
    loader = ScriptLoader(lines)
    for number, line in enumerate(lines, 1):
        if line and not line.startswith("#"):
            loader.load_line(number, line)
    return loader.script
