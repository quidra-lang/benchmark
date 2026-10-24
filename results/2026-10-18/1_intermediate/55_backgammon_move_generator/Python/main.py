import re
import sys
from itertools import groupby


WHITE = 0
BLACK = 1
COLORS = ("W", "B")
OFF = 0
BAR = 25
CHECKERS = 15
STARTING_POINTS = ((24, 2), (13, 5), (8, 3), (6, 5))
MULTIPLIERS = {"single": 1, "gammon": 2, "backgammon": 3}
RESULTS = ("single", "gammon", "backgammon", "drop")
STRATEGIES = ("BEST", "FIRST", "RANDOM")
MAX_CUBE = 64
MAX_SEED = 2147483646
MODULUS = 2147483647
MULTIPLIER = 48271


class CommandError(Exception):
    pass


def require(condition, message="bad arguments"):
    if not condition:
        raise CommandError(message)


def number_argument(text, low, high, message="bad arguments"):
    require(re.fullmatch(r"[0-9]+", text) is not None, message)
    value = int(text)
    require(low <= value <= high, message)
    return value


def dice_arguments(arguments):
    return number_argument(arguments[0], 1, 6), number_argument(arguments[1], 1, 6)


def point_name(point):
    if point == BAR:
        return "bar"
    if point == OFF:
        return "off"
    return str(point)


class Dice:
    def __init__(self, seed):
        self.value = seed

    def next(self):
        self.value = MULTIPLIER * self.value % MODULUS
        return self.value

    def roll(self):
        return self.next() % 6 + 1


class Position:
    def __init__(self, checkers):
        self.checkers = checkers

    @classmethod
    def starting(cls):
        side = [0] * 26
        for point, count in STARTING_POINTS:
            side[point] = count
        return cls([list(side), list(side)])

    def copy(self):
        return Position([list(side) for side in self.checkers])

    def key(self):
        return tuple(self.checkers[WHITE] + self.checkers[BLACK])

    def board_value(self, number):
        return self.checkers[WHITE][number] - self.checkers[BLACK][25 - number]

    def opposing(self, color, point):
        return self.checkers[1 - color][25 - point]

    def finished(self, color):
        return self.checkers[color][OFF] == CHECKERS

    def pip_count(self, color):
        return sum(point * count for point, count in enumerate(self.checkers[color]))

    def keith_count(self, color):
        side = self.checkers[color]
        empty = sum(side[point] == 0 for point in (4, 5, 6))
        return (
            self.pip_count(color) + 2 * max(side[1] - 1, 0) + max(side[2] - 1, 0)
            + max(side[3] - 3, 0) + empty
        )

    def rearmost(self, color):
        side = self.checkers[color]
        return max((point for point in range(1, 26) if side[point]), default=0)

    def has_contact(self):
        return self.rearmost(WHITE) + self.rearmost(BLACK) > 25

    def all_home(self, color):
        return not any(self.checkers[color][7:])

    def starting_points(self, color):
        side = self.checkers[color]
        if side[BAR]:
            return [BAR]
        return [point for point in range(24, 0, -1) if side[point]]

    def sub_move(self, color, start, die):
        destination = start - die
        hit = False
        if destination >= 1:
            opposing = self.opposing(color, destination)
            if opposing >= 2:
                return None
            hit = opposing == 1
        else:
            if not self.all_home(color):
                return None
            if destination < 0 and any(self.checkers[color][start + 1:7]):
                return None
            destination = OFF
        result = self.copy()
        result.checkers[color][start] -= 1
        result.checkers[color][destination] += 1
        if hit:
            result.checkers[1 - color][25 - destination] -= 1
            result.checkers[1 - color][BAR] += 1
        return result, destination, hit


def game_result(position, winner):
    loser = position.checkers[1 - winner]
    if loser[OFF] > 0:
        return "single"
    if loser[BAR] > 0 or any(loser[19:25]):
        return "backgammon"
    return "gammon"


