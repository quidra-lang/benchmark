import re
import sys


ADJACENT_KEYS = {
    "a": "qswz", "b": "ghnv", "c": "dfvx", "d": "cefrsx", "e": "drsw",
    "f": "cdgrtv", "g": "bfhtvy", "h": "bgjnuy", "i": "jkou", "j": "hikmnu",
    "k": "ijlmo", "l": "kop", "m": "jkn", "n": "bhjm", "o": "iklp",
    "p": "lo", "q": "aw", "r": "deft", "s": "adewxz", "t": "fgry",
    "u": "hijy", "v": "bcfg", "w": "aeqs", "x": "cdsz", "y": "ghtu",
    "z": "asx",
}
SOUNDEX_GROUPS = (
    ("bfpv", "1"), ("cgjkqsxz", "2"), ("dt", "3"), ("l", "4"),
    ("mn", "5"), ("r", "6"), ("aeiouy", "0"),
)
SOUNDEX_DIGITS = {
    letter: digit for letters, digit in SOUNDEX_GROUPS for letter in letters
}
SENTENCE_MARKS = ".!?"
FINDING_KINDS = ("unknown", "case", "capital", "repeats")
COUNTER_NAMES = ("checked", "unknown", "case", "capital", "repeats", "corrected")
OPTION_MAXIMUMS = {"LIMIT": 3, "SUGGESTIONS": 10}
KEYBOARD_MODES = ("ON", "OFF")
MAX_WORD_LENGTH = 30
MAX_FREQUENCY = 1000000
MAX_LISTED = 20
REPORT_SIZE = 10


class CommandError(Exception):
    pass


def word_argument(text):
    if re.fullmatch(r"[A-Za-z]{1,30}", text) is None:
        raise CommandError(f"BAD WORD {text}")
    return text.lower()


def number_argument(text, minimum, maximum):
    if re.fullmatch(r"[0-9]{1,7}", text) is None:
        raise CommandError(f"BAD NUMBER {text}")
    value = int(text)
    if not minimum <= value <= maximum:
        raise CommandError(f"BAD NUMBER {text}")
    return value


def decimal_text(numerator, denominator, digits):
    scale = 10 ** digits
    value = (2 * numerator * scale + denominator) // (2 * denominator)
    return f"{value // scale}.{value % scale:0{digits}d}"


def frequency_key(entry):
    word, frequency = entry
    return -frequency, word


def capitalize_first(word):
    return word[0].upper() + word[1:]


def apply_case(token_text, word):
    if len(token_text) >= 2 and token_text.isupper():
        return word.upper()
    if token_text[0].isupper():
        return capitalize_first(word)
    return word


class Token:
    def __init__(self, number, text, start, end, gap, previous):
        self.number = number
        self.text = text
        self.word = text.lower()
        self.start = start
        self.end = end
        self.gap = gap
        self.sentence_start = previous is None or any(
            mark in gap for mark in SENTENCE_MARKS
        )
        self.repeat = (
            previous is not None
            and self.word == previous.word
            and all(character == " " for character in gap)
        )

    def mixed_case(self):
        has_inner_upper = any(character.isupper() for character in self.text[1:])
        return has_inner_upper and not self.text.isupper()


def tokenize(text):
    tokens = []
    previous = None
    position = 0
    for match in re.finditer(r"[A-Za-z]+", text):
        token = Token(
            len(tokens) + 1, match.group(), match.start(), match.end(),
            text[position:match.start()], previous,
        )
        tokens.append(token)
        previous = token
        position = match.end()
    return tokens


def gap_cost(keyboard):
    return 2 if keyboard else 1


def substitution_cost(first, second, keyboard):
    if first == second:
        return 0
    if not keyboard:
        return 1
    return 1 if second in ADJACENT_KEYS[first] else 2


def is_swap(first, second, i, j):
    return (
        i >= 2 and j >= 2
        and first[i - 1] == second[j - 2]
        and first[i - 2] == second[j - 1]
    )


def distance_table(first, second, keyboard):
    gap = gap_cost(keyboard)
    rows, columns = len(first), len(second)
    table = [[0] * (columns + 1) for _ in range(rows + 1)]
    for i in range(rows + 1):
        table[i][0] = i * gap
    for j in range(columns + 1):
        table[0][j] = j * gap
    for i in range(1, rows + 1):
        for j in range(1, columns + 1):
            best = min(
                table[i - 1][j] + gap,
                table[i][j - 1] + gap,
                table[i - 1][j - 1] + substitution_cost(first[i - 1], second[j - 1], keyboard),
            )
            if is_swap(first, second, i, j):
                best = min(best, table[i - 2][j - 2] + 1)
            table[i][j] = best
    return table


