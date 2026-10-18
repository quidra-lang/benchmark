import os
import re

from clues import comma_separated, fits, is_clue_line, parse_clue, run_clue, span, spaced
from line_solver import FILLED, UNKNOWN, has_placement
from propagation import determined_count, line_cells, line_label, propagate
from render import answer_sheet, char_state, grid_display, state_char, state_string
from search import Search, guess_cell


PUZZLE_PATH = "input/puzzles.txt"
PICTURE_PATH = "input/pictures.txt"
OUTPUT_DIRECTORY = "output"
SOLUTIONS_PATH = "output/solutions.txt"
STATS_PATH = "output/stats.csv"
GENERATED_PATH = "output/generated.txt"
NAME_PATTERN = re.compile(r"[a-z0-9_]{1,20}")
MAX_SIDE = 30
TRACE_CELL_LIMIT = 49
GUESS_WEIGHT = 25
GIVEN_VALUES = ("#", ".")
ANSWER_CHARACTERS = ("#", ".", "?")
PICTURE_CHARACTERS = ("#", ".")
STATUS_BY_SOLUTIONS = ("none", "unique", "multiple")
DIFFICULTY_ORDER = {"easy": 0, "medium": 1, "hard": 2}
SYMMETRIES = (("lr", False, True), ("ud", True, False), ("rot180", True, True))
NEIGHBORS = ((-1, 0), (1, 0), (0, -1), (0, 1))
STATS_HEADER = (
    "puzzle,status,difficulty,width,height,givens,simple_known,logic_known,"
    "line_solves,guesses,max_depth,solutions,answer"
)
INVALID_STATS_FIELDS = 11


def read_blocks(path):
    with open(path) as handle:
        lines = handle.read().splitlines()
    blocks = []
    block = None
    for line in lines:
        if block is None:
            if line != "" and not line.startswith("#"):
                block = [line]
        elif line == "END":
            blocks.append(block)
            block = None
        else:
            block.append(line)
    return blocks


def write_lines(path, lines):
    with open(path, "w") as handle:
        handle.write("".join(line + "\n" for line in lines))


def join_paragraphs(paragraphs):
    lines = []
    for paragraph in paragraphs:
        if lines:
            lines.append("")
        lines.extend(paragraph)
    return lines


def valid_name(name):
    return NAME_PATTERN.fullmatch(name) is not None


def number_list(numbers):
    return ",".join(str(number) for number in numbers) if numbers else "-"


def cell_text(row, column):
    return f"{row + 1},{column + 1}"


def state_grid(texts):
    return [[char_state(character) for character in text] for text in texts]


def grid_columns(grid):
    return [line_cells(grid, False, column) for column in range(len(grid[0]))]


def line_clue(row_clues, column_clues, is_row, index):
    return row_clues[index] if is_row else column_clues[index]


def differing_cells(first, second):
    return [
        (row, column)
        for row in range(len(first))
        for column in range(len(first[0]))
        if first[row][column] != second[row][column]
    ]


