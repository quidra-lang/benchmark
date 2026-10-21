import re
import sys
from collections import Counter
from dataclasses import dataclass
from fractions import Fraction
from functools import cache


TOKEN_PATTERN = re.compile(r"[A-Za-z]+")
WORD_PATTERN = re.compile(r"[A-Za-z]{1,30}")
NUMBER_PATTERN = re.compile(r"[0-9]{1,7}")
PREFIX_TERM_PATTERN = re.compile(r"[A-Za-z]{1,30}\*")
LEXEME_PATTERN = re.compile(r"[()]|[^ ()]+")
OPERATORS = ("AND", "OR", "NOT")
PARENTHESES = ("(", ")")
CONJUNCTION_CONTINUATIONS = ("AND", "NOT", "(", "term", "prefix")
VOWELS = "aeiou"
STEP_NAMES = ("1a", "1b", "1c", "2", "3", "4", "5a", "5b")
STEP_4_SUFFIXES = (
    "al", "ance", "ence", "er", "ic", "able", "ible", "ant", "ement", "ment",
    "ent", "ion", "ou", "ism", "ate", "iti", "ous", "ive", "ize",
)
KWIC_WIDTH = 30
MAX_COUNT = 100
MAX_DOCUMENT_NUMBER = 999
MAX_LINE_NUMBER = 999


class CommandError(Exception):
    pass


def letter_pattern(word):
    kinds = []
    for index, letter in enumerate(word):
        if letter in VOWELS or (letter == "y" and index > 0 and kinds[-1] == "C"):
            kinds.append("V")
        else:
            kinds.append("C")
    return "".join(kinds)


def measure(word):
    return letter_pattern(word).count("VC")


def has_vowel(word):
    return "V" in letter_pattern(word)


def ends_double(word):
    return letter_pattern(word).endswith("CC") and word[-1] == word[-2]


def ends_cvc(word):
    return letter_pattern(word).endswith("CVC") and word[-1] not in "wxy"


def always(remainder):
    return True


def measure_above_zero(remainder):
    return measure(remainder) > 0


def measure_above_one(remainder):
    return measure(remainder) > 1


def ion_condition(remainder):
    return measure(remainder) > 1 and remainder.endswith(("s", "t"))


def final_e_condition(remainder):
    value = measure(remainder)
    return value > 1 or (value == 1 and not ends_cvc(remainder))


def rules_with(condition, replacements):
    return [(suffix, replacement, condition) for suffix, replacement in replacements.items()]


RULE_TABLES = {
    "1a": rules_with(always, {"sses": "ss", "ies": "i", "ss": "ss", "s": ""}),
    "1b": [("eed", "ee", measure_above_zero), ("ed", "", has_vowel), ("ing", "", has_vowel)],
    "1c": [("y", "i", has_vowel)],
    "2": rules_with(measure_above_zero, {
        "ational": "ate", "tional": "tion", "enci": "ence", "anci": "ance",
        "izer": "ize", "abli": "able", "alli": "al", "entli": "ent", "eli": "e",
        "ousli": "ous", "ization": "ize", "ation": "ate", "ator": "ate",
        "alism": "al", "iveness": "ive", "fulness": "ful", "ousness": "ous",
        "aliti": "al", "iviti": "ive", "biliti": "ble",
    }),
    "3": rules_with(measure_above_zero, {
        "icate": "ic", "ative": "", "alize": "al", "iciti": "ic",
        "ical": "ic", "ful": "", "ness": "",
    }),
    "4": [
        (suffix, "", ion_condition if suffix == "ion" else measure_above_one)
        for suffix in STEP_4_SUFFIXES
    ],
    "5a": [("e", "", final_e_condition)],
}


def apply_rules(word, rules):
    """Apply the rule with the longest matching suffix; return the word and the applied suffix."""
    matching = [rule for rule in rules if word.endswith(rule[0])]
    if not matching:
        return word, None
    suffix, replacement, condition = max(matching, key=lambda rule: len(rule[0]))
    remainder = word[:-len(suffix)]
    if not condition(remainder):
        return word, None
    return remainder + replacement, suffix


def tidy_step_1b(word):
    if word.endswith(("at", "bl", "iz")):
        return word + "e"
    if ends_double(word) and word[-1] not in "lsz":
        return word[:-1]
    if measure(word) == 1 and ends_cvc(word):
        return word + "e"
    return word


