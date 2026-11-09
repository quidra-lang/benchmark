from collections import deque, namedtuple
import copy
import re
import sys


WIDTH = 10
HEIGHT = 22
VISIBLE_HEIGHT = 20
MULTIPLIER = 48271
MODULUS = 2147483647
KINDS = "IOTSZJL"
STATE_NAMES = ("0", "R", "2", "L")
SHAPE_ROWS = {
    "I": ("....", "####", "....", "...."),
    "O": ("##", "##"),
    "T": (".#.", "###", "..."),
    "S": (".##", "##.", "..."),
    "Z": ("##.", ".##", "..."),
    "J": ("#..", "###", "..."),
    "L": ("..#", "###", "..."),
}
KICKS = {
    (0, 1): ((0, 0), (-1, 0), (-1, 1), (0, -2), (-1, -2)),
    (1, 0): ((0, 0), (1, 0), (1, -1), (0, 2), (1, 2)),
    (1, 2): ((0, 0), (1, 0), (1, -1), (0, 2), (1, 2)),
    (2, 1): ((0, 0), (-1, 0), (-1, 1), (0, -2), (-1, -2)),
    (2, 3): ((0, 0), (1, 0), (1, 1), (0, -2), (1, -2)),
    (3, 2): ((0, 0), (-1, 0), (-1, -1), (0, 2), (-1, 2)),
    (3, 0): ((0, 0), (-1, 0), (-1, -1), (0, 2), (-1, 2)),
    (0, 3): ((0, 0), (1, 0), (1, 1), (0, -2), (1, -2)),
}
I_KICKS = {
    (0, 1): ((0, 0), (-2, 0), (1, 0), (-2, -1), (1, 2)),
    (1, 0): ((0, 0), (2, 0), (-1, 0), (2, 1), (-1, -2)),
    (1, 2): ((0, 0), (-1, 0), (2, 0), (-1, 2), (2, -1)),
    (2, 1): ((0, 0), (1, 0), (-2, 0), (1, -2), (-2, 1)),
    (2, 3): ((0, 0), (2, 0), (-1, 0), (2, 1), (-1, -2)),
    (3, 2): ((0, 0), (-2, 0), (1, 0), (-2, -1), (1, 2)),
    (3, 0): ((0, 0), (1, 0), (-2, 0), (1, -2), (-2, 1)),
    (0, 3): ((0, 0), (-1, 0), (2, 0), (-1, 2), (2, -1)),
}
GRAVITY = (60, 48, 37, 28, 21, 16, 11, 8, 6, 4, 3, 2)
LOCK_DELAY = 30
MAX_RESETS = 15
MAX_RISE = 8
COMBO_LINES = (0, 1, 1, 2, 2, 3, 3, 4, 4, 4, 5)
PERFECT_POINTS = {1: 800, 2: 1200, 3: 1800, 4: 2000}
B2B_TETRIS_PERFECT_POINTS = 3200
CLEAR_TYPES = {
    (None, 1): ("SINGLE", 100, 0),
    (None, 2): ("DOUBLE", 300, 1),
    (None, 3): ("TRIPLE", 500, 2),
    (None, 4): ("TETRIS", 800, 4),
    ("mini", 0): ("TSPIN_MINI", 100, 0),
    ("mini", 1): ("TSPIN_MINI_SINGLE", 200, 0),
    ("mini", 2): ("TSPIN_MINI_DOUBLE", 400, 1),
    ("full", 0): ("TSPIN", 400, 0),
    ("full", 1): ("TSPIN_SINGLE", 800, 2),
    ("full", 2): ("TSPIN_DOUBLE", 1200, 4),
    ("full", 3): ("TSPIN_TRIPLE", 1600, 6),
}
TSPIN_LABELS = (
    ("mini", "TSPIN_MINI"),
    ("mini_single", "TSPIN_MINI_SINGLE"),
    ("mini_double", "TSPIN_MINI_DOUBLE"),
    ("zero", "TSPIN"),
    ("single", "TSPIN_SINGLE"),
    ("double", "TSPIN_DOUBLE"),
    ("triple", "TSPIN_TRIPLE"),
)
ROTATIONS = ("CW", "CCW")
MOVEMENTS = ("L", "R", "LL", "RR", "SD", "DD") + ROTATIONS
OPERATIONS = MOVEMENTS + ("HD", "LOCK", "HOLD")
STEPS = {"L": (-1, 0), "R": (1, 0), "SD": (0, -1), "LL": (-1, 0), "RR": (1, 0), "DD": (0, -1)}
REPEATED = ("LL", "RR", "DD")
ROTATION_SEQUENCES = ((), ("CW",), ("CW", "CW"), ("CCW",))
START_EXCLUDED = ("history", "start_state", "saves")
SAVE_EXCLUDED = ("saves",)
NUMBER = re.compile(r"0|[1-9][0-9]*")
PATTERN = re.compile(r"[#.]{10}")
NAME = re.compile(r"[a-z]{1,8}")

