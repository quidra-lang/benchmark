import os
from functools import cmp_to_key

from filler import Attempt, GridState
from grid import EMPTY, Grid
from render import decimal, grid_lines, list_line, number_lines
from slots import Layout, find_short_run
from word_index import (
    UPPERCASE, WordIndex, clue_line_error, is_valid_integer, is_valid_word, matches,
    word_line_error,
)


INPUT_DIR = "input"
OUTPUT_DIR = "output"
NAME_CHARACTERS = "abcdefghijklmnopqrstuvwxyz0123456789_"
MAX_NAME_LENGTH = 20
SYMMETRIES = ("rot180", "mirror", "none")
CHECKED_SYMMETRIES = ("rot180", "mirror")
MAX_BUDGET = 100000
MAX_MIN_SCORE = 100
MIN_SIDE = 3
MAX_SIDE = 15
GRID_SYMBOLS = ".#" + UPPERCASE
SCORE_BANDS = ((1, 20), (21, 40), (41, 60), (61, 80), (81, 100))
TOP_COUNT = 5
RARE_COUNT = 5
HIGHLIGHT_COUNT = 3
LETTER_POINTS = {
    "A": 1, "B": 3, "C": 3, "D": 2, "E": 1, "F": 4, "G": 2, "H": 4, "I": 1,
    "J": 8, "K": 5, "L": 1, "M": 3, "N": 1, "O": 1, "P": 3, "Q": 10, "R": 1,
    "S": 1, "T": 1, "U": 1, "V": 4, "W": 4, "X": 8, "Y": 4, "Z": 10,
}


def read_lines(name):
    with open(os.path.join(INPUT_DIR, name)) as handle:
        return handle.read().split("\n")[:-1]


def write_lines(name, lines):
    with open(os.path.join(OUTPUT_DIR, name), "w") as handle:
        handle.write("".join(line + "\n" for line in lines))


def write_paragraphs(name, paragraphs):
    lines = []
    for paragraph in paragraphs:
        if lines:
            lines.append("")
        lines.extend(paragraph)
    write_lines(name, lines)


def is_ignored(line):
    return line == "" or line.startswith("#")


def read_settings(lines):
    settings = {}
    for line in lines:
        if not is_ignored(line):
            key, value = line.split(" ")
            settings[key] = value if key == "symmetry" else int(value)
    return settings


def is_valid_name(name):
    if not 1 <= len(name) <= MAX_NAME_LENGTH:
        return False
    return all(character in NAME_CHARACTERS for character in name)


def is_valid_row(row, width):
    if not MIN_SIDE <= len(row) <= MAX_SIDE or len(row) != width:
        return False
    return all(symbol in GRID_SYMBOLS for symbol in row)


def cell_text(grid, cell):
    row, column = grid.location(cell)
    return f"{row},{column}"


def joined(items, separator):
    return separator.join(items) if items else "-"


class WordList:
    def __init__(self, lines):
        self.line_count = len(lines)
        self.scores = {}
        self.first_lines = {}
        self.invalid = []
        self.duplicates = []
        for number, line in enumerate(lines, 1):
            reason = word_line_error(line)
            if reason is not None:
                self.invalid.append((number, reason))
                continue
            word, score = line.split(" ")
            if word in self.scores:
                self.duplicates.append((number, word, self.first_lines[word]))
            else:
                self.scores[word] = int(score)
                self.first_lines[word] = number
        self.index = WordIndex(self.scores)

    def length_lines(self):
        lines = []
        for length in sorted(self.index.by_length):
            words = self.index.by_length[length]
            total = sum(self.scores[word] for word in words)
            best = words[0]
            lines.append(
                f"length {length} words={len(words)} average={decimal(total, len(words), 2)} "
                f"best={best}:{self.scores[best]}"
            )
        return lines

    def band_line(self):
        parts = []
        for low, high in SCORE_BANDS:
            count = sum(1 for score in self.scores.values() if low <= score <= high)
            parts.append(f"{low}-{high}={count}")
        return "bands " + " ".join(parts)

    def rare_letters_line(self):
        counts = []
        for letter in UPPERCASE:
            counts.append((sum(1 for word in self.scores if letter in word), letter))
        counts.sort()
        return "rare_letters " + " ".join(
            f"{letter}:{count}" for count, letter in counts[:RARE_COUNT]
        )

    def report_lines(self):
        lines = [
            f"WORDLIST lines={self.line_count} valid={len(self.scores)} "
            f"invalid={len(self.invalid)} duplicates={len(self.duplicates)}"
        ]
        for number, reason in self.invalid:
            lines.append(f"invalid {number} {reason}")
        for number, word, first in self.duplicates:
            lines.append(f"duplicate {number} {word} first={first}")
        lines.extend(self.length_lines())
        lines.append(self.band_line())
        top = self.index.ranked[:TOP_COUNT]
        lines.append("top " + " ".join(f"{word}:{self.scores[word]}" for word in top))
        lines.append(self.rare_letters_line())
        return lines


