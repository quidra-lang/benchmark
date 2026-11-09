import sys


SIZE = 10
ROW_LETTERS = "ABCDEFGHIJ"
SHIP_NAMES = ("CARRIER", "BATTLESHIP", "CRUISER", "SUBMARINE", "DESTROYER")
SHIP_LENGTHS = (5, 4, 3, 3, 2)
SHIP_SYMBOLS = "CBRSD"
RULES = ("SALVO", "CHAIN", "TOUCH")
STRATEGIES = ("HUNT", "PROB", "RANDOM")
TOURNEY_PAIRS = (
    ("HUNT", "PROB"), ("HUNT", "RANDOM"), ("PROB", "HUNT"),
    ("PROB", "RANDOM"), ("RANDOM", "HUNT"), ("RANDOM", "PROB"),
)
DIRECTIONS = {"H": (0, 1), "V": (1, 0)}
NEIGHBOUR_STEPS = ((0, -1), (1, 0), (0, 1), (-1, 0))
MULTIPLIER = 48271
MODULUS = 2147483647
CELLS = tuple((row, col) for row in range(SIZE) for col in range(SIZE))
BOARD_HEADER = "  " + " ".join(str(col) for col in range(1, SIZE + 1))
DENSITY_HEADER = " " + "".join(f"{col:>5}" for col in range(1, SIZE + 1))


class CommandError(Exception):
    pass


def next_random(state):
    return MULTIPLIER * state % MODULUS


def cell_name(cell):
    row, col = cell
    return ROW_LETTERS[row] + str(col + 1)


def parse_cell(text):
    return ROW_LETTERS.index(text[0]), int(text[1:]) - 1


def inside(cell):
    row, col = cell
    return 0 <= row < SIZE and 0 <= col < SIZE


def surrounding(cell):
    row, col = cell
    cells = []
    for dr in (-1, 0, 1):
        for dc in (-1, 0, 1):
            neighbour = (row + dr, col + dc)
            if (dr, dc) != (0, 0) and inside(neighbour):
                cells.append(neighbour)
    return cells


def orthogonal(cell):
    row, col = cell
    neighbours = [(row + dr, col + dc) for dr, dc in NEIGHBOUR_STEPS]
    return [neighbour for neighbour in neighbours if inside(neighbour)]


def ship_cells(start, direction, length):
    row, col = start
    dr, dc = DIRECTIONS[direction]
    return [(row + dr * step, col + dc * step) for step in range(length)]


def ship_range(cells):
    return cell_name(cells[0]) + "-" + cell_name(cells[-1])


def adjacent(first, second):
    return max(abs(first[0] - second[0]), abs(first[1] - second[1])) == 1


def ships_touch(first, second):
    return any(adjacent(a, b) for a in first for b in second)


def is_straight(cells):
    row, col = cells[0]
    horizontal = all(cell == (row, col + step) for step, cell in enumerate(cells))
    vertical = all(cell == (row + step, col) for step, cell in enumerate(cells))
    return horizontal or vertical


def is_hit(result):
    return result.startswith("HIT") or result.startswith("SUNK")


def switch_text(value):
    return "ON" if value else "OFF"


class Player:
    def __init__(self, number):
        self.number = number
        self.ships = [None] * len(SHIP_NAMES)
        self.attacked = set()
        self.candidates = []
        self.random = number
        self.controller = "HUMAN"
        self.torpedo_used = False
        self.sonar_used = False
        self.shots = 0
        self.hits = 0
        self.sinks = 0
        self.turns = 0
        self.streak = 0
        self.longest_streak = 0
        self.wins = 0

    def advance_random(self):
        self.random = next_random(self.random)
        return self.random

    def ship_at(self, cell):
        for index, cells in enumerate(self.ships):
            if cells is not None and cell in cells:
                return index
        return None

    def attacked_count(self, index):
        return sum(cell in self.attacked for cell in self.ships[index])

    def is_sunk(self, index):
        cells = self.ships[index]
        return cells is not None and all(cell in self.attacked for cell in cells)

    def placed_count(self):
        return sum(cells is not None for cells in self.ships)

    def fully_placed(self):
        return self.placed_count() == len(SHIP_NAMES)

    def afloat_count(self):
        return sum(
            cells is not None and not self.is_sunk(index)
            for index, cells in enumerate(self.ships)
        )

    def defeated(self):
        return all(self.is_sunk(index) for index in range(len(SHIP_NAMES)))

    def record_shot(self, result):
        self.shots += 1
        if is_hit(result):
            self.hits += 1
            self.streak += 1
            self.longest_streak = max(self.longest_streak, self.streak)
        else:
            self.streak = 0
        if result.startswith("SUNK"):
            self.sinks += 1

    def accuracy(self):
        if self.shots == 0:
            return "-"
        return f"{self.hits * 100 // self.shots}%"


