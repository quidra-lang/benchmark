import re
import sys
from dataclasses import dataclass
from functools import lru_cache

COLUMNS = "ABCDEFGHJKLMNOPQRST"
HANDICAP_POINTS = {
    9: "C3 G7 C7 G3 C5 G5 E3 E7 E5".split(),
    13: "D4 K10 D10 K4 D7 K7 G4 G10 G7".split(),
    19: "D4 Q16 D16 Q4 D10 Q10 K4 K16 K10".split(),
}
ARITY = {
    "BOARD": 2, "KOMI": 1, "SUPERKO": 1, "HANDICAP": 1,
    "PLAY": 2, "PASS": 1, "REPLAY": 1, "UNDO": 0,
    "SHOW": 0, "MAP": 0, "STATUS": 0, "CAPTURES": 0,
    "HISTORY": 0, "MOVES": 0, "GROUP": 1, "GROUPS": 0,
    "ATARI": 0, "LEGAL": 1, "EYES": 1, "SAFE": 1,
    "LADDER": 1, "DEAD": 1, "REGIONS": 0, "SCORE": 1,
}
POINT_ARGUMENTS = {"PLAY": 1, "GROUP": 0, "LADDER": 0, "DEAD": 0}


def other(color):
    return "W" if color == "B" else "B"


