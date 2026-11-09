MISS = "miss"
HIT = "hit"
CRITICAL = "critical"


class Dice:
    def __init__(self, count, sides):
        self.count = count
        self.sides = sides

    def roll(self, rng):
        return rng.roll(self.count, self.sides)


def parse_dice(token):
    count, sides = token.split("d")
    return Dice(int(count), int(sides))


def resolve_attack(rng, to_hit, defense, dice, bonus):
    roll = 1 + rng.rnd(20)
    if roll == 1:
        return MISS, 0
    if roll == 20:
        outcome = CRITICAL
        damage = dice.roll(rng) + dice.roll(rng) + bonus
    elif roll + to_hit >= defense:
        outcome = HIT
        damage = dice.roll(rng) + bonus
    else:
        return MISS, 0
    return outcome, max(damage, 1)
