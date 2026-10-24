from collections import deque
from itertools import combinations_with_replacement
from math import factorial, gcd
import re
import sys


DICE = 5
FACE_VALUES = (1, 2, 3, 4, 5, 6)
CATEGORIES = (
    "ONES", "TWOS", "THREES", "FOURS", "FIVES", "SIXES", "THREEKIND",
    "FOURKIND", "FULLHOUSE", "SMALL", "LARGE", "YAHTZEE", "CHANCE",
)
UPPER_CATEGORIES = CATEGORIES[:6]
LOWER_CATEGORIES = CATEGORIES[6:]
JOKER_POINTS = {"FULLHOUSE": 25, "SMALL": 30, "LARGE": 40}
STRATEGIES = ("KIND", "STRAIGHT", "HIGH", "UPPER")
JOKER_MODES = ("FORCED", "FREE", "OFF")
MODULUS = 2147483647
MULTIPLIER = 48271
MAX_ROLLS = 4
MAX_PLAYERS = 6
MAX_AUTO_TURNS = 100
MAX_SIM_GAMES = 50
UPPER_TARGET = 63
UPPER_BONUS = 35
YAHTZEE_SCORE = 50
YAHTZEE_BONUS = 100
OUTCOMES_PER_ROLL = len(FACE_VALUES) ** DICE
HOLD_PATTERNS = tuple(
    tuple(mark == "1" for mark in format(number, "05b")) for number in range(2 ** DICE)
)
INTEGER_WORD = re.compile(r"-?(0|[1-9][0-9]*)")
NAME_WORD = re.compile(r"[A-Z]{1,8}")
PATTERN_WORD = re.compile(r"[01]{5}")


class CommandError(Exception):
    pass


def integer_word(text, minimum, maximum):
    if INTEGER_WORD.fullmatch(text) is None or text == "-0":
        raise CommandError(f"bad value {text}")
    value = int(text)
    if not minimum <= value <= maximum:
        raise CommandError(f"bad value {text}")
    return value


def player_name(text):
    if NAME_WORD.fullmatch(text) is None:
        raise CommandError(f"bad name {text}")
    return text


def hold_pattern(text):
    if PATTERN_WORD.fullmatch(text) is None:
        raise CommandError(f"bad pattern {text}")
    return [mark == "1" for mark in text]


def category_name(text):
    if text not in CATEGORIES:
        raise CommandError(f"bad category {text}")
    return text


def strategy_name(text):
    if text not in STRATEGIES:
        raise CommandError(f"bad strategy {text}")
    return text


def face_list(faces):
    return " ".join(str(face) for face in faces) if faces else "-"


def pattern_text(holds):
    return "".join("1" if hold else "0" for hold in holds)


def held_faces(faces, holds):
    return [face for face, hold in zip(faces, holds) if hold]


def fraction_text(numerator, denominator):
    divisor = gcd(numerator, denominator)
    numerator //= divisor
    denominator //= divisor
    return str(numerator) if denominator == 1 else f"{numerator}/{denominator}"


def average_text(total, count):
    value = 100 * total // count if count else 0
    return f"{value // 100}.{value % 100:02d}"


def is_yahtzee(faces):
    return faces.count(faces[0]) == DICE


def has_run(faces, start, length):
    return all(face in faces for face in range(start, start + length))


def normal_score(category, faces):
    if category in UPPER_CATEGORIES:
        face = UPPER_CATEGORIES.index(category) + 1
        return face * faces.count(face)
    counts = [faces.count(face) for face in FACE_VALUES]
    if category == "THREEKIND":
        return sum(faces) if max(counts) >= 3 else 0
    if category == "FOURKIND":
        return sum(faces) if max(counts) >= 4 else 0
    if category == "FULLHOUSE":
        return 25 if 3 in counts and 2 in counts else 0
    if category == "SMALL":
        return 30 if any(has_run(faces, start, 4) for start in (1, 2, 3)) else 0
    if category == "LARGE":
        return 40 if any(has_run(faces, start, 5) for start in (1, 2)) else 0
    if category == "YAHTZEE":
        return YAHTZEE_SCORE if max(counts) == DICE else 0
    return sum(faces)


