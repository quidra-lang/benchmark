from collections import deque
from fractions import Fraction
import re
import sys


PRESETS = {
    "beginner": (9, 9, 10),
    "intermediate": (16, 16, 40),
    "expert": (30, 16, 99),
}
SAFETY_MODES = ("block", "cell", "none")
MAX_SIDE = 30
MULTIPLIER = 48271
MODULUS = 2147483647
NUMBER_WORD = re.compile(r"0|[1-9][0-9]{0,9}")
COORDINATES = ("number", "number")
COMMANDS = {
    "NEW": ("number", "number", "number", "number"),
    "PRESET": ("name", "number"),
    "SAFETY": ("mode",),
    "RESTART": (),
    "REVEAL": COORDINATES,
    "FLAG": COORDINATES,
    "UNFLAG": COORDINATES,
    "QUESTION": COORDINATES,
    "CHORD": COORDINATES,
    "UNDO": (),
    "SHOW": (),
    "STATUS": (),
    "CELL": COORDINATES,
    "HISTORY": ("number",),
    "REPLAY": ("number",),
    "HINT": (),
    "AUTO": (),
    "ANALYZE": (),
    "PROB": COORDINATES,
    "FRONTIER": (),
    "SOLVE": (),
    "BOARDINFO": (),
    "STATS": (),
}
CELL_COMMANDS = ("REVEAL", "FLAG", "UNFLAG", "QUESTION", "CHORD", "CELL", "PROB")
PLAY_COMMANDS = (
    "REVEAL", "FLAG", "UNFLAG", "QUESTION", "CHORD", "UNDO",
    "HINT", "AUTO", "ANALYZE", "PROB", "FRONTIER", "SOLVE",
)
UNDOABLE_COMMANDS = ("REVEAL", "FLAG", "UNFLAG", "QUESTION", "CHORD", "AUTO", "SOLVE")
REVEAL_KINDS = ("reveal", "auto-reveal", "guess")
FLAG_KINDS = ("flag", "auto-flag")
MARK_SYMBOLS = {"none": "#", "flag": "F", "question": "?"}


def valid_argument(kind, text):
    if kind == "number":
        return NUMBER_WORD.fullmatch(text) is not None
    if kind == "name":
        return text in PRESETS
    return text in SAFETY_MODES


def board_parameters(name, arguments):
    if name == "PRESET":
        width, height, mines = PRESETS[arguments[0]]
        return width, height, mines, int(arguments[1])
    width, height, mines, seed = (int(text) for text in arguments)
    return width, height, mines, seed


def valid_board(width, height, mines, seed):
    return (
        1 <= width <= MAX_SIDE
        and 1 <= height <= MAX_SIDE
        and 1 <= mines <= width * height - 9
        and 1 <= seed <= MODULUS - 1
    )


def fraction_text(value):
    return f"{value.numerator}/{value.denominator}"


class CommandError(Exception):
    pass


class Constraint:
    def __init__(self, cell, remaining, unknown):
        self.cell = cell
        self.remaining = remaining
        self.unknown = unknown


class Deduction:
    def __init__(self):
        self.safe = {}
        self.mines = {}

    def empty(self):
        return not self.safe and not self.mines


class Component:
    def __init__(self, cells, constraints):
        self.cells = cells
        self.memberships = [[] for _ in cells]
        position = {cell: index for index, cell in enumerate(cells)}
        for index, constraint in enumerate(constraints):
            for cell in constraint.unknown:
                self.memberships[position[cell]].append(index)
        self.needed = [constraint.remaining for constraint in constraints]
        self.unassigned = [len(constraint.unknown) for constraint in constraints]
        self.assignment = [0] * len(cells)
        self.configurations = 0
        self.mine_hits = [0] * len(cells)
        self.fewest_mines = len(cells)
        self.most_mines = 0

    def count(self):
        self.search(0, 0)

    def search(self, position, mines):
        if position == len(self.cells):
            self.configurations += 1
            self.fewest_mines = min(self.fewest_mines, mines)
            self.most_mines = max(self.most_mines, mines)
            for index, value in enumerate(self.assignment):
                self.mine_hits[index] += value
            return
        for value in (0, 1):
            feasible = True
            for index in self.memberships[position]:
                self.needed[index] -= value
                self.unassigned[index] -= 1
                if self.needed[index] < 0 or self.needed[index] > self.unassigned[index]:
                    feasible = False
            if feasible:
                self.assignment[position] = value
                self.search(position + 1, mines + value)
            for index in self.memberships[position]:
                self.needed[index] += value
                self.unassigned[index] += 1

    def probability(self, index):
        return Fraction(self.mine_hits[index], self.configurations)