class View:
    def __init__(self, game, number):
        target = game.opponent(number)
        self.states = {}
        for cell in CELLS:
            if cell in game.reefs:
                self.states[cell] = "~"
            elif cell in target.attacked:
                self.states[cell] = "o"
            else:
                self.states[cell] = "."
        for index, cells in enumerate(target.ships):
            if cells is None:
                continue
            mark = "#" if target.is_sunk(index) else "x"
            for cell in cells:
                if cell in target.attacked:
                    self.states[cell] = mark
        self.excluded = set()
        if not game.rules["TOUCH"]:
            for cell in CELLS:
                if self.states[cell] == "#":
                    self.excluded.update(surrounding(cell))
        self.remaining = [
            index for index in range(len(SHIP_NAMES)) if not target.is_sunk(index)
        ]

    def state(self, cell):
        return self.states.get(cell)

    def is_candidate(self, cell):
        return self.state(cell) == "." and cell not in self.excluded

    def candidate_cells(self):
        return [cell for cell in CELLS if self.is_candidate(cell)]

    def hunt(self, stack):
        for row, col in CELLS:
            if self.states[(row, col)] != "x":
                continue
            for dr, dc in DIRECTIONS.values():
                front = (row + dr, col + dc)
                if self.state(front) != "x":
                    continue
                while self.state(front) == "x":
                    front = (front[0] + dr, front[1] + dc)
                back = (row - dr, col - dc)
                if self.is_candidate(front):
                    return front, "LINE"
                if self.is_candidate(back):
                    return back, "LINE"
        for cell in reversed(stack):
            if self.is_candidate(cell):
                return cell, "STACK"
        shortest = min(SHIP_LENGTHS[index] for index in self.remaining)
        for row, col in CELLS:
            if (row + col) % shortest == 0 and self.is_candidate((row, col)):
                return (row, col), "PARITY"
        return None

    def possible(self, cells):
        return all(
            self.state(cell) in (".", "x") and cell not in self.excluded
            for cell in cells
        )

    def scores(self):
        scores = dict.fromkeys(CELLS, 0)
        for index in self.remaining:
            for start in CELLS:
                for direction in DIRECTIONS:
                    cells = ship_cells(start, direction, SHIP_LENGTHS[index])
                    if not self.possible(cells):
                        continue
                    hits = sum(self.states[cell] == "x" for cell in cells)
                    for cell in cells:
                        scores[cell] += 1 + 10 * hits
        return scores

    def best(self, scores):
        best_cell = None
        for cell in CELLS:
            if self.states[cell] != ".":
                continue
            if best_cell is None or scores[cell] > scores[best_cell]:
                best_cell = cell
        return best_cell, scores[best_cell]


