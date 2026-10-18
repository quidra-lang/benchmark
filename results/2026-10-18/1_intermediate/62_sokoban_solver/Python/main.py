from collections import deque
from itertools import permutations
import re
import sys


DIRECTIONS = "udlr"
DELTAS = {"u": (-1, 0), "d": (1, 0), "l": (0, -1), "r": (0, 1)}
TURNS = {
    "ROT90": "rlud",
    "ROT180": "durl",
    "ROT270": "lrdu",
    "FLIPH": "udrl",
    "FLIPV": "dulr",
}
STEP_LETTERS = "udlrUDLR"
LEVEL_CHARACTERS = "#-.$*@+"
DIGITS = "0123456789"
MAX_SIDE = 10
MAX_LIMIT = 100000
NUMBER_WORD = re.compile(r"0|[1-9][0-9]{0,5}")
NAME_WORD = re.compile(r"[a-z]{1,8}")
CELL = ("number", "number")
COMMANDS = {
    "IMPORT": ("text",),
    "VALID": (),
    "INFO": (),
    "SHOW": (),
    "EXPORT": (),
    "MOVE": ("steps",),
    "PUSH": CELL + ("direction",),
    "BRING": CELL + CELL,
    "PATH": CELL,
    "UNDO": ("number",),
    "REDO": ("number",),
    "RESET": (),
    "STATUS": (),
    "HISTORY": (),
    "BOXES": (),
    "REACH": (),
    "DEADSQUARES": (),
    "DEADLOCK": (),
    "BOUND": (),
    "SAVE": ("name",),
    "RESTORE": ("name",),
    "CHECK": ("steps",),
    "SOLVE": ("number",),
    "HINT": ("number",),
    "PLAY": (),
    "TRANSFORM": ("transform",),
}
CELL_COUNTS = {"PATH": 1, "PUSH": 1, "BRING": 2}
LEVEL_FREE_COMMANDS = ("IMPORT", "VALID")


def decode(text, allowed):
    pieces = []
    index = 0
    while index < len(text):
        start = index
        while index < len(text) and text[index] in DIGITS:
            index += 1
        count = text[start:index]
        if len(count) > 2 or count.startswith("0") or index == len(text):
            return None
        if text[index] not in allowed:
            return None
        pieces.append(text[index] * (int(count) if count else 1))
        index += 1
    return "".join(pieces)


def encode(text):
    pieces = []
    start = 0
    while start < len(text):
        end = start
        while end < len(text) and text[end] == text[start]:
            end += 1
        run = end - start
        pieces.append((str(run) if run > 1 else "") + text[start])
        start = end
    return "".join(pieces)


def step_sequence(word):
    return decode(word, STEP_LETTERS).lower()


def valid_argument(kind, text):
    if kind == "number":
        return NUMBER_WORD.fullmatch(text) is not None
    if kind == "steps":
        return decode(text, STEP_LETTERS) is not None
    if kind == "direction":
        return len(text) == 1 and text in DIRECTIONS
    if kind == "name":
        return NAME_WORD.fullmatch(text) is not None
    if kind == "transform":
        return text in TURNS
    return True


def push_count(letters):
    return sum(letter.isupper() for letter in letters)


def turn_letters(letters, kind):
    turned = []
    for letter in letters:
        direction = TURNS[kind][DIRECTIONS.index(letter.lower())]
        turned.append(direction.upper() if letter.isupper() else direction)
    return turned


def move_box(boxes, source, destination):
    return tuple(sorted(destination if box == source else box for box in boxes))


def counted(label, letters):
    if not letters:
        return label, 0
    return label, len(letters), "".join(letters)


def find_interior(height, width, walls, start):
    interior = [False] * (height * width)
    interior[start] = True
    stack = [start]
    while stack:
        cell = stack.pop()
        row, column = divmod(cell, width)
        for d_row, d_column in DELTAS.values():
            next_row, next_column = row + d_row, column + d_column
            if 0 <= next_row < height and 0 <= next_column < width:
                neighbor = next_row * width + next_column
                if not walls[neighbor] and not interior[neighbor]:
                    interior[neighbor] = True
                    stack.append(neighbor)
    return interior


class CommandError(Exception):
    pass


class StepFailure(Exception):
    pass


class Position:
    def __init__(self, player, boxes):
        self.player = player
        self.boxes = boxes

    def same(self, other):
        return self.player == other.player and self.boxes == other.boxes