class PlayCounts:
    def __init__(self):
        self.guesses = 0
        self.rounds = 0
        self.flagged = 0
        self.opened = 0


class UndoEntry:
    def __init__(self, name, revealed, marks, moves):
        self.name = name
        self.revealed = revealed
        self.marks = marks
        self.moves = moves


class Game:
    def __init__(self, width, height, mine_count, seed):
        self.width = width
        self.height = height
        self.size = width * height
        self.mine_count = mine_count
        self.seed = seed
        self.neighbors = [self.neighbor_cells(cell) for cell in range(self.size)]
        self.placed = False
        self.mines = [False] * self.size
        self.numbers = [0] * self.size
        self.restart()

    def restart(self):
        self.revealed = [False] * self.size
        self.marks = ["none"] * self.size
        self.state = "playing" if self.placed else "ready"
        self.exploded = None
        self.moves = []
        self.undo_record = []

    def neighbor_cells(self, cell):
        x, y = cell % self.width, cell // self.width
        result = []
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                nx, ny = x + dx, y + dy
                if (dx != 0 or dy != 0) and 0 <= nx < self.width and 0 <= ny < self.height:
                    result.append(ny * self.width + nx)
        return result

    def cell_name(self, cell):
        return f"{cell % self.width},{cell // self.width}"

    def clone(self):
        copy = Game(self.width, self.height, self.mine_count, self.seed)
        copy.placed = self.placed
        copy.mines = self.mines[:]
        copy.numbers = self.numbers[:]
        copy.revealed = self.revealed[:]
        copy.marks = self.marks[:]
        copy.state = self.state
        copy.exploded = self.exploded
        copy.moves = self.moves[:]
        return copy

    def snapshot(self, name):
        return UndoEntry(name, self.revealed[:], self.marks[:], self.moves[:])

    def restore(self, entry):
        self.revealed = entry.revealed
        self.marks = entry.marks
        self.moves = entry.moves

    def set_mines(self, mines):
        self.mines = mines
        self.numbers = [
            sum(mines[neighbor] for neighbor in self.neighbors[cell])
            for cell in range(self.size)
        ]
        self.placed = True
        self.state = "playing"

    def place_mines(self, start, safety):
        start_x, start_y = start % self.width, start // self.width
        candidates = []
        for cell in range(self.size):
            x, y = cell % self.width, cell // self.width
            if safety == "block":
                allowed = abs(x - start_x) >= 2 or abs(y - start_y) >= 2
            elif safety == "cell":
                allowed = cell != start
            else:
                allowed = True
            if allowed:
                candidates.append(cell)
        mines = [False] * self.size
        random_state = self.seed
        for _ in range(self.mine_count):
            random_state = MULTIPLIER * random_state % MODULUS
            mines[candidates.pop(random_state % len(candidates))] = True
        self.set_mines(mines)

    def finished(self):
        return self.state in ("won", "lost")

    def unknown(self, cell):
        return not self.revealed[cell] and self.marks[cell] != "flag"

    def remaining_mines(self):
        return self.mine_count - self.marks.count("flag")

    def revealed_count(self):
        return self.revealed.count(True)

    def safe_count(self):
        return self.size - self.mine_count

    def neighbor_flags(self, cell):
        return sum(self.marks[neighbor] == "flag" for neighbor in self.neighbors[cell])

    def unknown_neighbors(self, cell):
        return [neighbor for neighbor in self.neighbors[cell] if self.unknown(neighbor)]

    def toggle_question(self, cell):
        self.marks[cell] = "none" if self.marks[cell] == "question" else "question"

    def reveal(self, start):
        if self.mines[start]:
            self.state = "lost"
            self.exploded = start
            return 0
        self.revealed[start] = True
        self.marks[start] = "none"
        opened = 1
        queue = deque([start])
        while queue:
            cell = queue.popleft()
            if self.numbers[cell] != 0:
                continue
            for neighbor in self.neighbors[cell]:
                if self.unknown(neighbor):
                    self.revealed[neighbor] = True
                    self.marks[neighbor] = "none"
                    queue.append(neighbor)
                    opened += 1
        return opened

    def chord(self, center):
        opened = 0
        for neighbor in self.neighbors[center]:
            if self.unknown(neighbor):
                opened += self.reveal(neighbor)
                if self.state == "lost":
                    break
        return opened

    def check_win(self):
        if self.state == "playing" and self.revealed_count() == self.safe_count():
            self.state = "won"
            for cell in range(self.size):
                if self.mines[cell]:
                    self.marks[cell] = "flag"

    def symbol(self, cell):
        if self.state == "lost":
            if cell == self.exploded:
                return "!"
            if self.mines[cell]:
                return "F" if self.marks[cell] == "flag" else "*"
            if self.marks[cell] == "flag":
                return "X"
        if self.revealed[cell]:
            return str(self.numbers[cell]) if self.numbers[cell] else "."
        return MARK_SYMBOLS[self.marks[cell]]

    def display(self):
        return [
            "".join(self.symbol(y * self.width + x) for x in range(self.width))
            for y in range(self.height)
        ]

    def replay(self, count):
        board = self.clone()
        board.restart()
        for kind, cell in self.moves[:count]:
            if kind in REVEAL_KINDS:
                board.reveal(cell)
            elif kind == "chord":
                board.chord(cell)
            elif kind in FLAG_KINDS:
                board.marks[cell] = "flag"
            elif kind == "unflag":
                board.marks[cell] = "none"
            else:
                board.toggle_question(cell)
            board.check_win()
        return board

    def constraints(self):
        result = []
        for cell in range(self.size):
            if self.revealed[cell] and self.numbers[cell] > 0:
                unknown = set(self.unknown_neighbors(cell))
                if unknown:
                    remaining = self.numbers[cell] - self.neighbor_flags(cell)
                    result.append(Constraint(cell, remaining, unknown))
        return result

    def single_rule(self, constraints, mine_side):
        result = Deduction()
        target = result.mines if mine_side else result.safe
        for constraint in constraints:
            needed = len(constraint.unknown) if mine_side else 0
            if constraint.remaining == needed:
                reason = "single " + self.cell_name(constraint.cell)
                for cell in constraint.unknown:
                    target.setdefault(cell, reason)
        return result

    def subset_rule(self, constraints):
        result = Deduction()
        for first in constraints:
            for second in constraints:
                if not first.unknown < second.unknown:
                    continue
                rest = second.unknown - first.unknown
                difference = second.remaining - first.remaining
                if difference == 0:
                    target = result.safe
                elif difference == len(rest):
                    target = result.mines
                else:
                    continue
                reason = f"subset {self.cell_name(first.cell)} {self.cell_name(second.cell)}"
                for cell in rest:
                    target.setdefault(cell, reason)
        return result

    def count_rule(self):
        result = Deduction()
        if self.state == "playing" and self.remaining_mines() == 0:
            for cell in range(self.size):
                if self.unknown(cell):
                    result.safe[cell] = "count"
        return result

    def deduce(self):
        constraints = self.constraints()
        result = self.single_rule(constraints, False)
        if result.empty():
            result = self.single_rule(constraints, True)
        if result.empty():
            result = self.subset_rule(constraints)
        if result.empty():
            result = self.count_rule()
        return result

    def auto_play(self, counts):
        while self.state == "playing":
            deduction = self.deduce()
            if deduction.empty():
                return
            counts.rounds += 1
            for cell in sorted(deduction.safe):
                if not self.revealed[cell]:
                    self.moves.append(("auto-reveal", cell))
                    counts.opened += self.reveal(cell)
                    self.check_win()
                    if self.finished():
                        return
            for cell in sorted(deduction.mines):
                if self.unknown(cell):
                    self.marks[cell] = "flag"
                    counts.flagged += 1
                    self.moves.append(("auto-flag", cell))

    def components(self):
        touching = {}
        for constraint in self.constraints():
            for cell in constraint.unknown:
                touching.setdefault(cell, []).append(constraint)
        assigned = set()
        result = []
        for start in sorted(touching):
            if start in assigned:
                continue
            assigned.add(start)
            cells = [start]
            members = []
            used = set()
            pending = [start]
            while pending:
                cell = pending.pop()
                for constraint in touching[cell]:
                    if constraint.cell in used:
                        continue
                    used.add(constraint.cell)
                    members.append(constraint)
                    for other in constraint.unknown:
                        if other not in assigned:
                            assigned.add(other)
                            cells.append(other)
                            pending.append(other)
            result.append(Component(sorted(cells), members))
        return result

    def guess_cell(self):
        unknown = [cell for cell in range(self.size) if self.unknown(cell)]
        if not unknown:
            return None
        frontier = set()
        values = {}
        for component in self.components():
            component.count()
            frontier.update(component.cells)
            if component.configurations > 0:
                for index, cell in enumerate(component.cells):
                    values[cell] = component.probability(index)
        outside = Fraction(max(self.remaining_mines(), 0), len(unknown))
        best = None
        best_value = None
        for cell in unknown:
            if cell in values:
                value = values[cell]
            elif cell in frontier:
                continue
            else:
                value = outside
            if best is None or value < best_value:
                best = cell
                best_value = value
        return best

    def board_info(self):
        blank = [not self.mines[cell] and self.numbers[cell] == 0 for cell in range(self.size)]
        seen = [False] * self.size
        openings = 0
        largest = 0
        for start in range(self.size):
            if not blank[start] or seen[start]:
                continue
            openings += 1
            seen[start] = True
            region = {start}
            pending = [start]
            while pending:
                cell = pending.pop()
                for neighbor in self.neighbors[cell]:
                    region.add(neighbor)
                    if blank[neighbor] and not seen[neighbor]:
                        seen[neighbor] = True
                        pending.append(neighbor)
            largest = max(largest, len(region))
        isolated = 0
        for cell in range(self.size):
            if self.mines[cell] or blank[cell]:
                continue
            if not any(blank[neighbor] for neighbor in self.neighbors[cell]):
                isolated += 1
        return openings + isolated, openings, largest


