"""Compare exact combinatorial, ascending, single-item and ad-slot auctions."""

import re
from collections import Counter
from fractions import Fraction
from types import SimpleNamespace

from auctions import candidates, dutch, english, value_of
from bids_io import Bid, read_inputs
from payments import blocking_coalitions, coalition_welfares, critical_payments, gsp_price, slot_vcg_payment, vcg_payments
from report import bundle, fraction, write_reports
from wdp_solver import greedy_order, greedy_select, solve


BID_FORM = re.compile(r"[a-z]+(?:\+[a-z]+)*:(?:0|[1-9][0-9]{0,4})")
CTR_FORM = re.compile(r"[1-9][0-9]*/[1-9][0-9]*")
FORMATS = ("first_price", "second_price", "english", "dutch", "all_pay")
OUTCOMES = ("vcg", "greedy", "critical", "saa")


def numbers(values):
    return "+".join(map(str, sorted(values))) or "-"


def allocation(bids, items, reserves):
    winning = sorted(bids, key=lambda bid: bid.number)
    owners = {item: bid.bidder for bid in winning for item in bid.bundle}
    unsold = [item for item in items if item not in owners]
    accepted = sum(bid.amount for bid in winning)
    retained = sum(reserves[item] for item in unsold)
    return SimpleNamespace(winning=winning, owners=owners, unsold=unsold,
                           accepted=accepted, retained=retained, welfare=accepted + retained)


def duplicate_name(participants):
    seen = set()
    for participant in participants:
        if participant.name in seen:
            return participant.name
        seen.add(participant.name)
    return None


