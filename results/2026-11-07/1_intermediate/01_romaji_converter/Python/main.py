from collections import namedtuple
import re
import sys


SYSTEMS = ("HEPBURN", "TRADITIONAL", "KUNREI", "NIHON", "WAPURO")
VOWELS = "aiueo"
LOWER = "abcdefghijklmnopqrstuvwxyz"
UPPER = LOWER.upper()
LETTERS = LOWER + UPPER
SEPARATORS = ' 0123456789.,!?;:()"'
WORD_PATTERN = re.compile(r"[A-Za-z'-]+")
ROWS = {
    "a": "a i u e o".split(),
    "ka": "ka ki ku ke ko".split(),
    "sa": "sa si su se so".split(),
    "ta": "ta ti tu te to".split(),
    "na": "na ni nu ne no".split(),
    "ha": "ha hi hu he ho".split(),
    "ma": "ma mi mu me mo".split(),
    "ya": "ya yu yo".split(),
    "ra": "ra ri ru re ro".split(),
    "wa": "wa wi we wo".split(),
    "ga": "ga gi gu ge go".split(),
    "za": "za zi zu ze zo".split(),
    "da": "da di du de do".split(),
    "ba": "ba bi bu be bo".split(),
    "pa": "pa pi pu pe po".split(),
}
CONTRACTED_ROWS = "ka sa ta na ha ma ra ga za da ba pa".split()
BASE_ROWS = "a ka sa ta na ha ma ya ra wa".split()
BASE_ROW = {row: row for row in BASE_ROWS}
BASE_ROW.update({"ga": "ka", "za": "sa", "da": "ta", "ba": "ha", "pa": "ha"})
DEVOICE = str.maketrans({"g": "k", "z": "s", "d": "t", "b": "h", "p": "h"})
GOJUON = ("a i u e o ka ki ku ke ko sa si su se so ta ti tu te to na ni nu ne no "
          "ha hi hu he ho ma mi mu me mo ya yu yo ra ri ru re ro wa wi we wo N").split()
IROHA = ("i ro ha ni ho he to ti ri nu ru wo wa ka yo ta re so tu ne na ra mu u wi no "
         "o ku ya ma ke hu ko e te a sa ki yu me mi si we hi mo se su N").split()
COLLATION_RANKS = {
    "GOJUON": {kana: index for index, kana in enumerate(GOJUON)},
    "IROHA": {kana: index for index, kana in enumerate(IROHA)},
}
SPECIAL_DISPLAY = {"N": "N", "Q": "Q", "L": "-"}
Mora = namedtuple("Mora", "identifier column")


def mora_table():
    order = []
    info = {}
    for row, identifiers in ROWS.items():
        for identifier in identifiers:
            order.append(identifier)
            info[identifier] = row, identifier[-1]
    for row in CONTRACTED_ROWS:
        for ending in ("ya", "yu", "yo"):
            identifier = row[0] + ending
            order.append(identifier)
            info[identifier] = row, ending
    return order, info


MORA_ORDER, MORA_INFO = mora_table()


def make_spellings(system):
    result = {identifier: identifier for identifier in MORA_ORDER}
    if system in ("HEPBURN", "TRADITIONAL", "WAPURO"):
        result.update({"si": "shi", "ti": "chi", "tu": "tsu", "hu": "fu", "zi": "ji"})
        prefixes = {"sy": "sh", "ty": "ch", "zy": "j"}
        if system != "WAPURO":
            result.update({"di": "ji", "du": "zu", "wi": "i", "we": "e", "wo": "o"})
            prefixes["dy"] = "j"
        for identifier in MORA_ORDER:
            if identifier[:2] in prefixes:
                result[identifier] = prefixes[identifier[:2]] + identifier[2:]
    elif system == "KUNREI":
        result.update({"di": "zi", "du": "zu", "wi": "i", "we": "e", "wo": "o",
                       "dya": "zya", "dyu": "zyu", "dyo": "zyo"})
    return result


