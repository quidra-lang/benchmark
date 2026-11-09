from collections import deque
from math import gcd
import sys


TWO_SIDED = "MARKET"
ROOMMATE = "ROOMS"
HOUSING = "HOUSES"
MULTIPLIER = 48271
MODULUS = 2147483647
MAX_MATCHINGS = 50


class CommandError(Exception):
    pass


def rank(preference, other):
    if other in preference:
        return preference.index(other) + 1
    return len(preference) + 1


def acceptable(preferences, first, second):
    return second in preferences[first] and first in preferences[second]


def list_notation(items):
    return " ".join(items) if items else "-"


def partner_text(partner):
    return "*" if partner is None else partner


def first_duplicate(names):
    seen = set()
    for name in names:
        if name in seen:
            return name
        seen.add(name)
    return None


def next_random(state):
    return MULTIPLIER * state % MODULUS


def rank_summary(ranks):
    total = sum(ranks)
    first = ranks.count(1)
    if ranks:
        divisor = gcd(total, len(ranks))
        average = f"{total // divisor}/{len(ranks) // divisor}"
        hundredths = total * 100 // len(ranks)
        truncated = f"{hundredths // 100}.{hundredths % 100:02d}"
    else:
        average = "-"
        truncated = "-"
    return f"sum={total} average={average} truncated={truncated} first={first}"


class Market:
    def __init__(self, name, kind, agents):
        self.name = name
        self.kind = kind
        self.agents = agents
        self.preferences = {agent: [] for agent in agents}

    def require_agent(self, name):
        if name not in self.preferences:
            raise CommandError(f"UNKNOWN AGENT {name}")

    def position(self, agent):
        return self.agents.index(agent)

    def ordered(self, first, second):
        if self.position(second) < self.position(first):
            return second, first
        return first, second


class TwoSidedMarket(Market):
    def __init__(self, name, proposers, receivers):
        super().__init__(name, TWO_SIDED, proposers + receivers)
        self.proposers = proposers
        self.receivers = receivers
        self.capacities = {receiver: 1 for receiver in receivers}
        self.current = None
        self.source = None

    def require_proposer(self, name):
        self.require_agent(name)
        if name in self.receivers:
            raise CommandError(f"NOT PROPOSER {name}")

    def require_receiver(self, name):
        self.require_agent(name)
        if name in self.proposers:
            raise CommandError(f"NOT RECEIVER {name}")

    def possible_partners(self, agent):
        return self.receivers if agent in self.proposers else self.proposers

    def capacity(self, agent):
        if agent in self.proposers:
            return 1
        return self.capacities[agent]

    def one_to_one(self):
        return all(self.capacities[receiver] == 1 for receiver in self.receivers)

    def empty_matching(self):
        return {proposer: None for proposer in self.proposers}

    def partners(self, matching, receiver):
        return [proposer for proposer in self.proposers if matching[proposer] == receiver]

    def pair_notation(self, matching):
        return " ".join(
            f"{proposer}-{partner_text(matching[proposer])}" for proposer in self.proposers
        )

    def blocks(self, matching, proposer, receiver):
        if not acceptable(self.preferences, proposer, receiver):
            return False
        preference = self.preferences[proposer]
        if rank(preference, receiver) >= rank(preference, matching[proposer]):
            return False
        partners = self.partners(matching, receiver)
        if len(partners) < self.capacities[receiver]:
            return True
        choices = self.preferences[receiver]
        worst = max(rank(choices, partner) for partner in partners)
        return rank(choices, proposer) < worst


class RoommateMarket(Market):
    def __init__(self, name, agents):
        super().__init__(name, ROOMMATE, agents)

    def possible_partners(self, agent):
        return [other for other in self.agents if other != agent]