class Statistics:
    def __init__(self):
        self.played = 0
        self.wins = 0
        self.losses = 0
        self.streak = 0
        self.best_streak = 0
        self.fastest = None

    def record(self, game):
        self.played += 1
        if game.state == "won":
            self.wins += 1
            self.streak += 1
            self.best_streak = max(self.best_streak, self.streak)
            moves = len(game.moves)
            if self.fastest is None or moves < self.fastest:
                self.fastest = moves
        else:
            self.losses += 1
            self.streak = 0

    def summary(self):
        rate = "-" if self.played == 0 else f"{self.wins * 100 // self.played}%"
        fastest = "-" if self.fastest is None else self.fastest
        return (
            f"stats played {self.played} won {self.wins} lost {self.losses} rate {rate} "
            f"streak {self.streak} best {self.best_streak} fastest {fastest}"
        )


class Minesweeper:
    def __init__(self):
        self.game = None
        self.safety = "block"
        self.statistics = Statistics()
        self.output = []
        self.handlers = {
            "RESTART": self.restart,
            "REVEAL": self.reveal,
            "FLAG": self.flag,
            "UNFLAG": self.unflag,
            "QUESTION": self.question,
            "CHORD": self.chord,
            "UNDO": self.undo,
            "SHOW": self.show,
            "STATUS": self.status,
            "CELL": self.describe_cell,
            "HISTORY": self.history,
            "REPLAY": self.replay,
            "HINT": self.hint,
            "AUTO": self.auto,
            "ANALYZE": self.analyze,
            "PROB": self.probability,
            "FRONTIER": self.frontier,
            "SOLVE": self.solve,
            "BOARDINFO": self.board_info,
        }

    def emit(self, *parts):
        self.output.append(" ".join(str(part) for part in parts))

    def target(self, arguments):
        return int(arguments[1]) * self.game.width + int(arguments[0])

    def hidden_target(self, arguments):
        cell = self.target(arguments)
        if self.game.revealed[cell]:
            raise CommandError("already revealed")
        return cell

    def open_cell(self, cell):
        if not self.game.placed:
            self.game.place_mines(cell, self.safety)
        return self.game.reveal(cell)

    def report_outcome(self):
        game = self.game
        if game.state == "lost":
            self.emit("boom", game.cell_name(game.exploded))
            self.output.extend(game.display())
        elif game.state == "won":
            self.emit("win", "moves", len(game.moves))
        else:
            return
        self.statistics.record(game)

    def layout(self, width, height, rows):
        for number, row in enumerate(rows, 1):
            if len(row) != width or any(symbol not in "*." for symbol in row):
                raise CommandError(f"bad row {number}")
        mines = sum(row.count("*") for row in rows)
        if mines == 0 or mines == width * height:
            raise CommandError(f"bad mine count {mines}")
        game = Game(width, height, mines, 0)
        game.set_mines([symbol == "*" for row in rows for symbol in row])
        self.game = game
        self.emit("layout", f"{width}x{height}", "mines", mines)

    def new_game(self, width, height, mines, seed):
        if not valid_board(width, height, mines, seed):
            raise CommandError("bad value")
        self.game = Game(width, height, mines, seed)
        self.emit("new", f"{width}x{height}", "mines", mines)

    def restart(self, arguments):
        game = self.game
        game.restart()
        self.emit("restart", f"{game.width}x{game.height}", "mines", game.mine_count)

    def reveal(self, arguments):
        game = self.game
        cell = self.hidden_target(arguments)
        if game.marks[cell] == "flag":
            raise CommandError("flagged")
        game.moves.append(("reveal", cell))
        opened = self.open_cell(cell)
        if game.state != "lost":
            self.emit("revealed", opened)
            game.check_win()
        self.report_outcome()

    def flag(self, arguments):
        game = self.game
        cell = self.hidden_target(arguments)
        if game.marks[cell] == "flag":
            raise CommandError("already flagged")
        game.marks[cell] = "flag"
        game.moves.append(("flag", cell))
        self.emit("flagged", game.cell_name(cell), "left", game.remaining_mines())

    def unflag(self, arguments):
        game = self.game
        cell = self.hidden_target(arguments)
        if game.marks[cell] != "flag":
            raise CommandError("not flagged")
        game.marks[cell] = "none"
        game.moves.append(("unflag", cell))
        self.emit("unflagged", game.cell_name(cell), "left", game.remaining_mines())

    def question(self, arguments):
        game = self.game
        cell = self.hidden_target(arguments)
        game.moves.append(("question", cell))
        game.toggle_question(cell)
        outcome = "questioned" if game.marks[cell] == "question" else "unmarked"
        self.emit(outcome, game.cell_name(cell), "left", game.remaining_mines())

    def chord(self, arguments):
        game = self.game
        cell = self.target(arguments)
        if not game.revealed[cell]:
            raise CommandError("not revealed")
        number = game.numbers[cell]
        if number == 0:
            raise CommandError("no number")
        flags = game.neighbor_flags(cell)
        if flags != number:
            raise CommandError(f"flags {flags} of {number}")
        if not game.unknown_neighbors(cell):
            raise CommandError("nothing to reveal")
        game.moves.append(("chord", cell))
        opened = game.chord(cell)
        if game.state != "lost":
            self.emit("chorded", opened)
            game.check_win()
        self.report_outcome()

    def undo(self, arguments):
        game = self.game
        if not game.undo_record:
            raise CommandError("nothing to undo")
        entry = game.undo_record.pop()
        game.restore(entry)
        self.emit("undo", entry.name, "moves", len(game.moves))

    def show(self, arguments):
        self.output.extend(self.game.display())

    def status(self, arguments):
        game = self.game
        self.emit(
            "status", game.state, "left", game.remaining_mines(), "moves", len(game.moves),
            "revealed", f"{game.revealed_count()}/{game.safe_count()}",
        )

    def describe_cell(self, arguments):
        game = self.game
        cell = self.target(arguments)
        name = game.cell_name(cell)
        if game.revealed[cell]:
            self.emit(
                "cell", name, "number", game.numbers[cell], "flags", game.neighbor_flags(cell),
                "unknown", len(game.unknown_neighbors(cell)),
            )
        else:
            opened = sum(game.revealed[neighbor] for neighbor in game.neighbors[cell])
            self.emit("cell", name, "hidden", "mark", game.marks[cell], "open", opened)

    def history(self, arguments):
        game = self.game
        total = len(game.moves)
        shown = min(int(arguments[0]), total)
        self.emit("history", total)
        for index in range(total - shown, total):
            kind, cell = game.moves[index]
            self.emit(index + 1, kind, game.cell_name(cell))

    def replay(self, arguments):
        game = self.game
        count = int(arguments[0])
        if count > len(game.moves):
            raise CommandError(f"no move {count}")
        self.emit("replay", f"{count}/{len(game.moves)}")
        self.output.extend(game.replay(count).display())

    def hint(self, arguments):
        game = self.game
        deduction = game.deduce()
        if deduction.safe:
            side, reasons = "safe", deduction.safe
        elif deduction.mines:
            side, reasons = "mine", deduction.mines
        else:
            self.emit("hint", "none")
            return
        cell = min(reasons)
        self.emit("hint", side, game.cell_name(cell), "by", reasons[cell])

    def auto(self, arguments):
        counts = PlayCounts()
        self.game.auto_play(counts)
        self.emit(
            "auto", "rounds", counts.rounds, "flagged", counts.flagged,
            "revealed", counts.opened,
        )
        self.report_outcome()

    def analyze(self, arguments):
        copy = self.game.clone()
        counts = PlayCounts()
        copy.auto_play(counts)
        if copy.state == "lost":
            self.emit("analyze", "boom", copy.cell_name(copy.exploded), "rounds", counts.rounds)
        elif copy.state == "won":
            self.emit("analyze", "clear", "rounds", counts.rounds)
        else:
            self.emit(
                "analyze", "stuck", "rounds", counts.rounds,
                "revealed", f"{copy.revealed_count()}/{copy.safe_count()}",
            )

    def probability(self, arguments):
        game = self.game
        cell = self.hidden_target(arguments)
        if game.marks[cell] == "flag":
            raise CommandError("flagged")
        name = game.cell_name(cell)
        component = next((c for c in game.components() if cell in c.cells), None)
        if component is None:
            self.emit("prob", name, "unconstrained")
            return
        component.count()
        if component.configurations == 0:
            self.emit("prob", name, "inconsistent")
            return
        chance = component.probability(component.cells.index(cell))
        self.emit(
            "prob", name, fraction_text(chance), "size", len(component.cells),
            "configs", component.configurations,
        )

    def frontier(self, arguments):
        game = self.game
        components = game.components()
        cells = sum(len(component.cells) for component in components)
        self.emit("frontier", cells, "components", len(components))
        for component in components:
            component.count()
            parts = ["component", game.cell_name(component.cells[0]), "size", len(component.cells)]
            if component.configurations > 0:
                parts.extend((
                    "configs", component.configurations,
                    "min", component.fewest_mines, "max", component.most_mines,
                ))
            else:
                parts.append("inconsistent")
            self.emit(*parts)

    def solve(self, arguments):
        game = self.game
        counts = PlayCounts()
        while True:
            game.auto_play(counts)
            if game.finished():
                break
            cell = game.guess_cell()
            if cell is None:
                break
            counts.guesses += 1
            game.moves.append(("guess", cell))
            counts.opened += self.open_cell(cell)
            game.check_win()
            if game.finished():
                break
        self.emit(
            "solve", "guesses", counts.guesses, "rounds", counts.rounds,
            "flagged", counts.flagged, "revealed", counts.opened,
        )
        self.report_outcome()

    def board_info(self, arguments):
        game = self.game
        three_bv, openings, largest = game.board_info()
        self.emit(
            "3bv", three_bv, "openings", openings, "largest", largest,
            "mines", game.mine_count, "safe", game.safe_count(),
        )

    def run_game_command(self, name, arguments):
        game = self.game
        if game is None:
            raise CommandError("no game")
        if name in CELL_COMMANDS:
            if int(arguments[0]) >= game.width or int(arguments[1]) >= game.height:
                raise CommandError("out of range")
        if name in PLAY_COMMANDS and game.finished():
            raise CommandError("game over")
        if name in ("ANALYZE", "BOARDINFO") and not game.placed:
            raise CommandError("not started")
        if name not in UNDOABLE_COMMANDS:
            self.handlers[name](arguments)
            return
        entry = game.snapshot(name.lower())
        self.handlers[name](arguments)
        if len(game.moves) > len(entry.moves):
            game.undo_record.append(entry)

    def run_command(self, name, arguments):
        if name not in COMMANDS:
            raise CommandError(f"unknown command {name}")
        kinds = COMMANDS[name]
        if len(arguments) != len(kinds) or not all(map(valid_argument, kinds, arguments)):
            raise CommandError("bad arguments")
        if name == "HISTORY" and int(arguments[0]) == 0:
            raise CommandError("bad value")
        if name in ("NEW", "PRESET"):
            self.new_game(*board_parameters(name, arguments))
        elif name == "SAFETY":
            self.safety = arguments[0]
            self.emit("safety", self.safety)
        elif name == "STATS":
            self.emit(self.statistics.summary())
        else:
            self.run_game_command(name, arguments)

    def execute(self, words, rows):
        try:
            if words[0] == "LAYOUT":
                self.layout(int(words[1]), int(words[2]), rows)
            else:
                self.run_command(words[0], words[1:])
        except CommandError as error:
            self.emit(f"error: {error}")


def main():
    engine = Minesweeper()
    count = int(sys.stdin.readline())
    for _ in range(count):
        words = sys.stdin.readline().rstrip("\n").split(" ")
        rows = []
        if words[0] == "LAYOUT":
            rows = [sys.stdin.readline().rstrip("\n") for _ in range(int(words[2]))]
        engine.execute(words, rows)
    sys.stdout.write("\n".join(engine.output) + "\n")


if __name__ == "__main__":
    main()
