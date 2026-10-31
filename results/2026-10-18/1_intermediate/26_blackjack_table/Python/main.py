import re
import sys


RANKS = "A23456789TJQK"
SUITS = "CDHS"
BLACK_SUITS = "CS"
SEAT_COUNT = 7
MODULUS = 2147483647
MULTIPLIER = 48271
RULE_DEFAULTS = {
    "DEALER": "S17", "PEN": "75", "MIN": "10", "MAX": "500",
    "BJ": "3:2", "DAS": "ON", "DOUBLE": "ANY", "HANDS": "4",
    "RSA": "OFF", "SURRENDER": "ON", "CHARLIE": "0", "SIDEMAX": "25",
}
RULE_CHOICES = {
    "DEALER": ("S17", "H17"),
    "BJ": ("3:2", "6:5"),
    "DAS": ("ON", "OFF"),
    "DOUBLE": ("ANY", "9-11", "10-11"),
    "RSA": ("ON", "OFF"),
    "SURRENDER": ("ON", "OFF"),
    "CHARLIE": ("0", "5", "6", "7"),
}
RULE_RANGES = {
    "PEN": (50, 90),
    "MIN": (1, 10000),
    "MAX": (1, 10000),
    "HANDS": (1, 4),
    "SIDEMAX": (0, 1000),
}
SIDE_PAYOUTS = {"perfect": 25, "colored": 12, "mixed": 6, "lose": -1}
SYMBOL_ACTIONS = {
    "S": ("stand", "stand"),
    "H": ("hit", "hit"),
    "D": ("double", "hit"),
    "Ds": ("double", "stand"),
    "R": ("surrender", "hit"),
}
STAT_FIELDS = (
    "rounds", "hands", "wins", "losses", "pushes",
    "blackjacks", "busts", "surrenders", "doubles", "splits",
)
WIN_RESULTS = ("blackjack", "charlie", "win")
LOSS_RESULTS = ("lose", "bust", "surrender")
COUNTED_RESULTS = {"blackjack": "blackjacks", "bust": "busts", "surrender": "surrenders"}
DECIDED_REASONS = ("bust", "surrender", "charlie")


class CommandError(Exception):
    pass


def valid_integer(word, minimum, maximum):
    if re.fullmatch(r"0|[1-9][0-9]{0,9}", word) is None:
        return False
    return minimum <= int(word) <= maximum


def integer_value(word, minimum, maximum):
    if not valid_integer(word, minimum, maximum):
        raise CommandError(f"bad value {word}")
    return int(word)


def valid_rule_value(name, value):
    if name in RULE_CHOICES:
        return value in RULE_CHOICES[name]
    minimum, maximum = RULE_RANGES[name]
    return valid_integer(value, minimum, maximum)


def signed(value):
    return f"{value:+d}"


def true_count(running, remaining):
    value = abs(running) * 5200 // remaining
    sign = "-" if running < 0 else ""
    return f"{sign}{value // 100}.{value % 100:02d}"


def side_result(first, second):
    if first.rank != second.rank:
        return "lose"
    if first.suit == second.suit:
        return "perfect"
    if first.is_black() == second.is_black():
        return "colored"
    return "mixed"


def hand_profit(result, bet, blackjack_rule):
    if result == "blackjack":
        return bet * 3 // 2 if blackjack_rule == "3:2" else bet * 6 // 5
    if result in ("win", "charlie"):
        return bet
    if result == "push":
        return 0
    if result == "surrender":
        return bet // 2 - bet
    return -bet


def pair_split_wanted(value, upcard):
    if value in (1, 8):
        return True
    if value == 9:
        return upcard not in (7, 10, 11)
    if value in (2, 3, 7):
        return upcard <= 7
    if value == 6:
        return upcard <= 6
    if value == 4:
        return upcard in (5, 6)
    return False


def soft_symbol(total, upcard):
    if total >= 19:
        return "S"
    if total == 18:
        if 3 <= upcard <= 6:
            return "Ds"
        return "S" if upcard in (2, 7, 8) else "H"
    if total == 17:
        return "D" if 3 <= upcard <= 6 else "H"
    if total >= 15:
        return "D" if 4 <= upcard <= 6 else "H"
    if total >= 13:
        return "D" if upcard in (5, 6) else "H"
    return "H"