class PuzzleBlock:
    def __init__(self, lines):
        self.name = lines[0][len("PUZZLE "):]
        size = lines[1].split(" ")
        self.width = int(size[1])
        self.height = int(size[2])
        columns_at = lines.index("COLUMNS")
        self.row_lines = lines[3:columns_at]
        self.column_lines = []
        self.given_lines = []
        position = columns_at + 1
        while position < len(lines) and is_clue_line(lines[position]):
            self.column_lines.append(lines[position])
            position += 1
        while position < len(lines) and lines[position].startswith("GIVEN "):
            _, row, column, value = lines[position].split(" ")
            self.given_lines.append((int(row), int(column), value))
            position += 1
        self.answer_lines = lines[position + 1:] if position < len(lines) else None
        self.row_clues = []
        self.column_clues = []
        self.givens = []
        self.answer = None
        self.error = None

    def check_clues(self, texts, kind, length):
        clues = []
        for number, text in enumerate(texts, 1):
            clue = parse_clue(text)
            if clue is None:
                return None, f"bad clue {kind} {number}"
            if not fits(clue, length):
                return None, f"{kind} {number} too long"
            clues.append(clue)
        return clues, None

    def check_givens(self):
        taken = set()
        for number, (row, column, value) in enumerate(self.given_lines, 1):
            inside = 1 <= row <= self.height and 1 <= column <= self.width
            if not inside or value not in GIVEN_VALUES:
                return f"bad given {number}"
            if (row, column) in taken:
                return f"duplicate given {number}"
            taken.add((row, column))
            self.givens.append((row - 1, column - 1, char_state(value)))
        return None

    def answer_is_valid(self):
        if len(self.answer_lines) != self.height:
            return False
        for line in self.answer_lines:
            if len(line) != self.width:
                return False
            if any(character not in ANSWER_CHARACTERS for character in line):
                return False
        return True

    def validate(self, earlier_names):
        if not valid_name(self.name):
            return "bad name"
        if self.name in earlier_names:
            return "duplicate name"
        if not (1 <= self.width <= MAX_SIDE and 1 <= self.height <= MAX_SIDE):
            return "bad size"
        if len(self.row_lines) != self.height:
            return f"row count {len(self.row_lines)} expected {self.height}"
        if len(self.column_lines) != self.width:
            return f"column count {len(self.column_lines)} expected {self.width}"
        self.row_clues, error = self.check_clues(self.row_lines, "row", self.width)
        if error is not None:
            return error
        self.column_clues, error = self.check_clues(self.column_lines, "column", self.height)
        if error is not None:
            return error
        row_total = sum(sum(clue) for clue in self.row_clues)
        column_total = sum(sum(clue) for clue in self.column_clues)
        if row_total != column_total:
            return f"total mismatch rows={row_total} columns={column_total}"
        error = self.check_givens()
        if error is not None:
            return error
        if self.answer_lines is not None:
            if not self.answer_is_valid():
                return "bad answer"
            self.answer = state_grid(self.answer_lines)
        return None


class PictureBlock:
    def __init__(self, lines):
        self.name = lines[0][len("PICTURE "):]
        self.rows = lines[1:]
        self.error = None

    def validate(self, earlier_names):
        if not valid_name(self.name):
            return "bad name"
        if self.name in earlier_names:
            return "duplicate name"
        if not 1 <= len(self.rows) <= MAX_SIDE:
            return "bad height"
        width = len(self.rows[0])
        for number, row in enumerate(self.rows, 1):
            if not 1 <= len(row) <= MAX_SIDE or len(row) != width:
                return f"bad row {number}"
            if any(character not in PICTURE_CHARACTERS for character in row):
                return f"bad row {number}"
        return None

    def grid(self):
        return state_grid(self.rows)


def start_grid(height, width, givens):
    grid = [[UNKNOWN] * width for _ in range(height)]
    for row, column, state in givens:
        grid[row][column] = state
    return grid


def logical_solve(row_clues, column_clues, givens, precise):
    height = len(row_clues)
    width = len(column_clues)
    grid = start_grid(height, width, givens)
    propagation = propagate(
        grid, row_clues, column_clues, precise, [True] * height, [True] * width
    )
    return grid, propagation


def solving_result(grid, propagation):
    if propagation.conflict is not None:
        return "contradiction at=" + propagation.conflict.label()
    if determined_count(grid) == len(grid) * len(grid[0]):
        return "solved"
    return "stuck"


class Analysis:
    def __init__(self, row_clues, column_clues, givens):
        self.simple_grid, self.simple = logical_solve(row_clues, column_clues, givens, False)
        self.logic_grid, self.logic = logical_solve(row_clues, column_clues, givens, True)
        self.simple_result = solving_result(self.simple_grid, self.simple)
        self.logic_result = solving_result(self.logic_grid, self.logic)
        self.search = None
        self.solutions = []
        self.difficulty = "-"
        if self.logic.conflict is not None:
            self.status = "contradiction"
        elif self.logic_result == "solved":
            self.status = "unique"
            self.solutions = [self.logic_grid]
            self.difficulty = "easy" if self.simple_result == "solved" else "medium"
        else:
            self.search = Search(row_clues, column_clues)
            self.search.run(self.logic_grid, 1)
            self.solutions = self.search.solutions
            self.status = STATUS_BY_SOLUTIONS[len(self.solutions)]
            if self.status == "unique":
                self.difficulty = "hard"
        self.line_solves = self.logic.line_solves()
        self.guesses = 0
        self.max_depth = 0
        if self.search is not None:
            self.line_solves += self.search.line_solves()
            self.guesses = self.search.guess_count()
            self.max_depth = self.search.max_depth()


def is_fixed(clue, length):
    return not clue or span(clue) == length