class CombinatorialAuction:
    def __init__(self, raw, reserves, parameters):
        self.name, self.items, self.reserves, self.parameters = raw.name, raw.items, reserves, parameters
        self.bidders, self.valid, self.eligible, self.below, self.rejected = [], [], [], [], []
        self.bid_count = 0
        self.validate(raw.lines)
        self.names = [bidder.name for bidder in self.bidders]
        self.optimal = solve(self.items, reserves, self.eligible)
        self.exact = allocation(self.optimal.winning, self.items, reserves)
        self.order = greedy_order(self.eligible)
        self.greedy = allocation(greedy_select(self.order), self.items, reserves)
        self.critical = critical_payments(self.order, self.greedy.winning, reserves)
        self.vcg_details = vcg_payments(self.items, reserves, self.eligible, self.optimal, self.names)
        self.values = {name: sum(bid.amount for bid in self.exact.winning if bid.bidder == name) for name in self.names}
        self.greedy_values = {name: sum(bid.amount for bid in self.greedy.winning if bid.bidder == name) for name in self.names}
        self.vcg_paid = {name: self.vcg_details[name][0] if name in self.vcg_details else 0 for name in self.names}
        self.vcg_utilities = {name: self.values[name] - self.vcg_paid[name] for name in self.names}
        self.critical_paid = {name: sum(self.critical[bid.number][0] for bid in self.greedy.winning if bid.bidder == name)
                              for name in self.names}
        self.critical_utilities = {name: self.greedy_values[name] - self.critical_paid[name] for name in self.names}
        self.vcg_revenue = sum(self.vcg_paid.values())
        self.critical_revenue = sum(self.critical_paid.values())
        self.saa = self.ascending()

    def bid_error(self, text, bidder):
        if BID_FORM.fullmatch(text) is None:
            return "malformed bid", None, None
        names_text, amount_text = text.split(":")
        item_names, seen = names_text.split("+"), set()
        for name in item_names:
            if name not in self.reserves:
                return "unknown item " + name, None, None
            if name not in self.items:
                return "item not offered " + name, None, None
            if name in seen:
                return "duplicate item " + name, None, None
            seen.add(name)
        if len(item_names) > self.parameters["max_bundle_size"]:
            return "bundle too large", None, None
        amount, items = int(amount_text), frozenset(item_names)
        if amount == 0:
            return "zero value", None, None
        for earlier in bidder.valid:
            if earlier.bundle == items:
                return "duplicate bundle " + str(earlier.number), None, None
        if len(bidder.valid) >= self.parameters["max_bids_per_bidder"]:
            return "too many bids", None, None
        return None, items, amount

    def validate(self, lines):
        seen = set()
        for name, language, bid_strings in lines:
            line_error = "duplicate bidder" if name in seen else None
            seen.add(name)
            if line_error is None and language not in ("XOR", "OR"):
                line_error = "bad language " + language
            bidder = None
            if line_error is None:
                bidder = SimpleNamespace(name=name, language=language, valid=[], eligible=[])
                self.bidders.append(bidder)
            for text in bid_strings:
                self.bid_count += 1
                if line_error is not None:
                    self.rejected.append((self.bid_count, name, line_error))
                    continue
                error, items, amount = self.bid_error(text, bidder)
                if error is not None:
                    self.rejected.append((self.bid_count, name, error))
                    continue
                bid = Bid(self.bid_count, name, items, amount, language == "XOR")
                bidder.valid.append(bid)
                self.valid.append(bid)
                reserve = sum(self.reserves[item] for item in items)
                if amount >= reserve:
                    bidder.eligible.append(bid)
                    self.eligible.append(bid)
                else:
                    self.below.append((bid, reserve))

    def ascending(self):
        increment = self.parameters["saa_increment"]
        choices = {bidder.name: candidates(bidder.valid, bidder.language == "XOR") for bidder in self.bidders}
        eligibility = {name: max((len(candidate.bundle) for candidate in choices[name]), default=0) for name in self.names}
        prices = {item: self.reserves[item] for item in self.items}
        holders = {item: None for item in self.items}
        bid_counts, bid_rounds, last_rounds = Counter(), Counter(), Counter()
        state = self.parameters["seed"]
        lines = [f"AUCTION {self.name} increment {increment}"]
        for round_number in range(1, self.parameters["round_cap"] + 1):
            activities, new_by_bidder = {}, {}
            new_by_item = {item: [] for item in self.items}
            for name in self.names:
                held = {item for item in self.items if holders[item] == name}
                asking = {item: prices[item] + (increment if holders[item] not in (None, name) else 0) for item in self.items}
                chosen, best_surplus = None, 0
                for candidate in choices[name]:
                    if len(candidate.bundle | held) <= eligibility[name]:
                        surplus = candidate.value - sum(asking[item] for item in candidate.bundle)
                        if surplus > best_surplus:
                            chosen, best_surplus = candidate, surplus
                demanded = chosen.bundle if chosen is not None else set()
                activities[name] = len(demanded | held)
                new_by_bidder[name] = demanded - held
                for item in self.items:
                    if item in new_by_bidder[name]:
                        new_by_item[item].append(name)
            demand = sum(len(items) for items in new_by_bidder.values())
            if demand:
                line = f"ROUND {round_number} demand {demand}"
                line += "".join(" " + name + ":" + bundle(new_by_bidder[name], self.items)
                                for name in self.names if new_by_bidder[name])
                lines.append(line)
                for item in self.items:
                    bidders = new_by_item[item]
                    if not bidders:
                        continue
                    if len(bidders) >= 2:
                        state = 48271 * state % 2147483647
                        winner = bidders[state % len(bidders)]
                    else:
                        winner = bidders[0]
                    if holders[item] is not None:
                        prices[item] += increment
                    holders[item] = winner
                    bid_counts[item] += len(bidders)
                    bid_rounds[item] += 1
                    last_rounds[item] = round_number
                lines.append("STANDING" + "".join(f" {item}={prices[item]}@{holders[item] or '-'}" for item in self.items))
            else:
                lines.append(f"ROUND {round_number} none")
            changed = []
            for name in self.names:
                if activities[name] < eligibility[name]:
                    eligibility[name] = activities[name]
                    changed.append(f"{name}={eligibility[name]}")
            if changed:
                lines.append("ELIGIBILITY " + " ".join(changed))
            if demand == 0 or round_number == self.parameters["round_cap"]:
                reason = "quiet" if demand == 0 else "cap"
                break
        lines.append(f"END rounds {round_number} {reason}")
        for item in self.items:
            if holders[item] is None:
                lines.append(f"ITEM {item} unsold reserve {self.reserves[item]}")
            else:
                lines.append(f"ITEM {item} price {prices[item]} holder {holders[item]} bids {bid_counts[item]} "
                             f"rounds {bid_rounds[item]} last {last_rounds[item]}")
        payments, utilities = {}, {}
        values_total, exposure, exposed = 0, 0, 0
        for name in self.names:
            won = {item for item in self.items if holders[item] == name}
            paid = sum(prices[item] for item in won)
            value = value_of(choices[name], won)
            utility = value - paid
            payments[name], utilities[name] = paid, utility
            values_total += value
            if utility < 0:
                exposure -= utility
                exposed += 1
            line = (f"BIDDER {name} won {bundle(won, self.items)} paid {paid} value {value} "
                    f"utility {utility} eligibility {eligibility[name]}")
            lines.append(line + (" exposed" if utility < 0 else ""))
        revenue = sum(payments.values())
        retained = sum(self.reserves[item] for item in self.items if holders[item] is None)
        welfare = values_total + retained
        efficiency = Fraction(welfare, self.exact.welfare)
        lines.append(f"TOTAL revenue {revenue} welfare {welfare} efficiency {fraction(efficiency)} exposure {exposure} exposed {exposed}")
        return SimpleNamespace(lines=lines, payments=payments, utilities=utilities, revenue=revenue,
                               retained=retained, welfare=welfare, efficiency=efficiency, rounds=round_number,
                               reason=reason, exposure=exposure, exposed=exposed)

    def wdp_report(self):
        lines = [f"AUCTION {self.name} items {len(self.items)} bidders {len(self.bidders)} bids {self.bid_count} "
                 f"valid {len(self.valid)} eligible {len(self.eligible)}"]
        for bidder in self.bidders:
            lines.append(f"BIDDER {bidder.name} {bidder.language} valid {len(bidder.valid)} eligible {len(bidder.eligible)}")
        for number, name, reason in self.rejected:
            lines.append(f"REJECT {number} {name} {reason}")
        for bid, reserve in self.below:
            lines.append(f"BELOW_RESERVE {bid.number} {bid.bidder} value {bid.amount} reserve {reserve}")
        for item, share, source in self.optimal.shares:
            lines.append(f"SHARE {item} {fraction(share)} " + ("reserve" if source is None else f"bid {source}"))
        lines.append("ROOT_BOUND " + fraction(self.optimal.bound))
        for nodes, welfare, chosen in self.optimal.improvements:
            lines.append(f"IMPROVE {nodes} welfare {welfare} bids {numbers(chosen)}")
        result = self.exact
        lines.append(f"OPTIMAL welfare {result.welfare} accepted {result.accepted} retained {result.retained} winners {len(result.winning)}")
        for bid in result.winning:
            lines.append(f"WIN {bid.number} {bid.bidder} {bundle(bid.bundle, self.items)} {bid.amount}")
        lines.append("UNSOLD " + (" ".join(result.unsold) if result.unsold else "-"))
        search = self.optimal
        lines.append(f"SEARCH nodes {search.nodes} pruned {search.pruned} leaves {search.leaves} improvements {len(search.improvements)}")
        lines.append("GREEDY_ORDER " + (" ".join(str(bid.number) for bid in self.order) if self.order else "-"))
        result = self.greedy
        lines.append(f"GREEDY welfare {result.welfare} accepted {result.accepted} retained {result.retained} "
                     f"winners {len(result.winning)} efficiency {fraction(Fraction(result.welfare, self.exact.welfare))}")
        for bid in result.winning:
            critical, rival = self.critical[bid.number]
            rival_number = str(rival.number) if rival is not None else "-"
            lines.append(f"GWIN {bid.number} {bid.bidder} {bundle(bid.bundle, self.items)} {bid.amount} "
                         f"critical {critical} against {rival_number}")
        lines.append("GUNSOLD " + (" ".join(result.unsold) if result.unsold else "-"))
        for item in self.items:
            demand = sum(item in bid.bundle for bid in self.eligible)
            lines.append(f"ITEM {item} reserve {self.reserves[item]} demand {demand} "
                         f"optimal {self.exact.owners.get(item, '-')} greedy {self.greedy.owners.get(item, '-')}")
        return lines

    def vcg_report(self):
        lines = [f"AUCTION {self.name} welfare {self.exact.welfare}"]
        for name in self.names:
            if name not in self.vcg_details:
                lines.append(f"BIDDER {name} lost")
                continue
            paid, alternative = self.vcg_details[name]
            won = numbers(bid.number for bid in self.exact.winning if bid.bidder == name)
            lines.append(f"BIDDER {name} won {won} value {self.values[name]} without {alternative.welfare} "
                         f"alternative {numbers(alternative.numbers)} payment {paid} utility {self.vcg_utilities[name]}")
        lines.append(f"TOTAL revenue {self.vcg_revenue} pay_as_bid {self.exact.accepted} retained {self.exact.retained} "
                     f"seller {self.vcg_revenue + self.exact.retained} bidders {sum(self.vcg_utilities.values())}")
        for name in self.names:
            lines.append(f"PAYMENTS {name} vcg {self.vcg_paid[name]} pay_as_bid {self.values[name]} "
                         f"greedy {self.greedy_values[name]} critical {self.critical_paid[name]} saa {self.saa.payments[name]}")
        for name in self.names:
            lines.append(f"UTILITIES {name} vcg {self.vcg_utilities[name]} critical {self.critical_utilities[name]} saa {self.saa.utilities[name]}")
        return lines

    def core_report(self):
        lines, counts = [f"AUCTION {self.name} bidders {len(self.bidders)}"], Counter()
        if len(self.bidders) > self.parameters["core_max_bidders"]:
            lines.append("SKIPPED")
            counts["skipped"] = 1
            return lines, counts
        counts["checked"] = 1
        coalitions = coalition_welfares(self.items, self.reserves, self.eligible, self.names)
        lines.append("COALITIONS " + str(len(coalitions)))
        outcomes = [("vcg", self.vcg_revenue + self.exact.retained, self.vcg_utilities),
                    ("greedy", self.greedy.welfare, {name: 0 for name in self.names}),
                    ("critical", self.critical_revenue + self.greedy.retained, self.critical_utilities),
                    ("saa", self.saa.revenue + self.saa.retained, self.saa.utilities)]
        for name, seller, utilities in outcomes:
            lines.append(f"OUTCOME {name} seller {seller} utilities " + " ".join(str(utilities[bidder]) for bidder in self.names))
            blocking, minimal = blocking_coalitions(coalitions, seller, utilities)
            for record in minimal:
                coalition = record.coalition
                members = "+".join(coalition.members) or "-"
                lines.append(f"BLOCK {members} welfare {coalition.welfare} payoff {record.payoff} "
                             f"deficit {record.deficit} bids {numbers(coalition.numbers)}")
            if not blocking:
                lines.append("RESULT core")
                counts[name] += 1
            else:
                worst = max(blocking, key=lambda record: record.deficit)
                members = "+".join(worst.coalition.members) or "-"
                lines.append(f"RESULT blocked {len(blocking)} minimal {len(minimal)} max_deficit {worst.deficit} by {members}")
        return lines, counts