def hard_symbol(total, upcard):
    if total >= 17:
        return "S"
    if total >= 13:
        if upcard <= 6:
            return "S"
        if (total == 16 and upcard >= 9) or (total == 15 and upcard == 10):
            return "R"
        return "H"
    if total == 12:
        return "S" if 4 <= upcard <= 6 else "H"
    if total == 11:
        return "D" if upcard <= 10 else "H"
    if total == 10:
        return "D" if upcard <= 9 else "H"
    if total == 9:
        return "D" if 3 <= upcard <= 6 else "H"
    return "H"


class Card:
    def __init__(self, rank, suit):
        self.rank = rank
        self.suit = suit
        self.code = rank + suit
        self.value = min(RANKS.index(rank) + 1, 10)

    def is_black(self):
        return self.suit in BLACK_SUITS

    def hi_lo(self):
        if 2 <= self.value <= 6:
            return 1
        if 7 <= self.value <= 9:
            return 0
        return -1


class Shoe:
    def __init__(self, decks, seed):
        self.decks = decks
        self.size = 52 * decks
        self.state = seed
        self.cards = []
        self.drawn = 0
        self.running = 0
        self.shuffle()

    def next_random(self):
        self.state = MULTIPLIER * self.state % MODULUS
        return self.state

    def shuffle(self):
        self.cards = [
            Card(rank, suit)
            for _ in range(self.decks) for suit in SUITS for rank in RANKS
        ]
        for i in range(self.size - 1, 0, -1):
            j = self.next_random() % (i + 1)
            self.cards[i], self.cards[j] = self.cards[j], self.cards[i]
        self.drawn = 0
        self.running = 0

    def draw(self, face_up=True):
        card = self.cards[self.drawn]
        self.drawn += 1
        if face_up:
            self.running += card.hi_lo()
        return card

    def reveal(self, card):
        self.running += card.hi_lo()

    def cut(self, penetration):
        return self.size * penetration // 100

    def remaining(self):
        return self.size - self.drawn


class Hand:
    def __init__(self, bet, split=False, split_aces=False):
        self.cards = []
        self.bet = bet
        self.split = split
        self.split_aces = split_aces
        self.finished = False
        self.reason = None

    def add(self, card):
        self.cards.append(card)

    def total(self):
        points = sum(card.value for card in self.cards)
        if any(card.rank == "A" for card in self.cards) and points + 10 <= 21:
            return points + 10, True
        return points, False

    def is_bust(self):
        return self.total()[0] > 21

    def is_blackjack(self):
        return not self.split and len(self.cards) == 2 and self.total()[0] == 21

    def finish(self, reason):
        self.finished = True
        self.reason = reason

    def display(self):
        total, soft = self.total()
        if self.is_blackjack():
            status = "blackjack"
        elif total > 21:
            status = f"bust {total}"
        elif soft:
            status = f"soft {total}"
        else:
            status = str(total)
        return " ".join(card.code for card in self.cards) + f" ({status})"


class Player:
    def __init__(self, name, seat, bankroll):
        self.name = name
        self.seat = seat
        self.bankroll = bankroll
        self.bet = 0
        self.side = 0
        self.insurance = 0
        self.hands = []
        self.stats = dict.fromkeys(STAT_FIELDS, 0)
        self.net = 0

    def hand_name(self, index):
        return f"{self.name}[{index + 1}]"

    def record(self, result):
        self.stats["hands"] += 1
        if result in WIN_RESULTS:
            self.stats["wins"] += 1
        elif result in LOSS_RESULTS:
            self.stats["losses"] += 1
        else:
            self.stats["pushes"] += 1
        if result in COUNTED_RESULTS:
            self.stats[COUNTED_RESULTS[result]] += 1