SPELLINGS = {system: make_spellings(system) for system in SYSTEMS}
READINGS = {}
for system in SYSTEMS:
    inverse = {}
    for identifier in MORA_ORDER:
        inverse.setdefault(SPELLINGS[system][identifier], identifier)
    READINGS[system] = inverse
NORMAL_READINGS = {}
for system in ("HEPBURN", "KUNREI", "NIHON", "WAPURO"):
    for spelling, identifier in READINGS[system].items():
        NORMAL_READINGS.setdefault(spelling, identifier)


class Problem(Exception):
    def __init__(self, message, column=None):
        self.message = message if column is None else f"col {column}: {message}"


def case_pattern(text, column):
    letters = [char for char in text if char in LETTERS]
    if all(char in LOWER for char in letters):
        return "LOWER"
    if text[0] in UPPER and all(char in LOWER for char in text[1:] if char in LETTERS):
        return "TITLE"
    if len(letters) >= 2 and all(char in UPPER for char in letters):
        return "UPPER"
    raise Problem("mixed case", column)


class Word:
    def __init__(self, text, column):
        self.text = text
        self.column = column
        self.pattern = case_pattern(text, column)
        self.morae = []

    def identifiers(self):
        return [mora.identifier for mora in self.morae]


def syllable_at(text, position, readings):
    for length in (3, 2, 1):
        spelling = text[position:position + length]
        if len(spelling) == length and spelling in readings:
            return readings[spelling], length
    return None


def parse_word(original, column, system, normalize=False):
    text = original.lower()
    readings = NORMAL_READINGS if normalize else READINGS[system]
    morae = []
    position = 0
    while position < len(text):
        char = text[position]
        next_char = text[position + 1] if position + 1 < len(text) else ""
        third = text[position + 2] if position + 2 < len(text) else ""
        current_column = column + position
        if char == "-":
            if not morae or morae[-1].identifier not in MORA_INFO:
                raise Problem("misplaced long mark", current_column)
            identifier, length = "L", 1
        elif char == "'":
            raise Problem("misplaced apostrophe", current_column)
        else:
            match = syllable_at(text, position, readings)
            if match is not None:
                identifier, length = match
            elif (system == "WAPURO" or normalize) and text.startswith("xtu", position):
                identifier, length = "Q", 3
            elif char == "n":
                identifier, length = "N", 1
                if normalize:
                    if next_char == "'" or (next_char == "n" and (not third or third not in "aiueoy'")):
                        length = 2
                elif system == "WAPURO":
                    if next_char == "n":
                        length = 2
                elif next_char == "'":
                    length = 2
            elif (system == "TRADITIONAL" or normalize) and char == "m" and next_char in ("b", "m", "p"):
                identifier, length = "N", 1
            elif char in LOWER and char not in "aiueon" and next_char == char and syllable_at(text, position + 1, readings):
                identifier, length = "Q", 1
            elif (system in ("HEPBURN", "TRADITIONAL") or normalize) and text.startswith("tch", position) and syllable_at(text, position + 1, readings):
                identifier, length = "Q", 1
            else:
                raise Problem("unknown syllable", current_column)
        morae.append(Mora(identifier, current_column))
        position += length
    return morae


def long_pairs(morae):
    latter = set()
    position = 0
    while position + 1 < len(morae):
        first = morae[position].identifier
        second = morae[position + 1].identifier
        if first in MORA_INFO and second in VOWELS and len(second) == 1:
            vowel = first[-1]
            if vowel == second or (vowel, second) in (("o", "u"), ("e", "i")):
                latter.add(position + 1)
                position += 2
                continue
        position += 1
    return latter


def long_elements(morae):
    pairs = long_pairs(morae)
    elements = {}
    for index, mora in enumerate(morae):
        if mora.identifier == "L":
            elements[index] = morae[index - 1].identifier[-1]
        elif index in pairs:
            previous = morae[index - 1].identifier[-1]
            if (previous, mora.identifier) in (("o", "o"), ("o", "u"), ("u", "u")):
                elements[index] = previous
    return elements


