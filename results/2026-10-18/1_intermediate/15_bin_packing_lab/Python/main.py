import sys


METHODS = ("NEXTFIT", "FIRSTFIT", "BESTFIT", "WORSTFIT", "ALMOSTWORST", "HARMONIC", "KBOUNDED", "FFD", "BFD", "WFD")
PARAMETERIZED = ("HARMONIC", "KBOUNDED")


class CommandError(Exception):
    pass


def ceiling(numerator, denominator):
    return (numerator + denominator - 1) // denominator


def item_text(item):
    return f"{item[0]}:{item[1]}"


def descending(items):
    return sorted(items, key=lambda item: (-item[1], item[0]))


class Bin:
    def __init__(self, category=None):
        self.items = []
        self.load = 0
        self.category = category

    def put(self, item):
        self.items.append(item)
        self.load += item[1]

    def copy(self):
        result = Bin(self.category)
        result.items = self.items.copy()
        result.load = self.load
        return result


class Packing:
    def __init__(self, method, parameter):
        self.method = method
        self.parameter = parameter
        self.bins = []
        self.steps = []
        self.inspections = 0
        self.closes = 0

    def name(self):
        return self.method + (f" k={self.parameter}" if self.method in PARAMETERIZED else "")

    def header(self, capacity, total):
        text = f"{self.name()} bins={len(self.bins)} inspections={self.inspections} waste={len(self.bins) * capacity - total}"
        if self.method == "KBOUNDED":
            text += f" closes={self.closes}"
        return text


