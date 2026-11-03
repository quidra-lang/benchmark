import sys


MIN_DEGREE = 2
MAX_DEGREE = 5
INDEX_FREE_COMMANDS = ("CREATE", "LOAD", "TRACE")
DAMAGE_SENSITIVE_COMMANDS = (
    "INSERT", "BULKLOAD", "DELETE", "DELRANGE", "RANGE", "COUNT", "MIN", "MAX",
    "FLOOR", "CEIL", "RANK", "SELECT", "SEEK", "NEXT", "PREV", "HEIGHT", "COMPACT",
)


class CommandError(Exception):
    pass


def entry_text(entry):
    key, value = entry
    return f"{key}={value}"


def bound_text(bound, infinity):
    return infinity if bound is None else str(bound)


def read_degree(text):
    degree = int(text)
    if not MIN_DEGREE <= degree <= MAX_DEGREE:
        raise CommandError(f"BAD DEGREE {degree}")
    return degree


def read_range(arguments):
    low, high = int(arguments[0]), int(arguments[1])
    if low > high:
        raise CommandError(f"BAD RANGE {low} {high}")
    return low, high


def position(node, key):
    for j, entry in enumerate(node.entries):
        if key <= entry[0]:
            return j
    return len(node.entries)


def ceiling_entry(entries, key):
    for entry in entries:
        if entry[0] >= key:
            return entry
    return None


def floor_entry(entries, key):
    for entry in reversed(entries):
        if entry[0] <= key:
            return entry
    return None


def count_changes(before, after):
    writes = sum(1 for page, content in after.items() if before.get(page) != content)
    frees = sum(1 for page in before if page not in after)
    return writes, frees


class Node:
    def __init__(self, page, entries=None, children=None):
        self.page = page
        self.entries = [] if entries is None else entries
        self.children = [] if children is None else children

    def is_leaf(self):
        return not self.children

    def key(self, j):
        return self.entries[j][0]

    def keys(self):
        return [key for key, _ in self.entries]

    def notation(self):
        return "[" + " ".join(str(key) for key in self.keys()) + "]"

    def kids_text(self):
        if self.is_leaf():
            return "-"
        return ",".join(str(child.page) for child in self.children)

    def content(self):
        return " ".join(entry_text(entry) for entry in self.entries) + "|" + self.kids_text()

    def tree_notation(self):
        tokens = ["("]
        if self.is_leaf():
            tokens.extend(entry_text(entry) for entry in self.entries)
        else:
            tokens.append(self.children[0].tree_notation())
            for entry, child in zip(self.entries, self.children[1:]):
                tokens.append(entry_text(entry))
                tokens.append(child.tree_notation())
        tokens.append(")")
        return " ".join(tokens)

    def collect(self, result):
        if self.is_leaf():
            result.extend(self.entries)
            return
        for entry, child in zip(self.entries, self.children):
            child.collect(result)
            result.append(entry)
        self.children[-1].collect(result)

    def first_entry(self):
        node = self
        while not node.is_leaf():
            node = node.children[0]
        return node.entries[0]

    def last_entry(self):
        node = self
        while not node.is_leaf():
            node = node.children[-1]
        return node.entries[-1]

    def copy(self):
        return Node(self.page, list(self.entries), [child.copy() for child in self.children])