Position = namedtuple("Position", "state x y")
Candidate = namedtuple("Candidate", "value kind operations")
Command = namedtuple("Command", "parsers after_end handler")


def rotation_states(rows):
    size = len(rows)
    blocks = [(i, j) for j, row in enumerate(rows) for i, mark in enumerate(row) if mark == "#"]
    states = []
    for _ in range(4):
        states.append(tuple(blocks))
        blocks = [(size - 1 - j, i) for i, j in blocks]
    return tuple(states)


SHAPES = {kind: rotation_states(rows) for kind, rows in SHAPE_ROWS.items()}
SPAWNS = {kind: Position(0, 5 if kind == "O" else 4, HEIGHT) for kind in KINDS}


def piece_cells(kind, position):
    return [(position.x + i, position.y - j) for i, j in SHAPES[kind][position.state]]


def lowest_row(kind, position):
    return min(row for _, row in piece_cells(kind, position))


def offset(position, dx, dy):
    return Position(position.state, position.x + dx, position.y + dy)


def next_random(value):
    return value * MULTIPLIER % MODULUS


def shuffled_bag(value):
    bag = list(KINDS)
    for i in range(len(bag) - 1, 0, -1):
        value = next_random(value)
        j = value % (i + 1)
        bag[i], bag[j] = bag[j], bag[i]
    return bag, value


def fall_interval(level):
    return GRAVITY[level - 1] if level <= len(GRAVITY) else 1


def ratio(numerator, denominator):
    if denominator == 0:
        return "0.00"
    hundredths = 100 * numerator // denominator
    return f"{hundredths // 100}.{hundredths % 100:02d}"


class GameOver(Exception):
    pass


class Well:
    def __init__(self):
        self.rows = [[False] * WIDTH for _ in range(HEIGHT)]

    def copy(self):
        well = Well()
        well.rows = [row[:] for row in self.rows]
        return well

    def filled(self, column, row):
        return self.rows[row - 1][column - 1]

    def blocked(self, column, row):
        return not (1 <= column <= WIDTH and 1 <= row <= HEIGHT) or self.filled(column, row)

    def fits(self, kind, position):
        return not any(self.blocked(column, row) for column, row in piece_cells(kind, position))

    def grounded(self, kind, position):
        return not self.fits(kind, offset(position, 0, -1))

    def landing(self, kind, position):
        while not self.grounded(kind, position):
            position = offset(position, 0, -1)
        return position

    def place(self, kind, position):
        for column, row in piece_cells(kind, position):
            self.rows[row - 1][column - 1] = True
        kept = [row for row in self.rows if not all(row)]
        cleared = HEIGHT - len(kept)
        self.rows = kept + [[False] * WIDTH for _ in range(cleared)]
        return cleared

    def is_empty(self):
        return not any(any(row) for row in self.rows)

    def set_row(self, row, pattern):
        self.rows[row - 1] = [mark == "#" for mark in pattern]

    def insert_garbage(self, count, hole):
        if any(any(row) for row in self.rows[HEIGHT - count:]):
            return False
        garbage = [[column != hole for column in range(1, WIDTH + 1)] for _ in range(count)]
        self.rows = garbage + self.rows[:HEIGHT - count]
        return True

    def metrics(self):
        heights = []
        holes = 0
        for column in range(WIDTH):
            height = max(
                (number for number, row in enumerate(self.rows, 1) if row[column]), default=0
            )
            heights.append(height)
            holes += sum(1 for row in self.rows[:height] if not row[column])
        bumpiness = sum(abs(left - right) for left, right in zip(heights, heights[1:]))
        return heights, holes, bumpiness


