from copy import deepcopy
import sys


SEATS = "NESW"
SUITS = "CDSH"
RANKS = "23456789TJQKA"
STRATEGIES = ("BASIC", "LOW", "HIGH", "SMART", "MOON")
DIRECTIONS = {"L": "LEFT", "R": "RIGHT", "A": "ACROSS", "H": "HOLD"}
DEFAULT_RULES = dict(TARGET=100, LIMIT=100, MOON="ADD", JACK="OFF",
                     QSBREAK="OFF", BLOOD="OFF", PASS="LRAH")
QS, KS, AS, JD = 36, 37, 38, 22


class CommandError(Exception):
    pass


def fail(reason):
    raise CommandError(reason)


def card_text(card):
    return RANKS[card % 13] + SUITS[card // 13]


def cards_text(cards):
    return " ".join(card_text(card) for card in sorted(cards)) or "-"


def seat_value(word):
    if word not in SEATS or len(word) != 1:
        fail(f"bad seat {word}")
    return SEATS.index(word)


def card_value(word):
    if len(word) != 2 or word[0] not in RANKS or word[1] not in SUITS:
        fail(f"bad card {word}")
    return SUITS.index(word[1]) * 13 + RANKS.index(word[0])


def bounded(word, low, high):
    value = int(word)
    if not low <= value <= high:
        fail(f"bad value {word}")
    return value


def rank_key(card):
    return card % 13, card // 13


def high_key(card):
    return -(card % 13), card // 13


def lowest(cards):
    return min(cards, key=rank_key)


def highest(cards):
    return min(cards, key=high_key)


def penalty(card):
    return card == QS or card // 13 == 3


def pairs(label, values):
    return label + " " + " ".join(f"{seat} {value}" for seat, value in zip(SEATS, values))


class Generator:
    def __init__(self, seed):
        self.state = seed

    def draw(self):
        self.state = 48271 * self.state % 2147483647
        return self.state

    def shuffle(self, deck):
        for i in range(len(deck) - 1, 0, -1):
            j = self.draw() % (i + 1)
            deck[i], deck[j] = deck[j], deck[i]


class Game:
    def __init__(self, rules, bots, generator):
        self.rules = rules
        self.bots = bots
        self.generator = generator
        self.state = "between"
        self.number = 0
        self.scores = [0] * 4
        self.stats = [[0] * 4 for _ in SEATS]
        self.stacked = {}
        self.history = []
        self.log = []
        self.record = []

    def point(self, card):
        if card == QS:
            return 13
        if card // 13 == 3:
            return 1
        return -10 if card == JD and self.rules["JACK"] == "ON" else 0

    def write(self, level, line):
        self.log.append((level, line))
        if level:
            self.record.append(line)

    def deal(self):
        self.number += 1
        cycle = self.rules["PASS"]
        self.pass_code = cycle[(self.number - 1) % len(cycle)]
        self.hands = [set(self.stacked.get(seat, ())) for seat in range(4)]
        used = set().union(*self.hands)
        deck = [card for card in range(52) if card not in used]
        self.generator.shuffle(deck)
        free = [seat for seat in range(4) if seat not in self.stacked]
        for i, card in enumerate(deck):
            self.hands[free[i % len(free)]].add(card)
        self.stacked.clear()
        self.passes = {}
        self.taken = [set() for _ in SEATS]
        self.tricks = []
        self.trick_counts = [0] * 4
        self.current = []
        self.broken = False
        self.undo = []
        self.record = []
        self.write(1, f"hand {self.number} pass {DIRECTIONS[self.pass_code]}")
        for seat in range(4):
            self.write(2, f"{SEATS[seat]}: {cards_text(self.hands[seat])}")
        if self.pass_code == "H":
            self.begin_play()
        else:
            self.state = "passing"

    def begin_play(self):
        self.state = "playing"
        self.leader = next(seat for seat in range(4) if 0 in self.hands[seat])
        self.write(2, f"lead {SEATS[self.leader]}")

    def pass_cards(self, seat, cards):
        self.hands[seat].difference_update(cards)
        self.passes[seat] = list(cards)
        self.write(2, f"{SEATS[seat]} passes {cards_text(cards)}")
        if len(self.passes) == 4:
            offset = {"L": 1, "R": 3, "A": 2}[self.pass_code]
            for source, passed in self.passes.items():
                self.hands[(source + offset) % 4].update(passed)
            self.begin_play()

    def actor(self):
        return (self.leader + len(self.current)) % 4

    def legal(self):
        hand = self.hands[self.actor()]
        if not self.current:
            if not self.tricks:
                return {0}
            non_hearts = {card for card in hand if card // 13 != 3}
            return non_hearts if not self.broken and non_hearts else set(hand)
        suit = self.current[0][1] // 13
        followers = {card for card in hand if card // 13 == suit}
        if followers:
            return followers
        if not self.tricks and self.rules["BLOOD"] == "OFF":
            safe = {card for card in hand if not penalty(card)}
            if safe:
                return safe
        return set(hand)

    def choose_pass(self, seat):
        hand = self.hands[seat]
        strategy = self.bots[seat]
        low = sorted(hand, key=rank_key)
        high = sorted(hand, key=high_key)
        hearts = sorted((card for card in hand if card // 13 == 3), key=high_key)
        special = [card for card in (QS, KS, AS) if card in hand]
        if strategy == "LOW":
            order = high
        elif strategy == "HIGH":
            order = low
        elif strategy == "MOON":
            order = [card for card in low if card // 13 != 3] + [card for card in low if card // 13 == 3]
        elif strategy == "SMART":
            protected = QS in hand and sum(card // 13 == 2 for card in hand) >= 5
            order = [] if protected else special
            suits = [suit for suit in (0, 1) if any(card // 13 == suit for card in hand)]
            if suits:
                suit = min(suits, key=lambda s: (sum(card // 13 == s for card in hand), s))
                order += [card for card in high if card // 13 == suit]
            order += hearts + high
        else:
            order = special + hearts + high
        return list(dict.fromkeys(order))[:3]

    def choose_play(self):
        seat = self.actor()
        hand = self.hands[seat]
        legal = self.legal()
        strategy = self.bots[seat]
        if strategy == "LOW":
            return lowest(legal)
        if strategy == "HIGH":
            return highest(legal)
        if strategy == "MOON" and any(any(penalty(card) for card in self.taken[other])
                                      for other in range(4) if other != seat):
            strategy = "BASIC"
        if not self.current:
            if strategy == "SMART" and not self.queen_played() and QS not in hand:
                small_spades = {card for card in legal if card // 13 == 2 and card % 13 < 10}
                if small_spades:
                    return lowest(small_spades)
            suits = {card // 13 for card in legal}
            if strategy == "MOON":
                suit = min(suits, key=lambda s: (-sum(card // 13 == s for card in legal), s))
                return highest(card for card in legal if card // 13 == suit)
            suit = min(suits, key=lambda s: (sum(card // 13 == s for card in legal), s))
            return lowest(card for card in legal if card // 13 == suit)
        led = self.current[0][1] // 13
        if any(card // 13 == led for card in hand):
            winning = max(card % 13 for _, card in self.current if card // 13 == led)
            lower = {card for card in legal if card % 13 < winning}
            if strategy == "MOON":
                high = highest(legal)
                return high if high % 13 > winning else lowest(legal)
            if lower:
                return highest(lower)
            if strategy == "SMART" and len(self.current) == 3:
                return highest(legal - {QS}) if legal - {QS} else QS
            return lowest(legal)
        if strategy == "MOON":
            safe = {card for card in legal if not penalty(card)}
            return lowest(safe or legal)
        if QS in legal:
            return QS
        if strategy == "SMART" and not self.queen_played():
            if AS in legal:
                return AS
            if KS in legal:
                return KS
        hearts = {card for card in legal if card // 13 == 3}
        return highest(hearts or legal)

    def queen_played(self):
        return any(QS in cards for cards in self.taken) or any(card == QS for _, card in self.current)

    def winner(self, plays):
        led = plays[0][1] // 13
        return max((play for play in plays if play[1] // 13 == led), key=lambda play: play[1] % 13)[0]

    def trick_line(self, plays, number):
        sequence = " ".join(f"{SEATS[seat]} {card_text(card)}" for seat, card in plays)
        points = sum(self.point(card) for _, card in plays)
        return f"trick {number}: {sequence} -> {SEATS[self.winner(plays)]} {points}"

    def play(self, card):
        seat = self.actor()
        fields = (self.hands, self.taken, self.tricks, self.trick_counts, self.current,
                  self.leader, self.broken, self.record)
        self.undo.append((deepcopy(fields), len(self.log), seat, card))
        self.hands[seat].remove(card)
        self.current.append((seat, card))
        if card // 13 == 3 or card == QS and self.rules["QSBREAK"] == "ON":
            self.broken = True
        if len(self.current) == 4:
            winner = self.winner(self.current)
            self.taken[winner].update(card for _, card in self.current)
            self.trick_counts[winner] += 1
            self.tricks.append(self.current)
            self.write(2, self.trick_line(self.current, len(self.tricks)))
            self.current = []
            self.leader = winner
            if len(self.tricks) == 13:
                self.finish_hand()

    def undo_card(self):
        fields, length, seat, card = self.undo.pop()
        (self.hands, self.taken, self.tricks, self.trick_counts, self.current,
         self.leader, self.broken, self.record) = fields
        del self.log[length:]
        return seat, card

    def claim(self, seat):
        remaining = set().union(*self.hands)
        count = 13 - len(self.tricks)
        self.taken[seat].update(remaining)
        self.trick_counts[seat] += count
        self.hands = [set() for _ in SEATS]
        self.write(2, f"claim {SEATS[seat]} tricks {count} points {sum(self.point(card) for card in remaining)}")
        self.finish_hand()

    def finish_hand(self):
        points = [sum(self.point(card) for card in cards) for cards in self.taken]
        shooter = next((seat for seat in range(4) if sum(penalty(card) for card in self.taken[seat]) == 14), None)
        if shooter is not None:
            points[shooter] -= 26
            method = self.rules["MOON"]
            if method == "AUTO":
                add = [self.scores[seat] + points[seat] + (26 if seat != shooter else 0) for seat in range(4)]
                ended = self.number >= self.rules["LIMIT"] or max(add) >= self.rules["TARGET"]
                winner = min(range(4), key=lambda seat: (add[seat], seat))
                method = "SUB" if ended and winner != shooter else "ADD"
            if method == "SUB":
                points[shooter] -= 26
            else:
                points = [value + (26 if seat != shooter else 0) for seat, value in enumerate(points)]
            self.write(1, f"moon {SEATS[shooter]} {method}")
        for seat in range(4):
            self.scores[seat] += points[seat]
            stats = self.stats[seat]
            stats[0] += self.trick_counts[seat]
            stats[1] += sum(card // 13 == 3 for card in self.taken[seat])
            stats[2] += QS in self.taken[seat]
            stats[3] += shooter == seat
        self.write(1, pairs("points", points))
        self.write(1, pairs("scores", self.scores))
        self.history.append(dict(number=self.number, direction=DIRECTIONS[self.pass_code],
                                 points=points, shooter=shooter, record=self.record.copy()))
        ended = self.number >= self.rules["LIMIT"] or max(self.scores) >= self.rules["TARGET"]
        self.state = "none" if ended else "between"
        if ended:
            self.write(0, f"game over hands {self.number}")
            for rank, seat in enumerate(self.ranking(), 1):
                self.write(0, f"rank {rank} {SEATS[seat]} {self.scores[seat]}")
            for line in self.stats_lines():
                self.write(0, line)

    def ranking(self):
        return sorted(range(4), key=lambda seat: (self.scores[seat], seat))

    def stats_lines(self):
        return [f"stats {SEATS[seat]} tricks {s[0]} hearts {s[1]} queens {s[2]} moons {s[3]}"
                for seat, s in enumerate(self.stats)]

    def auto_pass(self):
        for seat in range(4):
            if seat not in self.passes:
                self.pass_cards(seat, self.choose_pass(seat))

    def auto_hand(self):
        if self.state == "passing":
            self.auto_pass()
        while self.state == "playing":
            self.play(self.choose_play())

    def auto_game(self):
        if self.state in ("passing", "playing"):
            self.auto_hand()
        while self.state != "none":
            self.deal()
            self.auto_hand()


def duplicate_card(cards):
    seen = set()
    for card in cards:
        if card in seen:
            fail(f"duplicate card {card_text(card)}")
        seen.add(card)


def validate_rule(name, word):
    if name not in DEFAULT_RULES:
        fail(f"unknown rule {name}")
    if name in ("TARGET", "LIMIT"):
        try:
            value = int(word)
        except ValueError:
            fail(f"bad value {word}")
        if not 1 <= value <= (1000 if name == "TARGET" else 100):
            fail(f"bad value {word}")
        return value
    allowed = ("ADD", "SUB", "AUTO") if name == "MOON" else ("ON", "OFF")
    if name == "PASS":
        good = 1 <= len(word) <= 8 and all(char in "LRAH" for char in word)
    else:
        good = word in allowed
    if not good:
        fail(f"bad value {word}")
    return word


class Table:
    def __init__(self):
        self.rules = DEFAULT_RULES.copy()
        self.bots = ["BASIC"] * 4
        self.game = None

    def active(self):
        return self.game is not None and self.game.state != "none"

    def require_game(self):
        if not self.active():
            fail("no game")

    def require_hand(self):
        if not self.active() or self.game.state not in ("passing", "playing"):
            fail("no hand")

    def require_playing(self):
        if not self.active() or self.game.state != "playing":
            fail("not playing")

    def require_passing(self):
        if not self.active() or self.game.state != "passing":
            fail("not passing")

    def require_between(self):
        self.require_game()
        if self.game.state != "between":
            fail("hand in progress")

    def simulate(self, command, seed, count):
        generator = Generator(seed)
        if command == "GAME":
            game = Game(self.rules, self.bots, generator)
            game.auto_game()
            return [f"game seed {seed}"] + [line for level, line in game.log if level <= count]
        rounds = 4 if command == "ROTATE" else 1
        places = [[0] * 4 for _ in SEATS]
        totals = [0] * 4
        stats = [[0] * 4 for _ in SEATS]
        hands = 0
        for rotation in range(rounds):
            strategies = [None] * 4
            for seat in range(4):
                strategies[(seat + rotation) % 4] = self.bots[seat]
            for _ in range(count):
                game = Game(self.rules, strategies, generator)
                game.auto_game()
                hands += game.number
                ranking = game.ranking()
                for original in range(4):
                    actual = (original + rotation) % 4
                    places[original][ranking.index(actual)] += 1
                    totals[original] += game.scores[actual]
                    stats[original] = [a + b for a, b in zip(stats[original], game.stats[actual])]
        games = rounds * count
        output = [f"{command.lower()} seed {seed} games {games} hands {hands}"]
        for seat in range(4):
            cents = 100 * totals[seat] // games
            average = f"{'-' if cents < 0 else ''}{abs(cents) // 100}.{abs(cents) % 100:02d}"
            name = SEATS[seat] + (f" {self.bots[seat]}" if command == "ROTATE" else "")
            positions = " ".join(map(str, places[seat]))
            tricks, hearts, queens, moons = stats[seat]
            output.append(f"{name} places {positions} total {totals[seat]} average {average} "
                          f"tricks {tricks} hearts {hearts} queens {queens} moons {moons}")
        return output

    def command(self, words):
        command, args = words[0], words[1:]
        known = {"RULE", "BOT", "SETTINGS", "GAME", "MATCH", "ROTATE", "NEW", "ABANDON", "STACK",
                 "DEAL", "SHOW", "PASS", "PLAY", "AUTO", "UNDO", "CLAIM", "LEGAL", "PREVIEW", "SCORE",
                 "TAKEN", "TRICKS", "VOIDS", "UNSEEN", "STATS", "HISTORY", "REPLAY"}
        if command not in known:
            fail(f"unknown command {command}")
        if command == "RULE":
            name, word = args
            value = validate_rule(name, word)
            if self.active():
                fail("game in progress")
            self.rules[name] = value
            return [f"rule {name} {word}"]
        if command == "BOT":
            seat = seat_value(args[0])
            if args[1] not in STRATEGIES:
                fail(f"bad value {args[1]}")
            self.bots[seat] = args[1]
            return [f"bot {SEATS[seat]} {args[1]}"]
        if command == "SETTINGS":
            rule_line = "rules " + " ".join(f"{name} {value}" for name, value in self.rules.items())
            return [rule_line, pairs("bots", self.bots)]
        if command in ("GAME", "MATCH", "ROTATE"):
            seed = bounded(args[0], 1, 2147483646)
            limits = {"GAME": (0, 2), "MATCH": (1, 50), "ROTATE": (1, 10)}
            low, high = limits[command]
            count = bounded(args[1], low, high)
            return self.simulate(command, seed, count)
        if command == "NEW":
            seed = bounded(args[0], 1, 2147483646)
            if self.active():
                fail("game in progress")
            self.game = Game(self.rules, self.bots, Generator(seed))
            return [f"new game seed {seed}"]
        if command == "ABANDON":
            self.require_game()
            self.game = None
            return ["game abandoned"]

        # Validate argument words before any state-dependent checks or mutation.
        seat = None
        cards = []
        if command in ("STACK", "PASS", "PLAY", "CLAIM"):
            seat = seat_value(args[0])
        if command in ("STACK", "PASS", "PLAY"):
            cards = [card_value(word) for word in args[1:]]
        if command == "STACK" and len(cards) != 13:
            fail("need 13 cards")
        if command == "AUTO" and args[0] not in ("PASS", "CARD", "TRICK", "HAND", "GAME"):
            fail(f"bad value {args[0]}")

        if command in ("STACK", "DEAL"):
            self.require_between()
        elif command == "SHOW":
            self.require_hand()
        elif command == "PASS":
            self.require_passing()
        elif command in ("PLAY", "UNDO", "CLAIM", "LEGAL", "PREVIEW", "TAKEN", "TRICKS", "VOIDS", "UNSEEN"):
            self.require_playing()
        elif command in ("SCORE", "STATS", "HISTORY", "REPLAY"):
            self.require_game()
        elif command == "AUTO":
            mode = args[0]
            if mode == "PASS":
                self.require_passing()
            elif mode in ("CARD", "TRICK"):
                self.require_playing()
            elif mode == "HAND":
                self.require_hand()
            else:
                self.require_game()
        game = self.game
        before = len(game.log)
        prefix = []
        if command == "STACK":
            duplicate_card(cards)
            for card in cards:
                owner = next((other for other in range(4) if other != seat and card in game.stacked.get(other, ())), None)
                if owner is not None:
                    fail(f"{card_text(card)} stacked for {SEATS[owner]}")
            game.stacked[seat] = set(cards)
            return [f"stacked {SEATS[seat]}"]
        if command == "DEAL":
            game.deal()
        elif command == "SHOW":
            return [f"{SEATS[seat]}: {cards_text(game.hands[seat])}" for seat in range(4)]
        elif command == "PASS":
            if seat in game.passes:
                fail(f"{SEATS[seat]} already passed")
            duplicate_card(cards)
            for card in cards:
                if card not in game.hands[seat]:
                    fail(f"{SEATS[seat]} does not hold {card_text(card)}")
            game.pass_cards(seat, cards)
        elif command == "PLAY":
            card = cards[0]
            if seat != game.actor():
                fail(f"waiting for {SEATS[game.actor()]}")
            if card not in game.hands[seat]:
                fail(f"{SEATS[seat]} does not hold {card_text(card)}")
            if card not in game.legal():
                if not game.current:
                    fail("must lead 2C" if not game.tricks else "hearts not broken")
                led = game.current[0][1] // 13
                if any(held // 13 == led for held in game.hands[seat]):
                    fail(f"must follow {SUITS[led]}")
                fail("no points on first trick")
            prefix.append(f"{SEATS[seat]} plays {card_text(card)}")
            game.play(card)
        elif command == "AUTO":
            mode = args[0]
            if mode == "PASS":
                game.auto_pass()
            elif mode == "CARD":
                seat = game.actor()
                card = game.choose_play()
                prefix.append(f"{SEATS[seat]} plays {card_text(card)}")
                game.play(card)
            elif mode == "TRICK":
                count = len(game.tricks)
                while game.state == "playing" and len(game.tricks) == count:
                    game.play(game.choose_play())
            elif mode == "HAND":
                game.auto_hand()
            else:
                game.auto_game()
        elif command == "UNDO":
            if not game.undo:
                fail("nothing to undo")
            seat, card = game.undo_card()
            return [f"undo {SEATS[seat]} {card_text(card)}"]
        elif command == "CLAIM":
            if seat != game.actor():
                fail(f"waiting for {SEATS[game.actor()]}")
            if game.current:
                fail("trick in progress")
            for card in game.hands[seat]:
                if any(other_card // 13 == card // 13 and other_card % 13 > card % 13
                       for other in range(4) if other != seat for other_card in game.hands[other]):
                    fail("claim rejected")
            game.claim(seat)
        elif command == "LEGAL":
            return [f"legal {SEATS[game.actor()]}: {cards_text(game.legal())} bot {card_text(game.choose_play())}"]
        elif command == "PREVIEW":
            output = []
            for card in sorted(game.legal()):
                copy = deepcopy(game)
                count = len(copy.tricks)
                copy.play(card)
                while copy.state == "playing" and len(copy.tricks) == count:
                    copy.play(copy.choose_play())
                trick = copy.tricks[-1]
                points = sum(copy.point(played) for _, played in trick)
                output.append(f"preview {card_text(card)} -> {SEATS[copy.winner(trick)]} {points}")
            return output
        elif command == "SCORE":
            output = [pairs("scores", game.scores)]
            if game.state == "playing":
                output.append(pairs("taken", [sum(game.point(card) for card in cards) for cards in game.taken]))
            return output
        elif command == "TAKEN":
            return [f"{SEATS[seat]}: {cards_text(card for card in game.taken[seat] if game.point(card) != 0)}"
                    for seat in range(4)]
        elif command == "TRICKS":
            output = [game.trick_line(trick, number) for number, trick in enumerate(game.tricks, 1)]
            if game.current:
                output.append("current: " + " ".join(f"{SEATS[seat]} {card_text(card)}" for seat, card in game.current))
            return output or ["no tricks"]
        elif command == "VOIDS":
            voids = [set() for _ in SEATS]
            for trick in game.tricks + ([game.current] if game.current else []):
                led = trick[0][1] // 13
                for seat, card in trick:
                    if card // 13 != led:
                        voids[seat].add(led)
            return [pairs("voids", ["".join(SUITS[suit] for suit in sorted(missing)) or "-" for missing in voids])]
        elif command == "UNSEEN":
            seat = game.actor()
            played = set().union(*game.taken) | {card for _, card in game.current}
            unseen = set(range(52)) - game.hands[seat] - played
            return [f"unseen {SEATS[seat]}: {cards_text(unseen)}"]
        elif command == "STATS":
            return game.stats_lines()
        elif command == "HISTORY":
            output = []
            for hand in game.history:
                line = f"hand {hand['number']} pass {hand['direction']} " + pairs("points", hand["points"])
                if hand["shooter"] is not None:
                    line += f" moon {SEATS[hand['shooter']]}"
                output.append(line)
            return output or ["no hands"]
        elif command == "REPLAY":
            hand = int(args[0])
            if not 1 <= hand <= len(game.history):
                fail(f"bad value {args[0]}")
            return game.history[hand - 1]["record"].copy()
        return prefix + [line for _, line in game.log[before:]]


def main():
    table = Table()
    output = []
    lines = sys.stdin.read().splitlines()
    for line in lines[1:int(lines[0]) + 1]:
        try:
            output.extend(table.command(line.split(" ")))
        except CommandError as error:
            output.append(f"error: {error}")
    sys.stdout.write("\n".join(output) + "\n")


if __name__ == "__main__":
    main()