def edit_distance(first, second, keyboard):
    return distance_table(first, second, keyboard)[len(first)][len(second)]


def prefix_distance(word, other, keyboard):
    return min(distance_table(word, other, keyboard)[len(word)])


def edit_operations(first, second, keyboard):
    table = distance_table(first, second, keyboard)
    gap = gap_cost(keyboard)
    operations = []
    i, j = len(first), len(second)
    while i > 0 or j > 0:
        if i >= 1 and j >= 1 and table[i][j] == table[i - 1][j - 1] + substitution_cost(
            first[i - 1], second[j - 1], keyboard
        ):
            if first[i - 1] != second[j - 1]:
                operations.append(f"sub:{first[i - 1]}>{second[j - 1]}")
            i, j = i - 1, j - 1
        elif is_swap(first, second, i, j) and table[i][j] == table[i - 2][j - 2] + 1:
            operations.append(f"swap:{first[i - 2]}{first[i - 1]}")
            i, j = i - 2, j - 2
        elif i >= 1 and table[i][j] == table[i - 1][j] + gap:
            operations.append(f"del:{first[i - 1]}")
            i -= 1
        else:
            operations.append(f"ins:{second[j - 1]}")
            j -= 1
    operations.reverse()
    return table[len(first)][len(second)], operations


def soundex(word):
    code = word[0].upper()
    previous = "0" if word[0] in "hw" else SOUNDEX_DIGITS[word[0]]
    for letter in word[1:]:
        if letter in "hw":
            continue
        digit = SOUNDEX_DIGITS[letter]
        if digit != "0" and digit != previous:
            code += digit
        previous = digit
    return (code + "000")[:4]


def segment(word, dictionary):
    length = len(word)
    ways = [0] * (length + 1)
    best = [None] * (length + 1)
    ways[length] = 1
    best[length] = []
    for start in range(length - 1, -1, -1):
        for end in range(start + 1, length + 1):
            piece = word[start:end]
            if piece not in dictionary or ways[end] == 0:
                continue
            ways[start] += ways[end]
            candidate = [piece] + best[end]
            current = best[start]
            if current is None or (len(candidate), candidate) < (len(current), current):
                best[start] = candidate
    return ways[0], best[0]


class UndoRecord:
    def __init__(self, name, dictionary, ignored, rules):
        self.name = name
        self.dictionary = dict(dictionary)
        self.ignored = set(ignored)
        self.rules = dict(rules)


