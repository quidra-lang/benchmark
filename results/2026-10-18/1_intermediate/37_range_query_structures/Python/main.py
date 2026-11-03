from math import gcd, isqrt
import sys


KINDS = ("SEG", "LAZY", "FEN", "RFEN", "SPARSE", "SQRT", "PERSIST", "GRID")
OPERATIONS = ("SUM", "MIN", "MAX", "GCD")


class CommandError(Exception):
    pass


def lowbit(position):
    return position & -position


def fenwick_add(tree, position, delta):
    size = len(tree) - 1
    visits = 0
    while position <= size:
        tree[position] += delta
        visits += 1
        position += lowbit(position)
    return visits


def fenwick_prefix(tree, position):
    total, visits = 0, 0
    while position >= 1:
        total += tree[position]
        visits += 1
        position -= lowbit(position)
    return total, visits


def tree_layout(n):
    low = [0] * (4 * n)
    high = [0] * (4 * n)
    numbers = []
    pending = [(1, 0, n - 1)]
    while pending:
        node, first, last = pending.pop()
        low[node] = first
        high[node] = last
        numbers.append(node)
        if first < last:
            middle = (first + last) // 2
            pending.append((2 * node, first, middle))
            pending.append((2 * node + 1, middle + 1, last))
    numbers.sort()
    return low, high, numbers


class SegmentTree:
    def __init__(self, values, op):
        self.op = op
        self.low, self.high, self.numbers = tree_layout(len(values))
        self.value = [0] * len(self.low)
        self.visits = 0
        self.build(1, values)

    def leaf(self, number):
        return abs(number) if self.op == "GCD" else number

    def combine(self, first, second):
        if self.op == "SUM":
            return first + second
        if self.op == "MIN":
            return min(first, second)
        if self.op == "MAX":
            return max(first, second)
        return gcd(first, second)

    def pull(self, node):
        self.value[node] = self.combine(self.value[2 * node], self.value[2 * node + 1])

    def build(self, node, values):
        if self.low[node] == self.high[node]:
            self.value[node] = self.leaf(values[self.low[node]])
            return
        self.build(2 * node, values)
        self.build(2 * node + 1, values)
        self.pull(node)

    def query(self, left, right):
        self.visits = 0
        answer = self.query_node(1, left, right)
        return answer, self.visits

    def query_node(self, node, left, right):
        self.visits += 1
        low, high = self.low[node], self.high[node]
        if left <= low and high <= right:
            return self.value[node]
        middle = (low + high) // 2
        if right <= middle:
            return self.query_node(2 * node, left, right)
        if left > middle:
            return self.query_node(2 * node + 1, left, right)
        left_result = self.query_node(2 * node, left, right)
        right_result = self.query_node(2 * node + 1, left, right)
        return self.combine(left_result, right_result)

    def update(self, index, number):
        node = 1
        while self.low[node] < self.high[node]:
            middle = (self.low[node] + self.high[node]) // 2
            node = 2 * node if index <= middle else 2 * node + 1
        self.value[node] = self.leaf(number)
        visited = 1
        while node > 1:
            node //= 2
            self.pull(node)
            visited += 1
        return visited