class Laboratory:
    def __init__(self):
        self.reserves, self.raw_auctions, self.groups, self.parameters = read_inputs()
        self.wdp_lines, self.vcg_lines, self.core_lines, self.ascending_lines, self.single_lines = [], [], [], [], []
        self.summary_lines = ["mechanism,revenue,welfare,efficiency"]
        self.wdp_totals, self.vcg_totals, self.core_totals, self.ascending_totals = Counter(), Counter(), Counter(), Counter()
        self.group_totals = Counter()

    def summary_row(self, name, mechanism, revenue, welfare, efficiency):
        self.summary_lines.append(f"{name}/{mechanism},{fraction(revenue)},{fraction(welfare)},{fraction(efficiency)}")

    def process_auctions(self):
        for name in self.parameters["run"]:
            auction = CombinatorialAuction(self.raw_auctions[name], self.reserves, self.parameters)
            self.wdp_lines.extend(auction.wdp_report())
            self.vcg_lines.extend(auction.vcg_report())
            core_lines, core_counts = auction.core_report()
            self.core_lines.extend(core_lines)
            self.core_totals.update(core_counts)
            self.ascending_lines.extend(auction.saa.lines)
            self.wdp_totals.update({"auctions": 1, "bids": auction.bid_count, "valid": len(auction.valid),
                                    "eligible": len(auction.eligible), "nodes": auction.optimal.nodes,
                                    "greedy_optimal": int(auction.greedy.welfare == auction.exact.welfare)})
            revenues = {"vcg": auction.vcg_revenue, "pay_as_bid": auction.exact.accepted,
                        "greedy": auction.greedy.accepted, "critical": auction.critical_revenue, "saa": auction.saa.revenue}
            self.vcg_totals.update(revenues)
            self.ascending_totals.update({"auctions": 1, "rounds": auction.saa.rounds,
                                          "capped": int(auction.saa.reason == "cap"), "exposed": auction.saa.exposed,
                                          "exposure": auction.saa.exposure})
            for mechanism in ("vcg", "pay_as_bid", "greedy", "critical", "saa"):
                welfare = auction.exact.welfare if mechanism in ("vcg", "pay_as_bid") else auction.greedy.welfare
                if mechanism == "saa":
                    welfare = auction.saa.welfare
                self.summary_row(name, mechanism, revenues[mechanism], welfare, Fraction(welfare, auction.exact.welfare))

    def validate_lot(self, group):
        participants = group.participants
        if not participants:
            return "no bidders"
        duplicate = duplicate_name(participants)
        if duplicate is not None:
            return "duplicate bidder " + duplicate
        for participant in participants:
            if participant.bid > participant.value:
                return "bid above value " + participant.name
        return None

    def validate_slots(self, group):
        rates = []
        for text in group.arguments:
            if CTR_FORM.fullmatch(text) is None:
                return "bad ctr " + text, None
            numerator, denominator = map(int, text.split("/"))
            rate = Fraction(numerator, denominator)
            if rate > 1 or rates and rate >= rates[-1]:
                return "bad ctr " + text, None
            rates.append(rate)
        if not group.participants:
            return "no advertisers", None
        duplicate = duplicate_name(group.participants)
        if duplicate is not None:
            return "duplicate advertiser " + duplicate, None
        return None, rates

    def lot(self, group):
        participants, reserve = group.participants, int(group.arguments[0])
        eligible = [index for index, participant in enumerate(participants) if participant.bid >= reserve]
        first = max(eligible, key=lambda index: participants[index].bid) if eligible else None
        efficient = max(range(len(participants)), key=lambda index: participants[index].value)
        optimum = max(reserve, participants[efficient].value)
        if participants[efficient].value < reserve:
            efficient = None
        efficient_name = participants[efficient].name if efficient is not None else "-"
        lines = [f"LOT {group.name} reserve {reserve} bidders {len(participants)} efficient {efficient_name} optimum {optimum}"]
        first_price = participants[first].bid if first is not None else 0
        second_price = max([reserve] + [participant.value for index, participant in enumerate(participants)
                                        if index != efficient and participant.value >= reserve]) if efficient is not None else 0
        ascending = english(participants, reserve, self.parameters["english_increment"])
        descending = dutch(participants, reserve, self.parameters["dutch_start"], self.parameters["dutch_decrement"])
        mechanisms = [(first, first_price, None), (efficient, second_price, None),
                      (ascending.winner, ascending.price, ascending.steps),
                      (descending.winner, descending.price, descending.steps), (first, first_price, None)]
        results = []
        for name, (winner, price, steps) in zip(FORMATS, mechanisms):
            utilities = [0] * len(participants)
            revenue = price
            if name == "all_pay":
                revenue = sum(participants[index].bid for index in eligible)
                for index in eligible:
                    utilities[index] = -participants[index].bid
            if winner is None:
                welfare = reserve
                line = name.upper() + " unsold"
            else:
                utilities[winner] = participants[winner].value - price
                welfare = participants[winner].value
                line = f"{name.upper()} winner {participants[winner].name} price {price} utility {utilities[winner]}"
            if steps is not None:
                line += " steps " + str(steps)
            efficiency = Fraction(welfare, optimum)
            lines.append(line + f" revenue {revenue} welfare {welfare} efficiency {fraction(efficiency)}")
            if name == "english":
                lines.append("ENGLISH_DROPS" + "".join(f" {participant.name}={drop if drop is not None else '-'}"
                                                       for participant, drop in zip(participants, ascending.drops)))
            results.append(SimpleNamespace(name=name, utilities=utilities, revenue=revenue))
            self.summary_row(group.name, name, revenue, welfare, efficiency)
        for index, participant in enumerate(participants):
            lines.append("UTILITY " + participant.name + " " + " ".join(str(result.utilities[index]) for result in results))
        lines.append("RANKING " + " ".join(result.name for result in sorted(results, key=lambda result: -result.revenue)))
        return lines

    def slots(self, group, rates):
        ranked_bids = sorted(group.participants, key=lambda participant: -participant.bid)
        ranked_values = sorted(group.participants, key=lambda participant: -participant.value)
        count, slots = len(group.participants), len(rates)
        lines = [f"SLOTS {group.name} slots {slots} advertisers {count}"]
        gsp_revenue, gsp_welfare, vcg_revenue, optimum = Fraction(0), Fraction(0), Fraction(0), Fraction(0)
        for rank in range(min(count, slots)):
            bidder, rate = ranked_bids[rank], rates[rank]
            price = gsp_price(ranked_bids, rank)
            payment, utility = rate * price, rate * (bidder.value - price)
            gsp_revenue += payment
            gsp_welfare += rate * bidder.value
            optimum += rate * ranked_values[rank].value
            lines.append(f"GSP {rank + 1} {bidder.name} ctr {fraction(rate)} bid {bidder.bid} "
                         f"price {price} payment {fraction(payment)} utility {fraction(utility)}")
        efficiency = gsp_welfare / optimum
        lines.append(f"GSP_TOTAL revenue {fraction(gsp_revenue)} welfare {fraction(gsp_welfare)} efficiency {fraction(efficiency)}")
        for rank in range(min(count, slots)):
            bidder, rate = ranked_values[rank], rates[rank]
            payment = slot_vcg_payment(ranked_values, rates, rank)
            vcg_revenue += payment
            utility = rate * bidder.value - payment
            lines.append(f"VCG {rank + 1} {bidder.name} ctr {fraction(rate)} value {bidder.value} "
                         f"payment {fraction(payment)} price {fraction(payment / rate)} utility {fraction(utility)}")
        lines.append(f"VCG_TOTAL revenue {fraction(vcg_revenue)} welfare {fraction(optimum)} efficiency 1")
        violations = 0
        for rank in range(1, min(count, slots + 1)):
            bidder = ranked_bids[rank]
            rate = rates[rank] if rank < slots else 0
            stay = rate * (bidder.value - gsp_price(ranked_bids, rank))
            swap = rates[rank - 1] * (bidder.value - bidder.bid)
            violated = stay < swap
            violations += violated
            lines.append(f"ENVY {rank + 1} {bidder.name} stay {fraction(stay)} swap {fraction(swap)} "
                         + ("violated" if violated else "ok"))
        lines.append("ENVY_FREE no violations " + str(violations) if violations else "ENVY_FREE yes")
        deviations = 0
        for rank, bidder in enumerate(ranked_bids):
            rate = rates[rank] if rank < slots else 0
            current = rate * (bidder.value - gsp_price(ranked_bids, rank))
            for target in range(slots):
                if target == rank:
                    continue
                if target < rank:
                    price = ranked_bids[target].bid if target < count else 0
                else:
                    price = gsp_price(ranked_bids, target)
                payoff = rates[target] * (bidder.value - price)
                if payoff > current:
                    deviations += 1
                    lines.append(f"DEVIATE {bidder.name} from {rank + 1} to {target + 1} gain {fraction(payoff - current)}")
        lines.append("NASH no deviations " + str(deviations) if deviations else "NASH yes")
        equilibrium = violations == 0 and deviations == 0
        lines.append("EQUILIBRIUM " + ("yes" if equilibrium else "no"))
        self.group_totals.update({"envy_free": int(violations == 0), "nash": int(deviations == 0), "equilibria": int(equilibrium)})
        self.summary_row(group.name, "gsp", gsp_revenue, gsp_welfare, efficiency)
        self.summary_row(group.name, "vcg", vcg_revenue, optimum, Fraction(1))
        return lines

    def process_groups(self):
        for group in self.groups:
            self.group_totals["lots" if group.kind == "lot" else "slot_groups"] += 1
            if group.kind == "lot":
                error = self.validate_lot(group)
                rates = None
            else:
                error, rates = self.validate_slots(group)
            if error is not None:
                self.single_lines.append(f"{group.kind.upper()} {group.name} ERROR {error}")
                self.group_totals["errors"] += 1
                continue
            self.single_lines.extend(self.lot(group) if group.kind == "lot" else self.slots(group, rates))

    def total_lines(self):
        totals = self.wdp_totals
        self.wdp_lines.append(f"TOTAL auctions {totals['auctions']} bids {totals['bids']} valid {totals['valid']} "
                              f"eligible {totals['eligible']} nodes {totals['nodes']} greedy_optimal {totals['greedy_optimal']}")
        totals = self.vcg_totals
        self.vcg_lines.append("OVERALL" + "".join(f" {name} {totals[name]}" for name in ("vcg", "pay_as_bid", "greedy", "critical", "saa")))
        totals = self.core_totals
        self.core_lines.append(f"SUMMARY checked {totals['checked']} skipped {totals['skipped']}"
                               + "".join(f" {name} {totals[name]}" for name in OUTCOMES))
        totals = self.ascending_totals
        self.ascending_lines.append(f"SUMMARY auctions {totals['auctions']} rounds {totals['rounds']} capped {totals['capped']} "
                                    f"exposed {totals['exposed']} exposure {totals['exposure']}")
        totals = self.group_totals
        self.single_lines.append(f"SUMMARY lots {totals['lots']} slot_groups {totals['slot_groups']} errors {totals['errors']} "
                                 f"envy_free {totals['envy_free']} nash {totals['nash']} equilibria {totals['equilibria']}")

    def run(self):
        self.process_auctions()
        self.process_groups()
        self.total_lines()
        write_reports([("wdp.txt", self.wdp_lines), ("vcg.txt", self.vcg_lines),
                       ("core_check.txt", self.core_lines), ("ascending_log.txt", self.ascending_lines),
                       ("single_item.txt", self.single_lines), ("summary.csv", self.summary_lines)])


def main():
    Laboratory().run()


if __name__ == "__main__":
    main()