class BTree:
    def __init__(self, degree, root=None):
        self.degree = degree
        self.root = Node(0) if root is None else root
        self.splits = 0
        self.merges = 0
        self.borrows = 0
        self.steps = []
        self.cases = []

    def copy(self):
        tree = BTree(self.degree, self.root.copy())
        tree.splits = self.splits
        tree.merges = self.merges
        tree.borrows = self.borrows
        return tree

    def nodes(self):
        result = []
        stack = [self.root]
        while stack:
            node = stack.pop()
            result.append(node)
            stack.extend(reversed(node.children))
        return result

    def number_pages(self):
        for page, node in enumerate(self.nodes()):
            node.page = page

    def entries(self):
        result = []
        self.root.collect(result)
        return result

    def node_count(self):
        return len(self.nodes())

    def key_count(self):
        return sum(len(node.entries) for node in self.nodes())

    def height(self):
        height = 0
        node = self.root
        while not node.is_leaf():
            node = node.children[0]
            height += 1
        return height

    def snapshot(self):
        return {node.page: node.content() for node in self.nodes()}

    def is_full(self, node):
        return len(node.entries) == 2 * self.degree - 1

    def free_page(self):
        used = {node.page for node in self.nodes()}
        page = 0
        while page in used:
            page += 1
        return page

    def step(self, text):
        self.steps.append("STEP " + text)

    def record(self, case, details):
        self.cases.append(case)
        self.step(f"{case} {details}")

    def search(self, key):
        path = []
        node = self.root
        while True:
            path.append(node)
            j = position(node, key)
            if j < len(node.entries) and node.key(j) == key:
                return path, j
            if node.is_leaf():
                return path, None
            node = node.children[j]

    def split_child(self, node, j):
        t = self.degree
        child = node.children[j]
        sibling = Node(self.free_page())
        middle = child.entries[t - 1]
        self.step(
            f"split page={child.page} keys={child.notation()} "
            f"up={middle[0]} new={sibling.page}"
        )
        sibling.entries = child.entries[t:]
        child.entries = child.entries[:t - 1]
        if not child.is_leaf():
            sibling.children = child.children[t:]
            child.children = child.children[:t]
        node.entries.insert(j, middle)
        node.children.insert(j + 1, sibling)
        self.splits += 1

    def insert(self, key, value):
        if self.is_full(self.root):
            self.root = Node(self.free_page(), [], [self.root])
            self.step(f"grow page={self.root.page}")
            self.split_child(self.root, 0)
        node = self.root
        while not node.is_leaf():
            j = position(node, key)
            if self.is_full(node.children[j]):
                self.split_child(node, j)
                if key > node.key(j):
                    j += 1
            node = node.children[j]
        node.entries.insert(position(node, key), (key, value))
        self.step(f"place page={node.page} keys={node.notation()}")

    def put(self, key, value):
        self.steps = []
        path, index = self.search(key)
        if index is None:
            self.insert(key, value)
            return None
        node = path[-1]
        old = node.entries[index][1]
        node.entries[index] = (key, value)
        return old

    def merge_child(self, node, j, case):
        left = node.children[j]
        right = node.children.pop(j + 1)
        left.entries.append(node.entries.pop(j))
        left.entries.extend(right.entries)
        left.children.extend(right.children)
        self.merges += 1
        self.record(
            case, f"page={node.page} merge={left.page}+{right.page} keys={left.notation()}"
        )
        if node is self.root and not node.entries:
            self.root = left
            self.step(f"shrink page={left.page}")
        return left

    def fill_child(self, node, j):
        t = self.degree
        child = node.children[j]
        left = node.children[j - 1] if j > 0 else None
        right = node.children[j + 1] if j < len(node.entries) else None
        if left is not None and len(left.entries) >= t:
            child.entries.insert(0, node.entries[j - 1])
            node.entries[j - 1] = left.entries.pop()
            if not left.is_leaf():
                child.children.insert(0, left.children.pop())
            self.borrows += 1
            self.record(
                "3a-left",
                f"page={node.page} child={child.page} from={left.page} keys={child.notation()}",
            )
            return child
        if right is not None and len(right.entries) >= t:
            child.entries.append(node.entries[j])
            node.entries[j] = right.entries.pop(0)
            if not right.is_leaf():
                child.children.append(right.children.pop(0))
            self.borrows += 1
            self.record(
                "3a-right",
                f"page={node.page} child={child.page} from={right.page} keys={child.notation()}",
            )
            return child
        if left is not None:
            return self.merge_child(node, j - 1, "3b-left")
        return self.merge_child(node, j, "3b-right")

    def remove(self, node, key):
        t = self.degree
        j = position(node, key)
        if j < len(node.entries) and node.key(j) == key:
            if node.is_leaf():
                del node.entries[j]
                self.record("1", f"page={node.page} keys={node.notation()}")
                return
            left = node.children[j]
            right = node.children[j + 1]
            if len(left.entries) >= t:
                predecessor = left.last_entry()
                self.record("2a", f"page={node.page} pred={predecessor[0]}")
                self.remove(left, predecessor[0])
                node.entries[j] = predecessor
            elif len(right.entries) >= t:
                successor = right.first_entry()
                self.record("2b", f"page={node.page} succ={successor[0]}")
                self.remove(right, successor[0])
                node.entries[j] = successor
            else:
                merged = self.merge_child(node, j, "2c")
                self.remove(merged, key)
            return
        child = node.children[j]
        if len(child.entries) == t - 1:
            child = self.fill_child(node, j)
        self.remove(child, key)

    def delete(self, key):
        self.steps = []
        self.cases = []
        self.remove(self.root, key)

    def scan(self, node, low, high, result):
        visits = 1
        m = len(node.entries)
        for j in range(m + 1):
            left_open = j == 0 or node.key(j - 1) < high
            right_open = j == m or node.key(j) > low
            if not node.is_leaf() and left_open and right_open:
                visits += self.scan(node.children[j], low, high, result)
            if j < m and low <= node.key(j) <= high:
                result.append(node.entries[j])
        return visits

    def violation(self):
        t = self.degree
        reference_depth = None
        stack = [(self.root, "root", 0, None, None)]
        while stack:
            node, location, depth, low, high = stack.pop()
            keys = node.keys()
            m = len(keys)
            place = f"at={location} node={node.notation()}"
            if node is not self.root:
                smallest = t - 1
            elif node.is_leaf():
                smallest = 0
            else:
                smallest = 1
            if not smallest <= m <= 2 * t - 1:
                return f"COUNT {place} keys={m} allowed={smallest}..{2 * t - 1}"
            for j in range(m - 1):
                if keys[j] >= keys[j + 1]:
                    return f"ORDER {place} {keys[j]}>={keys[j + 1]}"
            for key in keys:
                if (low is not None and key <= low) or (high is not None and key >= high):
                    return (
                        f"RANGE {place} key={key} low={bound_text(low, '-inf')} "
                        f"high={bound_text(high, '+inf')}"
                    )
            if node.is_leaf():
                if reference_depth is None:
                    reference_depth = depth
                elif depth != reference_depth:
                    return f"DEPTH {place} depth={depth} expected={reference_depth}"
            for j in reversed(range(len(node.children))):
                child_low = keys[j - 1] if j > 0 else low
                child_high = keys[j] if j < m else high
                stack.append(
                    (node.children[j], f"{location}.{j}", depth + 1, child_low, child_high)
                )
        return None

    def damaged(self):
        return self.violation() is not None

    def status(self):
        return "DAMAGED" if self.damaged() else "OK"


