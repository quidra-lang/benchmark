import sys


MODULUS = 2147483647
MULTIPLIER = 48271
STV_SCALE = 100
UNRANKABLE = ("CONDORCET", "STV")
SUMMARY_METHODS = (
    "PLURALITY", "RUNOFF", "IRV", "COOMBS", "BUCKLIN", "BORDA", "BALDWIN", "NANSON",
    "BLACK", "VETO", "COPELAND", "MINIMAX WINNING", "SCHULZE", "RANKEDPAIRS", "KEMENY",
)


def next_random(state):
    return state * MULTIPLIER % MODULUS


def stv_value(value):
    return f"{value // STV_SCALE}.{value % STV_SCALE:02d}"


def tie_mark(tie):
    return " (tie)" if tie else ""


def name_list(names, candidates, separator=", "):
    return separator.join(names[candidate] for candidate in candidates)


def first_member(ranking, members):
    for candidate in ranking:
        if candidate in members:
            return candidate
    return None


class CommandError(Exception):
    pass


class BallotGroup:
    def __init__(self, votes, ranking):
        self.votes = votes
        self.ranking = ranking


class WeightedGroup:
    def __init__(self, votes, ranking):
        self.votes = votes
        self.ranking = ranking
        self.value = STV_SCALE
        self.current = None


class Outcome:
    def __init__(self, lines, standings=None):
        self.lines = lines
        self.standings = standings


class Election:
    def __init__(self, number, names):
        self.number = number
        self.names = names
        self.index = {name: candidate for candidate, name in enumerate(names)}
        self.withdrawn = [False] * len(names)
        self.tiebreak = sorted(range(len(names)), key=lambda candidate: names[candidate])
        self.entries = []

    def active(self):
        return [candidate for candidate in range(len(self.names)) if not self.withdrawn[candidate]]

    def withdrawn_candidates(self):
        return [candidate for candidate in range(len(self.names)) if self.withdrawn[candidate]]

    def groups(self):
        return [group for entry in self.entries for group in entry]

    def total_votes(self):
        return sum(group.votes for group in self.groups())


