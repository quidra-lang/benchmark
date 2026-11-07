import sys


MODES = ("FIRST", "NEXT", "BEST", "WORST", "SEGFIT", "BUDDY")
HEAPLESS_COMMANDS = ("HEAP", "BENCH")
COUNTERS = ("allocs", "frees", "reallocs", "moves", "failures", "collected")
UNIT = 8
HEADER = 8
MIN_BLOCK = 16
MIN_BUDDY_BLOCK = 32
MIN_HEAP = 32
MAX_HEAP = 65536
DEFAULT_ALIGNMENT = 8
MAX_ALIGNMENT = 4096
MAP_WIDTH = 64
UNINITIALIZED = -1
RANDOM_MULTIPLIER = 48271
RANDOM_MODULUS = 2147483647


class CommandError(Exception):
    pass


def is_power_of_two(value):
    return value > 0 and value & (value - 1) == 0


def size_class(size):
    return size.bit_length() - 1


def fragmentation_percent(free, largest):
    return (free - largest) * 100 // free if free > 0 else 0


def next_random(state):
    return RANDOM_MULTIPLIER * state % RANDOM_MODULUS


def byte_text(value):
    return "?" if value == UNINITIALIZED else str(value)


class Block:
    def __init__(self, start, size):
        self.start = start
        self.size = size
        self.used = False
        self.owner = None
        self.requested = 0
        self.contents = []
        self.stamp = 0

    def end(self):
        return self.start + self.size

    def payload(self):
        return self.start + HEADER

    def area(self):
        return f"{self.start}+{self.size}"

    def map_units(self):
        rest = self.size // UNIT - 1
        if not self.used:
            return "F" + "." * rest
        return "H" + "".join("#" if UNIT * unit < self.requested else "-" for unit in range(rest))