class Clue:
    def __init__(self, word, number, text):
        self.word = word
        self.number = number
        self.text = text
        self.uses = 0


class ClueBook:
    def __init__(self, lines, scores):
        self.entries = 0
        self.added = 0
        self.invalid = []
        self.unknown = []
        self.clues = {}
        for number, line in enumerate(lines, 1):
            if is_ignored(line):
                continue
            self.entries += 1
            reason = clue_line_error(line)
            if reason is not None:
                self.invalid.append((number, reason))
                continue
            word, text = line.split("|")
            if word not in scores:
                self.unknown.append((number, word))
                continue
            word_clues = self.clues.setdefault(word, [])
            word_clues.append(Clue(word, len(word_clues) + 1, text))
            self.added += 1

    def choose(self, word):
        if word not in self.clues:
            return None
        clue = min(self.clues[word], key=lambda item: (item.uses, item.number))
        clue.uses += 1
        return clue.text

    def report_lines(self):
        lines = [
            f"CLUES entries={self.entries} valid={self.added} invalid={len(self.invalid)} "
            f"unknown={len(self.unknown)} words={len(self.clues)}"
        ]
        for number, reason in self.invalid:
            lines.append(f"clue_invalid {number} {reason}")
        for number, word in self.unknown:
            lines.append(f"clue_unknown {number} {word}")
        clues = [clue for word in sorted(self.clues) for clue in self.clues[word]]
        used = sum(1 for clue in clues if clue.uses >= 1)
        repeated = [clue for clue in clues if clue.uses >= 2]
        lines.append(
            f"CLUE_USE used={used} unused={len(clues) - used} repeated={len(repeated)}"
        )
        for clue in repeated:
            lines.append(f"repeated {clue.word} clue={clue.number} uses={clue.uses}")
        return lines


class Block:
    def __init__(self, name):
        self.name = name
        self.options = []
        self.rows = []


def split_blocks(lines):
    blocks = []
    block = None
    for line in lines:
        if block is None:
            if line.startswith("TEMPLATE "):
                block = Block(line[len("TEMPLATE "):])
        elif line == "END":
            blocks.append(block)
            block = None
        elif " " in line:
            block.options.append(line)
        else:
            block.rows.append(line)
    return blocks