class LazyTree:
    def __init__(self, values):
        self.low, self.high, self.numbers = tree_layout(len(values))
        size = len(self.low)
        self.sums = [0] * size
        self.mins = [0] * size
        self.maxes = [0] * size
        self.assigned = [None] * size
        self.added = [0] * size
        self.visits = self.covered = self.pushes = 0
        self.build(1, values)

    def is_leaf(self, node):
        return self.low[node] == self.high[node]

    def length(self, node):
        return self.high[node] - self.low[node] + 1

    def build(self, node, values):
        if self.is_leaf(node):
            value = values[self.low[node]]
            self.sums[node] = self.mins[node] = self.maxes[node] = value
            return
        self.build(2 * node, values)
        self.build(2 * node + 1, values)
        self.pull(node)

    def pull(self, node):
        left, right = 2 * node, 2 * node + 1
        self.sums[node] = self.sums[left] + self.sums[right]
        self.mins[node] = min(self.mins[left], self.mins[right])
        self.maxes[node] = max(self.maxes[left], self.maxes[right])

    def apply_assign(self, node, value):
        self.sums[node] = value * self.length(node)
        self.mins[node] = self.maxes[node] = value
        if not self.is_leaf(node):
            self.assigned[node] = value
            self.added[node] = 0

    def apply_add(self, node, value):
        self.sums[node] += value * self.length(node)
        self.mins[node] += value
        self.maxes[node] += value
        if not self.is_leaf(node):
            self.added[node] += value

    def push(self, node):
        assigned, added = self.assigned[node], self.added[node]
        if assigned is None and added == 0:
            return
        self.pushes += 1
        for child in (2 * node, 2 * node + 1):
            if assigned is not None:
                self.apply_assign(child, assigned)
            if added != 0:
                self.apply_add(child, added)
        self.assigned[node] = None
        self.added[node] = 0

    def update(self, left, right, value, assign):
        self.visits = self.covered = self.pushes = 0
        self.update_node(1, left, right, value, assign)
        return self.visits, self.covered, self.pushes

    def update_node(self, node, left, right, value, assign):
        self.visits += 1
        low, high = self.low[node], self.high[node]
        if left <= low and high <= right:
            self.covered += 1
            if assign:
                self.apply_assign(node, value)
            else:
                self.apply_add(node, value)
            return
        self.push(node)
        middle = (low + high) // 2
        if left <= middle:
            self.update_node(2 * node, left, right, value, assign)
        if right > middle:
            self.update_node(2 * node + 1, left, right, value, assign)
        self.pull(node)

    def query(self, left, right):
        self.visits = self.pushes = 0
        total, smallest, largest = self.query_node(1, left, right)
        return total, smallest, largest, self.visits, self.pushes

    def query_node(self, node, left, right):
        self.visits += 1
        low, high = self.low[node], self.high[node]
        if left <= low and high <= right:
            return self.sums[node], self.mins[node], self.maxes[node]
        self.push(node)
        middle = (low + high) // 2
        if right <= middle:
            return self.query_node(2 * node, left, right)
        if left > middle:
            return self.query_node(2 * node + 1, left, right)
        left_sum, left_min, left_max = self.query_node(2 * node, left, right)
        right_sum, right_min, right_max = self.query_node(2 * node + 1, left, right)
        return left_sum + right_sum, min(left_min, right_min), max(left_max, right_max)


class FenwickTree:
    def __init__(self, values):
        self.values = list(values)
        self.tree = [0] * (len(values) + 1)
        for index, value in enumerate(values):
            fenwick_add(self.tree, index + 1, value)

    def add(self, index, delta):
        self.values[index] += delta
        return fenwick_add(self.tree, index + 1, delta)

    def range_sum(self, left, right):
        upper, upper_visits = fenwick_prefix(self.tree, right + 1)
        lower, lower_visits = fenwick_prefix(self.tree, left)
        return upper - lower, upper_visits + lower_visits

    def lower_bound(self, k):
        n = len(self.values)
        step = 1 << (n.bit_length() - 1)
        position, rest, visits = 0, k, 0
        while step >= 1:
            if position + step <= n:
                visits += 1
                value = self.tree[position + step]
                if value < rest:
                    rest -= value
                    position += step
            step //= 2
        return (position if position < n else None), visits


class RangeFenwick:
    def __init__(self, values):
        n = len(values)
        self.b1 = [0] * (n + 1)
        self.b2 = [0] * (n + 1)
        for position in range(1, n + 1):
            previous = values[position - 2] if position > 1 else 0
            difference = values[position - 1] - previous
            fenwick_add(self.b1, position, difference)
            fenwick_add(self.b2, position, (position - 1) * difference)

    def add(self, left, right, delta):
        visits = fenwick_add(self.b1, left + 1, delta)
        visits += fenwick_add(self.b1, right + 2, -delta)
        visits += fenwick_add(self.b2, left + 1, delta * left)
        visits += fenwick_add(self.b2, right + 2, -delta * (right + 1))
        return visits

    def prefix(self, position):
        first, first_visits = fenwick_prefix(self.b1, position)
        second, second_visits = fenwick_prefix(self.b2, position)
        return position * first - second, first_visits + second_visits

    def range_sum(self, left, right):
        upper, upper_visits = self.prefix(right + 1)
        lower, lower_visits = self.prefix(left)
        return upper - lower, upper_visits + lower_visits


