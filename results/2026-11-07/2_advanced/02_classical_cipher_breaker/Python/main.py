import os
from itertools import permutations

import analysis
import playfair
import substitution
import transposition
from scoring import ALPHABET, is_letter, letter_string, letter_value, parse_weights
from substitution import AFFINE_MULTIPLIERS


COMMANDS = ("ENCRYPT", "DECRYPT", "BREAK", "ANALYZE", "COMPARE", "IDENTIFY")
NAMING_COMMANDS = ("ENCRYPT", "DECRYPT", "BREAK")
CIPHERS = ("caesar", "affine", "vigenere", "autokey", "playfair", "railfence", "columnar")
SUBSTITUTION_CIPHERS = ("caesar", "affine", "vigenere", "autokey")
MONOGRAM_SCORED_CIPHERS = ("caesar", "affine")
CIPHER_FUNCTIONS = {
    "caesar": (substitution.caesar_encrypt, substitution.caesar_decrypt),
    "affine": (substitution.affine_encrypt, substitution.affine_decrypt),
    "vigenere": (substitution.vigenere_encrypt, substitution.vigenere_decrypt),
    "autokey": (substitution.autokey_encrypt, substitution.autokey_decrypt),
    "playfair": (playfair.encrypt, playfair.decrypt),
    "railfence": (transposition.rail_fence_encrypt, transposition.rail_fence_decrypt),
    "columnar": (transposition.columnar_encrypt, transposition.columnar_decrypt),
}
NUMBER_KEY_RANGES = {"caesar": (0, 25), "railfence": (2, 20)}
WORD_KEY_LENGTHS = {"vigenere": 20, "autokey": 20, "playfair": 25}
COLUMNAR_KEY_LENGTHS = (2, 9)
TOP_OPTION = (1, 20, 5)
BREAK_OPTIONS = {
    "caesar": {"TOP": TOP_OPTION},
    "affine": {"TOP": TOP_OPTION},
    "vigenere": {
        "TOP": TOP_OPTION,
        "MAXLEN": (2, 20, 10),
        "IOC": (1, 100000, 6000),
        "KASISKI": (1, 100, 60),
        "REFINE": (0, 10, 5),
    },
    "autokey": {"TOP": TOP_OPTION, "MAXLEN": (1, 20, 8)},
    "railfence": {"TOP": TOP_OPTION, "MAXRAILS": (2, 20, 10)},
    "columnar": {"TOP": TOP_OPTION, "MAXLEN": (2, 6, 6)},
    "playfair": {"TOP": TOP_OPTION, "KEYS": None},
}
ANALYZE_OPTIONS = {"MAXLEN": (2, 20, 10)}
IDENTIFY_OPTIONS = {"KEYS": None}
FAMILY_CIPHERS = {
    "playfair": ("playfair",),
    "transposition": ("railfence", "columnar"),
    "monoalphabetic": ("affine",),
    "polyalphabetic": ("vigenere", "autokey"),
}
DIGITS = "0123456789"
NAME_CHARACTERS = "abcdefghijklmnopqrstuvwxyz" + DIGITS + "_"
MAX_NAME_LENGTH = 16
MAX_KEY_DIGITS = 2
MAX_OPTION_DIGITS = 6
MIN_BREAK_LETTERS = 40
PREVIEW_LENGTH = 40
TOP_LIST_LENGTH = 10
GROUP_SIZE = 5
GROUPS_PER_LINE = 10
FAMILY_IOC = 5500
FAMILY_MONO_AVERAGE = 44


class JobError(Exception):
    pass


def is_valid_name(text):
    return (
        1 <= len(text) <= MAX_NAME_LENGTH
        and all(character in NAME_CHARACTERS for character in text)
    )


def is_digit_string(text, max_length):
    return 1 <= len(text) <= max_length and all(character in DIGITS for character in text)


def encrypt(cipher, key, text):
    return CIPHER_FUNCTIONS[cipher][0](text, key)


def decrypt(cipher, key, text):
    return CIPHER_FUNCTIONS[cipher][1](text, key)


def key_notation(cipher, key):
    if cipher == "affine":
        return f"{key[0]},{key[1]}"
    return str(key)