def best_candidate(candidates):
    return max(candidates, key=lambda candidate: candidate[1])


def most_frequent_face(faces):
    return max(FACE_VALUES, key=lambda face: (faces.count(face), face))


def longest_run(faces):
    best_start, best_length = 0, 0
    for start in FACE_VALUES:
        length = 0
        while start + length in faces:
            length += 1
        if length > 0 and length >= best_length:
            best_start, best_length = start, length
    return best_start, best_length


def bot_holds(strategy, faces):
    if strategy == "HIGH":
        return [face >= 5 for face in faces]
    if strategy == "STRAIGHT":
        start, length = longest_run(faces)
        if length >= 3:
            holds = [False] * DICE
            for value in range(start, start + length):
                holds[faces.index(value)] = True
            return holds
    target = most_frequent_face(faces)
    return [face == target for face in faces]


def reroll_outcomes(count):
    outcomes = []
    for rolled in combinations_with_replacement(FACE_VALUES, count):
        weight = factorial(count)
        for face in FACE_VALUES:
            weight //= factorial(rolled.count(face))
        outcomes.append((rolled, weight))
    return outcomes


REROLLS = [reroll_outcomes(count) for count in range(DICE + 1)]


class Rules:
    def __init__(self):
        self.rolls = 3
        self.joker = "FORCED"


class DiceRoller:
    def __init__(self, seed):
        self.state = seed
        self.loaded = deque()
        self.counts = [0] * len(FACE_VALUES)

    def roll_die(self):
        if self.loaded:
            face = self.loaded.popleft()
        else:
            self.state = MULTIPLIER * self.state % MODULUS
            face = self.state % len(FACE_VALUES) + 1
        self.counts[face - 1] += 1
        return face


class Player:
    def __init__(self, name, strategy="KIND"):
        self.name = name
        self.strategy = strategy
        self.boxes = dict.fromkeys(CATEGORIES)
        self.yahtzee_bonus = 0

    def open_categories(self):
        return [category for category in CATEGORIES if self.boxes[category] is None]

    def used_count(self):
        return len(CATEGORIES) - len(self.open_categories())

    def round(self):
        return self.used_count() + 1

    def upper_subtotal(self):
        return sum(self.boxes[c] for c in UPPER_CATEGORIES if self.boxes[c] is not None)

    def upper_bonus(self):
        return UPPER_BONUS if self.upper_subtotal() >= UPPER_TARGET else 0

    def total(self):
        entered = sum(points for points in self.boxes.values() if points is not None)
        return entered + self.upper_bonus() + self.yahtzee_bonus


class Turn:
    def __init__(self, seat, rolls=0, faces=(), holds=(False,) * DICE):
        self.seat = seat
        self.rolls = rolls
        self.faces = list(faces)
        self.holds = list(holds)

    def copy(self):
        return Turn(self.seat, self.rolls, self.faces, self.holds)


class ScoreEntry:
    def __init__(self, player, category, points, bonus, joker, turn):
        self.player = player
        self.category = category
        self.points = points
        self.bonus = bonus
        self.joker = joker
        self.turn = turn.copy()