def evaluation(well, cleared):
    heights, holes, bumpiness = well.metrics()
    return 76 * cleared - 51 * sum(heights) - 36 * holes - 18 * bumpiness


def rotate(well, kind, position, operation):
    after = (position.state + (1 if operation == "CW" else 3)) % 4
    if kind == "O":
        kicks = ((0, 0),)
    else:
        kicks = (I_KICKS if kind == "I" else KICKS)[position.state, after]
    for test, (dx, dy) in enumerate(kicks, 1):
        target = Position(after, position.x + dx, position.y + dy)
        if well.fits(kind, target):
            return target, test
    return None


def move(well, kind, position, operation):
    if operation in ROTATIONS:
        return rotate(well, kind, position, operation)
    dx, dy = STEPS[operation]
    target = position
    while well.fits(kind, offset(target, dx, dy)):
        target = offset(target, dx, dy)
        if operation not in REPEATED:
            break
    return None if target == position else (target, 0)


def explore(well, kind, start):
    paths = {start: ()}
    frontier = deque([start])
    while frontier:
        position = frontier.popleft()
        yield position, paths[position]
        for operation in MOVEMENTS:
            moved = move(well, kind, position, operation)
            if moved is not None and moved[0] not in paths:
                paths[moved[0]] = paths[position] + (operation,)
                frontier.append(moved[0])


def shortest_sequence(well, kind, target):
    start = SPAWNS[kind]
    if not well.fits(kind, start):
        return None
    for position, path in explore(well, kind, start):
        if well.landing(kind, position) == target:
            return path
    return None


def tspin_type(well, position, test):
    state, x, y = position
    corners = [
        well.blocked(column, row)
        for column, row in ((x, y), (x + 2, y), (x + 2, y - 2), (x, y - 2))
    ]
    if sum(corners) < 3:
        return None
    if corners[state] and corners[(state + 1) % 4] or test == 5:
        return "full"
    return "mini"


def rotated(well, kind, position, rotations):
    for rotation in rotations:
        moved = move(well, kind, position, rotation)
        if moved is None:
            return None
        position = moved[0]
    return position


def shift_sequences(well, kind, position):
    yield (), position
    for step in ("L", "R"):
        current = position
        shifts = ()
        while (moved := move(well, kind, current, step)) is not None:
            current = moved[0]
            shifts += (step,)
            yield shifts, current


def placements(well, kind, start, prefix):
    candidates = []
    seen = set()
    for rotations in ROTATION_SEQUENCES:
        position = rotated(well, kind, start, rotations)
        if position is None:
            continue
        for shifts, shifted in shift_sequences(well, kind, position):
            landing = well.landing(kind, shifted)
            blocks = frozenset(piece_cells(kind, landing))
            if blocks in seen:
                continue
            seen.add(blocks)
            trial = well.copy()
            cleared = trial.place(kind, landing)
            operations = prefix + rotations + shifts + ("HD",)
            candidates.append(Candidate(evaluation(trial, cleared), kind, operations))
    return candidates


class Stats:
    def __init__(self):
        self.drop_total = 0
        self.hold_count = 0
        self.operation_total = 0
        self.faults = 0
        self.perfects = 0
        self.sent = 0
        self.cancelled = 0
        self.received = 0
        self.max_combo = 0
        self.max_chain = 0
        self.kind_counts = dict.fromkeys(KINDS, 0)
        self.clear_counts = {name: 0 for name, _, _ in CLEAR_TYPES.values()}


