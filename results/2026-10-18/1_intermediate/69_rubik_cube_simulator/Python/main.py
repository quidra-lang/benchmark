import math
import re
import string
import sys
from itertools import combinations, groupby


FACES = "URFDLB"
COLORS = "WRGYOB"
FACE_COLORS = dict(zip(FACES, COLORS))
SOLVED = [color for color in COLORS for _ in range(9)]
# Outward normal, column direction and row direction of each face, in face order.
FACE_FRAMES = (
    ((0, 1, 0), (1, 0, 0), (0, 0, 1)),
    ((1, 0, 0), (0, 0, -1), (0, -1, 0)),
    ((0, 0, 1), (1, 0, 0), (0, -1, 0)),
    ((0, -1, 0), (1, 0, 0), (0, 0, -1)),
    ((-1, 0, 0), (0, 0, 1), (0, -1, 0)),
    ((0, 0, -1), (-1, 0, 0), (0, -1, 0)),
)
# Axis (0 = x, 1 = y, 2 = z), clockwise quarter turns seen from the positive side, turned layers.
TURNS = {
    "R": (0, 1, (1,)),
    "L": (0, 3, (-1,)),
    "M": (0, 3, (0,)),
    "r": (0, 1, (0, 1)),
    "l": (0, 3, (-1, 0)),
    "x": (0, 1, (-1, 0, 1)),
    "U": (1, 1, (1,)),
    "D": (1, 3, (-1,)),
    "E": (1, 3, (0,)),
    "u": (1, 1, (0, 1)),
    "d": (1, 3, (-1, 0)),
    "y": (1, 1, (-1, 0, 1)),
    "F": (2, 1, (1,)),
    "B": (2, 3, (-1,)),
    "S": (2, 1, (0,)),
    "f": (2, 1, (0, 1)),
    "b": (2, 3, (-1, 0)),
    "z": (2, 1, (-1, 0, 1)),
}
AXIS = {letter: turn[0] for letter, turn in TURNS.items()}
SLICE_LETTERS = "MES"
ROTATION_LETTERS = "xyz"
OPPOSITES = {
    letter: other
    for pair in ("RL", "UD", "FB", "rl", "ud", "fb")
    for letter, other in (pair, pair[::-1])
}
MIRROR_AXES = {"LR": 0, "UD": 1, "FB": 2}
SUFFIXES = {1: "", 2: "2", 3: "'"}
AMOUNTS = {suffix: amount for amount, suffix in SUFFIXES.items()}
REPLACEMENT_TEXTS = {
    "M": "R L' x'",
    "E": "U D' y'",
    "S": "F' B z",
    "r": "L x",
    "l": "R x'",
    "u": "D y",
    "d": "U y'",
    "f": "B z",
    "b": "F z'",
}
CORNER_LAYOUT = {
    "URF": "U9 R1 F3",
    "UFL": "U7 F1 L3",
    "ULB": "U1 L1 B3",
    "UBR": "U3 B1 R3",
    "DFR": "D3 F9 R7",
    "DLF": "D1 L9 F7",
    "DBL": "D7 B9 L7",
    "DRB": "D9 R9 B7",
}
EDGE_LAYOUT = {
    "UR": "U6 R2",
    "UF": "U8 F2",
    "UL": "U4 L2",
    "UB": "U2 B2",
    "DR": "D6 R8",
    "DF": "D2 F8",
    "DL": "D4 L8",
    "DB": "D8 B8",
    "FR": "F6 R4",
    "FL": "F4 L6",
    "BL": "B6 L4",
    "BR": "B4 R6",
}
CENTER_LAYOUT = {face: f"{face}5" for face in FACES}
MARKS = ("", "+", "-")
CROSS_EDGES = ("DR", "DF", "DL", "DB")
F2L_SLOTS = (("DFR", "FR"), ("DLF", "FL"), ("DBL", "BL"), ("DRB", "BR"))
SEARCH_MOVES = [(face, amount) for face in FACES for amount in (1, 2, 3)]
BLOCKED_AFTER = {"D": "U", "L": "R", "B": "F"}
MULTIPLIER = 48271
MODULUS = 2147483647
MAX_SEED = 2147483646
MAX_SCRAMBLE = 50
MAX_DEPTH = 4
MAX_MOVES = 500
DIGITS = set(string.digits)
NONZERO_DIGITS = DIGITS - {"0"}
LOWERCASE = set(string.ascii_lowercase)

