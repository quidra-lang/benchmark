from math import isqrt


def squared_distance(first, second):
    dx = first[0] - second[0]
    dy = first[1] - second[1]
    return dx * dx + dy * dy


def scaled(delta, step, length):
    if delta >= 0:
        return delta * step // length
    return -(-delta * step // length)


def advance(point, goal, step):
    dx = goal[0] - point[0]
    dy = goal[1] - point[1]
    squared = dx * dx + dy * dy
    if squared <= step * step:
        return goal, True
    length = isqrt(squared)
    return (point[0] + scaled(dx, step, length), point[1] + scaled(dy, step, length)), False


def damage_dealt(hp, power, armor):
    return min(hp, max(1, power - armor))


class Effect:
    def __init__(self):
        self.strength = 0
        self.remaining = 0
        self.source = None

    def active(self):
        return self.remaining > 0

    def receive(self, strength, duration, source=None):
        if strength > self.strength:
            self.strength = strength
            self.remaining = duration
            self.source = source
        elif strength == self.strength:
            self.remaining = max(self.remaining, duration)

    def advance_time(self):
        self.remaining -= 1
        if self.remaining == 0:
            self.strength = 0
            self.source = None


class Projectile:
    def __init__(
        self, number, tower, target, position, aim, targets, power, speed, splash,
        slow_rate, slow_time, burn_amount, burn_time,
    ):
        self.number = number
        self.tower = tower
        self.target = target
        self.position = position
        self.aim = aim
        self.targets = targets
        self.power = power
        self.speed = speed
        self.splash = splash
        self.slow_rate = slow_rate
        self.slow_time = slow_time
        self.burn_amount = burn_amount
        self.burn_time = burn_time

    def fly(self):
        if self.speed == 0:
            return True
        self.position, arrived = advance(self.position, self.aim, self.speed)
        return arrived