def apply_step(name, word):
    if name == "5b":
        if measure(word) > 1 and ends_double(word) and word.endswith("l"):
            return word[:-1]
        return word
    result, suffix = apply_rules(word, RULE_TABLES[name])
    if name == "1b" and suffix in ("ed", "ing"):
        return tidy_step_1b(result)
    return result


def stemming_steps(word):
    changes = []
    if len(word) > 2:
        for name in STEP_NAMES:
            result = apply_step(name, word)
            if result != word:
                changes.append((name, result))
            word = result
    return word, changes


@cache
def porter_stem(word):
    return stemming_steps(word)[0]


def yes_no(flag):
    return "YES" if flag else "NO"


def word_argument(text):
    if WORD_PATTERN.fullmatch(text) is None:
        raise CommandError(f"BAD WORD {text}")
    return text.lower()


def number_argument(text, minimum, maximum):
    if NUMBER_PATTERN.fullmatch(text) is None:
        raise CommandError(f"BAD NUMBER {text}")
    value = int(text)
    if not minimum <= value <= maximum:
        raise CommandError(f"BAD NUMBER {text}")
    return value


def split_arguments(name, rest):
    if name == "SEARCH":
        return [rest]
    if name == "APPEND":
        return rest.split(" ", 1)
    return rest.split(" ")


def by_count(entry):
    stem, count = entry
    return -count, stem


def document_count(occurrences):
    return len({document.number for document, _ in occurrences})


def closest_distance(positions, others, same_stem):
    if same_stem:
        gaps = [later - earlier for earlier, later in zip(positions, positions[1:])]
    else:
        # The closest pair of different stems is adjacent in the merged order.
        merged = sorted(
            [(position, 0) for position in positions] + [(other, 1) for other in others]
        )
        gaps = [
            later[0] - earlier[0]
            for earlier, later in zip(merged, merged[1:])
            if earlier[1] != later[1]
        ]
    return min(gaps, default=None)


def classify(lexeme):
    if lexeme in OPERATORS or lexeme in PARENTHESES:
        return lexeme, lexeme
    if WORD_PATTERN.fullmatch(lexeme):
        return "term", lexeme.lower()
    if PREFIX_TERM_PATTERN.fullmatch(lexeme):
        return "prefix", lexeme[:-1].lower()
    raise CommandError(f"BAD TERM {lexeme}")


@dataclass
class Token:
    text: str
    line: int
    position: int
    start: int

    @property
    def form(self):
        return self.text.lower()

    @property
    def end(self):
        return self.start + len(self.text)


class Document:
    def __init__(self, number):
        self.number = number
        self.lines = []
        self.tokens = []

    def add_line(self, text):
        self.lines.append(text)
        added = []
        for match in TOKEN_PATTERN.finditer(text):
            token = Token(match.group(), len(self.lines), len(self.tokens) + 1, match.start())
            self.tokens.append(token)
            added.append(token)
        return added

    def line_tokens(self, line_number):
        return [token for token in self.tokens if token.line == line_number]

    def reference(self, token):
        return f"{self.number}:{token.line}:{token.position}"


class QueryParser:
    def __init__(self, items, stem_sets):
        self.items = items
        self.position = 0
        self.stem_sets = stem_sets

    def peek(self):
        if self.position < len(self.items):
            return self.items[self.position][0]
        return None

    def take(self):
        if self.position >= len(self.items):
            raise CommandError("SYNTAX")
        item = self.items[self.position]
        self.position += 1
        return item

    def parse(self):
        result = self.expression()
        if self.position < len(self.items):
            raise CommandError("SYNTAX")
        return result

    def expression(self):
        canonical, documents = self.conjunction()
        while self.peek() == "OR":
            self.position += 1
            right, right_documents = self.conjunction()
            canonical = f"({canonical} OR {right})"
            documents = documents | right_documents
        return canonical, documents

    def conjunction(self):
        canonical, documents = self.negation()
        while self.peek() in CONJUNCTION_CONTINUATIONS:
            if self.peek() == "AND":
                self.position += 1
            right, right_documents = self.negation()
            canonical = f"({canonical} AND {right})"
            documents = documents & right_documents
        return canonical, documents

    def negation(self):
        if self.peek() == "NOT":
            self.position += 1
            canonical, documents = self.negation()
            return f"(NOT {canonical})", set(self.stem_sets) - documents
        return self.element()

    def element(self):
        kind, spelling = self.take()
        if kind == "(":
            result = self.expression()
            if self.take()[0] != ")":
                raise CommandError("SYNTAX")
            return result
        if kind == "term":
            stem = porter_stem(spelling)
            documents = {number for number, stems in self.stem_sets.items() if stem in stems}
            return stem, documents
        if kind == "prefix":
            documents = {
                number for number, stems in self.stem_sets.items()
                if any(stem.startswith(spelling) for stem in stems)
            }
            return f"{spelling}*", documents
        raise CommandError("SYNTAX")