class Level:
    def __init__(self, height, width, walls, goals, interior):
        self.height = height
        self.width = width
        self.size = height * width
        self.walls = walls
        self.goals = goals
        self.interior = interior
        self.offsets = {
            direction: d_row * width + d_column
            for direction, (d_row, d_column) in DELTAS.items()
        }
        self.goal_cells = [cell for cell in range(self.size) if goals[cell]]
        self.reason = None
        self.distances = []
        self.dead = [False] * self.size

    def cell_text(self, cell):
        row, column = divmod(cell, self.width)
        return f"{row + 1} {column + 1}"

    def cell_at(self, row, column):
        return (row - 1) * self.width + column - 1

    def contains(self, row, column):
        return 1 <= row <= self.height and 1 <= column <= self.width

    def on_border(self, cell):
        row, column = divmod(cell, self.width)
        return row in (0, self.height - 1) or column in (0, self.width - 1)

    def invalidity(self, players, boxes):
        if players != 1:
            return f"players {players}"
        if not boxes:
            return "no boxes"
        if len(boxes) != len(self.goal_cells):
            return f"boxes {len(boxes)} goals {len(self.goal_cells)}"
        for cell in range(self.size):
            if self.interior[cell] and self.on_border(cell):
                return "open " + self.cell_text(cell)
        for cell in range(self.size):
            if (self.goals[cell] or cell in boxes) and not self.interior[cell]:
                return "outside " + self.cell_text(cell)
        return None

    def analyze(self):
        self.distances = [self.push_distances(goal) for goal in self.goal_cells]
        self.dead = [
            self.interior[cell]
            and all(distance[cell] is None for distance in self.distances)
            for cell in range(self.size)
        ]

    def push_distances(self, goal):
        distance = [None] * self.size
        distance[goal] = 0
        queue = deque([goal])
        while queue:
            cell = queue.popleft()
            for direction in DIRECTIONS:
                offset = self.offsets[direction]
                box = cell - offset
                if (
                    self.interior[box]
                    and self.interior[box - offset]
                    and distance[box] is None
                ):
                    distance[box] = distance[cell] + 1
                    queue.append(box)
        return distance

    def goal_distance(self, cell):
        defined = [
            distance[cell] for distance in self.distances if distance[cell] is not None
        ]
        return min(defined) if defined else None

    def boxes_on_goals(self, boxes):
        return sum(self.goals[box] for box in boxes)

    def solved(self, boxes):
        return self.boxes_on_goals(boxes) == len(boxes)

    def reachable(self, player, boxes):
        seen = [False] * self.size
        seen[player] = True
        stack = [player]
        while stack:
            cell = stack.pop()
            for offset in self.offsets.values():
                neighbor = cell + offset
                if self.interior[neighbor] and not seen[neighbor] and neighbor not in boxes:
                    seen[neighbor] = True
                    stack.append(neighbor)
        return seen

    def representative(self, player, boxes):
        return self.reachable(player, boxes).index(True)

    def walk_path(self, start, target, boxes):
        came_from = [None] * self.size
        queue = deque([start])
        while queue:
            cell = queue.popleft()
            for direction in DIRECTIONS:
                neighbor = cell + self.offsets[direction]
                if (
                    self.interior[neighbor]
                    and neighbor not in boxes
                    and neighbor != start
                    and came_from[neighbor] is None
                ):
                    came_from[neighbor] = (cell, direction)
                    queue.append(neighbor)
        directions = []
        cell = target
        while cell != start:
            cell, direction = came_from[cell]
            directions.append(direction)
        return "".join(reversed(directions))

    def step(self, position, direction):
        offset = self.offsets[direction]
        target = position.player + offset
        if self.walls[target]:
            raise StepFailure("wall")
        if target not in position.boxes:
            return Position(target, position.boxes), direction
        beyond = target + offset
        if self.walls[beyond] or beyond in position.boxes:
            raise StepFailure("blocked")
        return Position(target, move_box(position.boxes, target, beyond)), direction.upper()

    def pushable(self, box, direction, boxes, reachable):
        offset = self.offsets[direction]
        destination = box + offset
        return (
            reachable[box - offset]
            and self.interior[destination]
            and destination not in boxes
        )

    def side_blocked(self, box, sides, boxes, assumed):
        if any(self.walls[side] or side in assumed for side in sides):
            return True
        if all(self.dead[side] for side in sides):
            return True
        extended = assumed + (box,)
        return any(side in boxes and self.frozen(side, boxes, extended) for side in sides)

    def frozen(self, box, boxes, assumed):
        horizontal = (box + self.offsets["l"], box + self.offsets["r"])
        vertical = (box + self.offsets["u"], box + self.offsets["d"])
        return (
            self.side_blocked(box, horizontal, boxes, assumed)
            and self.side_blocked(box, vertical, boxes, assumed)
        )

    def has_frozen_box(self, boxes):
        return any(not self.goals[box] and self.frozen(box, boxes, ()) for box in boxes)

    def split_rows(self, symbols):
        return [
            "".join(symbols[start:start + self.width])
            for start in range(0, self.size, self.width)
        ]

    def symbol(self, cell, position):
        if self.walls[cell]:
            return "#"
        if cell == position.player:
            return "+" if self.goals[cell] else "@"
        if cell in position.boxes:
            return "*" if self.goals[cell] else "$"
        return "." if self.goals[cell] else "-"

    def render(self, position):
        return self.split_rows([self.symbol(cell, position) for cell in range(self.size)])

    def dead_symbol(self, cell):
        if self.walls[cell]:
            return "#"
        if self.goals[cell]:
            return "."
        return "x" if self.dead[cell] else "-"

    def dead_map(self):
        return self.split_rows([self.dead_symbol(cell) for cell in range(self.size)])

    def map_cell(self, kind, cell):
        row, column = divmod(cell, self.width)
        last_row, last_column = self.height - 1, self.width - 1
        if kind == "ROT90":
            return column * self.height + last_row - row
        if kind == "ROT180":
            return (last_row - row) * self.width + last_column - column
        if kind == "ROT270":
            return (last_column - column) * self.height + row
        if kind == "FLIPH":
            return row * self.width + last_column - column
        return (last_row - row) * self.width + column

    def map_position(self, kind, position):
        boxes = tuple(sorted(self.map_cell(kind, box) for box in position.boxes))
        return Position(self.map_cell(kind, position.player), boxes)

    def transformed(self, kind):
        if kind in ("ROT90", "ROT270"):
            height, width = self.width, self.height
        else:
            height, width = self.height, self.width
        walls = [False] * self.size
        goals = [False] * self.size
        interior = [False] * self.size
        for cell in range(self.size):
            moved = self.map_cell(kind, cell)
            walls[moved] = self.walls[cell]
            goals[moved] = self.goals[cell]
            interior[moved] = self.interior[cell]
        level = Level(height, width, walls, goals, interior)
        level.analyze()
        return level