def half_text(amount):
    return ("-" if amount < 0 else "") + str(abs(amount) // 2) + \
           ("." + ("5" if abs(amount) % 2 else "0"))


def parse_komi(text):
    if not re.fullmatch(r"-?(0|[1-9][0-9]*)(?:\.[05])?", text):
        return None
    negative = text.startswith("-")
    unsigned = text[1:] if negative else text
    components = unsigned.split(".")
    integer = int(components[0])
    if integer > 100:
        return None
    fraction = int(components[1]) if len(components) > 1 else 0
    result = 2 * integer + (fraction // 5)
    if negative and result == 0:
        return None
    return -result if negative else result


def point_index(text, n):
    if not re.fullmatch(r"[A-HJ-T](?:[1-9]|1[0-9])", text):
        return None
    column = COLUMNS.find(text[0])
    row = int(text[1:])
    if not (0 <= column < n and 1 <= row <= n):
        return None
    return (row - 1) * n + column


def point_name(position, n):
    return COLUMNS[position % n] + str(position // n + 1)


def sgf_name(position, n):
    column, row = position % n, position // n
    return chr(97 + column) + chr(97 + n - 1 - row)


def sgf_position(text, n):
    column = ord(text[0]) - 97
    top_row = ord(text[1]) - 97
    return (n - top_row - 1) * n + column


@lru_cache(maxsize=100000)
def adjacent(position, n):
    row, col = divmod(position, n)
    points = []
    if row > 0:
        points.append(position - n)
    if row + 1 < n:
        points.append(position + n)
    if col > 0:
        points.append(position - 1)
    if col + 1 < n:
        points.append(position + 1)
    return tuple(points)


@lru_cache(maxsize=100000)
def diagonal(position, n):
    row, col = divmod(position, n)
    return tuple(r * n + c for r in (row - 1, row + 1)
                 for c in (col - 1, col + 1)
                 if 0 <= r < n and 0 <= c < n)


def flood(board, n, root, allowed):
    visited = {root}
    pending = [root]
    while pending:
        position = pending.pop()
        for neighbor in adjacent(position, n):
            if neighbor not in visited and board[neighbor] in allowed:
                visited.add(neighbor)
                pending.append(neighbor)
    return visited


def group(board, n, position):
    color = board[position]
    stones = flood(board, n, position, {color})
    liberties = {neighbor for stone in stones
                 for neighbor in adjacent(stone, n)
                 if board[neighbor] == "."}
    return stones, liberties


def groups(board, n, color=None):
    result = []
    visited = set()
    for position, value in enumerate(board):
        if value not in "BW" or position in visited:
            continue
        if color is not None and color != value:
            continue
        stones, liberties = group(board, n, position)
        visited.update(stones)
        result.append((value, min(stones), stones, liberties))
    return result


def placement(board, n, color, position):
    if board[position] != ".":
        return None, 0, "occupied"
    enemy = other(color)
    next_board = list(board)
    next_board[position] = color
    visited = set()
    captured = 0
    for neighbor in adjacent(position, n):
        if next_board[neighbor] != enemy or neighbor in visited:
            continue
        stones, liberties = group(next_board, n, neighbor)
        visited.update(stones)
        if not liberties:
            for stone in stones:
                next_board[stone] = "."
            captured += len(stones)
    next_board = "".join(next_board)
    if not group(next_board, n, position)[1]:
        return None, 0, "suicide"
    return next_board, captured, None


def regions(board, n):
    result = []
    visited = set()
    for position, value in enumerate(board):
        if value != "." or position in visited:
            continue
        points = flood(board, n, position, {"."})
        visited.update(points)
        borders = {board[neighbor] for point in points
                   for neighbor in adjacent(point, n)
                   if board[neighbor] in "BW"}
        owner = next(iter(borders)) if len(borders) == 1 else "neutral"
        result.append((min(points), points, owner))
    return result


def eyes(board, n, color):
    found = []
    for position, value in enumerate(board):
        if value != ".":
            continue
        neighbors = adjacent(position, n)
        if all(board[neighbor] == color for neighbor in neighbors):
            enemy = other(color)
            enemy_diagonals = sum(board[d] == enemy for d in diagonal(position, n))
            real = (enemy_diagonals <= 1 if len(neighbors) == 4
                    else enemy_diagonals == 0)
            found.append((position, real))
    return found


def unconditionally_alive(board, n, color):
    own = groups(board, n, color)
    remaining_groups = set(range(len(own)))
    opponent_areas = []
    visited = set()
    for position, disc in enumerate(board):
        if disc == color or position in visited:
            continue
        area = flood(board, n, position, set(".BW") - {color})
        visited.update(area)
        opponent_areas.append(area)

    touch = []
    vital = []
    for area in opponent_areas:
        touching = set()
        vital_for = set()
        empty = {position for position in area if board[position] == "."}
        for i, (_, _, stones, liberties) in enumerate(own):
            if any(any(neighbor in stones for neighbor in adjacent(position, n))
                   for position in area):
                touching.add(i)
            if empty <= liberties:
                vital_for.add(i)
        touch.append(touching)
        vital.append(vital_for)

    remaining_areas = set(range(len(opponent_areas)))
    while True:
        previous = (len(remaining_groups), len(remaining_areas))
        remaining_groups = {i for i in remaining_groups
                            if sum(i in vital[j] for j in remaining_areas) >= 2}
        remaining_areas = {j for j in remaining_areas
                           if touch[j] <= remaining_groups}
        if previous == (len(remaining_groups), len(remaining_areas)):
            break
    return [own[i] for i in sorted(remaining_groups)]


def read_ladder(board, n, target):
    defender = board[target]
    attacker = other(defender)

    @lru_cache(maxsize=None)
    def attack(current, depth):
        if depth >= 40:
            return False, None
        _, liberties = group(current, n, target)
        for move in sorted(liberties):
            updated, _, reason = placement(current, n, attacker, move)
            if reason:
                continue
            escaped, _ = defend(updated, depth + 1)
            if not escaped:
                return True, move
        return False, None

    @lru_cache(maxsize=None)
    def defend(current, depth):
        if depth >= 40:
            return True, None
        stones, liberties = group(current, n, target)
        candidates = set(liberties)
        checked = set()
        for stone in stones:
            for neighbor in adjacent(stone, n):
                if current[neighbor] != attacker or neighbor in checked:
                    continue
                enemy_stones, enemy_liberties = group(current, n, neighbor)
                checked.update(enemy_stones)
                if len(enemy_liberties) == 1:
                    candidates.update(enemy_liberties)
        for move in sorted(candidates):
            updated, _, reason = placement(current, n, defender, move)
            if reason:
                continue
            _, next_liberties = group(updated, n, target)
            if len(next_liberties) >= 3:
                return True, move
            if len(next_liberties) == 2 and not attack(updated, depth + 1)[0]:
                return True, move
        return False, None

    liberties = group(board, n, target)[1]
    if len(liberties) >= 3:
        return "safe", None
    if len(liberties) == 1:
        escaped, move = defend(board, 0)
        return ("escapes" if escaped else "captured"), move
    captured, move = attack(board, 0)
    return ("captured" if captured else "escapes"), move


@dataclass(frozen=True)
class Snapshot:
    board: str
    turn: str
    captured_black: int
    captured_white: int
    passes: int
    over: bool


@dataclass(frozen=True)
class Move:
    color: str
    position: int | None
    captured: int
    before: Snapshot


class GoGame:
    def __init__(self):
        self.superko = False
        self.output = []
        self.reset(19, 13)

    def reset(self, n, komi2):
        self.n = n
        self.komi2 = komi2
        self.board = "." * (n * n)
        self.turn = "B"
        self.prisoners = {"B": 0, "W": 0}
        self.passes = 0
        self.over = False
        self.handicap = []
        self.history = []
        self.positions = [self.board]
        self.dead = set()

    def emit(self, *values):
        self.output.append(" ".join(map(str, values)))

    def snapshot(self):
        return Snapshot(self.board, self.turn, self.prisoners["B"],
                        self.prisoners["W"], self.passes, self.over)

    def restore(self, state):
        self.board, self.turn, self.passes, self.over = (
            state.board, state.turn, state.passes, state.over)
        self.prisoners = {"B": state.captured_black, "W": state.captured_white}

    def point(self, text):
        return point_index(text, self.n)

    def point_text(self, position):
        return point_name(position, self.n)

    def star_points(self):
        indices = range(9) if self.n == 19 else (0, 1, 2, 3, 8)
        return {self.point(HANDICAP_POINTS[self.n][i]) for i in indices}

    def check_placement(self, color, position):
        next_board, captured, reason = placement(self.board, self.n, color, position)
        if reason:
            return None, 0, reason
        if len(self.positions) >= 2 and next_board == self.positions[-2]:
            return None, 0, "ko"
        if self.superko and next_board in self.positions:
            return None, 0, "superko"
        return next_board, captured, None

    def move(self, color, position, checked=None):
        before = self.snapshot()
        captured = 0
        if position is None:
            self.passes += 1
            if self.passes == 2:
                self.over = True
        else:
            if checked is None:
                checked = self.check_placement(color, position)
            self.board, captured, _ = checked
            self.prisoners[color] += captured
            self.passes = 0
        self.turn = other(color)
        self.history.append(Move(color, position, captured, before))
        self.positions.append(self.board)
        self.dead.clear()
        return captured

    def no_dead_board(self):
        board = list(self.board)
        for position in self.dead:
            board[position] = "."
        return "".join(board)

    def show(self, region_map=False):
        board = self.no_dead_board() if region_map else self.board
        display = {}
        if region_map:
            for _, region, owner in regions(board, self.n):
                character = "x" if owner == "B" else "o" if owner == "W" else "."
                display.update({position: character for position in region})
        header = "   " + " ".join(COLUMNS[:self.n])
        self.emit(header)
        stars = self.star_points()
        for row in range(self.n - 1, -1, -1):
            fields = []
            for position in range(row * self.n, (row + 1) * self.n):
                disc = board[position]
                if disc == ".":
                    fields.append(display.get(position, ".") if region_map
                                  else "+" if position in stars else ".")
                elif region_map:
                    fields.append("X" if disc == "B" else "O")
                else:
                    letter = "X" if disc == "B" else "O"
                    fields.append(letter.lower() if position in self.dead else letter)
            self.emit(f"{row + 1:>2}", " ".join(fields), row + 1)
        self.emit(header)

    def show_group(self, color, representative, stones, liberties):
        self.emit("group", color, self.point_text(representative),
                  "size", len(stones), "liberties", len(liberties))
        self.emit("stones", *(self.point_text(p) for p in sorted(stones)))
        self.emit("liberties", *(self.point_text(p) for p in sorted(liberties)))

    def show_score(self, method):
        board = self.no_dead_board()
        territory = {"B": 0, "W": 0}
        for _, points, owner in regions(board, self.n):
            if owner in territory:
                territory[owner] += len(points)
        stones = {color: board.count(color) for color in "BW"}
        if method == "AREA":
            b_total = 2 * (stones["B"] + territory["B"])
            w_total = 2 * (stones["W"] + territory["W"]) + self.komi2
            self.emit("B", "stones", stones["B"], "territory", territory["B"],
                      "total", half_text(b_total))
            self.emit("W", "stones", stones["W"], "territory", territory["W"],
                      "komi", half_text(self.komi2), "total", half_text(w_total))
        else:
            prisoners = {
                "B": self.prisoners["B"] + sum(self.board[p] == "W" for p in self.dead),
                "W": self.prisoners["W"] + sum(self.board[p] == "B" for p in self.dead),
            }
            b_total = 2 * (territory["B"] + prisoners["B"])
            w_total = 2 * (territory["W"] + prisoners["W"]) + self.komi2
            self.emit("B", "territory", territory["B"], "prisoners", prisoners["B"],
                      "total", half_text(b_total))
            self.emit("W", "territory", territory["W"], "prisoners", prisoners["W"],
                      "komi", half_text(self.komi2), "total", half_text(w_total))
        difference = b_total - w_total
        self.emit("result", "B+" + half_text(difference) if difference > 0
                  else "W+" + half_text(-difference) if difference < 0
                  else "Draw")

    def replay(self, text):
        records = re.findall(r";([BW])\[([a-z]*)\]", text)
        played = 0
        stopped = None
        for color, coordinate in records:
            point = sgf_position(coordinate, self.n) if coordinate else None
            label = self.point_text(point) if point is not None else "pass"
            reason = ("game over" if self.over else
                      "turn" if color != self.turn else None)
            checked = None
            if reason is None and point is not None:
                checked = self.check_placement(color, point)
                reason = checked[2]
            if reason:
                stopped = (color, label, reason)
                break
            self.move(color, point, checked)
            played += 1
        if stopped:
            self.emit("replay", played, "moves", "stopped", *stopped)
        else:
            self.emit("replay", played, "moves")
        if self.over:
            self.emit("game over")

    def moves_record(self):
        result = f"(;GM[1]FF[4]SZ[{self.n}]KM[{half_text(self.komi2)}]"
        if self.handicap:
            result += f"HA[{len(self.handicap)}]AB"
            result += "".join("[" + sgf_name(p, self.n) + "]" for p in self.handicap)
        for row in self.history:
            coordinate = "" if row.position is None else sgf_name(row.position, self.n)
            result += f";{row.color}[{coordinate}]"
        self.emit(result + ")")

    def command(self, name, a):
        if name == "BOARD":
            self.reset(int(a[0]), parse_komi(a[1]))
            self.emit("board", self.n, "komi", half_text(self.komi2))
        elif name == "KOMI":
            self.komi2 = parse_komi(a[0])
            self.emit("komi", half_text(self.komi2))
        elif name == "SUPERKO":
            self.superko = a[0] == "ON"
            self.emit("superko", "on" if self.superko else "off")
        elif name == "HANDICAP":
            if self.history or any(disc in "BW" for disc in self.board):
                self.emit("ERROR", "handicap not allowed")
                return
            amount = int(a[0])
            indexes = ([0, 1, 2, 3, 8] if amount == 5
                       else [0, 1, 2, 3, 4, 5, 8] if amount == 7
                       else list(range(amount)))
            self.handicap = [self.point(HANDICAP_POINTS[self.n][i]) for i in indexes]
            board = list(self.board)
            for point in self.handicap:
                board[point] = "B"
            self.board = "".join(board)
            self.turn = "W"
            self.positions = [self.board]
            self.dead.clear()
            self.emit("handicap", amount, *(self.point_text(p) for p in self.handicap))
        elif name == "PLAY":
            color, point = a[0], self.point(a[1])
            reason = "turn" if color != self.turn else None
            checked = None
            if reason is None:
                checked = self.check_placement(color, point)
                reason = checked[2]
            if reason:
                self.emit("ILLEGAL", color, a[1], reason)
            else:
                captured = self.move(color, point, checked)
                self.emit(color, a[1],
                          *(("captures", captured) if captured else ()))
        elif name == "PASS":
            color = a[0]
            if color != self.turn:
                self.emit("ILLEGAL", color, "pass", "turn")
            else:
                self.move(color, None)
                self.emit(color, "pass")
                if self.over:
                    self.emit("game over")
        elif name == "REPLAY":
            self.replay(a[0])
        elif name == "UNDO":
            if not self.history:
                self.emit("ERROR", "nothing to undo")
            else:
                row = self.history.pop()
                self.restore(row.before)
                self.positions.pop()
                self.dead.clear()
                self.emit("undo", row.color, "pass" if row.position is None
                          else self.point_text(row.position))
        elif name == "SHOW":
            self.show()
        elif name == "MAP":
            self.show(True)
        elif name == "STATUS":
            self.emit("size", self.n, "komi", half_text(self.komi2),
                      "handicap", len(self.handicap), "superko",
                      "on" if self.superko else "off")
            if self.over:
                self.emit("moves", len(self.history), "game over")
            else:
                self.emit("moves", len(self.history), "next", self.turn,
                          "passes", self.passes)
        elif name == "CAPTURES":
            self.emit("captures", "B", self.prisoners["B"], "W", self.prisoners["W"])
        elif name == "HISTORY":
            self.emit("history", len(self.history))
            for i, row in enumerate(self.history, 1):
                parts = [i, row.color,
                         "pass" if row.position is None else self.point_text(row.position)]
                if row.captured:
                    parts.extend(("captures", row.captured))
                self.emit(*parts)
        elif name == "MOVES":
            self.moves_record()
        elif name == "GROUP":
            position = self.point(a[0])
            if self.board[position] == ".":
                self.emit("ERROR", "no stone")
            else:
                stones, liberties = group(self.board, self.n, position)
                self.show_group(self.board[position], min(stones), stones, liberties)
        elif name == "GROUPS":
            found = groups(self.board, self.n)
            self.emit("groups", len(found))
            for color, first, stones, liberties in found:
                parts = [color, self.point_text(first), "size", len(stones),
                         "liberties", len(liberties)]
                if first in self.dead:
                    parts.append("dead")
                self.emit(*parts)
        elif name == "ATARI":
            found = [(color, first, stones, liberties)
                     for color, first, stones, liberties in groups(self.board, self.n)
                     if len(liberties) == 1]
            if not found:
                self.emit("atari", "none")
            for color, first, stones, liberties in found:
                self.emit("atari", color, self.point_text(first), "size", len(stones),
                          "at", self.point_text(next(iter(liberties))))
        elif name == "LEGAL":
            color = a[0]
            rejected = []
            count = 0
            for position, disc in enumerate(self.board):
                if disc != ".":
                    continue
                _, _, reason = self.check_placement(color, position)
                if reason:
                    rejected.append((self.point_text(position), reason))
                else:
                    count += 1
            self.emit("legal", color, count)
            for point, reason in rejected:
                self.emit(point, reason)
        elif name == "EYES":
            found = eyes(self.board, self.n, a[0])
            self.emit("eyes", a[0], len(found))
            for position, real in found:
                self.emit(self.point_text(position), "real" if real else "false")
        elif name == "SAFE":
            found = unconditionally_alive(self.board, self.n, a[0])
            self.emit("safe", a[0], len(found))
            for _, position, stones, _ in found:
                self.emit(self.point_text(position), "size", len(stones))
        elif name == "LADDER":
            point = self.point(a[0])
            if self.board[point] == ".":
                self.emit("ERROR", "no stone")
            else:
                status, move = read_ladder(self.board, self.n, point)
                if move is None:
                    self.emit("ladder", a[0], status)
                else:
                    self.emit("ladder", a[0], status, self.point_text(move))
        elif name == "DEAD":
            point = self.point(a[0])
            if self.board[point] == ".":
                self.emit("ERROR", "no stone")
            else:
                stones, _ = group(self.board, self.n, point)
                first = min(stones)
                if first in self.dead:
                    self.dead.difference_update(stones)
                    self.emit("alive", self.board[point], self.point_text(first),
                              "size", len(stones))
                else:
                    self.dead.update(stones)
                    self.emit("dead", self.board[point], self.point_text(first),
                              "size", len(stones))
        elif name == "REGIONS":
            found = regions(self.no_dead_board(), self.n)
            self.emit("regions", len(found))
            for first, points, owner in found:
                self.emit(self.point_text(first), "size", len(points), owner)
        elif name == "SCORE":
            self.show_score(a[0])

    def execute(self, line):
        name, *a = line.split(" ")
        if name not in ARITY:
            self.emit("ERROR", "unknown command")
            return
        if len(a) != ARITY[name]:
            self.emit("ERROR", "bad arguments")
            return
        valid = True
        if name == "BOARD":
            valid = a[0] in ("9", "13", "19") and parse_komi(a[1]) is not None
        elif name == "KOMI":
            valid = parse_komi(a[0]) is not None
        elif name == "SUPERKO":
            valid = a[0] in ("ON", "OFF")
        elif name == "HANDICAP":
            valid = a[0] in tuple(str(i) for i in range(2, 10))
        elif name in ("PLAY", "PASS", "LEGAL", "EYES", "SAFE"):
            valid = a[0] in ("B", "W")
        elif name == "SCORE":
            valid = a[0] in ("AREA", "TERRITORY")
        if not valid:
            self.emit("ERROR", "bad arguments")
            return
        if name in POINT_ARGUMENTS and point_index(a[POINT_ARGUMENTS[name]], self.n) is None:
            self.emit("ERROR", "bad point")
            return
        if name == "REPLAY":
            valid = re.fullmatch(r"(?:;[BW]\[[a-z]{0,2}\])+", a[0])
            if valid:
                for color, content in re.findall(r";([BW])\[([a-z]*)\]", a[0]):
                    if content and (len(content) != 2 or
                                    ord(content[0]) - 97 >= self.n or
                                    ord(content[1]) - 97 >= self.n):
                        valid = False
                        break
            if not valid:
                self.emit("ERROR", "bad sequence")
                return
        if name in ("PLAY", "PASS", "REPLAY") and self.over:
            self.emit("ERROR", "game over")
            return
        self.command(name, a)


def main():
    game = GoGame()
    count = int(sys.stdin.readline())
    for _ in range(count):
        game.execute(sys.stdin.readline().rstrip("\n"))
    if game.output:
        sys.stdout.write("\n".join(game.output) + "\n")


if __name__ == "__main__":
    main()
