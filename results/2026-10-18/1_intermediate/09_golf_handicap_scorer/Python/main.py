import sys
from fractions import Fraction


class CommandError(Exception):
    pass


def round_half_up(numerator, denominator):
    return (2 * numerator + denominator) // (2 * denominator)


def round_half_away(numerator, denominator):
    if numerator < 0:
        return -round_half_up(-numerator, denominator)
    return round_half_up(numerator, denominator)


def decimal_display(value, negative_sign="-"):
    sign = negative_sign if value < 0 else ""
    value = abs(value)
    return f"{sign}{value // 10}.{value % 10}"


def index_display(value):
    return "none" if value is None else decimal_display(value, "+")


def handicap_display(value):
    return "none" if value is None else ("+" + str(-value) if value < 0 else str(value))


def average_display(total, count):
    if count == 0:
        return "-"
    hundredths = total * 100 // count
    return f"{hundredths // 100}.{hundredths % 100:02d}"


def allocation(handicap, indexes):
    quotient, remainder = divmod(abs(handicap), 18)
    if handicap >= 0:
        return [quotient + int(index <= remainder) for index in indexes]
    return [-quotient - int(index >= 19 - remainder) for index in indexes]


def countback(values):
    return sum(values), sum(values[9:]), sum(values[12:]), sum(values[15:]), values[17]


def ranked(entries, values, larger=False):
    def key(identifier):
        counts = countback(values[identifier])
        if larger:
            counts = tuple(-value for value in counts)
        return counts, identifier
    return sorted(entries, key=key)


def match_status(lead):
    if lead == 0:
        return "AS"
    return str(abs(lead)) + (" UP" if lead > 0 else " DN")


class Course:
    def __init__(self, identifier, pars, indexes):
        self.identifier = identifier
        self.pars = pars
        self.indexes = indexes
        self.par = sum(pars)
        self.tees = {}


class Tee:
    def __init__(self, identifier, rating, slope):
        self.identifier = identifier
        self.rating = rating
        self.slope = slope

    def handicap(self, index, course):
        numerator = index * self.slope + 113 * (self.rating - 10 * course.par)
        return round_half_up(numerator, 1130)


class Player:
    def __init__(self, identifier, name, index):
        self.identifier = identifier
        self.name = name
        self.index = index
        self.rounds = []
        self.records = []
        self.calculation = None

    def low_index(self, day):
        records = [(index, date) for date, index in self.records if day - 365 <= date < day]
        return min(records) if records else None

    def eligible(self):
        start = max(0, len(self.rounds) - 20)
        reduction = 0
        eligible = []
        for position in range(len(self.rounds) - 1, start - 1, -1):
            record = self.rounds[position]
            reduction += record.exceptional
            eligible.append((position + 1, record, record.differential - reduction))
        return eligible[::-1]

    def counting(self, eligible):
        count = len(eligible)
        if count < 3:
            return [], 0
        if count == 3:
            lowest, adjustment = 1, -20
        elif count == 4:
            lowest, adjustment = 1, -10
        elif count == 5:
            lowest, adjustment = 1, 0
        elif count == 6:
            lowest, adjustment = 2, -10
        elif count <= 8:
            lowest, adjustment = 2, 0
        elif count <= 11:
            lowest, adjustment = 3, 0
        elif count <= 14:
            lowest, adjustment = 4, 0
        elif count <= 16:
            lowest, adjustment = 5, 0
        elif count <= 18:
            lowest, adjustment = 6, 0
        elif count == 19:
            lowest, adjustment = 7, 0
        else:
            lowest, adjustment = 8, 0
        return sorted(eligible, key=lambda row: (row[2], -row[0]))[:lowest], adjustment

    def update_index(self, day):
        selected, adjustment = self.counting(self.eligible())
        if not selected:
            self.calculation = None
            return
        average = round_half_away(sum(row[2] for row in selected), len(selected))
        candidate = average + adjustment
        low_record = self.low_index(day)
        low = low_record[0] if low_record is not None else None
        soft = False
        hard = False
        maximum = False
        if low is not None:
            if candidate - low > 30:
                candidate = low + 30 + (candidate - low - 30) // 2
                soft = True
            if candidate - low > 50:
                candidate = low + 50
                hard = True
        if candidate > 540:
            candidate = 540
            maximum = True
        self.index = candidate
        self.calculation = (len(selected), average, adjustment, low, hard, soft, maximum)


