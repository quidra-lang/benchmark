def belongs(name, prefix):
    return name == prefix or name.startswith(prefix + ".")


def is_nobits(name):
    return belongs(name, ".bss")


def is_string_section(name):
    return belongs(name, ".rodata.str")


def read_lines(path):
    with open(path, encoding="ascii", newline="\n") as source:
        return [line[:-1] for line in source]


class Section:
    def __init__(self, owner, name, alignment, size):
        self.kind = "input"
        self.owner = owner
        self.name = name
        self.alignment = alignment
        self.size = size
        self.contents = bytearray()
        self.nobits = is_nobits(name)
        self.string = is_string_section(name)
        self.relocations = []
        self.discard_reason = None
        self.output = None
        self.live = False
        self.address = None
        self.merged = None
        self.merged_positions = {}


class Symbol:
    def __init__(self, owner, name, binding, kind):
        self.owner = owner
        self.name = name
        self.binding = binding
        self.kind = kind
        self.section = None
        self.offset = 0
        self.size = 0
        self.alignment = 1


class Relocation:
    def __init__(self, section, offset, type_name, symbol, addend):
        self.section = section
        self.offset = offset
        self.type = type_name
        self.symbol = symbol
        self.addend = addend


class Object:
    def __init__(self, name):
        self.name = name
        self.order = None
        self.sections = []
        self.section_names = {}
        self.comdats = []
        self.symbols = []
        self.symbol_names = {}


def parse_object(lines, index, name):
    result = Object(name)
    while lines[index] != "end":
        words = lines[index].split(" ")
        index += 1
        if words[0] == "section":
            section = Section(result, words[1], int(words[2]), int(words[3]))
            result.sections.append(section)
            result.section_names[section.name] = section
            if not section.nobits:
                while len(section.contents) < section.size:
                    section.contents.extend(bytes.fromhex(lines[index].split(" ")[1]))
                    index += 1
        elif words[0] == "comdat":
            result.comdats.append((words[1], [result.section_names[name] for name in words[2:]]))
        elif words[0] == "symbol":
            kind = "undefined" if words[3] == "undef" else "common" if words[3] == "common" else "defined"
            symbol = Symbol(result, words[1], words[2], kind)
            if kind == "common":
                symbol.size, symbol.alignment = int(words[4]), int(words[5])
            elif kind == "defined":
                symbol.section = result.section_names[words[3]]
                symbol.offset = int(words[4])
            result.symbols.append(symbol)
            result.symbol_names[symbol.name] = symbol
        elif words[0] == "reloc":
            section = result.section_names[words[1]]
            symbol = result.symbol_names[words[4]]
            section.relocations.append(Relocation(section, int(words[2]), words[3], symbol, int(words[5])))
    return result, index + 1


def read_object(path):
    return parse_object(read_lines(path), 0, path.name)[0]