class Game:
    def __init__(self, players, rules, roller):
        self.players = players
        self.rules = rules
        self.roller = roller
        self.turn = Turn(0)
        self.entries = []
        self.redo_list = []

    def finished(self):
        return self.turn is None

    def current_player(self):
        return self.players[self.turn.seat]

    def ranking(self):
        return sorted(self.players, key=lambda player: -player.total())

    def roll(self):
        turn = self.turn
        if turn.rolls == 0:
            turn.faces = [self.roller.roll_die() for _ in range(DICE)]
        else:
            for index in range(DICE):
                if not turn.holds[index]:
                    turn.faces[index] = self.roller.roll_die()
        turn.rolls += 1
        self.redo_list.clear()
        return f"{self.current_player().name} roll {turn.rolls}: {face_list(turn.faces)}"

    def set_holds(self, holds):
        self.turn.holds = holds
        self.redo_list.clear()
        held = held_faces(self.turn.faces, holds)
        return f"{self.current_player().name} holds {pattern_text(holds)}: {face_list(held)}"

    def joker_situation(self, player, faces):
        return (
            self.rules.joker != "OFF" and is_yahtzee(faces)
            and player.boxes["YAHTZEE"] is not None
        )

    def allowed_categories(self, player, faces, joker):
        open_categories = player.open_categories()
        if not joker or self.rules.joker == "FREE":
            return open_categories
        upper = UPPER_CATEGORIES[faces[0] - 1]
        if player.boxes[upper] is None:
            return [upper]
        lower = [category for category in open_categories if category in LOWER_CATEGORIES]
        return lower if lower else open_categories

    def points_to_enter(self, faces, category, joker):
        if joker and category in JOKER_POINTS:
            return JOKER_POINTS[category]
        return normal_score(category, faces)

    def candidates(self, player, faces):
        joker = self.joker_situation(player, faces)
        allowed = self.allowed_categories(player, faces, joker)
        result = []
        for category in player.open_categories():
            score = self.points_to_enter(faces, category, joker) if category in allowed else 0
            result.append((category, score))
        return result

    def best(self, player, faces):
        return best_candidate(self.candidates(player, faces))

    def prepare_entry(self, category):
        player = self.current_player()
        faces = self.turn.faces
        if player.boxes[category] is not None:
            raise CommandError(f"{category} already used")
        joker = self.joker_situation(player, faces)
        if category not in self.allowed_categories(player, faces, joker):
            upper = UPPER_CATEGORIES[faces[0] - 1]
            if player.boxes[upper] is None:
                raise CommandError(f"joker requires {upper}")
            raise CommandError("joker requires lower box")
        points = self.points_to_enter(faces, category, joker)
        bonus = 0
        if is_yahtzee(faces) and player.boxes["YAHTZEE"] == YAHTZEE_SCORE:
            bonus = YAHTZEE_BONUS
        return ScoreEntry(player, category, points, bonus, joker, self.turn)

    def score_line(self, entry, verb):
        player = entry.player
        parts = [player.name, verb, entry.points, "in", entry.category]
        if entry.joker:
            parts.append("joker")
        if entry.bonus:
            parts.extend(("ybonus", entry.bonus))
        subtotal = player.upper_subtotal()
        if entry.category in UPPER_CATEGORIES:
            subtotal += entry.points
        gained = 0
        if player.upper_bonus() == 0 and subtotal >= UPPER_TARGET:
            gained = UPPER_BONUS
            parts.extend(("ubonus", gained))
        parts.extend(("total", player.total() + entry.points + entry.bonus + gained))
        return " ".join(str(part) for part in parts)

    def enter(self, entry):
        entry.player.boxes[entry.category] = entry.points
        entry.player.yahtzee_bonus += entry.bonus
        self.entries.append(entry)

    def score(self, category):
        entry = self.prepare_entry(category)
        line = self.score_line(entry, "scores")
        self.enter(entry)
        self.redo_list.clear()
        if all(player.used_count() == len(CATEGORIES) for player in self.players):
            self.turn = None
            return [line, "game over"]
        self.turn = Turn((self.turn.seat + 1) % len(self.players))
        player = self.current_player()
        return [line, f"turn {player.round()} {player.name}"]

    def undo(self):
        entry = self.entries.pop()
        entry.player.boxes[entry.category] = None
        entry.player.yahtzee_bonus -= entry.bonus
        self.redo_list.append((self.turn, entry))
        self.turn = entry.turn.copy()
        return entry

    def redo(self):
        turn, entry = self.redo_list.pop()
        self.enter(entry)
        self.turn = turn
        return entry

    def bot_category(self):
        player = self.current_player()
        faces = self.turn.faces
        if player.strategy == "UPPER":
            face = most_frequent_face(faces)
            category = UPPER_CATEGORIES[face - 1]
            allowed = self.allowed_categories(player, faces, self.joker_situation(player, faces))
            if faces.count(face) >= 3 and category in allowed:
                return category
        return self.best(player, faces)[0]

    def bot_turn(self):
        lines = []
        if self.turn.rolls == 0:
            lines.append(self.roll())
        while self.turn.rolls < self.rules.rolls:
            holds = bot_holds(self.current_player().strategy, self.turn.faces)
            if all(holds):
                break
            lines.append(self.set_holds(holds))
            lines.append(self.roll())
        lines.extend(self.score(self.bot_category()))
        return lines