def write_parts(morae, system, long_mode):
    elements = long_elements(morae)
    parts = []
    for index, mora in enumerate(morae):
        identifier = mora.identifier
        following = morae[index + 1].identifier if index + 1 < len(morae) else None
        next_spelling = SPELLINGS[system].get(following, "")
        if index in elements:
            vowel = elements[index]
            if long_mode == "KEEP":
                part = "-" if identifier == "L" else SPELLINGS[system][identifier]
            elif long_mode == "DROP":
                part = ""
            elif long_mode == "PASSPORT":
                part = "h" if vowel == "o" and (not next_spelling or next_spelling[0] not in VOWELS) else ""
            elif long_mode == "HYPHEN":
                part = "-"
            else:
                part = vowel
        elif identifier in MORA_INFO:
            part = SPELLINGS[system][identifier]
        elif identifier == "N":
            initial = next_spelling[:1]
            if system == "WAPURO":
                part = "nn" if following == "N" or initial in tuple("aiueoyn") else "n"
            elif system == "TRADITIONAL" and initial in ("b", "m", "p"):
                part = "m"
            else:
                part = "n'" if initial in tuple("aiueoy") else "n"
        else:
            if next_spelling and next_spelling[0] not in "aiueon":
                part = "t" if system in ("HEPBURN", "TRADITIONAL") and next_spelling.startswith("ch") else next_spelling[0]
            elif system == "WAPURO":
                part = "xtu"
            else:
                raise Problem("small tsu cannot be written", mora.column)
        parts.append(part)
    return parts


def apply_case(text, pattern):
    if pattern == "UPPER":
        return text.upper()
    if pattern == "TITLE":
        return text.capitalize()
    return text


def canonical(word, system):
    return apply_case("".join(write_parts(word.morae, system, "KEEP")), word.pattern)


def devoiced(identifier):
    return identifier[0].translate(DEVOICE) + identifier[1:]


def collation_elements(morae):
    elements = []
    for mora in morae:
        identifier = mora.identifier
        if identifier == "L":
            continue
        if identifier == "N":
            elements.append(("N", 0, 0))
        elif identifier == "Q":
            elements.append(("tu", 0, 1))
        else:
            row, dan = MORA_INFO[identifier]
            voice = 1 if row in ("ga", "za", "da", "ba") else 2 if row == "pa" else 0
            if dan in ("ya", "yu", "yo"):
                elements.append((devoiced(row[0] + "i"), voice, 0))
                elements.append((dan, 0, 1))
            else:
                elements.append((devoiced(identifier), voice, 0))
    return elements


def wildcard_match(pattern, morae):
    identifiers = [mora.identifier for mora in morae]
    previous = [True] + [False] * len(identifiers)
    for item in pattern:
        current = [False] * (len(identifiers) + 1)
        if item == "*":
            current[0] = previous[0]
            for index in range(1, len(current)):
                current[index] = previous[index] or current[index - 1]
        else:
            for index, identifier in enumerate(identifiers, 1):
                current[index] = previous[index - 1] and (item == "?" or item == identifier)
        previous = current
    return previous[-1]


FORMATS = {
    "SET": (2, 0), "TABLE": (2, 1), "CONVERT": (2, 2),
    "NORMALIZE": (0, 0), "REVERSE": (1, 1), "VALID": (1, 1),
    "DETECT": (0, 0), "DIFF": (2, 2), "SAME": (2, 2),
    "MORAE": (1, 1), "SYLLABLES": (1, 1), "ROW": (1, 1),
    "STATS": (1, 1), "SORT": (1, 1), "INDEX": (1, 1),
    "FIND": (2, 1), "HAIKU": (1, 1), "KAIBUN": (1, 1), "SHIRITORI": (1, 1),
}
SETTING_VALUES = {
    "LONG": ("KEEP", "DROP", "PASSPORT", "HYPHEN", "DOUBLE"),
    "CASE": ("KEEP", "LOWER", "UPPER", "TITLE"),
    "ORDER": ("GOJUON", "IROHA"),
}