class HousingMarket(Market):
    def __init__(self, name, agents, houses):
        super().__init__(name, HOUSING, agents)
        self.house_order = houses
        self.houses = dict(zip(agents, houses))
        self.owners = dict(zip(houses, agents))

    def possible_partners(self, agent):
        return self.house_order

    def effective_list(self, agent):
        preference = self.preferences[agent]
        house = self.houses[agent]
        if house in preference:
            return preference[:preference.index(house) + 1]
        return preference + [house]

    def allocation_notation(self, received):
        return " ".join(
            f"{agent}-{partner_text(received.get(agent))}" for agent in self.agents
        )


class DeferredAcceptance:
    def __init__(self, market, preferences, receivers_propose):
        self.market = market
        self.preferences = preferences
        self.receivers_propose = receivers_propose
        if receivers_propose:
            self.proposing = market.receivers
            self.receiving = market.proposers
        else:
            self.proposing = market.proposers
            self.receiving = market.receivers
        self.next_position = {agent: 0 for agent in self.proposing}
        self.hold_counts = {agent: 0 for agent in self.proposing}
        self.holding = {agent: [] for agent in self.receiving}
        self.lines = []

    def able(self, agent):
        return (
            self.hold_counts[agent] < self.market.capacity(agent)
            and self.next_position[agent] < len(self.preferences[agent])
        )

    def hold(self, receiver, proposer):
        self.holding[receiver].append(proposer)
        self.hold_counts[proposer] += 1

    def release(self, receiver, proposer):
        self.holding[receiver].remove(proposer)
        self.hold_counts[proposer] -= 1

    def propose(self, proposer, receiver, queue):
        choices = self.preferences[receiver]
        held = self.holding[receiver]
        if proposer not in choices:
            self.lines.append(f"PROPOSE {proposer} {receiver} REJECT")
            return
        if len(held) < self.market.capacity(receiver):
            self.hold(receiver, proposer)
            self.lines.append(f"PROPOSE {proposer} {receiver} HOLD")
            return
        worst = max(held, key=lambda agent: rank(choices, agent))
        if rank(choices, proposer) < rank(choices, worst):
            self.release(receiver, worst)
            self.hold(receiver, proposer)
            self.lines.append(f"PROPOSE {proposer} {receiver} HOLD REJECT {worst}")
            if self.able(worst) and worst not in queue:
                queue.append(worst)
        else:
            self.lines.append(f"PROPOSE {proposer} {receiver} REJECT")

    def run(self):
        queue = deque(agent for agent in self.proposing if self.able(agent))
        while queue:
            proposer = queue.popleft()
            receiver = self.preferences[proposer][self.next_position[proposer]]
            self.next_position[proposer] += 1
            self.propose(proposer, receiver, queue)
            if self.able(proposer):
                queue.append(proposer)
        matching = self.market.empty_matching()
        for receiver, held in self.holding.items():
            for proposer in held:
                if self.receivers_propose:
                    matching[receiver] = proposer
                else:
                    matching[proposer] = receiver
        return matching


def deferred_acceptance(market, preferences, receivers_propose):
    procedure = DeferredAcceptance(market, preferences, receivers_propose)
    matching = procedure.run()
    return matching, procedure.lines


def boston_mechanism(market, preferences):
    matching = market.empty_matching()
    slots = dict(market.capacities)
    rounds = max(len(preferences[proposer]) for proposer in market.proposers)
    applications = 0
    for round_index in range(rounds):
        applied = {}
        for proposer in market.proposers:
            preference = preferences[proposer]
            if matching[proposer] is None and len(preference) > round_index:
                applied[proposer] = preference[round_index]
                applications += 1
        for receiver in market.receivers:
            for proposer in preferences[receiver]:
                if applied.get(proposer) == receiver and slots[receiver] > 0:
                    matching[proposer] = receiver
                    slots[receiver] -= 1
    return matching, applications


def cost_and_regret(market, matching):
    cost = 0
    regret = 0
    for proposer in market.proposers:
        receiver = matching[proposer]
        if receiver is None:
            continue
        for value in (
            rank(market.preferences[proposer], receiver),
            rank(market.preferences[receiver], proposer),
        ):
            cost += value
            regret = max(regret, value)
    return cost, regret