def clue_statistics(row_clues, column_clues):
    width = len(column_clues)
    height = len(row_clues)
    lengths = [length for clue in row_clues + column_clues for length in clue]
    fixed = sum(1 for clue in row_clues if is_fixed(clue, width))
    fixed += sum(1 for clue in column_clues if is_fixed(clue, height))
    row_blocks = sum(len(clue) for clue in row_clues)
    column_blocks = sum(len(clue) for clue in column_clues)
    filled = sum(sum(clue) for clue in row_clues)
    max_block = max(lengths) if lengths else 0
    return (
        f"row_blocks={row_blocks} column_blocks={column_blocks} filled={filled} "
        f"max_block={max_block} fixed_lines={fixed}"
    )


def step_statistics(propagation):
    productive = 0
    idle = 0
    best = 0
    best_label = "-"
    for step in propagation.steps:
        if step.contradiction:
            continue
        if step.gain > 0:
            productive += 1
        else:
            idle += 1
        if step.gain > best:
            best = step.gain
            best_label = step.label()
    return f"productive={productive} idle={idle} best={best} at={best_label}"


def component_sizes(grid):
    height = len(grid)
    width = len(grid[0])
    seen = [[False] * width for _ in range(height)]
    sizes = []
    for row in range(height):
        for column in range(width):
            if grid[row][column] != FILLED or seen[row][column]:
                continue
            seen[row][column] = True
            pending = [(row, column)]
            size = 0
            while pending:
                current_row, current_column = pending.pop()
                size += 1
                for row_step, column_step in NEIGHBORS:
                    next_row = current_row + row_step
                    next_column = current_column + column_step
                    if not (0 <= next_row < height and 0 <= next_column < width):
                        continue
                    if grid[next_row][next_column] == FILLED and not seen[next_row][next_column]:
                        seen[next_row][next_column] = True
                        pending.append((next_row, next_column))
            sizes.append(size)
    return sizes


def bounding_box(grid):
    rows = [row for row, states in enumerate(grid) if FILLED in states]
    if not rows:
        return "-"
    columns = [column for column, cells in enumerate(grid_columns(grid)) if FILLED in cells]
    return f"{rows[0] + 1},{columns[0] + 1},{rows[-1] + 1},{columns[-1] + 1}"


def is_symmetric(grid, flip_rows, flip_columns):
    height = len(grid)
    width = len(grid[0])
    for row in range(height):
        for column in range(width):
            mirror_row = height - 1 - row if flip_rows else row
            mirror_column = width - 1 - column if flip_columns else column
            if grid[row][column] != grid[mirror_row][mirror_column]:
                return False
    return True


def symmetry_text(grid):
    names = [
        name for name, flip_rows, flip_columns in SYMMETRIES
        if is_symmetric(grid, flip_rows, flip_columns)
    ]
    return ",".join(names) if names else "none"


def features_text(grid):
    sizes = component_sizes(grid)
    filled = sum(states.count(FILLED) for states in grid)
    largest = max(sizes) if sizes else 0
    return (
        f"filled={filled} components={len(sizes)} largest={largest} "
        f"bbox={bounding_box(grid)} symmetry={symmetry_text(grid)}"
    )


def unknown_summary(lines):
    parts = []
    for number, cells in enumerate(lines, 1):
        count = cells.count(UNKNOWN)
        if count > 0:
            parts.append(f"{number}:{count}")
    return " ".join(parts)


def stuck_line(grid):
    return f"stuck rows={unknown_summary(grid)} columns={unknown_summary(grid_columns(grid))}"


def conflict_line(block, analysis):
    step = analysis.logic.conflict
    clue = line_clue(block.row_clues, block.column_clues, step.is_row, step.index)
    cells = line_cells(analysis.logic_grid, step.is_row, step.index)
    return f"conflict line={step.label()} clue={comma_separated(clue)} cells={state_string(cells)}"


def search_lines(search):
    lines = [
        f"search guesses={search.guess_count()} max_depth={search.max_depth()} "
        f"backtracks={search.backtracks} solutions={len(search.solutions)} "
        f"line_solves={search.line_solves()}"
    ]
    for guess in search.guesses:
        lines.append(
            f"guess {guess.number} depth={guess.depth} cell={cell_text(guess.row, guess.column)} "
            f"value={state_char(guess.value)} solves={guess.solves} known={guess.known} "
            f"result={guess.result}"
        )
    return lines