def blot_shots(distances):
    count = 0
    for first in range(1, 7):
        for second in range(1, 7):
            reachable = {first, second, first + second}
            if first == second:
                reachable.update((3 * first, 4 * first))
            if reachable & distances:
                count += 1
    return count


def evaluation_terms(position, color):
    mine = position.checkers[color]
    theirs = position.checkers[1 - color]
    pips = position.pip_count(1 - color) - position.pip_count(color)
    blots = 0
    for point in range(1, 25):
        if mine[point] == 1:
            distances = {point - target for target in range(point) if theirs[25 - target]}
            blots += blot_shots(distances)
    home = sum(mine[point] >= 2 for point in range(1, 7))
    prime = 0
    run = 0
    for point in range(1, 25):
        run = run + 1 if mine[point] >= 2 else 0
        prime = max(prime, run)
    anchors = sum(mine[point] >= 2 for point in range(19, 25))
    bar = theirs[BAR] - mine[BAR]
    return pips, blots, home, prime, anchors, bar


def evaluate(position, color):
    pips, blots, home, prime, anchors, bar = evaluation_terms(position, color)
    return 2 * pips - blots + 4 * home + 3 * prime + 3 * anchors + 6 * bar


def find_merge(pairs, hits):
    for first, (_, middle) in enumerate(pairs):
        if middle >= 1 and middle not in hits:
            for second, (start, _) in enumerate(pairs):
                if start == middle:
                    return first, second
    return None


def merged_pairs(moves, hits):
    pairs = sorted(moves, reverse=True)
    while True:
        found = find_merge(pairs, hits)
        if found is None:
            return pairs
        first, second = found
        combined = (pairs[first][0], pairs[second][1])
        del pairs[second]
        del pairs[first]
        pairs.append(combined)
        pairs.sort(reverse=True)


def play_notation(pairs, hits):
    if not pairs:
        return "none"
    parts = []
    starred = set()
    for (start, destination), group in groupby(pairs):
        count = len(list(group))
        text = point_name(start) + "/" + point_name(destination)
        if destination in hits and destination not in starred:
            starred.add(destination)
            text += "*"
        if count >= 2:
            text += f"({count})"
        parts.append(text)
    return " ".join(parts)


class Sequence:
    def __init__(self, moves, dice, hits, position):
        self.moves = moves
        self.dice = dice
        self.hits = hits
        self.position = position


class Play:
    def __init__(self, sequence):
        self.position = sequence.position
        self.key = merged_pairs(sequence.moves, sequence.hits)
        self.notation = play_notation(self.key, sequence.hits)


class PlayGenerator:
    def __init__(self, position, color, first, second):
        self.color = color
        self.sequences = []
        self.shortest = {}
        dice = [first] * 4 if first == second else [first, second]
        self.explore(position, dice, [], [], set())
        self.maximum = max(len(sequence.moves) for sequence in self.sequences)
        self.by_position = {}
        for sequence in self.legal_sequences(first, second):
            key = sequence.position.key()
            if key not in self.by_position:
                self.by_position[key] = Play(sequence)
        self.plays = sorted(self.by_position.values(), key=lambda play: play.key, reverse=True)

    def explore(self, position, remaining, moves, used, hits):
        key = position.key()
        if key not in self.shortest or len(moves) < self.shortest[key]:
            self.shortest[key] = len(moves)
        self.sequences.append(Sequence(moves, used, hits, position))
        for index, die in enumerate(remaining):
            if die in remaining[:index]:
                continue
            rest = remaining[:index] + remaining[index + 1:]
            for start in position.starting_points(self.color):
                outcome = position.sub_move(self.color, start, die)
                if outcome is None:
                    continue
                after, destination, hit = outcome
                self.explore(
                    after, rest, moves + [(start, destination)], used + [die],
                    hits | {destination} if hit else hits,
                )

    def legal_sequences(self, first, second):
        candidates = [s for s in self.sequences if len(s.moves) == self.maximum]
        if self.maximum == 1 and first != second:
            larger = max(first, second)
            with_larger = [s for s in candidates if s.dice[0] == larger]
            if with_larger:
                return with_larger
        return candidates