class Round:
    def __init__(self, player, course, tee, day, scores):
        self.course = course
        self.tee = tee
        self.day = day
        self.scores = scores
        self.previous_index = player.index
        self.previous_records = len(player.records)
        self.previous_calculation = player.calculation
        self.handicap = tee.handicap(player.index, course) if player.index is not None else None
        strokes = allocation(self.handicap or 0, course.indexes)
        self.adjusted = []
        for par, score, stroke in zip(course.pars, scores, strokes):
            limit = par + 5 if self.handicap is None else par + 2 + stroke
            if score == "-":
                adjusted = par + stroke
            elif score == "X":
                adjusted = limit
            else:
                adjusted = min(score, limit)
            self.adjusted.append(adjusted)
        self.ags = sum(self.adjusted)
        self.differential = round_half_away(113 * (10 * self.ags - tee.rating), tee.slope)
        self.exceptional = 0
        if player.index is not None and player.index - self.differential >= 70:
            self.exceptional = 20 if player.index - self.differential >= 100 else 10

    def nets(self, strokes):
        return [score - stroke if isinstance(score, int) else None for score, stroke in zip(self.scores, strokes)]

    def points(self, nets):
        return [max(0, par + 2 - net) if net is not None else 0 for par, net in zip(self.course.pars, nets)]

    def complete(self):
        return all(isinstance(score, int) for score in self.scores)


class Event:
    def __init__(self, identifier, form, course, tee, day, allowance, players):
        self.identifier = identifier
        self.form = form
        self.course = course
        self.tee = tee
        self.day = day
        self.allowance = allowance
        self.players = players

    def rounds(self):
        rounds = {}
        for player in self.players:
            matching = [
                record for record in player.rounds
                if record.course is self.course and record.tee is self.tee and record.day == self.day
            ]
            if not matching:
                raise CommandError("missing round")
            if matching[0].handicap is None:
                raise CommandError("no index")
            rounds[player.identifier] = matching[0]
        return rounds