def pack(items, capacity, method, parameter=0):
    result = Packing(method, parameter)
    order = descending(items) if method in ("FFD", "BFD", "WFD") else items
    active = []
    current = {}
    for item in order:
        size = item[1]
        before = result.inspections
        chosen = None
        closed = None
        category = None
        if method == "NEXTFIT":
            if result.bins:
                result.inspections += 1
                if result.bins[-1].load + size <= capacity:
                    chosen = len(result.bins) - 1
        elif method in ("FIRSTFIT", "FFD", "KBOUNDED"):
            candidates = active if method == "KBOUNDED" else range(len(result.bins))
            for index in candidates:
                result.inspections += 1
                if result.bins[index].load + size <= capacity:
                    chosen = index
                    break
        elif method == "HARMONIC":
            category = min(capacity // size, parameter)
            if category in current:
                result.inspections += 1
                index = current[category]
                if result.bins[index].load + size <= capacity:
                    chosen = index
        else:
            result.inspections += len(result.bins)
            fitting = [index for index, bin in enumerate(result.bins) if bin.load + size <= capacity]
            if fitting:
                if method in ("BESTFIT", "BFD"):
                    chosen = max(fitting, key=lambda index: (result.bins[index].load, -index))
                else:
                    fitting.sort(key=lambda index: (result.bins[index].load, index))
                    chosen = fitting[1] if method == "ALMOSTWORST" and len(fitting) >= 2 else fitting[0]
        opened = chosen is None
        if opened:
            if method == "KBOUNDED" and len(active) == parameter:
                closed = max(active, key=lambda index: (result.bins[index].load, -index))
                active.remove(closed)
                result.closes += 1
            chosen = len(result.bins)
            result.bins.append(Bin(category))
            if method == "KBOUNDED":
                active.append(chosen)
            if method == "HARMONIC":
                current[category] = chosen
        result.bins[chosen].put(item)
        result.steps.append((item, chosen, result.inspections - before, opened, closed, category))
    return result


def bounds(items, capacity):
    total = sum(size for _, size in items)
    thresholds = sorted({0} | {size for _, size in items if 2 * size <= capacity})
    rows = []
    for alpha in thresholds:
        first = [size for _, size in items if size > capacity - alpha]
        second = [size for _, size in items if 2 * size > capacity and size <= capacity - alpha]
        third = [size for _, size in items if 2 * size <= capacity and size >= alpha]
        excess = sum(third) - (len(second) * capacity - sum(second))
        bound = len(first) + len(second) + (ceiling(excess, capacity) if excess > 0 else 0)
        rows.append((alpha, len(first), len(second), len(third), bound))
    return ceiling(total, capacity), max(row[4] for row in rows), rows


class ExactSearch:
    def __init__(self, items, capacity, limit, lower, incumbent, emit):
        self.items = descending(items)
        self.capacity = capacity
        self.limit = limit
        self.lower = lower
        self.best = [bin.copy() for bin in incumbent]
        self.live = []
        self.nodes = 0
        self.status = None
        self.emit = emit
        self.remaining = [0] * (len(items) + 1)
        for index in range(len(items) - 1, -1, -1):
            self.remaining[index] = self.remaining[index + 1] + self.items[index][1]

    def visit(self, index):
        if self.nodes == self.limit:
            self.status = "limit"
            return
        self.nodes += 1
        count = len(self.live)
        used = self.remaining[0] - self.remaining[index]
        free = count * self.capacity - used
        excess = self.remaining[index] - free
        minimum = count + (ceiling(excess, self.capacity) if excess > 0 else 0)
        if minimum >= len(self.best):
            return
        if index == len(self.items):
            self.best = [bin.copy() for bin in self.live]
            self.emit(f"IMPROVE bins={count} nodes={self.nodes}")
            if count == self.lower:
                self.status = "bound"
            return
        item = self.items[index]
        seen_loads = set()
        for bin in self.live:
            old_load = bin.load
            if old_load in seen_loads:
                continue
            seen_loads.add(old_load)
            if old_load + item[1] > self.capacity:
                continue
            bin.put(item)
            self.visit(index + 1)
            bin.items.pop()
            bin.load = old_load
            if self.status is not None:
                return
        if count + 1 < len(self.best):
            bin = Bin()
            bin.put(item)
            self.live.append(bin)
            self.visit(index + 1)
            self.live.pop()


class Shelf:
    def __init__(self, bottom, height):
        self.bottom = bottom
        self.height = height
        self.used = 0
        self.items = []


class Sheet:
    def __init__(self, width, height):
        self.free = [(0, 0, width, height)]
        self.placements = []
        self.area = 0


class PackingLab:
    def __init__(self):
        self.items = None
        self.capacity = None
        self.output = []

    def emit(self, *parts):
        self.output.append(" ".join(str(part) for part in parts))

    def total(self):
        return sum(size for _, size in self.items)

    def bin_line(self, number, bin, capacity, classes=False, over=False):
        text = f"BIN {number} load={bin.load}/{capacity} items=" + " ".join(item_text(item) for item in bin.items)
        if classes:
            text += f" class={bin.category}"
        if over:
            text += " OVER"
        self.emit(text)

    def bin_lines(self, bins, classes=False):
        for number, bin in enumerate(bins, 1):
            self.bin_line(number, bin, self.capacity, classes)

    def method(self, method, arguments):
        parameter = int(arguments[0]) if method in PARAMETERIZED else 0
        if method in PARAMETERIZED and parameter == 0:
            raise CommandError("BAD PARAMETER")
        return pack(self.items, self.capacity, method, parameter)

    def cmd_items(self, capacity, *sizes):
        capacity = int(capacity)
        if capacity == 0:
            raise CommandError("BAD CAPACITY")
        items = [(index, int(size)) for index, size in enumerate(sizes, 1)]
        for number, size in items:
            if size == 0 or size > capacity:
                raise CommandError(f"BAD ITEM {number}")
        self.capacity, self.items = capacity, items
        self.emit(f"ITEMS count={len(items)} capacity={capacity} total={self.total()}")

    def cmd_random(self, count, capacity, seed):
        count, capacity, value = int(count), int(capacity), int(seed)
        if count == 0 or count > 40:
            raise CommandError("BAD COUNT")
        if capacity == 0:
            raise CommandError("BAD CAPACITY")
        if value == 0 or value >= 2147483647:
            raise CommandError("BAD SEED")
        items = []
        for number in range(1, count + 1):
            value = 48271 * value % 2147483647
            items.append((number, value % capacity + 1))
        self.capacity, self.items = capacity, items
        self.emit(f"RANDOM count={count} capacity={capacity} total={self.total()}")
        self.emit("SIZES", *(size for _, size in items))

    def run_method(self, method, arguments):
        result = self.method(method, arguments)
        self.emit(result.header(self.capacity, self.total()))
        self.bin_lines(result.bins, method == "HARMONIC")

    def cmd_trace(self, method, *arguments):
        result = self.method(method, arguments)
        self.emit("TRACE", result.header(self.capacity, self.total()))
        for step, (item, bin, inspected, opened, closed, category) in enumerate(result.steps, 1):
            text = f"STEP {step} item={item_text(item)} bin={bin + 1} inspected={inspected}"
            if opened:
                text += " new"
            if closed is not None:
                text += f" closed={closed + 1}"
            if category is not None:
                text += f" class={category}"
            self.emit(text)

    def cmd_reduce(self, method, *arguments):
        result = self.method(method, arguments)
        bins = result.bins
        before = len(bins)
        events = []
        while True:
            eliminated = False
            for source in sorted(range(len(bins)), key=lambda index: (bins[index].load, index)):
                loads = [bin.load for bin in bins]
                moves = []
                for item in descending(bins[source].items):
                    fitting = [index for index in range(len(bins)) if index != source and loads[index] + item[1] <= self.capacity]
                    if not fitting:
                        break
                    destination = max(fitting, key=lambda index: (loads[index], -index))
                    loads[destination] += item[1]
                    moves.append((item, destination))
                else:
                    move_text = " ".join(f"{item_text(item)}->{destination + 1}" for item, destination in moves)
                    events.append(f"ELIMINATE bin={source + 1} load={bins[source].load} moves={move_text}")
                    for item, destination in moves:
                        bins[destination].put(item)
                    bins.pop(source)
                    eliminated = True
                    break
            if not eliminated:
                break
        self.emit(f"REDUCE {result.name()} before={before} after={len(bins)} eliminated={before - len(bins)}")
        for event in events:
            self.emit(event)
        self.bin_lines(bins, method == "HARMONIC")

    def cmd_bounds(self):
        first, second, rows = bounds(self.items, self.capacity)
        self.emit(f"BOUNDS total={self.total()} L1={first} L2={second}")
        for alpha, count1, count2, count3, bound in rows:
            self.emit(f"ALPHA {alpha} j1={count1} j2={count2} j3={count3} bound={bound}")

    def cmd_compare(self, parameter):
        parameter = int(parameter)
        if parameter == 0:
            raise CommandError("BAD PARAMETER")
        first, second, _ = bounds(self.items, self.capacity)
        results = [pack(self.items, self.capacity, method, parameter) for method in METHODS]
        results.sort(key=lambda result: (len(result.bins), result.method))
        self.emit(f"COMPARE k={parameter} L1={first} L2={second}")
        for result in results:
            count = len(result.bins)
            self.emit(f"{result.method} bins={count} gap={count - second} waste={count * self.capacity - self.total()} inspections={result.inspections}")

    def cmd_exact(self, limit):
        limit = int(limit)
        if limit == 0:
            raise CommandError("BAD PARAMETER")
        if len(self.items) >= 21:
            raise CommandError("TOO MANY ITEMS")
        incumbent = pack(self.items, self.capacity, "FFD").bins
        _, lower, _ = bounds(self.items, self.capacity)
        self.emit(f"EXACT ffd={len(incumbent)} L2={lower}")
        search = ExactSearch(self.items, self.capacity, limit, lower, incumbent, self.emit)
        if len(incumbent) == lower:
            search.status = "bound"
        else:
            search.visit(0)
        status = search.status or "complete"
        self.emit(f"RESULT bins={len(search.best)} nodes={search.nodes} status={status}")
        self.bin_lines(search.best)

    def cmd_check(self, *assignments):
        labels = [int(value) for value in assignments]
        if len(labels) != len(self.items) or any(label == 0 for label in labels):
            raise CommandError("BAD ASSIGNMENT")
        bins = {}
        for label, item in zip(labels, self.items):
            bins.setdefault(label, Bin()).put(item)
        overfull = sum(bin.load > self.capacity for bin in bins.values())
        _, lower, _ = bounds(self.items, self.capacity)
        self.emit(f"CHECK bins={len(bins)} over={overfull} L2={lower} status={'invalid' if overfull else 'valid'}")
        for label in sorted(bins):
            bin = bins[label]
            self.bin_line(label, bin, self.capacity, over=bin.load > self.capacity)

    def cover_lines(self, name, bins):
        covered = [bin for bin in bins if bin.load >= self.capacity]
        rest = next((bin for bin in bins if bin.load < self.capacity), None)
        self.emit(f"{name} covered={len(covered)} rest={0 if rest is None else rest.load}")
        self.bin_lines(covered)
        if rest is not None:
            self.emit("REST items=" + " ".join(item_text(item) for item in rest.items))

    def cmd_cover(self):
        self.emit(f"COVER total={self.total()} upper={self.total() // self.capacity}")
        sequential = []
        for item in self.items:
            if not sequential or sequential[-1].load >= self.capacity:
                sequential.append(Bin())
            sequential[-1].put(item)
        self.cover_lines("DNF", sequential)
        available = descending(self.items)
        paired = []
        while available:
            bin = Bin()
            bin.put(available.pop(0))
            while bin.load < self.capacity and available:
                bin.put(available.pop())
            paired.append(bin)
        self.cover_lines("BIGSMALL", paired)

    def machine_lines(self, machines):
        for number, bin in enumerate(machines, 1):
            items = " ".join(item_text(item) for item in bin.items) or "-"
            self.emit(f"MACHINE {number} load={bin.load} items={items}")

    def cmd_multifit(self, count):
        count = int(count)
        if count == 0:
            raise CommandError("BAD PARAMETER")
        total = self.total()
        largest = max(size for _, size in self.items)
        lower = max(ceiling(total, count), largest)
        upper = max(ceiling(2 * total, count), largest)
        self.emit(f"MULTIFIT m={count} lower={lower} upper={upper}")
        while lower < upper:
            middle = (lower + upper) // 2
            number = len(pack(self.items, middle, "FFD").bins)
            success = number <= count
            self.emit(f"TRY cap={middle} bins={number} {'ok' if success else 'fail'}")
            if success:
                upper = middle
            else:
                lower = middle + 1
        machines = pack(self.items, upper, "FFD").bins
        machines.extend(Bin() for _ in range(count - len(machines)))
        self.emit(f"RESULT cap={upper} makespan={max(bin.load for bin in machines)}")
        self.machine_lines(machines)
        lpt = [Bin() for _ in range(count)]
        for item in descending(self.items):
            chosen = min(range(count), key=lambda index: (lpt[index].load, index))
            lpt[chosen].put(item)
        self.emit(f"LPT makespan={max(bin.load for bin in lpt)}")
        self.machine_lines(lpt)

    def maximal_patterns(self, length, pieces):
        patterns = []

        def enumerate_prefix(index, remaining, prefix):
            size = pieces[index][0]
            maximum = remaining // size
            if index == len(pieces) - 1:
                patterns.append((prefix + (maximum,), remaining - maximum * size))
                return
            for count in range(maximum, -1, -1):
                enumerate_prefix(index + 1, remaining - count * size, prefix + (count,))

        enumerate_prefix(0, length, ())
        return patterns

    def cmd_cutstock(self, length, *tokens):
        length = int(length)
        if length == 0:
            raise CommandError("BAD CAPACITY")
        pieces = []
        seen = set()
        for number, token in enumerate(tokens, 1):
            size, demand = (int(value) for value in token.split(":"))
            if size == 0 or size > length or demand == 0:
                raise CommandError(f"BAD PIECE {number}")
            if size in seen:
                raise CommandError(f"DUPLICATE PIECE {number}")
            seen.add(size)
            pieces.append((size, demand))
        pieces.sort(reverse=True)
        patterns = self.maximal_patterns(length, pieces)
        remaining = [demand for _, demand in pieces]
        uses = [0] * len(patterns)
        while any(remaining):
            chosen = max(
                range(len(patterns)),
                key=lambda index: (sum(min(count, needed) for count, needed in zip(patterns[index][0], remaining)), -index),
            )
            uses[chosen] += 1
            remaining = [max(0, needed - count) for needed, count in zip(remaining, patterns[chosen][0])]
        cut = [sum(use * pattern[0][index] for use, pattern in zip(uses, patterns)) for index in range(len(pieces))]
        quantity = sum(size * demand for size, demand in pieces)
        bars = sum(uses)
        self.emit(f"CUTSTOCK L={length} pieces={len(pieces)} patterns={len(patterns)}")
        for number, (counts, trim) in enumerate(patterns, 1):
            breakdown = "+".join(f"{count}x{size}" for count, (size, _) in zip(counts, pieces) if count)
            self.emit(f"PATTERN {number} {breakdown} rest={trim}")
        for number, use in enumerate(uses, 1):
            if use:
                self.emit(f"USE {number} bars={use}")
        for (size, demand), count in zip(pieces, cut):
            self.emit(f"PIECE {size} demand={demand} cut={count}")
        trim = sum(use * pattern[1] for use, pattern in zip(uses, patterns))
        surplus = sum(cut) - sum(demand for _, demand in pieces)
        self.emit(f"TOTAL bars={bars} trim={trim} surplus={surplus} waste={bars * length - quantity}")
        sizes = [size for size, demand in pieces for _ in range(demand)]
        comparison = pack(list(enumerate(sizes, 1)), length, "FIRSTFIT")
        count = len(comparison.bins)
        self.emit(f"FFD bars={count} waste={count * length - quantity}")
        self.emit(f"LOWER bars={ceiling(quantity, length)}")

    def rectangles(self, tokens):
        return [(number, *(int(value) for value in token.split("x"))) for number, token in enumerate(tokens, 1)]

    def drawing(self, width, height, placements):
        cells = [["."] * width for _ in range(height)]
        for number, x, y, rectangle_width, rectangle_height, _ in placements:
            letter = chr(64 + number)
            for row in range(y, y + rectangle_height):
                cells[row][x:x + rectangle_width] = [letter] * rectangle_width
        for row in reversed(cells):
            self.emit("".join(row))

    def shelf_method(self, method, width, rectangles, area):
        shelves = []
        placements = []
        for number, rectangle_width, rectangle_height in rectangles:
            chosen = None
            if method == "NFDH":
                if shelves and shelves[-1].used + rectangle_width <= width:
                    chosen = len(shelves) - 1
            else:
                fitting = [index for index, shelf in enumerate(shelves) if shelf.used + rectangle_width <= width]
                if fitting:
                    chosen = fitting[0] if method == "FFDH" else max(fitting, key=lambda index: (shelves[index].used, -index))
            if chosen is None:
                bottom = shelves[-1].bottom + shelves[-1].height if shelves else 0
                chosen = len(shelves)
                shelves.append(Shelf(bottom, rectangle_height))
            shelf = shelves[chosen]
            shelf.items.append((number, shelf.used))
            placements.append((number, shelf.used, shelf.bottom, rectangle_width, rectangle_height, False))
            shelf.used += rectangle_width
        height = shelves[-1].bottom + shelves[-1].height
        self.emit(f"{method} height={height} shelves={len(shelves)} util={area * 100 // (width * height)}")
        for number, shelf in enumerate(shelves, 1):
            items = " ".join(f"{chr(64 + rectangle)}@{x}" for rectangle, x in shelf.items)
            self.emit(f"LEVEL {number} y={shelf.bottom} h={shelf.height} used={shelf.used} items={items}")
        self.drawing(width, height, placements)

    def cmd_shelf(self, width, *tokens):
        width = int(width)
        if width == 0:
            raise CommandError("BAD CAPACITY")
        rectangles = self.rectangles(tokens)
        for number, rectangle_width, rectangle_height in rectangles:
            if rectangle_width == 0 or rectangle_height == 0 or rectangle_width > width:
                raise CommandError(f"BAD RECT {number}")
        rectangles.sort(key=lambda rectangle: (-rectangle[2], -rectangle[1], rectangle[0]))
        area = sum(rectangle_width * rectangle_height for _, rectangle_width, rectangle_height in rectangles)
        self.emit(f"SHELF W={width} rects={len(rectangles)} area={area}")
        for method in ("NFDH", "FFDH", "BFDH"):
            self.shelf_method(method, width, rectangles, area)
        heights = [0] * width
        placements = []
        for number, rectangle_width, rectangle_height in rectangles:
            x = min(range(width - rectangle_width + 1), key=lambda column: (max(heights[column:column + rectangle_width]), column))
            y = max(heights[x:x + rectangle_width])
            heights[x:x + rectangle_width] = [y + rectangle_height] * rectangle_width
            placements.append((number, x, y, rectangle_width, rectangle_height, False))
        height = max(heights)
        self.emit(f"SKYLINE height={height} util={area * 100 // (width * height)}")
        for number, x, y, rectangle_width, rectangle_height, _ in placements:
            self.emit(f"PLACE {chr(64 + number)} x={x} y={y} w={rectangle_width} h={rectangle_height}")
        self.drawing(width, height, placements)

    def free_rectangle(self, sheets, width, height, rotate, rule):
        chosen = None
        best = None
        for sheet_number, sheet in enumerate(sheets):
            for index, (_, _, free_width, free_height) in enumerate(sheet.free):
                fits = width <= free_width and height <= free_height
                fits_rotated = rotate and height <= free_width and width <= free_height
                if not (fits or fits_rotated):
                    continue
                if rule == "FIRST":
                    return sheet_number, index
                key = free_width * free_height, sheet_number, index
                if best is None or key < best:
                    best = key
                    chosen = sheet_number, index
        return chosen

    def cmd_guillotine(self, width, height, mode, rule, *tokens):
        width, height = int(width), int(height)
        if width == 0 or height == 0:
            raise CommandError("BAD CAPACITY")
        rectangles = self.rectangles(tokens)
        rotate = mode == "ROTATE"
        for number, rectangle_width, rectangle_height in rectangles:
            fits = rectangle_width <= width and rectangle_height <= height
            fits_rotated = rotate and rectangle_height <= width and rectangle_width <= height
            if rectangle_width == 0 or rectangle_height == 0 or not (fits or fits_rotated):
                raise CommandError(f"BAD RECT {number}")
        rectangles.sort(key=lambda rectangle: (-rectangle[1] * rectangle[2], rectangle[0]))
        sheets = []
        rotated_count = 0
        for number, rectangle_width, rectangle_height in rectangles:
            chosen = self.free_rectangle(sheets, rectangle_width, rectangle_height, rotate, rule)
            if chosen is None:
                chosen = len(sheets), 0
                sheets.append(Sheet(width, height))
            sheet_number, index = chosen
            sheet = sheets[sheet_number]
            x, y, free_width, free_height = sheet.free.pop(index)
            rotated = not (rectangle_width <= free_width and rectangle_height <= free_height)
            placed_width, placed_height = (rectangle_height, rectangle_width) if rotated else (rectangle_width, rectangle_height)
            rotated_count += rotated
            sheet.placements.append((number, x, y, placed_width, placed_height, rotated))
            sheet.area += rectangle_width * rectangle_height
            right_width = free_width - placed_width
            top_height = free_height - placed_height
            if right_width <= top_height:
                children = (
                    (x, y + placed_height, free_width, top_height),
                    (x + placed_width, y, right_width, placed_height),
                )
            else:
                children = (
                    (x, y + placed_height, placed_width, top_height),
                    (x + placed_width, y, right_width, free_height),
                )
            sheet.free.extend(rectangle for rectangle in children if rectangle[2] and rectangle[3])
        area = sum(sheet.area for sheet in sheets)
        self.emit(
            f"GUILLOTINE W={width} H={height} mode={mode} rule={rule} rects={len(rectangles)}",
            f"sheets={len(sheets)} rotated={rotated_count} util={area * 100 // (len(sheets) * width * height)}",
        )
        for number, sheet in enumerate(sheets, 1):
            self.emit(f"SHEET {number} placed={len(sheet.placements)} area={sheet.area}")
            for rectangle, x, y, placed_width, placed_height, rotated in sheet.placements:
                text = f"PLACE {chr(64 + rectangle)} x={x} y={y} w={placed_width} h={placed_height}"
                self.emit(text + (" rotated" if rotated else ""))
            free = " ".join(f"{x},{y},{free_width}x{free_height}" for x, y, free_width, free_height in sheet.free) or "none"
            self.emit("FREE", free)
            self.drawing(width, height, sheet.placements)

    def execute(self, line):
        command, *arguments = line.split()
        try:
            if command not in ("ITEMS", "RANDOM", "CUTSTOCK", "SHELF", "GUILLOTINE") and self.items is None:
                raise CommandError("NO ITEMS")
            if command in METHODS:
                self.run_method(command, arguments)
            else:
                getattr(self, "cmd_" + command.lower())(*arguments)
        except CommandError as error:
            self.emit("ERROR", str(error))


def main():
    count = int(sys.stdin.readline())
    laboratory = PackingLab()
    for _ in range(count):
        laboratory.execute(sys.stdin.readline())
    sys.stdout.write("\n".join(laboratory.output) + "\n")


if __name__ == "__main__":
    main()
