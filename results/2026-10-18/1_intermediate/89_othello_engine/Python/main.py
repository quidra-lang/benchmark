import re
import sys
from dataclasses import dataclass, replace
from functools import lru_cache

COLS = "abcdefgh"
DIRS = ((-1, -1), (-1, 0), (-1, 1), (0, -1), (0, 1),
        (1, -1), (1, 0), (1, 1))
AXES = (((0, -1), (0, 1)), ((-1, 0), (1, 0)),
        ((-1, -1), (1, 1)), ((-1, 1), (1, -1)))
WEIGHTS = (
    100, -20, 10, 5, 5, 10, -20, 100,
    -20, -50, -2, -2, -2, -2, -50, -20,
    10, -2, -1, -1, -1, -1, -2, 10,
    5, -2, -1, -1, -1, -1, -2, 5,
    5, -2, -1, -1, -1, -1, -2, 5,
    10, -2, -1, -1, -1, -1, -2, 10,
    -20, -50, -2, -2, -2, -2, -50, -20,
    100, -20, 10, 5, 5, 10, -20, 100,
)
TRANSFORMS = ("rot90", "rot180", "rot270", "mirror", "flip", "diag", "anti")
ZERO_ARGS = ("NEW", "DUMP", "SHOW", "SCORE", "LEGAL", "HISTORY",
             "SHEET", "STATS", "EVAL", "STABLE", "SOLVE")
SQUARE_ARGS = ("FLIPS", "MOVE")
RECORD_ARGS = ("PLAY", "RECORD")
NUMBER_ARGS = ("UNDO", "REDO", "HINT", "PV", "AI", "ANALYZE",
               "RANDOM", "PERFT", "DIVIDE")
OTHER_COMMANDS = ("LOAD", "TRANSFORM", "AUTOPLAY", "MC")
COMMANDS = set(ZERO_ARGS + SQUARE_ARGS + RECORD_ARGS + NUMBER_ARGS + OTHER_COMMANDS)
ACTIVE_ONLY = ("FLIPS", "MOVE", "PLAY", "HINT", "PV", "AI", "SOLVE",
               "AUTOPLAY", "RANDOM", "MC", "DIVIDE")


def other(color):
    return "W" if color == "B" else "B"