class Request:
    def __init__(self, command, args, text="", words=None, pattern=None):
        self.command = command
        self.args = args
        self.text = text
        self.words = [] if words is None else words
        self.pattern = pattern


def read_pattern(text, system):
    if any(char not in LOWER + "'-?*" for char in text):
        raise Problem("invalid pattern")
    result = []
    try:
        for part in re.split(r"([?*])", text):
            if part in ("?", "*"):
                result.append(part)
            elif part:
                result.extend(mora.identifier for mora in parse_word(part, 1, system))
    except Problem:
        raise Problem("invalid pattern")
    return result


def prepare_request(line):
    command = line.split(" ", 1)[0]
    if command not in FORMATS:
        raise Problem(f"unknown command {command}")
    count, system_count = FORMATS[command]
    if command in ("SET", "TABLE"):
        pieces = line.split(" ")
        if len(pieces) < 3:
            raise Problem("missing argument")
        if len(pieces) > 3:
            raise Problem("too many arguments")
        args, text = pieces[1:], ""
    else:
        pieces = line.split(" ", count + 1)
        if len(pieces) < count + 2:
            raise Problem("missing argument")
        args, text = pieces[1:count + 1], pieces[-1]
    for system in args[:system_count]:
        if system not in SYSTEMS:
            raise Problem(f"unknown system {system}")
    if command in ("SET", "TABLE"):
        return Request(command, args)
    pattern = read_pattern(args[1], args[0]) if command == "FIND" else None
    allowed = LETTERS + "'-" + SEPARATORS + ("/" if command in ("SAME", "HAIKU") else "")
    for column, char in enumerate(text, 1):
        if char not in allowed:
            raise Problem("invalid character", column)
    if command == "SAME":
        parts = text.split("/")
        if len(parts) != 2 or any(WORD_PATTERN.search(part) is None for part in parts):
            raise Problem("expected two texts")
    if command == "HAIKU":
        parts = text.split("/")
        if len(parts) not in (3, 5) or any(WORD_PATTERN.search(part) is None for part in parts):
            raise Problem("expected 3 or 5 lines")
    matches = list(WORD_PATTERN.finditer(text))
    if not matches:
        raise Problem("no words")
    words = [Word(match.group(), match.start() + 1) for match in matches]
    if command != "DETECT":
        slash_column = text.index("/") + 1 if command == "SAME" else None
        for word in words:
            if command == "NORMALIZE":
                system = "HEPBURN"
            elif command == "SAME" and word.column > slash_column:
                system = args[1]
            else:
                system = args[0]
            word.morae = parse_word(word.text, word.column, system, command == "NORMALIZE")
    return Request(command, args, text, words, pattern)