class Heap:
    def __init__(self, mode, size):
        self.mode = mode
        self.size = size
        self.rover = 0
        self.registrations = 0
        self.blocks = [self.register(Block(0, size))]

    def register(self, block):
        self.registrations += 1
        block.stamp = self.registrations
        return block

    def is_buddy(self):
        return self.mode == "BUDDY"

    def required_length(self, request):
        length = (request + UNIT - 1) // UNIT * UNIT + HEADER
        if not self.is_buddy():
            return length
        power = MIN_BUDDY_BLOCK
        while power < length:
            power *= 2
        return power

    def locate(self, address):
        index = 0
        while self.blocks[index].end() <= address:
            index += 1
        return index

    def used_blocks(self):
        return [block for block in self.blocks if block.used]

    def free_blocks(self):
        return [block for block in self.blocks if not block.used]

    def used_total(self):
        return sum(block.size for block in self.used_blocks())

    def fragmentation(self):
        sizes = [block.size for block in self.free_blocks()]
        return fragmentation_percent(sum(sizes), max(sizes, default=0))

    def placement(self, block, alignment):
        place = (block.start + HEADER + alignment - 1) // alignment * alignment - HEADER
        if 0 < place - block.start < MIN_BLOCK:
            place += alignment
        return place

    def rank(self, index, rover_index):
        block = self.blocks[index]
        if self.mode == "NEXT":
            return (index - rover_index) % len(self.blocks), 0
        if self.mode in ("BEST", "BUDDY"):
            return block.size, block.start
        if self.mode == "WORST":
            return -block.size, block.start
        if self.mode == "SEGFIT":
            return size_class(block.size), -block.stamp
        return block.start, 0

    def choose(self, length, alignment):
        rover_index = self.locate(self.rover)
        candidates = []
        for index, block in enumerate(self.blocks):
            if block.used:
                continue
            place = self.placement(block, alignment)
            if place + length <= block.end():
                candidates.append((self.rank(index, rover_index), index, place))
        return min(candidates, default=None)

    def allocate(self, length, alignment):
        choice = self.choose(length, alignment)
        if choice is None:
            return None
        _, index, place = choice
        if self.is_buddy():
            self.halve(index, length)
            block = self.blocks[index]
        else:
            block = self.carve(index, place, length)
        block.used = True
        if self.mode == "NEXT":
            self.rover = 0 if block.end() == self.size else block.end()
        return block

    def carve(self, index, place, length):
        chosen = self.blocks[index]
        parts = []
        if place > chosen.start:
            parts.append(self.register(Block(chosen.start, place - chosen.start)))
        block = Block(place, chosen.end() - place)
        parts.append(block)
        if block.size - length >= MIN_BLOCK:
            parts.append(self.register(Block(place + length, block.size - length)))
            block.size = length
        self.blocks[index:index + 1] = parts
        return block

    def halve(self, index, length):
        block = self.blocks[index]
        while block.size > length:
            block.size //= 2
            self.blocks.insert(index + 1, self.register(Block(block.end(), block.size)))

    def merge_next(self, index):
        self.blocks[index].size += self.blocks.pop(index + 1).size

    def buddy_index(self, index):
        block = self.blocks[index]
        if block.start % (2 * block.size) == 0:
            return index + 1
        return index - 1

    def coalesce(self, index):
        merges = 0
        if self.is_buddy():
            while self.blocks[index].size < self.size:
                partner = self.buddy_index(index)
                buddy = self.blocks[partner]
                if buddy.used or buddy.size != self.blocks[index].size:
                    break
                index = min(index, partner)
                self.merge_next(index)
                merges += 1
        else:
            if index + 1 < len(self.blocks) and not self.blocks[index + 1].used:
                self.merge_next(index)
                merges += 1
            if index > 0 and not self.blocks[index - 1].used:
                index -= 1
                self.merge_next(index)
                merges += 1
        return self.register(self.blocks[index]), merges

    def release(self, block):
        block.used = False
        block.owner = None
        block.requested = 0
        block.contents = []
        return self.coalesce(self.blocks.index(block))

    def shrink(self, index, length):
        block = self.blocks[index]
        if self.is_buddy():
            if length == block.size:
                return "kept"
            self.halve(index, length)
            return "shrunk"
        if block.size - length < MIN_BLOCK:
            return "kept"
        self.blocks.insert(index + 1, Block(block.start + length, block.size - length))
        block.size = length
        self.coalesce(index + 1)
        return "shrunk"

    def grow_into_next(self, index, length):
        block = self.blocks[index]
        if index + 1 == len(self.blocks) or self.blocks[index + 1].used:
            return None
        total = block.size + self.blocks[index + 1].size
        if total < length:
            return None
        del self.blocks[index + 1]
        if total - length >= MIN_BLOCK:
            block.size = length
            self.blocks.insert(index + 1, self.register(Block(block.end(), total - length)))
        else:
            block.size = total
        return "grown"

    def grow_buddy(self, index, length):
        block = self.blocks[index]
        size = block.size
        last = index
        while size < length:
            last += 1
            if block.start % (2 * size) != 0 or last == len(self.blocks):
                return None
            partner = self.blocks[last]
            if partner.used or partner.size != size:
                return None
            size *= 2
        del self.blocks[index + 1:last + 1]
        block.size = length
        return "grown"

    def resize(self, block, length):
        index = self.blocks.index(block)
        if length <= block.size:
            return self.shrink(index, length)
        if self.is_buddy():
            return self.grow_buddy(index, length)
        return self.grow_into_next(index, length)

    def extend(self, amount):
        self.blocks.append(Block(self.size, amount))
        self.size += amount
        block, _ = self.coalesce(len(self.blocks) - 1)
        return block

    def trim(self):
        released = 0
        if self.is_buddy():
            while not self.blocks[-1].used and 2 * self.blocks[-1].size == self.size:
                released += self.blocks.pop().size
                self.size //= 2
        elif len(self.blocks) >= 2 and not self.blocks[-1].used:
            last = self.blocks.pop()
            released = last.size
            self.size = last.start
        if self.rover >= self.size:
            self.rover = 0
        return released

    def compact(self):
        moved = []
        address = 0
        packed = self.used_blocks()
        for block in packed:
            if block.start != address:
                moved.append((block, block.payload()))
                block.start = address
            address += block.size
        if address < self.size:
            packed.append(self.register(Block(address, self.size - address)))
        self.blocks = packed
        self.rover = 0
        return moved, address