class GolfScorer:
    def __init__(self):
        self.courses = {}
        self.players = {}
        self.events = {}
        self.output = []

    def emit(self, *parts):
        self.output.append(" ".join(str(part) for part in parts))

    def player(self, identifier):
        if identifier not in self.players:
            raise CommandError("unknown player")
        return self.players[identifier]

    def course(self, identifier):
        if identifier not in self.courses:
            raise CommandError("unknown course")
        return self.courses[identifier]

    def tee(self, course_id, tee_id):
        course = self.course(course_id)
        if tee_id not in course.tees:
            raise CommandError("unknown tee")
        return course, course.tees[tee_id]

    def register_course(self, arguments):
        identifier = arguments[0]
        if identifier in self.courses:
            raise CommandError("duplicate course")
        pars = [int(value) for value in arguments[1:19]]
        indexes = [int(value) for value in arguments[19:37]]
        if any(par not in (3, 4, 5) for par in pars) or sorted(indexes) != list(range(1, 19)):
            raise CommandError("invalid course")
        self.courses[identifier] = Course(identifier, pars, indexes)

    def register_tee(self, arguments):
        identifier, tee_id, rating, slope = arguments
        course = self.course(identifier)
        if tee_id in course.tees:
            raise CommandError("duplicate tee")
        rating, slope = int(rating), int(slope)
        if not (500 <= rating <= 900 and 55 <= slope <= 155):
            raise CommandError("invalid tee")
        course.tees[tee_id] = Tee(tee_id, rating, slope)

    def register_player(self, arguments):
        identifier, name = arguments[:2]
        if identifier in self.players:
            raise CommandError("duplicate player")
        index = int(arguments[2]) if len(arguments) == 3 else None
        if index is not None and not -100 <= index <= 540:
            raise CommandError("invalid index")
        self.players[identifier] = Player(identifier, name, index)

    def add_round(self, arguments):
        player = self.player(arguments[0])
        course, tee = self.tee(arguments[1], arguments[2])
        day = int(arguments[3])
        if player.rounds and day < player.rounds[-1].day:
            raise CommandError("invalid day")
        scores = [int(value) if value.isdigit() else value for value in arguments[4:]]
        if scores.count("-") >= 5:
            raise CommandError("too few holes")
        record = Round(player, course, tee, day, scores)
        player.rounds.append(record)
        player.update_index(day)
        if player.index is not None:
            player.records.append((day, player.index))
        parts = [
            "round", player.identifier, str(len(player.rounds)) + ":",
            "ags", record.ags, "diff", decimal_display(record.differential),
        ]
        if record.exceptional:
            parts.extend(("exceptional", decimal_display(-record.exceptional)))
        parts.extend(("index", index_display(player.index)))
        self.emit(*parts)

    def remove(self, arguments):
        player = self.player(arguments[0])
        if not player.rounds:
            raise CommandError("no rounds")
        number = len(player.rounds)
        record = player.rounds.pop()
        player.index = record.previous_index
        player.records = player.records[:record.previous_records]
        player.calculation = record.previous_calculation
        self.emit("removed", player.identifier, str(number) + ":", "index", index_display(player.index))

    def show_index(self, arguments):
        player = self.player(arguments[0])
        parts = ["index", player.identifier + ":", index_display(player.index), "rounds", len(player.rounds)]
        if player.calculation is not None:
            lowest, average, adjustment, low, hard, soft, maximum = player.calculation
            parts.extend((
                "lowest", lowest, "average", decimal_display(average),
                "adjustment", decimal_display(adjustment),
            ))
            if low is not None:
                parts.extend(("low", index_display(low)))
            if hard:
                parts.extend(("hard", "cap"))
            elif soft:
                parts.extend(("soft", "cap"))
            if maximum:
                parts.append("maximum")
        self.emit(*parts)

    def history(self, arguments):
        player = self.player(arguments[0])
        eligible = player.eligible()
        selected, _ = player.counting(eligible)
        counted = {row[0] for row in selected}
        self.emit("history", player.identifier + ":", "rounds", len(player.rounds))
        for number, record, adjusted in eligible:
            parts = [
                number, "day", record.day, record.course.identifier, record.tee.identifier,
                "ags", record.ags, "diff", decimal_display(record.differential),
            ]
            if adjusted != record.differential:
                parts.extend(("adjusted", decimal_display(adjusted)))
            if number in counted:
                parts.append("*")
            self.emit(*parts)

    def lowindex(self, arguments):
        player = self.player(arguments[0])
        day = int(arguments[1])
        record = player.low_index(day)
        parts = ["lowindex", player.identifier, str(day) + ":"]
        if record is None:
            parts.append("none")
        else:
            index, date = record
            parts.extend((index_display(index), "day", date))
        self.emit(*parts)

    def coursehcp(self, arguments):
        player = self.player(arguments[0])
        course, tee = self.tee(arguments[1], arguments[2])
        if player.index is None:
            raise CommandError("no index")
        handicap = tee.handicap(player.index, course)
        self.emit(
            "coursehcp", player.identifier, course.identifier, tee.identifier + ":",
            handicap_display(handicap), "strokes", *allocation(handicap, course.indexes),
        )

    def hcptable(self, arguments):
        course, tee = self.tee(arguments[0], arguments[1])
        first, last = int(arguments[2]), int(arguments[3])
        if not -100 <= first <= last <= 540:
            raise CommandError("invalid index")
        self.emit("hcptable", course.identifier, tee.identifier + ":", index_display(first), "to", index_display(last))
        start = first
        handicap = tee.handicap(first, course)
        for index in range(first + 1, last + 1):
            next_handicap = tee.handicap(index, course)
            if next_handicap != handicap:
                self.emit(index_display(start), "to", index_display(index - 1) + ":", handicap_display(handicap))
                start, handicap = index, next_handicap
        self.emit(index_display(start), "to", index_display(last) + ":", handicap_display(handicap))

    def card_total(self, label, record, strokes, nets, points, first, last):
        scores = record.scores[first:last]
        net_values = nets[first:last]
        complete = all(isinstance(score, int) for score in scores)
        self.emit(
            label, sum(record.course.pars[first:last]), sum(scores) if complete else "-",
            sum(record.adjusted[first:last]), sum(strokes[first:last]),
            sum(net_values) if complete else "-", sum(points[first:last]),
        )

    def card(self, arguments):
        player = self.player(arguments[0])
        number = int(arguments[1])
        if number > len(player.rounds):
            raise CommandError("unknown round")
        record = player.rounds[number - 1]
        course = record.course
        strokes = allocation(record.handicap or 0, course.indexes)
        nets = record.nets(strokes)
        points = record.points(nets)
        self.emit(
            "card", player.identifier, str(number) + ":", course.identifier,
            record.tee.identifier, "day", record.day, "handicap", handicap_display(record.handicap),
        )
        for index in range(18):
            self.emit(
                index + 1, course.pars[index], course.indexes[index], record.scores[index],
                record.adjusted[index], strokes[index], nets[index] if nets[index] is not None else "-", points[index],
            )
            if index == 8:
                self.card_total("OUT", record, strokes, nets, points, 0, 9)
            elif index == 17:
                self.card_total("IN", record, strokes, nets, points, 9, 18)
                self.card_total("TOTAL", record, strokes, nets, points, 0, 18)
        self.emit("ags", record.ags, "diff", decimal_display(record.differential))

    def stats(self, arguments):
        player = self.player(arguments[0])
        categories = dict.fromkeys(("eagles", "birdies", "pars", "bogeys", "doubles", "others", "pickups"), 0)
        par_scores = {par: [] for par in (3, 4, 5)}
        complete_totals = []
        for record in player.rounds:
            if record.complete():
                complete_totals.append(sum(record.scores))
            for par, score in zip(record.course.pars, record.scores):
                if score == "X":
                    categories["pickups"] += 1
                elif isinstance(score, int):
                    relative = score - par
                    category = ("eagles" if relative <= -2 else "birdies" if relative == -1 else
                                "pars" if relative == 0 else "bogeys" if relative == 1 else
                                "doubles" if relative == 2 else "others")
                    categories[category] += 1
                    par_scores[par].append(score)
        parts = [
            "stats", player.identifier + ":", "rounds", len(player.rounds),
            "best", min(complete_totals) if complete_totals else "-",
            "average", average_display(sum(complete_totals), len(complete_totals)),
        ]
        for category, count in categories.items():
            parts.extend((category, count))
        for par, scores in par_scores.items():
            parts.extend(("par" + str(par), average_display(sum(scores), len(scores))))
        self.emit(*parts)

    def holestats(self, arguments):
        course = self.course(arguments[0])
        rounds = [r for p in self.players.values() for r in p.rounds if r.course is course]
        scores = [[r.scores[h] for r in rounds if isinstance(r.scores[h], int)] for h in range(18)]
        def difficulty(hole):
            values = scores[hole]
            relative = Fraction(sum(values), len(values)) - course.pars[hole] if values else Fraction(0)
            return not values, -relative, hole
        order = sorted(range(18), key=difficulty)
        ranks = {hole: rank for rank, hole in enumerate(order, 1)}
        self.emit("holestats", course.identifier + ":", "rounds", len(rounds))
        for hole, values in enumerate(scores):
            self.emit(
                hole + 1, "par", course.pars[hole], "si", course.indexes[hole],
                "scores", len(values), "avg", average_display(sum(values), len(values)), "rank", ranks[hole],
            )

    def show_players(self, arguments):
        players = sorted(self.players.values(), key=lambda p: (p.index is None, p.index or 0, p.identifier))
        self.emit("players", len(players))
        for player in players:
            self.emit(player.identifier, player.name, index_display(player.index), "rounds", len(player.rounds))

    def register_event(self, arguments):
        identifier, form, course_id, tee_id, day, allowance = arguments[:6]
        if identifier in self.events:
            raise CommandError("duplicate event")
        course, tee = self.tee(course_id, tee_id)
        allowance = int(allowance)
        if not 1 <= allowance <= 100:
            raise CommandError("invalid allowance")
        identifiers = arguments[6:]
        if any(identifier not in self.players for identifier in identifiers):
            raise CommandError("unknown player")
        count = len(identifiers)
        if form in ("MATCH", "NASSAU"):
            valid = count == 2
        elif form == "FOURBALL":
            valid = count == 4
        elif form == "BETTERBALL":
            valid = count in (4, 6, 8)
        else:
            valid = 2 <= count <= 8
        if len(set(identifiers)) != count or not valid:
            raise CommandError("invalid players")
        self.events[identifier] = Event(
            identifier, form, course, tee, int(day), allowance,
            [self.players[player] for player in identifiers],
        )

    def event_data(self, event):
        rounds = event.rounds()
        handicaps = {
            identifier: round_half_up(record.handicap * event.allowance, 100)
            for identifier, record in rounds.items()
        }
        minimum = min(handicaps.values()) if event.form in ("MATCH", "NASSAU", "FOURBALL") else 0
        nets = {
            identifier: record.nets(allocation(handicaps[identifier] - minimum, event.course.indexes))
            for identifier, record in rounds.items()
        }
        points = {identifier: record.points(nets[identifier]) for identifier, record in rounds.items()}
        return rounds, handicaps, nets, points

    def event_ranking(self, event, rounds, nets, points):
        identifiers = [player.identifier for player in event.players]
        if event.form == "STROKE":
            complete = [identifier for identifier in identifiers if rounds[identifier].complete()]
            return ranked(complete, nets), nets
        if event.form == "STABLEFORD":
            return ranked(identifiers, points, True), points
        values = {
            identifier: [
                -1 if net is None or net > par else 1 if net < par else 0
                for net, par in zip(nets[identifier], event.course.pars)
            ]
            for identifier in identifiers
        }
        return ranked(identifiers, values, True), values

    def individual_results(self, event, rounds, handicaps, nets, points):
        order, values = self.event_ranking(event, rounds, nets, points)
        for rank, identifier in enumerate(order, 1):
            handicap = handicap_display(handicaps[identifier])
            if event.form == "STROKE":
                self.emit(rank, identifier, "net", sum(nets[identifier]), "gross", sum(rounds[identifier].scores), "hcp", handicap)
            elif event.form == "STABLEFORD":
                self.emit(rank, identifier, "points", sum(points[identifier]), "hcp", handicap)
            else:
                self.emit(rank, identifier, match_status(sum(values[identifier])), "hcp", handicap)
        if event.form == "STROKE":
            nonreturners = sorted(player.identifier for player in event.players if not rounds[player.identifier].complete())
            for identifier in nonreturners:
                self.emit("NR", identifier, "hcp", handicap_display(handicaps[identifier]))
            if order:
                gross = {identifier: rounds[identifier].scores for identifier in order}
                winner = ranked(order, gross)[0]
                self.emit("gross", winner, sum(gross[winner]))

    def match_holes(self, event, nets):
        identifiers = [player.identifier for player in event.players]
        if event.form == "FOURBALL":
            sides = (identifiers[:2], identifiers[2:])
        else:
            sides = (identifiers[:1], identifiers[1:])
        names = tuple("+".join(side) for side in sides)
        holes = []
        for hole in range(18):
            side_scores = []
            for side in sides:
                scores = [nets[player][hole] for player in side if nets[player][hole] is not None]
                side_scores.append(min(scores) if scores else None)
            first, second = side_scores
            if first is None:
                winner = 0 if second is None else -1
            elif second is None or first < second:
                winner = 1
            else:
                winner = -1 if first > second else 0
            holes.append(winner)
        return names, holes

    def play_match(self, names, holes, first, last):
        lead = 0
        statuses = []
        for hole in range(first, last):
            lead += holes[hole]
            statuses.append(match_status(lead))
            remaining = last - hole - 1
            if abs(lead) > remaining or remaining == 0:
                break
        if lead == 0:
            result = "AS"
        else:
            name = names[0] if lead > 0 else names[1]
            margin = f"{abs(lead)}&{remaining}" if remaining else str(abs(lead)) + " UP"
            result = name + " " + margin
        return statuses, result

    def match_results(self, event, handicaps, nets):
        minimum = min(handicaps.values())
        parts = ["strokes"]
        for player in event.players:
            parts.extend((player.identifier, handicaps[player.identifier] - minimum))
        self.emit(*parts)
        names, holes = self.match_holes(event, nets)
        if event.form == "NASSAU":
            for label, first, last in (("front", 0, 9), ("back", 9, 18), ("total", 0, 18)):
                _, result = self.play_match(names, holes, first, last)
                self.emit(label, result)
        else:
            statuses, result = self.play_match(names, holes, 0, 18)
            self.emit("status", ", ".join(statuses))
            self.emit("result", result)

    def betterball_results(self, event, handicaps, points):
        identifiers = [player.identifier for player in event.players]
        teams = {identifiers[i]: (identifiers[i], identifiers[i + 1]) for i in range(0, len(identifiers), 2)}
        values = {
            first: [max(points[first][hole], points[second][hole]) for hole in range(18)]
            for first, second in teams.values()
        }
        for rank, first in enumerate(ranked(teams, values, True), 1):
            first, second = teams[first]
            self.emit(
                rank, first + "+" + second, "points", sum(values[first]), "hcp",
                handicap_display(handicaps[first]), handicap_display(handicaps[second]),
            )

    def skins_results(self, event, nets):
        identifiers = [player.identifier for player in event.players]
        totals = dict.fromkeys(identifiers, 0)
        carry = 0
        last_minimum = []
        for hole in range(18):
            carry += 1
            available = [player for player in identifiers if nets[player][hole] is not None]
            if available:
                best = min(nets[player][hole] for player in available)
                winners = [player for player in available if nets[player][hole] == best]
            else:
                winners = []
            last_minimum = winners
            if len(winners) == 1:
                self.emit("hole", hole + 1, winners[0], carry)
                totals[winners[0]] += 100 * carry
                carry = 0
        if carry:
            sharing = sorted(last_minimum or identifiers)
            share = carry * 100 // len(sharing)
            for identifier in sharing:
                totals[identifier] += share
            self.emit("carry", carry, *sharing)
        for identifier in sorted(identifiers, key=lambda player: (-totals[player], player)):
            value = totals[identifier]
            self.emit(identifier, f"{value // 100}.{value % 100:02d}")

    def results(self, arguments):
        identifier = arguments[0]
        if identifier not in self.events:
            raise CommandError("unknown event")
        event = self.events[identifier]
        rounds, handicaps, nets, points = self.event_data(event)
        self.emit(
            "results", identifier + ":", event.form, event.course.identifier,
            event.tee.identifier, "day", event.day, "allowance", event.allowance,
        )
        if event.form in ("STROKE", "STABLEFORD", "PAR"):
            self.individual_results(event, rounds, handicaps, nets, points)
        elif event.form in ("MATCH", "NASSAU", "FOURBALL"):
            self.match_results(event, handicaps, nets)
        elif event.form == "BETTERBALL":
            self.betterball_results(event, handicaps, points)
        else:
            self.skins_results(event, nets)

    def merit(self, arguments):
        players = {}
        counted = 0
        awards = (10, 8, 6, 5, 4, 3, 2, 1)
        for event in self.events.values():
            if event.form not in ("STROKE", "STABLEFORD", "PAR"):
                continue
            try:
                rounds, _, nets, points = self.event_data(event)
            except CommandError:
                continue
            counted += 1
            order, _ = self.event_ranking(event, rounds, nets, points)
            for player in event.players:
                players.setdefault(player.identifier, [0, 0, 0])[2] += 1
            for rank, identifier in enumerate(order):
                players[identifier][0] += awards[rank]
                players[identifier][1] += int(rank == 0)
        self.emit("merit:", "events", counted)
        order = sorted(players, key=lambda player: (-players[player][0], -players[player][1], player))
        for rank, identifier in enumerate(order, 1):
            points, wins, appearances = players[identifier]
            self.emit(rank, identifier, points, "wins", wins, "played", appearances)

    def execute(self, line):
        command, *arguments = line.split()
        handlers = {
            "COURSE": self.register_course,
            "TEE": self.register_tee,
            "PLAYER": self.register_player,
            "ROUND": self.add_round,
            "REMOVE": self.remove,
            "INDEX": self.show_index,
            "HISTORY": self.history,
            "LOWINDEX": self.lowindex,
            "COURSEHCP": self.coursehcp,
            "HCPTABLE": self.hcptable,
            "CARD": self.card,
            "STATS": self.stats,
            "HOLESTATS": self.holestats,
            "PLAYERS": self.show_players,
            "EVENT": self.register_event,
            "RESULTS": self.results,
            "MERIT": self.merit,
        }
        try:
            handlers[command](arguments)
        except CommandError as error:
            self.emit("ERROR", error)


def main():
    scorer = GolfScorer()
    count = int(sys.stdin.readline())
    for _ in range(count):
        scorer.execute(sys.stdin.readline().rstrip("\n"))
    if scorer.output:
        sys.stdout.write("\n".join(scorer.output) + "\n")


if __name__ == "__main__":
    main()