def successor(market, matching, holders, proposer):
    receiver = matching[proposer]
    if receiver is None:
        return None
    preference = market.preferences[proposer]
    for candidate in preference[preference.index(receiver) + 1:]:
        choices = market.preferences[candidate]
        if proposer not in choices:
            continue
        holder = holders.get(candidate)
        if holder is None:
            return None
        if rank(choices, proposer) < rank(choices, holder):
            return holder
    return None


def rotation_sequence(market, matching):
    holders = {
        matching[proposer]: proposer for proposer in market.proposers
        if matching[proposer] is not None
    }
    successors = {
        proposer: successor(market, matching, holders, proposer)
        for proposer in market.proposers
    }
    rotations = []
    covered = set()
    for start in market.proposers:
        if start in covered:
            continue
        path = [start]
        current = successors[start]
        while current is not None and current not in path:
            path.append(current)
            current = successors[current]
        if current == start:
            rotations.append(path)
            covered.update(path)
    return rotations


def rotation_notation(matching, rotation):
    return " ".join(f"{proposer}-{matching[proposer]}" for proposer in rotation)


def eliminate_rotation(matching, rotation):
    result = dict(matching)
    for index, proposer in enumerate(rotation):
        result[proposer] = matching[rotation[(index + 1) % len(rotation)]]
    return result


class LatticeEntry:
    def __init__(self, market, number, matching, origin, via):
        self.number = number
        self.matching = matching
        self.origin = origin
        self.via = via
        self.cost, self.regret = cost_and_regret(market, matching)


def stable_matchings(market):
    first, _ = deferred_acceptance(market, market.preferences, False)
    entries = [LatticeEntry(market, 1, first, "-", "-")]
    numbers = {}
    notations = []
    index = 0
    while index < len(entries):
        entry = entries[index]
        for rotation in rotation_sequence(market, entry.matching):
            notation = rotation_notation(entry.matching, rotation)
            if notation not in numbers:
                notations.append(notation)
                numbers[notation] = len(notations)
            eliminated = eliminate_rotation(entry.matching, rotation)
            if all(other.matching != eliminated for other in entries):
                if len(entries) == MAX_MATCHINGS:
                    raise CommandError("TOO MANY MATCHINGS")
                entries.append(LatticeEntry(
                    market, len(entries) + 1, eliminated, entry.number, numbers[notation]
                ))
        index += 1
    return entries, notations


