import sys
from copy import deepcopy
from functools import cache
from itertools import product


class Invalid(Exception):
    pass


DARTS = {}
for number in range(1, 21):
    DARTS[f"S{number}"] = (number, False)
    DARTS[f"D{number}"] = (2 * number, True)
    DARTS[f"T{number}"] = (3 * number, False)
DARTS["25"] = (25, False)
DARTS["BULL"] = (50, True)
DARTS["MISS"] = (0, False)
CANDIDATES_A = [
    f"{prefix}{number}"
    for prefix in ("S", "T", "D")
    for number in range(20, 0, -1)
] + ["25", "BULL"]
CANDIDATES_B = [f"D{number}" for number in range(20, 0, -1)] + ["BULL"]


@cache
def checkout(score, maximum=3):
    for count in range(1, maximum + 1):
        for prefix in product(CANDIDATES_A, repeat=count - 1):
            wanted = score - sum(DARTS[dart][0] for dart in prefix)
            for last in CANDIDATES_B:
                if DARTS[last][0] == wanted:
                    return prefix + (last,)
    return None


def pair(values, reverse=False):
    if reverse:
        values = values[::-1]
    return "-".join(map(str, values))


CHOICES = {
    "TENNIS": {
        "SETS": ("3", "5"),
        "DEUCE": ("AD", "NOAD"),
        "FINAL": ("TB7", "TB10", "ADV", "SUPER"),
        "FIRST": ("A", "B"),
    },
    "TABLETENNIS": {"GAMES": ("5", "7"), "FIRST": ("A", "B")},
    "BADMINTON": {"FIRST": ("A", "B")},
    "VOLLEYBALL": {"FIRST": ("A", "B")},
    "DARTS": {
        "START": ("301", "501", "701"),
        "SETS": ("1", "2", "3", "4", "5"),
        "LEGS": ("1", "2", "3", "4", "5"),
        "FIRST": ("A", "B"),
    },
    "BOWLING": {},
}
DEFAULTS = {
    "TENNIS": {"SETS": "3", "DEUCE": "AD", "FINAL": "TB7", "FIRST": "A"},
    "TABLETENNIS": {"GAMES": "5", "FIRST": "A"},
    "BADMINTON": {"FIRST": "A"},
    "VOLLEYBALL": {"FIRST": "A"},
    "DARTS": {"START": "501", "SETS": "1", "LEGS": "1", "FIRST": "A"},
    "BOWLING": {},
}