class Converter:
    def __init__(self):
        self.settings = {"LONG": "KEEP", "CASE": "KEEP", "ORDER": "GOJUON"}
        self.handlers = {
            "SET": self.set_option, "TABLE": self.table, "CONVERT": self.convert,
            "NORMALIZE": self.normalize, "REVERSE": self.reverse, "VALID": self.valid,
            "DETECT": self.detect, "DIFF": self.diff, "SAME": self.same,
            "MORAE": self.morae, "SYLLABLES": self.syllables, "ROW": self.row,
            "STATS": self.stats, "SORT": self.sort, "INDEX": self.index,
            "FIND": self.find, "HAIKU": self.haiku, "KAIBUN": self.kaibun,
            "SHIRITORI": self.shiritori,
        }

    def execute(self, line):
        try:
            request = prepare_request(line)
            return self.handlers[request.command](request)
        except Problem as problem:
            return "ERROR " + problem.message

    def write(self, word, system, morae=None):
        sequence = word.morae if morae is None else morae
        text = "".join(write_parts(sequence, system, self.settings["LONG"]))
        pattern = word.pattern if self.settings["CASE"] == "KEEP" else self.settings["CASE"]
        return apply_case(text, pattern)

    def rewrite_text(self, request, render):
        words = iter(request.words)
        return WORD_PATTERN.sub(lambda match: render(next(words)), request.text)

    def set_option(self, request):
        option, value = request.args
        if option not in SETTING_VALUES:
            raise Problem(f"unknown option {option}")
        if value not in SETTING_VALUES[option]:
            raise Problem(f"unknown value {value}")
        self.settings[option] = value
        return f"{option}={value}"

    def table(self, request):
        system, row = request.args
        if row not in ROWS:
            raise Problem(f"unknown row {row}")
        return " ".join(SPELLINGS[system][identifier] for identifier in MORA_ORDER
                        if MORA_INFO[identifier][0] == row)

    def convert(self, request):
        return self.rewrite_text(request, lambda word: self.write(word, request.args[1]))

    def normalize(self, request):
        return self.rewrite_text(request, lambda word: self.write(word, "HEPBURN"))

    def reverse(self, request):
        def render(word):
            expanded = []
            for index, mora in enumerate(word.morae):
                if mora.identifier == "L":
                    expanded.append(Mora(word.morae[index - 1].identifier[-1], mora.column))
                else:
                    expanded.append(mora)
            return self.write(word, request.args[0], list(reversed(expanded)))

        return self.rewrite_text(request, render)

    def valid(self, request):
        for word in request.words:
            expected = canonical(word, request.args[0])
            if word.text != expected:
                index = 0
                while index < min(len(word.text), len(expected)) and word.text[index] == expected[index]:
                    index += 1
                return f"INVALID col {word.column + index}: expected {expected}"
        return "VALID"

    def detect(self, request):
        results = []
        for system in SYSTEMS:
            try:
                for word in request.words:
                    word.morae = parse_word(word.text, word.column, system)
                verdict = "canonical" if all(canonical(word, system) == word.text for word in request.words) else "readable"
            except Problem:
                verdict = "error"
            results.append(f"{system}={verdict}")
        return " ".join(results)

    def diff(self, request):
        differences = []
        for word in request.words:
            first = self.write(word, request.args[0])
            second = self.write(word, request.args[1])
            if first != second:
                differences.append(f"{first}>{second}")
        counts = f"{len(differences)} of {len(request.words)}"
        return counts + (": " + " ".join(differences) if differences else "")

    def same(self, request):
        slash_column = request.text.index("/") + 1
        left = [word for word in request.words if word.column < slash_column]
        right = [word for word in request.words if word.column > slash_column]
        exact = True
        for index, (first, second) in enumerate(zip(left, right), 1):
            first_long = long_elements(first.morae)
            second_long = long_elements(second.morae)
            first_loose = [m.identifier for i, m in enumerate(first.morae) if i not in first_long]
            second_loose = [m.identifier for i, m in enumerate(second.morae) if i not in second_long]
            if first_loose != second_loose:
                return f"DIFFERENT at word {index}"
            exact = exact and first.identifiers() == second.identifiers()
        if len(left) != len(right):
            return f"DIFFERENT at word {min(len(left), len(right)) + 1}"
        return "EXACT" if exact else "LOOSE"

    def morae(self, request):
        system = request.args[0]
        count = sum(len(word.morae) for word in request.words)
        words = [".".join(SPELLINGS[system][m.identifier] if m.identifier in MORA_INFO
                          else SPECIAL_DISPLAY[m.identifier] for m in word.morae)
                 for word in request.words]
        return f"{count}: " + " ".join(words)

    def syllables(self, request):
        count = 0
        words = []
        for word in request.words:
            parts = write_parts(word.morae, request.args[0], "KEEP")
            pairs = long_pairs(word.morae)
            syllables = []
            for index, (mora, part) in enumerate(zip(word.morae, parts)):
                if index == 0 or (mora.identifier in MORA_INFO and index not in pairs):
                    syllables.append(part)
                else:
                    syllables[-1] += part
            count += len(syllables)
            words.append(".".join(syllables))
        return f"{count}: " + " ".join(words)

    def row(self, request):
        items = []
        for word in request.words:
            for mora in word.morae:
                identifier = mora.identifier
                if identifier in MORA_INFO:
                    row, dan = MORA_INFO[identifier]
                    items.append(f"{SPELLINGS[request.args[0]][identifier]}: {row} {dan}")
                else:
                    items.append(f"{SPECIAL_DISPLAY[identifier]}: special")
        return ", ".join(items)

    def stats(self, request):
        base_counts = dict.fromkeys(BASE_ROWS, 0)
        other_counts = dict.fromkeys(("voiced", "semivoiced", "contracted", "N", "Q", "L"), 0)
        total = 0
        for word in request.words:
            for mora in word.morae:
                total += 1
                identifier = mora.identifier
                if identifier in MORA_INFO:
                    row, dan = MORA_INFO[identifier]
                    base_counts[BASE_ROW[row]] += 1
                    if row in ("ga", "za", "da", "ba"):
                        other_counts["voiced"] += 1
                    if row == "pa":
                        other_counts["semivoiced"] += 1
                    if dan in ("ya", "yu", "yo"):
                        other_counts["contracted"] += 1
                else:
                    other_counts[identifier] += 1
        items = [f"morae={total}"]
        items.extend(f"{row}={count}" for row, count in base_counts.items() if count)
        items.extend(f"{name}={count}" for name, count in other_counts.items())
        return " ".join(items)

    def collation_key(self, word):
        elements = collation_elements(word.morae)
        ranks = COLLATION_RANKS[self.settings["ORDER"]]
        return (
            tuple(ranks[base] for base, voice, size in elements),
            tuple(voice for base, voice, size in elements),
            tuple(size for base, voice, size in elements),
            tuple(1 if mora.identifier == "L" else 0 for mora in word.morae),
        )

    def sorted_words(self, request):
        return sorted(request.words, key=self.collation_key)

    def sort(self, request):
        return " ".join(word.text for word in self.sorted_words(request))

    def index(self, request):
        groups = []
        for word in self.sorted_words(request):
            first = collation_elements(word.morae)[0][0]
            if self.settings["ORDER"] == "IROHA" or first == "N":
                heading = first
            else:
                heading = MORA_INFO[first][0]
            if groups and groups[-1][0] == heading:
                groups[-1][1].append(word.text)
            else:
                groups.append((heading, [word.text]))
        return "; ".join(heading + ": " + " ".join(words) for heading, words in groups)

    def find(self, request):
        matches = [word.text for word in request.words if wildcard_match(request.pattern, word.morae)]
        counts = f"{len(matches)} of {len(request.words)}"
        return counts + (": " + " ".join(matches) if matches else "")

    def haiku(self, request):
        line_count = request.text.count("/") + 1
        counts = [0] * line_count
        for word in request.words:
            index = request.text[:word.column - 1].count("/")
            counts[index] += len(word.morae)
        expected = [5, 7, 5] if line_count == 3 else [5, 7, 5, 7, 7]
        verdict = "OK" if counts == expected else "NG"
        form = "haiku" if line_count == 3 else "tanka"
        return f"{verdict} {form} " + "-".join(map(str, counts))

    def kaibun(self, request):
        bases = [base for word in request.words for base, voice, size in collation_elements(word.morae)]
        verdict = "YES" if bases == bases[::-1] else "NO"
        return verdict + " " + ".".join(bases)

    def shiritori(self, request):
        previous_tail = None
        seen = set()
        for index, word in enumerate(request.words, 1):
            elements = collation_elements(word.morae)
            head, tail = elements[0][0], elements[-1][0]
            identifiers = tuple(word.identifiers())
            if previous_tail is not None and head != previous_tail:
                expected = SPELLINGS[request.args[0]][previous_tail]
                return f"NG {index}: {word.text} must start with {expected}"
            if identifiers in seen:
                return f"NG {index}: {word.text} is repeated"
            if tail == "N":
                return f"NG {index}: {word.text} ends with N"
            seen.add(identifiers)
            previous_tail = tail
        return f"OK {len(request.words)}"


def main():
    converter = Converter()
    count = int(sys.stdin.readline())
    for _ in range(count):
        line = sys.stdin.readline().rstrip("\n")
        print(converter.execute(line))


if __name__ == "__main__":
    main()