NUMBER = re.compile(r"0|[1-9][0-9]{0,9}")
NAME = re.compile(r"[a-z]{1,8}")
WORD = re.compile(r".+")
NO_ARGUMENT_COMMANDS = {
    "RESET", "SHOW", "STATE", "ISSOLVED", "HISTORY", "SOLUTION", "ANALYZE", "STAGE", "MACROS",
}
WORD_COMMANDS = {
    "CHECK": (WORD,),
    "LOAD": (WORD,),
    "UNDO": (NUMBER,),
    "REDO": (NUMBER,),
    "SEARCH": (NUMBER,),
    "WHERE": (WORD,),
    "SAVE": (NAME,),
    "RESTORE": (NAME,),
    "SCRAMBLE": (NUMBER, NUMBER),
}
SEQUENCE_COMMANDS = {
    "APPLY", "INVERT", "SIMPLIFY", "METRICS", "ORDER", "CYCLES", "UNROTATE", "UNTIL",
}
HEAD_WORD_COMMANDS = {
    "DEFINE": NAME,
    "MIRROR": re.compile(r"LR|UD|FB"),
    "ROTATE": re.compile(r"[xyz][2']?"),
}


class CommandError(Exception):
    pass


def require(condition, message="bad arguments"):
    if not condition:
        raise CommandError(message)


def parse_moves(text):
    return [(word[0], AMOUNTS[word[1:]]) for word in text.split()]


def move_text(move):
    letter, amount = move
    return letter + SUFFIXES[amount]


def moves_text(moves):
    return " ".join(move_text(move) for move in moves)


def sequence_text(moves):
    return " ".join([str(len(moves))] + [move_text(move) for move in moves])


def inverse(moves):
    return [(letter, 4 - amount) for letter, amount in reversed(moves)]


def sticker_number(label):
    return 9 * FACES.index(label[0]) + int(label[1]) - 1


def sticker_places():
    places = []
    for normal, column_step, row_step in FACE_FRAMES:
        for row in (-1, 0, 1):
            for column in (-1, 0, 1):
                cubie = tuple(
                    n + column * c + row * r for n, c, r in zip(normal, column_step, row_step)
                )
                places.append((cubie, normal))
    return places


def quarter_turn(vector, axis):
    turned = list(vector)
    first, second = (axis + 1) % 3, (axis + 2) % 3
    turned[first], turned[second] = vector[second], -vector[first]
    return tuple(turned)


def permute(state, table):
    return [state[source] for source in table]


def build_move_tables():
    places = sticker_places()
    numbers = {place: number for number, place in enumerate(places)}
    tables = {}
    for letter, (axis, turns, layers) in TURNS.items():
        quarter = list(range(54))
        for number, (cubie, normal) in enumerate(places):
            if cubie[axis] in layers:
                for _ in range(turns):
                    cubie = quarter_turn(cubie, axis)
                    normal = quarter_turn(normal, axis)
                quarter[numbers[cubie, normal]] = number
        table = list(range(54))
        for amount in (1, 2, 3):
            table = permute(table, quarter)
            tables[letter, amount] = table
    return tables


def apply_moves(state, moves):
    for move in moves:
        state = permute(state, MOVE_TABLES[move])
    return state


def effect(moves):
    return tuple(apply_moves(list(range(54)), moves))


MOVE_TABLES = build_move_tables()
MOVES_BY_EFFECT = {tuple(table): move for move, table in MOVE_TABLES.items()}
ROTATION_TABLE = [
    parse_moves(f"{first} {second}")
    for first in ("", "x", "x2", "x'", "z", "z'")
    for second in ("", "y", "y2", "y'")
]
ROTATIONS_BY_EFFECT = {effect(rotation): rotation for rotation in ROTATION_TABLE}
REPLACEMENTS = {letter: parse_moves(text) for letter, text in REPLACEMENT_TEXTS.items()}