def build_level(rows):
    height, width = len(rows), len(rows[0])
    cells = "".join(rows)
    walls = [symbol == "#" for symbol in cells]
    goals = [symbol in ".*+" for symbol in cells]
    players = [cell for cell, symbol in enumerate(cells) if symbol in "@+"]
    boxes = tuple(cell for cell, symbol in enumerate(cells) if symbol in "$*")
    if len(players) == 1:
        interior = find_interior(height, width, walls, players[0])
    else:
        interior = [False] * len(cells)
    level = Level(height, width, walls, goals, interior)
    level.reason = level.invalidity(len(players), boxes)
    if level.reason is None:
        level.analyze()
    player = players[0] if players else None
    return level, Position(player, boxes)


class SearchNode:
    def __init__(self, boxes, representative, parent, push):
        self.boxes = boxes
        self.representative = representative
        self.parent = parent
        self.push = push


class SearchResult:
    def __init__(self, outcome, expanded, states, notation=""):
        self.outcome = outcome
        self.expanded = expanded
        self.states = states
        self.notation = notation


def solution_pushes(nodes):
    pushes = []
    node = nodes[-1]
    while node.parent is not None:
        pushes.append(node.push)
        node = nodes[node.parent]
    pushes.reverse()
    return pushes


def solution_notation(level, position, pushes):
    pieces = []
    for box, direction in pushes:
        offset = level.offsets[direction]
        pieces.append(level.walk_path(position.player, box - offset, position.boxes))
        pieces.append(direction.upper())
        position = Position(box, move_box(position.boxes, box, box + offset))
    return "".join(pieces)