def number_list(numbers):
    return ",".join(str(number) for number in numbers)


def count_list(entries):
    return " ".join(f"{item}:{count}" for item, count in entries)


def as_suffix(new_name):
    return "" if new_name is None else f" as={new_name}"


def group_form(letters):
    groups = [letters[start:start + GROUP_SIZE] for start in range(0, len(letters), GROUP_SIZE)]
    return [
        " ".join(groups[start:start + GROUPS_PER_LINE])
        for start in range(0, len(groups), GROUPS_PER_LINE)
    ]


def solution_lines(cipher, key, text, letters):
    if cipher in SUBSTITUTION_CIPHERS:
        return decrypt(cipher, key, text).split("\n")
    return group_form(decrypt(cipher, key, letters))


def playfair_key_list(text):
    keys = []
    runs = "".join(character if is_letter(character) else " " for character in text).split()
    for run in runs:
        key = run.upper().replace("J", "I")
        if key not in keys:
            keys.append(key)
    return keys


def split_new_name(command, words):
    if command in NAMING_COMMANDS and len(words) >= 5 and words[-2] == "AS":
        if not is_valid_name(words[-1]):
            raise JobError("bad syntax")
        return words[:-2], words[-1]
    return words, None


def check_word_count(command, words):
    count = len(words)
    if command in ("ENCRYPT", "DECRYPT"):
        valid = count == 4
    elif command == "BREAK":
        valid = count >= 3
    elif command in ("ANALYZE", "IDENTIFY"):
        valid = count in (2, 3)
    else:
        valid = count == 3
    if not valid:
        raise JobError("bad syntax")


def require_cipher(word):
    if word not in CIPHERS:
        raise JobError(f"unknown cipher {word}")


def parse_key(cipher, word):
    if cipher in NUMBER_KEY_RANGES:
        minimum, maximum = NUMBER_KEY_RANGES[cipher]
        if is_digit_string(word, MAX_KEY_DIGITS) and minimum <= int(word) <= maximum:
            return int(word)
    elif cipher == "affine":
        parts = word.split(",")
        if len(parts) == 2 and all(is_digit_string(part, MAX_KEY_DIGITS) for part in parts):
            multiplier, offset = int(parts[0]), int(parts[1])
            if multiplier in AFFINE_MULTIPLIERS and offset <= 25:
                return multiplier, offset
    elif cipher == "columnar":
        minimum, maximum = COLUMNAR_KEY_LENGTHS
        valid = all(is_letter(character) or character in DIGITS for character in word)
        if minimum <= len(word) <= maximum and valid:
            return word.upper()
    else:
        valid = all(is_letter(character) for character in word)
        if 1 <= len(word) <= WORD_KEY_LENGTHS[cipher] and valid:
            key = word.upper()
            return key.replace("J", "I") if cipher == "playfair" else key
    raise JobError(f"bad key {word}")


def parse_options(words, allowed):
    options = {}
    for word in words:
        name, separator, value = word.partition("=")
        if not separator or name not in allowed or name in options:
            raise JobError(f"bad option {word}")
        if name == "KEYS":
            if not is_valid_name(value):
                raise JobError(f"bad option {word}")
            options[name] = value
        else:
            minimum, maximum, _ = allowed[name]
            if not is_digit_string(value, MAX_OPTION_DIGITS):
                raise JobError(f"bad option {word}")
            if not minimum <= int(value) <= maximum:
                raise JobError(f"bad option {word}")
            options[name] = int(value)
    for name, limits in allowed.items():
        if name not in options:
            options[name] = None if limits is None else limits[2]
    return options


def default_options(cipher):
    return parse_options([], BREAK_OPTIONS[cipher])


def cipher_family(shaped, ioc, mono_average):
    if shaped:
        return "playfair"
    if ioc >= FAMILY_IOC and mono_average >= FAMILY_MONO_AVERAGE:
        return "transposition"
    if ioc >= FAMILY_IOC:
        return "monoalphabetic"
    return "polyalphabetic"


class Period:
    def __init__(self, length, indices, kasiski):
        self.length = length
        self.indices = indices
        self.average = sum(indices) // length
        self.kasiski = kasiski

    def line(self):
        return (
            f"L={self.length} ioc={self.average} kasiski={self.kasiski} "
            f"cols={number_list(self.indices)}"
        )