class Game:
    def __init__(self, number, seed, level):
        self.number = number
        self.well = Well()
        self.random_value = seed
        self.queue = []
        self.hold = None
        self.hold_used = False
        self.start_level = level
        self.level = level
        self.score = 0
        self.lines = 0
        self.pieces = 0
        self.streak = 0
        self.chain = 0
        self.pending = []
        self.stats = Stats()
        self.ended = False
        self.history = []
        self.start_state = None
        self.saves = {}
        self.add_bag()
        self.spawn(self.take_next())
        self.record_start()

    def snapshot(self, excluded):
        state = {key: value for key, value in vars(self).items() if key not in excluded}
        return copy.deepcopy(state)

    def restore(self, state):
        vars(self).update(copy.deepcopy(state))

    def record_start(self):
        self.start_state = self.snapshot(START_EXCLUDED)

    def draw_random(self):
        self.random_value = next_random(self.random_value)
        return self.random_value

    def add_bag(self):
        bag, self.random_value = shuffled_bag(self.random_value)
        self.queue.extend(bag)

    def take_next(self):
        kind = self.queue.pop(0)
        if len(self.queue) < 5:
            self.add_bag()
        return kind

    def spawn(self, kind):
        self.kind = kind
        self.position = SPAWNS[kind]
        self.last_motion = "none"
        self.rotation_test = 0
        self.operations = 0
        self.drop_points = 0
        self.fall_counter = 0
        self.ground_counter = 0
        self.resets = 0
        self.lowest = lowest_row(kind, self.position)
        if not self.well.fits(kind, self.position):
            self.game_over("block out")

    def update_position(self, position, motion, test=0):
        self.position = position
        self.last_motion = motion
        self.rotation_test = test
        lowest = lowest_row(self.kind, position)
        if lowest < self.lowest:
            self.lowest = lowest
            self.resets = 0

    def game_over(self, reason):
        print(f"game over {reason}")
        self.print_summary()
        self.ended = True
        raise GameOver

    def print_summary(self):
        stats = self.stats
        clears = stats.clear_counts
        print(
            f"summary game {self.number} score {self.score} level {self.level}"
            f" lines {self.lines} pieces {self.pieces}"
        )
        print(
            f"clears single {clears['SINGLE']} double {clears['DOUBLE']}"
            f" triple {clears['TRIPLE']} tetris {clears['TETRIS']} perfect {stats.perfects}"
        )
        print("tspins " + " ".join(f"{label} {clears[name]}" for label, name in TSPIN_LABELS))
        print("pieces " + " ".join(f"{kind} {count}" for kind, count in stats.kind_counts.items()))
        print(
            f"best combo {stats.max_combo} chain {stats.max_chain} holds {stats.hold_count}"
            f" drops {stats.drop_total} faults {stats.faults}"
        )
        print(f"garbage sent {stats.sent} cancelled {stats.cancelled} received {stats.received}")
        print(
            f"rates app {ratio(stats.sent, self.pieces)} apl {ratio(stats.sent, self.lines)}"
            f" kpp {ratio(stats.operation_total, self.pieces)}"
        )

    def perform(self, operations):
        for operation in operations:
            if not self.operate(operation):
                print(f"fail {operation}")

    def operate(self, operation):
        if operation == "HD":
            self.hard_drop()
        elif operation == "LOCK":
            if not self.well.grounded(self.kind, self.position):
                return False
            self.lock()
        elif operation == "HOLD":
            return self.hold_piece()
        else:
            return self.move_piece(operation)
        return True

    def add_drop_points(self, points):
        self.score += points
        self.drop_points += points
        self.stats.drop_total += points

    def move_piece(self, operation):
        self.operations += 1
        moved = move(self.well, self.kind, self.position, operation)
        if moved is None:
            return False
        target, test = moved
        if operation in ("SD", "DD"):
            self.add_drop_points(self.position.y - target.y)
            self.update_position(target, "move")
            self.fall_counter = 0
            self.ground_counter = 0
            return True
        if operation in ROTATIONS:
            self.update_position(target, "rotation", test)
        else:
            self.update_position(target, "move")
        if self.ground_counter > 0 and self.resets < MAX_RESETS:
            self.ground_counter = 0
            self.resets += 1
        return True

    def hard_drop(self):
        landing = self.well.landing(self.kind, self.position)
        rows = self.position.y - landing.y
        self.add_drop_points(2 * rows)
        if rows > 0:
            self.update_position(landing, "move")
        self.lock()

    def hold_piece(self):
        if self.hold_used:
            return False
        self.hold_used = True
        self.stats.hold_count += 1
        if self.hold is None:
            self.hold = self.kind
            self.spawn(self.take_next())
        else:
            kind = self.hold
            self.hold = self.kind
            self.spawn(kind)
        return True

    def tick(self):
        if not self.well.grounded(self.kind, self.position):
            self.ground_counter = 0
            self.fall_counter += 1
            if self.fall_counter >= fall_interval(self.level):
                self.update_position(offset(self.position, 0, -1), "move")
                self.fall_counter = 0
        else:
            self.ground_counter += 1
            if self.ground_counter >= LOCK_DELAY:
                self.lock()

    def lock(self):
        kind, position = self.kind, self.position
        shortest = shortest_sequence(self.well, kind, position)
        spin = None
        if kind == "T" and self.last_motion == "rotation":
            spin = tspin_type(self.well, position, self.rotation_test)
        blocks = piece_cells(kind, position)
        cleared = self.well.place(kind, position)
        self.history.append(self.start_state)
        self.pieces += 1
        self.stats.kind_counts[kind] += 1
        self.stats.operation_total += self.operations
        sent = self.score_lock(shortest, spin, cleared)
        if all(row > VISIBLE_HEIGHT for _, row in blocks):
            self.game_over("lock out")
        self.cancel_garbage(sent)
        if cleared == 0:
            self.receive_garbage()
        self.hold_used = False
        self.spawn(self.take_next())
        self.record_start()

    def score_lock(self, shortest, spin, cleared):
        stats = self.stats
        level = self.level
        clear_type = CLEAR_TYPES.get((spin, cleared))
        name, base_points, sent = clear_type or (None, 0, 0)
        points = base_points * level
        back_to_back = False
        if cleared > 0:
            self.streak += 1
            if cleared == 4 or spin is not None:
                self.chain += 1
                back_to_back = self.chain >= 2
            else:
                self.chain = 0
        else:
            self.streak = 0
        if back_to_back:
            points = points * 3 // 2
            sent += 1
        combo = self.streak - 1
        combo_points = 50 * combo * level if combo >= 1 else 0
        if combo >= 0:
            sent += COMBO_LINES[min(combo, len(COMBO_LINES) - 1)]
        perfect = cleared > 0 and self.well.is_empty()
        perfect_points = 0
        if perfect:
            if cleared == 4 and back_to_back:
                perfect_points = B2B_TETRIS_PERFECT_POINTS * level
            else:
                perfect_points = PERFECT_POINTS[cleared] * level
            sent += 10
            stats.perfects += 1
        gained = points + combo_points + perfect_points
        self.score += gained
        self.lines += cleared
        stats.sent += sent
        stats.max_combo = max(stats.max_combo, combo)
        stats.max_chain = max(stats.max_chain, self.chain)

        state, x, y = self.position
        keys = "-" if shortest is None else len(shortest)
        print(
            f"lock {self.pieces} {self.kind} {STATE_NAMES[state]} {x} {y}"
            f" keys {self.operations} {keys} drop {self.drop_points}"
            f" lines {cleared} sent {sent} +{gained} total {self.score}"
        )
        if shortest is not None and self.operations > len(shortest):
            stats.faults += 1
            print("finesse " + (" ".join(shortest) or "none"))
        if clear_type is not None:
            stats.clear_counts[name] += 1
            line = f"clear {name} {points}"
            if back_to_back:
                line += " b2b"
            if combo >= 1:
                line += f" combo {combo} {combo_points}"
            if perfect:
                line += f" perfect {perfect_points}"
            print(line)
        new_level = self.start_level + self.lines // 10
        if new_level > level:
            self.level = new_level
            print(f"level {self.level}")
        return sent

    def reduce_pending(self, amount):
        while amount > 0:
            used = min(amount, self.pending[0])
            self.pending[0] -= used
            amount -= used
            if self.pending[0] == 0:
                self.pending.pop(0)

    def cancel_garbage(self, sent):
        cancelled = min(sent, sum(self.pending))
        if cancelled >= 1:
            self.reduce_pending(cancelled)
            self.stats.cancelled += cancelled
            print(f"cancel {cancelled} pending {sum(self.pending)}")

    def receive_garbage(self):
        risen = 0
        while self.pending and risen < MAX_RISE:
            rows = min(self.pending[0], MAX_RISE - risen)
            hole = self.draw_random() % WIDTH + 1
            self.insert_garbage(rows, hole)
            self.stats.received += rows
            risen += rows
            self.reduce_pending(rows)
            print(f"rise {rows} hole {hole} pending {sum(self.pending)}")

    def insert_garbage(self, count, hole):
        if not self.well.insert_garbage(count, hole):
            self.game_over("top out")

    def ranked_candidates(self):
        candidates = placements(self.well, self.kind, self.position, ())
        if not self.hold_used:
            other = self.hold or self.queue[0]
            if self.well.fits(other, SPAWNS[other]):
                candidates += placements(self.well, other, SPAWNS[other], ("HOLD",))
        return sorted(candidates, key=lambda candidate: candidate.value, reverse=True)

    def print_well(self):
        piece = ghost = set()
        if not self.ended:
            piece = set(piece_cells(self.kind, self.position))
            ghost = set(piece_cells(self.kind, self.well.landing(self.kind, self.position)))
        for row in range(HEIGHT, 0, -1):
            marks = []
            for column in range(1, WIDTH + 1):
                if self.well.filled(column, row):
                    marks.append("#")
                elif (column, row) in piece:
                    marks.append("@")
                elif (column, row) in ghost:
                    marks.append("+")
                else:
                    marks.append(".")
            print(f"{row:2} {''.join(marks)}")

    def show_next(self):
        print(f"hold {self.hold or '-'} next {''.join(self.queue[:5])}")

    def preview(self, count):
        queue = list(self.queue)
        value = self.random_value
        while len(queue) < count:
            bag, value = shuffled_bag(value)
            queue.extend(bag)
        print(f"preview {''.join(queue[:count])}")

    def status(self):
        print(f"score {self.score} level {self.level} lines {self.lines} pieces {self.pieces}")
        if self.ended:
            piece = "-"
        else:
            state, x, y = self.position
            piece = f"{self.kind} {STATE_NAMES[state]} {x} {y}"
        print(f"piece {piece} streak {self.streak} chain {self.chain} pending {sum(self.pending)}")

    def analyze(self):
        heights, holes, bumpiness = self.well.metrics()
        print("heights " + " ".join(map(str, heights)))
        print(f"holes {holes} bumpiness {bumpiness} value {evaluation(self.well, 0)}")

    def set_row(self, row, pattern):
        for column, cell_row in piece_cells(self.kind, self.position):
            if cell_row == row and pattern[column - 1] == "#":
                print("ERROR overlap")
                return
        self.well.set_row(row, pattern)
        print("OK")

    def add_garbage(self, count, hole):
        self.insert_garbage(count, hole)
        for rise in range(count + 1):
            raised = offset(self.position, 0, rise)
            if self.well.fits(self.kind, raised):
                self.position = raised
                print("OK")
                return
        self.game_over("top out")

    def attack(self, count):
        self.pending.append(count)
        print(f"pending {sum(self.pending)}")

    def run_ticks(self, count):
        for _ in range(count):
            self.tick()

    def undo(self):
        if not self.history:
            print("ERROR nothing to undo")
            return
        state = self.history.pop()
        self.restore(state)
        self.start_state = state
        print(f"undo {self.pieces} {self.kind}")

    def save(self, name):
        self.saves[name] = self.snapshot(SAVE_EXCLUDED)
        print("OK")

    def load(self, name):
        if name not in self.saves:
            print("ERROR unknown save")
            return
        self.restore(self.saves[name])
        print(f"load {self.pieces} {self.kind}")

    def spins(self):
        if self.kind != "T":
            print("spins 0")
            return
        found = {}
        for position, _ in explore(self.well, "T", self.position):
            for rotation in ROTATIONS:
                moved = move(self.well, "T", position, rotation)
                if moved is None or not self.well.grounded("T", moved[0]):
                    continue
                target, test = moved
                spin = tspin_type(self.well, target, test)
                if spin == "full" or spin is not None and target not in found:
                    found[target] = spin
        for target in sorted(found, key=lambda position: (position.y, position.x, position.state)):
            trial = self.well.copy()
            cleared = trial.place("T", target)
            name = CLEAR_TYPES[found[target], cleared][0]
            print(f"spin {STATE_NAMES[target.state]} {target.x} {target.y} {name}")
        print(f"spins {len(found)}")

    def hint(self, count):
        for rank, candidate in enumerate(self.ranked_candidates()[:count], 1):
            operations = " ".join(candidate.operations)
            print(f"hint {rank} {candidate.kind} {operations} value {candidate.value}")

    def auto(self, count):
        for _ in range(count):
            best = self.ranked_candidates()[0]
            print(f"auto {best.kind} {' '.join(best.operations)}")
            self.perform(best.operations)