def compact_root(entries, degree):
    level_entries = entries
    children = []
    while True:
        total = len(level_entries)
        groups = (total + 2 * degree) // (2 * degree)
        size, extra = divmod(total - (groups - 1), groups)
        nodes = []
        separators = []
        start = 0
        child_start = 0
        for number in range(groups):
            count = size + 1 if number < extra else size
            node = Node(0, level_entries[start:start + count])
            start += count
            if children:
                node.children = children[child_start:child_start + count + 1]
                child_start += count + 1
            nodes.append(node)
            if number < groups - 1:
                separators.append(level_entries[start])
                start += 1
        if groups == 1:
            return nodes[0]
        level_entries = separators
        children = nodes


class NotationParser:
    def __init__(self, tokens):
        self.tokens = tokens
        self.position = 0

    def current(self):
        if self.position < len(self.tokens):
            return self.tokens[self.position]
        return None

    def fail(self):
        raise CommandError(f"SYNTAX {self.position + 1}")

    def expect(self, token):
        if self.current() != token:
            self.fail()
        self.position += 1

    def at_entry(self):
        return self.current() not in (None, "(", ")")

    def entry(self):
        key, value = self.current().split("=")
        self.position += 1
        return int(key), value

    def node(self):
        self.expect("(")
        node = Node(0)
        if self.current() == "(":
            node.children.append(self.node())
            while self.at_entry():
                node.entries.append(self.entry())
                node.children.append(self.node())
        else:
            while self.at_entry():
                node.entries.append(self.entry())
        self.expect(")")
        return node

    def tree(self):
        root = self.node()
        if self.position < len(self.tokens):
            self.fail()
        return root