class PieceKind:
    def __init__(self, layout):
        self.names = list(layout)
        self.stickers = [
            [sticker_number(label) for label in labels.split()] for labels in layout.values()
        ]
        self.colors = [[FACE_COLORS[face] for face in name] for name in self.names]

    def identify(self, colors):
        for piece, piece_colors in enumerate(self.colors):
            for orientation in range(len(colors)):
                if colors[orientation:] + colors[:orientation] == piece_colors:
                    return piece, orientation
        return None

    def contents(self, state):
        return [self.identify([state[number] for number in group]) for group in self.stickers]

    def placed(self, state):
        return {
            self.names[position]
            for position, content in enumerate(self.contents(state))
            if content == (position, 0)
        }

    def locate(self, state, name):
        piece = self.names.index(name)
        contents = self.contents(state)
        position = next(index for index, content in enumerate(contents) if content[0] == piece)
        return self.names[position], contents[position][1]

    def cycle_notation(self, state):
        size = len(self.names)
        location = [0] * size
        twist = [0] * size
        for position, (piece, orientation) in enumerate(self.contents(state)):
            location[piece] = position
            twist[piece] = orientation
        visited = set()
        cycles = []
        for start in range(size):
            if start in visited:
                continue
            cycle = [start]
            position = location[start]
            while position != start:
                cycle.append(position)
                position = location[position]
            visited.update(cycle)
            mark = MARKS[sum(twist[piece] for piece in cycle) % len(self.stickers[0])]
            if len(cycle) >= 2 or mark:
                cycles.append("(" + " ".join(self.names[piece] for piece in cycle) + ")" + mark)
        return " ".join(cycles) or "none"


CORNERS = PieceKind(CORNER_LAYOUT)
EDGES = PieceKind(EDGE_LAYOUT)
CENTERS = PieceKind(CENTER_LAYOUT)


def is_solved(state):
    return all(len(set(state[start:start + 9])) == 1 for start in range(0, 54, 9))


