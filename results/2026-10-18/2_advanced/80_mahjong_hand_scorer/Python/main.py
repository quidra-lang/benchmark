"""Validate and score mahjong wins, then analyze thirteen-tile hands."""

from collections import Counter
from pathlib import Path

import decomposition
import scoring
import shanten
import tiles
import yaku


WAIT_ORDER = ("ryanmen", "kanchan", "penchan", "shanpon", "tanki", "single", "thirteen")
WIN_ORDER = ("dealer_ron", "dealer_tsumo", "nondealer_ron", "nondealer_tsumo")


def read_records(filename):
    records = []
    for line in Path("input", filename).read_text(encoding="ascii").splitlines():
        label, *items = line.split(" ")
        records.append((label, dict(item.split("=", 1) for item in items)))
    return records


def read_rules():
    rules = {}
    for name, fields in read_records("rules.txt"):
        rules[name] = {key: int(value) if key == "honba" else value == "yes"
                       for key, value in fields.items()}
    return rules


class Meld:
    def __init__(self, text):
        self.kind = text[0]
        self.tiles = tiles.parse(text[1:])
        self.block = tuple(sorted(tile.kind for tile in self.tiles)) if self.tiles is not None else ()

    def valid(self):
        if self.kind == "C":
            return (len(self.block) == 3 and self.block[0] < 27 and self.block[0] % 9 <= 6
                    and self.block == tuple(range(self.block[0], self.block[0] + 3)))
        if self.kind not in ("P", "K", "A"):
            return False
        size = 3 if self.kind == "P" else 4
        return len(self.block) == size and len(set(self.block)) == 1


class Situation:
    def __init__(self, label, fields, rules):
        self.label = label
        self.rule_name = fields["rules"]
        self.rules = rules[self.rule_name]
        self.hand = tiles.parse(fields["hand"])
        self.win = tiles.parse(fields["win"])
        self.melds = [] if fields["melds"] == "-" else [Meld(text) for text in fields["melds"].split(",")]
        self.dora = tiles.parse(fields["dora"])
        self.ura = tiles.parse(fields["ura"], allow_empty=True)
        self.discards = tiles.parse(fields["discards"], allow_empty=True)
        self.by = fields["by"]
        self.seat = fields["seat"]
        self.discarder = fields["from"]
        self.round = fields["round"]
        self.seat_tile = tiles.WIND_TILES[self.seat]
        self.round_tile = tiles.WIND_TILES[self.round]
        self.flags = set() if fields["flags"] == "-" else set(fields["flags"].split(","))
        self.closed = all(meld.kind == "A" for meld in self.melds)
        self.riichi = bool(self.flags & {"riichi", "double_riichi"})
        self.kan_count = sum(meld.kind in ("K", "A") for meld in self.melds)
        self.honba = int(fields["honba"])
        self.sticks = int(fields["sticks"])

    def prepare(self):
        self.winning_tile = self.win[0].kind
        self.hand_counts = tiles.counts(self.hand)
        self.concealed_counts = tiles.counts(self.hand + self.win)
        meld_tiles = [tile for meld in self.melds for tile in meld.tiles]
        self.meld_counts = tiles.counts(meld_tiles)
        self.all_tiles = self.hand + self.win + meld_tiles
        self.all_counts = tiles.counts(self.all_tiles)


class WaitingHand:
    def __init__(self, label, fields, rules):
        self.label, self.fields = label, fields
        self.rules = rules[fields["rules"]]
        self.hand = tiles.parse(fields["hand"])
        self.dora = tiles.parse(fields["dora"])
        self.discards = tiles.parse(fields["discards"], allow_empty=True)
        self.visible = tiles.parse(fields["visible"], allow_empty=True)


class Candidate:
    def __init__(self, form_type, pair, sets, winning_block, form, wait):
        self.form_type, self.pair, self.sets = form_type, pair, sets
        self.winning_block, self.form, self.wait = winning_block, form, wait
        self.yaku, self.yakuman, self.fu_items = [], [], []
        self.multiplier = self.han = self.fu = self.fu_total = self.base = 0
        self.dora = self.aka = self.ura = 0
        self.category = "none"