def ranked_plays(plays, color):
    scored = [(evaluate(play.position, color), play) for play in plays]
    scored.sort(key=lambda item: -item[0])
    return scored


def parse_point(text, first):
    if first and text == "bar":
        return BAR
    if not first and text == "off":
        return OFF
    if not first and text.endswith("*"):
        text = text[:-1]
    if re.fullmatch(r"[1-9][0-9]*", text) is None or int(text) > 24:
        return None
    return int(text)


def parse_element(element):
    match = re.fullmatch(r"(.*)\(([234])\)", element)
    path, count = (match.group(1), int(match.group(2))) if match else (element, 1)
    parts = path.split("/")
    if len(parts) < 2:
        return None
    points = [parse_point(part, index == 0) for index, part in enumerate(parts)]
    if None in points:
        return None
    if any(earlier <= later for earlier, later in zip(points, points[1:])):
        return None
    return [pair for pair in zip(points, points[1:]) for _ in range(count)]


def parse_play(arguments):
    if arguments == ["none"]:
        return []
    moves = []
    for element in arguments:
        pairs = parse_element(element)
        if pairs is None:
            return None
        moves.extend(pairs)
    return moves


def apply_moves(position, color, moves):
    result = position.copy()
    mine = result.checkers[color]
    theirs = result.checkers[1 - color]
    for start, destination in moves:
        mine[start] -= 1
        mine[destination] += 1
    for point in {destination for _, destination in moves if destination >= 1}:
        if position.opposing(color, point) == 1:
            theirs[25 - point] -= 1
            theirs[BAR] += 1
    return result


def rule_violation(position, color, moves, result):
    mine = result.checkers[color]
    if any(count < 0 for count in mine):
        return "no checker"
    if mine[BAR] > 0 and any(start != BAR for start, _ in moves):
        return "bar"
    if any(end >= 1 and position.opposing(color, end) >= 2 for _, end in moves):
        return "blocked"
    if any(end == OFF for _, end in moves) and not result.all_home(color):
        return "bear-off"
    return None


class GameState:
    def __init__(self):
        self.position = Position.starting()
        self.side = WHITE
        self.cube = 1
        self.owner = None
        self.pending = False
        self.over = False
        self.score = [0, 0]

    def copy(self):
        state = GameState()
        state.position = self.position.copy()
        state.side = self.side
        state.cube = self.cube
        state.owner = self.owner
        state.pending = self.pending
        state.over = self.over
        state.score = list(self.score)
        return state

    def owner_name(self):
        return "center" if self.owner is None else COLORS[self.owner]


def cube_decision(state, prohibited):
    side = state.side
    other = 1 - side
    if state.owner == other or state.cube == MAX_CUBE or prohibited:
        return "unavailable"
    position = state.position
    if position.has_contact():
        value = evaluate(position, side)
        if value < 60:
            return "no double"
        if value <= 100:
            return "double take"
        return "double drop"
    advantage = 8 * position.keith_count(side) - 7 * position.keith_count(other)
    limit = 28 if state.owner is None else 21
    if advantage > limit:
        return "no double"
    if advantage >= 14:
        return "double take"
    return "double drop"


class HistoryEntry:
    def __init__(self, record, before, after):
        self.record = record
        self.before = before
        self.after = after


class MatchScore:
    def __init__(self, target):
        self.target = target
        self.points = [0, 0]
        self.crawford = False
        self.crawford_played = False

    def prohibits(self, side, cube):
        return self.crawford or self.points[side] + cube >= self.target

    def score_text(self):
        return f"{self.points[WHITE]}-{self.points[BLACK]}"