class Template:
    def __init__(self, block, settings):
        self.name = block.name
        self.options = block.options
        self.rows = block.rows
        self.node_budget = settings["node_budget"]
        self.min_score = settings["min_score"]
        self.symmetry = settings["symmetry"]
        self.themes = []
        self.error = None
        self.grid = None
        self.layout = None
        self.initial = None
        self.theme_slots = []
        self.attempts = []
        self.final = None
        self.state = None
        self.chosen = []

    def process(self, earlier_names, index, clue_book, relax_step):
        self.error = self.check(earlier_names, index)
        if self.error is None:
            self.run_attempts(index, relax_step)
            self.choose_clues(clue_book)

    def read_options(self):
        seen = set()
        for number, line in enumerate(self.options, 1):
            key, _, value = line.partition(" ")
            if key == "theme":
                if not is_valid_word(value) or value in self.themes:
                    return number
                self.themes.append(value)
            elif key in seen or not self.apply_option(key, value):
                return number
            seen.add(key)
        return None

    def apply_option(self, key, value):
        if key == "node_budget" and is_valid_integer(value, 1, MAX_BUDGET):
            self.node_budget = int(value)
        elif key == "min_score" and is_valid_integer(value, 1, MAX_MIN_SCORE):
            self.min_score = int(value)
        elif key == "symmetry" and value in SYMMETRIES:
            self.symmetry = value
        else:
            return False
        return True

    def check(self, earlier_names, index):
        if not is_valid_name(self.name):
            return "bad name"
        if self.name in earlier_names:
            return "duplicate name"
        bad_option = self.read_options()
        if bad_option is not None:
            return f"bad option {bad_option}"
        if not MIN_SIDE <= len(self.rows) <= MAX_SIDE:
            return "bad height"
        for number, row in enumerate(self.rows, 1):
            if not is_valid_row(row, len(self.rows[0])):
                return f"bad row {number}"
        self.grid = Grid(self.rows)
        if self.symmetry != "none":
            cell = self.grid.asymmetric_cell(self.symmetry)
            if cell is not None:
                return f"asymmetric at {cell_text(self.grid, cell)}"
        components = self.grid.component_count()
        if components != 1:
            return f"disconnected components={components}"
        short_run = find_short_run(self.grid)
        if short_run is not None:
            cell, direction = short_run
            return f"short slot at {cell_text(self.grid, cell)} {direction}"
        self.layout = Layout(self.grid)
        orphan = self.layout.orphan_cell()
        if orphan is not None:
            return f"orphan cell {cell_text(self.grid, orphan)}"
        return self.place_themes(index)

    def fitting_slot(self, state, word):
        for slot in self.layout.slots:
            if state.words[slot.index] is not None or slot.length != len(word):
                continue
            if matches(word, state.pattern(slot)):
                return slot
        return None

    def place_themes(self, index):
        state = GridState(list(self.grid.cells), [None] * len(self.layout.slots))
        for number, theme in enumerate(self.themes, 1):
            if theme not in index.scores:
                return f"unknown theme {number}"
            slot = self.fitting_slot(state, theme)
            if slot is None:
                return f"theme {number} does not fit"
            state.assign(slot, theme)
            self.theme_slots.append(slot.index)
        self.initial = state
        return None

    def run_attempts(self, index, relax_step):
        min_score = self.min_score
        while True:
            attempt = Attempt(self.layout, index, self.initial, min_score, self.node_budget)
            attempt.run()
            self.attempts.append(attempt)
            if attempt.outcome == "filled" or relax_step < 1 or min_score <= 1:
                break
            min_score = max(min_score - relax_step, 1)
        self.final = attempt
        self.state = attempt.final_state()

    def choose_clues(self, clue_book):
        self.chosen = [None] * len(self.layout.slots)
        across = [slot for slot in self.layout.slots if slot.across]
        down = [slot for slot in self.layout.slots if not slot.across]
        for slot in across + down:
            word = self.state.words[slot.index]
            if word is not None:
                self.chosen[slot.index] = clue_book.choose(word)

    def is_filled(self):
        return self.error is None and self.final.outcome == "filled"

    def total_score(self, scores):
        return sum(scores[word] for word in self.state.words)

    def slot_count(self):
        return len(self.layout.slots)

    def entry(self, slot, scores):
        word = self.state.words[slot.index]
        return f"{slot.label}:{word}:{scores[word]}"

    def grid_paragraph(self):
        lines = [f"TEMPLATE {self.name}"]
        if self.error is not None:
            lines.append(f"error {self.error}")
            return lines
        lines.append(
            f"outcome={self.final.outcome} attempts={len(self.attempts)} "
            f"min_score={self.final.min_score}"
        )
        lines.extend(grid_lines(self.grid, self.state.letters))
        lines.append("numbers")
        lines.extend(number_lines(self.layout))
        return lines

    def clue_paragraph(self, scores):
        lines = [f"TEMPLATE {self.name}"]
        clued = 0
        missing = 0
        unfilled = 0
        for heading, across in (("ACROSS", True), ("DOWN", False)):
            group = [slot for slot in self.layout.slots if slot.across == across]
            if group:
                lines.append(heading)
            for slot in group:
                word = self.state.words[slot.index]
                if word is None:
                    unfilled += 1
                    lines.append(list_line(slot, "(unfilled)", self.state.pattern(slot), "-", False))
                    continue
                clue = self.chosen[slot.index]
                if clue is None:
                    missing += 1
                    clue = "(no clue)"
                else:
                    clued += 1
                theme = slot.index in self.theme_slots
                lines.append(list_line(slot, clue, word, scores[word], theme))
        lines.append(f"clued={clued} missing={missing} unfilled={unfilled}")
        return lines

    def grid_summary(self):
        grid = self.grid
        whites = grid.white_cells()
        blacks = grid.size() - len(whites)
        givens = sum(1 for cell in whites if grid.is_given(cell))
        holding = [name for name in CHECKED_SYMMETRIES if grid.asymmetric_cell(name) is None]
        if not holding:
            holding = ["none"]
        return (
            f"grid size={grid.width}x{grid.height} blocks={blacks} white={len(whites)} "
            f"density={decimal(100 * blacks, grid.size(), 1)} givens={givens} "
            f"required={self.symmetry} symmetry={','.join(holding)}"
        )

    def slot_lengths(self):
        return sorted({slot.length for slot in self.layout.slots})

    def slot_summary(self):
        slots = self.layout.slots
        lengths = [slot.length for slot in slots]
        across = sum(1 for slot in slots if slot.across)
        counts = ",".join(f"{length}:{lengths.count(length)}" for length in self.slot_lengths())
        unchecked = sum(
            1 for cell in self.grid.white_cells() if self.layout.owner_count(cell) == 1
        )
        return (
            f"slots across={across} down={len(slots) - across} total={len(slots)} "
            f"lengths={counts} avg_length={decimal(sum(lengths), len(slots), 2)} "
            f"longest={max(lengths)} unchecked={unchecked}"
        )

    def themes_line(self, scores):
        theme_slots = [slot for slot in self.layout.slots if slot.index in self.theme_slots]
        return "themes " + " ".join(self.entry(slot, scores) for slot in theme_slots)

    def coverage_line(self, index):
        parts = []
        for length in self.slot_lengths():
            words = index.by_length.get(length, [])
            supply = sum(1 for word in words if index.scores[word] >= self.min_score)
            parts.append(f"{length}:{supply}")
        return "coverage " + " ".join(parts)

    def tightest_line(self, index):
        counts = []
        for slot in self.layout.slots:
            if slot.index in self.theme_slots:
                continue
            words = index.candidates(self.initial.pattern(slot), self.min_score, self.initial.used)
            counts.append((len(words), slot.index))
        counts.sort()
        slots = self.layout.slots
        parts = [f"{slots[slot].label}:{count}" for count, slot in counts[:HIGHLIGHT_COUNT]]
        return "tightest " + joined(parts, " ")

    def attempt_lines(self):
        lines = []
        for number, attempt in enumerate(self.attempts, 1):
            lines.append(
                f"attempt {number} min_score={attempt.min_score} budget={attempt.budget} "
                f"outcome={attempt.outcome} nodes={attempt.nodes} "
                f"backtracks={attempt.backtracks} prunes={attempt.prunes} "
                f"dead_ends={attempt.dead_ends} max_depth={attempt.max_depth}"
            )
        return lines

    def hotspots_line(self):
        failures = self.final.failures
        failed = [slot for slot in self.layout.slots if failures[slot.index] >= 1]
        failed.sort(key=lambda slot: (-failures[slot.index], slot.index))
        parts = [f"{slot.label}:{failures[slot.index]}" for slot in failed[:HIGHLIGHT_COUNT]]
        return "hotspots " + joined(parts, " ")

    def worst_crossing(self, scores):
        worst = None
        worst_sum = 0
        for cell in self.grid.white_cells():
            across = self.layout.across_slot[cell]
            down = self.layout.down_slot[cell]
            if across is None or down is None:
                continue
            crossing_sum = scores[self.state.words[across]] + scores[self.state.words[down]]
            if worst is None or crossing_sum < worst_sum:
                worst = cell
                worst_sum = crossing_sum
        if worst is None:
            return "-"
        slots = self.layout.slots
        across = slots[self.layout.across_slot[worst]]
        down = slots[self.layout.down_slot[worst]]
        return (
            f"{cell_text(self.grid, worst)} {across.label}:{self.state.words[across.index]}"
            f"+{down.label}:{self.state.words[down.index]}={worst_sum}"
        )

    def quality_lines(self, scores, weak_score):
        slots = self.layout.slots
        words = self.state.words
        total = self.total_score(scores)
        weakest = min(slots, key=lambda slot: scores[words[slot.index]])
        weak = [self.entry(slot, scores) for slot in slots if scores[words[slot.index]] < weak_score]
        letters = [self.state.letters[cell] for cell in self.grid.white_cells()]
        distinct = set(letters)
        missing = "".join(letter for letter in UPPERCASE if letter not in distinct)
        points = sum(LETTER_POINTS[letter] for letter in letters)
        pangram = "yes" if not missing else "no"
        return [
            f"quality total={total} average={decimal(total, len(slots), 2)} "
            f"weakest={self.entry(weakest, scores)} weak={joined(weak, ',')}",
            f"letters distinct={len(distinct)} pangram={pangram} missing={missing or '-'} "
            f"scrabble={decimal(points, len(letters), 2)} "
            f"worst_crossing={self.worst_crossing(scores)}",
        ]

    def partial_line(self, index):
        slots = self.layout.slots
        state = self.state
        assigned = sum(1 for word in state.words if word is not None)
        whites = self.grid.white_cells()
        lettered = sum(1 for cell in whites if state.letters[cell] != EMPTY)
        blocked = []
        for slot in slots:
            if state.words[slot.index] is not None:
                continue
            if not index.candidates(state.pattern(slot), self.final.min_score, state.used):
                blocked.append(slot.label)
        return (
            f"partial assigned={assigned}/{len(slots)} letters={lettered}/{len(whites)} "
            f"blocked={joined(blocked, ',')}"
        )

    def stats_paragraph(self, index, weak_score):
        lines = [f"TEMPLATE {self.name}", self.grid_summary(), self.slot_summary()]
        if self.theme_slots:
            lines.append(self.themes_line(index.scores))
        lines.append(self.coverage_line(index))
        lines.append(self.tightest_line(index))
        lines.extend(self.attempt_lines())
        lines.append("trace " + joined(self.final.trace, " "))
        lines.append(self.hotspots_line())
        if self.is_filled():
            order = [slot.label for slot in self.final.sequence]
            lines.append("order " + joined(order, " "))
            lines.extend(self.quality_lines(index.scores, weak_score))
        else:
            lines.append(self.partial_line(index))
        return lines


