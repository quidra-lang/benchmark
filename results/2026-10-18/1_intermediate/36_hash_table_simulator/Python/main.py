import sys


MODES = ("CHAIN", "LINEAR", "QUADRATIC", "DOUBLE", "ROBINHOOD", "CUCKOO")
PROBING_MODES = ("LINEAR", "QUADRATIC", "DOUBLE")
TABLELESS_COMMANDS = ("CREATE", "MAXLOAD", "MINLOAD", "TRACE", "HASH", "BENCH")
MIN_CAPACITY = 2
MAX_CAPACITY = 10000
MAX_LOAD_RANGE = (10, 95)
MIN_LOAD_RANGE = (0, 40)
MAX_GENERATED = 500
MAX_KEY_LENGTH = 10
MAX_LISTED = 100
RANDOM_MULTIPLIER = 48271
RANDOM_MODULUS = 2147483647
MAP_WIDTH = 40
BAR_WIDTH = 50
TOMBSTONE = object()


def poly_hash(text, base, modulus):
    value = 0
    for char in text:
        value = (value * base + ord(char)) % modulus
    return value


def is_prime(number):
    if number < 2:
        return False
    divisor = 2
    while divisor * divisor <= number:
        if number % divisor == 0:
            return False
        divisor += 1
    return True


def next_prime(number):
    while not is_prime(number):
        number += 1
    return number


def slots_for(mode, capacity):
    return 2 * capacity if mode == "CUCKOO" else capacity


def two_decimal(numerator, denominator):
    if denominator == 0:
        return "0.00"
    scaled = 100 * numerator // denominator
    return f"{scaled // 100}.{scaled % 100:02d}"


def gauge(number):
    return str(number) if number <= 9 else "+"


def holds_item(slot):
    return slot is not None and slot is not TOMBSTONE


def content(slot):
    if slot is None:
        return "-"
    if slot is TOMBSTONE:
        return "D"
    return slot.key


def generate_keys(count, length, seed):
    keys = []
    state = seed
    for _ in range(count):
        letters = []
        for _ in range(length):
            state = RANDOM_MULTIPLIER * state % RANDOM_MODULUS
            letters.append(chr(ord("a") + state % 26))
        keys.append("".join(letters))
    return keys


def circular_runs(slots):
    if None not in slots:
        return [len(slots)]
    start = slots.index(None)
    runs = []
    length = 0
    for offset in range(1, len(slots) + 1):
        if slots[(start + offset) % len(slots)] is None:
            if length > 0:
                runs.append(length)
            length = 0
        else:
            length += 1
    return runs


def histogram(values):
    counts = {}
    for value in values:
        counts[value] = counts.get(value, 0) + 1
    lines = []
    for value in sorted(counts):
        frequency = counts[value]
        if frequency > BAR_WIDTH:
            bar = "#" * BAR_WIDTH + "+"
        else:
            bar = "#" * frequency
        lines.append(f"{value} {frequency} {bar}")
    return lines


def map_rows(symbols, prefix):
    rows = []
    for start in range(0, len(symbols), MAP_WIDTH):
        rows.append(f"{prefix}{start:05d} " + "".join(symbols[start:start + MAP_WIDTH]))
    return rows


class CommandError(Exception):
    pass


def require(condition, message):
    if not condition:
        raise CommandError(message)


def mode_argument(text):
    require(text in MODES, f"BAD MODE {text}")
    return text


def capacity_argument(text):
    capacity = int(text)
    require(MIN_CAPACITY <= capacity <= MAX_CAPACITY, "BAD CAPACITY")
    return capacity


def generation_arguments(arguments):
    count, length, seed = (int(text) for text in arguments)
    require(
        1 <= count <= MAX_GENERATED
        and 1 <= length <= MAX_KEY_LENGTH
        and 1 <= seed <= RANDOM_MODULUS - 1,
        "BAD ARGUMENT",
    )
    return count, length, seed


class Item:
    def __init__(self, key, value):
        self.key = key
        self.value = value


class Search:
    def __init__(self):
        self.item = None
        self.place = 0
        self.offset = 0
        self.probes = 0
        self.path = []
        self.tombstone = None
        self.vacant = None


class Placement:
    def __init__(self):
        self.success = True
        self.place = 0
        self.reused = False
        self.moves = []
        self.homeless = None


