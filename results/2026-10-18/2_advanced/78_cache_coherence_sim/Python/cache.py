"""Set-associative caches with LRU, FIFO, and tree pseudo-LRU replacement."""


class Cache:
    def __init__(self, sets, ways, replacement):
        self.number_sets = sets
        self.ways = ways
        self.replacement = replacement
        self.entries = [[None for _ in range(ways)] for _ in range(sets)]
        self.touched = [[0 for _ in range(ways)] for _ in range(sets)]
        self.bits = [[0 for _ in range(ways)] for _ in range(sets)]
        self.fills = [0] * sets
        self.evictions = [0] * sets
        self.clock = 0

    def locate(self, block):
        row = block % self.number_sets
        for way, item in enumerate(self.entries[row]):
            if item is not None and item["block"] == block:
                return row, way
        return None

    def state(self, block):
        where = self.locate(block)
        if where is None:
            return "I"
        row, way = where
        return self.entries[row][way]["state"]

    def change(self, block, state):
        place = self.locate(block)
        if place is not None:
            row, way = place
            self.entries[row][way]["state"] = state

    def touch_way(self, row, way, fill=False):
        if self.replacement == "LRU" or (
                self.replacement == "FIFO" and fill):
            self.clock += 1
            self.touched[row][way] = self.clock
        elif self.replacement == "PLRU":
            lo, hi, node = 0, self.ways, 1
            while hi - lo > 1:
                mid = (lo + hi) // 2
                if way < mid:
                    self.bits[row][node] = 1
                    hi = mid
                    node *= 2
                else:
                    self.bits[row][node] = 0
                    lo = mid
                    node = node * 2 + 1

    def touch(self, block):
        where = self.locate(block)
        if where is not None:
            self.touch_way(*where, fill=False)

    def victim(self, row):
        if self.replacement == "PLRU":
            lo, hi, node = 0, self.ways, 1
            while hi - lo > 1:
                middle = (lo + hi) // 2
                if self.bits[row][node] == 0:
                    hi = middle
                    node *= 2
                else:
                    lo = middle
                    node = node * 2 + 1
            return lo
        return min(range(self.ways),
                   key=lambda way: (self.touched[row][way], way))

    def fill(self, block, state):
        row = block % self.number_sets
        empty = next(
            (way for way, value in enumerate(self.entries[row]) if value is None),
            None,
        )
        way = self.victim(row) if empty is None else empty
        victim = self.entries[row][way]
        if victim is not None:
            self.evictions[row] += 1
        self.entries[row][way] = {"block": block, "state": state}
        self.fills[row] += 1
        self.touch_way(row, way, fill=True)
        return victim

    def remove(self, block):
        where = self.locate(block)
        if where is None:
            return None
        row, way = where
        old = self.entries[row][way]
        self.entries[row][way] = None
        return old

    def order(self, row):
        if self.replacement == "PLRU":
            if self.ways == 1:
                return "-"
            return "".join(str(self.bits[row][index])
                           for index in range(1, self.ways))
        active = [
            way for way, item in enumerate(self.entries[row])
            if item is not None
        ]
        return (" ".join(str(way) for way in sorted(
            active, key=lambda way: (-self.touched[row][way], way)
        )) if active else "-")

    def lines(self):
        for row in self.entries:
            for item in row:
                if item is not None:
                    yield item

    def total_lines(self):
        return sum(1 for _ in self.lines())