def square_name(square):
    return COLS[square % 8] + str(square // 8 + 1)


def square_index(text):
    return (int(text[1]) - 1) * 8 + COLS.index(text[0])


def on_board(row, column):
    return 0 <= row < 8 and 0 <= column < 8


def initial_board():
    board = ["."] * 64
    for square, color in (("d4", "W"), ("e5", "W"), ("d5", "B"), ("e4", "B")):
        board[square_index(square)] = color
    return "".join(board)


@lru_cache(maxsize=200000)
def flips(board, color, square):
    if board[square] != ".":
        return ()
    row, column = divmod(square, 8)
    enemy = other(color)
    result = []
    for dr, dc in DIRS:
        r, c = row + dr, column + dc
        line = []
        while on_board(r, c) and board[8 * r + c] == enemy:
            line.append(8 * r + c)
            r += dr
            c += dc
        if line and on_board(r, c) and board[8 * r + c] == color:
            result.extend(line)
    return tuple(sorted(result))


@lru_cache(maxsize=200000)
def legal(board, color):
    return tuple(i for i, disc in enumerate(board)
                 if disc == "." and flips(board, color, i))


def place(board, color, square):
    chars = list(board)
    chars[square] = color
    for i in flips(board, color, square):
        chars[i] = color
    return "".join(chars)


def terminal(board):
    return not legal(board, "B") and not legal(board, "W")


def game_over(board):
    black, white = board.count("B"), board.count("W")
    result = "winner B" if black > white else "winner W" if white > black else "draw"
    return f"game over B {black} W {white} {result}"


def evaluate(board, side):
    opponent = other(side)
    weight = sum(w if board[i] == side else -w if board[i] == opponent else 0
                 for i, w in enumerate(WEIGHTS))
    own = len(legal(board, side))
    enemy = len(legal(board, opponent))
    return weight + 10 * (own - enemy), weight, own, enemy


@lru_cache(maxsize=500000)
def search(board, side, depth):
    moves = legal(board, side)
    opponent = other(side)
    if not moves and not legal(board, opponent):
        return 1000 * (board.count(side) - board.count(opponent))
    if depth == 0:
        return evaluate(board, side)[0]
    if not moves:
        return -search(board, opponent, depth - 1)
    return max(-search(place(board, side, move), opponent, depth - 1)
               for move in moves)


def scored_moves(board, side, depth):
    opponent = other(side)
    return sorted(
        ((-search(place(board, side, move), opponent, depth - 1), move)
         for move in legal(board, side)),
        key=lambda item: (-item[0], item[1]),
    )


@lru_cache(maxsize=500000)
def exact(board, side):
    moves, opponent = legal(board, side), other(side)
    if not moves and not legal(board, opponent):
        return board.count(side) - board.count(opponent)
    if not moves:
        return -exact(board, opponent)
    return max(-exact(place(board, side, move), opponent) for move in moves)


def exact_moves(board, side):
    opponent = other(side)
    return sorted(
        ((-exact(place(board, side, move), opponent), move)
         for move in legal(board, side)),
        key=lambda item: (-item[0], item[1]),
    )


def variation(board, side, depth=None):
    steps = []
    while not terminal(board) and (depth is None or depth > 0):
        choices = legal(board, side)
        if choices:
            move = (exact_moves(board, side) if depth is None
                    else scored_moves(board, side, depth))[0][1]
            steps.append(square_name(move))
            board = place(board, side, move)
        else:
            steps.append("pass")
        side = other(side)
        if depth is not None:
            depth -= 1
    return steps, board


@lru_cache(maxsize=200000)
def perft(board, side, depth):
    if depth == 0:
        return 1
    moves, opponent = legal(board, side), other(side)
    if not moves:
        return 1 if not legal(board, opponent) else perft(board, opponent, depth - 1)
    return sum(perft(place(board, side, move), opponent, depth - 1)
               for move in moves)


def stable_counts(board):
    stable = set()
    while True:
        new = set()
        for square, disc in enumerate(board):
            if disc == "." or square in stable:
                continue
            row, column = divmod(square, 8)
            for axis in AXES:
                full_line = True
                anchored = False
                for dr, dc in axis:
                    r, c = row + dr, column + dc
                    if not on_board(r, c):
                        anchored = True
                    elif 8 * r + c in stable and board[8 * r + c] == disc:
                        anchored = True
                    while on_board(r, c):
                        if board[8 * r + c] == ".":
                            full_line = False
                        r += dr
                        c += dc
                if not full_line and not anchored:
                    break
            else:
                new.add(square)
        if not new:
            break
        stable.update(new)
    return (sum(board[i] == "B" for i in stable),
            sum(board[i] == "W" for i in stable))


def transform_square(square, name):
    row, col = divmod(square, 8)
    if name == "rot90":
        row, col = col, 7 - row
    elif name == "rot180":
        row, col = 7 - row, 7 - col
    elif name == "rot270":
        row, col = 7 - col, row
    elif name == "mirror":
        col = 7 - col
    elif name == "flip":
        row = 7 - row
    elif name == "diag":
        row, col = col, row
    else:
        row, col = 7 - col, 7 - row
    return row * 8 + col


def transform_board(board, name):
    result = ["."] * 64
    for square, disc in enumerate(board):
        result[transform_square(square, name)] = disc
    return "".join(result)


@dataclass(frozen=True)
class Position:
    board: str
    side: str
    over: bool


@dataclass(frozen=True)
class Move:
    side: str
    square: int
    count: int
    passed: bool
    before: Position
    after: Position


def transform_move(row, name):
    def transformed(position):
        return replace(position, board=transform_board(position.board, name))
    return replace(row, square=transform_square(row.square, name),
                   before=transformed(row.before), after=transformed(row.after))


class Random:
    def __init__(self, seed):
        self.value = seed

    def draw(self):
        self.value = 48271 * self.value % 2147483647
        return self.value


def random_game(board, side, random):
    while True:
        moves = legal(board, side)
        if moves:
            square = moves[random.draw() % len(moves)]
            board = place(board, side, square)
        elif not legal(board, other(side)):
            return board
        side = other(side)


def average(total, count):
    value = total * 100 // count
    return f"{value // 100}.{value % 100:02d}"


class Othello:
    def __init__(self):
        self.board = initial_board()
        self.side = "B"
        self.over = False
        self.history = []
        self.redo = []
        self.output = []

    def reset(self):
        self.board = initial_board()
        self.side = "B"
        self.over = False
        self.history = []
        self.redo = []

    def emit(self, *items):
        self.output.append(" ".join(map(str, items)))

    def snapshot(self):
        return Position(self.board, self.side, self.over)

    def restore(self, position):
        self.board, self.side, self.over = position.board, position.side, position.over

    def status(self):
        return game_over(self.board) if self.over else self.side + " to move"

    def adjust(self, quiet=False):
        if legal(self.board, self.side):
            return False
        if legal(self.board, other(self.side)):
            if not quiet:
                self.emit(self.side, "passes")
            self.side = other(self.side)
            return True
        self.over = True
        if not quiet:
            self.emit(game_over(self.board))
        return False

    def move(self, square, quiet=False, value=None):
        before = self.snapshot()
        side = self.side
        count = len(flips(self.board, side, square))
        self.board = place(self.board, side, square)
        if not quiet:
            if value is None:
                self.emit(side, square_name(square), "flips", count)
            else:
                self.emit(side, square_name(square), "flips", count, "value", value)
        self.side = other(side)
        passed = self.adjust(quiet)
        self.history.append(Move(side, square, count, passed, before, self.snapshot()))
        self.redo.clear()
        return passed

    def reason(self, square):
        if self.over:
            return "game over"
        if self.board[square] != ".":
            return "occupied"
        if not flips(self.board, self.side, square):
            return "no flips"
        return None

    def read_record(self, text):
        engine = Othello()
        positions = [square_index(text[i:i + 2]) for i in range(0, len(text), 2)]
        passes = 0
        for number, square in enumerate(positions, 1):
            reason = engine.reason(square)
            if reason:
                self.emit("ILLEGAL", "move", number, square_name(square), reason)
                return
            passes += engine.move(square, quiet=True)
        self.board, self.side, self.over = engine.board, engine.side, engine.over
        self.history, self.redo = engine.history, []
        first = square_name(positions[0])
        operation = {"f5": None, "e6": "diag", "d3": "anti", "c4": "rot180"}[first]
        normalized = "".join(
            square_name(transform_square(square, operation)) if operation
            else square_name(square) for square in positions
        )
        self.emit("record", len(positions), "moves", passes, "passes")
        self.emit("normal", normalized)
        self.emit(self.status())

    def print_board(self):
        self.emit("  a b c d e f g h")
        choices = set(legal(self.board, self.side)) if not self.over else set()
        for row in range(8):
            text = [("*" if index in choices else self.board[index])
                    for index in range(row * 8, (row + 1) * 8)]
            self.emit(row + 1, *text)
        self.emit(self.status())

    def sheet(self):
        board = self.history[0].before.board if self.history else self.board
        fields = list(board)
        for number, record in enumerate(self.history, 1):
            fields[record.square] = str(number)
        self.emit(" " + "".join(f"{column:>3}" for column in COLS))
        for row in range(8):
            self.emit(str(row + 1) + "".join(f"{v:>3}" for v in fields[8 * row:8 * row + 8]))

    def stats(self):
        if self.history:
            total = sum(row.count for row in self.history)
            passes = sum(row.passed for row in self.history)
            self.emit("moves", len(self.history), "flips", total,
                      "avg", average(total, len(self.history)), "passes", passes)
        else:
            self.emit("moves", 0)
        for side in "BW":
            rows = [row for row in self.history if row.side == side]
            if not rows:
                self.emit(side, "moves", 0)
                continue
            flipped = sum(row.count for row in rows)
            maximum = max(row.count for row in rows)
            first = next(row for row in rows if row.count == maximum)
            corners = sum(row.square in (0, 7, 56, 63) for row in rows)
            self.emit(side, "moves", len(rows), "flips", flipped,
                      "avg", average(flipped, len(rows)), "max", maximum,
                      square_name(first.square), "corners", corners)

    def analyze(self, depth):
        losses = {"B": 0, "W": 0}
        for index, record in enumerate(self.history, 1):
            rankings = scored_moves(record.before.board, record.side, depth)
            best, best_square = rankings[0]
            value = next(score for score, square in rankings if square == record.square)
            losses[record.side] += best - value
            self.emit(index, record.side, square_name(record.square), value,
                      "best", square_name(best_square), best)
        self.emit("loss", "B", losses["B"], "W", losses["W"])

    def auto(self, black, white, seed=None):
        generator = Random(seed) if seed is not None else None
        names, passes = [], 0
        while not self.over:
            if generator is not None:
                choices = legal(self.board, self.side)
                square = choices[generator.draw() % len(choices)]
            else:
                depth = black if self.side == "B" else white
                square = scored_moves(self.board, self.side, depth)[0][1]
            names.append(square_name(square))
            passes += self.move(square, quiet=True)
        self.emit("random" if generator else "autoplay", len(names), "moves", passes, "passes")
        self.emit("moves", "".join(names))
        self.emit(game_over(self.board))

    def monte_carlo(self, samples, seed):
        generator = Random(seed)
        opponent = other(self.side)
        results = []
        for move in legal(self.board, self.side):
            start = place(self.board, self.side, move)
            wins = draws = losses = 0
            for _ in range(samples):
                final = random_game(start, opponent, generator)
                score = final.count(self.side) - final.count(opponent)
                if score > 0:
                    wins += 1
                elif score < 0:
                    losses += 1
                else:
                    draws += 1
            self.emit(square_name(move), wins, draws, losses)
            results.append((2 * wins + draws, move))
        best, square = min(results, key=lambda row: (-row[0], row[1]))
        self.emit("best", square_name(square), best)

    def valid_command(self, command, a):
        if command == "NEW":
            self.reset()
            self.emit("OK")
        elif command == "LOAD":
            self.board, self.side, self.over = a[0], a[1], False
            self.history, self.redo = [], []
            self.emit("OK")
            self.adjust()
        elif command == "DUMP":
            self.emit("board", self.board, self.side)
        elif command == "SHOW":
            self.print_board()
        elif command == "SCORE":
            self.emit("score", "B", self.board.count("B"), "W", self.board.count("W"),
                      "empty", self.board.count("."))
        elif command == "LEGAL":
            moves = legal(self.board, self.side) if not self.over else ()
            self.emit("legal", len(moves), *(square_name(move) for move in moves))
        elif command in SQUARE_ARGS:
            square = square_index(a[0])
            reason = self.reason(square)
            if reason:
                self.emit("ILLEGAL", reason)
            elif command == "FLIPS":
                changes = flips(self.board, self.side, square)
                self.emit("flips", a[0], len(changes),
                          *(square_name(s) for s in changes))
            else:
                self.move(square)
        elif command == "PLAY":
            text = a[0]
            for number, offset in enumerate(range(0, len(text), 2), 1):
                square = square_index(text[offset:offset + 2])
                reason = self.reason(square)
                if reason:
                    self.emit("ILLEGAL", "move", number, square_name(square), reason)
                    break
                self.move(square)
        elif command == "RECORD":
            self.read_record(a[0])
        elif command == "UNDO":
            count = int(a[0])
            if count > len(self.history):
                self.emit("ERROR", "cannot undo")
            else:
                removed = self.history[-count:]
                self.restore(removed[0].before)
                del self.history[-count:]
                self.redo = removed + self.redo
                self.emit(self.status())
        elif command == "REDO":
            count = int(a[0])
            if count > len(self.redo):
                self.emit("ERROR", "cannot redo")
            else:
                added = self.redo[:count]
                del self.redo[:count]
                self.history.extend(added)
                self.restore(added[-1].after)
                self.emit(self.status())
        elif command == "HISTORY":
            self.emit("history", len(self.history))
            for number, record in enumerate(self.history, 1):
                parts = [number, record.side, square_name(record.square), record.count]
                if record.passed:
                    parts.append("pass")
                self.emit(*parts)
        elif command == "SHEET":
            self.sheet()
        elif command == "STATS":
            self.stats()
        elif command == "TRANSFORM":
            self.board = transform_board(self.board, a[0])
            self.history = [transform_move(row, a[0]) for row in self.history]
            self.redo = [transform_move(row, a[0]) for row in self.redo]
            self.emit("OK")
        elif command == "EVAL":
            value, weights, own, enemy = evaluate(self.board, self.side)
            self.emit("eval", value, "weights", weights, "mobility", own, enemy)
        elif command == "STABLE":
            black, white = stable_counts(self.board)
            self.emit("stable", "B", black, "W", white)
        elif command == "HINT":
            for value, square in scored_moves(self.board, self.side, int(a[0])):
                self.emit(square_name(square), value)
        elif command == "PV":
            depth = int(a[0])
            value = search(self.board, self.side, depth)
            steps, _ = variation(self.board, self.side, depth)
            self.emit("pv", value, *steps)
        elif command == "AI":
            value, square = scored_moves(self.board, self.side, int(a[0]))[0]
            self.move(square, value=value)
        elif command == "ANALYZE":
            self.analyze(int(a[0]))
        elif command == "SOLVE":
            if self.board.count(".") >= 9:
                self.emit("ERROR", "too many empties")
            else:
                for value, square in exact_moves(self.board, self.side):
                    self.emit(square_name(square), value)
                steps, final = variation(self.board, self.side)
                self.emit("line", *steps)
                self.emit("final", "B", final.count("B"), "W", final.count("W"))
        elif command == "AUTOPLAY":
            self.auto(int(a[0]), int(a[1]))
        elif command == "RANDOM":
            self.auto(0, 0, seed=int(a[0]))
        elif command == "MC":
            self.monte_carlo(int(a[0]), int(a[1]))
        elif command == "PERFT":
            depth = int(a[0])
            self.emit("perft", depth, perft(self.board, self.side, depth))
        elif command == "DIVIDE":
            depth = int(a[0])
            total = 0
            for square in legal(self.board, self.side):
                count = perft(place(self.board, self.side, square),
                              other(self.side), depth - 1)
                self.emit(square_name(square), count)
                total += count
            self.emit("total", total)

    def execute(self, text):
        command, *args = text.split(" ")
        if command not in COMMANDS:
            self.emit("ERROR", "unknown command")
            return
        if command == "LOAD":
            valid = len(args) == 2 and len(args[0]) == 64 and \
                    set(args[0]) <= set(".BW") and args[1] in "BW"
            if not valid:
                self.emit("ERROR", "bad board")
                return
        elif command in SQUARE_ARGS:
            if len(args) != 1:
                self.emit("ERROR", "bad arguments")
                return
            if re.fullmatch(r"[a-h][1-8]", args[0]) is None:
                self.emit("ERROR", "bad square")
                return
        elif command in RECORD_ARGS:
            if len(args) != 1:
                self.emit("ERROR", "bad arguments")
                return
            record = args[0]
            valid = 2 <= len(record) <= 120 and len(record) % 2 == 0 and \
                    all(re.fullmatch(r"[a-h][1-8]", record[i:i + 2])
                        for i in range(0, len(record), 2))
            if not valid:
                self.emit("ERROR", "bad record")
                return
        elif command in ZERO_ARGS:
            if args:
                self.emit("ERROR", "bad arguments")
                return
        elif command == "TRANSFORM":
            if len(args) != 1 or args[0] not in TRANSFORMS:
                self.emit("ERROR", "bad arguments")
                return
        else:
            expected = 2 if command in ("AUTOPLAY", "MC") else 1
            if len(args) != expected or not all(re.fullmatch(r"[0-9]+", x) for x in args):
                self.emit("ERROR", "bad arguments")
                return
            numbers = list(map(int, args))
            if command == "AUTOPLAY":
                valid = all(1 <= n <= 4 for n in numbers)
            elif command in ("HINT", "PV", "AI", "ANALYZE"):
                valid = 1 <= numbers[0] <= 4
            elif command in ("PERFT", "DIVIDE"):
                valid = 1 <= numbers[0] <= 8
            elif command == "MC":
                valid = 1 <= numbers[0] <= 100 and 1 <= numbers[1] <= 2147483646
            elif command == "RANDOM":
                valid = 1 <= numbers[0] <= 2147483646
            else:
                valid = numbers[0] >= 1
            if not valid:
                self.emit("ERROR", "bad arguments")
                return
        if command in ACTIVE_ONLY and self.over:
            self.emit("ERROR", "game over")
            return
        self.valid_command(command, args)


def main():
    engine = Othello()
    count = int(sys.stdin.readline())
    for _ in range(count):
        engine.execute(sys.stdin.readline().rstrip("\n"))
    if engine.output:
        sys.stdout.write("\n".join(engine.output) + "\n")


if __name__ == "__main__":
    main()