class IndexConsole:
    def __init__(self):
        self.tree = None
        self.saved = None
        self.tracing = False
        self.cursor = "UNSET"
        self.cursor_key = 0
        self.output = []

    def emit(self, *parts):
        self.output.append(" ".join(str(part) for part in parts))

    def emit_steps(self):
        if self.tracing:
            self.output.extend(self.tree.steps)

    def summary(self):
        return (
            f"nodes={self.tree.node_count()}", f"keys={self.tree.key_count()}",
            self.tree.status(),
        )

    def move_cursor(self, entry, end_state):
        if entry is None:
            self.cursor = end_state
            return end_state
        self.cursor = "KEY"
        self.cursor_key = entry[0]
        return entry_text(entry)

    def create(self, arguments):
        degree = read_degree(arguments[0])
        self.tree = BTree(degree)
        self.cursor = "UNSET"
        self.emit(f"CREATE t={degree}")

    def load(self, arguments):
        degree = read_degree(arguments[0])
        root = NotationParser(arguments[1:]).tree()
        self.tree = BTree(degree, root)
        self.tree.number_pages()
        self.cursor = "UNSET"
        self.emit("LOAD", f"t={degree}", *self.summary())

    def insert(self, arguments):
        key, value = int(arguments[0]), arguments[1]
        before = self.tree.snapshot()
        splits = self.tree.splits
        old = self.tree.put(key, value)
        writes, _ = count_changes(before, self.tree.snapshot())
        if old is not None:
            self.emit("INSERT", key, "UPDATED", f"old={old}", f"writes={writes}")
            return
        self.emit_steps()
        self.emit(
            "INSERT", key, "NEW", f"splits={self.tree.splits - splits}",
            f"height={self.tree.height()}", f"writes={writes}",
        )

    def bulkload(self, arguments):
        before = self.tree.snapshot()
        splits = self.tree.splits
        added = 0
        updated = 0
        for j in range(0, len(arguments), 2):
            if self.tree.put(int(arguments[j]), arguments[j + 1]) is None:
                added += 1
            else:
                updated += 1
        writes, _ = count_changes(before, self.tree.snapshot())
        self.emit(
            "BULKLOAD", f"pairs={len(arguments) // 2}", f"new={added}",
            f"updated={updated}", f"splits={self.tree.splits - splits}",
            f"height={self.tree.height()}", f"writes={writes}",
        )

    def delete(self, arguments):
        key = int(arguments[0])
        path, index = self.tree.search(key)
        if index is None:
            self.emit("DELETE", key, "NOT FOUND")
            return
        value = path[-1].entries[index][1]
        before = self.tree.snapshot()
        self.tree.delete(key)
        self.emit_steps()
        writes, frees = count_changes(before, self.tree.snapshot())
        self.emit(
            "DELETE", key, "REMOVED", f"value={value}",
            "cases=" + ",".join(self.tree.cases), f"height={self.tree.height()}",
            f"writes={writes}", f"frees={frees}",
        )

    def delete_range(self, arguments):
        low, high = read_range(arguments)
        keys = [key for key, _ in self.tree.entries() if low <= key <= high]
        before = self.tree.snapshot()
        merges = self.tree.merges
        borrows = self.tree.borrows
        for key in keys:
            self.tree.delete(key)
        writes, frees = count_changes(before, self.tree.snapshot())
        self.emit(
            "DELRANGE", low, high, f"removed={len(keys)}",
            f"merges={self.tree.merges - merges}", f"borrows={self.tree.borrows - borrows}",
            f"height={self.tree.height()}", f"writes={writes}", f"frees={frees}",
        )

    def get(self, arguments):
        key = int(arguments[0])
        path, index = self.tree.search(key)
        route = " -> ".join(node.notation() for node in path)
        if index is None:
            self.emit("GET", key, "NOT FOUND", f"path={route}")
        else:
            value = path[-1].entries[index][1]
            self.emit("GET", key, "FOUND", f"value={value}", f"path={route}")

    def scan_range(self, arguments, show_entries):
        low, high = read_range(arguments)
        result = []
        visits = self.tree.scan(self.tree.root, low, high, result)
        parts = [low, high, f"count={len(result)}", f"visited={visits}"]
        if show_entries:
            self.emit("RANGE", *parts, *(entry_text(entry) for entry in result))
        else:
            self.emit("COUNT", *parts)

    def range_entries(self, arguments):
        self.scan_range(arguments, True)

    def count_entries(self, arguments):
        self.scan_range(arguments, False)

    def minimum(self, arguments):
        entries = self.tree.entries()
        self.emit("MIN", entry_text(entries[0]) if entries else "EMPTY")

    def maximum(self, arguments):
        entries = self.tree.entries()
        self.emit("MAX", entry_text(entries[-1]) if entries else "EMPTY")

    def floor(self, arguments):
        key = int(arguments[0])
        entry = floor_entry(self.tree.entries(), key)
        self.emit("FLOOR", key, "NONE" if entry is None else entry_text(entry))

    def ceiling(self, arguments):
        key = int(arguments[0])
        entry = ceiling_entry(self.tree.entries(), key)
        self.emit("CEIL", key, "NONE" if entry is None else entry_text(entry))

    def rank(self, arguments):
        key = int(arguments[0])
        smaller = sum(1 for entry_key, _ in self.tree.entries() if entry_key < key)
        self.emit("RANK", key, smaller)

    def select(self, arguments):
        index = int(arguments[0])
        entries = self.tree.entries()
        if not 1 <= index <= len(entries):
            raise CommandError(f"BAD POSITION {index}")
        self.emit("SELECT", index, entry_text(entries[index - 1]))

    def seek(self, arguments):
        key = int(arguments[0])
        entry = ceiling_entry(self.tree.entries(), key)
        self.emit("SEEK", key, self.move_cursor(entry, "END"))

    def next_entry(self, arguments):
        if self.cursor == "UNSET":
            raise CommandError("NO CURSOR")
        entries = self.tree.entries()
        if self.cursor == "KEY":
            entry = ceiling_entry(entries, self.cursor_key + 1)
        elif self.cursor == "BEGIN":
            entry = entries[0] if entries else None
        else:
            entry = None
        self.emit("NEXT", self.move_cursor(entry, "END"))

    def previous_entry(self, arguments):
        if self.cursor == "UNSET":
            raise CommandError("NO CURSOR")
        entries = self.tree.entries()
        if self.cursor == "KEY":
            entry = floor_entry(entries, self.cursor_key - 1)
        elif self.cursor == "END":
            entry = entries[-1] if entries else None
        else:
            entry = None
        self.emit("PREV", self.move_cursor(entry, "BEGIN"))

    def print_levels(self, arguments):
        level = [self.tree.root]
        depth = 0
        while level:
            self.emit("LEVEL", depth, *(node.notation() for node in level))
            level = [child for node in level for child in node.children]
            depth += 1

    def pages(self, arguments):
        for node in sorted(self.tree.nodes(), key=lambda node: node.page):
            self.emit("PAGE", node.page, node.notation(), f"kids={node.kids_text()}")

    def dump(self, arguments):
        self.emit("DUMP", self.tree.degree, self.tree.root.tree_notation())

    def height(self, arguments):
        self.emit("HEIGHT", self.tree.height())

    def stats(self, arguments):
        tree = self.tree
        nodes = tree.nodes()
        leaves = sum(1 for node in nodes if node.is_leaf())
        keys = tree.key_count()
        fill = 100 * keys // ((2 * tree.degree - 1) * len(nodes))
        self.emit(
            "STATS", f"t={tree.degree}", f"nodes={len(nodes)}", f"leaves={leaves}",
            f"keys={keys}", f"fill={fill}%", f"splits={tree.splits}",
            f"merges={tree.merges}", f"borrows={tree.borrows}",
        )

    def verify(self, arguments):
        violation = self.tree.violation()
        if violation is None:
            self.emit("VERIFY OK")
        else:
            self.emit("VERIFY FAIL", violation)

    def rebuild(self, arguments):
        entries = self.tree.entries()
        tree = BTree(self.tree.degree)
        for key, value in entries:
            tree.put(key, value)
        self.tree = tree
        self.emit(
            "REBUILD", f"entries={len(entries)}", f"keys={tree.key_count()}",
            f"nodes={tree.node_count()}", f"splits={tree.splits}", f"height={tree.height()}",
        )

    def compact(self, arguments):
        before = self.tree.node_count()
        degree = self.tree.degree
        tree = BTree(degree, compact_root(self.tree.entries(), degree))
        tree.number_pages()
        self.tree = tree
        self.emit("COMPACT", f"nodes={before}->{tree.node_count()}", f"height={tree.height()}")

    def save(self, arguments):
        self.saved = self.tree.copy()
        self.emit("SAVE", *self.summary())

    def restore(self, arguments):
        if self.saved is None:
            raise CommandError("NO SAVE")
        self.tree = self.saved.copy()
        self.emit("RESTORE", *self.summary())

    def set_trace(self, arguments):
        self.tracing = arguments[0] == "ON"
        self.emit("TRACE", arguments[0])

    def execute(self, line):
        command, *arguments = line.split()
        handlers = {
            "CREATE": self.create,
            "LOAD": self.load,
            "INSERT": self.insert,
            "BULKLOAD": self.bulkload,
            "DELETE": self.delete,
            "DELRANGE": self.delete_range,
            "GET": self.get,
            "RANGE": self.range_entries,
            "COUNT": self.count_entries,
            "MIN": self.minimum,
            "MAX": self.maximum,
            "FLOOR": self.floor,
            "CEIL": self.ceiling,
            "RANK": self.rank,
            "SELECT": self.select,
            "SEEK": self.seek,
            "NEXT": self.next_entry,
            "PREV": self.previous_entry,
            "PRINT": self.print_levels,
            "PAGES": self.pages,
            "DUMP": self.dump,
            "HEIGHT": self.height,
            "STATS": self.stats,
            "VERIFY": self.verify,
            "REBUILD": self.rebuild,
            "COMPACT": self.compact,
            "SAVE": self.save,
            "RESTORE": self.restore,
            "TRACE": self.set_trace,
        }
        try:
            if command not in INDEX_FREE_COMMANDS:
                if self.tree is None:
                    raise CommandError("NO INDEX")
                if command in DAMAGE_SENSITIVE_COMMANDS and self.tree.damaged():
                    raise CommandError("DAMAGED")
            handlers[command](arguments)
        except CommandError as error:
            self.emit("ERROR", error)


def main():
    console = IndexConsole()
    count = int(sys.stdin.readline())
    for _ in range(count):
        console.execute(sys.stdin.readline().rstrip("\n"))
    sys.stdout.write("\n".join(console.output) + "\n")


if __name__ == "__main__":
    main()