class PeriodProfile:
    def __init__(self, letters, max_length):
        self.repeats = analysis.repeated_trigrams(letters)
        gaps = [gap for repeat in self.repeats for gap in repeat.gaps]
        self.gap_count = len(gaps)
        self.periods = []
        for length in range(1, max_length + 1):
            kasiski = sum(1 for gap in gaps if gap % length == 0)
            indices = analysis.column_indices(letters, length)
            self.periods.append(Period(length, indices, kasiski))

    def period(self, length):
        return self.periods[length - 1]

    def kasiski_length(self, threshold):
        if self.gap_count == 0:
            return None
        found = None
        for period in self.periods[1:]:
            if 100 * period.kasiski >= threshold * self.gap_count:
                found = period.length
        return found

    def key_length(self, options):
        kasiski_length = self.kasiski_length(options["KASISKI"])
        if kasiski_length is not None and self.period(kasiski_length).average >= options["IOC"]:
            return kasiski_length, "kasiski"
        for period in self.periods:
            if period.average >= options["IOC"]:
                return period.length, "ioc"
        best = max(self.periods, key=lambda period: period.average)
        return best.length, "maxioc"

    def lines(self):
        lines = [period.line() for period in self.periods]
        lines.append(f"kasiski repeats={len(self.repeats)} spacings={self.gap_count}")
        for repeat in self.repeats:
            lines.append(
                f"{repeat.trigram} at={number_list(repeat.positions)} "
                f"gaps={number_list(repeat.gaps)} gcd={repeat.gcd}"
            )
        return lines


class Candidate:
    def __init__(self, key, plaintext, score):
        self.key = key
        self.plaintext = plaintext
        self.score = score


class BreakResult:
    def __init__(self, cipher, candidates):
        self.cipher = cipher
        self.candidates = candidates
        self.key = candidates[0].key
        self.score = candidates[0].score
        self.profile = None
        self.length = 0
        self.method = None
        self.passes = 0
        self.changes = 0

    def margin(self):
        if len(self.candidates) < 2:
            return 0
        return self.candidates[0].score - self.candidates[1].score