class Advisor:
    def __init__(self, game, player):
        self.game = game
        self.player = player
        self.values = {}
        self.expectations = {}

    def value(self, hand, level):
        key = (hand, level)
        if key not in self.values:
            if level == 0:
                result = self.game.best(self.player, list(hand))[1]
            else:
                result = max(
                    self.expectation(tuple(held_faces(hand, holds)), level)
                    for holds in HOLD_PATTERNS
                )
            self.values[key] = result
        return self.values[key]

    def expectation(self, held, level):
        key = (held, level)
        if key not in self.expectations:
            total = 0
            for rolled, weight in REROLLS[DICE - len(held)]:
                total += weight * self.value(tuple(sorted(held + rolled)), level - 1)
            self.expectations[key] = total * len(FACE_VALUES) ** len(held)
        return self.expectations[key]

    def best_hold(self, faces, levels):
        best_holds, best_value = None, -1
        for holds in HOLD_PATTERNS:
            value = self.expectation(tuple(sorted(held_faces(faces, holds))), levels)
            if value > best_value:
                best_holds, best_value = holds, value
        return best_holds, best_value


class Record:
    def __init__(self):
        self.games = 0
        self.wins = 0
        self.best = 0
        self.total = 0

    def add(self, total, won):
        self.games += 1
        if won:
            self.wins += 1
        self.best = max(self.best, total)
        self.total += total


class SeatSummary:
    def __init__(self, strategy):
        self.strategy = strategy
        self.wins = 0
        self.total = 0
        self.best = 0
        self.bonus = 0
        self.yahtzee = 0

    def add(self, player, won):
        total = player.total()
        if won:
            self.wins += 1
        self.total += total
        self.best = max(self.best, total)
        if player.upper_bonus() == UPPER_BONUS:
            self.bonus += 1
        if player.boxes["YAHTZEE"] == YAHTZEE_SCORE:
            self.yahtzee += 1