class GameRecord:
    def __init__(self):
        self.lines = []
        self.plays = 0
        self.winner = None
        self.result = None
        self.points = 0

    def finish(self, winner, result, points):
        self.winner = winner
        self.result = result
        self.points = points


def choose_play(position, color, first, second, strategy, dice):
    plays = PlayGenerator(position, color, first, second).plays
    if strategy == "BEST":
        return ranked_plays(plays, color)[0][1]
    if strategy == "FIRST":
        return plays[0]
    return plays[dice.next() % len(plays)]


def play_game(state, strategies, dice, match=None, opening=None):
    record = GameRecord()
    turn = 1
    while True:
        side = state.side
        other = 1 - side
        if turn == 1 and opening is not None:
            first, second = opening
        else:
            prohibited = match is not None and match.prohibits(side, state.cube)
            decision = cube_decision(state, prohibited)
            if decision in ("double take", "double drop"):
                record.lines.append(f"{turn} {COLORS[side]} doubles {2 * state.cube}")
            if decision == "double drop":
                record.lines.append(f"{turn} {COLORS[other]} drops")
                record.finish(side, "drop", state.cube)
                return record
            if decision == "double take":
                record.lines.append(f"{turn} {COLORS[other]} takes")
                state.cube *= 2
                state.owner = other
            first, second = dice.roll(), dice.roll()
        play = choose_play(state.position, side, first, second, strategies[side], dice)
        state.position = play.position
        record.plays += 1
        record.lines.append(f"{turn} {COLORS[side]} {first}-{second} {play.notation}")
        if state.position.finished(side):
            result = game_result(state.position, side)
            record.finish(side, result, MULTIPLIERS[result] * state.cube)
            return record
        state.side = other
        turn += 1


def opening_game(dice):
    while True:
        white, black = dice.roll(), dice.roll()
        if white != black:
            break
    state = GameState()
    state.side = WHITE if white > black else BLACK
    return state, (white, black)


def parse_position(arguments):
    require(len(arguments) == 4, "bad position")
    values = arguments[0].split(",")
    require(len(values) == 24, "bad position")
    require(all(re.fullmatch(r"-?[0-9]+", value) for value in values), "bad position")
    wbar = number_argument(arguments[1], 0, CHECKERS, "bad position")
    bbar = number_argument(arguments[2], 0, CHECKERS, "bad position")
    require(arguments[3] in COLORS, "bad position")
    checkers = [[0] * 26, [0] * 26]
    for number, text in enumerate(values, 1):
        value = int(text)
        if value > 0:
            checkers[WHITE][number] = value
        else:
            checkers[BLACK][25 - number] = -value
    checkers[WHITE][BAR] = wbar
    checkers[BLACK][BAR] = bbar
    for side in checkers:
        side[OFF] = CHECKERS - sum(side)
        require(0 <= side[OFF] <= CHECKERS - 1, "bad position")
    return Position(checkers), COLORS.index(arguments[3])


def position_text(position, side):
    values = ",".join(str(position.board_value(number)) for number in range(1, 25))
    white_bar = position.checkers[WHITE][BAR]
    black_bar = position.checkers[BLACK][BAR]
    return f"POS {values} {white_bar} {black_bar} {COLORS[side]}"


def point_field(value, row):
    count = abs(value)
    if count < row:
        return "."
    if row == 5 and count > 5:
        return str(count)
    return "W" if value > 0 else "B"


def board_line(fields):
    left = "".join(f"{field:>3}" for field in fields[:6])
    right = "".join(f"{field:>3}" for field in fields[6:])
    return left + " |" + right