class CipherDesk:
    def __init__(self, weights, messages):
        self.weights = weights
        self.messages = messages
        self.job_count = 0
        self.ok_counts = dict.fromkeys(COMMANDS, 0)
        self.error_counts = dict.fromkeys(COMMANDS, 0)
        self.result_lines = []
        self.candidate_lines = []
        self.analysis_lines = []

    def message_text(self, name):
        if name not in self.messages:
            raise JobError(f"unknown message {name}")
        return "\n".join(self.messages[name])

    def require_unused(self, new_name):
        if new_name is not None and new_name in self.messages:
            raise JobError(f"duplicate message {new_name}")

    def store(self, new_name, lines):
        if new_name is not None:
            self.messages[new_name] = lines

    def key_list(self, options):
        name = options.get("KEYS")
        if name is None:
            return None
        return playfair_key_list(self.message_text(name))

    def score(self, cipher, plaintext):
        if cipher in MONOGRAM_SCORED_CIPHERS:
            return self.weights.monogram_fitness(plaintext)
        return self.weights.bigram_fitness(plaintext)

    def vigenere_score(self, letters, key):
        return self.weights.bigram_fitness(substitution.vigenere_decrypt(letters, key))

    def vigenere_shift(self, column):
        counts = analysis.letter_counts(column)
        fitness = []
        for shift in range(26):
            total = 0
            for value, count in enumerate(counts):
                total += count * self.weights.monograms[(value - shift) % 26]
            fitness.append(total)
        return fitness.index(max(fitness))

    def autokey_shift(self, column):
        values = [letter_value(letter) for letter in column]
        fitness = []
        for shift in range(26):
            previous = shift
            total = 0
            for value in values:
                previous = (value - previous) % 26
                total += self.weights.monograms[previous]
            fitness.append(total)
        return fitness.index(max(fitness))

    def column_key(self, cipher, letters, length):
        key = ""
        for column in analysis.columns(letters, length):
            if cipher == "vigenere":
                key += ALPHABET[self.vigenere_shift(column)]
            else:
                key += ALPHABET[self.autokey_shift(column)]
        return key

    def candidate_keys(self, cipher, letters, options, key_list):
        if cipher == "caesar":
            return list(range(26))
        if cipher == "affine":
            return [
                (multiplier, offset)
                for multiplier in AFFINE_MULTIPLIERS
                for offset in range(26)
            ]
        if cipher == "railfence":
            return list(range(2, options["MAXRAILS"] + 1))
        if cipher == "columnar":
            return [
                "".join(order)
                for width in range(2, options["MAXLEN"] + 1)
                for order in permutations(DIGITS[1:width + 1])
            ]
        if cipher == "playfair":
            return key_list
        return [
            self.column_key(cipher, letters, length)
            for length in range(1, options["MAXLEN"] + 1)
        ]

    def break_cipher(self, cipher, letters, options, key_list):
        candidates = []
        for key in self.candidate_keys(cipher, letters, options, key_list):
            plaintext = decrypt(cipher, key, letters)
            candidates.append(Candidate(key, plaintext, self.score(cipher, plaintext)))
        ranked = sorted(candidates, key=lambda candidate: -candidate.score)
        result = BreakResult(cipher, ranked)
        if cipher == "vigenere":
            self.refine_vigenere(result, letters, candidates, options)
        return result

    def refine_vigenere(self, result, letters, candidates, options):
        profile = PeriodProfile(letters, options["MAXLEN"])
        length, method = profile.key_length(options)
        key = candidates[length - 1].key
        reference = candidates[length - 1].score
        passes = 0
        changes = 0
        while passes < options["REFINE"]:
            passes += 1
            changed = False
            for index in range(length):
                scores = [
                    self.vigenere_score(letters, key[:index] + letter + key[index + 1:])
                    for letter in ALPHABET
                ]
                best = max(scores)
                if best > reference:
                    key = key[:index] + ALPHABET[scores.index(best)] + key[index + 1:]
                    reference = best
                    changes += 1
                    changed = True
            if not changed:
                break
        result.profile = profile
        result.length = length
        result.method = method
        result.key = key
        result.score = reference
        result.passes = passes
        result.changes = changes

    def run(self, line):
        self.job_count += 1
        number = self.job_count
        words = line.split(" ")
        command = words[0]
        if command not in COMMANDS:
            self.result_lines.append(f"JOB {number} ERROR unknown command")
            return
        try:
            self.execute(number, command, words)
        except JobError as error:
            self.result_lines.append(f"JOB {number} ERROR {error}")
            self.error_counts[command] += 1
        else:
            self.ok_counts[command] += 1

    def execute(self, number, command, words):
        words, new_name = split_new_name(command, words)
        check_word_count(command, words)
        if command in ("ENCRYPT", "DECRYPT"):
            self.transform(number, command, words, new_name)
        elif command == "BREAK":
            self.break_message(number, words, new_name)
        elif command == "ANALYZE":
            self.analyze(number, words)
        elif command == "COMPARE":
            self.compare(number, words)
        else:
            self.identify(number, words)

    def transform(self, number, command, words, new_name):
        cipher, key_word, source = words[1:]
        require_cipher(cipher)
        key = parse_key(cipher, key_word)
        text = self.message_text(source)
        self.require_unused(new_name)
        letters = letter_string(text)
        if not letters:
            raise JobError("no letters")
        if command == "DECRYPT" and cipher == "playfair":
            if not playfair.is_valid_ciphertext(letters):
                raise JobError("bad playfair text")
        operation = encrypt if command == "ENCRYPT" else decrypt
        if cipher in SUBSTITUTION_CIPHERS:
            lines = operation(cipher, key, text).split("\n")
        else:
            lines = group_form(operation(cipher, key, letters))
        letter_count = sum(len(letter_string(line)) for line in lines)
        self.result_lines.append(
            f"JOB {number} {command} {cipher} key={key_notation(cipher, key)} "
            f"source={source} letters={letter_count} lines={len(lines)}{as_suffix(new_name)}"
        )
        self.result_lines.extend(lines)
        self.store(new_name, lines)

    def break_message(self, number, words, new_name):
        cipher = words[1]
        require_cipher(cipher)
        source = words[2]
        options = parse_options(words[3:], BREAK_OPTIONS[cipher])
        if cipher == "playfair" and options["KEYS"] is None:
            raise JobError("missing option KEYS")
        text = self.message_text(source)
        key_list = self.key_list(options)
        self.require_unused(new_name)
        letters = letter_string(text)
        if len(letters) < MIN_BREAK_LETTERS:
            raise JobError("text too short")
        if cipher == "playfair":
            if not playfair.is_valid_ciphertext(letters):
                raise JobError("bad playfair text")
            if not key_list:
                raise JobError("empty key list")
        result = self.break_cipher(cipher, letters, options, key_list)
        lines = solution_lines(cipher, result.key, text, letters)
        self.result_lines.append(
            f"JOB {number} BREAK {cipher} source={source} "
            f"key={key_notation(cipher, result.key)} score={result.score} "
            f"lines={len(lines)}{as_suffix(new_name)}"
        )
        self.result_lines.extend(lines)
        self.store(new_name, lines)
        self.candidate_lines.append(
            f"JOB {number} BREAK {cipher} source={source} "
            f"tried={len(result.candidates)} margin={result.margin()}"
        )
        for rank, candidate in enumerate(result.candidates[:options["TOP"]], 1):
            self.candidate_lines.append(
                f"{rank} {key_notation(cipher, candidate.key)} {candidate.score} "
                f"{candidate.plaintext[:PREVIEW_LENGTH]}"
            )
        if cipher == "vigenere":
            self.analysis_lines.extend(vigenere_report(number, source, letters, result))
        elif cipher == "playfair":
            self.analysis_lines.extend(playfair_report(number, source, letters, result))

    def analyze(self, number, words):
        source = words[1]
        options = parse_options(words[2:], ANALYZE_OPTIONS)
        letters = letter_string(self.message_text(source))
        count = len(letters)
        if count < MIN_BREAK_LETTERS:
            raise JobError("text too short")
        doubles = [index for index in range(count - 1) if letters[index] == letters[index + 1]]
        pair_doubles = sum(1 for index in doubles if index % 2 == 0)
        report = [
            f"JOB {number} ANALYZE source={source}",
            f"letters={count}",
            f"ioc={analysis.index_of_coincidence(letters)} "
            f"mono={self.weights.monogram_fitness(letters)} "
            f"bigram={self.weights.bigram_fitness(letters)}",
            f"doubles={len(doubles)} pair_doubles={pair_doubles} distinct={len(set(letters))}",
        ]
        for letter, occurrences in zip(ALPHABET, analysis.letter_counts(letters)):
            report.append(f"{letter} {occurrences} {analysis.percentage(occurrences, count)}")
        bigrams = [letters[index:index + 2] for index in range(count - 1)]
        report.append("bigrams " + count_list(analysis.top_counts(bigrams, TOP_LIST_LENGTH)))
        report.extend(PeriodProfile(letters, options["MAXLEN"]).lines())
        self.result_lines.append(f"JOB {number} ANALYZE source={source} letters={count}")
        self.analysis_lines.extend(report)

    def compare(self, number, words):
        first_name, second_name = words[1:]
        first = letter_string(self.message_text(first_name))
        second = letter_string(self.message_text(second_name))
        prefix = f"JOB {number} COMPARE {first_name} {second_name}"
        if first == second:
            self.result_lines.append(f"{prefix} equal letters={len(first)}")
            return
        shared = min(len(first), len(second))
        mismatches = [index + 1 for index in range(shared) if first[index] != second[index]]
        first_mismatch = mismatches[0] if mismatches else shared + 1
        self.result_lines.append(
            f"{prefix} differ letters={len(first)},{len(second)} "
            f"first={first_mismatch} mismatches={len(mismatches)}"
        )

    def identify(self, number, words):
        source = words[1]
        options = parse_options(words[2:], IDENTIFY_OPTIONS)
        text = self.message_text(source)
        key_list = self.key_list(options)
        letters = letter_string(text)
        count = len(letters)
        if count < MIN_BREAK_LETTERS:
            raise JobError("text too short")
        ioc = analysis.index_of_coincidence(letters)
        mono_average = self.weights.monogram_fitness(letters) // count
        distinct = len(set(letters))
        shaped = count % 2 == 0 and "J" not in letters and playfair.is_valid_ciphertext(letters)
        family = cipher_family(shaped, ioc, mono_average)
        if family == "playfair" and key_list is not None and not key_list:
            raise JobError("empty key list")
        tried = []
        if family != "playfair" or key_list is not None:
            for cipher in FAMILY_CIPHERS[family]:
                tried.append(self.break_cipher(cipher, letters, default_options(cipher), key_list))
        report = [
            f"JOB {number} IDENTIFY source={source}",
            f"letters={count} ioc={ioc} mono_avg={mono_average} distinct={distinct} "
            f"shape={'yes' if shaped else 'no'}",
            f"family={family}",
        ]
        for result in tried:
            report.append(
                f"try {result.cipher} key={key_notation(result.cipher, result.key)} "
                f"score={result.score}"
            )
        header = f"JOB {number} IDENTIFY source={source} family={family}"
        if not tried:
            self.result_lines.append(header)
            self.analysis_lines.extend(report)
            return
        chosen = max(tried, key=lambda result: result.score)
        cipher, key = chosen.cipher, chosen.key
        if cipher == "affine" and key[0] == 1:
            cipher, key = "caesar", key[1]
        lines = solution_lines(cipher, key, text, letters)
        self.result_lines.append(
            f"{header} cipher={cipher} key={key_notation(cipher, key)} "
            f"score={chosen.score} lines={len(lines)}"
        )
        self.result_lines.extend(lines)
        report.append(f"choice {cipher}")
        self.analysis_lines.extend(report)

    def finish(self):
        for command in COMMANDS:
            self.result_lines.append(
                f"TOTAL {command} ok={self.ok_counts[command]} "
                f"errors={self.error_counts[command]}"
            )
        ok = sum(self.ok_counts.values())
        self.result_lines.append(
            f"SUMMARY jobs={self.job_count} ok={ok} errors={self.job_count - ok} "
            f"messages={len(self.messages)}"
        )