def number_in(low, high):
    def parse(word):
        if NUMBER.fullmatch(word) and low <= int(word) <= high:
            return int(word)
        return None
    return parse


def parse_pattern(word):
    return word if PATTERN.fullmatch(word) and "." in word else None


def parse_name(word):
    return word if NAME.fullmatch(word) else None


COMMANDS = {
    "NEW": Command((number_in(1, MODULUS - 1), number_in(1, 15)), True, None),
    "PRINT": Command((), True, Game.print_well),
    "NEXT": Command((), True, Game.show_next),
    "PREVIEW": Command((number_in(1, 14),), True, Game.preview),
    "STATUS": Command((), True, Game.status),
    "ANALYZE": Command((), True, Game.analyze),
    "ROW": Command((number_in(1, HEIGHT), parse_pattern), False, Game.set_row),
    "GARBAGE": Command((number_in(1, 10), number_in(1, WIDTH)), False, Game.add_garbage),
    "ATTACK": Command((number_in(1, 20),), False, Game.attack),
    "TICK": Command((number_in(1, 1000),), False, Game.run_ticks),
    "UNDO": Command((), False, Game.undo),
    "SAVE": Command((parse_name,), False, Game.save),
    "LOAD": Command((parse_name,), True, Game.load),
    "SPINS": Command((), False, Game.spins),
    "HINT": Command((number_in(1, 10),), False, Game.hint),
    "AUTO": Command((number_in(1, 50),), False, Game.auto),
}