def ranking_paragraph(filled, scores):
    def compare(first, second):
        left = first.total_score(scores) * second.slot_count()
        right = second.total_score(scores) * first.slot_count()
        if left != right:
            return -1 if left > right else 1
        if first.name != second.name:
            return -1 if first.name < second.name else 1
        return 0

    lines = ["RANKING"]
    ranked = sorted(filled, key=cmp_to_key(compare))
    for position, template in enumerate(ranked, 1):
        total = template.total_score(scores)
        entries = template.slot_count()
        lines.append(
            f"rank {position} {template.name} average={decimal(total, entries, 2)} "
            f"total={total} entries={entries}"
        )
    return lines


def reuse_paragraph(filled):
    appearances = {}
    for template in filled:
        for word in template.state.words:
            appearances.setdefault(word, []).append(template.name)
    reused = [word for word in appearances if len(appearances[word]) >= 2]
    reused.sort(key=lambda word: (-len(appearances[word]), word))
    lines = ["REUSE"]
    for word in reused:
        names = appearances[word]
        lines.append(f"reused {word} {len(names)} {','.join(names)}")
    return lines


def summary_paragraph(templates):
    valid = [template for template in templates if template.error is None]
    outcomes = [template.final.outcome for template in valid]
    attempts = sum(len(template.attempts) for template in valid)
    nodes = sum(attempt.nodes for template in valid for attempt in template.attempts)
    return [
        f"SUMMARY templates={len(templates)} invalid={len(templates) - len(valid)} "
        f"filled={outcomes.count('filled')} unfillable={outcomes.count('unfillable')} "
        f"budget={outcomes.count('budget')} attempts={attempts} nodes={nodes}"
    ]


def main():
    settings = read_settings(read_lines("params.txt"))
    word_list = WordList(read_lines("words.txt"))
    index = word_list.index
    clue_book = ClueBook(read_lines("clues.txt"), word_list.scores)
    templates = []
    names = set()
    for block in split_blocks(read_lines("templates.txt")):
        template = Template(block, settings)
        template.process(names, index, clue_book, settings["relax_step"])
        names.add(block.name)
        templates.append(template)
    valid = [template for template in templates if template.error is None]
    filled = [template for template in valid if template.is_filled()]
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    write_paragraphs("grid.txt", [template.grid_paragraph() for template in templates])
    write_paragraphs("clues.txt", [template.clue_paragraph(index.scores) for template in valid])
    stats = [template.stats_paragraph(index, settings["weak_score"]) for template in valid]
    stats.append(ranking_paragraph(filled, index.scores))
    stats.append(reuse_paragraph(filled))
    stats.append(summary_paragraph(templates))
    write_paragraphs("search_stats.txt", stats)
    write_lines("wordlist.txt", word_list.report_lines() + clue_book.report_lines())


if __name__ == "__main__":
    main()