class Referee:
    def __init__(self):
        self.state = GameState()
        self.history = []
        self.redo = []
        self.output = []
        self.handlers = {
            "NEW": self.new_game,
            "POS": self.set_position,
            "SHOW": self.show,
            "BOARD": self.board,
            "PIPS": self.pips,
            "RACE": self.race,
            "MOVES": self.moves,
            "PLAY": self.play,
            "AUTO": self.auto,
            "HINT": self.hint,
            "EVAL": self.evaluation,
            "SHOTS": self.shots,
            "CUBE": self.cube,
            "DOUBLE": self.double,
            "TAKE": self.take,
            "DROP": self.drop,
            "RESIGN": self.resign,
            "SCORE": self.show_score,
            "HISTORY": self.show_history,
            "UNDO": self.undo,
            "REDO": self.redo_plays,
            "GAME": self.game,
            "MATCH": self.match,
            "STATS": self.stats,
        }

    def emit(self, *parts):
        self.output.append(" ".join(str(part) for part in parts))

    def require_in_play(self, allow_pending=True):
        if self.state.over:
            raise CommandError("game over")
        if self.state.pending and not allow_pending:
            raise CommandError("double pending")

    def end_game(self, winner, result, points):
        self.state.over = True
        self.state.score[winner] += points
        self.emit("result", COLORS[winner], result, points)

    def commit_play(self, play, first, second):
        before = self.state.copy()
        state = self.state
        side = state.side
        state.position = play.position
        if state.position.finished(side):
            result = game_result(state.position, side)
            self.end_game(side, result, MULTIPLIERS[result] * state.cube)
        else:
            state.side = 1 - side
        record = f"{COLORS[side]} {first}-{second} {play.notation}"
        self.history.append(HistoryEntry(record, before, state.copy()))
        self.redo = []

    def new_game(self, arguments):
        require(not arguments)
        score = self.state.score
        self.state = GameState()
        self.state.score = score
        self.history = []
        self.redo = []
        self.emit("OK")

    def set_position(self, arguments):
        position, side = parse_position(arguments)
        state = GameState()
        state.position = position
        state.side = side
        state.score = self.state.score
        self.state = state
        self.history = []
        self.redo = []
        self.emit("OK")

    def show(self, arguments):
        require(not arguments)
        self.emit(position_text(self.state.position, self.state.side))

    def board(self, arguments):
        require(not arguments)
        state = self.state
        position = state.position
        upper = range(13, 25)
        lower = range(12, 0, -1)
        self.emit(board_line([str(number) for number in upper]))
        for row in range(1, 6):
            self.emit(board_line([point_field(position.board_value(n), row) for n in upper]))
        if state.over:
            status = "game over"
        elif state.pending:
            status = f"{COLORS[state.side]} doubles"
        else:
            status = f"{COLORS[state.side]} to move"
        white, black = position.checkers
        self.emit(
            f"bar W{white[BAR]} B{black[BAR]} | off W{white[OFF]} B{black[OFF]}"
            f" | cube {state.cube} {state.owner_name()} | {status}"
        )
        for row in range(5, 0, -1):
            self.emit(board_line([point_field(position.board_value(n), row) for n in lower]))
        self.emit(board_line([str(number) for number in lower]))

    def pips(self, arguments):
        require(not arguments)
        position = self.state.position
        self.emit("pips", "W", position.pip_count(WHITE), "B", position.pip_count(BLACK))

    def race(self, arguments):
        require(not arguments)
        self.require_in_play()
        position = self.state.position
        if position.has_contact():
            self.emit("contact")
        else:
            self.emit("race", "W", position.keith_count(WHITE), "B", position.keith_count(BLACK))

    def moves(self, arguments):
        require(len(arguments) == 2)
        first, second = dice_arguments(arguments)
        self.require_in_play()
        plays = PlayGenerator(self.state.position, self.state.side, first, second).plays
        for play in plays:
            self.emit(play.notation)
        self.emit("total", len(plays))

    def play(self, arguments):
        require(len(arguments) >= 3)
        first, second = dice_arguments(arguments)
        self.require_in_play(False)
        moves = parse_play(arguments[2:])
        if moves is None:
            self.emit("ILLEGAL syntax")
            return
        position = self.state.position
        side = self.state.side
        result = apply_moves(position, side, moves)
        violation = rule_violation(position, side, moves, result)
        if violation is not None:
            self.emit("ILLEGAL", violation)
            return
        generator = PlayGenerator(position, side, first, second)
        key = result.key()
        if key in generator.by_position:
            play = generator.by_position[key]
            self.emit("OK", play.notation)
            self.commit_play(play, first, second)
        elif key in generator.shortest:
            if generator.shortest[key] < generator.maximum:
                self.emit("ILLEGAL too few dice")
            else:
                self.emit("ILLEGAL larger die required")
        else:
            self.emit("ILLEGAL impossible")

    def auto(self, arguments):
        require(len(arguments) == 2)
        first, second = dice_arguments(arguments)
        self.require_in_play(False)
        side = self.state.side
        plays = PlayGenerator(self.state.position, side, first, second).plays
        value, play = ranked_plays(plays, side)[0]
        self.emit("OK", play.notation, "eval", value)
        self.commit_play(play, first, second)

    def hint(self, arguments):
        require(len(arguments) == 3)
        first, second = dice_arguments(arguments)
        count = number_argument(arguments[2], 1, 1000)
        self.require_in_play()
        side = self.state.side
        plays = PlayGenerator(self.state.position, side, first, second).plays
        for value, play in ranked_plays(plays, side)[:count]:
            self.emit(value, play.notation)

    def evaluation(self, arguments):
        require(not arguments)
        self.require_in_play()
        side = self.state.side
        pips, blots, home, prime, anchors, bar = evaluation_terms(self.state.position, side)
        self.emit(
            "eval", evaluate(self.state.position, side), "pips", pips, "blots", blots,
            "home", home, "prime", prime, "anchors", anchors, "bar", bar,
        )

    def shots(self, arguments):
        require(not arguments)
        self.require_in_play()
        position = self.state.position
        side = self.state.side
        blots = [point for point in range(24, 0, -1) if position.checkers[side][point] == 1]
        weights = {point: 0 for point in blots}
        total = 0
        rolls = []
        for first in range(6, 0, -1):
            for second in range(first, 0, -1):
                hit = set()
                for play in PlayGenerator(position, 1 - side, first, second).plays:
                    hit.update(p for p in blots if play.position.checkers[side][p] == 0)
                if not hit:
                    continue
                weight = 1 if first == second else 2
                total += weight
                rolls.append(f" {first}-{second}")
                for point in hit:
                    weights[point] += weight
        self.emit(f"shots {total}/36" + "".join(rolls))
        for point in blots:
            self.emit("blot", point, f"{weights[point]}/36")

    def cube(self, arguments):
        require(not arguments)
        self.require_in_play(False)
        self.emit("cube", cube_decision(self.state, False))

    def double(self, arguments):
        require(not arguments)
        self.require_in_play(False)
        state = self.state
        if state.owner == 1 - state.side or state.cube == MAX_CUBE:
            raise CommandError("cube unavailable")
        state.pending = True
        self.redo = []
        self.emit("OK", "double", 2 * state.cube)

    def take(self, arguments):
        require(not arguments)
        self.require_in_play()
        state = self.state
        if not state.pending:
            raise CommandError("no double")
        state.pending = False
        state.cube *= 2
        state.owner = 1 - state.side
        self.redo = []
        self.emit("OK", "take", state.cube, state.owner_name())

    def drop(self, arguments):
        require(not arguments)
        self.require_in_play()
        state = self.state
        if not state.pending:
            raise CommandError("no double")
        state.pending = False
        self.redo = []
        self.emit("OK", "drop")
        self.end_game(state.side, "drop", state.cube)

    def resign(self, arguments):
        require(len(arguments) == 1 and arguments[0] in MULTIPLIERS)
        self.require_in_play(False)
        kind = arguments[0]
        self.redo = []
        self.emit("OK", "resign")
        self.end_game(1 - self.state.side, kind, MULTIPLIERS[kind] * self.state.cube)

    def show_score(self, arguments):
        require(not arguments)
        score = self.state.score
        self.emit("score", "W", score[WHITE], "B", score[BLACK])

    def show_history(self, arguments):
        require(not arguments)
        self.emit("history", len(self.history))
        for number, entry in enumerate(self.history, 1):
            self.emit(number, entry.record)

    def undo(self, arguments):
        require(len(arguments) == 1)
        count = number_argument(arguments[0], 1, 1000)
        if count > len(self.history):
            raise CommandError("cannot undo")
        entries = self.history[-count:]
        del self.history[-count:]
        self.redo = entries + self.redo
        self.state = entries[0].before.copy()
        self.emit("OK")

    def redo_plays(self, arguments):
        require(len(arguments) == 1)
        count = number_argument(arguments[0], 1, 1000)
        if count > len(self.redo):
            raise CommandError("cannot redo")
        entries = self.redo[:count]
        del self.redo[:count]
        self.history.extend(entries)
        self.state = entries[-1].after.copy()
        self.emit("OK")

    def game(self, arguments):
        require(len(arguments) == 3)
        seed = number_argument(arguments[0], 1, MAX_SEED)
        require(arguments[1] in STRATEGIES and arguments[2] in STRATEGIES)
        self.require_in_play(False)
        record = play_game(self.state.copy(), arguments[1:], Dice(seed))
        for line in record.lines:
            self.emit(line)
        self.emit("result", COLORS[record.winner], record.result, record.points)

    def match(self, arguments):
        require(len(arguments) == 2)
        target = number_argument(arguments[0], 1, 15)
        dice = Dice(number_argument(arguments[1], 1, MAX_SEED))
        match = MatchScore(target)
        number = 0
        while max(match.points) < target:
            number += 1
            match.crawford = not match.crawford_played and max(match.points) == target - 1
            if match.crawford:
                match.crawford_played = True
            state, opening = opening_game(dice)
            first_player = state.side
            record = play_game(state, STRATEGIES[:1] * 2, dice, match, opening)
            match.points[record.winner] += record.points
            label = f"game {number} crawford" if match.crawford else f"game {number}"
            self.emit(
                label, "start", COLORS[first_player], "turns", record.plays,
                "result", COLORS[record.winner], record.result, record.points,
                "score", match.score_text(),
            )
        winner = WHITE if match.points[WHITE] >= target else BLACK
        self.emit("match", COLORS[winner], match.score_text())

    def stats(self, arguments):
        require(len(arguments) == 2)
        count = number_argument(arguments[0], 1, 50)
        dice = Dice(number_argument(arguments[1], 1, MAX_SEED))
        wins = {result: [0, 0] for result in RESULTS}
        points = [0, 0]
        turns = 0
        for _ in range(count):
            state, opening = opening_game(dice)
            record = play_game(state, STRATEGIES[:1] * 2, dice, None, opening)
            wins[record.result][record.winner] += 1
            points[record.winner] += record.points
            turns += record.plays
        for result in RESULTS:
            self.emit(result, "W", wins[result][WHITE], "B", wins[result][BLACK])
        self.emit("points", "W", points[WHITE], "B", points[BLACK])
        self.emit("turns", turns)

    def execute(self, line):
        name, *arguments = line.split(" ")
        if name not in self.handlers:
            self.emit("ERROR unknown command")
            return
        try:
            self.handlers[name](arguments)
        except CommandError as error:
            self.emit("ERROR", error)


def main():
    referee = Referee()
    count = int(sys.stdin.readline())
    for _ in range(count):
        referee.execute(sys.stdin.readline().rstrip("\n"))
    sys.stdout.write("\n".join(referee.output) + "\n")


if __name__ == "__main__":
    main()