class Outcome:
    def __init__(self, search):
        self.search = search
        self.line = ""
        self.moves = []
        self.notices = []

    def found(self):
        return self.search.item is not None

    def trace(self):
        path = " ".join(self.search.path) if self.search.path else "none"
        return ["PATH " + path] + self.moves


class Table:
    def __init__(self, mode, capacity):
        self.mode = mode
        self.capacity = capacity
        self.probes = 0
        self.rehashes = 0
        self.inserts = 0
        self.updates = 0
        self.hits = 0
        self.misses = 0
        self.deletes = 0
        self.absent = 0
        self.clear()

    def clear(self):
        self.size = 0
        self.tomb = 0
        if self.mode == "CHAIN":
            self.buckets = [[] for _ in range(self.capacity)]
            self.slots = []
        else:
            self.buckets = []
            self.slots = [None] * self.slot_count()

    def slot_count(self):
        return slots_for(self.mode, self.capacity)

    def h1(self, key):
        return poly_hash(key, 31, self.capacity)

    def h2(self, key):
        return poly_hash(key, 37, self.capacity)

    def step(self, key):
        return 1 + poly_hash(key, 37, self.capacity - 1)

    def distance(self, item, place):
        return (place - self.h1(item.key) + self.capacity) % self.capacity

    def cuckoo_place(self, key, part):
        if part == 1:
            return self.h1(key)
        return self.capacity + self.h2(key)

    def position(self, place):
        if self.mode != "CUCKOO":
            return str(place)
        if place < self.capacity:
            return f"T1.{place}"
        return f"T2.{place - self.capacity}"

    def items(self):
        if self.mode == "CHAIN":
            return [item for chain in self.buckets for item in chain]
        return [slot for slot in self.slots if holds_item(slot)]

    def keys_at(self, cursor):
        if self.mode == "CHAIN":
            return [item.key for item in self.buckets[cursor]]
        slot = self.slots[cursor]
        return [slot.key] if holds_item(slot) else []

    def costs(self):
        return [self.search(item.key).probes for item in self.items()]

    def runs(self):
        if self.mode == "CHAIN":
            return [len(chain) for chain in self.buckets if chain]
        if self.mode == "CUCKOO":
            first = circular_runs(self.slots[:self.capacity])
            return first + circular_runs(self.slots[self.capacity:])
        return circular_runs(self.slots)

    def map_symbols(self):
        if self.mode == "CHAIN":
            return [gauge(len(chain)) if chain else "." for chain in self.buckets]
        symbols = []
        for place, slot in enumerate(self.slots):
            if slot is None:
                symbols.append(".")
            elif slot is TOMBSTONE:
                symbols.append("D")
            elif self.mode == "CUCKOO":
                symbols.append("#")
            elif self.mode == "ROBINHOOD":
                symbols.append(gauge(self.distance(slot, place)))
            else:
                symbols.append(gauge(self.search(slot.key).probes - 1))
        return symbols

    def search(self, key):
        search = Search()
        if self.mode == "CHAIN":
            self.search_chain(key, search)
        elif self.mode == "ROBINHOOD":
            self.search_robinhood(key, search)
        elif self.mode == "CUCKOO":
            self.search_cuckoo(key, search)
        else:
            self.search_probing(key, search)
        return search

    def examine(self, search, place):
        slot = self.slots[place]
        search.probes += 1
        search.path.append(f"{self.position(place)}:{content(slot)}")
        return slot

    def search_chain(self, key, search):
        bucket = self.h1(key)
        search.place = bucket
        for offset, item in enumerate(self.buckets[bucket]):
            search.probes += 1
            search.path.append(f"{bucket}:{item.key}")
            if item.key == key:
                search.item = item
                search.offset = offset
                return

    def search_probing(self, key, search):
        start = self.h1(key)
        stride = self.step(key)
        for attempt in range(self.capacity):
            if self.mode == "LINEAR":
                place = (start + attempt) % self.capacity
            elif self.mode == "QUADRATIC":
                place = (start + attempt * attempt) % self.capacity
            else:
                place = (start + attempt * stride) % self.capacity
            slot = self.examine(search, place)
            if slot is None:
                search.vacant = place
                return
            if slot is TOMBSTONE:
                if search.tombstone is None:
                    search.tombstone = place
            elif slot.key == key:
                search.item = slot
                search.place = place
                return

    def search_robinhood(self, key, search):
        start = self.h1(key)
        for attempt in range(self.capacity):
            place = (start + attempt) % self.capacity
            slot = self.examine(search, place)
            if slot is None:
                return
            if slot.key == key:
                search.item = slot
                search.place = place
                return
            if self.distance(slot, place) < attempt:
                return

    def search_cuckoo(self, key, search):
        for part in (1, 2):
            place = self.cuckoo_place(key, part)
            slot = self.examine(search, place)
            if slot is not None and slot.key == key:
                search.item = slot
                search.place = place
                return

    def place(self, item):
        placement = Placement()
        if self.mode == "CHAIN":
            placement.place = self.h1(item.key)
            self.buckets[placement.place].append(item)
        elif self.mode == "ROBINHOOD":
            self.place_robinhood(item, placement)
        elif self.mode == "CUCKOO":
            self.place_cuckoo(item, placement)
        else:
            self.place_probing(item, placement)
        if placement.success:
            self.size += 1
        return placement

    def place_probing(self, item, placement):
        search = self.search(item.key)
        if search.tombstone is not None:
            placement.place = search.tombstone
            placement.reused = True
            self.tomb -= 1
        elif search.vacant is not None:
            placement.place = search.vacant
        else:
            placement.success = False
            return
        self.slots[placement.place] = item

    def place_robinhood(self, item, placement):
        current = item
        place = self.h1(item.key)
        distance = 0
        origin = None
        while True:
            occupant = self.slots[place]
            if occupant is None or self.distance(occupant, place) < distance:
                self.slots[place] = current
                if origin is None:
                    placement.place = place
                else:
                    placement.moves.append(f"SHIFT {current.key} {origin} -> {place}")
                if occupant is None:
                    return
                current = occupant
                origin = place
                distance = self.distance(occupant, place)
            place = (place + 1) % self.capacity
            distance += 1

    def place_cuckoo(self, item, placement):
        current = item
        part = 1
        while True:
            place = self.cuckoo_place(current.key, part)
            occupant = self.slots[place]
            if occupant is None:
                self.slots[place] = current
                break
            if len(placement.moves) == self.capacity:
                placement.success = False
                placement.homeless = current
                return
            self.slots[place] = current
            placement.moves.append(f"KICK {occupant.key} {self.position(place)}")
            current = occupant
            part = 3 - part
        first = self.cuckoo_place(item.key, 1)
        if self.slots[first] is item:
            placement.place = first
        else:
            placement.place = self.cuckoo_place(item.key, 2)

    def placement_note(self, placement):
        if self.mode == "ROBINHOOD":
            return f" shifted={len(placement.moves)}"
        if self.mode == "CUCKOO":
            return f" kicks={len(placement.moves)}"
        if placement.reused:
            return " reused"
        return ""

    def remove(self, search):
        self.size -= 1
        place = search.place
        if self.mode == "CHAIN":
            del self.buckets[place][search.offset]
            return []
        if self.mode in PROBING_MODES:
            self.slots[place] = TOMBSTONE
            self.tomb += 1
            return []
        self.slots[place] = None
        if self.mode == "CUCKOO":
            return []
        return self.backward_shift(place)

    def backward_shift(self, place):
        moves = []
        current = (place + 1) % self.capacity
        while True:
            item = self.slots[current]
            if item is None or self.distance(item, current) < 1:
                return moves
            target = (current - 1 + self.capacity) % self.capacity
            self.slots[target] = item
            self.slots[current] = None
            moves.append(f"SHIFT {item.key} {current} -> {target}")
            current = (current + 1) % self.capacity

    def rebuild(self, items, mode, capacity):
        table = Table(mode, capacity)
        for item in items:
            if not table.place(item).success:
                return False
        self.mode = table.mode
        self.capacity = table.capacity
        self.size = table.size
        self.tomb = 0
        self.buckets = table.buckets
        self.slots = table.slots
        return True

    def auto_rebuild(self, reason, capacity, pending):
        items = self.items()
        if pending is not None:
            items.append(pending)
        old_capacity = self.capacity
        while not self.rebuild(items, self.mode, capacity):
            capacity = next_prime(2 * capacity)
        self.rehashes += 1
        return f"REHASH {reason} {old_capacity} -> {capacity}"

    def performance(self):
        costs = self.costs()
        return (
            f"longest={max(costs, default=0)} avg={two_decimal(sum(costs), self.size)} "
            f"probes={self.probes} rehashes={self.rehashes}"
        )