class SpellChecker:
    def __init__(self, dictionary):
        self.dictionary = dictionary
        self.ignored = set()
        self.rules = {}
        self.keyboard = False
        self.base_limit = 2
        self.suggestion_count = 5
        self.undo_history = []
        self.unknown_log = {}
        self.correction_log = {}
        self.counters = dict.fromkeys(COUNTER_NAMES, 0)
        self.output = []
        self.handlers = {
            "CHECK": (None, self.check),
            "CORRECT": (None, self.correct),
            "FIX": (None, self.fix),
            "PROFILE": (None, self.profile),
            "LEARN": (None, self.learn),
            "SUGGEST": (1, self.suggest),
            "DIST": (2, self.dist),
            "SOUNDEX": (1, self.soundex_code),
            "SOUNDS": (1, self.sounds),
            "SPLIT": (1, self.split),
            "PREFIX": (2, self.prefix),
            "COMPLETE": (2, self.complete),
            "LIST": (2, self.list_words),
            "WORD": (1, self.word_info),
            "ADD": (2, self.add),
            "REMOVE": (1, self.remove),
            "IGNORE": (1, self.ignore),
            "UNIGNORE": (1, self.unignore),
            "RULE": (2, self.rule),
            "UNRULE": (1, self.unrule),
            "RULES": (0, self.show_rules),
            "KEYBOARD": (1, self.keyboard_mode),
            "SET": (2, self.set_option),
            "UNDO": (0, self.undo),
            "REPORT": (0, self.report),
            "HISTORY": (0, self.history),
            "STATS": (0, self.stats),
        }

    def emit(self, *parts):
        self.output.append(" ".join(str(part) for part in parts))

    def limit(self):
        return 2 * self.base_limit if self.keyboard else self.base_limit

    def is_known(self, word):
        return word in self.dictionary or word in self.ignored

    def frequency_order(self):
        entries = sorted(self.dictionary.items(), key=frequency_key)
        return [word for word, _ in entries]

    def require_entry(self, word):
        if word not in self.dictionary:
            raise CommandError(f"NOT FOUND {word}")
        return self.dictionary[word]

    def candidates(self, word):
        limit = self.limit()
        gap = gap_cost(self.keyboard)
        found = []
        for other, frequency in self.dictionary.items():
            if other == word or abs(len(other) - len(word)) * gap > limit:
                continue
            distance = edit_distance(word, other, self.keyboard)
            if distance <= limit:
                found.append((distance, -frequency, other))
        found.sort()
        return [(other, distance) for distance, _, other in found]

    def correction(self, word):
        if self.is_known(word):
            return None
        if word in self.rules:
            return self.rules[word]
        found = self.candidates(word)
        return found[0][0] if found else None

    def record_undo(self, name):
        record = UndoRecord(name, self.dictionary, self.ignored, self.rules)
        self.undo_history.append(record)

    def log_correction(self, word, replacement):
        key = (word, replacement)
        self.correction_log[key] = self.correction_log.get(key, 0) + 1
        self.counters["corrected"] += 1

    def unknown_finding(self, token):
        prefix = f"UNKNOWN {token.number} {token.text}"
        if token.word in self.rules:
            return f"{prefix} RULE {self.rules[token.word]}"
        found = self.candidates(token.word)
        if not found:
            return f"{prefix} NONE"
        words = [other for other, _ in found[:self.suggestion_count]]
        return " ".join([prefix, "SUGGEST"] + words)

    def check(self, text):
        tokens = tokenize(text)
        findings = []
        for token in tokens:
            if not self.is_known(token.word):
                findings.append(("unknown", self.unknown_finding(token)))
                self.unknown_log[token.word] = self.unknown_log.get(token.word, 0) + 1
            if token.mixed_case():
                findings.append(("case", f"CASE {token.number} {token.text}"))
            if token.sentence_start and token.text[0].islower():
                findings.append(("capital", f"CAPITAL {token.number} {token.text}"))
            if token.repeat:
                findings.append(("repeats", f"REPEAT {token.number} {token.text}"))
        counts = {
            kind: sum(found == kind for found, _ in findings) for kind in FINDING_KINDS
        }
        self.counters["checked"] += len(tokens)
        for kind in FINDING_KINDS:
            self.counters[kind] += counts[kind]
        self.emit(
            "CHECK", f"words={len(tokens)}",
            *(f"{kind}={counts[kind]}" for kind in FINDING_KINDS),
        )
        for _, line in findings:
            self.emit(line)

    def correct(self, text):
        pieces = []
        position = 0
        changed = 0
        for token in tokenize(text):
            replacement = self.correction(token.word)
            if replacement is None:
                pieces.append(token.gap + token.text)
            else:
                pieces.append(token.gap + apply_case(token.text, replacement))
                self.log_correction(token.word, replacement)
                changed += 1
            position = token.end
        pieces.append(text[position:])
        self.emit(f"CORRECT changed={changed}:", "".join(pieces))

    def fix(self, text):
        pieces = []
        position = 0
        removed = 0
        replaced = 0
        recased = 0
        for token in tokenize(text):
            position = token.end
            if token.repeat:
                removed += 1
                continue
            replacement = self.correction(token.word)
            target = token.word if replacement is None else replacement
            result = apply_case(token.text, target)
            if token.sentence_start and result[0].islower():
                result = capitalize_first(result)
            if replacement is not None:
                self.log_correction(token.word, replacement)
                replaced += 1
            elif result != token.text:
                recased += 1
            pieces.append(token.gap + result)
        pieces.append(text[position:])
        self.emit(
            "FIX", f"removed={removed}", f"replaced={replaced}",
            f"recased={recased}:", "".join(pieces),
        )

    def profile(self, text):
        tokens = tokenize(text)
        distinct = len({token.word for token in tokens})
        unknown = sum(not self.is_known(token.word) for token in tokens)
        sentences = sum(token.sentence_start for token in tokens)
        if tokens:
            characters = sum(len(token.text) for token in tokens)
            rate = decimal_text(100 * unknown, len(tokens), 1)
            average = decimal_text(characters, len(tokens), 2)
            longest = max(tokens, key=lambda token: len(token.text)).word
        else:
            rate, average, longest = "0.0", "0.00", "-"
        self.emit(
            "PROFILE", f"words={len(tokens)}", f"distinct={distinct}",
            f"unknown={unknown}", f"rate={rate}", f"avglen={average}",
            f"longest={longest}", f"sentences={sentences}",
        )

    def learn(self, text):
        self.record_undo("LEARN")
        updated = 0
        added = 0
        skipped = 0
        for token in tokenize(text):
            if len(token.word) > MAX_WORD_LENGTH:
                skipped += 1
            elif token.word in self.dictionary:
                self.dictionary[token.word] += 1
                updated += 1
            else:
                self.dictionary[token.word] = 1
                self.ignored.discard(token.word)
                added += 1
        self.emit("LEARN", f"updated={updated}", f"added={added}", f"skipped={skipped}")

    def suggest(self, arguments):
        word = word_argument(arguments[0])
        if self.is_known(word):
            self.emit("SUGGEST", word, "KNOWN")
        elif word in self.rules:
            self.emit("SUGGEST", word, "RULE", self.rules[word])
        else:
            found = self.candidates(word)
            self.emit(
                "SUGGEST", word, f"found={len(found)}",
                *(f"{other}:{distance}" for other, distance in found[:self.suggestion_count]),
            )

    def dist(self, arguments):
        first = word_argument(arguments[0])
        second = word_argument(arguments[1])
        distance, operations = edit_operations(first, second, self.keyboard)
        self.emit("DIST", first, second, distance, *operations)

    def soundex_code(self, arguments):
        word = word_argument(arguments[0])
        self.emit("SOUNDEX", word, soundex(word))

    def sounds(self, arguments):
        word = word_argument(arguments[0])
        code = soundex(word)
        matches = [
            other for other in self.frequency_order()
            if other != word and soundex(other) == code
        ]
        self.emit("SOUNDS", word, code, f"count={len(matches)}", *matches[:REPORT_SIZE])

    def split(self, arguments):
        word = word_argument(arguments[0])
        ways, best = segment(word, self.dictionary)
        if ways == 0:
            self.emit("SPLIT", word, "ways=0", "->", "NONE")
        else:
            self.emit("SPLIT", word, f"ways={ways}", "->", *best)

    def prefix(self, arguments):
        word = word_argument(arguments[0])
        count = number_argument(arguments[1], 1, MAX_LISTED)
        matches = [other for other in self.frequency_order() if other.startswith(word)]
        self.emit(
            "PREFIX", word, f"count={len(matches)}",
            *(f"{other}:{self.dictionary[other]}" for other in matches[:count]),
        )

    def complete(self, arguments):
        word = word_argument(arguments[0])
        count = number_argument(arguments[1], 1, MAX_LISTED)
        threshold = self.limit() // 2
        matches = []
        for other, frequency in self.dictionary.items():
            distance = prefix_distance(word, other, self.keyboard)
            if distance <= threshold:
                matches.append((distance, -frequency, other))
        matches.sort()
        self.emit(
            "COMPLETE", word, f"count={len(matches)}",
            *(f"{other}:{distance}" for distance, _, other in matches[:count]),
        )

    def list_words(self, arguments):
        word = word_argument(arguments[0])
        count = number_argument(arguments[1], 1, MAX_LISTED)
        matches = sorted(other for other in self.dictionary if other >= word)
        self.emit(
            "LIST", word, f"count={len(matches)}",
            *(f"{other}:{self.dictionary[other]}" for other in matches[:count]),
        )

    def word_info(self, arguments):
        word = word_argument(arguments[0])
        frequency = self.require_entry(word)
        rank = self.frequency_order().index(word) + 1
        self.emit(
            "WORD", word, f"freq={frequency}", f"rank={rank}",
            f"soundex={soundex(word)}", f"neighbors={len(self.candidates(word))}",
        )

    def add(self, arguments):
        word = word_argument(arguments[0])
        frequency = number_argument(arguments[1], 1, MAX_FREQUENCY)
        if word in self.dictionary:
            raise CommandError(f"DUPLICATE {word}")
        self.record_undo("ADD")
        self.dictionary[word] = frequency
        self.ignored.discard(word)
        self.emit("ADD", word, frequency)

    def remove(self, arguments):
        word = word_argument(arguments[0])
        frequency = self.require_entry(word)
        self.record_undo("REMOVE")
        del self.dictionary[word]
        self.emit("REMOVE", word, frequency)

    def ignore(self, arguments):
        word = word_argument(arguments[0])
        if word in self.dictionary:
            raise CommandError(f"IN DICTIONARY {word}")
        if word in self.ignored:
            raise CommandError(f"ALREADY IGNORED {word}")
        self.record_undo("IGNORE")
        self.ignored.add(word)
        self.emit("IGNORE", word)

    def unignore(self, arguments):
        word = word_argument(arguments[0])
        if word not in self.ignored:
            raise CommandError(f"NOT IGNORED {word}")
        self.record_undo("UNIGNORE")
        self.ignored.remove(word)
        self.emit("UNIGNORE", word)

    def rule(self, arguments):
        source = word_argument(arguments[0])
        target = word_argument(arguments[1])
        if source in self.dictionary:
            raise CommandError(f"IN DICTIONARY {source}")
        if target not in self.dictionary:
            raise CommandError(f"NOT FOUND {target}")
        self.record_undo("RULE")
        previous = self.rules.get(source)
        self.rules[source] = target
        if previous is None:
            self.emit("RULE", source, target)
        else:
            self.emit("RULE", source, target, "REPLACED", previous)

    def unrule(self, arguments):
        word = word_argument(arguments[0])
        if word not in self.rules:
            raise CommandError(f"NO RULE {word}")
        self.record_undo("UNRULE")
        target = self.rules.pop(word)
        self.emit("UNRULE", word, target)

    def show_rules(self, arguments):
        self.emit(
            "RULES", f"count={len(self.rules)}",
            *(f"{source}>{target}" for source, target in sorted(self.rules.items())),
        )

    def keyboard_mode(self, arguments):
        mode = arguments[0]
        if mode not in KEYBOARD_MODES:
            raise CommandError(f"BAD MODE {mode}")
        self.keyboard = mode == "ON"
        self.emit("KEYBOARD", mode)

    def set_option(self, arguments):
        option = arguments[0]
        if option not in OPTION_MAXIMUMS:
            raise CommandError(f"BAD OPTION {option}")
        value = number_argument(arguments[1], 1, OPTION_MAXIMUMS[option])
        if option == "LIMIT":
            self.base_limit = value
        else:
            self.suggestion_count = value
        self.emit("SET", option, value)

    def undo(self, arguments):
        if not self.undo_history:
            raise CommandError("NOTHING TO UNDO")
        record = self.undo_history.pop()
        self.dictionary = record.dictionary
        self.ignored = record.ignored
        self.rules = record.rules
        self.emit("UNDO", record.name)

    def report(self, arguments):
        entries = sorted(self.unknown_log.items(), key=lambda entry: (-entry[1], entry[0]))
        self.emit(
            "REPORT", f"distinct={len(entries)}",
            *(f"{word}:{count}" for word, count in entries[:REPORT_SIZE]),
        )

    def history(self, arguments):
        entries = sorted(self.correction_log.items(), key=lambda entry: (-entry[1], entry[0]))
        self.emit(
            "HISTORY", f"distinct={len(entries)}",
            *(
                f"{word}>{replacement}:{count}"
                for (word, replacement), count in entries[:REPORT_SIZE]
            ),
        )

    def stats(self, arguments):
        top, top_frequency = min(self.dictionary.items(), key=frequency_key)
        characters = sum(len(word) for word in self.dictionary)
        self.emit(
            "STATS", f"words={len(self.dictionary)}",
            f"total={sum(self.dictionary.values())}",
            f"avglen={decimal_text(characters, len(self.dictionary), 2)}",
            f"top={top}:{top_frequency}", f"ignored={len(self.ignored)}",
            f"rules={len(self.rules)}", f"keyboard={'ON' if self.keyboard else 'OFF'}",
            f"limit={self.limit()}", f"suggestions={self.suggestion_count}",
            f"undo={len(self.undo_history)}",
        )
        self.emit("SESSION", *(f"{name}={self.counters[name]}" for name in COUNTER_NAMES))

    def execute(self, line):
        name, separator, rest = line.partition(" ")
        try:
            if name not in self.handlers:
                raise CommandError(f"UNKNOWN COMMAND {name}")
            arity, handler = self.handlers[name]
            if arity is None:
                if not separator:
                    raise CommandError(f"BAD ARGUMENTS {name}")
                handler(rest)
            else:
                arguments = rest.split(" ") if separator else []
                if len(arguments) != arity:
                    raise CommandError(f"BAD ARGUMENTS {name}")
                handler(arguments)
        except CommandError as error:
            self.emit("ERROR", error)


def main():
    dictionary = {}
    word_count = int(sys.stdin.readline())
    for _ in range(word_count):
        word, frequency = sys.stdin.readline().split()
        dictionary[word] = int(frequency)
    checker = SpellChecker(dictionary)
    command_count = int(sys.stdin.readline())
    for _ in range(command_count):
        checker.execute(sys.stdin.readline().rstrip("\n"))
    sys.stdout.write("\n".join(checker.output) + "\n")


if __name__ == "__main__":
    main()