class Tally:
    def __init__(self, election, field):
        self.names = election.names
        self.field = field
        self.position = {candidate: place for place, candidate in enumerate(election.tiebreak)}
        members = set(field)
        self.groups = [
            BallotGroup(group.votes, [candidate for candidate in group.ranking if candidate in members])
            for group in election.groups()
        ]
        self.total = sum(group.votes for group in self.groups)
        size = len(self.names)
        self.pairwise = [[0] * size for _ in range(size)]
        for group in self.groups:
            unranked = [candidate for candidate in field if candidate not in group.ranking]
            for place, preferred in enumerate(group.ranking):
                for other in group.ranking[place + 1:] + unranked:
                    self.pairwise[preferred][other] += group.votes

    def earliest(self, candidates):
        return min(candidates, key=lambda candidate: self.position[candidate])

    def latest(self, candidates):
        return max(candidates, key=lambda candidate: self.position[candidate])

    def by_tiebreak(self, candidates):
        return sorted(candidates, key=lambda candidate: self.position[candidate])

    def descending(self, candidates, values):
        return sorted(candidates, key=lambda candidate: (-values[candidate], self.position[candidate]))

    def ascending(self, candidates, values):
        return sorted(candidates, key=lambda candidate: (values[candidate], self.position[candidate]))

    def leader_tie(self, standings, values):
        return values[standings[0]] == values[standings[1]]

    def value_list(self, values, form=str):
        return ", ".join(
            f"{self.names[candidate]} {form(values[candidate])}" for candidate in sorted(values)
        )

    def winner_line(self, winner, tie):
        return "winner: " + self.names[winner] + tie_mark(tie)

    def name_or_none(self, candidate):
        return "NONE" if candidate is None else self.names[candidate]

    def beats(self, first, second):
        return self.pairwise[first][second] > self.pairwise[second][first]

    def first_choices(self, members):
        counts = {candidate: 0 for candidate in members}
        for group in self.groups:
            choice = first_member(group.ranking, counts)
            if choice is not None:
                counts[choice] += group.votes
        return counts

    def last_places(self, members):
        counts = {candidate: 0 for candidate in members}
        for group in self.groups:
            ranked = [candidate for candidate in group.ranking if candidate in counts]
            if len(ranked) < len(members):
                for candidate in members:
                    if candidate not in ranked:
                        counts[candidate] += group.votes
            else:
                counts[ranked[-1]] += group.votes
        return counts

    def borda_scores(self, members):
        scores = {candidate: 0 for candidate in members}
        for group in self.groups:
            ranked = [candidate for candidate in group.ranking if candidate in scores]
            for place, candidate in enumerate(ranked, 1):
                scores[candidate] += group.votes * (len(members) - place)
        return scores

    def approvals(self, depth):
        counts = {candidate: 0 for candidate in self.field}
        for group in self.groups:
            for candidate in group.ranking[:depth]:
                counts[candidate] += group.votes
        return counts

    def has_majority(self, values):
        total = sum(values.values())
        return any(2 * value > total for value in values.values())

    def look_back(self, rounds):
        current = rounds[-1]
        lowest = min(current.values())
        pool = [candidate for candidate in current if current[candidate] == lowest]
        tie = len(pool) > 1
        for values in reversed(rounds[:-1]):
            least = min(values[candidate] for candidate in pool)
            pool = [candidate for candidate in pool if values[candidate] == least]
        return self.latest(pool), tie

    def condorcet_winner(self):
        for candidate in self.field:
            if all(self.beats(candidate, other) for other in self.field if other != candidate):
                return candidate
        return None

    def condorcet_loser(self):
        for candidate in self.field:
            if all(self.beats(other, candidate) for other in self.field if other != candidate):
                return candidate
        return None

    def closure(self, relation):
        reach = [row[:] for row in relation]
        for middle in self.field:
            for start in self.field:
                for end in self.field:
                    if reach[start][middle] and reach[middle][end]:
                        reach[start][end] = True
        return reach

    def reaches(self, edges, start, target):
        seen = {start}
        stack = [start]
        while stack:
            current = stack.pop()
            if current == target:
                return True
            for following in self.field:
                if edges[current][following] and following not in seen:
                    seen.add(following)
                    stack.append(following)
        return False

    def sequence(self, blocks):
        remaining = list(self.field)
        standings = []
        tie = False
        while remaining:
            choices = [
                candidate for candidate in remaining
                if not any(blocks[other][candidate] for other in remaining if other != candidate)
            ]
            if not standings:
                tie = len(choices) > 1
            chosen = self.earliest(choices)
            standings.append(chosen)
            remaining.remove(chosen)
        return standings, tie

    def pairwise_lines(self, table):
        lines = []
        for place, first in enumerate(self.field):
            for second in self.field[place + 1:]:
                if table[first][second] > table[second][first]:
                    result = self.names[first]
                elif table[first][second] < table[second][first]:
                    result = self.names[second]
                else:
                    result = "tie"
                lines.append(
                    f"{self.names[first]} vs {self.names[second]}: "
                    f"{table[first][second]}-{table[second][first]} ({result})"
                )
        return lines

    def ballot_lines(self):
        totals = {}
        blank = 0
        for group in self.groups:
            if group.ranking:
                notation = name_list(self.names, group.ranking, ">")
            else:
                notation = "-"
                blank += group.votes
            totals[notation] = totals.get(notation, 0) + group.votes
        lines = [f"total {self.total}, blank {blank}, distinct {len(totals)}"]
        for notation in sorted(totals, key=lambda text: (-totals[text], text)):
            lines.append(f"{totals[notation]} {notation}")
        return lines

    def profile_lines(self):
        lines = []
        for candidate in self.field:
            places = [0] * len(self.field)
            unranked = 0
            for group in self.groups:
                if candidate in group.ranking:
                    places[group.ranking.index(candidate)] += group.votes
                else:
                    unranked += group.votes
            counts = " ".join(str(count) for count in places)
            lines.append(f"{self.names[candidate]}: {counts} unranked {unranked}")
        return lines

    def instant_runoff_rounds(self):
        remaining = list(self.field)
        rounds = []
        eliminations = []
        while True:
            votes = self.first_choices(remaining)
            rounds.append(votes)
            if len(remaining) == 1 or self.has_majority(votes):
                return rounds, eliminations
            loser, tie = self.look_back(rounds)
            eliminations.append((loser, tie))
            remaining.remove(loser)

    def exhausted_lines(self):
        rounds, _ = self.instant_runoff_rounds()
        lines = []
        for number, votes in enumerate(rounds, 1):
            active = sum(votes.values())
            lines.append(f"round {number}: active {active}, exhausted {self.total - active}")
        return lines

    def scored(self, label, values, highest_first):
        if highest_first:
            standings = self.descending(self.field, values)
        else:
            standings = self.ascending(self.field, values)
        lines = [
            f"{label}: {self.value_list(values)}",
            self.winner_line(standings[0], self.leader_tie(standings, values)),
        ]
        return Outcome(lines, standings)

    def plurality(self):
        return self.scored("votes", self.first_choices(self.field), True)

    def runoff(self):
        first_round = self.first_choices(self.field)
        order = self.descending(self.field, first_round)
        lines = ["round 1: " + self.value_list(first_round)]
        if self.has_majority(first_round):
            lines.append(self.winner_line(order[0], False))
            return Outcome(lines, order)
        finalists = sorted(order[:2])
        advancement_tie = len(order) >= 3 and first_round[order[1]] == first_round[order[2]]
        second_round = self.first_choices(finalists)
        winner, runner_up = order[0], order[1]
        if second_round[runner_up] > second_round[winner]:
            winner, runner_up = runner_up, winner
        tie = second_round[winner] == second_round[runner_up]
        lines.append("finalists: " + name_list(self.names, finalists) + tie_mark(advancement_tie))
        lines.append("round 2: " + self.value_list(second_round))
        lines.append(self.winner_line(winner, tie))
        return Outcome(lines, [winner, runner_up] + order[2:])

    def instant_runoff(self):
        rounds, eliminations = self.instant_runoff_rounds()
        lines = []
        for number, votes in enumerate(rounds, 1):
            line = f"round {number}: " + self.value_list(votes)
            if number <= len(eliminations):
                loser, tie = eliminations[number - 1]
                line += f"; eliminated {self.names[loser]}" + tie_mark(tie)
            lines.append(line)
        final = rounds[-1]
        standings = self.descending(final.keys(), final)
        standings += [loser for loser, _ in reversed(eliminations)]
        lines.append(self.winner_line(standings[0], False))
        return Outcome(lines, standings)

    def coombs(self):
        remaining = list(self.field)
        eliminated = []
        lines = []
        while True:
            votes = self.first_choices(remaining)
            line = f"round {len(lines) + 1}: " + self.value_list(votes)
            if len(remaining) == 1 or self.has_majority(votes):
                lines.append(line)
                break
            lasts = self.last_places(remaining)
            most = max(lasts.values())
            pool = [candidate for candidate in remaining if lasts[candidate] == most]
            fewest = min(votes[candidate] for candidate in pool)
            loser = self.latest([candidate for candidate in pool if votes[candidate] == fewest])
            lines.append(
                line + "; last " + self.value_list(lasts)
                + f"; eliminated {self.names[loser]}" + tie_mark(len(pool) > 1)
            )
            remaining.remove(loser)
            eliminated.append(loser)
        standings = self.descending(remaining, votes) + eliminated[::-1]
        lines.append(self.winner_line(standings[0], False))
        return Outcome(lines, standings)

    def bucklin(self):
        majority = sum(group.votes for group in self.groups if group.ranking) // 2 + 1
        lines = [f"majority: {majority}"]
        rounds = []
        for depth in range(1, len(self.field) + 1):
            votes = self.approvals(depth)
            rounds.append(votes)
            lines.append(f"round {depth}: " + self.value_list(votes))
            if max(votes.values()) >= majority:
                break
        standings = sorted(
            self.field,
            key=lambda candidate: [-counts[candidate] for counts in reversed(rounds)]
            + [self.position[candidate]],
        )
        lines.append(self.winner_line(standings[0], self.leader_tie(standings, rounds[-1])))
        return Outcome(lines, standings)

    def borda(self):
        return self.scored("scores", self.borda_scores(self.field), True)

    def baldwin(self):
        remaining = list(self.field)
        rounds = []
        eliminated = []
        lines = []
        while len(remaining) > 1:
            scores = self.borda_scores(remaining)
            rounds.append(scores)
            loser, tie = self.look_back(rounds)
            lines.append(
                f"round {len(rounds)}: {self.value_list(scores)}; "
                f"eliminated {self.names[loser]}" + tie_mark(tie)
            )
            remaining.remove(loser)
            eliminated.append(loser)
        standings = remaining + eliminated[::-1]
        lines.append(self.winner_line(standings[0], False))
        return Outcome(lines, standings)

    def nanson(self):
        remaining = list(self.field)
        eliminated = []
        lines = []
        while len(remaining) > 1:
            scores = self.borda_scores(remaining)
            total = sum(scores.values())
            below = [candidate for candidate in remaining if scores[candidate] * len(remaining) < total]
            line = f"round {len(lines) + 1}: " + self.value_list(scores)
            if not below:
                lines.append(line)
                break
            lines.append(line + "; eliminated " + name_list(self.names, below))
            eliminated = self.descending(below, scores) + eliminated
            remaining = [candidate for candidate in remaining if candidate not in below]
        standings = self.by_tiebreak(remaining) + eliminated
        lines.append(self.winner_line(standings[0], len(remaining) > 1))
        return Outcome(lines, standings)

    def black(self):
        winner = self.condorcet_winner()
        scores = self.borda_scores(self.field)
        standings = self.descending(self.field, scores)
        tie = self.leader_tie(standings, scores)
        if winner is not None:
            standings = [winner] + [candidate for candidate in standings if candidate != winner]
            tie = False
        lines = [
            "condorcet: " + self.name_or_none(winner),
            "scores: " + self.value_list(scores),
            self.winner_line(standings[0], tie),
        ]
        return Outcome(lines, standings)

    def veto(self):
        return self.scored("vetoes", self.last_places(self.field), False)

    def condorcet(self):
        size = len(self.names)
        weak = [[first == second or not self.beats(second, first) for second in range(size)]
                for first in range(size)]
        strong = [[self.beats(first, second) for second in range(size)] for first in range(size)]
        weak_reach = self.closure(weak)
        strong_reach = self.closure(strong)
        smith = [
            candidate for candidate in self.field
            if all(weak_reach[candidate][other] for other in self.field)
        ]
        schwartz = [
            candidate for candidate in self.field
            if all(strong_reach[candidate][other] or not strong_reach[other][candidate]
                   for other in self.field)
        ]
        lines = [
            "winner: " + self.name_or_none(self.condorcet_winner()),
            "loser: " + self.name_or_none(self.condorcet_loser()),
            "smith: " + name_list(self.names, smith),
            "schwartz: " + name_list(self.names, schwartz),
        ]
        return Outcome(lines)

    def copeland(self):
        doubled = {}
        parts = []
        for candidate in self.field:
            rivals = [other for other in self.field if other != candidate]
            wins = sum(1 for other in rivals if self.beats(candidate, other))
            losses = sum(1 for other in rivals if self.beats(other, candidate))
            draws = len(rivals) - wins - losses
            doubled[candidate] = 2 * wins + draws
            score = f"{wins + draws // 2}.{draws % 2 * 5}"
            parts.append(f"{self.names[candidate]} {score} ({wins}-{draws}-{losses})")
        standings = self.descending(self.field, doubled)
        lines = [
            "scores: " + ", ".join(parts),
            self.winner_line(standings[0], self.leader_tie(standings, doubled)),
        ]
        return Outcome(lines, standings)

    def minimax(self, kind):
        scores = {}
        for candidate in self.field:
            rivals = [other for other in self.field if other != candidate]
            beaters = [other for other in rivals if self.beats(other, candidate)]
            if kind == "WINNING":
                values = [self.pairwise[other][candidate] for other in beaters]
            elif kind == "MARGIN":
                values = [
                    self.pairwise[other][candidate] - self.pairwise[candidate][other]
                    for other in beaters
                ]
            else:
                values = [self.pairwise[other][candidate] for other in rivals]
            scores[candidate] = max(values, default=0)
        return self.scored("scores", scores, False)

    def schulze(self):
        size = len(self.names)
        strength = [
            [self.pairwise[first][second] if self.beats(first, second) else 0 for second in range(size)]
            for first in range(size)
        ]
        for middle in self.field:
            for start in self.field:
                for end in self.field:
                    if start != middle and end != middle and start != end:
                        through = min(strength[start][middle], strength[middle][end])
                        strength[start][end] = max(strength[start][end], through)
        blocks = [[strength[first][second] > strength[second][first] for second in range(size)]
                  for first in range(size)]
        standings, tie = self.sequence(blocks)
        lines = self.pairwise_lines(strength)
        lines.append("ranking: " + name_list(self.names, standings, " > "))
        lines.append(self.winner_line(standings[0], tie))
        return Outcome(lines, standings)

    def pair_key(self, pair):
        winner, loser = pair
        return (
            -self.pairwise[winner][loser], self.pairwise[loser][winner],
            self.position[winner], self.position[loser],
        )

    def ranked_pairs(self):
        pairs = [
            (winner, loser) for winner in self.field for loser in self.field
            if self.beats(winner, loser)
        ]
        pairs.sort(key=self.pair_key)
        size = len(self.names)
        locked = [[False] * size for _ in range(size)]
        lines = []
        for winner, loser in pairs:
            if self.reaches(locked, loser, winner):
                action = "skip"
            else:
                action = "lock"
                locked[winner][loser] = True
            lines.append(
                f"{action} {self.names[winner]}>{self.names[loser]} "
                f"{self.pairwise[winner][loser]}-{self.pairwise[loser][winner]}"
            )
        standings, tie = self.sequence(locked)
        lines.append(self.winner_line(standings[0], tie))
        return Outcome(lines, standings)

    def lead_score(self, leader, rest):
        return sum(self.pairwise[leader][other] for other in self.field if rest & (1 << other))

    def kemeny(self):
        full = sum(1 << candidate for candidate in self.field)
        best = [0] * (full + 1)
        count = [0] * (full + 1)
        count[0] = 1
        leaders = [[] for _ in range(full + 1)]
        for mask in range(1, full + 1):
            if (mask & full) != mask:
                continue
            for leader in self.field:
                if mask & (1 << leader):
                    rest = mask ^ (1 << leader)
                    score = self.lead_score(leader, rest) + best[rest]
                    if not leaders[mask] or score > best[mask]:
                        best[mask] = score
                        count[mask] = count[rest]
                        leaders[mask] = [leader]
                    elif score == best[mask]:
                        count[mask] += count[rest]
                        leaders[mask].append(leader)
        standings = []
        mask = full
        while mask:
            chosen = self.earliest(leaders[mask])
            standings.append(chosen)
            mask ^= 1 << chosen
        lines = [
            f"score: {best[full]}",
            f"optimal: {count[full]}",
            "ranking: " + name_list(self.names, standings, " > "),
            self.winner_line(standings[0], len(leaders[full]) > 1),
        ]
        return Outcome(lines, standings)

    def approval(self, depth):
        return self.scored("approvals", self.approvals(depth), True)

    def single_transferable_vote(self, seats):
        ballots = [WeightedGroup(group.votes, group.ranking) for group in self.groups if group.ranking]
        quota = sum(ballot.votes for ballot in ballots) * STV_SCALE // (seats + 1) + 1
        continuing = list(self.field)
        elected = []
        rounds = []
        lines = ["quota: " + stv_value(quota)]
        while True:
            tallies = {candidate: 0 for candidate in continuing}
            exhausted = 0
            for ballot in ballots:
                ballot.current = first_member(ballot.ranking, tallies)
                if ballot.current is None:
                    exhausted += ballot.votes * ballot.value
                else:
                    tallies[ballot.current] += ballot.votes * ballot.value
            rounds.append(tallies)
            line = (
                f"round {len(rounds)}: {self.value_list(tallies, stv_value)}; "
                f"exhausted {stv_value(exhausted)}"
            )
            if len(continuing) == seats - len(elected):
                added = self.descending(continuing, tallies)
                elected.extend(added)
                lines.append(line + "; elected " + name_list(self.names, added))
                break
            reached = [candidate for candidate in continuing if tallies[candidate] >= quota]
            if reached:
                winner = self.descending(reached, tallies)[0]
                total = tallies[winner]
                surplus = total - quota
                for ballot in ballots:
                    if ballot.current == winner:
                        ballot.value = ballot.value * surplus // total
                elected.append(winner)
                continuing.remove(winner)
                lines.append(line + f"; elected {self.names[winner]} (surplus {stv_value(surplus)})")
                if len(elected) == seats:
                    break
            else:
                loser, tie = self.look_back(rounds)
                continuing.remove(loser)
                lines.append(line + f"; excluded {self.names[loser]}" + tie_mark(tie))
        lines.append("elected: " + name_list(self.names, elected))
        return Outcome(lines)

    def run(self, method):
        name = method[0]
        if name == "MINIMAX":
            return self.minimax(method[1])
        if name == "APPROVAL":
            return self.approval(int(method[1]))
        if name == "STV":
            return self.single_transferable_vote(int(method[1]))
        methods = {
            "PLURALITY": self.plurality,
            "RUNOFF": self.runoff,
            "IRV": self.instant_runoff,
            "COOMBS": self.coombs,
            "BUCKLIN": self.bucklin,
            "BORDA": self.borda,
            "BALDWIN": self.baldwin,
            "NANSON": self.nanson,
            "BLACK": self.black,
            "VETO": self.veto,
            "CONDORCET": self.condorcet,
            "COPELAND": self.copeland,
            "SCHULZE": self.schulze,
            "RANKEDPAIRS": self.ranked_pairs,
            "KEMENY": self.kemeny,
        }
        return methods[name]()