class Simulator:
    def __init__(self):
        self.table = None
        self.max_load = 75
        self.min_load = 0
        self.tracing = False
        self.output = []
        self.handlers = {
            "CREATE": self.create,
            "MAXLOAD": self.set_max_load,
            "MINLOAD": self.set_min_load,
            "TRACE": self.set_trace,
            "HASH": self.show_hash,
            "PUT": self.put_command,
            "ADD": self.add_command,
            "GET": self.get,
            "DEL": self.delete_command,
            "PROBE": self.probe,
            "GEN": self.generate,
            "GENDEL": self.generate_deletes,
            "RESIZE": self.resize,
            "CONVERT": self.convert,
            "CLEAR": self.clear,
            "DUMP": self.dump,
            "MAP": self.show_map,
            "STATS": self.stats,
            "KEYS": self.keys,
            "TOP": self.top,
            "SCAN": self.scan,
            "CLUSTERS": self.clusters,
            "DIST": self.distribution,
            "COMPARE": self.compare,
            "BENCH": self.bench,
        }

    def emit(self, *parts):
        self.output.append(" ".join(str(part) for part in parts))

    def report(self, outcome):
        self.emit(outcome.line)
        if self.tracing:
            self.output.extend(outcome.trace())
        self.output.extend(outcome.notices)

    def load_check(self, table, notices):
        limit = self.max_load * table.slot_count()
        if (table.size + table.tomb) * 100 <= limit:
            return
        if table.size * 200 > limit:
            notices.append(table.auto_rebuild("load", next_prime(2 * table.capacity), None))
        else:
            notices.append(table.auto_rebuild("tomb", table.capacity, None))

    def shrink_check(self, table, notices):
        capacity = next_prime(table.capacity // 2)
        if table.size * 100 >= self.min_load * table.slot_count():
            return
        if capacity >= table.capacity:
            return
        if table.size * 100 > self.max_load * slots_for(table.mode, capacity):
            return
        old_capacity = table.capacity
        if table.rebuild(table.items(), table.mode, capacity):
            table.rehashes += 1
            notices.append(f"REHASH shrink {old_capacity} -> {capacity}")

    def put(self, table, key, value, adding):
        search = table.search(key)
        table.probes += search.probes
        outcome = Outcome(search)
        name = "ADD" if adding else "PUT"
        item = search.item
        if item is not None:
            old_value = item.value
            item.value = old_value + value if adding else value
            table.updates += 1
            outcome.line = (
                f"{name} {key}={item.value} UPDATED old={old_value} "
                f"at={table.position(search.place)} probes={search.probes}"
            )
            return outcome
        table.inserts += 1
        item = Item(key, value)
        placement = table.place(item)
        outcome.moves = placement.moves
        head = f"{name} {key}={value} NEW"
        if placement.success:
            outcome.line = (
                f"{head} at={table.position(placement.place)} probes={search.probes}"
                + table.placement_note(placement)
            )
        elif table.mode == "QUADRATIC":
            outcome.line = f"{head} probes={search.probes} full"
            capacity = next_prime(2 * table.capacity)
            outcome.notices.append(table.auto_rebuild("full", capacity, item))
        else:
            outcome.line = f"{head} probes={search.probes} kicks={len(placement.moves)} failed"
            capacity = next_prime(2 * table.capacity)
            outcome.notices.append(table.auto_rebuild("kicks", capacity, placement.homeless))
        self.load_check(table, outcome.notices)
        return outcome

    def delete(self, table, key):
        search = table.search(key)
        table.probes += search.probes
        outcome = Outcome(search)
        if search.item is None:
            table.absent += 1
            outcome.line = f"DEL {key} NOT FOUND probes={search.probes}"
            return outcome
        table.deletes += 1
        position = table.position(search.place)
        outcome.moves = table.remove(search)
        outcome.line = f"DEL {key} OK at={position} probes={search.probes}"
        if table.mode == "ROBINHOOD":
            outcome.line += f" shifted={len(outcome.moves)}"
        self.shrink_check(table, outcome.notices)
        return outcome

    def create(self, arguments):
        mode = mode_argument(arguments[0])
        capacity = capacity_argument(arguments[1])
        self.table = Table(mode, next_prime(capacity))
        self.emit(f"CREATE {mode} cap={self.table.capacity}")

    def set_max_load(self, arguments):
        percent = int(arguments[0])
        require(MAX_LOAD_RANGE[0] <= percent <= MAX_LOAD_RANGE[1], "BAD LOAD")
        self.max_load = percent
        self.emit("MAXLOAD", percent)

    def set_min_load(self, arguments):
        percent = int(arguments[0])
        require(MIN_LOAD_RANGE[0] <= percent <= MIN_LOAD_RANGE[1], "BAD LOAD")
        self.min_load = percent
        self.emit("MINLOAD", percent)

    def set_trace(self, arguments):
        flag = arguments[0]
        require(flag in ("ON", "OFF"), "BAD ARGUMENT")
        self.tracing = flag == "ON"
        self.emit("TRACE", flag)

    def show_hash(self, arguments):
        key = arguments[0]
        modulus = capacity_argument(arguments[1])
        self.emit(
            f"HASH {key} m={modulus} h31={poly_hash(key, 31, modulus)} "
            f"h37={poly_hash(key, 37, modulus)} step={1 + poly_hash(key, 37, modulus - 1)}"
        )

    def put_command(self, arguments):
        self.report(self.put(self.table, arguments[0], int(arguments[1]), False))

    def add_command(self, arguments):
        self.report(self.put(self.table, arguments[0], int(arguments[1]), True))

    def get(self, arguments):
        key = arguments[0]
        table = self.table
        search = table.search(key)
        table.probes += search.probes
        outcome = Outcome(search)
        if search.item is None:
            table.misses += 1
            outcome.line = f"GET {key} NOT FOUND probes={search.probes}"
        else:
            table.hits += 1
            outcome.line = (
                f"GET {key}={search.item.value} "
                f"at={table.position(search.place)} probes={search.probes}"
            )
        self.report(outcome)

    def delete_command(self, arguments):
        self.report(self.delete(self.table, arguments[0]))

    def probe(self, arguments):
        key = arguments[0]
        search = self.table.search(key)
        verdict = "FOUND" if search.item is not None else "MISS"
        self.emit("PROBE", key, *search.path, verdict, f"probes={search.probes}")

    def generate(self, arguments):
        count, length, seed = generation_arguments(arguments)
        created = 0
        for number, key in enumerate(generate_keys(count, length, seed), 1):
            outcome = self.put(self.table, key, number, False)
            if not outcome.found():
                created += 1
            self.output.extend(outcome.notices)
        self.emit(f"GEN {count} new={created} updated={count - created}")

    def generate_deletes(self, arguments):
        count, length, seed = generation_arguments(arguments)
        deleted = 0
        for key in generate_keys(count, length, seed):
            outcome = self.delete(self.table, key)
            if outcome.found():
                deleted += 1
            self.output.extend(outcome.notices)
        self.emit(f"GENDEL {count} deleted={deleted} missing={count - deleted}")

    def resize(self, arguments):
        capacity = next_prime(capacity_argument(arguments[0]))
        table = self.table
        limit = self.max_load * slots_for(table.mode, capacity)
        require(table.size * 100 <= limit, "TOO SMALL")
        old_capacity = table.capacity
        require(table.rebuild(table.items(), table.mode, capacity), "REBUILD FAILED")
        self.emit(f"RESIZE {old_capacity} -> {capacity}")

    def convert(self, arguments):
        mode = mode_argument(arguments[0])
        table = self.table
        limit = self.max_load * slots_for(mode, table.capacity)
        require(table.size * 100 <= limit, "TOO SMALL")
        old_mode = table.mode
        require(table.rebuild(table.items(), mode, table.capacity), "REBUILD FAILED")
        self.emit(f"CONVERT {old_mode} -> {mode} cap={table.capacity}")

    def clear(self, arguments):
        self.emit("CLEAR", self.table.size)
        self.table.clear()

    def dump(self, arguments):
        table = self.table
        self.emit(
            f"DUMP {table.mode} cap={table.capacity} size={table.size} tomb={table.tomb}"
        )
        if table.mode == "CHAIN":
            for index, chain in enumerate(table.buckets):
                if chain:
                    self.emit(index, *(f"{item.key}={item.value}" for item in chain))
                else:
                    self.emit(index, "-")
            return
        for place, slot in enumerate(table.slots):
            if table.mode == "CUCKOO":
                prefix = f"T{place // table.capacity + 1} {place % table.capacity}"
            else:
                prefix = str(place)
            if not holds_item(slot):
                self.emit(prefix, content(slot))
            elif table.mode == "ROBINHOOD":
                distance = table.distance(slot, place)
                self.emit(prefix, f"{slot.key}={slot.value}", f"d={distance}")
            else:
                self.emit(prefix, f"{slot.key}={slot.value}")

    def show_map(self, arguments):
        table = self.table
        self.emit(f"MAP {table.mode} cap={table.capacity}")
        symbols = table.map_symbols()
        if table.mode == "CUCKOO":
            self.output.extend(map_rows(symbols[:table.capacity], "T1 "))
            self.output.extend(map_rows(symbols[table.capacity:], "T2 "))
        else:
            self.output.extend(map_rows(symbols, ""))

    def stats(self, arguments):
        table = self.table
        slots = table.slot_count()
        self.emit(
            f"STATS {table.mode} size={table.size} cap={table.capacity} slots={slots} "
            f"tomb={table.tomb} load={two_decimal(100 * table.size, slots)}% "
            + table.performance()
        )
        self.emit(
            f"OPS inserts={table.inserts} updates={table.updates} hits={table.hits} "
            f"misses={table.misses} deletes={table.deletes} absent={table.absent}"
        )

    def keys(self, arguments):
        keys = sorted(item.key for item in self.table.items())
        self.emit("KEYS", len(keys), *keys)

    def top(self, arguments):
        limit = int(arguments[0])
        require(1 <= limit <= MAX_LISTED, "BAD ARGUMENT")
        table = self.table
        searches = [table.search(item.key) for item in table.items()]
        searches.sort(key=lambda search: (-search.probes, search.item.key))
        chosen = searches[:limit]
        self.emit("TOP", len(chosen))
        for search in chosen:
            self.emit(
                search.item.key, f"cost={search.probes}", f"at={table.position(search.place)}"
            )

    def scan(self, arguments):
        cursor = int(arguments[0])
        limit = int(arguments[1])
        require(1 <= limit <= MAX_LISTED, "BAD ARGUMENT")
        total = self.table.slot_count()
        require(cursor < total, "BAD CURSOR")
        keys = []
        while cursor < total and len(keys) < limit:
            keys.extend(self.table.keys_at(cursor))
            cursor += 1
        if cursor == total:
            cursor = 0
        self.emit(f"SCAN next={cursor}", *keys)

    def clusters(self, arguments):
        runs = self.table.runs()
        self.emit(f"CLUSTERS runs={len(runs)} longest={max(runs, default=0)}")
        self.output.extend(histogram(runs))

    def distribution(self, arguments):
        costs = self.table.costs()
        self.emit(f"DIST keys={self.table.size} longest={max(costs, default=0)}")
        self.output.extend(histogram(costs))

    def compare(self, arguments):
        capacity = next_prime(capacity_argument(arguments[0]))
        items = sorted(self.table.items(), key=lambda item: item.key)
        self.emit(f"COMPARE keys={len(items)} cap={capacity}")
        for mode in MODES:
            trial = Table(mode, capacity)
            for item in items:
                self.put(trial, item.key, item.value, False)
            self.emit(f"{mode} cap={trial.capacity} {trial.performance()}")

    def bench(self, arguments):
        capacity = next_prime(capacity_argument(arguments[0]))
        count, length, seed = generation_arguments(arguments[1:])
        keys = generate_keys(2 * count, length, seed)
        inserted = keys[:count]
        queries = keys[count:]
        self.emit(f"BENCH cap={capacity} count={count} len={length} seed={seed}")
        for mode in MODES:
            trial = Table(mode, capacity)
            for number, key in enumerate(inserted, 1):
                self.put(trial, key, number, False)
            misses = 0
            miss_probes = 0
            for key in queries:
                search = trial.search(key)
                if search.item is None:
                    misses += 1
                    miss_probes += search.probes
            costs = trial.costs()
            self.emit(
                f"{mode} cap={trial.capacity} keys={trial.size} "
                f"hit={two_decimal(sum(costs), trial.size)} misses={misses} "
                f"miss={two_decimal(miss_probes, misses)} rehashes={trial.rehashes}"
            )

    def execute(self, line):
        command, *arguments = line.split()
        if command not in self.handlers:
            self.emit("ERROR UNKNOWN COMMAND", command)
            return
        if self.table is None and command not in TABLELESS_COMMANDS:
            self.emit("ERROR NO TABLE")
            return
        try:
            self.handlers[command](arguments)
        except CommandError as error:
            self.emit("ERROR", error)


def main():
    simulator = Simulator()
    count = int(sys.stdin.readline())
    for _ in range(count):
        simulator.execute(sys.stdin.readline().rstrip("\n"))
    sys.stdout.write("\n".join(simulator.output) + "\n")


if __name__ == "__main__":
    main()