class YahtzeeTable:
    def __init__(self):
        self.rules = Rules()
        self.game = None
        self.records = {}
        self.output = []
        self.handlers = {
            "RULE": self.set_rule,
            "GAME": self.start_game,
            "BOT": self.set_bot,
            "LOAD": self.load,
            "ROLL": self.roll,
            "HOLD": self.hold,
            "KEEP": self.keep,
            "SCORE": self.score,
            "WHATIF": self.what_if,
            "UNDO": self.undo,
            "REDO": self.redo,
            "SUGGEST": self.suggest,
            "ODDS": self.odds,
            "ADVISE": self.advise,
            "AUTO": self.auto,
            "STATUS": self.status,
            "CARD": self.card,
            "BONUS": self.bonus,
            "STATS": self.stats,
            "LOG": self.log,
            "FACES": self.faces,
            "STANDINGS": self.standings,
            "END": self.end,
            "RECORDS": self.show_records,
            "SIM": self.simulate,
        }

    def emit(self, line):
        self.output.append(line)

    def require_no_game(self):
        if self.game is not None:
            raise CommandError("game in progress")

    def require_game(self):
        if self.game is None:
            raise CommandError("no game")
        return self.game

    def require_turn(self):
        game = self.require_game()
        if game.finished():
            raise CommandError("game over")
        return game

    def require_rolled(self):
        game = self.require_turn()
        if game.turn.rolls == 0:
            raise CommandError("not rolled")
        return game

    def require_rolls_left(self):
        game = self.require_rolled()
        if game.turn.rolls == self.rules.rolls:
            raise CommandError("no rolls left")
        return game

    def set_rule(self, arguments):
        rule, value = arguments
        if rule == "ROLLS":
            rolls = integer_word(value, 1, MAX_ROLLS)
            self.require_no_game()
            self.rules.rolls = rolls
        elif rule == "JOKER":
            if value not in JOKER_MODES:
                raise CommandError(f"bad value {value}")
            self.require_no_game()
            self.rules.joker = value
        else:
            raise CommandError(f"unknown rule {rule}")
        self.emit(f"rule {rule} {value}")

    def start_game(self, arguments):
        seed = integer_word(arguments[0], 1, MODULUS - 1)
        names = [player_name(text) for text in arguments[1:]]
        if len(names) > MAX_PLAYERS:
            raise CommandError("too many players")
        self.require_no_game()
        for index, name in enumerate(names):
            if name in names[:index]:
                raise CommandError(f"duplicate name {name}")
        players = [Player(name) for name in names]
        self.game = Game(players, self.rules, DiceRoller(seed))
        self.emit(f"game seed {seed} players " + " ".join(names))
        self.emit(f"turn 1 {names[0]}")

    def set_bot(self, arguments):
        name = player_name(arguments[0])
        strategy = strategy_name(arguments[1])
        game = self.require_game()
        player = next((p for p in game.players if p.name == name), None)
        if player is None:
            raise CommandError(f"no player {name}")
        player.strategy = strategy
        self.emit(f"bot {name} {strategy}")

    def load(self, arguments):
        values = [integer_word(text, 1, len(FACE_VALUES)) for text in arguments]
        game = self.require_game()
        game.roller.loaded.extend(values)
        self.emit(f"loaded {len(game.roller.loaded)}")

    def roll(self, arguments):
        game = self.require_turn()
        if game.turn.rolls == self.rules.rolls:
            raise CommandError("no rolls left")
        if all(game.turn.holds):
            raise CommandError("all dice held")
        self.emit(game.roll())

    def hold(self, arguments):
        holds = hold_pattern(arguments[0])
        game = self.require_rolls_left()
        self.emit(game.set_holds(holds))

    def keep(self, arguments):
        values = [integer_word(text, 1, len(FACE_VALUES)) for text in arguments]
        game = self.require_rolls_left()
        faces = game.turn.faces
        holds = [False] * DICE
        for value in values:
            index = next(
                (i for i in range(DICE) if not holds[i] and faces[i] == value), None
            )
            if index is None:
                raise CommandError(f"not showing {value}")
            holds[index] = True
        self.emit(game.set_holds(holds))

    def score(self, arguments):
        category = category_name(arguments[0])
        game = self.require_rolled()
        self.output.extend(game.score(category))

    def what_if(self, arguments):
        category = category_name(arguments[0])
        game = self.require_rolled()
        entry = game.prepare_entry(category)
        self.emit(game.score_line(entry, "would score"))

    def undo(self, arguments):
        game = self.require_game()
        if not game.entries:
            raise CommandError("nothing to undo")
        entry = game.undo()
        self.emit(f"undo {entry.player.name} {entry.category} {entry.points}")

    def redo(self, arguments):
        game = self.require_game()
        if not game.redo_list:
            raise CommandError("nothing to redo")
        entry = game.redo()
        self.emit(f"redo {entry.player.name} {entry.category} {entry.points}")

    def suggest(self, arguments):
        game = self.require_rolled()
        candidates = game.candidates(game.current_player(), game.turn.faces)
        parts = ["suggest"]
        for category, score in candidates:
            parts.extend((category, str(score)))
        category, score = best_candidate(candidates)
        parts.extend(("best", category, str(score)))
        self.emit(" ".join(parts))

    def odds(self, arguments):
        holds = hold_pattern(arguments[0])
        game = self.require_rolls_left()
        player = game.current_player()
        held = held_faces(game.turn.faces, holds)
        open_categories = player.open_categories()
        expected = dict.fromkeys(open_categories, 0)
        chances = dict.fromkeys(open_categories, 0)
        best_total = 0
        for rolled, weight in REROLLS[DICE - len(held)]:
            candidates = game.candidates(player, held + list(rolled))
            for category, score in candidates:
                expected[category] += weight * score
                if score > 0:
                    chances[category] += weight
            best_total += weight * best_candidate(candidates)[1]
        outcomes = len(FACE_VALUES) ** (DICE - len(held))
        self.emit(f"odds {pattern_text(holds)} outcomes {outcomes}")
        for category in open_categories:
            self.emit(
                f"{category} expect {fraction_text(expected[category], outcomes)}"
                f" chance {fraction_text(chances[category], outcomes)}"
            )
        self.emit(f"best expect {fraction_text(best_total, outcomes)}")

    def advise(self, arguments):
        game = self.require_rolls_left()
        levels = self.rules.rolls - game.turn.rolls
        advisor = Advisor(game, game.current_player())
        faces = game.turn.faces
        holds, value = advisor.best_hold(faces, levels)
        expect = fraction_text(value, OUTCOMES_PER_ROLL ** levels)
        held = face_list(held_faces(faces, holds))
        self.emit(f"advise {pattern_text(holds)}: {held} expect {expect}")

    def auto(self, arguments):
        count = integer_word(arguments[0], 1, MAX_AUTO_TURNS)
        game = self.require_turn()
        for _ in range(count):
            self.output.extend(game.bot_turn())
            if game.finished():
                break

    def status(self, arguments):
        game = self.require_game()
        if game.finished():
            self.emit("status game over")
            return
        turn = game.turn
        player = game.current_player()
        self.emit(
            f"status round {player.round()} player {player.name} rolls {turn.rolls}"
            f" dice {face_list(turn.faces)} holds {pattern_text(turn.holds)}"
        )

    def card(self, arguments):
        players = self.require_game().players
        widths = [max(len(player.name), 4) for player in players]
        rows = [("CATEGORY", [player.name for player in players])]
        for category in CATEGORIES:
            cells = []
            for player in players:
                points = player.boxes[category]
                cells.append("-" if points is None else str(points))
            rows.append((category, cells))
        rows.append(("UPPER", [str(player.upper_subtotal()) for player in players]))
        rows.append(("BONUS", [str(player.upper_bonus()) for player in players]))
        rows.append(("YBONUS", [str(player.yahtzee_bonus) for player in players]))
        rows.append(("TOTAL", [str(player.total()) for player in players]))
        for heading, cells in rows:
            line = f"{heading:<9}"
            for cell, width in zip(cells, widths):
                line += f" {cell:>{width}}"
            self.emit(line)

    def bonus(self, arguments):
        game = self.require_game()
        for player in game.players:
            subtotal = player.upper_subtotal()
            need = max(UPPER_TARGET - subtotal, 0)
            maximum = subtotal
            for face, category in zip(FACE_VALUES, UPPER_CATEGORIES):
                if player.boxes[category] is None:
                    maximum += DICE * face
            if subtotal >= UPPER_TARGET:
                state = "made"
            elif maximum < UPPER_TARGET:
                state = "lost"
            else:
                state = "open"
            self.emit(f"bonus {player.name} upper {subtotal} need {need} max {maximum} {state}")

    def stats(self, arguments):
        game = self.require_game()
        for player in game.players:
            entries = [entry for entry in game.entries if entry.player is player]
            rolls = sum(entry.turn.rolls for entry in entries)
            zeros = sum(entry.points == 0 for entry in entries)
            yahtzees = sum(is_yahtzee(entry.turn.faces) for entry in entries)
            average = average_text(sum(entry.points for entry in entries), len(entries))
            self.emit(
                f"stats {player.name} turns {len(entries)} rolls {rolls} zeros {zeros}"
                f" yahtzees {yahtzees} average {average}"
            )

    def log(self, arguments):
        game = self.require_game()
        if not game.entries:
            self.emit("no scores")
        for number, entry in enumerate(game.entries, 1):
            parts = [
                "log", str(number), entry.player.name, face_list(entry.turn.faces),
                entry.category, str(entry.points),
            ]
            if entry.joker:
                parts.append("joker")
            if entry.bonus:
                parts.extend(("ybonus", str(entry.bonus)))
            self.emit(" ".join(parts))

    def faces(self, arguments):
        counts = self.require_game().roller.counts
        rolled = sum(counts)
        if rolled:
            squares = sum(count * count for count in counts)
            chi2 = fraction_text(len(FACE_VALUES) * squares - rolled * rolled, rolled)
        else:
            chi2 = "0"
        counted = " ".join(str(count) for count in counts)
        self.emit(f"faces {counted} total {rolled} chi2 {chi2}")

    def standings(self, arguments):
        ranking = self.require_game().ranking()
        leader = ranking[0].total()
        for rank, player in enumerate(ranking, 1):
            total = player.total()
            self.emit(f"standing {rank} {player.name} {total} behind {leader - total}")

    def end(self, arguments):
        game = self.require_game()
        finished = game.finished()
        self.emit("end final" if finished else "end abandoned")
        for rank, player in enumerate(game.ranking(), 1):
            self.emit(f"rank {rank} {player.name} {player.total()}")
            if finished:
                self.records.setdefault(player.name, Record()).add(player.total(), rank == 1)
        self.game = None

    def show_records(self, arguments):
        if not self.records:
            self.emit("no records")
        ordered = sorted(
            self.records.items(),
            key=lambda item: (-item[1].wins, -item[1].best, item[0]),
        )
        for name, record in ordered:
            self.emit(
                f"record {name} games {record.games} wins {record.wins} best {record.best}"
                f" average {average_text(record.total, record.games)}"
            )

    def simulate(self, arguments):
        seed = integer_word(arguments[0], 1, MODULUS - 1)
        count = integer_word(arguments[1], 1, MAX_SIM_GAMES)
        strategies = [strategy_name(text) for text in arguments[2:]]
        if len(strategies) > MAX_PLAYERS:
            raise CommandError("too many players")
        roller = DiceRoller(seed)
        summaries = [SeatSummary(strategy) for strategy in strategies]
        for _ in range(count):
            players = [Player(str(seat), strategy) for seat, strategy in enumerate(strategies, 1)]
            game = Game(players, self.rules, roller)
            while not game.finished():
                game.bot_turn()
            winner = game.ranking()[0]
            for player, summary in zip(players, summaries):
                summary.add(player, player is winner)
        self.emit(f"sim seed {seed} games {count} players {len(strategies)}")
        for seat, summary in enumerate(summaries, 1):
            self.emit(
                f"seat {seat} {summary.strategy} wins {summary.wins}"
                f" average {average_text(summary.total, count)} best {summary.best}"
                f" bonus {summary.bonus} yahtzee {summary.yahtzee}"
            )

    def execute(self, line):
        command, *arguments = line.split()
        try:
            if command not in self.handlers:
                raise CommandError(f"unknown command {command}")
            self.handlers[command](arguments)
        except CommandError as error:
            self.emit(f"error: {error}")


def main():
    table = YahtzeeTable()
    count = int(sys.stdin.readline())
    for _ in range(count):
        table.execute(sys.stdin.readline().rstrip("\n"))
    sys.stdout.write("\n".join(table.output) + "\n")


if __name__ == "__main__":
    main()