def push_search(level, start, fixed, target, pruning, limit):
    first = SearchNode(
        start.boxes, level.representative(start.player, start.boxes), None, None
    )
    nodes = [first]
    known = {(first.boxes, first.representative)}
    expanded = 0
    while expanded < len(nodes):
        if expanded == limit:
            return SearchResult("limit", expanded, len(nodes))
        node = nodes[expanded]
        expanded += 1
        reachable = level.reachable(node.representative, node.boxes)
        for box in node.boxes:
            if box in fixed:
                continue
            for direction in DIRECTIONS:
                if not level.pushable(box, direction, node.boxes, reachable):
                    continue
                destination = box + level.offsets[direction]
                boxes = move_box(node.boxes, box, destination)
                if pruning and (level.dead[destination] or level.has_frozen_box(boxes)):
                    continue
                state = (boxes, level.representative(box, boxes))
                if state in known:
                    continue
                known.add(state)
                nodes.append(SearchNode(boxes, state[1], expanded - 1, (box, direction)))
                reached = level.solved(boxes) if target is None else destination == target
                if reached:
                    notation = solution_notation(level, start, solution_pushes(nodes))
                    return SearchResult("found", expanded, len(nodes), notation)
    return SearchResult("no solution", expanded, len(nodes))


class Sokoban:
    def __init__(self, rows):
        self.output = []
        self.handlers = {
            "IMPORT": self.import_level,
            "VALID": self.valid,
            "INFO": self.info,
            "SHOW": self.show,
            "EXPORT": self.export,
            "MOVE": self.move,
            "PUSH": self.push,
            "BRING": self.bring,
            "PATH": self.path,
            "UNDO": self.undo,
            "REDO": self.redo,
            "RESET": self.reset,
            "STATUS": self.status,
            "HISTORY": self.show_history,
            "BOXES": self.boxes,
            "REACH": self.reach,
            "DEADSQUARES": self.dead_squares,
            "DEADLOCK": self.deadlock,
            "BOUND": self.bound,
            "SAVE": self.save,
            "RESTORE": self.restore,
            "CHECK": self.check,
            "SOLVE": self.solve,
            "HINT": self.hint,
            "PLAY": self.play,
            "TRANSFORM": self.transform,
        }
        self.load(rows)

    def emit(self, *parts):
        self.output.append(" ".join(str(part) for part in parts))

    def load(self, rows):
        self.level, self.initial = build_level(rows)
        self.current = self.initial
        self.history = []
        self.redo_list = []
        self.snapshots = {}
        self.solution = None

    def cell_argument(self, arguments, index):
        return self.level.cell_at(int(arguments[index]), int(arguments[index + 1]))

    def simulate(self, directions):
        position = self.current
        letters = []
        try:
            for direction in directions:
                position, letter = self.level.step(position, direction)
                letters.append(letter)
        except StepFailure as failure:
            return position, letters, f"step {len(letters) + 1} {failure}"
        return position, letters, None

    def take_steps(self, directions):
        self.current, letters, failure = self.simulate(directions)
        self.history.extend(letters)
        if letters:
            self.redo_list = []
        return letters, failure

    def progress(self, boxes):
        on_goals = self.level.boxes_on_goals(boxes)
        parts = ["goals", f"{on_goals}/{len(boxes)}"]
        if on_goals == len(boxes):
            parts.append("solved")
        return parts

    def search_solution(self, limit):
        if self.level.solved(self.current.boxes):
            return "already solved", None
        result = push_search(self.level, self.current, (), None, True, limit)
        counts = f"expanded {result.expanded} states {result.states}"
        if result.outcome != "found":
            return f"{result.outcome} {counts}", None
        notation = result.notation
        summary = f"solution pushes {push_count(notation)} moves {len(notation)} {counts}"
        return summary, notation

    def load_rows(self, width, rows):
        for number, row in enumerate(rows, 1):
            if len(row) != width or any(symbol not in LEVEL_CHARACTERS for symbol in row):
                raise CommandError(f"bad row {number}")
        self.load(rows)
        self.emit("loaded", f"{len(rows)}x{width}")

    def import_level(self, arguments):
        rows = [decode(part, LEVEL_CHARACTERS) for part in arguments[0].split("|")]
        if None in rows or len(rows) > MAX_SIDE:
            raise CommandError("bad level")
        width = len(rows[0])
        if any(len(row) != width for row in rows) or not 1 <= width <= MAX_SIDE:
            raise CommandError("bad level")
        self.load(rows)
        self.emit("loaded", f"{len(rows)}x{width}")

    def valid(self, arguments):
        if self.level.reason is None:
            self.emit("valid")
        else:
            self.emit("invalid", self.level.reason)

    def info(self, arguments):
        level = self.level
        self.emit(
            "size", f"{level.height}x{level.width}", "walls", sum(level.walls),
            "cells", sum(level.interior), "boxes", len(self.current.boxes),
            "dead", sum(level.dead),
        )

    def show(self, arguments):
        for row in self.level.render(self.current):
            self.emit(row)

    def export(self, arguments):
        rows = self.level.render(self.current)
        self.emit("level", "|".join(encode(row) for row in rows))

    def move(self, arguments):
        letters, failure = self.take_steps(step_sequence(arguments[0]))
        if letters:
            self.emit("moved", "".join(letters))
        if failure is not None:
            raise CommandError(failure)

    def push(self, arguments):
        level, position = self.level, self.current
        box = self.cell_argument(arguments, 0)
        direction = arguments[2]
        offset = level.offsets[direction]
        if box not in position.boxes:
            raise CommandError("no box")
        destination = box + offset
        if not level.interior[destination] or destination in position.boxes:
            raise CommandError("blocked")
        if not level.reachable(position.player, position.boxes)[box - offset]:
            raise CommandError("unreachable")
        path = level.walk_path(position.player, box - offset, position.boxes)
        letters, _ = self.take_steps(path + direction)
        self.emit("pushed", "".join(letters))

    def bring(self, arguments):
        position = self.current
        source = self.cell_argument(arguments, 0)
        target = self.cell_argument(arguments, 2)
        if source not in position.boxes:
            raise CommandError("no box")
        if source == target:
            self.emit("brought", 0)
            return
        fixed = tuple(box for box in position.boxes if box != source)
        result = push_search(self.level, position, fixed, target, False, None)
        if result.outcome != "found":
            raise CommandError("no route")
        self.take_steps(result.notation.lower())
        self.emit("brought", push_count(result.notation), result.notation)

    def path(self, arguments):
        level, position = self.level, self.current
        target = self.cell_argument(arguments, 0)
        if not level.reachable(position.player, position.boxes)[target]:
            raise CommandError("unreachable")
        letters, _ = self.take_steps(level.walk_path(position.player, target, position.boxes))
        self.emit(*counted("path", letters))

    def undo(self, arguments):
        if not self.history:
            raise CommandError("nothing to undo")
        count = min(int(arguments[0]), len(self.history))
        for _ in range(count):
            letter = self.history.pop()
            direction = letter.lower()
            offset = self.level.offsets[direction]
            player = self.current.player
            boxes = self.current.boxes
            if letter.isupper():
                boxes = move_box(boxes, player + offset, player)
            self.current = Position(player - offset, boxes)
            self.redo_list.append(direction)
        self.emit("undone", count)

    def redo(self, arguments):
        if not self.redo_list:
            raise CommandError("nothing to redo")
        count = min(int(arguments[0]), len(self.redo_list))
        for _ in range(count):
            direction = self.redo_list.pop()
            self.current, letter = self.level.step(self.current, direction)
            self.history.append(letter)
        self.emit("redone", count)

    def reset(self, arguments):
        self.current = self.initial
        self.history = []
        self.redo_list = []
        self.emit("reset")

    def status(self, arguments):
        self.emit(
            "moves", len(self.history), "pushes", push_count(self.history),
            *self.progress(self.current.boxes),
        )

    def show_history(self, arguments):
        self.emit(*counted("history", self.history))

    def boxes(self, arguments):
        level, position = self.level, self.current
        reachable = level.reachable(position.player, position.boxes)
        self.emit("boxes", len(position.boxes))
        for box in position.boxes:
            distance = level.goal_distance(box)
            directions = "".join(
                direction for direction in DIRECTIONS
                if level.pushable(box, direction, position.boxes, reachable)
            )
            self.emit(
                "box", level.cell_text(box), "dead" if distance is None else distance,
                directions or "-",
            )

    def reach(self, arguments):
        position = self.current
        reachable = self.level.reachable(position.player, position.boxes)
        first = self.level.cell_text(reachable.index(True))
        self.emit("reach", sum(reachable), "first", first)

    def dead_squares(self, arguments):
        self.emit("dead", sum(self.level.dead))
        for row in self.level.dead_map():
            self.emit(row)

    def deadlock(self, arguments):
        level, boxes = self.level, self.current.boxes
        for box in boxes:
            if level.dead[box]:
                self.emit("deadlock", "dead", level.cell_text(box))
                return
        for box in boxes:
            if not level.goals[box] and level.frozen(box, boxes, ()):
                self.emit("deadlock", "frozen", level.cell_text(box))
                return
        self.emit("no deadlock")

    def bound(self, arguments):
        level, boxes = self.level, self.current.boxes
        best = None
        for order in permutations(range(len(level.goal_cells))):
            pushes = [level.distances[goal][box] for box, goal in zip(boxes, order)]
            if None in pushes:
                continue
            if best is None or sum(pushes) < sum(best[1]):
                best = (order, pushes)
        if best is None:
            self.emit("bound", "none")
            return
        order, pushes = best
        self.emit("bound", sum(pushes))
        for box, goal, count in zip(boxes, order, pushes):
            self.emit(
                "box", level.cell_text(box), "goal", level.cell_text(level.goal_cells[goal]),
                "pushes", count,
            )

    def save(self, arguments):
        name = arguments[0]
        self.snapshots[name] = (self.current, list(self.history))
        self.emit("saved", name, "moves", len(self.history))

    def restore(self, arguments):
        name = arguments[0]
        if name not in self.snapshots:
            raise CommandError(f"no snapshot {name}")
        position, history = self.snapshots[name]
        self.current = position
        self.history = list(history)
        self.redo_list = []
        self.emit("restored", name, "moves", len(self.history))

    def check(self, arguments):
        position, letters, failure = self.simulate(step_sequence(arguments[0]))
        if failure is not None:
            self.emit("check", "fail", failure)
            return
        self.emit(
            "check", "ok", "moves", len(letters), "pushes", push_count(letters),
            *self.progress(position.boxes),
        )

    def solve(self, arguments):
        summary, notation = self.search_solution(int(arguments[0]))
        self.emit(summary)
        self.solution = None
        if notation is not None:
            self.emit(notation)
            self.solution = (notation, self.current)

    def hint(self, arguments):
        summary, notation = self.search_solution(int(arguments[0]))
        if notation is None:
            self.emit(summary)
            return
        end = next(index for index, letter in enumerate(notation) if letter.isupper())
        part = notation[:end + 1]
        self.take_steps(part.lower())
        self.emit("hint", part)

    def play(self, arguments):
        if self.solution is None or not self.solution[1].same(self.current):
            raise CommandError("no solution")
        notation = self.solution[0]
        self.take_steps(notation.lower())
        self.emit("played", "pushes", push_count(notation), "moves", len(notation))

    def transform(self, arguments):
        kind = arguments[0]
        old = self.level
        self.level = old.transformed(kind)
        self.initial = old.map_position(kind, self.initial)
        self.current = old.map_position(kind, self.current)
        self.history = turn_letters(self.history, kind)
        self.redo_list = turn_letters(self.redo_list, kind)
        self.snapshots = {
            name: (old.map_position(kind, position), turn_letters(history, kind))
            for name, (position, history) in self.snapshots.items()
        }
        if self.solution is not None:
            notation, position = self.solution
            self.solution = (
                "".join(turn_letters(notation, kind)), old.map_position(kind, position)
            )
        self.emit("transformed", f"{self.level.height}x{self.level.width}")

    def check_values(self, name, arguments):
        for index in range(0, 2 * CELL_COUNTS.get(name, 0), 2):
            if not self.level.contains(int(arguments[index]), int(arguments[index + 1])):
                raise CommandError("bad value")
        if name in ("UNDO", "REDO") and int(arguments[0]) < 1:
            raise CommandError("bad value")
        if name in ("SOLVE", "HINT") and not 1 <= int(arguments[0]) <= MAX_LIMIT:
            raise CommandError("bad value")

    def run_command(self, name, arguments):
        if name not in COMMANDS:
            raise CommandError(f"unknown command {name}")
        kinds = COMMANDS[name]
        if len(arguments) != len(kinds) or not all(map(valid_argument, kinds, arguments)):
            raise CommandError("bad arguments")
        if name not in LEVEL_FREE_COMMANDS:
            if self.level.reason is not None:
                raise CommandError("invalid level")
            self.check_values(name, arguments)
        self.handlers[name](arguments)

    def execute(self, words, rows):
        try:
            if words[0] == "LOAD":
                self.load_rows(int(words[2]), rows)
            else:
                self.run_command(words[0], words[1:])
        except CommandError as error:
            self.emit("error:", error)


def main():
    height = int(sys.stdin.readline().split()[0])
    rows = [sys.stdin.readline().rstrip("\n") for _ in range(height)]
    game = Sokoban(rows)
    count = int(sys.stdin.readline())
    for _ in range(count):
        words = sys.stdin.readline().rstrip("\n").split(" ")
        rows = []
        if words[0] == "LOAD":
            rows = [sys.stdin.readline().rstrip("\n") for _ in range(int(words[1]))]
        game.execute(words, rows)
    sys.stdout.write("\n".join(game.output) + "\n")


if __name__ == "__main__":
    main()