class Session:
    def __init__(self):
        self.game = None
        self.games = 0

    def stop(self):
        if self.game is not None and not self.game.ended:
            print("game stopped")
            self.game.print_summary()

    def new_game(self, seed, level):
        self.stop()
        self.games += 1
        print(f"game {self.games} seed {seed} level {level}")
        self.game = Game(self.games, seed, level)

    def run_command(self, name, arguments):
        command = COMMANDS[name]
        values = [parse(word) for parse, word in zip(command.parsers, arguments)]
        if len(arguments) != len(command.parsers) or None in values:
            print("ERROR bad arguments")
        elif name == "NEW":
            self.new_game(*values)
        elif self.game is None:
            print("ERROR no game")
        elif self.game.ended and not command.after_end:
            print("ERROR game over")
        else:
            command.handler(self.game, *values)

    def run_operations(self, words):
        unknown = next((word for word in words if word not in OPERATIONS), None)
        if unknown is not None:
            print(f"ERROR unknown {unknown}")
        elif self.game is None:
            print("ERROR no game")
        elif self.game.ended:
            print("ERROR game over")
        else:
            self.game.perform(words)

    def execute(self, line):
        words = line.split(" ")
        try:
            if words[0] in COMMANDS:
                self.run_command(words[0], words[1:])
            else:
                self.run_operations(words)
        except GameOver:
            pass


def main():
    session = Session()
    count = int(sys.stdin.readline())
    for _ in range(count):
        session.execute(sys.stdin.readline().rstrip("\n"))
    session.stop()


if __name__ == "__main__":
    main()
