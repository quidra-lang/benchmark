LETTERS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
SIZE_CLASSES = ("1", "2-3", "4-7", "8-15", "16+")
SIZE_CLASS_LIMITS = (1, 3, 7, 15)


class HeapObject:
    def __init__(self, number, pointers, data):
        self.number = number
        self.size = 1 + pointers + data
        self.fields = [None] * pointers
        self.address = 0
        self.marked = False
        self.moves = 0
        self.age = 0
        self.count = 0


class Pair:
    def __init__(self):
        self.count = 0
        self.words = 0

    def add(self, obj):
        self.count += 1
        self.words += obj.size

    def add_pair(self, other):
        self.count += other.count
        self.words += other.words

    def __str__(self):
        return f"{self.count} {self.words}"


class CollectionRecord:
    def __init__(self, number, line, request, kind, blocks):
        self.number = number
        self.line = line
        self.request = request
        self.kind = kind
        self.live = Pair()
        self.freed = Pair()
        self.moved = Pair()
        self.promoted = Pair()
        self.stack = 0
        self.work = 0
        self.before = (total_free(blocks), largest_free(blocks))
        self.after = (0, 0)

    def finish(self, blocks):
        self.after = (total_free(blocks), largest_free(blocks))


def by_address(objects):
    return sorted(objects, key=lambda obj: obj.address)


def free_blocks(objects, start, end):
    blocks = []
    position = start
    for obj in by_address(objects):
        if obj.address < start or obj.address >= end:
            continue
        if obj.address > position:
            blocks.append((position, obj.address - position))
        position = obj.address + obj.size
    if position < end:
        blocks.append((position, end - position))
    return blocks


def first_fit(blocks, size):
    for address, length in blocks:
        if length >= size:
            return address
    return None


def total_free(blocks):
    return sum(length for _, length in blocks)


def largest_free(blocks):
    return max((length for _, length in blocks), default=0)


def dec2(numerator, denominator):
    rounded = (200 * numerator + denominator) // (2 * denominator)
    return f"{rounded // 100}.{rounded % 100:02d}"


def pct(part, whole):
    if whole == 0:
        return "-"
    return dec2(100 * part, whole)


def size_class(value):
    for index, limit in enumerate(SIZE_CLASS_LIMITS):
        if value <= limit:
            return index
    return len(SIZE_CLASS_LIMITS)


def class_table(values):
    counts = [0] * len(SIZE_CLASSES)
    for value in values:
        counts[size_class(value)] += 1
    return " ".join(f"{label}:{count}" for label, count in zip(SIZE_CLASSES, counts))


def heap_map(size, objects, reachable, inactive):
    cells = ["."] * size
    start, end = inactive
    for address in range(start, end):
        cells[address] = "-"
    for obj in objects:
        letter = LETTERS[(obj.number - 1) % len(LETTERS)]
        if obj.number in reachable:
            header, body = letter, letter.lower()
        else:
            header, body = "#", "="
        cells[obj.address] = header
        for address in range(obj.address + 1, obj.address + obj.size):
            cells[address] = body
    return "".join(cells)