def run_experiment(mode, size, seed, operations, max_request):
    heap = Heap(mode, size)
    state = seed
    live = []
    used = 0
    peak = 0
    successes = 0
    failures = 0
    for _ in range(operations):
        state = next_random(state)
        allocating = not live or state % 3 != 0
        state = next_random(state)
        if allocating:
            block = heap.allocate(heap.required_length(1 + state % max_request), DEFAULT_ALIGNMENT)
            if block is None:
                failures += 1
            else:
                successes += 1
                live.append(block)
                used += block.size
        else:
            block = live.pop(state % len(live))
            used -= block.size
            heap.release(block)
        peak = max(peak, used)
    return (
        f"BENCH {mode} ok={successes} fail={failures} peak={peak} used={used} "
        f"frag={heap.fragmentation()} blocks={len(heap.blocks)}"
    )


class Allocator:
    def __init__(self):
        self.output = []
        self.reset(None)
        self.handlers = {
            "HEAP": self.create_heap,
            "MALLOC": self.malloc,
            "CALLOC": self.calloc,
            "MEMALIGN": self.memalign,
            "REALLOC": self.realloc,
            "FREE": self.free,
            "FILL": self.fill,
            "COPY": self.copy,
            "READ": self.read,
            "ROOT": self.root,
            "UNROOT": self.unroot,
            "LINK": self.link,
            "UNLINK": self.unlink,
            "GC": self.collect,
            "SBRK": self.sbrk,
            "TRIM": self.trim,
            "COMPACT": self.compact,
            "WHO": self.who,
            "DUMP": self.dump,
            "MAP": self.show_map,
            "FREELIST": self.freelist,
            "TREE": self.tree,
            "STATS": self.stats,
            "LEAKS": self.leaks,
            "HISTORY": self.history,
            "BENCH": self.bench,
        }

    def reset(self, heap):
        self.heap = heap
        self.allocations = {}
        self.freed = set()
        self.roots = set()
        self.references = {}
        self.histories = {}
        self.counters = dict.fromkeys(COUNTERS, 0)
        self.peak = 0

    def emit(self, *parts):
        self.output.append(" ".join(str(part) for part in parts))

    def record(self, name, line):
        self.emit(line)
        self.histories.setdefault(name, []).append(line)

    def out_of_memory(self, name):
        self.counters["failures"] += 1
        return CommandError(f"OUT OF MEMORY {name}")

    def require_live(self, name):
        if name in self.allocations:
            return self.allocations[name]
        if name in self.freed:
            raise CommandError(f"USE AFTER FREE {name}")
        raise CommandError(f"UNKNOWN ID {name}")

    def require_range(self, name, offset, length):
        block = self.require_live(name)
        if offset + length > block.requested:
            raise CommandError(f"OUT OF BOUNDS {name}")
        return block

    def require_free_list(self):
        if self.heap.is_buddy():
            raise CommandError("UNSUPPORTED IN BUDDY MODE")

    def reachable(self):
        found = set(self.roots)
        pending = list(self.roots)
        while pending:
            name = pending.pop()
            for target in self.references.get(name, set()):
                if target not in found:
                    found.add(target)
                    pending.append(target)
        return found

    def create_heap(self, arguments):
        size, mode = int(arguments[0]), arguments[1]
        if size % UNIT != 0 or not MIN_HEAP <= size <= MAX_HEAP:
            raise CommandError("BAD HEAP SIZE")
        if mode == "BUDDY" and not is_power_of_two(size):
            raise CommandError("BAD HEAP SIZE")
        self.reset(Heap(mode, size))
        self.emit(f"HEAP size={size} mode={mode}")

    def allocate_id(self, word, name, request, alignment, fill):
        if request == 0:
            raise CommandError("BAD SIZE")
        if name in self.allocations:
            raise CommandError(f"DUPLICATE ID {name}")
        block = self.heap.allocate(self.heap.required_length(request), alignment)
        if block is None:
            raise self.out_of_memory(name)
        block.owner = name
        block.requested = request
        block.contents = [fill] * request
        self.allocations[name] = block
        self.freed.discard(name)
        self.counters["allocs"] += 1
        self.record(name, f"{word} {name} addr={block.payload()} block={block.size}")

    def malloc(self, arguments):
        name, request = arguments
        self.allocate_id("MALLOC", name, int(request), DEFAULT_ALIGNMENT, UNINITIALIZED)

    def calloc(self, arguments):
        name, count, size = arguments
        self.allocate_id("CALLOC", name, int(count) * int(size), DEFAULT_ALIGNMENT, 0)

    def memalign(self, arguments):
        name, alignment, request = arguments[0], int(arguments[1]), int(arguments[2])
        self.require_free_list()
        if not is_power_of_two(alignment) or not DEFAULT_ALIGNMENT <= alignment <= MAX_ALIGNMENT:
            raise CommandError("BAD ALIGNMENT")
        self.allocate_id("MEMALIGN", name, request, alignment, UNINITIALIZED)

    def release_id(self, name):
        block = self.allocations.pop(name)
        size = block.size
        self.freed.add(name)
        self.roots.discard(name)
        self.references.pop(name, None)
        for targets in self.references.values():
            targets.discard(name)
        result, merges = self.heap.release(block)
        return f"block={size} merges={merges} free={result.area()}"

    def free_id(self, name):
        if name in self.freed:
            raise CommandError(f"DOUBLE FREE {name}")
        if name not in self.allocations:
            raise CommandError(f"UNKNOWN ID {name}")
        details = self.release_id(name)
        self.counters["frees"] += 1
        self.record(name, f"FREE {name} {details}")

    def free(self, arguments):
        self.free_id(arguments[0])

    def realloc(self, arguments):
        name, request = arguments[0], int(arguments[1])
        if request == 0:
            self.free_id(name)
            return
        if name in self.freed:
            raise CommandError(f"USE AFTER FREE {name}")
        if name not in self.allocations:
            self.allocate_id("MALLOC", name, request, DEFAULT_ALIGNMENT, UNINITIALIZED)
            return
        block = self.allocations[name]
        length = self.heap.required_length(request)
        contents = block.contents[:request]
        contents += [UNINITIALIZED] * (request - len(contents))
        origin = block.payload()
        kind = self.heap.resize(block, length)
        if kind is None:
            moved = self.heap.allocate(length, DEFAULT_ALIGNMENT)
            if moved is None:
                raise self.out_of_memory(name)
            moved.owner = name
            self.allocations[name] = moved
            self.heap.release(block)
            self.counters["moves"] += 1
            block = moved
            kind = f"moved from={origin}"
        block.requested = request
        block.contents = contents
        self.counters["reallocs"] += 1
        self.record(name, f"REALLOC {name} addr={block.payload()} block={block.size} {kind}")

    def fill(self, arguments):
        name = arguments[0]
        offset, length, value = (int(text) for text in arguments[1:])
        block = self.require_range(name, offset, length)
        block.contents[offset:offset + length] = [value] * length
        self.emit(f"FILL {name} {offset}+{length} = {value}")

    def copy(self, arguments):
        target_name, source_name = arguments[0], arguments[2]
        target_offset, source_offset, length = int(arguments[1]), int(arguments[3]), int(arguments[4])
        target = self.require_range(target_name, target_offset, length)
        source = self.require_range(source_name, source_offset, length)
        values = source.contents[source_offset:source_offset + length]
        target.contents[target_offset:target_offset + length] = values
        self.emit(f"COPY {target_name} {target_offset}+{length} from {source_name} {source_offset}")

    def read(self, arguments):
        name = arguments[0]
        offset, length = int(arguments[1]), int(arguments[2])
        block = self.require_range(name, offset, length)
        values = " ".join(byte_text(value) for value in block.contents[offset:offset + length])
        self.emit(f"READ {name} {offset}+{length} = {values}")

    def root(self, arguments):
        name = arguments[0]
        self.require_live(name)
        self.roots.add(name)
        self.emit("ROOT", name)

    def unroot(self, arguments):
        name = arguments[0]
        self.require_live(name)
        if name not in self.roots:
            raise CommandError(f"NOT ROOT {name}")
        self.roots.remove(name)
        self.emit("UNROOT", name)

    def link(self, arguments):
        source, target = arguments
        self.require_live(source)
        self.require_live(target)
        self.references.setdefault(source, set()).add(target)
        self.emit("LINK", source, target)

    def unlink(self, arguments):
        source, target = arguments
        self.require_live(source)
        self.require_live(target)
        if target not in self.references.get(source, set()):
            raise CommandError(f"NO LINK {source} {target}")
        self.references[source].remove(target)
        self.emit("UNLINK", source, target)

    def collect(self, arguments):
        reachable = self.reachable()
        garbage = [block for name, block in self.allocations.items() if name not in reachable]
        garbage.sort(key=lambda block: block.start)
        self.emit(f"GC collected={len(garbage)} bytes={sum(block.size for block in garbage)}")
        for block in garbage:
            name = block.owner
            self.record(name, f"COLLECT {name} {self.release_id(name)}")
        self.counters["collected"] += len(garbage)

    def sbrk(self, arguments):
        amount = int(arguments[0])
        heap = self.heap
        if heap.is_buddy():
            valid = amount == heap.size and 2 * heap.size <= MAX_HEAP
        else:
            valid = amount % UNIT == 0 and amount >= MIN_BLOCK and heap.size + amount <= MAX_HEAP
        if not valid:
            raise CommandError("BAD SBRK SIZE")
        result = heap.extend(amount)
        self.emit(f"SBRK heap={heap.size} free={result.area()}")

    def trim(self, arguments):
        released = self.heap.trim()
        self.emit(f"TRIM heap={self.heap.size} released={released}")

    def compact(self, arguments):
        self.require_free_list()
        heap = self.heap
        moved, used = heap.compact()
        self.counters["moves"] += len(moved)
        free = f"{used}+{heap.size - used}" if used < heap.size else "none"
        self.emit(f"COMPACT moved={len(moved)} free={free}")
        for block, origin in moved:
            self.record(block.owner, f"MOVE {block.owner} {origin} -> {block.payload()}")

    def who(self, arguments):
        address = int(arguments[0])
        if address >= self.heap.size:
            self.emit("WHO", address, "outside")
            return
        block = self.heap.blocks[self.heap.locate(address)]
        if not block.used:
            self.emit("WHO", address, "free", block.area())
        elif address < block.payload():
            self.emit("WHO", address, "header", block.owner)
        else:
            offset = address - block.payload()
            region = "data" if offset < block.requested else "slack"
            self.emit("WHO", address, region, f"{block.owner}+{offset}")

    def dump(self, arguments):
        heap = self.heap
        header = f"DUMP mode={heap.mode} heap={heap.size} blocks={len(heap.blocks)}"
        if heap.mode == "NEXT":
            header += f" rover={heap.rover}"
        self.emit(header)
        for block in heap.blocks:
            if block.used:
                self.emit(block.start, block.size, "USED", block.owner, f"req={block.requested}")
            else:
                self.emit(block.start, block.size, "FREE")

    def show_map(self, arguments):
        self.emit(f"MAP heap={self.heap.size}")
        units = "".join(block.map_units() for block in self.heap.blocks)
        for first in range(0, len(units), MAP_WIDTH):
            self.emit(f"{first * UNIT:05d}", units[first:first + MAP_WIDTH])

    def freelist(self, arguments):
        blocks = self.heap.free_blocks()
        if self.heap.mode == "SEGFIT":
            blocks.sort(key=lambda block: -block.stamp)
        self.emit(f"FREELIST count={len(blocks)}")
        for power in sorted({size_class(block.size) for block in blocks}):
            members = [block.area() for block in blocks if size_class(block.size) == power]
            self.emit(f"{2 ** power}-{2 ** (power + 1) - 1}:", *members)

    def tree_node(self, leaves, start, size, depth):
        label = " " * (2 * depth) + f"{start}+{size}"
        block = leaves.get(start)
        if block is not None and block.size == size:
            if block.used:
                self.emit(label, "USED", block.owner)
            else:
                self.emit(label, "FREE")
            return
        self.emit(label, "split")
        half = size // 2
        self.tree_node(leaves, start, half, depth + 1)
        self.tree_node(leaves, start + half, half, depth + 1)

    def tree(self, arguments):
        if not self.heap.is_buddy():
            raise CommandError("REQUIRES BUDDY MODE")
        self.emit(f"TREE heap={self.heap.size}")
        leaves = {block.start: block for block in self.heap.blocks}
        self.tree_node(leaves, 0, self.heap.size, 0)

    def stats(self, arguments):
        used = self.heap.used_blocks()
        free = self.heap.free_blocks()
        free_total = sum(block.size for block in free)
        largest = max((block.size for block in free), default=0)
        self.emit(
            f"STATS used={sum(block.size for block in used)} used_blocks={len(used)}",
            f"free={free_total} free_blocks={len(free)} largest={largest}",
            f"frag={fragmentation_percent(free_total, largest)}",
            f"requested={sum(block.requested for block in used)} peak={self.peak}",
        )
        self.emit("OPS", *(f"{name}={self.counters[name]}" for name in COUNTERS))

    def leaks(self, arguments):
        reachable = self.reachable()
        names = sorted(self.allocations)
        requested = sum(self.allocations[name].requested for name in names)
        lost = sum(name not in reachable for name in names)
        self.emit(f"LEAKS count={len(names)} requested={requested} lost={lost}")
        for name in names:
            block = self.allocations[name]
            status = "reachable" if name in reachable else "lost"
            self.emit(
                f"LEAK {name} addr={block.payload()} block={block.size}",
                f"req={block.requested} {status}",
            )

    def history(self, arguments):
        name = arguments[0]
        lines = self.histories.get(name, [])
        self.emit(f"HISTORY {name} events={len(lines)}")
        self.output.extend(lines)

    def bench(self, arguments):
        size, seed, operations, max_request = (int(text) for text in arguments)
        if not is_power_of_two(size) or not MIN_HEAP <= size <= MAX_HEAP:
            raise CommandError("BAD HEAP SIZE")
        self.emit(f"BENCH heap={size} seed={seed} ops={operations} maxreq={max_request}")
        for mode in MODES:
            self.emit(run_experiment(mode, size, seed, operations, max_request))

    def execute(self, line):
        command, *arguments = line.split()
        try:
            if self.heap is None and command not in HEAPLESS_COMMANDS:
                raise CommandError("NO HEAP")
            self.handlers[command](arguments)
        except CommandError as error:
            self.emit("ERROR", error)
        if self.heap is not None:
            self.peak = max(self.peak, self.heap.used_total())


def main():
    allocator = Allocator()
    count = int(sys.stdin.readline())
    for _ in range(count):
        allocator.execute(sys.stdin.readline().rstrip("\n"))
    sys.stdout.write("\n".join(allocator.output) + "\n")


if __name__ == "__main__":
    main()
