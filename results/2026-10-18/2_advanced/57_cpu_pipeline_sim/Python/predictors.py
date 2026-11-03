"""Direct-mapped BTB, bounded return stack and branch direction predictors."""


class BTB:
    def __init__(self, entries):
        self.entries = [None] * entries

    def lookup(self, pc):
        entry = self.entries[(pc // 4) % len(self.entries)]
        return entry[1] if entry is not None and entry[0] == pc else None

    def insert(self, pc, target):
        self.entries[(pc // 4) % len(self.entries)] = pc, target


class RAS:
    def __init__(self, depth):
        self.depth = depth
        self.stack = []

    def push(self, address):
        if self.depth == 0:
            return
        if len(self.stack) == self.depth:
            self.stack.pop(0)
        self.stack.append(address)

    def pop(self):
        return self.stack.pop() if self.stack else None


def updated(counter, taken):
    return min(3, counter + 1) if taken else max(0, counter - 1)


class DirectionPredictor:
    def __init__(self, scheme, parameters):
        self.scheme = scheme
        self.parameters = parameters
        self.history = 0
        if scheme in ("ONEBIT", "TWOBIT", "GSHARE"):
            self.table = [0 if scheme == "ONEBIT" else 1] * parameters[0]
        elif scheme == "TOURNAMENT":
            local, global_size, _, chooser = parameters
            self.local = [1] * local
            self.global_table = [1] * global_size
            self.chooser = [1] * chooser

    def prediction(self, pc, target):
        if self.scheme in ("STATIC_NT", "PERFECT"):
            return False
        if self.scheme == "BTFN":
            return target < pc
        if self.scheme == "ONEBIT":
            return self.table[(pc // 4) % len(self.table)] == 1
        if self.scheme == "TWOBIT":
            return self.table[(pc // 4) % len(self.table)] >= 2
        if self.scheme == "GSHARE":
            return self.table[((pc // 4) ^ self.history) % len(self.table)] >= 2
        local = self.local[(pc // 4) % len(self.local)] >= 2
        global_prediction = self.global_table[((pc // 4) ^ self.history) % len(self.global_table)] >= 2
        chooser = self.chooser[(pc // 4) % len(self.chooser)]
        return global_prediction if chooser >= 2 else local

    def update(self, pc, taken):
        if self.scheme in ("STATIC_NT", "BTFN", "PERFECT"):
            return
        if self.scheme == "TOURNAMENT":
            local_index = (pc // 4) % len(self.local)
            global_index = ((pc // 4) ^ self.history) % len(self.global_table)
            chooser_index = (pc // 4) % len(self.chooser)
            local = self.local[local_index] >= 2
            global_prediction = self.global_table[global_index] >= 2
            if local != global_prediction:
                self.chooser[chooser_index] = updated(self.chooser[chooser_index], global_prediction == taken)
            self.local[local_index] = updated(self.local[local_index], taken)
            self.global_table[global_index] = updated(self.global_table[global_index], taken)
            self.history = (2 * self.history + int(taken)) % (1 << self.parameters[2])
        else:
            index = (((pc // 4) ^ self.history) if self.scheme == "GSHARE" else pc // 4) % len(self.table)
            self.table[index] = int(taken) if self.scheme == "ONEBIT" else updated(self.table[index], taken)
            if self.scheme == "GSHARE":
                self.history = (2 * self.history + int(taken)) % (1 << self.parameters[1])

    def storage_bits(self):
        if self.scheme in ("STATIC_NT", "BTFN", "PERFECT"):
            return 0
        if self.scheme == "ONEBIT":
            return self.parameters[0]
        if self.scheme == "TWOBIT":
            return 2 * self.parameters[0]
        if self.scheme == "GSHARE":
            return 2 * self.parameters[0] + self.parameters[1]
        local, global_size, history, chooser = self.parameters
        return 2 * (local + global_size + chooser) + history