class Irving:
    def __init__(self, market, verbose):
        self.market = market
        self.verbose = verbose
        self.working = {agent: list(market.preferences[agent]) for agent in market.agents}
        self.proposals = 0
        self.rotations = 0
        self.lines = []

    def remove_pair(self, first, second):
        if second in self.working[first]:
            self.working[first].remove(second)
        if first in self.working[second]:
            self.working[second].remove(first)

    def remove_after(self, agent, other):
        working = self.working[agent]
        for later in working[working.index(other) + 1:]:
            self.remove_pair(agent, later)

    def print_table(self):
        if self.verbose:
            for agent in self.market.agents:
                self.lines.append(f"TABLE {agent} {list_notation(self.working[agent])}")

    def empty_agent(self):
        for agent in self.market.agents:
            if not self.working[agent]:
                return agent
        return None

    def phase_one(self):
        held = {agent: None for agent in self.market.agents}
        queue = deque(self.market.agents)
        while queue:
            proposer = queue.popleft()
            receiver = self.working[proposer][0]
            self.proposals += 1
            if held[receiver] is not None:
                queue.append(held[receiver])
            held[receiver] = proposer
            self.remove_after(receiver, proposer)
            failed = self.empty_agent()
            if failed is not None:
                return failed
        return None

    def find_rotation(self):
        start = next(agent for agent in self.market.agents if len(self.working[agent]) >= 2)
        sequence = [start]
        while True:
            second = self.working[sequence[-1]][1]
            following = self.working[second][-1]
            if following in sequence:
                break
            sequence.append(following)
        cycle = sequence[sequence.index(following):]
        return [(agent, self.working[agent][0]) for agent in cycle]

    def eliminate(self, rotation):
        removals = []
        for index, (agent, _) in enumerate(rotation):
            target = rotation[(index + 1) % len(rotation)][1]
            working = self.working[target]
            for later in working[working.index(agent) + 1:]:
                removals.append((target, later))
        for first, second in removals:
            self.remove_pair(first, second)

    def phase_two(self):
        while any(len(self.working[agent]) >= 2 for agent in self.market.agents):
            rotation = self.find_rotation()
            self.rotations += 1
            pairs = " ".join(f"{agent}-{front}" for agent, front in rotation)
            self.lines.append(f"ROTATION {self.rotations} {pairs}")
            self.eliminate(rotation)
            self.print_table()
            failed = self.empty_agent()
            if failed is not None:
                return failed
        return None

    def solve(self):
        failed = self.phase_one()
        if failed is None:
            self.print_table()
            failed = self.phase_two()
        if failed is not None:
            self.lines.append(f"NO STABLE MATCHING {failed}")
            return
        pairs = []
        for agent in self.market.agents:
            partner = self.working[agent][0]
            if self.market.position(agent) < self.market.position(partner):
                pairs.append(f"{agent}-{partner}")
        self.lines.append("MATCHING " + " ".join(pairs))


def pointed_agent(market, agent, remaining):
    for house in market.effective_list(agent):
        owner = market.owners[house]
        if owner in remaining:
            return owner
    return None


def top_trading_cycles(market):
    remaining = list(market.agents)
    received = {}
    cycles = []
    while remaining:
        points = {agent: pointed_agent(market, agent, remaining) for agent in remaining}
        visited = []
        current = remaining[0]
        while current not in visited:
            visited.append(current)
            current = points[current]
        cycle = visited[visited.index(current):]
        for agent in cycle:
            received[agent] = market.houses[points[agent]]
        cycles.append(cycle)
        remaining = [agent for agent in remaining if agent not in cycle]
    return cycles, received


def serial_dictatorship(market, order):
    remaining = list(market.house_order)
    received = {}
    for agent in order:
        for house in market.preferences[agent]:
            if house in remaining:
                received[agent] = house
                remaining.remove(house)
                break
    return received