def copy_error(all_tiles, rules):
    reds = [0, 0, 0]
    for tile in all_tiles:
        if tile.red:
            reds[tile.kind // 9] += 1
    if not rules["red_fives"] and any(reds):
        return "red five not allowed"
    for kind, count in enumerate(tiles.counts(all_tiles)):
        if count >= 5:
            return "too many copies of " + tiles.name(kind)
    for suit, count in zip("mps", reds):
        if count >= 2:
            return "too many copies of 0" + suit
    return None


def validate_situation(situation):
    values = [situation.hand, situation.win, situation.dora, situation.ura, situation.discards]
    values.extend(meld.tiles for meld in situation.melds)
    if any(value is None for value in values) or len(situation.win) != 1:
        return "bad tile notation"
    if len(situation.melds) >= 5 or any(not meld.valid() for meld in situation.melds):
        return "bad meld"
    if len(situation.hand) != 13 - 3 * len(situation.melds):
        return "wrong tile count"
    situation.prepare()
    observed = situation.all_tiles + situation.dora + situation.ura + situation.discards
    error = copy_error(observed, situation.rules)
    if error is not None:
        return error
    if (situation.by == "tsumo" and situation.discarder != "-"
            or situation.by == "ron" and situation.discarder in ("-", situation.seat)):
        return "invalid discarder"
    flags = situation.flags
    valid_flags = {
        "riichi": situation.closed,
        "double_riichi": situation.closed and "riichi" not in flags,
        "ippatsu": situation.riichi and "rinshan" not in flags,
        "haitei": situation.by == "tsumo" and "rinshan" not in flags,
        "houtei": situation.by == "ron" and "chankan" not in flags,
        "rinshan": situation.by == "tsumo" and situation.kan_count >= 1,
        "chankan": situation.by == "ron",
        "tenhou": situation.seat == "E" and situation.by == "tsumo" and not situation.melds and flags == {"tenhou"},
        "chiihou": situation.seat != "E" and situation.by == "tsumo" and not situation.melds and flags == {"chiihou"},
    }
    for flag in yaku.FLAGS:
        if flag in flags and not valid_flags[flag]:
            return "invalid flag " + flag
    if len(situation.dora) != 1 + situation.kan_count:
        return "invalid dora indicators"
    if situation.riichi and len(situation.ura) != len(situation.dora) or not situation.riichi and situation.ura:
        return "invalid ura indicators"
    if situation.riichi and situation.sticks == 0:
        return "invalid sticks"
    if not decomposition.winning(situation.concealed_counts, len(situation.melds)):
        return "not a winning hand"
    return None


def validate_waiting(hand):
    if any(value is None for value in (hand.hand, hand.dora, hand.discards, hand.visible)):
        return "bad tile notation"
    if len(hand.hand) != 13:
        return "wrong tile count"
    observed = hand.hand + hand.dora + hand.discards + hand.visible
    error = copy_error(observed, hand.rules)
    if error is None:
        hand.counts = tiles.counts(hand.hand)
        hand.known_counts = tiles.counts(observed)
    return error


def candidates(situation):
    result = []
    winning = situation.winning_tile
    counts = situation.concealed_counts
    for pair, sets in decomposition.standard(tuple(counts), len(situation.melds)):
        blocks = ((pair, pair),) + sets
        choices = []
        for block in blocks:
            if winning in block and block not in choices:
                choices.append(block)
        for chosen in choices:
            parts, marked = ["standard"], False
            for block in blocks:
                notation = tiles.block(block)
                if block == chosen and not marked:
                    notation += "*"
                    marked = True
                parts.append(notation)
            parts.extend(meld.kind + tiles.block(meld.block) for meld in situation.melds)
            wait = decomposition.wait_shape("standard", chosen, winning, situation.hand_counts)
            result.append(Candidate("standard", pair, sets, chosen, " ".join(parts), wait))
    if not situation.melds and decomposition.seven_pairs(counts):
        parts = ["chiitoitsu"]
        for kind, count in enumerate(counts):
            if count:
                parts.append(tiles.block((kind, kind)) + ("*" if kind == winning else ""))
        result.append(Candidate("chiitoitsu", None, (), None, " ".join(parts), "tanki"))
    if not situation.melds and decomposition.thirteen_orphans(counts):
        parts = ["kokushi"]
        for kind in tiles.YAOCHUU:
            parts.append(tiles.block((kind,) * counts[kind]) + ("*" if kind == winning else ""))
        wait = decomposition.wait_shape("kokushi", None, winning, situation.hand_counts)
        result.append(Candidate("kokushi", None, (), None, " ".join(parts), wait))
    return sorted(result, key=lambda candidate: candidate.form)


def block_facts(situation, candidate):
    triplets, sequences, concealed_sequences = [], [], []
    for block in candidate.sets:
        if block[0] == block[-1]:
            concealed = situation.by == "tsumo" or block != candidate.winning_block
            triplets.append((block, concealed, False))
        else:
            sequences.append(block[0])
            concealed_sequences.append(block)
    for meld in situation.melds:
        if meld.kind == "C":
            sequences.append(meld.block[0])
        else:
            triplets.append((meld.block, meld.kind == "A", meld.kind in ("K", "A")))
    return triplets, sequences, concealed_sequences


def yakuman_names(situation, candidate, kinds, triplets):
    names = situation.flags & {"tenhou", "chiihou"}
    if all(tiles.honor(kind) for kind in kinds):
        names.add("tsuuiisou")
    if all(tiles.terminal(kind) for kind in kinds):
        names.add("chinroutou")
    if kinds <= tiles.GREEN:
        names.add("ryuuiisou")
    suits = {kind // 9 for kind in kinds}
    if not situation.melds and len(suits) == 1 and not any(tiles.honor(kind) for kind in kinds):
        start = next(iter(suits)) * 9
        counts = situation.all_counts[start:start + 9]
        if counts[0] >= 3 and counts[8] >= 3 and all(count >= 1 for count in counts[1:8]):
            initial = situation.hand_counts[start:start + 9]
            names.add("junsei_chuuren" if initial == [3, 1, 1, 1, 1, 1, 1, 1, 3] else "chuuren")
    if candidate.form_type == "kokushi":
        names.add("kokushi_13" if candidate.wait == "thirteen" else "kokushi")
    if candidate.form_type == "standard":
        concealed = sum(hidden for _, hidden, _ in triplets)
        triplet_kinds = {block[0] for block, _, _ in triplets}
        dragons = len(triplet_kinds & {31, 32, 33})
        winds = len(triplet_kinds & {27, 28, 29, 30})
        if concealed == 4:
            names.add("suuankou_tanki" if candidate.wait == "tanki" else "suuankou")
        if dragons == 3:
            names.add("daisangen")
        if winds == 4:
            names.add("daisuushii")
        if winds == 3 and 27 <= candidate.pair <= 30:
            names.add("shousuushii")
        if sum(kan for _, _, kan in triplets) == 4:
            names.add("suukantsu")
    return names


def ordinary_names(situation, candidate, kinds, triplets, sequences, concealed_sequences):
    names = situation.flags & set(yaku.FLAGS[:7])
    if situation.closed and situation.by == "tsumo":
        names.add("menzen_tsumo")
    if all(not tiles.yaochuu(kind) for kind in kinds) and (situation.closed or situation.rules["open_tanyao"]):
        names.add("tanyao")
    if all(tiles.yaochuu(kind) for kind in kinds):
        names.add("honroutou")
    number_suits = {kind // 9 for kind in kinds if kind < 27}
    honors = any(tiles.honor(kind) for kind in kinds)
    if len(number_suits) == 1:
        names.add("honitsu" if honors else "chinitsu")
    if candidate.form_type == "chiitoitsu":
        names.add("chiitoitsu")
    if candidate.form_type != "standard":
        return names
    pair = candidate.pair
    yakuhai_pair = pair >= 31 or pair in (situation.seat_tile, situation.round_tile)
    if (situation.closed and not situation.melds and len(concealed_sequences) == 4
            and not yakuhai_pair and candidate.wait == "ryanmen"):
        names.add("pinfu")
    repeated = Counter(concealed_sequences)
    ryanpeikou = situation.closed and len(concealed_sequences) == 4 and sum(count // 2 for count in repeated.values()) == 2
    if ryanpeikou:
        names.add("ryanpeikou")
    elif situation.closed and any(count >= 2 for count in repeated.values()):
        names.add("iipeikou")
    triplet_kinds = {block[0] for block, _, _ in triplets}
    for kind, name in ((31, "haku"), (32, "hatsu"), (33, "chun"),
                       (situation.seat_tile, "jikaze"), (situation.round_tile, "bakaze")):
        if kind in triplet_kinds:
            names.add(name)
    if len(triplets) == 4:
        names.add("toitoi")
    if sum(hidden for _, hidden, _ in triplets) == 3:
        names.add("sanankou")
    sequence_kinds = set(sequences)
    if any(all(start + suit * 9 in sequence_kinds for suit in range(3)) for start in range(7)):
        names.add("sanshoku_doujun")
    if any(all(number + suit * 9 in triplet_kinds for suit in range(3)) for number in range(9)):
        names.add("sanshoku_doukou")
    if any(all(suit * 9 + start in sequence_kinds for start in (0, 3, 6)) for suit in range(3)):
        names.add("ittsu")
    blocks = [(pair, pair), *candidate.sets, *(meld.block for meld in situation.melds)]
    if sequences and all(any(tiles.yaochuu(kind) for kind in block) for block in blocks):
        names.add("chanta" if honors else "junchan")
    if sum(kan for _, _, kan in triplets) == 3:
        names.add("sankantsu")
    if len(triplet_kinds & {31, 32, 33}) == 2 and pair >= 31:
        names.add("shousangen")
    return names


def evaluate_candidate(situation, candidate):
    kinds = {kind for kind, count in enumerate(situation.all_counts) if count}
    triplets, sequences, concealed_sequences = block_facts(situation, candidate)
    names = yakuman_names(situation, candidate, kinds, triplets)
    candidate.yakuman = yaku.yakuman(names, situation.rules["double_yakuman"])
    if candidate.yakuman:
        candidate.multiplier = sum(multiplier for _, multiplier in candidate.yakuman)
        candidate.base = 8000 * candidate.multiplier
        candidate.category = "yakuman"
        return candidate
    names = ordinary_names(situation, candidate, kinds, triplets, sequences, concealed_sequences)
    candidate.yaku = yaku.ordinary(names, situation.closed)
    candidate.dora = sum(situation.all_counts[tiles.next_dora(tile.kind)] for tile in situation.dora)
    candidate.ura = sum(situation.all_counts[tiles.next_dora(tile.kind)] for tile in situation.ura)
    candidate.aka = sum(tile.red for tile in situation.all_tiles)
    candidate.fu_items, candidate.fu_total, candidate.fu = scoring.fu_breakdown(
        candidate.form_type, candidate.pair, triplets, candidate.wait, situation.closed,
        situation.by, situation.seat_tile, situation.round_tile, "pinfu" in names
    )
    if candidate.yaku:
        candidate.han = sum(han for _, han in candidate.yaku) + candidate.dora + candidate.aka + candidate.ura
        candidate.category, candidate.base = scoring.limit(candidate.han, candidate.fu, situation.rules)
    return candidate


def evaluate_candidates(situation):
    return [evaluate_candidate(situation, candidate) for candidate in candidates(situation)]


def best_candidate(candidates):
    eligible = [candidate for candidate in candidates if candidate.base >= 1]
    return min(eligible, key=lambda candidate: (
        -candidate.base, -bool(candidate.yakuman),
        -candidate.han if not candidate.yakuman else 0,
        -candidate.fu if not candidate.yakuman else 0, candidate.form
    ), default=None)


def candidate_line(candidate):
    if candidate.yakuman:
        evaluation = (f"yakuman {candidate.multiplier} base {candidate.base} yaku "
                      + ",".join(name for name, _ in candidate.yakuman))
    elif not candidate.yaku:
        evaluation = "no_yaku"
    else:
        evaluation = (f"han {candidate.han} fu {candidate.fu} base {candidate.base} yaku "
                      + ",".join(name for name, _ in candidate.yaku))
    return f"CANDIDATE {candidate.form} = {candidate.wait} {evaluation}"


def winning_lines(situation, candidate):
    lines = ["FORM " + candidate.form, "WAIT " + candidate.wait]
    if candidate.yakuman:
        lines.extend(f"YAKUMAN {name} {multiplier}" for name, multiplier in candidate.yakuman)
        lines.append(f"SCORE yakuman {candidate.multiplier} base {candidate.base}")
    else:
        lines.extend(f"YAKU {name} {han}" for name, han in candidate.yaku)
        lines.append(f"DORA dora {candidate.dora} aka {candidate.aka} ura {candidate.ura}")
        lines.extend(f"FU {item} {value}" for item, value in candidate.fu_items)
        lines.append(f"FU total {candidate.fu_total} {candidate.fu}")
        lines.append(f"SCORE han {candidate.han} fu {candidate.fu} limit {candidate.category} base {candidate.base}")
    ron, dealer, nondealer, points = scoring.payments(candidate.base, situation.seat == "E", situation.by)
    if situation.by == "ron":
        lines.append(f"PAY ron {ron}")
    elif situation.seat == "E":
        lines.append(f"PAY tsumo all {nondealer}")
    else:
        lines.append(f"PAY tsumo dealer {dealer} nondealer {nondealer}")
    honba = situation.honba * situation.rules["honba"]
    sticks = situation.sticks * 1000
    gain = points + honba + sticks
    lines.append(f"BONUS honba {honba} sticks {sticks}")
    lines.append(f"TOTAL points {points} gain {gain}")
    delta = dict.fromkeys(tiles.WINDS, 0)
    if situation.by == "ron":
        delta[situation.discarder] = -ron - honba
    else:
        for wind in tiles.WINDS:
            if wind != situation.seat:
                payment = dealer if wind == "E" else nondealer
                delta[wind] = -payment - honba // 3
    delta[situation.seat] = gain
    changes = " ".join(f"{wind} {value:+d}" if value > 0 else f"{wind} {value}" for wind, value in delta.items())
    lines.append("DELTA " + changes)
    return lines, points


def hypothetical(hand, winning, method, rules):
    fields = dict(hand.fields)
    fields.update({
        "melds": "-", "win": tiles.name(winning), "by": method,
        "from": "-" if method == "tsumo" else "S" if fields["seat"] == "E" else "E",
        "flags": "riichi" if fields["riichi"] == "yes" else "-",
        "ura": "-", "honba": "0", "sticks": "0",
    })
    situation = Situation(hand.label, fields, rules)
    situation.prepare()
    return situation


class Reports:
    def __init__(self, rules):
        self.rules = rules
        self.situations = read_records("hands.txt")
        self.hands = read_records("waits.txt")
        self.stats, self.win_counts, self.wait_counts = Counter(), Counter(), Counter()
        self.han_counts, self.fu_counts, self.limit_counts, self.yaku_counts = Counter(), Counter(), Counter(), Counter()
        self.rule_counts = {name: Counter() for name in rules}
        self.maximum = 0
        self.maximum_hand = "-"
        self.summary = ["hand,han,fu,points,yaku"]

    def record_win(self, situation, candidate, points):
        self.stats["wins"] += 1
        self.stats["points"] += points
        self.rule_counts[situation.rule_name]["wins"] += 1
        self.rule_counts[situation.rule_name]["points"] += points
        group = ("dealer_" if situation.seat == "E" else "nondealer_") + situation.by
        self.win_counts[group] += 1
        self.wait_counts[candidate.wait] += 1
        self.limit_counts[candidate.category] += 1
        names = candidate.yakuman if candidate.yakuman else candidate.yaku
        for name, _ in names:
            self.yaku_counts[name] += 1
        if candidate.yakuman:
            han, fu = "Y" + str(candidate.multiplier), "-"
        else:
            han, fu = str(candidate.han), str(candidate.fu)
            self.han_counts[candidate.han] += 1
            self.fu_counts[candidate.fu] += 1
        self.summary.append(f"{situation.label},{han},{fu},{points}," + ";".join(name for name, _ in names))
        if points > self.maximum:
            self.maximum, self.maximum_hand = points, situation.label

    def scores(self):
        lines = []
        for label, fields in self.situations:
            situation = Situation(label, fields, self.rules)
            self.rule_counts[situation.rule_name]["hands"] += 1
            lines.append("HAND " + label)
            error = validate_situation(situation)
            if error is not None:
                self.stats["errors"] += 1
                lines.append("ERROR " + error)
                self.summary.append(label + ",-,-,0,ERROR")
                continue
            waiting = decomposition.waiting_tiles(situation.hand_counts, situation.meld_counts, len(situation.melds))
            lines.append("WAITS " + " ".join(tiles.name(kind) for kind in waiting))
            evaluated = evaluate_candidates(situation)
            lines.extend(candidate_line(candidate) for candidate in evaluated)
            if situation.by == "ron" and any(tile.kind in waiting for tile in situation.discards):
                self.stats["furiten"] += 1
                lines.append("RESULT furiten")
                self.summary.append(label + ",-,-,0,FURITEN")
                continue
            best = best_candidate(evaluated)
            if best is None:
                self.stats["no_yaku"] += 1
                lines.append("RESULT no_yaku")
                self.summary.append(label + ",-,-,0,NO_YAKU")
                continue
            report, points = winning_lines(situation, best)
            lines.extend(report)
            self.record_win(situation, best, points)
        lines.extend(self.score_statistics())
        return lines

    def score_statistics(self):
        lines = [
            f"STATS hands {len(self.situations)} wins {self.stats['wins']} furiten {self.stats['furiten']} "
            f"no_yaku {self.stats['no_yaku']} errors {self.stats['errors']}",
            "WINS " + " ".join(f"{name} {self.win_counts[name]}" for name in WIN_ORDER),
            "WAIT_COUNT " + " ".join(f"{name} {self.wait_counts[name]}" for name in WAIT_ORDER),
        ]
        lines.extend(f"HAN_COUNT {han} {count}" for han, count in sorted(self.han_counts.items()))
        lines.extend(f"FU_COUNT {fu} {count}" for fu, count in sorted(self.fu_counts.items()))
        lines.extend(f"LIMIT {category} {self.limit_counts[category]}" for category in yaku.CATEGORIES)
        for name in [name for name, _, _ in yaku.YAKU] + [name for name, _ in yaku.YAKUMAN]:
            if self.yaku_counts[name]:
                lines.append(f"YAKU_COUNT {name} {self.yaku_counts[name]}")
        lines.append(f"POINTS total {self.stats['points']} max {self.maximum} hand {self.maximum_hand}")
        for name, counts in self.rule_counts.items():
            lines.append(f"RULE {name} hands {counts['hands']} wins {counts['wins']} points {counts['points']}")
        return lines

    def acceptance(self, hand, current):
        result = []
        counts = list(hand.counts)
        for kind in range(34):
            if counts[kind] >= 4:
                continue
            counts[kind] += 1
            advancing = min(shanten.numbers(tuple(counts))) < current
            counts[kind] -= 1
            if advancing:
                result.append((kind, 4 - hand.known_counts[kind]))
        return result

    def tenpai_lines(self, hand, waiting, furiten):
        lines = []
        best = {"ron": None, "tsumo": None}
        for kind, remaining in waiting:
            results = {}
            for method in ("ron", "tsumo"):
                if method == "ron" and furiten:
                    results[method] = "furiten"
                    continue
                situation = hypothetical(hand, kind, method, self.rules)
                candidate = best_candidate(evaluate_candidates(situation))
                if candidate is None:
                    results[method] = "no_yaku"
                    continue
                points = scoring.payments(candidate.base, situation.seat == "E", method)[3]
                results[method] = str(points)
                if best[method] is None or points > best[method][1]:
                    best[method] = kind, points
            lines.append(f"WAIT {tiles.name(kind)} left {remaining} ron {results['ron']} tsumo {results['tsumo']}")
        choices = {}
        for method in ("ron", "tsumo"):
            value = best[method]
            choices[method] = "none" if value is None else f"{tiles.name(value[0])} {value[1]}"
        lines.append(f"BEST ron {choices['ron']} tsumo {choices['tsumo']}")
        return lines

    def waits(self):
        lines, statistics, counts = [], Counter(), Counter()
        for label, fields in self.hands:
            hand = WaitingHand(label, fields, self.rules)
            lines.append("HAND " + label)
            error = validate_waiting(hand)
            if error is not None:
                statistics["errors"] += 1
                lines.append("ERROR " + error)
                continue
            standard, seven, orphans = shanten.numbers(tuple(hand.counts))
            current = min(standard, seven, orphans)
            counts[current] += 1
            lines.append(f"SHANTEN standard {standard} chiitoitsu {seven} kokushi {orphans}")
            accepted = self.acceptance(hand, current)
            total = sum(remaining for _, remaining in accepted)
            if current != 0:
                suffix = "".join(f" {tiles.name(kind)}:{remaining}" for kind, remaining in accepted)
                lines.append(f"ACCEPT kinds {len(accepted)} tiles {total}" + suffix)
                continue
            statistics["tenpai"] += 1
            discarded = {tile.kind for tile in hand.discards}
            furiten = any(kind in discarded for kind, _ in accepted)
            statistics["furiten"] += furiten
            lines.append(f"TENPAI kinds {len(accepted)} tiles {total} furiten {'yes' if furiten else 'no'}")
            lines.extend(self.tenpai_lines(hand, accepted, furiten))
        lines.append(f"STATS hands {len(self.hands)} errors {statistics['errors']} "
                     f"tenpai {statistics['tenpai']} furiten {statistics['furiten']}")
        lines.extend(f"SHANTEN_COUNT {number} {counts[number]}" for number in range(7))
        return lines

    def write(self):
        scores = self.scores()
        waits = self.waits()
        directory = Path("output")
        directory.mkdir(exist_ok=True)
        for filename, lines in (("scores.txt", scores), ("waits.txt", waits), ("summary.csv", self.summary)):
            with (directory / filename).open("w", encoding="ascii", newline="\n") as destination:
                destination.write("\n".join(lines) + "\n")


def main():
    Reports(read_rules()).write()


if __name__ == "__main__":
    main()