class BlackjackTable:
    def __init__(self):
        self.rules = dict(RULE_DEFAULTS)
        self.seats = [None] * SEAT_COUNT
        self.players = {}
        self.shoe = None
        self.state = "idle"
        self.round_number = 0
        self.participants = []
        self.insurance_turn = 0
        self.dealer = Hand(0)
        self.dealer_blackjack = False
        self.dealer_blackjacks = 0
        self.dealer_busts = 0
        self.output = []
        self.handlers = {
            "SHOE": self.new_shoe,
            "RULE": self.set_rule,
            "RULES": self.show_rules,
            "PLAYER": self.seat_player,
            "LEAVE": self.leave,
            "REBUY": self.rebuy,
            "BET": self.place_bet,
            "SIDE": self.place_side,
            "DEAL": self.deal,
            "INSURANCE": self.insure,
            "HIT": self.hit,
            "STAND": self.stand,
            "DOUBLE": self.double,
            "SPLIT": self.split,
            "SURRENDER": self.surrender,
            "HINT": self.hint,
            "AUTO": self.auto,
            "STATUS": self.status,
            "COUNT": self.count,
            "STATS": self.stats,
        }

    def emit(self, *parts):
        self.output.append(" ".join(str(part) for part in parts))

    def rule_number(self, name):
        return int(self.rules[name])

    def seated(self):
        return [player for player in self.seats if player is not None]

    def require_player(self, name):
        if name not in self.players:
            raise CommandError(f"unknown player {name}")
        return self.players[name]

    def require_idle(self):
        if self.state != "idle":
            raise CommandError("round in progress")

    def require_round(self):
        if self.state == "idle":
            raise CommandError("no round")
        if self.state == "insurance":
            raise CommandError("insurance pending")

    def require_shoe(self):
        if self.shoe is None:
            raise CommandError("no shoe")

    def current_hand(self):
        for player in self.participants:
            for index, hand in enumerate(player.hands):
                if not hand.finished:
                    return player, index
        return None

    def require_turn(self, name):
        player = self.require_player(name)
        self.require_round()
        owner, index = self.current_hand()
        if owner is not player:
            raise CommandError(f"waiting for {owner.hand_name(index)}")
        return player, index

    def upcard_value(self):
        value = self.dealer.cards[0].value
        return 11 if value == 1 else value

    def can_resplit_aces(self, player, hand):
        return (
            all(card.rank == "A" for card in hand.cards)
            and self.rules["RSA"] == "ON"
            and len(player.hands) < self.rule_number("HANDS")
        )

    def auto_finish(self, player, hand):
        total = hand.total()[0]
        charlie = self.rule_number("CHARLIE")
        if total > 21:
            hand.finish("bust")
        elif charlie != 0 and len(hand.cards) == charlie:
            hand.finish("charlie")
        elif total == 21:
            hand.finish("stand")
        elif hand.split_aces and len(hand.cards) == 2 and not self.can_resplit_aces(player, hand):
            hand.finish("stand")

    def double_allowed(self, hand):
        total, soft = hand.total()
        rule = self.rules["DOUBLE"]
        if rule == "9-11" and (soft or not 9 <= total <= 11):
            return False
        if rule == "10-11" and (soft or not 10 <= total <= 11):
            return False
        return not (self.rules["DAS"] == "OFF" and hand.split)

    def action_error(self, action, player, hand):
        if action == "hit":
            if hand.split_aces:
                return "split aces"
        elif action == "double":
            if hand.split_aces:
                return "split aces"
            if len(hand.cards) != 2:
                return "two cards only"
            if not self.double_allowed(hand):
                return "double not allowed"
            if player.bankroll < hand.bet:
                return "insufficient funds"
        elif action == "split":
            if len(hand.cards) != 2:
                return "two cards only"
            if hand.cards[0].value != hand.cards[1].value:
                return "not a pair"
            if len(player.hands) >= self.rule_number("HANDS"):
                return "hand limit"
            if player.bankroll < hand.bet:
                return "insufficient funds"
        elif action == "surrender":
            if self.rules["SURRENDER"] == "OFF" or hand.split:
                return "surrender not allowed"
            if len(hand.cards) != 2:
                return "two cards only"
        return None

    def possible(self, action, player, hand):
        return self.action_error(action, player, hand) is None

    def recommendation(self, player, hand):
        if hand.split_aces:
            return "split" if self.possible("split", player, hand) else "stand"
        upcard = self.upcard_value()
        if (
            len(hand.cards) == 2
            and hand.cards[0].value == hand.cards[1].value
            and self.possible("split", player, hand)
            and pair_split_wanted(hand.cards[0].value, upcard)
        ):
            return "split"
        total, soft = hand.total()
        symbol = soft_symbol(total, upcard) if soft else hard_symbol(total, upcard)
        preferred, fallback = SYMBOL_ACTIONS[symbol]
        return preferred if self.possible(preferred, player, hand) else fallback

    def split_hand(self, player, index):
        hand = player.hands[index]
        first, second = hand.cards
        player.bankroll -= hand.bet
        player.stats["splits"] += 1
        self.emit(f"{player.hand_name(index)} splits {first.code} {second.code}")
        aces = first.rank == "A"
        hand.cards = [first]
        hand.split = True
        hand.split_aces = aces
        new_hand = Hand(hand.bet, True, aces)
        new_hand.add(second)
        player.hands.insert(index + 1, new_hand)
        hand.add(self.shoe.draw())
        self.emit(f"{player.hand_name(index)}: {hand.display()}")
        self.auto_finish(player, hand)

    def perform(self, action, player, index):
        hand = player.hands[index]
        name = player.hand_name(index)
        if action == "hit":
            hand.add(self.shoe.draw())
            self.emit(f"{name} hits: {hand.display()}")
            self.auto_finish(player, hand)
        elif action == "stand":
            hand.finish("stand")
            self.emit(f"{name} stands: {hand.display()}")
        elif action == "double":
            player.bankroll -= hand.bet
            hand.bet *= 2
            player.stats["doubles"] += 1
            hand.add(self.shoe.draw())
            self.emit(f"{name} doubles: {hand.display()}")
            self.auto_finish(player, hand)
            if not hand.finished:
                hand.finish("stand")
        elif action == "split":
            self.split_hand(player, index)
        else:
            hand.finish("surrender")
            self.emit(f"{name} surrenders: {hand.display()}")
        self.advance()

    def advance(self):
        while True:
            current = self.current_hand()
            if current is None:
                self.dealer_turn()
                return
            player, index = current
            hand = player.hands[index]
            if len(hand.cards) >= 2:
                return
            hand.add(self.shoe.draw())
            self.emit(f"{player.hand_name(index)}: {hand.display()}")
            self.auto_finish(player, hand)

    def reveal_dealer(self):
        self.shoe.reveal(self.dealer.cards[1])
        self.emit("dealer:", self.dealer.display())

    def dealer_hits(self):
        total, soft = self.dealer.total()
        return total <= 16 or (total == 17 and soft and self.rules["DEALER"] == "H17")

    def dealer_turn(self):
        self.reveal_dealer()
        if any(
            hand.reason not in DECIDED_REASONS and not hand.is_blackjack()
            for player in self.participants for hand in player.hands
        ):
            drew = False
            while self.dealer_hits():
                self.dealer.add(self.shoe.draw())
                self.emit("dealer hits:", self.dealer.display())
                drew = True
            if drew and self.dealer.is_bust():
                self.dealer_busts += 1
        self.settle()

    def hand_result(self, hand, dealer_total):
        if self.dealer_blackjack:
            return "push" if hand.is_blackjack() else "lose"
        if hand.is_blackjack():
            return "blackjack"
        if hand.reason in DECIDED_REASONS:
            return hand.reason
        total = hand.total()[0]
        if dealer_total > 21 or total > dealer_total:
            return "win"
        if total == dealer_total:
            return "push"
        return "lose"

    def settle(self):
        dealer_total = self.dealer.total()[0]
        for player in self.participants:
            for index, hand in enumerate(player.hands):
                result = self.hand_result(hand, dealer_total)
                profit = hand_profit(result, hand.bet, self.rules["BJ"])
                player.bankroll += hand.bet + profit
                player.net += profit
                player.record(result)
                self.emit(player.hand_name(index), result, signed(profit))
            self.emit(player.name, "bankroll", player.bankroll)
        for player in self.seated():
            player.bet = 0
            player.side = 0
        self.participants = []
        self.state = "idle"

    def peek(self):
        self.dealer_blackjack = self.dealer.is_blackjack()
        if self.dealer_blackjack:
            self.emit("dealer peeks: blackjack")
        else:
            self.emit("dealer peeks: no blackjack")
        for player in self.participants:
            if player.insurance != 0:
                if self.dealer_blackjack:
                    profit = player.insurance * 2
                else:
                    profit = -player.insurance
                player.bankroll += player.insurance + profit
                player.net += profit
                self.emit(player.name, "insurance", signed(profit))
        if self.dealer_blackjack:
            self.dealer_blackjacks += 1
            self.reveal_dealer()
            self.settle()
        else:
            self.state = "play"
            self.advance()

    def settle_side(self, player):
        first, second = player.hands[0].cards
        result = side_result(first, second)
        profit = player.side * SIDE_PAYOUTS[result]
        player.bankroll += player.side + profit
        player.net += profit
        self.emit(player.name, "side", result, signed(profit))

    def deal_cards(self):
        for player in self.participants:
            player.hands = [Hand(player.bet)]
            player.hands[0].add(self.shoe.draw())
        self.dealer = Hand(0)
        self.dealer.add(self.shoe.draw())
        for player in self.participants:
            player.hands[0].add(self.shoe.draw())
        self.dealer.add(self.shoe.draw(False))

    def new_shoe(self, arguments):
        decks = integer_value(arguments[0], 1, 8)
        seed = integer_value(arguments[1], 1, MODULUS - 1)
        self.require_idle()
        self.shoe = Shoe(decks, seed)
        cut = self.shoe.cut(self.rule_number("PEN"))
        self.emit("shoe", decks, "decks", self.shoe.size, "cards", "cut", cut)

    def set_rule(self, arguments):
        name, value = arguments
        if name not in RULE_DEFAULTS:
            raise CommandError(f"unknown rule {name}")
        if not valid_rule_value(name, value):
            raise CommandError(f"bad value {value}")
        self.require_idle()
        minimum = int(value) if name == "MIN" else self.rule_number("MIN")
        maximum = int(value) if name == "MAX" else self.rule_number("MAX")
        if minimum > maximum:
            raise CommandError("min above max")
        self.rules[name] = value
        self.emit("rule", name, value)

    def show_rules(self, arguments):
        parts = ["rules"]
        for name, value in self.rules.items():
            parts.extend((name, value))
        self.emit(*parts)

    def seat_player(self, arguments):
        name = arguments[0]
        if re.fullmatch(r"[A-Z]{1,8}", name) is None:
            raise CommandError(f"bad name {name}")
        bankroll = integer_value(arguments[1], 1, 1000000)
        self.require_idle()
        if name in self.players:
            raise CommandError("player exists")
        if None not in self.seats:
            raise CommandError("table full")
        seat = self.seats.index(None) + 1
        player = Player(name, seat, bankroll)
        self.seats[seat - 1] = player
        self.players[name] = player
        self.emit(name, "sits at seat", seat, "with", bankroll)

    def leave(self, arguments):
        player = self.require_player(arguments[0])
        self.require_idle()
        self.seats[player.seat - 1] = None
        del self.players[player.name]
        self.emit(player.name, "leaves with", player.bankroll, "net", signed(player.net))

    def rebuy(self, arguments):
        player = self.require_player(arguments[0])
        amount = integer_value(arguments[1], 1, 1000000)
        self.require_idle()
        player.bankroll += amount
        self.emit(player.name, "rebuys", amount, "bankroll", player.bankroll)

    def place_bet(self, arguments):
        player = self.require_player(arguments[0])
        amount = integer_value(arguments[1], 0, 1000000)
        self.require_idle()
        if amount == 0:
            player.bet = 0
            player.side = 0
            self.emit(player.name, "bet cleared")
            return
        if not self.rule_number("MIN") <= amount <= self.rule_number("MAX"):
            raise CommandError("bet out of limits")
        if amount + player.side > player.bankroll:
            raise CommandError("insufficient funds")
        player.bet = amount
        self.emit(player.name, "bets", amount)

    def place_side(self, arguments):
        player = self.require_player(arguments[0])
        amount = integer_value(arguments[1], 0, 1000000)
        self.require_idle()
        if amount == 0:
            player.side = 0
            self.emit(player.name, "side cleared")
            return
        if player.bet == 0:
            raise CommandError("no bet")
        if amount > self.rule_number("SIDEMAX"):
            raise CommandError("side out of limits")
        if player.bet + amount > player.bankroll:
            raise CommandError("insufficient funds")
        player.side = amount
        self.emit(player.name, "side", amount)

    def deal(self, arguments):
        self.require_idle()
        self.require_shoe()
        participants = [player for player in self.seated() if player.bet != 0]
        if not participants:
            raise CommandError("no bets")
        if self.shoe.drawn >= self.shoe.cut(self.rule_number("PEN")):
            self.shoe.shuffle()
            self.emit("shuffle")
        self.round_number += 1
        self.emit("round", self.round_number)
        self.participants = participants
        self.dealer_blackjack = False
        for player in participants:
            player.bankroll -= player.bet + player.side
            player.insurance = 0
            player.stats["rounds"] += 1
        self.deal_cards()
        for player in participants:
            hand = player.hands[0]
            if hand.is_blackjack():
                hand.finish("blackjack")
            self.emit(f"{player.hand_name(0)}: {hand.display()}")
        upcard = self.dealer.cards[0]
        self.emit("dealer:", upcard.code, "??")
        for player in participants:
            if player.side != 0:
                self.settle_side(player)
        if upcard.rank == "A":
            self.state = "insurance"
            self.insurance_turn = 0
            self.emit("insurance offered")
        elif upcard.value == 10:
            self.peek()
        else:
            self.state = "play"
            self.advance()

    def insure(self, arguments):
        player = self.require_player(arguments[0])
        amount = integer_value(arguments[1], 0, 1000000)
        if self.state != "insurance":
            raise CommandError("no insurance")
        turn = self.participants[self.insurance_turn]
        if player is not turn:
            raise CommandError(f"waiting for {turn.name}")
        if amount > player.bet // 2:
            raise CommandError("insurance out of limits")
        if amount > player.bankroll:
            raise CommandError("insufficient funds")
        player.bankroll -= amount
        player.insurance = amount
        if amount == 0:
            self.emit(player.name, "declines insurance")
        else:
            self.emit(player.name, "insures", amount)
        self.insurance_turn += 1
        if self.insurance_turn == len(self.participants):
            self.peek()

    def play(self, action, arguments):
        player, index = self.require_turn(arguments[0])
        error = self.action_error(action, player, player.hands[index])
        if error is not None:
            raise CommandError(error)
        self.perform(action, player, index)

    def hit(self, arguments):
        self.play("hit", arguments)

    def stand(self, arguments):
        self.play("stand", arguments)

    def double(self, arguments):
        self.play("double", arguments)

    def split(self, arguments):
        self.play("split", arguments)

    def surrender(self, arguments):
        self.play("surrender", arguments)

    def hint(self, arguments):
        self.require_round()
        player, index = self.current_hand()
        action = self.recommendation(player, player.hands[index])
        self.emit(f"hint {player.hand_name(index)}: {action}")

    def auto(self, arguments):
        player, index = self.require_turn(arguments[0])
        while True:
            self.perform(self.recommendation(player, player.hands[index]), player, index)
            if self.state != "play":
                return
            owner, index = self.current_hand()
            if owner is not player:
                return

    def status(self, arguments):
        if self.state == "idle":
            self.emit("table idle round", self.round_number)
        elif self.state == "insurance":
            turn = self.participants[self.insurance_turn]
            self.emit("table insurance round", self.round_number, "next", turn.name)
        else:
            owner, index = self.current_hand()
            self.emit("table play round", self.round_number, "turn", owner.hand_name(index))
        if self.state != "idle":
            self.emit("dealer:", self.dealer.cards[0].code, "??")
        for player in self.seated():
            self.emit(
                "seat", player.seat, player.name, "bankroll", player.bankroll,
                "bet", player.bet, "side", player.side,
            )
            if player in self.participants:
                for index, hand in enumerate(player.hands):
                    self.emit(f"{player.hand_name(index)}: {hand.display()} bet {hand.bet}")

    def count(self, arguments):
        self.require_shoe()
        remaining = self.shoe.remaining()
        running = self.shoe.running
        self.emit(
            "count running", running, "true", true_count(running, remaining),
            "remaining", remaining,
        )

    def stats(self, arguments):
        players = self.seated()
        if not players:
            raise CommandError("no players")
        for player in players:
            parts = ["stats", player.name]
            for field in STAT_FIELDS:
                parts.extend((field, player.stats[field]))
            parts.extend(("net", signed(player.net)))
            self.emit(*parts)
        self.emit(
            "stats dealer rounds", self.round_number,
            "blackjacks", self.dealer_blackjacks, "busts", self.dealer_busts,
        )

    def execute(self, line):
        command, *arguments = line.split()
        try:
            if command not in self.handlers:
                raise CommandError(f"unknown command {command}")
            self.handlers[command](arguments)
        except CommandError as error:
            self.emit("error:", error)


def main():
    table = BlackjackTable()
    count = int(sys.stdin.readline())
    for _ in range(count):
        table.execute(sys.stdin.readline().rstrip("\n"))
    if table.output:
        sys.stdout.write("\n".join(table.output) + "\n")


if __name__ == "__main__":
    main()