class Game:
    def __init__(self, args):
        self.id, self.sport = args[:2]
        if self.sport == "BOWLING":
            self.names = [args[2]]
            option_start = 3
        else:
            self.names = args[2:4]
            option_start = 4
        self.lineups = [[], []]
        if self.sport == "VOLLEYBALL":
            self.lineups = [
                [int(number) for number in lineup.split(",")]
                for lineup in args[4:6]
            ]
            option_start = 6
        self.options = DEFAULTS[self.sport].copy()
        seen = set()
        for option in args[option_start:]:
            parts = option.split("=")
            if (
                len(parts) != 2 or parts[0] not in CHOICES[self.sport]
                or parts[1] not in CHOICES[self.sport][parts[0]]
                or parts[0] in seen
            ):
                raise Invalid("invalid option")
            seen.add(parts[0])
            self.options[parts[0]] = parts[1]
        self.first = int(self.options.get("FIRST", "A") == "B")
        self.state = self.new_state()
        self.initial_state = deepcopy(self.state)
        self.history = []

    def new_state(self):
        start = int(self.options.get("START", "501"))
        return {
            "done": False,
            "winner": -1,
            "sets": [0, 0],
            "legs": [0, 0],
            "points": [0, 0],
            "games": [0, 0],
            "finished": [],
            "game_server": self.first,
            "server": self.first,
            "lineups": [lineup.copy() for lineup in self.lineups],
            "subs": [0, 0],
            "timeouts": [0, 0],
            "rally": [
                {
                    "points": 0, "served": 0, "serve_won": 0,
                    "run": 0, "current": 0, "holds": 0, "service_games": 0,
                    "breaks": 0, "opportunities": 0, "conversions": 0,
                }
                for _ in range(2)
            ],
            "frames": [[] for _ in range(10)],
            "marks": [[] for _ in range(10)],
            "frame": 0,
            "standing": 10,
            "remaining": [start, start],
            "player": self.first,
            "leg_number": 0,
            "turn": [],
            "turn_start": start,
            "turn_score": 0,
            "darts": [
                {
                    "darts": 0, "points": 0, "busts": 0, "high": 0,
                    "tons": 0, "maximums": 0, "attempts": 0, "hits": 0,
                }
                for _ in range(2)
            ],
        }

    def rally_sport(self):
        return self.sport in ("TENNIS", "TABLETENNIS", "BADMINTON", "VOLLEYBALL")

    def final_set(self, state):
        target = int(self.options["SETS"]) // 2
        return state["sets"] == [target, target]

    def tennis_kind(self, state):
        if self.final_set(state) and self.options["FINAL"] == "SUPER":
            return "super"
        advantage = self.final_set(state) and self.options["FINAL"] == "ADV"
        if state["games"] == [6, 6] and not advantage:
            return "tie"
        return "normal"

    def server(self, state):
        if self.sport == "TENNIS":
            if self.tennis_kind(state) == "normal":
                return state["game_server"]
            point_number = sum(state["points"]) + 1
            return state["game_server"] ^ (point_number // 2 % 2)
        if self.sport == "TABLETENNIS":
            first = self.first ^ (len(state["finished"]) % 2)
            played = sum(state["points"])
            alternation = played // 2 % 2 if played < 20 else played % 2
            return first ^ alternation
        return state["server"]

    def normal_game_wins(self, points, winner):
        return points[winner] >= 4 and (
            self.options["DEUCE"] == "NOAD"
            or points[winner] - points[1 - winner] >= 2
        )

    def finish_rally_unit(self, state, winner, record, target):
        state["finished"].append(record)
        state["sets"][winner] += 1
        if state["sets"][winner] == target:
            state["done"] = True
            state["winner"] = winner
            return
        state["points"] = [0, 0]
        state["games"] = [0, 0]
        if self.sport == "VOLLEYBALL":
            state["lineups"] = [lineup.copy() for lineup in self.lineups]
            state["subs"] = [0, 0]
            state["timeouts"] = [0, 0]
            state["server"] = self.first ^ (len(state["finished"]) % 2)

    def tennis_point(self, state, winner, server):
        kind = self.tennis_kind(state)
        if kind == "normal":
            receiver = 1 - server
            hypothetical = state["points"].copy()
            hypothetical[receiver] += 1
            if self.normal_game_wins(hypothetical, receiver):
                state["rally"][receiver]["opportunities"] += 1
                if winner == receiver:
                    state["rally"][receiver]["conversions"] += 1
        state["points"][winner] += 1
        needed = int(self.options["SETS"]) // 2 + 1
        if kind == "normal":
            if not self.normal_game_wins(state["points"], winner):
                return
            state["rally"][server]["service_games"] += 1
            if winner == server:
                state["rally"][server]["holds"] += 1
            else:
                state["rally"][winner]["breaks"] += 1
            state["games"][winner] += 1
            state["points"] = [0, 0]
            state["game_server"] ^= 1
            if (
                state["games"][winner] >= 6
                and state["games"][winner] - state["games"][1 - winner] >= 2
            ):
                record = {
                    "values": state["games"].copy(), "tie": -1, "super": False
                }
                self.finish_rally_unit(state, winner, record, needed)
            return
        ten_point = kind == "super" or (
            self.final_set(state) and self.options["FINAL"] == "TB10"
        )
        target = 10 if ten_point else 7
        if (
            state["points"][winner] < target
            or state["points"][winner] - state["points"][1 - winner] < 2
        ):
            return
        if kind == "super":
            record = {
                "values": state["points"].copy(), "tie": -1, "super": True
            }
        else:
            values = state["games"].copy()
            values[winner] += 1
            record = {
                "values": values,
                "tie": state["points"][1 - winner],
                "super": False,
            }
        state["game_server"] ^= 1
        self.finish_rally_unit(state, winner, record, needed)

    def point(self, state, winner):
        serving = self.server(state)
        stats = state["rally"]
        stats[winner]["points"] += 1
        stats[serving]["served"] += 1
        if winner == serving:
            stats[serving]["serve_won"] += 1
        stats[winner]["current"] += 1
        stats[winner]["run"] = max(
            stats[winner]["run"], stats[winner]["current"]
        )
        stats[1 - winner]["current"] = 0
        if self.sport == "TENNIS":
            self.tennis_point(state, winner, serving)
            return
        state["points"][winner] += 1
        if self.sport == "BADMINTON":
            state["server"] = winner
        elif self.sport == "VOLLEYBALL" and winner != state["server"]:
            state["server"] = winner
            lineup = state["lineups"][winner]
            lineup.append(lineup.pop(0))
        if self.sport == "TABLETENNIS":
            target = 11
            needed = int(self.options["GAMES"]) // 2 + 1
        elif self.sport == "BADMINTON":
            target = 21
            needed = 2
        else:
            target = 15 if len(state["finished"]) == 4 else 25
            needed = 3
        won = (
            state["points"][winner] >= target
            and state["points"][winner] - state["points"][1 - winner] >= 2
        ) or (self.sport == "BADMINTON" and state["points"][winner] == 30)
        if won:
            record = {
                "values": state["points"].copy(), "tie": -1, "super": False
            }
            self.finish_rally_unit(state, winner, record, needed)

    def standing(self, state):
        if state["frame"] == 9 and state["standing"] == 0:
            return 10
        return state["standing"]

    def roll(self, state, pins):
        standing = self.standing(state)
        if pins > standing:
            raise Invalid("too many pins")
        frame = state["frames"][state["frame"]]
        fresh_rack = not frame or state["frame"] == 9 and state["standing"] == 0
        if fresh_rack and pins == 10:
            mark = "X"
        elif pins == standing:
            mark = "/"
        elif pins == 0:
            mark = "-"
        else:
            mark = str(pins)
        frame.append(pins)
        state["marks"][state["frame"]].append(mark)
        state["standing"] = standing - pins
        if state["frame"] < 9:
            if frame == [10] or len(frame) == 2:
                state["frame"] += 1
                state["standing"] = 10
        elif len(frame) == 3 or (
            len(frame) == 2 and frame[0] != 10 and sum(frame) < 10
        ):
            state["done"] = True

    def frame_scores(self, state):
        scores = []
        for i, frame in enumerate(state["frames"]):
            value = None
            if i == 9:
                if state["done"]:
                    value = sum(frame)
            else:
                later = [
                    pins for following in state["frames"][i + 1:]
                    for pins in following
                ]
                if frame and frame[0] == 10:
                    if len(later) >= 2:
                        value = 10 + later[0] + later[1]
                elif len(frame) == 2:
                    if sum(frame) < 10:
                        value = sum(frame)
                    elif later:
                        value = 10 + later[0]
            scores.append(value)
        return scores

    def maximum(self, state):
        hypothetical = deepcopy(state)
        while not hypothetical["done"]:
            self.roll(hypothetical, self.standing(hypothetical))
        return sum(self.frame_scores(hypothetical))

    def completed_turn(self, state, player):
        stats = state["darts"][player]
        stats["high"] = max(stats["high"], state["turn_score"])
        if state["turn_score"] >= 100:
            stats["tons"] += 1
        if state["turn_score"] == 180:
            stats["maximums"] += 1

    def next_turn(self, state):
        state["player"] = 1 - state["player"]
        state["turn"] = []
        state["turn_score"] = 0
        state["turn_start"] = state["remaining"][state["player"]]

    def win_leg(self, state, player):
        state["legs"][player] += 1
        if state["legs"][player] == int(self.options["LEGS"]):
            state["sets"][player] += 1
            state["finished"].append({
                "values": state["legs"].copy(), "tie": -1, "super": False
            })
            if state["sets"][player] == int(self.options["SETS"]):
                state["done"] = True
                state["winner"] = player
                return
            state["legs"] = [0, 0]
        state["leg_number"] += 1
        start = int(self.options["START"])
        state["remaining"] = [start, start]
        state["player"] = self.first ^ (state["leg_number"] % 2)
        state["turn"] = []
        state["turn_score"] = 0
        state["turn_start"] = start

    def throw_dart(self, state, notation):
        if notation not in DARTS:
            raise Invalid("invalid dart")
        value, double = DARTS[notation]
        player = state["player"]
        stats = state["darts"][player]
        before = state["remaining"][player]
        stats["darts"] += 1
        if before == 50 or before <= 40 and before % 2 == 0:
            stats["attempts"] += 1
        state["turn"].append(notation)
        state["turn_score"] += value
        stats["points"] += value
        remaining = before - value
        if remaining < 0 or remaining == 1 or remaining == 0 and not double:
            stats["busts"] += 1
            stats["points"] -= state["turn_score"]
            state["remaining"][player] = state["turn_start"]
            self.next_turn(state)
            return
        state["remaining"][player] = remaining
        if remaining == 0:
            stats["hits"] += 1
            self.completed_turn(state, player)
            self.win_leg(state, player)
        elif len(state["turn"]) == 3:
            self.completed_turn(state, player)
            self.next_turn(state)

    def apply(self, name, args):
        if name == "POINT":
            self.point(self.state, int(args[0] == "B"))
        elif name == "ROLL":
            self.roll(self.state, int(args[0]))
        elif name == "THROW":
            self.throw_dart(self.state, args[0])
        else:
            side = int(args[0] == "B")
            if name == "SUB":
                lineup = self.state["lineups"][side]
                outgoing, incoming = map(int, args[1:])
                if outgoing not in lineup:
                    raise Invalid("player not on court")
                if incoming in lineup:
                    raise Invalid("player already on court")
                if self.state["subs"][side] >= 6:
                    raise Invalid("no substitutions left")
                lineup[lineup.index(outgoing)] = incoming
                self.state["subs"][side] += 1
            else:
                if self.state["timeouts"][side] >= 2:
                    raise Invalid("no timeouts left")
                self.state["timeouts"][side] += 1

    def event(self, name, args):
        if name == "POINT":
            allowed = self.rally_sport()
            events = [(side,) for side in args[0]]
        elif name == "ROLL":
            allowed = self.sport == "BOWLING"
            events = [(pins,) for pins in args]
        elif name == "THROW":
            allowed = self.sport == "DARTS"
            events = [(dart,) for dart in args]
        else:
            allowed = self.sport == "VOLLEYBALL"
            events = [tuple(args)]
        if not allowed:
            raise Invalid("wrong event")
        for values in events:
            if self.state["done"]:
                raise Invalid("match over")
            self.apply(name, values)
            self.history.append((name, values))

    def undo(self):
        if not self.history:
            raise Invalid("nothing to undo")
        self.history.pop()
        self.state = deepcopy(self.initial_state)
        for name, args in self.history:
            self.apply(name, args)

    def score_record(self, record, reverse=False):
        display = pair(record["values"], reverse)
        if record["super"]:
            return "[" + display + "]"
        if record["tie"] >= 0:
            display += f"({record['tie']})"
        return display

    def situation(self, side):
        state = self.state
        hypothetical = deepcopy(state)
        serving = self.server(state)
        normal = self.sport == "TENNIS" and self.tennis_kind(state) == "normal"
        self.point(hypothetical, side)
        if hypothetical["done"]:
            return "match point"
        if len(hypothetical["finished"]) > len(state["finished"]):
            if self.sport in ("TENNIS", "VOLLEYBALL"):
                return "set point"
            return "game point"
        if normal and hypothetical["game_server"] != state["game_server"]:
            return "game point" if side == serving else "break point"
        return None

    def bowling_score(self):
        state = self.state
        scores = self.frame_scores(state)
        total = 0
        items = []
        for i, frame in enumerate(state["frames"]):
            if not frame:
                break
            display = "".join(state["marks"][i])
            if scores[i] is not None:
                total += scores[i]
                display += f"({total})"
            items.append(display)
        suffix = " " + " ".join(items) if items else ""
        return f"{self.id}: {self.names[0]}{suffix}"

    def tennis_current(self):
        state = self.state
        kind = self.tennis_kind(state)
        if kind == "super":
            return ["[" + pair(state["points"]) + "]"]
        items = [pair(state["games"])]
        if kind == "tie":
            items.append(pair(state["points"]))
        elif self.options["DEUCE"] == "AD" and min(state["points"]) >= 3:
            a, b = state["points"]
            if a == b:
                items.append("40-40")
            elif a > b:
                items.append("AD-40")
            else:
                items.append("40-AD")
        else:
            display = ("0", "15", "30", "40")
            items.append("-".join(display[value] for value in state["points"]))
        return items

    def score(self):
        state = self.state
        if self.sport == "BOWLING":
            return self.bowling_score()
        serving = state["player"] if self.sport == "DARTS" else self.server(state)
        names = [
            name + ("*" if not state["done"] and i == serving else "")
            for i, name in enumerate(self.names)
        ]
        items = [self.score_record(record) for record in state["finished"]]
        if self.sport == "DARTS":
            items = [
                "sets", pair(state["sets"]), "legs", pair(state["legs"]),
                "score", pair(state["remaining"]),
            ]
            if not state["done"]:
                if state["turn"]:
                    items.extend(["turn", *state["turn"]])
                finish = checkout(
                    state["remaining"][state["player"]], 3 - len(state["turn"])
                )
                if finish:
                    items.extend(["checkout", *finish])
        elif not state["done"]:
            if self.sport == "TENNIS":
                items.extend(self.tennis_current())
            else:
                items.append(pair(state["points"]))
                if self.sport == "VOLLEYBALL":
                    number = state["lineups"][state["server"]][0]
                    items.extend(["server", str(number)])
            for side in range(2):
                status = self.situation(side)
                if status:
                    items.append(f"({status} {self.names[side]})")
        return f"{self.id}: {names[0]} vs {names[1]} " + " ".join(items)

    def stats(self):
        state = self.state
        if self.sport == "BOWLING":
            marks = [mark for frame in state["marks"] for mark in frame]
            open_frames = sum(
                len(frame) >= 2 and frame[0] != 10 and sum(frame[:2]) < 10
                for frame in state["frames"]
            )
            return [
                f"{self.id} {self.names[0]}: strikes {marks.count('X')}"
                f" spares {marks.count('/')} open {open_frames}"
                f" max {self.maximum(state)}"
            ]
        output = []
        for i, name in enumerate(self.names):
            line = f"{self.id} {name}: "
            if self.sport == "DARTS":
                stats = state["darts"][i]
                average = (
                    stats["points"] * 300 // stats["darts"]
                    if stats["darts"] else 0
                )
                line += (
                    f"darts {stats['darts']}"
                    f" average {average // 100}.{average % 100:02d}"
                    f" busts {stats['busts']} high {stats['high']}"
                    f" tons {stats['tons']} 180s {stats['maximums']}"
                    f" doubles {stats['hits']}/{stats['attempts']}"
                )
            else:
                stats = state["rally"][i]
                line += (
                    f"points {stats['points']}"
                    f" serve {stats['serve_won']}/{stats['served']}"
                    f" run {stats['run']}"
                )
                if self.sport == "TENNIS":
                    line += (
                        f" holds {stats['holds']}/{stats['service_games']}"
                        f" breaks {stats['breaks']}"
                        f" break points {stats['conversions']}/{stats['opportunities']}"
                    )
                elif self.sport == "VOLLEYBALL":
                    lineup = ",".join(map(str, state["lineups"][i]))
                    line += (
                        f" subs {state['subs'][i]} timeouts {state['timeouts'][i]}"
                        f" lineup {lineup}"
                    )
            output.append(line)
        return output

    def result(self):
        state = self.state
        if not state["done"]:
            raise Invalid("match not finished")
        if self.sport == "BOWLING":
            total = sum(self.frame_scores(state))
            return f"{self.id}: {self.names[0]} {total}"
        winner = state["winner"]
        scores = " ".join(
            self.score_record(record, reverse=winner == 1)
            for record in state["finished"]
        )
        return (
            f"{self.id}: {self.names[winner]} def. {self.names[1 - winner]}"
            f" {scores}"
        )


class Scoreboard:
    def __init__(self):
        self.matches = {}

    def standings(self):
        totals = {}
        for match in self.matches.values():
            if not match.state["done"] or match.sport == "BOWLING":
                continue
            for side, name in enumerate(match.names):
                totals.setdefault(name, [0, 0])
                index = 0 if side == match.state["winner"] else 1
                totals[name][index] += 1
        names = sorted(
            totals, key=lambda name: (-totals[name][0], totals[name][1], name)
        )
        display = ", ".join(
            f"{name} {pair(totals[name])}" for name in names
        )
        return "standings: " + (display or "none")

    def command(self, line):
        name, *args = line.split()
        if name == "MATCH":
            if args[0] in self.matches:
                raise Invalid("duplicate match")
            match = Game(args)
            self.matches[match.id] = match
            return []
        if name == "CHECKOUT":
            answer = checkout(int(args[0]))
            display = " ".join(answer) if answer else "none"
            return [f"checkout {args[0]}: {display}"]
        if name == "STANDINGS":
            return [self.standings()]
        if args[0] not in self.matches:
            raise Invalid("unknown match")
        match = self.matches[args[0]]
        if name == "UNDO":
            match.undo()
            return []
        if name == "SCORE":
            return [match.score()]
        if name == "STATS":
            return match.stats()
        if name == "RESULT":
            return [match.result()]
        match.event(name, args[1:])
        return []


def main():
    lines = sys.stdin.read().splitlines()
    scoreboard = Scoreboard()
    output = []
    for line in lines[1:int(lines[0]) + 1]:
        try:
            output.extend(scoreboard.command(line))
        except Invalid as error:
            output.append("ERROR " + str(error))
    if output:
        sys.stdout.write("\n".join(output) + "\n")


if __name__ == "__main__":
    main()