class Game:
    def __init__(self):
        self.phase = "SETUP"
        self.current = 1
        self.winner = None
        self.rules = dict.fromkeys(RULES, False)
        self.reefs = set()
        self.players = (Player(1), Player(2))
        self.sink_log = []

    def player(self, number):
        return self.players[number - 1]

    def opponent(self, number):
        return self.players[2 - number]

    def fleets_ready(self):
        return all(player.fully_placed() for player in self.players)

    def placement_problem(self, player, cells):
        if not all(inside(cell) for cell in cells):
            return "out of bounds"
        if any(cell in self.reefs for cell in cells):
            return "on reef"
        for index, placed in enumerate(player.ships):
            if placed is not None and any(cell in placed for cell in cells):
                return "overlaps " + SHIP_NAMES[index]
        if not self.rules["TOUCH"]:
            for index, placed in enumerate(player.ships):
                if placed is not None and ships_touch(placed, cells):
                    return "touches " + SHIP_NAMES[index]
        return None

    def auto_place(self, number, seed):
        player = self.player(number)
        player.random = seed
        player.ships = [None] * len(SHIP_NAMES)
        attempts = 0
        for index, length in enumerate(SHIP_LENGTHS):
            starts = SIZE + 1 - length
            while player.ships[index] is None:
                attempts += 1
                direction = "H" if player.advance_random() % 2 == 0 else "V"
                k = player.advance_random() % (SIZE * starts)
                if direction == "H":
                    start = divmod(k, starts)
                else:
                    start = divmod(k, SIZE)
                cells = ship_cells(start, direction, length)
                if self.placement_problem(player, cells) is None:
                    player.ships[index] = cells
        return attempts

    def shot_allowance(self, number):
        if self.rules["SALVO"]:
            return self.player(number).afloat_count()
        return 1

    def begin_battle(self):
        if self.phase == "SETUP":
            self.phase = "BATTLE"

    def shoot(self, number, cell):
        shooter = self.player(number)
        target = self.opponent(number)
        sunk_ship = None
        if cell in target.attacked:
            result = "ALREADY"
        else:
            target.attacked.add(cell)
            index = target.ship_at(cell)
            if index is None:
                result = "MISS"
            elif target.is_sunk(index):
                sunk_ship = SHIP_NAMES[index]
                result = "SUNK " + sunk_ship
            else:
                result = "HIT"
                shooter.candidates.extend(orthogonal(cell))
        shooter.record_shot(result)
        if sunk_ship is not None:
            self.sink_log.append((number, sunk_ship, shooter.shots))
        return result

    def choose_target(self, number, strategy, commit=True):
        view = View(self, number)
        player = self.player(number)
        if strategy == "HUNT":
            return view.hunt(player.candidates)
        if strategy == "PROB":
            return view.best(view.scores())
        cells = view.candidate_cells()
        value = next_random(player.random)
        if commit:
            player.random = value
        return cells[value % len(cells)], len(cells)

    def ai_turn(self, number, strategy):
        shots = []
        for _ in range(self.shot_allowance(number)):
            cell, _ = self.choose_target(number, strategy)
            shots.append((cell, self.shoot(number, cell)))
            if self.opponent(number).defeated():
                break
        return shots

    def torpedo(self, number, row, side):
        shooter = self.player(number)
        target = self.opponent(number)
        shooter.torpedo_used = True
        columns = range(SIZE) if side == "W" else range(SIZE - 1, -1, -1)
        result = "MISS"
        for col in columns:
            cell = (row, col)
            if cell in self.reefs:
                result = "REEF " + cell_name(cell)
                break
            if target.ship_at(cell) is not None:
                return self.shoot(number, cell) + " " + cell_name(cell)
            target.attacked.add(cell)
        shooter.record_shot(result)
        return result

    def sonar(self, number, cell):
        self.player(number).sonar_used = True
        target = self.opponent(number)
        area = [cell] + surrounding(cell)
        return sum(
            target.ship_at(spot) is not None and spot not in target.attacked
            for spot in area
        )

    def end_turn(self, number, results):
        player = self.player(number)
        player.turns += 1
        if self.opponent(number).defeated():
            self.phase = "OVER"
            self.winner = number
            player.wins += 1
            return True
        if self.rules["CHAIN"] and any(is_hit(result) for result in results):
            self.current = number
        else:
            self.current = 3 - number
        return False

    def resign(self, number):
        self.phase = "OVER"
        self.winner = 3 - number
        self.player(self.winner).wins += 1

    def board_symbol(self, player, cell):
        if cell in self.reefs:
            return "~"
        index = player.ship_at(cell)
        attacked = cell in player.attacked
        if index is None:
            return "o" if attacked else "."
        symbol = SHIP_SYMBOLS[index]
        return symbol.lower() if attacked else symbol


def play_match(base, seeds, strategies):
    game = Game()
    game.rules = dict(base.rules)
    game.reefs = set(base.reefs)
    for number, seed in zip((1, 2), seeds):
        game.auto_place(number, seed)
    game.phase = "BATTLE"
    game.current = 1
    while game.phase == "BATTLE":
        number = game.current
        shots = game.ai_turn(number, strategies[number - 1])
        game.end_turn(number, [result for _, result in shots])
    return game


def match_seeds(state):
    first = next_random(state)
    second = next_random(first)
    return first, second