class SearchEngine:
    def __init__(self, stopwords):
        self.stopwords = stopwords
        self.documents = {}
        self.output = []
        self.handlers = {
            "STEM": (1, 10, self.stem_words),
            "STEPS": (1, 1, self.show_steps),
            "MEASURE": (1, 1, self.show_measure),
            "INDEX": (0, 1, self.show_index),
            "SEARCH": (1, 1, self.search),
            "PHRASE": (2, 10, self.phrase),
            "NEAR": (3, 3, self.near),
            "TOP": (1, 2, self.top),
            "KWIC": (1, 1, self.kwic),
            "TF": (2, 2, self.term_frequency),
            "DF": (1, 1, self.document_frequency),
            "VARIANTS": (1, 1, self.variants),
            "SIMILAR": (2, 2, self.similar),
            "RANK": (2, 11, self.rank),
            "INFO": (1, 1, self.info),
            "LINE": (2, 2, self.show_line),
            "STATS": (0, 0, self.stats),
            "STOP": (1, 1, self.stop),
            "UNSTOP": (1, 1, self.unstop),
            "APPEND": (2, 2, self.append),
            "DELETE": (1, 1, self.delete),
        }

    def emit(self, *parts):
        self.output.append(" ".join(str(part) for part in parts))

    def add_document(self, number):
        document = Document(number)
        self.documents[number] = document
        return document

    def ordered_documents(self):
        return [self.documents[number] for number in sorted(self.documents)]

    def is_indexed(self, token):
        return token.form not in self.stopwords

    def indexed_tokens(self, document):
        return [token for token in document.tokens if self.is_indexed(token)]

    def term_frequencies(self, document):
        return Counter(porter_stem(token.form) for token in self.indexed_tokens(document))

    def stem_set(self, document):
        return set(self.term_frequencies(document))

    def total_frequencies(self):
        totals = Counter()
        for document in self.documents.values():
            totals.update(self.term_frequencies(document))
        return totals

    def occurrence_map(self):
        occurrences = {}
        for document in self.ordered_documents():
            for token in self.indexed_tokens(document):
                occurrences.setdefault(porter_stem(token.form), []).append((document, token))
        return occurrences

    def stem_positions(self, document, stem):
        return [
            token.position for token in self.indexed_tokens(document)
            if porter_stem(token.form) == stem
        ]

    def form_count(self, form):
        return sum(
            token.form == form
            for document in self.documents.values()
            for token in document.tokens
        )

    def token_matches(self, token, target):
        return target == "?" or (self.is_indexed(token) and porter_stem(token.form) == target)

    def describe_token(self, token):
        if self.is_indexed(token):
            return f"{token.form}/{porter_stem(token.form)}"
        return f"{token.form}/-"

    def term_argument(self, text):
        word = word_argument(text)
        if word in self.stopwords:
            raise CommandError(f"STOPWORD {word}")
        return porter_stem(word)

    def document_argument(self, text):
        number = number_argument(text, 1, MAX_DOCUMENT_NUMBER)
        if number not in self.documents:
            raise CommandError(f"NO DOC {number}")
        return self.documents[number]

    def stem_words(self, arguments):
        words = [word_argument(argument) for argument in arguments]
        self.emit("STEM", *(f"{word}:{porter_stem(word)}" for word in words))

    def show_steps(self, arguments):
        word = word_argument(arguments[0])
        _, changes = stemming_steps(word)
        if not changes:
            self.emit("STEPS", word, "NONE")
        else:
            self.emit("STEPS", word, *(f"{name}:{result}" for name, result in changes))

    def show_measure(self, arguments):
        word = word_argument(arguments[0])
        self.emit(
            "MEASURE", word, letter_pattern(word), f"m={measure(word)}",
            f"vowel={yes_no(has_vowel(word))}", f"double={yes_no(ends_double(word))}",
            f"cvc={yes_no(ends_cvc(word))}",
        )

    def show_index(self, arguments):
        prefix = word_argument(arguments[0]) if arguments else ""
        occurrences = self.occurrence_map()
        stems = sorted(stem for stem in occurrences if stem.startswith(prefix))
        self.emit("INDEX", f"stems={len(stems)}")
        for stem in stems:
            found = occurrences[stem]
            self.emit(
                stem, f"df={document_count(found)}",
                *(document.reference(token) for document, token in found),
            )

    def search(self, arguments):
        items = [classify(lexeme) for lexeme in LEXEME_PATTERN.findall(arguments[0])]
        stem_sets = {
            document.number: self.stem_set(document) for document in self.documents.values()
        }
        canonical, matches = QueryParser(items, stem_sets).parse()
        for kind, spelling in items:
            if kind == "term" and spelling in self.stopwords:
                raise CommandError(f"STOPWORD {spelling}")
        self.emit("SEARCH", canonical, f"count={len(matches)}", *sorted(matches))

    def phrase(self, arguments):
        words = [word_argument(argument) for argument in arguments]
        if all(word in self.stopwords for word in words):
            raise CommandError("STOPWORDS ONLY")
        targets = ["?" if word in self.stopwords else porter_stem(word) for word in words]
        matches = []
        for document in self.ordered_documents():
            tokens = document.tokens
            for start in range(len(tokens) - len(targets) + 1):
                if all(
                    self.token_matches(tokens[start + offset], target)
                    for offset, target in enumerate(targets)
                ):
                    matches.append(document.reference(tokens[start]))
        phrase_text = " ".join(targets)
        self.emit(f'PHRASE "{phrase_text}"', f"matches={len(matches)}", *matches)

    def near(self, arguments):
        first = self.term_argument(arguments[0])
        second = self.term_argument(arguments[1])
        limit = number_argument(arguments[2], 1, MAX_COUNT)
        found = []
        for document in self.ordered_documents():
            distance = closest_distance(
                self.stem_positions(document, first),
                self.stem_positions(document, second),
                first == second,
            )
            if distance is not None and distance <= limit:
                found.append(f"{document.number}:{distance}")
        self.emit("NEAR", first, second, limit, f"count={len(found)}", *found)

    def top(self, arguments):
        limit = number_argument(arguments[0], 1, MAX_COUNT)
        if len(arguments) == 2:
            document = self.document_argument(arguments[1])
            counts = self.term_frequencies(document)
            header = f"TOP {limit} doc={document.number}"
        else:
            counts = self.total_frequencies()
            header = f"TOP {limit}"
        ranked = sorted(counts.items(), key=by_count)[:limit]
        self.emit(header, *(f"{stem}:{count}" for stem, count in ranked))

    def kwic(self, arguments):
        stem = self.term_argument(arguments[0])
        found = self.occurrence_map().get(stem, [])
        self.emit("KWIC", stem, f"count={len(found)}")
        for document, token in found:
            text = document.lines[token.line - 1]
            before = text[max(0, token.start - KWIC_WIDTH):token.start].rjust(KWIC_WIDTH)
            after = text[token.end:token.end + KWIC_WIDTH].ljust(KWIC_WIDTH)
            self.emit(f"|{before}[{token.text}]{after}|", document.reference(token))

    def term_frequency(self, arguments):
        document = self.document_argument(arguments[0])
        stem = self.term_argument(arguments[1])
        self.emit("TF", document.number, stem, self.term_frequencies(document)[stem])

    def document_frequency(self, arguments):
        stem = self.term_argument(arguments[0])
        found = self.occurrence_map().get(stem, [])
        self.emit("DF", stem, document_count(found))

    def variants(self, arguments):
        stem = self.term_argument(arguments[0])
        found = self.occurrence_map().get(stem, [])
        forms = Counter(token.form for _, token in found)
        self.emit(
            "VARIANTS", stem, f"count={len(forms)}",
            *(f"{form}:{count}" for form, count in sorted(forms.items())),
        )

    def similar(self, arguments):
        document = self.document_argument(arguments[0])
        limit = number_argument(arguments[1], 1, MAX_COUNT)
        stems = self.stem_set(document)
        scores = []
        for other in self.documents.values():
            if other is document:
                continue
            other_stems = self.stem_set(other)
            union = len(stems | other_stems)
            score = Fraction(len(stems & other_stems), union) if union else Fraction(0)
            scores.append((score, other.number))
        scores.sort(key=lambda entry: (-entry[0], entry[1]))
        self.emit(
            "SIMILAR", document.number,
            *(
                f"{number}:{score.numerator}/{score.denominator}"
                for score, number in scores[:limit]
            ),
        )

    def rank(self, arguments):
        limit = number_argument(arguments[0], 1, MAX_COUNT)
        query = {self.term_argument(argument) for argument in arguments[1:]}
        ranked = []
        for document in self.documents.values():
            counts = self.term_frequencies(document)
            matched = sum(counts[stem] > 0 for stem in query)
            total = sum(counts[stem] for stem in query)
            if matched > 0:
                ranked.append((matched, total, document.number))
        ranked.sort(key=lambda entry: (-entry[0], -entry[1], entry[2]))
        self.emit(
            f"RANK count={len(ranked)}",
            *(f"{number}:{matched}:{total}" for matched, total, number in ranked[:limit]),
        )

    def info(self, arguments):
        document = self.document_argument(arguments[0])
        counts = self.term_frequencies(document)
        if counts:
            stem, count = min(counts.items(), key=by_count)
            top = f"{stem}:{count}"
        else:
            top = "-"
        self.emit(
            "INFO", document.number, f"lines={len(document.lines)}",
            f"tokens={len(document.tokens)}", f"indexed={counts.total()}",
            f"stems={len(counts)}", f"top={top}",
        )

    def show_line(self, arguments):
        document = self.document_argument(arguments[0])
        line_number = number_argument(arguments[1], 1, MAX_LINE_NUMBER)
        if line_number > len(document.lines):
            raise CommandError(f"NO LINE {document.number}:{line_number}")
        tokens = document.line_tokens(line_number)
        self.emit(
            f"LINE {document.number}:{line_number}", f"tokens={len(tokens)}",
            *(self.describe_token(token) for token in tokens),
        )

    def stats(self, arguments):
        documents = self.documents.values()
        self.emit(
            "STATS", f"docs={len(documents)}",
            f"lines={sum(len(document.lines) for document in documents)}",
            f"tokens={sum(len(document.tokens) for document in documents)}",
            f"indexed={sum(len(self.indexed_tokens(document)) for document in documents)}",
            f"stems={len(self.total_frequencies())}", f"stopwords={len(self.stopwords)}",
        )

    def stop(self, arguments):
        word = word_argument(arguments[0])
        if word in self.stopwords:
            raise CommandError(f"ALREADY STOPWORD {word}")
        self.stopwords.add(word)
        self.emit("STOP", word, f"unindexed={self.form_count(word)}")

    def unstop(self, arguments):
        word = word_argument(arguments[0])
        if word not in self.stopwords:
            raise CommandError(f"NOT STOPWORD {word}")
        self.stopwords.remove(word)
        self.emit("UNSTOP", word, f"indexed={self.form_count(word)}")

    def append(self, arguments):
        number = number_argument(arguments[0], 1, MAX_DOCUMENT_NUMBER)
        created = number not in self.documents
        document = self.add_document(number) if created else self.documents[number]
        tokens = document.add_line(arguments[1])
        indexed = sum(self.is_indexed(token) for token in tokens)
        self.emit(
            "APPEND", number, f"line={len(document.lines)}", f"tokens={len(tokens)}",
            f"indexed={indexed}", f"new={yes_no(created)}",
        )

    def delete(self, arguments):
        document = self.document_argument(arguments[0])
        del self.documents[document.number]
        self.emit(
            "DELETE", document.number, f"lines={len(document.lines)}",
            f"tokens={len(document.tokens)}",
        )

    def execute(self, line):
        name, separator, rest = line.partition(" ")
        try:
            if name not in self.handlers:
                raise CommandError(f"UNKNOWN COMMAND {name}")
            minimum, maximum, handler = self.handlers[name]
            arguments = split_arguments(name, rest) if separator else []
            if not minimum <= len(arguments) <= maximum:
                raise CommandError(f"BAD ARGUMENTS {name}")
            handler(arguments)
        except CommandError as error:
            self.emit("ERROR", error)


def main():
    lines = sys.stdin.read().splitlines()
    engine = SearchEngine(set(lines[0].split()[1:]))
    index = 1
    while lines[index].startswith("DOC "):
        document = engine.add_document(int(lines[index][4:]))
        index += 1
        while lines[index] != "ENDDOC":
            document.add_line(lines[index])
            index += 1
        index += 1
    for line in lines[index:]:
        if line == "END":
            break
        engine.execute(line)
    sys.stdout.write("\n".join(engine.output) + "\n")


if __name__ == "__main__":
    main()