def differ_line(solutions):
    cells = differing_cells(solutions[0], solutions[1])
    listed = " ".join(cell_text(row, column) for row, column in cells)
    return f"differ count={len(cells)} cells={listed}"


def display_lines(analysis):
    names = []
    grids = []
    if analysis.status == "contradiction":
        names.append("partial")
        grids.append(analysis.logic_grid)
    else:
        if analysis.simple_result == "stuck":
            names.append("simple")
            grids.append(analysis.simple_grid)
        if analysis.logic_result == "stuck":
            names.append("logic")
            grids.append(analysis.logic_grid)
        if analysis.status == "multiple":
            names.extend(("first", "second"))
            grids.extend(analysis.solutions)
    if not names:
        return []
    return grid_display(names, grids)


def evaluate_givens(block, analysis):
    if not block.givens or analysis.status == "multiple":
        return None
    if analysis.status == "unique":
        label = "redundant"
        accepted = ("unique",)
    else:
        label = "blame"
        accepted = ("unique", "multiple")
    numbers = []
    for number in range(1, len(block.givens) + 1):
        others = block.givens[:number - 1] + block.givens[number:]
        if Analysis(block.row_clues, block.column_clues, others).status in accepted:
            numbers.append(number)
    return f"givens {label}={number_list(numbers)}"


class Grading:
    def __init__(self, block, analysis):
        answer = block.answer
        self.answer = answer
        self.rows = [
            row for row in range(block.height)
            if not has_placement(answer[row], block.row_clues[row])
        ]
        self.columns = [
            column for column in range(block.width)
            if not has_placement(line_cells(answer, False, column), block.column_clues[column])
        ]
        self.givens = [
            number for number, (row, column, state) in enumerate(block.givens, 1)
            if answer[row][column] != UNKNOWN and answer[row][column] != state
        ]
        self.known = determined_count(answer)
        mismatched = bool(self.rows or self.columns or self.givens)
        self.extendable = None
        if self.known < block.width * block.height:
            self.result = "partial"
            extendable = not mismatched and self.completes(block)
            self.extendable = "yes" if extendable else "no"
        elif mismatched:
            self.result = "wrong"
        else:
            self.result = "correct"
        self.differs = None
        if analysis.status == "unique":
            solution = analysis.solutions[0]
            self.differs = sum(
                1
                for row in range(block.height)
                for column in range(block.width)
                if answer[row][column] != UNKNOWN and answer[row][column] != solution[row][column]
            )

    def completes(self, block):
        given_cells = {(row, column) for row, column, _ in block.givens}
        extra = [
            (row, column, state)
            for row, states in enumerate(self.answer)
            for column, state in enumerate(states)
            if state != UNKNOWN and (row, column) not in given_cells
        ]
        status = Analysis(block.row_clues, block.column_clues, block.givens + extra).status
        return status in ("unique", "multiple")

    def mismatch_line(self, block, is_row, index):
        clue = line_clue(block.row_clues, block.column_clues, is_row, index)
        cells = line_cells(self.answer, is_row, index)
        prefix = f"mismatch {line_label(is_row, index)} expected={comma_separated(clue)}"
        if self.result == "partial":
            return prefix + " cells=" + state_string(cells)
        return prefix + " got=" + comma_separated(run_clue(cells))

    def lines(self, block):
        rows = number_list([row + 1 for row in self.rows])
        columns = number_list([column + 1 for column in self.columns])
        text = (
            f"answer result={self.result} known={self.known} rows={rows} "
            f"columns={columns} givens={number_list(self.givens)}"
        )
        if self.extendable is not None:
            text += " extendable=" + self.extendable
        if self.differs is not None:
            text += f" differs={self.differs}"
        lines = [text]
        for row in self.rows:
            lines.append(self.mismatch_line(block, True, row))
        for column in self.columns:
            lines.append(self.mismatch_line(block, False, column))
        return lines