class Referee:
    def __init__(self):
        self.game = Game()
        self.output = []

    def emit(self, *parts):
        self.output.append(" ".join(str(part) for part in parts))

    def setup_game(self):
        if self.game.phase != "SETUP":
            raise CommandError("setup closed")
        return self.game

    def active_game(self):
        if self.game.phase == "OVER":
            raise CommandError("game over")
        return self.game

    def turn_game(self, number):
        game = self.active_game()
        if game.phase == "SETUP" and not game.fleets_ready():
            raise CommandError("fleets not ready")
        if number != game.current:
            raise CommandError("not your turn")
        return game

    def emit_fleet(self, number, player):
        for name, cells in zip(SHIP_NAMES, player.ships):
            self.emit("PLACED", number, name, ship_range(cells))

    def emit_shots(self, number, shots):
        for cell, result in shots:
            self.emit("SHOT", number, cell_name(cell), result)

    def close_turn(self, number, results):
        if self.game.end_turn(number, results):
            self.emit("WINNER", number)
            return True
        return False

    def play_ai_turn(self, number, strategy):
        shots = self.game.ai_turn(number, strategy)
        self.emit_shots(number, shots)
        return self.close_turn(number, [result for _, result in shots])

    def auto_play(self):
        game = self.game
        while game.phase == "BATTLE":
            controller = game.player(game.current).controller
            if controller == "HUMAN":
                return
            self.play_ai_turn(game.current, controller)

    def finish_turn(self, number, results):
        if not self.close_turn(number, results):
            self.auto_play()

    def place(self, arguments):
        number, name, start, direction = arguments
        game = self.setup_game()
        player = game.player(int(number))
        index = SHIP_NAMES.index(name)
        if player.ships[index] is not None:
            raise CommandError(f"{name} already placed")
        cells = ship_cells(parse_cell(start), direction, SHIP_LENGTHS[index])
        problem = game.placement_problem(player, cells)
        if problem is not None:
            raise CommandError(problem)
        player.ships[index] = cells
        self.emit("PLACED", number, name, ship_range(cells))

    def remove(self, arguments):
        number, name = arguments
        game = self.setup_game()
        player = game.player(int(number))
        index = SHIP_NAMES.index(name)
        if player.ships[index] is None:
            raise CommandError(f"{name} not placed")
        player.ships[index] = None
        self.emit("REMOVED", number, name)

    def autoplace(self, arguments):
        number, seed = int(arguments[0]), int(arguments[1])
        game = self.setup_game()
        attempts = game.auto_place(number, seed)
        self.emit("AUTOPLACE", number, "attempts", attempts)
        self.emit_fleet(number, game.player(number))

    def layout(self, arguments):
        number, text = int(arguments[0]), arguments[1]
        game = self.setup_game()
        rows = text.split("/")
        fleet = []
        for name, length, symbol in zip(SHIP_NAMES, SHIP_LENGTHS, SHIP_SYMBOLS):
            cells = [(row, col) for row, col in CELLS if rows[row][col] == symbol]
            if len(cells) != length:
                raise CommandError(f"{name} has {len(cells)} cells")
            if not is_straight(cells):
                raise CommandError(f"{name} not straight")
            if any(cell in game.reefs for cell in cells):
                raise CommandError(f"{name} on reef")
            fleet.append(cells)
        if not game.rules["TOUCH"]:
            for first in range(len(fleet)):
                for second in range(first + 1, len(fleet)):
                    if ships_touch(fleet[first], fleet[second]):
                        raise CommandError(
                            f"{SHIP_NAMES[first]} touches {SHIP_NAMES[second]}"
                        )
        player = game.player(number)
        player.ships = fleet
        self.emit("LAYOUT", number)
        self.emit_fleet(number, player)

    def reef(self, arguments):
        text = arguments[0]
        game = self.setup_game()
        cell = parse_cell(text)
        if cell in game.reefs:
            raise CommandError(f"reef exists at {text}")
        for player in game.players:
            index = player.ship_at(cell)
            if index is not None:
                raise CommandError(
                    f"{text} occupied by {player.number} {SHIP_NAMES[index]}"
                )
        game.reefs.add(cell)
        self.emit("REEF", text)

    def set_rule(self, rule, arguments):
        switch = arguments[0]
        game = self.setup_game()
        game.rules[rule] = switch == "ON"
        self.emit(rule, switch)

    def fire(self, arguments):
        number = int(arguments[0])
        targets = arguments[1:]
        game = self.turn_game(number)
        allowance = game.shot_allowance(number)
        if len(targets) != allowance:
            raise CommandError(f"expected {allowance} shots")
        cells = [parse_cell(text) for text in targets]
        for text, cell in zip(targets, cells):
            if cell in game.reefs:
                raise CommandError(f"reef at {text}")
        game.begin_battle()
        shots = []
        for cell in cells:
            shots.append((cell, game.shoot(number, cell)))
            if game.opponent(number).defeated():
                break
        self.emit_shots(number, shots)
        self.finish_turn(number, [result for _, result in shots])

    def ai(self, arguments):
        number, strategy = int(arguments[0]), arguments[1]
        game = self.turn_game(number)
        game.begin_battle()
        if not self.play_ai_turn(number, strategy):
            self.auto_play()

    def torpedo(self, arguments):
        number, row, side = int(arguments[0]), arguments[1], arguments[2]
        game = self.turn_game(number)
        if game.player(number).torpedo_used:
            raise CommandError("torpedo used")
        game.begin_battle()
        result = game.torpedo(number, ROW_LETTERS.index(row), side)
        self.emit("TORPEDO", number, row, side, result)
        self.finish_turn(number, [result])

    def sonar(self, arguments):
        number, text = int(arguments[0]), arguments[1]
        game = self.turn_game(number)
        if game.player(number).sonar_used:
            raise CommandError("sonar used")
        game.begin_battle()
        count = game.sonar(number, parse_cell(text))
        self.emit("SONAR", number, text, count)
        self.finish_turn(number, [])

    def resign(self, arguments):
        number = int(arguments[0])
        game = self.game
        if game.phase != "BATTLE":
            raise CommandError("not in battle")
        game.resign(number)
        self.emit("RESIGN", number)
        self.emit("WINNER", game.winner)

    def new_game(self, arguments):
        wins = [player.wins for player in self.game.players]
        self.game = Game()
        for player, count in zip(self.game.players, wins):
            player.wins = count
        self.emit("NEW")

    def control(self, arguments):
        number, controller = int(arguments[0]), arguments[1]
        self.game.player(number).controller = controller
        self.emit("CONTROL", number, controller)

    def seed(self, arguments):
        number, seed = int(arguments[0]), int(arguments[1])
        self.game.player(number).random = seed
        self.emit("SEED", number, seed)

    def hint(self, arguments):
        number, strategy = int(arguments[0]), arguments[1]
        game = self.active_game()
        cell, info = game.choose_target(number, strategy, commit=False)
        self.emit("HINT", number, strategy, cell_name(cell), info)

    def density(self, arguments):
        number = int(arguments[0])
        game = self.active_game()
        view = View(game, number)
        scores = view.scores()
        self.emit("DENSITY", number)
        self.emit(DENSITY_HEADER)
        for row in range(SIZE):
            values = []
            for col in range(SIZE):
                state = view.state((row, col))
                if state == ".":
                    value = scores[(row, col)]
                elif state == "~":
                    value = "~"
                else:
                    value = "-"
                values.append(f"{value:>5}")
            self.emit(ROW_LETTERS[row] + "".join(values))
        cell, score = view.best(scores)
        self.emit("BEST", cell_name(cell), score)

    def emit_board(self, symbols):
        self.emit(BOARD_HEADER)
        for row in range(SIZE):
            self.emit(ROW_LETTERS[row], *(symbols[(row, col)] for col in range(SIZE)))

    def show(self, arguments):
        number = int(arguments[0])
        game = self.game
        player = game.player(number)
        self.emit("BOARD", number)
        self.emit_board({cell: game.board_symbol(player, cell) for cell in CELLS})

    def radar(self, arguments):
        number = int(arguments[0])
        self.emit("RADAR", number)
        self.emit_board(View(self.game, number).states)

    def export(self, arguments):
        number = int(arguments[0])
        player = self.game.player(number)
        rows = []
        for row in range(SIZE):
            symbols = []
            for col in range(SIZE):
                index = player.ship_at((row, col))
                symbols.append("." if index is None else SHIP_SYMBOLS[index])
            rows.append("".join(symbols))
        self.emit("EXPORT", number, "/".join(rows))

    def fleet(self, arguments):
        number = int(arguments[0])
        player = self.game.player(number)
        self.emit("FLEET", number, "afloat", player.afloat_count())
        for index, name in enumerate(SHIP_NAMES):
            cells = player.ships[index]
            if cells is None:
                self.emit(name, "unplaced")
                continue
            state = "SUNK" if player.is_sunk(index) else "AFLOAT"
            hits = f"{player.attacked_count(index)}/{len(cells)}"
            self.emit(name, ship_range(cells), hits, state)

    def status(self, arguments):
        game = self.game
        first, second = game.players
        parts = ["STATUS", game.phase]
        for rule in RULES:
            parts.extend((rule.lower(), switch_text(game.rules[rule])))
        parts.extend(("reefs", len(game.reefs)))
        if game.phase == "SETUP":
            parts.extend(("placed", first.placed_count(), second.placed_count()))
        else:
            if game.phase == "BATTLE":
                parts.extend((
                    "turn", game.current, "shots", game.shot_allowance(game.current),
                ))
            else:
                parts.extend(("winner", game.winner))
            parts.extend(("afloat", first.afloat_count(), second.afloat_count()))
        self.emit(*parts)

    def stats(self, arguments):
        for player in self.game.players:
            self.emit(
                "STATS", player.number, "shots", player.shots, "hits", player.hits,
                "sunk", player.sinks, "turns", player.turns,
                "streak", player.longest_streak, "accuracy", player.accuracy(),
                "wins", player.wins,
            )

    def match(self, arguments):
        seeds = int(arguments[0]), int(arguments[1])
        strategies = arguments[2], arguments[3]
        game = play_match(self.game, seeds, strategies)
        self.emit("MATCH", 1, strategies[0], 2, strategies[1])
        for number, ship, shots in game.sink_log:
            self.emit("SINK", number, ship, shots)
        first, second = game.players
        self.emit(
            "RESULT", "winner", game.winner, "shots", first.shots, second.shots,
            "hits", first.hits, second.hits,
        )

    def series(self, arguments):
        count, state = int(arguments[0]), int(arguments[1])
        strategies = arguments[2], arguments[3]
        wins = [0, 0]
        shots = [0, 0]
        fastest = [None, None]
        for _ in range(count):
            seeds = match_seeds(state)
            state = seeds[1]
            game = play_match(self.game, seeds, strategies)
            for side, player in enumerate(game.players):
                shots[side] += player.shots
            winner = game.winner - 1
            wins[winner] += 1
            winner_shots = game.players[winner].shots
            if fastest[winner] is None or winner_shots < fastest[winner]:
                fastest[winner] = winner_shots
        fastest_text = ["-" if value is None else value for value in fastest]
        self.emit(
            "SERIES", count, "wins", *wins, "shots", *shots, "fastest", *fastest_text
        )

    def tourney(self, arguments):
        count, state = int(arguments[0]), int(arguments[1])
        wins = dict.fromkeys(STRATEGIES, 0)
        shots = dict.fromkeys(STRATEGIES, 0)
        for pair in TOURNEY_PAIRS:
            for _ in range(count):
                seeds = match_seeds(state)
                state = seeds[1]
                game = play_match(self.game, seeds, pair)
                wins[pair[game.winner - 1]] += 1
                for strategy, player in zip(pair, game.players):
                    shots[strategy] += player.shots
        ranking = sorted(STRATEGIES, key=lambda name: (-wins[name], shots[name], name))
        self.emit("TOURNEY", count)
        for rank, strategy in enumerate(ranking, 1):
            self.emit(rank, strategy, "wins", wins[strategy], "shots", shots[strategy])

    def execute(self, line):
        command, *arguments = line.split()
        handlers = {
            "PLACE": self.place,
            "REMOVE": self.remove,
            "AUTOPLACE": self.autoplace,
            "LAYOUT": self.layout,
            "REEF": self.reef,
            "FIRE": self.fire,
            "AI": self.ai,
            "TORPEDO": self.torpedo,
            "SONAR": self.sonar,
            "RESIGN": self.resign,
            "NEW": self.new_game,
            "CONTROL": self.control,
            "SEED": self.seed,
            "HINT": self.hint,
            "DENSITY": self.density,
            "SHOW": self.show,
            "RADAR": self.radar,
            "EXPORT": self.export,
            "FLEET": self.fleet,
            "STATUS": self.status,
            "STATS": self.stats,
            "MATCH": self.match,
            "SERIES": self.series,
            "TOURNEY": self.tourney,
        }
        try:
            if command in RULES:
                self.set_rule(command, arguments)
            else:
                handlers[command](arguments)
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