class SparseTable:
    def __init__(self, values):
        self.values = list(values)
        n = len(values)
        self.levels = n.bit_length()
        self.mins = [list(range(n))]
        self.maxes = [list(range(n))]
        for level in range(1, self.levels):
            half = 1 << (level - 1)
            mins = []
            maxes = []
            for index in range(n - (1 << level) + 1):
                mins.append(self.lower(self.mins[-1][index], self.mins[-1][index + half]))
                maxes.append(self.higher(self.maxes[-1][index], self.maxes[-1][index + half]))
            self.mins.append(mins)
            self.maxes.append(maxes)

    def lower(self, first, second):
        return first if self.values[first] <= self.values[second] else second

    def higher(self, first, second):
        return first if self.values[first] >= self.values[second] else second

    def query(self, left, right):
        level = (right - left + 1).bit_length() - 1
        end = right - (1 << level) + 1
        minimum = self.lower(self.mins[level][left], self.mins[level][end])
        maximum = self.higher(self.maxes[level][left], self.maxes[level][end])
        return minimum, maximum, level


class SqrtDecomposition:
    def __init__(self, values, block):
        self.n = len(values)
        self.block = block
        self.count = (self.n + block - 1) // block
        self.raw = list(values)
        self.tags = [0] * self.count
        self.sums = [0] * self.count
        for index, value in enumerate(values):
            self.sums[index // block] += value

    def split(self, left, right):
        first, last = left // self.block, right // self.block
        if first == last:
            return list(range(left, right + 1)), []
        cells = list(range(left, (first + 1) * self.block))
        cells.extend(range(last * self.block, right + 1))
        return cells, list(range(first + 1, last))

    def add(self, left, right, delta):
        cells, wholes = self.split(left, right)
        for index in cells:
            self.raw[index] += delta
            self.sums[index // self.block] += delta
        for number in wholes:
            self.tags[number] += delta
            self.sums[number] += delta * self.block
        return len(wholes), len(cells)

    def range_sum(self, left, right):
        cells, wholes = self.split(left, right)
        total = sum(self.raw[index] + self.tags[index // self.block] for index in cells)
        total += sum(self.sums[number] for number in wholes)
        return total, len(wholes), len(cells)


class NodePool:
    def __init__(self):
        self.left = []
        self.right = []
        self.total = []

    def create(self, left, right, total):
        self.left.append(left)
        self.right.append(right)
        self.total.append(total)
        return len(self.total) - 1

    def build(self, values, low, high):
        if low == high:
            return self.create(-1, -1, values[low])
        middle = (low + high) // 2
        left = self.build(values, low, middle)
        right = self.build(values, middle + 1, high)
        return self.create(left, right, self.total[left] + self.total[right])

    def assign(self, node, low, high, index, value):
        if low == high:
            return self.create(-1, -1, value)
        middle = (low + high) // 2
        left, right = self.left[node], self.right[node]
        if index <= middle:
            left = self.assign(left, low, middle, index, value)
        else:
            right = self.assign(right, middle + 1, high, index, value)
        return self.create(left, right, self.total[left] + self.total[right])

    def increment(self, node, low, high, index):
        left, right = self.left[node], self.right[node]
        if low < high:
            middle = (low + high) // 2
            if index <= middle:
                left = self.increment(left, low, middle, index)
            else:
                right = self.increment(right, middle + 1, high, index)
        return self.create(left, right, self.total[node] + 1)


class PersistentTree:
    def __init__(self, values):
        self.n = len(values)
        self.positions = NodePool()
        self.versions = [self.positions.build(values, 0, self.n - 1)]
        self.distinct = sorted(set(values))
        ranks = {value: rank for rank, value in enumerate(self.distinct)}
        last = len(self.distinct) - 1
        self.counts = NodePool()
        self.prefixes = [self.counts.build([0] * len(self.distinct), 0, last)]
        for value in values:
            self.prefixes.append(self.counts.increment(self.prefixes[-1], 0, last, ranks[value]))
        self.visits = 0

    def assign(self, version, index, value):
        before = len(self.positions.total)
        root = self.positions.assign(self.versions[version], 0, self.n - 1, index, value)
        self.versions.append(root)
        return len(self.versions) - 1, len(self.positions.total) - before

    def query(self, version, left, right):
        self.visits = 0
        total = self.query_node(self.versions[version], 0, self.n - 1, left, right)
        return total, self.visits

    def query_node(self, node, low, high, left, right):
        self.visits += 1
        if left <= low and high <= right:
            return self.positions.total[node]
        middle = (low + high) // 2
        if right <= middle:
            return self.query_node(self.positions.left[node], low, middle, left, right)
        if left > middle:
            return self.query_node(self.positions.right[node], middle + 1, high, left, right)
        left_total = self.query_node(self.positions.left[node], low, middle, left, right)
        right_total = self.query_node(self.positions.right[node], middle + 1, high, left, right)
        return left_total + right_total

    def kth(self, left, right, k):
        pool = self.counts
        newer = self.prefixes[right + 1]
        older = self.prefixes[left]
        low, high = 0, len(self.distinct) - 1
        visits = 1
        while low < high:
            middle = (low + high) // 2
            difference = pool.total[pool.left[newer]] - pool.total[pool.left[older]]
            if k <= difference:
                newer, older = pool.left[newer], pool.left[older]
                high = middle
            else:
                k -= difference
                newer, older = pool.right[newer], pool.right[older]
                low = middle + 1
            visits += 1
        return self.distinct[low], visits


class Grid:
    def __init__(self, rows, cols, values):
        self.rows = rows
        self.cols = cols
        self.tree = [[0] * (cols + 1) for _ in range(rows + 1)]
        for row in range(rows):
            for col in range(cols):
                self.add(row, col, values[row * cols + col])

    def add(self, row, col, delta):
        visits = 0
        y = row + 1
        while y <= self.rows:
            z = col + 1
            while z <= self.cols:
                self.tree[y][z] += delta
                visits += 1
                z += lowbit(z)
            y += lowbit(y)
        return visits

    def prefix(self, rows, cols):
        total, visits = 0, 0
        y = rows
        while y >= 1:
            z = cols
            while z >= 1:
                total += self.tree[y][z]
                visits += 1
                z -= lowbit(z)
            y -= lowbit(y)
        return total, visits

    def rectangle(self, top, left, bottom, right):
        whole, whole_visits = self.prefix(bottom + 1, right + 1)
        above, above_visits = self.prefix(top, right + 1)
        beside, beside_visits = self.prefix(bottom + 1, left)
        corner, corner_visits = self.prefix(top, left)
        visits = whole_visits + above_visits + beside_visits + corner_visits
        return whole - above - beside + corner, visits


class DistinctCounter:
    def __init__(self, size):
        self.counts = [0] * size
        self.distinct = 0

    def add(self, code):
        self.counts[code] += 1
        if self.counts[code] == 1:
            self.distinct += 1

    def remove(self, code):
        self.counts[code] -= 1
        if self.counts[code] == 0:
            self.distinct -= 1


def mo_order(queries, block):
    def key(number):
        left, right = queries[number]
        group = left // block
        return group, right if group % 2 == 0 else -right, number

    return sorted(range(len(queries)), key=key)


def run_mo(values, queries, order):
    ranks = {value: rank for rank, value in enumerate(sorted(set(values)))}
    codes = [ranks[value] for value in values]
    window = DistinctCounter(len(ranks))
    answers = [0] * len(queries)
    current_left, current_right = 0, -1
    moves = 0
    for number in order:
        left, right = queries[number]
        moves += abs(left - current_left) + abs(right - current_right)
        while current_left > left:
            current_left -= 1
            window.add(codes[current_left])
        while current_right < right:
            current_right += 1
            window.add(codes[current_right])
        while current_left < left:
            window.remove(codes[current_left])
            current_left += 1
        while current_right > right:
            window.remove(codes[current_right])
            current_right -= 1
        answers[number] = window.distinct
    return answers, moves


class Laboratory:
    def __init__(self, values):
        self.array = list(values)
        self.original = list(values)
        self.seg = self.lazy = self.fen = self.rfen = self.sparse = self.sqrt = self.persist = None
        self.grid = None
        self.output = []

    def emit(self, *parts):
        self.output.append(" ".join(str(part) for part in parts))

    def array_structures(self):
        return self.seg, self.lazy, self.fen, self.rfen, self.sparse, self.sqrt, self.persist

    def require(self, structure, kind):
        if structure is None:
            raise CommandError(f"NOT BUILT {kind}")
        return structure

    def index_argument(self, text):
        index = int(text)
        if index < 0 or index >= len(self.array):
            raise CommandError(f"BAD INDEX {index}")
        return index

    def range_arguments(self, left_text, right_text):
        left = self.index_argument(left_text)
        right = self.index_argument(right_text)
        if left > right:
            raise CommandError(f"BAD RANGE {left} {right}")
        return left, right

    def version_argument(self, text):
        version = int(text)
        if version < 0 or version >= len(self.persist.versions):
            raise CommandError(f"BAD VERSION {version}")
        return version

    def cell_arguments(self, row_text, col_text):
        row, col = int(row_text), int(col_text)
        if row < 0 or row >= self.grid.rows or col < 0 or col >= self.grid.cols:
            raise CommandError(f"BAD CELL {row} {col}")
        return row, col

    def range_query(self, structure, kind, report, args):
        self.require(structure, kind)
        left, right = self.range_arguments(args[0], args[1])
        items, _ = report(left, right)
        return left, right, items

    def seg_report(self, left, right):
        answer, visits = self.seg.query(left, right)
        return f"{self.seg.op.lower()}={answer} visited={visits}", [(answer, self.seg.op)]

    def lazy_report(self, left, right):
        total, smallest, largest, visits, pushes = self.lazy.query(left, right)
        items = f"sum={total} min={smallest} max={largest} visited={visits} pushes={pushes}"
        return items, [(total, "SUM"), (smallest, "MIN"), (largest, "MAX")]

    def fen_report(self, left, right):
        total, visits = self.fen.range_sum(left, right)
        return f"sum={total} visited={visits}", [(total, "SUM")]

    def rfen_report(self, left, right):
        total, visits = self.rfen.range_sum(left, right)
        return f"sum={total} visited={visits}", [(total, "SUM")]

    def sparse_report(self, left, right):
        minimum, maximum, level = self.sparse.query(left, right)
        low, high = self.sparse.values[minimum], self.sparse.values[maximum]
        items = f"min={low} minpos={minimum} max={high} maxpos={maximum} level={level}"
        return items, [(low, "MIN"), (high, "MAX")]

    def sqrt_report(self, left, right):
        total, whole, cells = self.sqrt.range_sum(left, right)
        return f"sum={total} whole={whole} cells={cells}", [(total, "SUM")]

    def persist_report(self, version, left, right):
        total, visits = self.persist.query(version, left, right)
        return f"sum={total} visited={visits}", [(total, "SUM")]

    def show_array(self, args):
        left, right = self.range_arguments(args[0], args[1])
        self.emit("ARRAY", left, right, *self.array[left:right + 1])

    def load(self, args):
        values = [int(text) for text in args]
        removed = sum(structure is not None for structure in self.array_structures())
        self.array = values
        self.original = list(values)
        self.seg = self.lazy = self.fen = self.rfen = self.sparse = self.sqrt = self.persist = None
        self.emit(f"LOAD n={len(values)} removed={removed}")

    def reset(self, args):
        self.array = list(self.original)
        rebuilt = sum(structure is not None for structure in self.array_structures())
        if self.seg is not None:
            self.seg = SegmentTree(self.array, self.seg.op)
        if self.lazy is not None:
            self.lazy = LazyTree(self.array)
        if self.fen is not None:
            self.fen = FenwickTree(self.array)
        if self.rfen is not None:
            self.rfen = RangeFenwick(self.array)
        if self.sparse is not None:
            self.sparse = SparseTable(self.array)
        if self.sqrt is not None:
            self.sqrt = SqrtDecomposition(self.array, self.sqrt.block)
        if self.persist is not None:
            self.persist = PersistentTree(self.array)
        self.emit(f"RESET rebuilt={rebuilt}")

    def check(self, args):
        left, right = self.range_arguments(args[0], args[1])
        values = self.array[left:right + 1]
        expected = {"SUM": sum(values), "MIN": min(values), "MAX": max(values), "GCD": gcd(*values)}
        summary = " ".join(f"{op.lower()}={expected[op]}" for op in OPERATIONS)
        self.emit(f"CHECK {left} {right} {summary}")
        reports = []
        if self.seg is not None:
            reports.append(("SEG", *self.seg_report(left, right)))
        if self.lazy is not None:
            reports.append(("LAZY", *self.lazy_report(left, right)))
        if self.fen is not None:
            reports.append(("FEN", *self.fen_report(left, right)))
        if self.rfen is not None:
            reports.append(("RFEN", *self.rfen_report(left, right)))
        if self.sparse is not None:
            reports.append(("SPARSE", *self.sparse_report(left, right)))
        if self.sqrt is not None:
            reports.append(("SQRT", *self.sqrt_report(left, right)))
        if self.persist is not None:
            version = len(self.persist.versions) - 1
            items, pairs = self.persist_report(version, left, right)
            reports.append(("PERSIST", f"version={version} {items}", pairs))
        ok = 0
        for kind, items, pairs in reports:
            if all(value == expected[key] for value, key in pairs):
                verdict = "OK"
                ok += 1
            else:
                verdict = "DIFF"
            self.emit(kind, verdict, items)
        self.emit(f"RESULT ok={ok} diff={len(reports) - ok}")

    def mo(self, args):
        queries = [self.range_arguments(args[i], args[i + 1]) for i in range(0, len(args), 2)]
        block = isqrt(len(self.array))
        order = mo_order(queries, block)
        answers, moves = run_mo(self.array, queries, order)
        self.emit(f"MO queries={len(queries)} block={block} moves={moves}")
        self.emit("ORDER", *(number + 1 for number in order))
        for number, (left, right) in enumerate(queries):
            self.emit(f"ANSWER {number + 1} {left} {right} distinct={answers[number]}")

    def seg_build(self, args):
        op = args[0]
        if op not in OPERATIONS:
            raise CommandError(f"BAD OP {op}")
        seg = self.seg = SegmentTree(self.array, op)
        nodes = len(seg.numbers)
        self.emit(f"SEG BUILD {op} nodes={nodes} maxnode={seg.numbers[-1]} root={seg.value[1]}")

    def seg_query(self, args):
        left, right, items = self.range_query(self.seg, "SEG", self.seg_report, args)
        self.emit(f"SEG QUERY {left} {right} {items}")

    def seg_update(self, args):
        seg = self.require(self.seg, "SEG")
        index = self.index_argument(args[0])
        value = int(args[1])
        self.array[index] = value
        visited = seg.update(index, value)
        self.emit(f"SEG UPDATE {index} {value} root={seg.value[1]} visited={visited}")

    def seg_dump(self, args):
        seg = self.require(self.seg, "SEG")
        self.emit(f"SEG DUMP {seg.op} nodes={len(seg.numbers)}")
        for node in seg.numbers:
            self.emit("NODE", node, seg.low[node], seg.high[node], seg.value[node])

    def lazy_build(self, args):
        lazy = self.lazy = LazyTree(self.array)
        root = f"sum={lazy.sums[1]} min={lazy.mins[1]} max={lazy.maxes[1]}"
        self.emit(f"LAZY BUILD nodes={len(lazy.numbers)} {root}")

    def lazy_update(self, args, assign):
        lazy = self.require(self.lazy, "LAZY")
        left, right = self.range_arguments(args[0], args[1])
        value = int(args[2])
        for index in range(left, right + 1):
            self.array[index] = value if assign else self.array[index] + value
        visits, covered, pushes = lazy.update(left, right, value, assign)
        name = "ASSIGN" if assign else "ADD"
        counts = f"visited={visits} covered={covered} pushes={pushes}"
        self.emit(f"LAZY {name} {left} {right} {value} {counts}")

    def lazy_add(self, args):
        self.lazy_update(args, False)

    def lazy_assign(self, args):
        self.lazy_update(args, True)

    def lazy_query(self, args):
        left, right, items = self.range_query(self.lazy, "LAZY", self.lazy_report, args)
        self.emit(f"LAZY QUERY {left} {right} {items}")

    def lazy_dump(self, args):
        lazy = self.require(self.lazy, "LAZY")
        self.emit(f"LAZY DUMP nodes={len(lazy.numbers)}")
        for node in lazy.numbers:
            assigned = "-" if lazy.assigned[node] is None else lazy.assigned[node]
            self.emit(
                "NODE", node, lazy.low[node], lazy.high[node],
                f"sum={lazy.sums[node]}", f"min={lazy.mins[node]}", f"max={lazy.maxes[node]}",
                f"assign={assigned}", f"add={lazy.added[node]}",
            )

    def fen_build(self, args):
        self.fen = FenwickTree(self.array)
        self.emit(f"FEN BUILD n={len(self.array)} total={sum(self.array)}")

    def fen_add(self, args):
        fen = self.require(self.fen, "FEN")
        index = self.index_argument(args[0])
        value = int(args[1])
        self.array[index] += value
        visits = fen.add(index, value)
        self.emit(f"FEN ADD {index} {value} visited={visits}")

    def fen_prefix(self, args):
        fen = self.require(self.fen, "FEN")
        index = self.index_argument(args[0])
        total, visits = fenwick_prefix(fen.tree, index + 1)
        self.emit(f"FEN PREFIX {index} sum={total} visited={visits}")

    def fen_range(self, args):
        left, right, items = self.range_query(self.fen, "FEN", self.fen_report, args)
        self.emit(f"FEN RANGE {left} {right} {items}")

    def fen_lower(self, args):
        fen = self.require(self.fen, "FEN")
        k = int(args[0])
        for index, value in enumerate(fen.values):
            if value < 0:
                raise CommandError(f"NEGATIVE {index}")
        index, visits = fen.lower_bound(k)
        answer = "none" if index is None else index
        self.emit(f"FEN LOWER {k} index={answer} visited={visits}")

    def fen_dump(self, args):
        fen = self.require(self.fen, "FEN")
        self.emit(f"FEN DUMP n={len(fen.values)}")
        self.emit("T", *fen.tree[1:])

    def rfen_build(self, args):
        self.rfen = RangeFenwick(self.array)
        self.emit(f"RFEN BUILD n={len(self.array)} total={sum(self.array)}")

    def rfen_add(self, args):
        rfen = self.require(self.rfen, "RFEN")
        left, right = self.range_arguments(args[0], args[1])
        value = int(args[2])
        for index in range(left, right + 1):
            self.array[index] += value
        visits = rfen.add(left, right, value)
        self.emit(f"RFEN ADD {left} {right} {value} visited={visits}")

    def rfen_sum(self, args):
        left, right, items = self.range_query(self.rfen, "RFEN", self.rfen_report, args)
        self.emit(f"RFEN SUM {left} {right} {items}")

    def rfen_dump(self, args):
        rfen = self.require(self.rfen, "RFEN")
        self.emit(f"RFEN DUMP n={len(rfen.b1) - 1}")
        self.emit("B1", *rfen.b1[1:])
        self.emit("B2", *rfen.b2[1:])

    def sparse_build(self, args):
        self.sparse = SparseTable(self.array)
        entries = sum(len(row) for row in self.sparse.mins)
        self.emit(f"SPARSE BUILD levels={self.sparse.levels} entries={entries}")

    def sparse_query(self, args):
        left, right, items = self.range_query(self.sparse, "SPARSE", self.sparse_report, args)
        self.emit(f"SPARSE QUERY {left} {right} {items}")

    def sparse_dump(self, args):
        sparse = self.require(self.sparse, "SPARSE")
        self.emit(f"SPARSE DUMP levels={sparse.levels}")
        for level in range(sparse.levels):
            self.emit("MIN", level, *sparse.mins[level])
            self.emit("MAX", level, *sparse.maxes[level])

    def sqrt_build(self, args):
        n = len(self.array)
        block = int(args[0]) if args else isqrt(n)
        if block > n:
            raise CommandError(f"BAD BLOCK {block}")
        self.sqrt = SqrtDecomposition(self.array, block)
        self.emit(f"SQRT BUILD block={block} blocks={self.sqrt.count}")

    def sqrt_add(self, args):
        sqrt = self.require(self.sqrt, "SQRT")
        left, right = self.range_arguments(args[0], args[1])
        value = int(args[2])
        for index in range(left, right + 1):
            self.array[index] += value
        whole, cells = sqrt.add(left, right, value)
        self.emit(f"SQRT ADD {left} {right} {value} whole={whole} cells={cells}")

    def sqrt_sum(self, args):
        left, right, items = self.range_query(self.sqrt, "SQRT", self.sqrt_report, args)
        self.emit(f"SQRT SUM {left} {right} {items}")

    def sqrt_dump(self, args):
        sqrt = self.require(self.sqrt, "SQRT")
        self.emit(f"SQRT DUMP block={sqrt.block} blocks={sqrt.count}")
        for number in range(sqrt.count):
            first = number * sqrt.block
            last = min(first + sqrt.block, sqrt.n) - 1
            self.emit(
                "BLOCK", number, first, last, f"add={sqrt.tags[number]}",
                f"sum={sqrt.sums[number]}", *sqrt.raw[first:last + 1],
            )

    def persist_build(self, args):
        persist = self.persist = PersistentTree(self.array)
        sizes = f"distinct={len(persist.distinct)} valuenodes={len(persist.counts.total)}"
        self.emit(f"PERSIST BUILD nodes={len(persist.positions.total)} {sizes}")

    def persist_set(self, args):
        persist = self.require(self.persist, "PERSIST")
        version = self.version_argument(args[0])
        index = self.index_argument(args[1])
        value = int(args[2])
        number, created = persist.assign(version, index, value)
        self.emit(f"PERSIST SET {version} {index} {value} version={number} created={created}")

    def persist_query(self, args):
        self.require(self.persist, "PERSIST")
        version = self.version_argument(args[0])
        left, right = self.range_arguments(args[1], args[2])
        items, _ = self.persist_report(version, left, right)
        self.emit(f"PERSIST QUERY {version} {left} {right} {items}")

    def persist_kth(self, args):
        persist = self.require(self.persist, "PERSIST")
        left, right = self.range_arguments(args[0], args[1])
        k = int(args[2])
        if k < 1 or k > right - left + 1:
            raise CommandError(f"BAD K {k}")
        value, visits = persist.kth(left, right, k)
        self.emit(f"PERSIST KTH {left} {right} {k} value={value} visited={visits}")

    def persist_nodes(self, args):
        persist = self.require(self.persist, "PERSIST")
        sizes = f"position={len(persist.positions.total)} value={len(persist.counts.total)}"
        self.emit(f"PERSIST NODES versions={len(persist.versions)} {sizes}")

    def grid_build(self, args):
        rows, cols = int(args[0]), int(args[1])
        values = [int(text) for text in args[2:]]
        if len(values) != rows * cols:
            raise CommandError(f"BAD COUNT {len(values)} {rows * cols}")
        self.grid = Grid(rows, cols, values)
        self.emit(f"GRID BUILD rows={rows} cols={cols} total={sum(values)}")

    def grid_add(self, args):
        grid = self.require(self.grid, "GRID")
        row, col = self.cell_arguments(args[0], args[1])
        value = int(args[2])
        visits = grid.add(row, col, value)
        self.emit(f"GRID ADD {row} {col} {value} visited={visits}")

    def grid_sum(self, args):
        grid = self.require(self.grid, "GRID")
        top, left = self.cell_arguments(args[0], args[1])
        bottom, right = self.cell_arguments(args[2], args[3])
        if top > bottom or left > right:
            raise CommandError(f"BAD RECT {top} {left} {bottom} {right}")
        total, visits = grid.rectangle(top, left, bottom, right)
        self.emit(f"GRID SUM {top} {left} {bottom} {right} sum={total} visited={visits}")

    def grid_dump(self, args):
        grid = self.require(self.grid, "GRID")
        self.emit(f"GRID DUMP rows={grid.rows} cols={grid.cols}")
        for row in range(1, grid.rows + 1):
            self.emit("ROW", row, *grid.tree[row][1:])

    def execute(self, words):
        if words[0] in KINDS:
            command, args = words[0] + " " + words[1], words[2:]
        else:
            command, args = words[0], words[1:]
        handlers = {
            "ARRAY": self.show_array,
            "LOAD": self.load,
            "RESET": self.reset,
            "CHECK": self.check,
            "MO": self.mo,
            "SEG BUILD": self.seg_build,
            "SEG QUERY": self.seg_query,
            "SEG UPDATE": self.seg_update,
            "SEG DUMP": self.seg_dump,
            "LAZY BUILD": self.lazy_build,
            "LAZY ADD": self.lazy_add,
            "LAZY ASSIGN": self.lazy_assign,
            "LAZY QUERY": self.lazy_query,
            "LAZY DUMP": self.lazy_dump,
            "FEN BUILD": self.fen_build,
            "FEN ADD": self.fen_add,
            "FEN PREFIX": self.fen_prefix,
            "FEN RANGE": self.fen_range,
            "FEN LOWER": self.fen_lower,
            "FEN DUMP": self.fen_dump,
            "RFEN BUILD": self.rfen_build,
            "RFEN ADD": self.rfen_add,
            "RFEN SUM": self.rfen_sum,
            "RFEN DUMP": self.rfen_dump,
            "SPARSE BUILD": self.sparse_build,
            "SPARSE QUERY": self.sparse_query,
            "SPARSE DUMP": self.sparse_dump,
            "SQRT BUILD": self.sqrt_build,
            "SQRT ADD": self.sqrt_add,
            "SQRT SUM": self.sqrt_sum,
            "SQRT DUMP": self.sqrt_dump,
            "PERSIST BUILD": self.persist_build,
            "PERSIST SET": self.persist_set,
            "PERSIST QUERY": self.persist_query,
            "PERSIST KTH": self.persist_kth,
            "PERSIST NODES": self.persist_nodes,
            "GRID BUILD": self.grid_build,
            "GRID ADD": self.grid_add,
            "GRID SUM": self.grid_sum,
            "GRID DUMP": self.grid_dump,
        }
        try:
            handlers[command](args)
        except CommandError as error:
            self.emit("ERROR", error)


def main():
    sys.stdin.readline()
    values = [int(text) for text in sys.stdin.readline().split()]
    laboratory = Laboratory(values)
    count = int(sys.stdin.readline())
    for _ in range(count):
        laboratory.execute(sys.stdin.readline().split())
    sys.stdout.write("\n".join(laboratory.output) + "\n")


if __name__ == "__main__":
    main()