class PuzzleReport:
    def __init__(self, block):
        self.block = block
        self.analysis = Analysis(block.row_clues, block.column_clues, block.givens)
        self.evaluation = evaluate_givens(block, self.analysis)
        self.grading = None
        if block.answer is not None:
            self.grading = Grading(block, self.analysis)

    def score(self):
        return self.analysis.line_solves + GUESS_WEIGHT * self.analysis.guesses

    def paragraph(self):
        block = self.block
        analysis = self.analysis
        lines = [
            "PUZZLE " + block.name,
            f"size={block.width}x{block.height} givens={len(block.givens)} "
            f"status={analysis.status} difficulty={analysis.difficulty}",
            "clues " + clue_statistics(block.row_clues, block.column_clues),
            f"simple known={determined_count(analysis.simple_grid)} "
            f"line_solves={analysis.simple.line_solves()} result={analysis.simple_result}",
            f"logic known={determined_count(analysis.logic_grid)} "
            f"line_solves={analysis.logic.line_solves()} result={analysis.logic_result}",
            "steps " + step_statistics(analysis.logic),
        ]
        if block.width * block.height <= TRACE_CELL_LIMIT:
            lines.append("trace " + analysis.logic.record())
        if analysis.logic_result == "stuck":
            lines.append(stuck_line(analysis.logic_grid))
        if analysis.status == "contradiction":
            lines.append(conflict_line(block, analysis))
        if analysis.search is not None:
            lines.extend(search_lines(analysis.search))
        if analysis.status == "multiple":
            lines.append(differ_line(analysis.solutions))
        lines.extend(display_lines(analysis))
        if analysis.status == "unique":
            solution = analysis.solutions[0]
            lines.append("sheet")
            lines.extend(answer_sheet(block.row_clues, block.column_clues, solution))
            lines.append("picture " + features_text(solution))
        if self.evaluation is not None:
            lines.append(self.evaluation)
        if self.grading is not None:
            lines.extend(self.grading.lines(block))
        return lines

    def stats_row(self):
        block = self.block
        analysis = self.analysis
        fields = [
            block.name, analysis.status, analysis.difficulty, block.width, block.height,
            len(block.givens), determined_count(analysis.simple_grid),
            determined_count(analysis.logic_grid), analysis.line_solves, analysis.guesses,
            analysis.max_depth, len(analysis.solutions),
            "-" if self.grading is None else self.grading.result,
        ]
        return ",".join(str(field) for field in fields)


def ranking_lines(reports):
    ranked = sorted(
        (report for report in reports if report.analysis.status == "unique"),
        key=lambda report: (
            DIFFICULTY_ORDER[report.analysis.difficulty], report.score(), report.block.name
        ),
    )
    lines = ["RANKING"]
    for rank, report in enumerate(ranked, 1):
        block = report.block
        lines.append(
            f"rank {rank} {block.name} {report.analysis.difficulty} "
            f"score={report.score()} size={block.width}x{block.height}"
        )
    return lines


def summary_line(blocks, reports):
    statuses = [report.analysis.status for report in reports]
    difficulties = [report.analysis.difficulty for report in reports]
    line_solves = sum(report.analysis.line_solves for report in reports)
    guesses = sum(report.analysis.guesses for report in reports)
    return (
        f"SUMMARY puzzles={len(blocks)} invalid={len(blocks) - len(reports)} "
        f"contradiction={statuses.count('contradiction')} none={statuses.count('none')} "
        f"unique={statuses.count('unique')} multiple={statuses.count('multiple')} "
        f"easy={difficulties.count('easy')} medium={difficulties.count('medium')} "
        f"hard={difficulties.count('hard')} line_solves={line_solves} guesses={guesses}"
    )


def invalid_stats_row(block):
    return block.name + ",invalid" + ",-" * INVALID_STATS_FIELDS


def process_puzzles(blocks):
    names = set()
    reports = []
    paragraphs = []
    stats = [STATS_HEADER]
    for block in blocks:
        block.error = block.validate(names)
        names.add(block.name)
        if block.error is not None:
            paragraphs.append(["PUZZLE " + block.name, "error " + block.error])
            stats.append(invalid_stats_row(block))
            continue
        report = PuzzleReport(block)
        reports.append(report)
        paragraphs.append(report.paragraph())
        stats.append(report.stats_row())
    paragraphs.append(ranking_lines(reports))
    paragraphs.append([summary_line(blocks, reports)])
    write_lines(SOLUTIONS_PATH, join_paragraphs(paragraphs))
    write_lines(STATS_PATH, stats)
    return reports