def misplaced_stickers(state):
    return sum(color != state[number // 9 * 9 + 4] for number, color in enumerate(state))


def face_row(state, face, row):
    start = 9 * FACES.index(face) + 3 * row
    return state[start:start + 3]


def normalizing_rotation(state):
    for rotation in ROTATION_TABLE:
        rotated = apply_moves(state, rotation)
        if all(rotated[9 * face + 4] == color for face, color in enumerate(COLORS)):
            return rotation
    return None


def normalized(state):
    return apply_moves(state, normalizing_rotation(state))


def permutation_parity(contents):
    pieces = [piece for piece, _ in contents]
    return sum(first > second for first, second in combinations(pieces, 2)) % 2


def invalid_reason(text):
    if len(text) != 54:
        return f"length {len(text)}"
    for position, color in enumerate(text, 1):
        if color not in COLORS:
            return f"char {position}"
    for color in COLORS:
        if text.count(color) != 9:
            return f"count {color} {text.count(color)}"
    state = list(text)
    rotation = normalizing_rotation(state)
    if rotation is None:
        return "centers"
    kinds = ((CORNERS, CORNERS.contents(state), "corner"), (EDGES, EDGES.contents(state), "edge"))
    for kind, contents, label in kinds:
        if None in contents:
            return f"{label} {kind.names[contents.index(None)]}"
    for kind, contents, _ in kinds:
        present = {piece for piece, _ in contents}
        for piece, name in enumerate(kind.names):
            if piece not in present:
                return f"missing {name}"
    normal = apply_moves(state, rotation)
    corners = CORNERS.contents(normal)
    edges = EDGES.contents(normal)
    if sum(orientation for _, orientation in corners) % 3:
        return "twist"
    if sum(orientation for _, orientation in edges) % 2:
        return "flip"
    if permutation_parity(corners) != permutation_parity(edges):
        return "parity"
    return None


def simplify(moves):
    while True:
        result = []
        for _, run in groupby(moves, key=lambda move: AXIS[move[0]]):
            totals = {}
            for letter, amount in run:
                totals[letter] = (totals.get(letter, 0) + amount) % 4
            result.extend((letter, total) for letter, total in totals.items() if total)
        if result == moves:
            return result
        moves = result


def mirror(moves, plane):
    mirror_axis = MIRROR_AXES[plane]
    result = []
    for letter, amount in moves:
        if AXIS[letter] != mirror_axis:
            result.append((letter, 4 - amount))
        elif letter in OPPOSITES:
            result.append((OPPOSITES[letter], 4 - amount))
        else:
            result.append((letter, amount))
    return result


def rotate(moves, rotation):
    undo = inverse([rotation])
    return [MOVES_BY_EFFECT[effect([rotation, move] + undo)] for move in moves]


def unrotate(moves):
    expanded = []
    for letter, amount in moves:
        if letter in REPLACEMENTS:
            expanded.extend(
                (part, part_amount * amount % 4) for part, part_amount in REPLACEMENTS[letter]
            )
        else:
            expanded.append((letter, amount))
    held = []
    result = []
    for move in expanded:
        if move[0] in ROTATION_LETTERS:
            held = ROTATIONS_BY_EFFECT[effect(held + [move])]
        else:
            result.append(MOVES_BY_EFFECT[effect(held + [move] + inverse(held))])
    return result + held


def metrics(moves):
    htm = qtm = stm = 0
    for letter, amount in moves:
        if letter in ROTATION_LETTERS:
            continue
        weight = 2 if letter in SLICE_LETTERS else 1
        htm += weight
        qtm += weight * (2 if amount == 2 else 1)
        stm += 1
    return htm, qtm, stm, len(moves)


def order(table):
    result = 1
    seen = set()
    for start in range(54):
        length = 0
        sticker = start
        while sticker not in seen:
            seen.add(sticker)
            sticker = table[sticker]
            length += 1
        if length:
            result = math.lcm(result, length)
    return result


def minstd(seed):
    value = seed
    while True:
        value = MULTIPLIER * value % MODULUS
        yield value


def scramble(count, seed):
    numbers = minstd(seed)
    moves = []
    for _ in range(count):
        faces = list(FACES)
        if moves:
            last = moves[-1][0]
            faces.remove(last)
            if len(moves) >= 2 and AXIS[last] == AXIS[moves[-2][0]]:
                faces = [face for face in faces if AXIS[face] != AXIS[last]]
        face = faces[next(numbers) % len(faces)]
        amount = (1, 3, 2)[next(numbers) % 3]
        moves.append((face, amount))
    return moves


def search(state, limit):
    for depth in range(limit + 1):
        found = search_depth(state, depth, None)
        if found is not None:
            return found
    return None


def search_depth(state, depth, previous):
    if depth == 0:
        return [] if is_solved(state) else None
    for move in SEARCH_MOVES:
        face = move[0]
        if face == previous or BLOCKED_AFTER.get(previous) == face:
            continue
        found = search_depth(permute(state, MOVE_TABLES[move]), depth - 1, face)
        if found is not None:
            return [move] + found
    return None


class SequenceParser:
    def __init__(self, line, start, macros):
        self.line = line
        self.position = start
        self.macros = macros

    def current(self):
        if self.position < len(self.line):
            return self.line[self.position]
        return None

    def read(self):
        character = self.current()
        self.position += 1
        return character

    def accept(self, character):
        if self.current() != character:
            return False
        self.position += 1
        return True

    def fail(self):
        raise CommandError(f"syntax at {self.position + 1}")

    def expect(self, character):
        if not self.accept(character):
            self.fail()

    def skip_spaces(self):
        while self.current() == " ":
            self.position += 1

    def parse(self):
        moves = self.sequence()
        self.skip_spaces()
        if self.current() is not None:
            self.fail()
        require(len(moves) <= MAX_MOVES, "too long")
        return moves

    def sequence(self):
        moves = []
        while True:
            self.skip_spaces()
            character = self.current()
            if character in TURNS:
                moves.append(self.move())
            elif character == "(":
                moves.extend(self.group())
            elif character == "[":
                moves.extend(self.bracket())
            elif character == "{":
                moves.extend(self.macro())
            else:
                return moves

    def move(self):
        letter = self.read()
        if self.accept("2"):
            return letter, 2
        if self.accept("'"):
            return letter, 3
        return letter, 1

    def group(self):
        self.read()
        moves = self.sequence()
        self.skip_spaces()
        self.expect(")")
        return self.power(moves)

    def bracket(self):
        self.read()
        first = self.sequence()
        self.skip_spaces()
        separator = self.current()
        if separator not in (",", ":"):
            self.fail()
        self.read()
        second = self.sequence()
        self.skip_spaces()
        self.expect("]")
        moves = first + second + inverse(first)
        if separator == ",":
            moves += inverse(second)
        return self.power(moves)

    def macro(self):
        self.read()
        start = self.position
        while self.current() in LOWERCASE:
            self.position += 1
        name = self.line[start:self.position]
        if not name or self.current() != "}":
            self.fail()
        if name not in self.macros:
            raise CommandError(f"undefined {name}")
        self.read()
        return self.power(self.macros[name])

    def power(self, moves):
        count = 1
        if self.current() in NONZERO_DIGITS:
            count = int(self.read())
            if self.current() in DIGITS:
                count = 10 * count + int(self.read())
        moves = moves * count
        return inverse(moves) if self.accept("'") else moves


class Simulator:
    def __init__(self):
        self.state = list(SOLVED)
        self.history = []
        self.redo = []
        self.macros = {}
        self.saves = {}

    def record(self, moves):
        self.state = apply_moves(self.state, moves)
        self.history.extend(moves)
        self.redo = []

    def do_reset(self):
        self.state = list(SOLVED)
        self.history = []
        self.redo = []
        print("reset")

    def do_show(self):
        for row in range(3):
            print(" " * 6 + " ".join(face_row(self.state, "U", row)))
        for row in range(3):
            print(" ".join(" ".join(face_row(self.state, face, row)) for face in "LFRB"))
        for row in range(3):
            print(" " * 6 + " ".join(face_row(self.state, "D", row)))

    def do_state(self):
        print("state", "".join(self.state))

    def do_issolved(self):
        if is_solved(self.state):
            print("solved")
        else:
            print("unsolved", misplaced_stickers(self.state))

    def do_history(self):
        print("history", sequence_text(self.history))

    def do_solution(self):
        print("solution", sequence_text(simplify(inverse(self.history))))

    def do_analyze(self):
        rotation = normalizing_rotation(self.state)
        normal = apply_moves(self.state, rotation)
        print("rotation", moves_text(rotation) or "none")
        print("corners", CORNERS.cycle_notation(normal))
        print("edges", EDGES.cycle_notation(normal))

    def do_stage(self):
        normal = normalized(self.state)
        corners = CORNERS.placed(normal)
        edges = EDGES.placed(normal)
        cross = sum(edge in edges for edge in CROSS_EDGES)
        slots = sum(corner in corners and edge in edges for corner, edge in F2L_SLOTS)
        top = normal[:9].count("W")
        if is_solved(normal):
            stage = "solved"
        elif cross == 4 and slots == 4 and top == 9:
            stage = "oll"
        elif cross == 4 and slots == 4:
            stage = "f2l"
        elif cross == 4:
            stage = "cross"
        else:
            stage = "none"
        print("stage", stage, "cross", cross, "slots", slots, "top", top)

    def do_macros(self):
        print("macros", len(self.macros))
        for name in sorted(self.macros):
            print("macro", name, sequence_text(self.macros[name]))

    def do_check(self, facelets):
        reason = invalid_reason(facelets)
        print("valid" if reason is None else f"invalid {reason}")

    def do_load(self, facelets):
        reason = invalid_reason(facelets)
        if reason is not None:
            raise CommandError(f"invalid {reason}")
        self.state = list(facelets)
        self.history = []
        self.redo = []
        print("loaded")

    def do_undo(self, count):
        require(count >= 1, "bad value")
        require(self.history, "nothing to undo")
        steps = min(count, len(self.history))
        for _ in range(steps):
            move = self.history.pop()
            self.state = apply_moves(self.state, inverse([move]))
            self.redo.append(move)
        print("undone", steps)

    def do_redo(self, count):
        require(count >= 1, "bad value")
        require(self.redo, "nothing to redo")
        steps = min(count, len(self.redo))
        for _ in range(steps):
            move = self.redo.pop()
            self.state = apply_moves(self.state, [move])
            self.history.append(move)
        print("redone", steps)

    def do_search(self, depth):
        require(depth <= MAX_DEPTH, "bad value")
        found = search(self.state, depth)
        print("not found" if found is None else f"found {sequence_text(found)}")

    def do_where(self, piece):
        if piece in CORNERS.names:
            kind, label = CORNERS, "twist"
        elif piece in EDGES.names:
            kind, label = EDGES, "flip"
        else:
            raise CommandError(f"unknown piece {piece}")
        position, orientation = kind.locate(normalized(self.state), piece)
        print(piece, "at", position, label, orientation)

    def do_save(self, name):
        self.saves[name] = (list(self.state), list(self.history))
        print("saved", name)

    def do_restore(self, name):
        require(name in self.saves, f"no save {name}")
        state, history = self.saves[name]
        self.state = list(state)
        self.history = list(history)
        self.redo = []
        print("restored", name)

    def do_scramble(self, count, seed):
        require(1 <= count <= MAX_SCRAMBLE and 1 <= seed <= MAX_SEED, "bad value")
        moves = scramble(count, seed)
        self.record(moves)
        print("scramble", moves_text(moves))

    def do_apply(self, moves):
        self.record(moves)
        print("applied", len(moves))

    def do_invert(self, moves):
        print("inverse", sequence_text(inverse(moves)))

    def do_simplify(self, moves):
        print("simplified", sequence_text(simplify(moves)))

    def do_metrics(self, moves):
        htm, qtm, stm, etm = metrics(moves)
        print("metrics htm", htm, "qtm", qtm, "stm", stm, "etm", etm)

    def do_order(self, moves):
        print("order", order(effect(moves)))

    def do_cycles(self, moves):
        state = apply_moves(SOLVED, moves)
        print("corners", CORNERS.cycle_notation(state))
        print("edges", EDGES.cycle_notation(state))
        print("centers", CENTERS.cycle_notation(state))

    def do_unrotate(self, moves):
        print("unrotated", sequence_text(unrotate(moves)))

    def do_until(self, moves):
        table = effect(moves)
        state = self.state
        for count in range(1, order(table) + 1):
            state = permute(state, table)
            if is_solved(state):
                print("until", count)
                return
        print("until never")

    def do_define(self, name, moves):
        self.macros[name] = moves
        print("defined", name, len(moves))

    def do_mirror(self, plane, moves):
        print("mirror", sequence_text(mirror(moves, plane)))

    def do_rotate(self, rotation, moves):
        print("rotated", sequence_text(rotate(moves, parse_moves(rotation)[0])))

    def parse(self, line, start):
        return SequenceParser(line, start, self.macros).parse()

    def run(self, line):
        name, separator, argument = line.partition(" ")
        if name in NO_ARGUMENT_COMMANDS:
            require(not separator)
            arguments = []
        elif name in WORD_COMMANDS:
            words = argument.split(" ") if separator else []
            patterns = WORD_COMMANDS[name]
            require(len(words) == len(patterns))
            require(all(pattern.fullmatch(word) for pattern, word in zip(patterns, words)))
            arguments = [
                int(word) if pattern is NUMBER else word for pattern, word in zip(patterns, words)
            ]
        elif name in SEQUENCE_COMMANDS:
            arguments = [self.parse(line, len(name) + 1)]
        elif name in HEAD_WORD_COMMANDS:
            require(separator)
            head = argument.partition(" ")[0]
            require(HEAD_WORD_COMMANDS[name].fullmatch(head))
            arguments = [head, self.parse(line, len(name) + len(head) + 2)]
        else:
            raise CommandError(f"unknown command {name}")
        getattr(self, f"do_{name.lower()}")(*arguments)

    def execute(self, line):
        try:
            self.run(line)
        except CommandError as error:
            print(f"error: {error}")


def main():
    simulator = Simulator()
    count = int(sys.stdin.readline())
    for _ in range(count):
        simulator.execute(sys.stdin.readline().rstrip("\n"))


if __name__ == "__main__":
    main()