class VoteCounter:
    def __init__(self):
        self.election = None
        self.started = 0
        self.output = []

    def require_election(self):
        if self.election is None:
            raise CommandError("no election")
        return self.election

    def candidate(self, name):
        if name not in self.election.index:
            raise CommandError(f"unknown candidate {name}")
        return self.election.index[name]

    def active_candidate(self, name):
        candidate = self.candidate(name)
        if self.election.withdrawn[candidate]:
            raise CommandError(f"withdrawn candidate {name}")
        return candidate

    def candidate_list(self, names):
        chosen = []
        for name in names:
            candidate = self.candidate(name)
            if candidate in chosen:
                raise CommandError(f"duplicate candidate {name}")
            chosen.append(candidate)
        return chosen

    def current_tally(self):
        return Tally(self.election, self.election.active())

    def candidates(self, names):
        if len(names) == 1:
            raise CommandError("too few candidates")
        for place, name in enumerate(names):
            if name in names[:place]:
                raise CommandError(f"duplicate candidate {name}")
        self.started += 1
        self.election = Election(self.started, names)
        self.output.append(f"election {self.started}: {len(names)} candidates")

    def ballot(self, arguments):
        election = self.require_election()
        votes, ranking = arguments
        order = [] if ranking == "-" else self.candidate_list(ranking.split(">"))
        election.entries.append([BallotGroup(int(votes), order)])

    def random_ballots(self, arguments):
        election = self.require_election()
        count = int(arguments[0])
        state = int(arguments[1])
        active = election.active()
        entry = []
        for _ in range(count):
            order = list(active)
            for i in range(len(order) - 1, 0, -1):
                state = next_random(state)
                j = state % (i + 1)
                order[i], order[j] = order[j], order[i]
            state = next_random(state)
            length = state % len(order) + 1
            entry.append(BallotGroup(1, order[:length]))
        election.entries.append(entry)

    def undo(self, arguments):
        election = self.require_election()
        if not election.entries:
            raise CommandError("nothing to undo")
        election.entries.pop()

    def withdraw(self, arguments):
        election = self.require_election()
        name = arguments[0]
        candidate = self.candidate(name)
        if election.withdrawn[candidate]:
            raise CommandError(f"already withdrawn {name}")
        if len(election.active()) <= 2:
            raise CommandError("too few candidates")
        election.withdrawn[candidate] = True

    def restore(self, arguments):
        election = self.require_election()
        name = arguments[0]
        candidate = self.candidate(name)
        if not election.withdrawn[candidate]:
            raise CommandError(f"not withdrawn {name}")
        election.withdrawn[candidate] = False

    def tiebreak(self, arguments):
        election = self.require_election()
        order = self.candidate_list(arguments)
        if len(order) != len(election.names):
            raise CommandError("incomplete tiebreak")
        election.tiebreak = order

    def status(self, arguments):
        election = self.election
        withdrawn = election.withdrawn_candidates()
        return [
            f"election {election.number}",
            "active: " + name_list(election.names, election.active()),
            "withdrawn: " + (name_list(election.names, withdrawn) if withdrawn else "none"),
            "tiebreak: " + name_list(election.names, election.tiebreak),
            f"ballots: {election.total_votes()} in {len(election.entries)} entries",
        ]

    def ballots(self, arguments):
        return self.current_tally().ballot_lines()

    def profile(self, arguments):
        return self.current_tally().profile_lines()

    def pairwise(self, arguments):
        tally = self.current_tally()
        return tally.pairwise_lines(tally.pairwise)

    def exhausted(self, arguments):
        return self.current_tally().exhausted_lines()

    def summary(self, arguments):
        tally = self.current_tally()
        wins = {candidate: 0 for candidate in tally.field}
        lines = []
        for method in SUMMARY_METHODS:
            winner = tally.run(method.split(" ")).standings[0]
            wins[winner] += 1
            lines.append(f"{method}: {tally.names[winner]}")
        lines.append("wins: " + tally.value_list(wins))
        return lines

    def compare(self, arguments):
        first = self.active_candidate(arguments[0])
        second = self.active_candidate(arguments[1])
        if first == second:
            raise CommandError("same candidate")
        tally = self.current_tally()
        ahead = {first: [], second: []}
        for method in SUMMARY_METHODS:
            standings = tally.run(method.split(" ")).standings
            if standings.index(first) < standings.index(second):
                ahead[first].append(method)
            else:
                ahead[second].append(method)
        for_first = tally.pairwise[first][second]
        for_second = tally.pairwise[second][first]
        names = tally.names
        lines = [
            f"{names[first]} {for_first}, {names[second]} {for_second}, "
            f"neither {tally.total - for_first - for_second}"
        ]
        for candidate in (first, second):
            methods = ", ".join(ahead[candidate]) if ahead[candidate] else "none"
            lines.append(f"{names[candidate]} ahead: {methods}")
        return lines

    def ranking(self, arguments):
        if arguments[0] in UNRANKABLE:
            raise CommandError("not rankable")
        tally = self.current_tally()
        return [name_list(tally.names, tally.run(arguments).standings, " > ")]

    def spoilers(self, arguments):
        if arguments[0] in UNRANKABLE:
            raise CommandError("not rankable")
        election = self.election
        active = election.active()
        if len(active) < 3:
            raise CommandError("too few candidates")
        winner = Tally(election, active).run(arguments).standings[0]
        lines = ["winner: " + election.names[winner]]
        for candidate in active:
            if candidate == winner:
                continue
            field = [other for other in active if other != candidate]
            result = Tally(election, field).run(arguments).standings[0]
            changed = " (changed)" if result != winner else ""
            lines.append(f"without {election.names[candidate]}: {election.names[result]}{changed}")
        return lines

    def run_method(self, method):
        if method[0] == "STV" and int(method[1]) >= len(self.election.active()):
            raise CommandError("too many seats")
        return self.current_tally().run(method).lines

    def execute(self, line):
        command, *arguments = line.split()
        actions = {
            "CANDIDATES": self.candidates,
            "BALLOT": self.ballot,
            "RANDOM": self.random_ballots,
            "UNDO": self.undo,
            "WITHDRAW": self.withdraw,
            "RESTORE": self.restore,
            "TIEBREAK": self.tiebreak,
        }
        reports = {
            "STATUS": self.status,
            "BALLOTS": self.ballots,
            "PROFILE": self.profile,
            "PAIRWISE": self.pairwise,
            "EXHAUSTED": self.exhausted,
            "SUMMARY": self.summary,
            "COMPARE": self.compare,
            "RANKING": self.ranking,
            "SPOILERS": self.spoilers,
        }
        try:
            if command in actions:
                actions[command](arguments)
                return
            election = self.require_election()
            if command != "STATUS" and not election.entries:
                raise CommandError("no ballots")
            if command in reports:
                lines = reports[command](arguments)
            else:
                lines = self.run_method([command] + arguments)
            self.output.append("[" + line + "]")
            self.output.extend(lines)
        except CommandError as error:
            self.output.append(f"ERROR {error}")


def main():
    counter = VoteCounter()
    count = int(sys.stdin.readline())
    for _ in range(count):
        counter.execute(sys.stdin.readline().rstrip("\n"))
    if counter.output:
        sys.stdout.write("\n".join(counter.output) + "\n")


if __name__ == "__main__":
    main()