class Generation:
    def __init__(self, grid):
        self.grid = grid
        self.row_clues = [run_clue(states) for states in grid]
        self.column_clues = [run_clue(cells) for cells in grid_columns(grid)]
        self.givens = []
        self.log = []
        self.initial = self.analyze(self.givens)
        self.add_hints()
        self.remove_hints()
        self.final = self.analyze(self.givens)
        self.add_logic_hints()

    def analyze(self, givens):
        return Analysis(self.row_clues, self.column_clues, givens)

    def append_given(self, row, column):
        state = self.grid[row][column]
        self.givens.append((row, column, state))
        return f"cell={cell_text(row, column)} value={state_char(state)}"

    def add_hints(self):
        analysis = self.initial
        while analysis.status == "multiple":
            row, column = differing_cells(analysis.solutions[0], analysis.solutions[1])[0]
            added = self.append_given(row, column)
            analysis = self.analyze(self.givens)
            self.log.append(f"# hint {len(self.givens)} {added} status={analysis.status}")

    def remove_hints(self):
        for given in list(self.givens):
            others = [other for other in self.givens if other != given]
            if self.analyze(others).status == "unique":
                self.givens = others
                row, column, _ = given
                self.log.append("# drop cell=" + cell_text(row, column))

    def add_logic_hints(self):
        count = 0
        while self.final.difficulty == "hard":
            row, column = guess_cell(self.final.logic_grid)
            added = self.append_given(row, column)
            self.final = self.analyze(self.givens)
            count += 1
            self.log.append(f"# logic hint {count} {added} difficulty={self.final.difficulty}")

    def puzzle_lines(self, name):
        lines = [
            "PUZZLE " + name,
            f"SIZE {len(self.column_clues)} {len(self.row_clues)}",
            "ROWS",
        ]
        lines.extend(spaced(clue) for clue in self.row_clues)
        lines.append("COLUMNS")
        lines.extend(spaced(clue) for clue in self.column_clues)
        for row, column, state in sorted(self.givens):
            lines.append(f"GIVEN {row + 1} {column + 1} {state_char(state)}")
        lines.append("END")
        return lines


def same_clues_name(reports, row_clues, column_clues):
    for report in reports:
        block = report.block
        if block.row_clues == row_clues and block.column_clues == column_clues:
            return block.name
    return "-"


def picture_paragraph(picture, generation, reports):
    grid = generation.grid
    initial = generation.initial
    final = generation.final
    duplicate = same_clues_name(reports, generation.row_clues, generation.column_clues)
    lines = [
        f"# picture {picture.name} size={len(grid[0])}x{len(grid)} {features_text(grid)}",
        f"# clues {clue_statistics(generation.row_clues, generation.column_clues)} "
        f"duplicate_of={duplicate}",
        f"# plain status={initial.status} difficulty={initial.difficulty} "
        f"line_solves={initial.line_solves} guesses={initial.guesses}",
    ]
    lines.extend(generation.log)
    lines.append(
        f"# final status={final.status} difficulty={final.difficulty} "
        f"hints={len(generation.givens)} line_solves={final.line_solves} guesses={final.guesses}"
    )
    lines.extend(generation.puzzle_lines(picture.name))
    return lines


def process_pictures(pictures, reports):
    names = set()
    paragraphs = []
    generations = []
    for picture in pictures:
        picture.error = picture.validate(names)
        names.add(picture.name)
        if picture.error is not None:
            paragraphs.append([f"# picture {picture.name} error {picture.error}"])
            continue
        generation = Generation(picture.grid())
        generations.append(generation)
        paragraphs.append(picture_paragraph(picture, generation, reports))
    unique = sum(1 for generation in generations if generation.initial.status == "unique")
    line_logic = sum(
        1 for generation in generations if generation.initial.difficulty in ("easy", "medium")
    )
    hinted = sum(1 for generation in generations if generation.givens)
    hints = sum(len(generation.givens) for generation in generations)
    paragraphs.append([
        f"# SUMMARY pictures={len(pictures)} invalid={len(pictures) - len(generations)} "
        f"unique={unique} line_logic={line_logic} hinted={hinted} hints={hints}"
    ])
    write_lines(GENERATED_PATH, join_paragraphs(paragraphs))


def main():
    os.makedirs(OUTPUT_DIRECTORY, exist_ok=True)
    blocks = [PuzzleBlock(lines) for lines in read_blocks(PUZZLE_PATH)]
    reports = process_puzzles(blocks)
    pictures = [PictureBlock(lines) for lines in read_blocks(PICTURE_PATH)]
    process_pictures(pictures, reports)


if __name__ == "__main__":
    main()