class MatchingLab:
    def __init__(self):
        self.markets = {}
        self.output = []
        self.handlers = {
            "MARKET": self.create_market,
            "ROOMS": self.create_rooms,
            "HOUSES": self.create_houses,
            "RANDOM": self.create_random,
            "PREF": self.set_preference,
            "CAPACITY": self.set_capacity,
            "SHOW": self.show,
            "GS": self.gale_shapley,
            "GSR": self.gale_shapley_receivers,
            "CHECK": self.check,
            "LATTICE": self.lattice,
            "EGALITARIAN": self.egalitarian,
            "MINREGRET": self.minimum_regret,
            "HR": self.hospitals_residents,
            "ROOMMATES": self.roommates,
            "TTC": self.trading_cycles,
            "SERIAL": self.serial,
            "BOSTON": self.boston,
            "MANIPULATE": self.manipulate,
            "STATS": self.stats,
        }

    def emit(self, *parts):
        self.output.append(" ".join(str(part) for part in parts))

    def require_new(self, name):
        if name in self.markets:
            raise CommandError(f"DUPLICATE MARKET {name}")

    def market(self, name, kind=None):
        if name not in self.markets:
            raise CommandError(f"UNKNOWN MARKET {name}")
        market = self.markets[name]
        if kind is not None and market.kind != kind:
            raise CommandError(f"WRONG TYPE {name}")
        return market

    def create_market(self, arguments):
        name = arguments[0]
        self.require_new(name)
        separator = arguments.index("|")
        proposers = arguments[1:separator]
        receivers = arguments[separator + 1:]
        duplicate = first_duplicate(proposers + receivers)
        if duplicate is not None:
            raise CommandError(f"DUPLICATE AGENT {duplicate}")
        self.markets[name] = TwoSidedMarket(name, proposers, receivers)
        self.emit("MARKET", name, f"proposers={len(proposers)}", f"receivers={len(receivers)}")

    def create_rooms(self, arguments):
        name, *agents = arguments
        self.require_new(name)
        duplicate = first_duplicate(agents)
        if duplicate is not None:
            raise CommandError(f"DUPLICATE AGENT {duplicate}")
        self.markets[name] = RoommateMarket(name, agents)
        self.emit("ROOMS", name, f"agents={len(agents)}")

    def create_houses(self, arguments):
        name = arguments[0]
        self.require_new(name)
        agents = []
        houses = []
        for word in arguments[1:]:
            agent, house = word.split(":")
            if agent in agents:
                raise CommandError(f"DUPLICATE AGENT {agent}")
            if house in houses:
                raise CommandError(f"DUPLICATE HOUSE {house}")
            agents.append(agent)
            houses.append(house)
        self.markets[name] = HousingMarket(name, agents, houses)
        self.emit("HOUSES", name, f"agents={len(agents)}")

    def create_random(self, arguments):
        name = arguments[0]
        size = int(arguments[1])
        seed = int(arguments[2])
        self.require_new(name)
        proposers = [f"P{number}" for number in range(1, size + 1)]
        receivers = [f"R{number}" for number in range(1, size + 1)]
        market = TwoSidedMarket(name, proposers, receivers)
        state = seed
        for agent in market.agents:
            order = list(market.possible_partners(agent))
            for i in range(size, 1, -1):
                state = next_random(state)
                j = state % i + 1
                order[i - 1], order[j - 1] = order[j - 1], order[i - 1]
            market.preferences[agent] = order
        self.markets[name] = market
        self.emit("RANDOM", name, f"n={size}", f"seed={seed}")

    def set_preference(self, arguments):
        name, agent, *choices = arguments
        market = self.market(name)
        market.require_agent(agent)
        possible = market.possible_partners(agent)
        for index, choice in enumerate(choices):
            if choice not in possible:
                raise CommandError(f"BAD CHOICE {choice}")
            if choice in choices[:index]:
                raise CommandError(f"DUPLICATE CHOICE {choice}")
        market.preferences[agent] = choices
        if market.kind == TWO_SIDED:
            market.current = None
        self.emit("PREF", name, agent, f"length={len(choices)}")

    def set_capacity(self, arguments):
        name, receiver, amount = arguments
        market = self.market(name, TWO_SIDED)
        market.require_receiver(receiver)
        market.capacities[receiver] = int(amount)
        market.current = None
        self.emit("CAPACITY", name, receiver, int(amount))

    def show(self, arguments):
        name = arguments[0]
        market = self.market(name)
        preferences = market.preferences
        if market.kind == TWO_SIDED:
            self.emit(
                "SHOW", name, "MARKET", f"proposers={len(market.proposers)}",
                f"receivers={len(market.receivers)}",
            )
            for proposer in market.proposers:
                self.emit("PROPOSER", proposer, list_notation(preferences[proposer]))
            for receiver in market.receivers:
                self.emit(
                    "RECEIVER", receiver, f"cap={market.capacities[receiver]}",
                    list_notation(preferences[receiver]),
                )
            self.emit("CURRENT", "-" if market.current is None else market.source)
        elif market.kind == ROOMMATE:
            self.emit("SHOW", name, "ROOMS", f"agents={len(market.agents)}")
            for agent in market.agents:
                self.emit("AGENT", agent, list_notation(preferences[agent]))
        else:
            self.emit("SHOW", name, "HOUSES", f"agents={len(market.agents)}")
            for agent in market.agents:
                self.emit(
                    "AGENT", agent, f"house={market.houses[agent]}",
                    list_notation(preferences[agent]),
                )

    def run_deferred_acceptance(self, arguments, command, receivers_propose):
        name = arguments[0]
        market = self.market(name, TWO_SIDED)
        matching, lines = deferred_acceptance(market, market.preferences, receivers_propose)
        market.current = matching
        market.source = command
        self.emit(command, name, f"proposals={len(lines)}")
        if len(arguments) == 2:
            self.output.extend(lines)
        self.emit("MATCHING", market.pair_notation(matching))

    def gale_shapley(self, arguments):
        self.run_deferred_acceptance(arguments, "GS", False)

    def gale_shapley_receivers(self, arguments):
        self.run_deferred_acceptance(arguments, "GSR", True)

    def report_check(self, name, unacceptable, blocking):
        if not unacceptable and not blocking:
            self.emit("CHECK", name, "STABLE")
            return
        self.emit(
            "CHECK", name, "UNSTABLE", f"unacceptable={len(unacceptable)}",
            f"blocking={len(blocking)}",
        )
        for first, second in unacceptable:
            self.emit("UNACCEPTABLE", first, second)
        for first, second in blocking:
            self.emit("BLOCKING", first, second)

    def check_two_sided(self, market, pairs):
        proposers = []
        receivers = []
        for proposer, receiver in pairs:
            market.require_proposer(proposer)
            market.require_receiver(receiver)
            if proposer in proposers:
                raise CommandError(f"DUPLICATE AGENT {proposer}")
            proposers.append(proposer)
            receivers.append(receiver)
            if receivers.count(receiver) > market.capacities[receiver]:
                raise CommandError(f"OVER CAPACITY {receiver}")
        matching = market.empty_matching()
        for proposer, receiver in pairs:
            matching[proposer] = receiver
        unacceptable = [
            (proposer, matching[proposer]) for proposer in market.proposers
            if matching[proposer] is not None
            and not acceptable(market.preferences, proposer, matching[proposer])
        ]
        blocking = [
            (proposer, receiver)
            for proposer in market.proposers for receiver in market.receivers
            if matching[proposer] != receiver and market.blocks(matching, proposer, receiver)
        ]
        self.report_check(market.name, unacceptable, blocking)

    def check_roommates(self, market, pairs):
        seen = []
        for first, second in pairs:
            market.require_agent(first)
            market.require_agent(second)
            if first in seen:
                raise CommandError(f"DUPLICATE AGENT {first}")
            if second == first or second in seen:
                raise CommandError(f"DUPLICATE AGENT {second}")
            seen.extend((first, second))
        partner = {agent: None for agent in market.agents}
        for first, second in pairs:
            partner[first] = second
            partner[second] = first
        preferences = market.preferences
        unacceptable = [
            market.ordered(first, second) for first, second in pairs
            if not acceptable(preferences, first, second)
        ]
        unacceptable.sort(key=lambda pair: (market.position(pair[0]), market.position(pair[1])))
        blocking = []
        for index, first in enumerate(market.agents):
            for second in market.agents[index + 1:]:
                if partner[first] == second or not acceptable(preferences, first, second):
                    continue
                first_gains = (
                    rank(preferences[first], second) < rank(preferences[first], partner[first])
                )
                second_gains = (
                    rank(preferences[second], first) < rank(preferences[second], partner[second])
                )
                if first_gains and second_gains:
                    blocking.append((first, second))
        self.report_check(market.name, unacceptable, blocking)

    def check(self, arguments):
        name = arguments[0]
        market = self.market(name)
        if market.kind == HOUSING:
            raise CommandError(f"WRONG TYPE {name}")
        pairs = [tuple(word.split("-")) for word in arguments[1:]]
        if market.kind == TWO_SIDED:
            self.check_two_sided(market, pairs)
        else:
            self.check_roommates(market, pairs)

    def lattice_entries(self, name):
        market = self.market(name, TWO_SIDED)
        if not market.one_to_one():
            raise CommandError("NOT ONE TO ONE")
        entries, notations = stable_matchings(market)
        return market, entries, notations

    def lattice(self, arguments):
        name = arguments[0]
        market, entries, notations = self.lattice_entries(name)
        self.emit("LATTICE", name, f"matchings={len(entries)}", f"rotations={len(notations)}")
        for entry in entries:
            self.emit(
                "MATCHING", entry.number, f"from={entry.origin}", f"via={entry.via}",
                f"cost={entry.cost}", f"regret={entry.regret}",
                market.pair_notation(entry.matching),
            )
        for number, notation in enumerate(notations, 1):
            self.emit("ROTATION", number, notation)

    def egalitarian(self, arguments):
        name = arguments[0]
        market, entries, _ = self.lattice_entries(name)
        best = min(entries, key=lambda entry: entry.cost)
        market.current = best.matching
        market.source = "EGALITARIAN"
        self.emit("EGALITARIAN", name, f"matching={best.number}", f"cost={best.cost}")
        self.emit("MATCHING", market.pair_notation(best.matching))

    def minimum_regret(self, arguments):
        name = arguments[0]
        market, entries, _ = self.lattice_entries(name)
        best = min(entries, key=lambda entry: entry.regret)
        market.current = best.matching
        market.source = "MINREGRET"
        self.emit("MINREGRET", name, f"matching={best.number}", f"regret={best.regret}")
        self.emit("MATCHING", market.pair_notation(best.matching))

    def hospitals_residents(self, arguments):
        name = arguments[0]
        market = self.market(name, TWO_SIDED)
        resident, _ = deferred_acceptance(market, market.preferences, False)
        hospital, _ = deferred_acceptance(market, market.preferences, True)
        self.emit(
            "HR", name, f"residents={len(market.proposers)}",
            f"hospitals={len(market.receivers)}",
        )
        self.emit("RESIDENT-OPTIMAL", market.pair_notation(resident))
        self.emit("HOSPITAL-OPTIMAL", market.pair_notation(hospital))
        unmatched = [proposer for proposer in market.proposers if resident[proposer] is None]
        self.emit("UNMATCHED", list_notation(unmatched))
        holds = all(
            (resident[proposer] is None) == (hospital[proposer] is None)
            for proposer in market.proposers
        )
        for receiver in market.receivers:
            capacity = market.capacities[receiver]
            resident_partners = market.partners(resident, receiver)
            hospital_partners = market.partners(hospital, receiver)
            same = resident_partners == hospital_partners
            self.emit(
                "HOSPITAL", receiver, f"cap={capacity}",
                f"resident={len(resident_partners)}", f"hospital={len(hospital_partners)}",
                "same=" + ("YES" if same else "NO"),
            )
            if len(resident_partners) != len(hospital_partners):
                holds = False
            if len(resident_partners) < capacity and not same:
                holds = False
        self.emit("RURAL", "HOLDS" if holds else "FAILS")

    def roommates(self, arguments):
        name = arguments[0]
        market = self.market(name, ROOMMATE)
        for agent in market.agents:
            if len(market.preferences[agent]) < len(market.agents) - 1:
                raise CommandError(f"INCOMPLETE {agent}")
        procedure = Irving(market, len(arguments) == 2)
        procedure.solve()
        self.emit("ROOMMATES", name, f"proposals={procedure.proposals}")
        self.output.extend(procedure.lines)

    def trading_cycles(self, arguments):
        name = arguments[0]
        market = self.market(name, HOUSING)
        cycles, received = top_trading_cycles(market)
        self.emit("TTC", name, f"cycles={len(cycles)}")
        for number, cycle in enumerate(cycles, 1):
            self.emit("CYCLE", number, *(f"{agent}:{received[agent]}" for agent in cycle))
        self.emit("ALLOCATION", market.allocation_notation(received))

    def serial(self, arguments):
        name, *order = arguments
        market = self.market(name, HOUSING)
        for index, agent in enumerate(order):
            market.require_agent(agent)
            if agent in order[:index]:
                raise CommandError(f"DUPLICATE AGENT {agent}")
        if len(order) != len(market.agents):
            raise CommandError("BAD ORDER")
        received = serial_dictatorship(market, order)
        worse = [
            agent for agent in market.agents
            if agent not in received or received[agent] not in market.effective_list(agent)
        ]
        self.emit("SERIAL", name, f"assigned={len(received)}")
        self.emit("ALLOCATION", market.allocation_notation(received))
        self.emit("WORSE", list_notation(worse))

    def boston(self, arguments):
        name = arguments[0]
        market = self.market(name, TWO_SIDED)
        matching, applications = boston_mechanism(market, market.preferences)
        market.current = matching
        market.source = "BOSTON"
        self.emit("BOSTON", name, f"applications={applications}")
        self.emit("MATCHING", market.pair_notation(matching))

    def manipulate(self, arguments):
        name, agent = arguments
        market = self.market(name, TWO_SIDED)
        market.require_proposer(agent)
        truth = market.preferences[agent]
        boston_base = boston_mechanism(market, market.preferences)[0][agent]
        gs_base = deferred_acceptance(market, market.preferences, False)[0][agent]
        self.emit(
            "MANIPULATE", name, agent, f"boston={partner_text(boston_base)}",
            f"gs={partner_text(gs_base)}", f"swaps={max(len(truth) - 1, 0)}",
        )
        improved = False
        for i in range(1, len(truth)):
            report = list(truth)
            report[i - 1], report[i] = report[i], report[i - 1]
            preferences = dict(market.preferences)
            preferences[agent] = report
            boston_result = boston_mechanism(market, preferences)[0][agent]
            gs_result = deferred_acceptance(market, preferences, False)[0][agent]
            if rank(truth, boston_result) < rank(truth, boston_base):
                self.emit(
                    "IMPROVE", "BOSTON", i, truth[i - 1], truth[i], f"result={boston_result}"
                )
                improved = True
            if rank(truth, gs_result) < rank(truth, gs_base):
                self.emit("IMPROVE", "GS", i, truth[i - 1], truth[i], f"result={gs_result}")
                improved = True
        if not improved:
            self.emit("NO IMPROVEMENT")

    def stats(self, arguments):
        name = arguments[0]
        market = self.market(name, TWO_SIDED)
        if market.current is None:
            raise CommandError("NO MATCHING")
        matching = market.current
        preferences = market.preferences
        pairs = [
            (proposer, matching[proposer]) for proposer in market.proposers
            if matching[proposer] is not None
        ]
        proposer_ranks = [rank(preferences[proposer], receiver) for proposer, receiver in pairs]
        receiver_ranks = [rank(preferences[receiver], proposer) for proposer, receiver in pairs]
        unmatched_proposers = len(market.proposers) - len(pairs)
        unmatched_receivers = sum(
            not market.partners(matching, receiver) for receiver in market.receivers
        )
        self.emit("STATS", name, f"source={market.source}", f"pairs={len(pairs)}")
        self.emit("PROPOSERS", rank_summary(proposer_ranks), f"unmatched={unmatched_proposers}")
        self.emit("RECEIVERS", rank_summary(receiver_ranks), f"unmatched={unmatched_receivers}")

    def execute(self, line):
        command, *arguments = line.split(" ")
        try:
            self.handlers[command](arguments)
        except CommandError as error:
            self.emit("ERROR", error)


def main():
    lab = MatchingLab()
    count = int(sys.stdin.readline())
    for _ in range(count):
        lab.execute(sys.stdin.readline().rstrip("\n"))
    sys.stdout.write("\n".join(lab.output) + "\n")


if __name__ == "__main__":
    main()