def vigenere_report(number, source, letters, result):
    lines = [f"JOB {number} BREAK vigenere source={source}", f"letters={len(letters)}"]
    lines.extend(result.profile.lines())
    lines.append(f"decision length={result.length} method={result.method}")
    lines.append(f"refine passes={result.passes} changes={result.changes} key={result.key}")
    return lines


def playfair_report(number, source, letters, result):
    pairs = playfair.ciphertext_pairs(letters)
    square = playfair.build_square(result.key)
    rows = [square[start:start + playfair.SIZE] for start in range(0, len(square), playfair.SIZE)]
    return [
        f"JOB {number} BREAK playfair source={source}",
        f"letters={len(letters)}",
        f"digraphs pairs={len(pairs)} distinct={len(set(pairs))}",
        "top " + count_list(analysis.top_counts(pairs, TOP_LIST_LENGTH)),
        "square " + " ".join(rows),
    ]


def parse_messages(text):
    messages = {}
    name = None
    body = []
    for line in text.split("\n"):
        if name is None:
            if line.startswith("MESSAGE "):
                name = line[len("MESSAGE "):]
                body = []
        elif line == "END":
            messages[name] = body
            name = None
        else:
            body.append(line)
    return messages


def job_lines(text):
    return [line for line in text.split("\n") if line and not line.startswith("#")]


def read_file(path):
    with open(path) as handle:
        return handle.read()


def write_file(path, lines):
    with open(path, "w") as handle:
        handle.write("".join(line + "\n" for line in lines))


def main():
    weights = parse_weights(read_file("input/weights.txt"))
    desk = CipherDesk(weights, parse_messages(read_file("input/messages.txt")))
    for line in job_lines(read_file("input/jobs.txt")):
        desk.run(line)
    desk.finish()
    os.makedirs("output", exist_ok=True)
    write_file("output/results.txt", desk.result_lines)
    write_file("output/candidates.txt", desk.candidate_lines)
    write_file("output/analysis.txt", desk.analysis_lines)


if __name__ == "__main__":
    main()
