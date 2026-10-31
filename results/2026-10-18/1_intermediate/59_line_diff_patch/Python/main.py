import re
import sys


DATA_COMMANDS = ("FILE", "PATCH", "EDIT")
FORMATS_WITH_ARGUMENT = ("IFDEF", "UNIFIED", "CONTEXT", "SIDE")
OFFSETS = (0, 1, -1, 2, -2, 3, -3)
GRAPH_WIDTH = 20
NUMBER_PAIR = re.compile(r"([0-9]{1,4})(?:,([0-9]{1,4}))?")
MARKER_PREFIXES = {"<<<<<<<": "start", "|||||||": "base", ">>>>>>>": "end"}
SEPARATOR = "======="


class CommandError(Exception):
    pass


def range_r(start, count):
    if count >= 2:
        return f"{start + 1},{start + count}"
    if count == 1:
        return str(start + 1)
    return str(start)


def range_u(start, count):
    if count >= 2:
        return f"{start + 1},{count}"
    if count == 1:
        return str(start + 1)
    return f"{start},0"


def range_m(start, count):
    return f"{start + 1},{count}"


def comparison_key(line, options):
    if "ICASE" in options:
        line = line.lower()
    if "IWHITE" in options:
        line = line.replace(" ", "")
    if "ISPACE" in options:
        line = re.sub(" {2,}", " ", line)
    return line


def matched_pairs(first, second):
    rows, columns = len(first), len(second)
    table = [[0] * (columns + 1) for _ in range(rows + 1)]
    for i in range(1, rows + 1):
        for j in range(1, columns + 1):
            if first[i - 1] == second[j - 1]:
                table[i][j] = table[i - 1][j - 1] + 1
            else:
                table[i][j] = max(table[i - 1][j], table[i][j - 1])
    pairs = [(rows + 1, columns + 1)]
    i, j = rows, columns
    while i >= 1 and j >= 1:
        if first[i - 1] == second[j - 1]:
            pairs.append((i, j))
            i -= 1
            j -= 1
        elif table[i - 1][j] >= table[i][j - 1]:
            i -= 1
        else:
            j -= 1
    pairs.append((0, 0))
    pairs.reverse()
    return pairs


class ChangeBlock:
    def __init__(self, p, q, x, y):
        self.p = p
        self.q = q
        self.x = x
        self.y = y

    def letter(self):
        if self.x >= 1 and self.y >= 1:
            return "c"
        return "d" if self.y == 0 else "a"


def change_blocks(first, second):
    pairs = matched_pairs(first, second)
    blocks = []
    for (i, j), (next_i, next_j) in zip(pairs, pairs[1:]):
        if next_i - i > 1 or next_j - j > 1:
            blocks.append(ChangeBlock(i, j, next_i - i - 1, next_j - j - 1))
    return blocks


def walk(blocks, old_start, new_start, old_end):
    steps = []
    old_index, new_index = old_start, new_start
    for block in blocks:
        while old_index < block.p:
            steps.append((old_index, new_index, None))
            old_index += 1
            new_index += 1
        steps.append((old_index, new_index, block))
        old_index, new_index = block.p + block.x, block.q + block.y
    while old_index < old_end:
        steps.append((old_index, new_index, None))
        old_index += 1
        new_index += 1
    return steps


def side_row(left, symbol, right, width):
    return (left[:width].ljust(width) + " " + symbol + " " + right[:width]).rstrip(" ")


def stat_graph(inserted, deleted):
    total = inserted + deleted
    if total <= GRAPH_WIDTH:
        plus, minus = inserted, deleted
    else:
        plus = GRAPH_WIDTH * inserted // total
        minus = GRAPH_WIDTH * deleted // total
        if inserted >= 1 and plus == 0:
            plus = 1
        if deleted >= 1 and minus == 0:
            minus = 1
    return "+" * plus + "-" * minus


class Hunk:
    def __init__(self, blocks, context, old_total):
        first, last = blocks[0], blocks[-1]
        before = min(context, first.p)
        after = min(context, old_total - last.p - last.x)
        self.blocks = blocks
        self.old_start = first.p - before
        self.old_count = last.p + last.x + after - self.old_start
        self.new_start = first.q - before
        self.new_count = last.q + last.y + after - self.new_start

    def steps(self):
        return walk(self.blocks, self.old_start, self.new_start, self.old_start + self.old_count)


class LineDiff:
    def __init__(self, old, new, options=()):
        self.old = old
        self.new = new
        self.blocks = change_blocks(
            [comparison_key(line, options) for line in old],
            [comparison_key(line, options) for line in new],
        )

    def deleted(self, block):
        return self.old[block.p:block.p + block.x]

    def inserted(self, block):
        return self.new[block.q:block.q + block.y]

    def hunks(self, context):
        groups = []
        for block in self.blocks:
            if groups:
                previous = groups[-1][-1]
                if block.p - (previous.p + previous.x) <= 2 * context:
                    groups[-1].append(block)
                    continue
            groups.append([block])
        return [Hunk(group, context, len(self.old)) for group in groups]

    def normal(self):
        lines = []
        for block in self.blocks:
            letter = block.letter()
            lines.append(range_r(block.p, block.x) + letter + range_r(block.q, block.y))
            lines.extend("< " + line for line in self.deleted(block))
            if letter == "c":
                lines.append("---")
            lines.extend("> " + line for line in self.inserted(block))
        return lines

    def ed(self):
        lines = []
        for block in reversed(self.blocks):
            letter = block.letter()
            lines.append(range_r(block.p, block.x) + letter)
            if letter != "d":
                lines.extend(self.inserted(block))
                lines.append(".")
        return lines

    def rcs(self):
        lines = []
        for block in self.blocks:
            if block.x >= 1:
                lines.append(f"d{block.p + 1} {block.x}")
            if block.y >= 1:
                lines.append(f"a{block.p + block.x} {block.y}")
                lines.extend(self.inserted(block))
        return lines

    def ifdef(self, macro):
        lines = []
        for old_index, _, block in walk(self.blocks, 0, 0, len(self.old)):
            if block is None:
                lines.append(self.old[old_index])
            elif block.x >= 1 and block.y >= 1:
                lines.append("#ifndef " + macro)
                lines.extend(self.deleted(block))
                lines.append(f"#else /* {macro} */")
                lines.extend(self.inserted(block))
                lines.append(f"#endif /* {macro} */")
            elif block.y == 0:
                lines.append("#ifndef " + macro)
                lines.extend(self.deleted(block))
                lines.append(f"#endif /* ! {macro} */")
            else:
                lines.append("#ifdef " + macro)
                lines.extend(self.inserted(block))
                lines.append(f"#endif /* {macro} */")
        return lines

    def unified(self, context, old_name, new_name):
        lines = ["--- " + old_name, "+++ " + new_name]
        for hunk in self.hunks(context):
            old_range = range_u(hunk.old_start, hunk.old_count)
            new_range = range_u(hunk.new_start, hunk.new_count)
            lines.append(f"@@ -{old_range} +{new_range} @@")
            for old_index, _, block in hunk.steps():
                if block is None:
                    lines.append(" " + self.old[old_index])
                else:
                    lines.extend("-" + line for line in self.deleted(block))
                    lines.extend("+" + line for line in self.inserted(block))
        return lines

    def context(self, context, old_name, new_name):
        lines = ["*** " + old_name, "--- " + new_name]
        for hunk in self.hunks(context):
            lines.append("*" * 15)
            lines.append(f"*** {range_r(hunk.old_start, hunk.old_count)} ****")
            if any(block.x >= 1 for block in hunk.blocks):
                for old_index, _, block in hunk.steps():
                    if block is None:
                        lines.append("  " + self.old[old_index])
                    else:
                        marker = "! " if block.y >= 1 else "- "
                        lines.extend(marker + line for line in self.deleted(block))
            lines.append(f"--- {range_r(hunk.new_start, hunk.new_count)} ----")
            if any(block.y >= 1 for block in hunk.blocks):
                for _, new_index, block in hunk.steps():
                    if block is None:
                        lines.append("  " + self.new[new_index])
                    else:
                        marker = "! " if block.x >= 1 else "+ "
                        lines.extend(marker + line for line in self.inserted(block))
        return lines

    def side_by_side(self, width):
        lines = []
        for old_index, new_index, block in walk(self.blocks, 0, 0, len(self.old)):
            if block is None:
                lines.append(side_row(self.old[old_index], " ", self.new[new_index], width))
                continue
            for row in range(max(block.x, block.y)):
                if row < block.x and row < block.y:
                    left, symbol, right = self.old[block.p + row], "|", self.new[block.q + row]
                elif row < block.x:
                    left, symbol, right = self.old[block.p + row], "<", ""
                else:
                    left, symbol, right = "", ">", self.new[block.q + row]
                lines.append(side_row(left, symbol, right, width))
        return lines


class TokenTotals:
    def __init__(self):
        self.deleted = 0
        self.inserted = 0
        self.common = 0


def split_tokens(line, by_word):
    return line.split() if by_word else list(line)


def deletion(tokens, separator):
    return "[-" + separator.join(tokens) + "-]"


def insertion(tokens, separator):
    return "{+" + separator.join(tokens) + "+}"


def compare_tokens(old_tokens, new_tokens, separator, totals):
    parts = []
    for old_index, _, block in walk(change_blocks(old_tokens, new_tokens), 0, 0, len(old_tokens)):
        if block is None:
            parts.append(old_tokens[old_index])
            totals.common += 1
            continue
        if block.x >= 1:
            parts.append(deletion(old_tokens[block.p:block.p + block.x], separator))
        if block.y >= 1:
            parts.append(insertion(new_tokens[block.q:block.q + block.y], separator))
        totals.deleted += block.x
        totals.inserted += block.y
    return separator.join(parts)


class PatchHunk:
    def __init__(self, line_number, old_start, old_count, new_start, new_count):
        self.line_number = line_number
        self.old_start = old_start
        self.old_count = old_count
        self.new_start = new_start
        self.new_count = new_count
        self.body = []

    def sequences(self, reverse):
        old_kinds = (" ", "+") if reverse else (" ", "-")
        new_kinds = (" ", "-") if reverse else (" ", "+")
        old = [text for kind, text in self.body if kind in old_kinds]
        new = [text for kind, text in self.body if kind in new_kinds]
        return old, new

    def start(self, reverse):
        return self.new_start if reverse else self.old_start

    def leading_context(self):
        count = 0
        while count < len(self.body) and self.body[count][0] == " ":
            count += 1
        return count

    def trailing_context(self):
        count = 0
        while count < len(self.body) and self.body[len(self.body) - 1 - count][0] == " ":
            count += 1
        return count


class HunkMatch:
    def __init__(self, fuzz, delta, position, lines):
        self.fuzz = fuzz
        self.delta = delta
        self.position = position
        self.lines = lines

    def report(self, number):
        text = f"Hunk #{number} succeeded at {self.position + 1}"
        if self.fuzz >= 1:
            text += f" with fuzz {self.fuzz}"
        if self.delta in (1, -1):
            text += f" (offset {self.delta} line)"
        elif self.delta != 0:
            text += f" (offset {self.delta} lines)"
        return text


def parse_range(text, sign):
    if not text.startswith(sign):
        return None
    match = NUMBER_PAIR.fullmatch(text[1:])
    if match is None:
        return None
    start = int(match.group(1))
    count = 1 if match.group(2) is None else int(match.group(2))
    if start == 0 and count != 0:
        return None
    return start, count


def parse_hunk_header(line, line_number):
    parts = line.split(" ")
    old_range = new_range = None
    if len(parts) == 4 and parts[0] == "@@" and parts[3] == "@@":
        old_range = parse_range(parts[1], "-")
        new_range = parse_range(parts[2], "+")
    if old_range is None or new_range is None:
        raise CommandError(f"PATCH ERROR line {line_number}: bad hunk header")
    return PatchHunk(line_number, old_range[0], old_range[1], new_range[0], new_range[1])


def parse_patch(patch_lines):
    index = 0
    while index < len(patch_lines) and not patch_lines[index].startswith("@@"):
        index += 1
    if index == len(patch_lines):
        raise CommandError("PATCH ERROR no hunks")
    hunks = []
    while index < len(patch_lines):
        hunk = parse_hunk_header(patch_lines[index], index + 1)
        index += 1
        old_seen = new_seen = 0
        while old_seen < hunk.old_count or new_seen < hunk.new_count:
            if index == len(patch_lines):
                raise CommandError(f"PATCH ERROR line {hunk.line_number}: truncated hunk")
            line = patch_lines[index]
            kind = line[0]
            in_old = kind in (" ", "-")
            in_new = kind in (" ", "+")
            if (
                len(line) < 2
                or not (in_old or in_new)
                or (in_old and old_seen == hunk.old_count)
                or (in_new and new_seen == hunk.new_count)
            ):
                raise CommandError(f"PATCH ERROR line {index + 1}: bad hunk line")
            hunk.body.append((kind, line[1:]))
            if in_old:
                old_seen += 1
            if in_new:
                new_seen += 1
            index += 1
        if all(kind == " " for kind, _ in hunk.body):
            raise CommandError(f"PATCH ERROR line {hunk.line_number}: no changes")
        hunks.append(hunk)
    return hunks


def search_hunk(hunk, lines, adjustment, reverse, max_fuzz):
    old, new = hunk.sequences(reverse)
    start = hunk.start(reverse)
    expected = start - 1 + adjustment if old else start + adjustment
    leading, trailing = hunk.leading_context(), hunk.trailing_context()
    for fuzz in range(max_fuzz + 1):
        head = min(fuzz, leading)
        tail = min(fuzz, trailing)
        old_part = old[head:len(old) - tail]
        new_part = new[head:len(new) - tail]
        for delta in OFFSETS:
            position = expected + head + delta
            end = position + len(old_part)
            if position < 0 or end > len(lines):
                continue
            if lines[position:end] == old_part:
                return HunkMatch(fuzz, delta, position, lines[:position] + new_part + lines[end:])
    return None


def parse_edit_command(line):
    instruction, address = line[-1], line[:-1]
    match = NUMBER_PAIR.fullmatch(address)
    if instruction not in ("a", "c", "d") or match is None:
        return None
    if instruction == "a" and match.group(2) is not None:
        return None
    first = int(match.group(1))
    last = first if match.group(2) is None else int(match.group(2))
    return instruction, first, last


def run_edit_script(lines, script):
    lines = list(lines)
    executed = 0
    index = 0
    while index < len(script):
        line_number = index + 1
        command = parse_edit_command(script[index])
        if command is None:
            raise CommandError(f"EDIT ERROR line {line_number}: bad command")
        instruction, first, last = command
        if instruction == "a":
            valid = first <= len(lines)
        else:
            valid = 1 <= first <= last <= len(lines)
        if not valid:
            raise CommandError(f"EDIT ERROR line {line_number}: bad range")
        index += 1
        text = []
        if instruction in ("a", "c"):
            end = index
            while end < len(script) and script[end] != ".":
                end += 1
            if end == len(script):
                raise CommandError(f"EDIT ERROR line {line_number}: missing terminator")
            text = script[index:end]
            index = end + 1
        if instruction == "a":
            lines[first:first] = text
        elif instruction == "c":
            lines[first - 1:last] = text
        else:
            del lines[first - 1:last]
        executed += 1
    return lines, executed


class Chunk:
    def __init__(self, kind, base_start, ours_start, theirs_start, base, ours, theirs):
        self.kind = kind
        self.base_start = base_start
        self.ours_start = ours_start
        self.theirs_start = theirs_start
        self.base = base
        self.ours = ours
        self.theirs = theirs

    def location(self):
        return (
            f"base {range_m(self.base_start, len(self.base))}"
            f" a {range_m(self.ours_start, len(self.ours))}"
            f" b {range_m(self.theirs_start, len(self.theirs))}"
        )


def chunk_kind(base, ours, theirs):
    if ours == base:
        return "b"
    if theirs == base:
        return "a"
    if ours == theirs:
        return "both"
    return "conflict"


def match_table(first, second):
    matches = [0] * (len(first) + 2)
    for i, j in matched_pairs(first, second)[1:-1]:
        matches[i] = j
    return matches


def three_way_chunks(base, ours, theirs):
    ours_match = match_table(base, ours)
    theirs_match = match_table(base, theirs)
    chunks = []
    x = y = z = 0
    while x < len(base) or y < len(ours) or z < len(theirs):
        if x < len(base) and ours_match[x + 1] == y + 1 and theirs_match[x + 1] == z + 1:
            chunks.append(Chunk("stable", x, y, z, base[x:x + 1], ours[y:y + 1], theirs[z:z + 1]))
            x += 1
            y += 1
            z += 1
            continue
        anchor = x + 1
        while anchor <= len(base) and (ours_match[anchor] == 0 or theirs_match[anchor] == 0):
            anchor += 1
        if anchor <= len(base):
            next_x, next_y, next_z = anchor - 1, ours_match[anchor] - 1, theirs_match[anchor] - 1
        else:
            next_x, next_y, next_z = len(base), len(ours), len(theirs)
        base_part, ours_part, theirs_part = base[x:next_x], ours[y:next_y], theirs[z:next_z]
        kind = chunk_kind(base_part, ours_part, theirs_part)
        chunks.append(Chunk(kind, x, y, z, base_part, ours_part, theirs_part))
        x, y, z = next_x, next_y, next_z
    return chunks


def kind_counts(chunks):
    counts = {"a": 0, "b": 0, "both": 0, "conflict": 0}
    for chunk in chunks:
        if chunk.kind != "stable":
            counts[chunk.kind] += 1
    return f"a={counts['a']} b={counts['b']} both={counts['both']} conflicts={counts['conflict']}"


def common_prefix_length(first, second):
    length = 0
    while length < len(first) and length < len(second) and first[length] == second[length]:
        length += 1
    return length


def common_suffix_length(first, second, limit):
    length = 0
    while (
        length < limit
        and first[len(first) - 1 - length] == second[len(second) - 1 - length]
    ):
        length += 1
    return length


def conflict_lines(chunk, mode, base_name, ours_name, theirs_name):
    if mode == "OURS":
        return chunk.ours
    if mode == "THEIRS":
        return chunk.theirs
    if mode == "DIFF3":
        return (
            ["<<<<<<< " + ours_name] + chunk.ours + ["||||||| " + base_name] + chunk.base
            + [SEPARATOR] + chunk.theirs + [">>>>>>> " + theirs_name]
        )
    ours, theirs = chunk.ours, chunk.theirs
    head = common_prefix_length(ours, theirs)
    tail = common_suffix_length(ours, theirs, min(len(ours), len(theirs)) - head)
    ours_middle = ours[head:len(ours) - tail]
    theirs_middle = theirs[head:len(theirs) - tail]
    if mode == "UNION":
        middle = ours_middle + theirs_middle
    else:
        middle = (
            ["<<<<<<< " + ours_name] + ours_middle + [SEPARATOR]
            + theirs_middle + [">>>>>>> " + theirs_name]
        )
    return ours[:head] + middle + ours[len(ours) - tail:]


def marker_kind(line):
    if line == SEPARATOR:
        return "separator"
    prefix = line[:7]
    if prefix in MARKER_PREFIXES and (len(line) == 7 or line[7] == " "):
        return MARKER_PREFIXES[prefix]
    return None


def next_marker(lines, index):
    index += 1
    while index < len(lines) and marker_kind(lines[index]) is None:
        index += 1
    return index


class ConflictRegion:
    def __init__(self, start, end, ours, base, theirs):
        self.start = start
        self.end = end
        self.ours = ours
        self.base = base
        self.theirs = theirs

    def part(self, side):
        if side == "OURS":
            return self.ours
        if side == "THEIRS":
            return self.theirs
        if side == "BASE":
            return self.base
        return self.ours + self.theirs


def region_at(lines, start):
    if marker_kind(lines[start]) != "start":
        return None
    middle = next_marker(lines, start)
    base_marker = None
    if middle < len(lines) and marker_kind(lines[middle]) == "base":
        base_marker = middle
        middle = next_marker(lines, middle)
    if middle == len(lines) or marker_kind(lines[middle]) != "separator":
        return None
    end = next_marker(lines, middle)
    if end == len(lines) or marker_kind(lines[end]) != "end":
        return None
    if base_marker is None:
        ours, base = lines[start + 1:middle], None
    else:
        ours, base = lines[start + 1:base_marker], lines[base_marker + 1:middle]
    return ConflictRegion(start + 1, end + 1, ours, base, lines[middle + 1:end])


def conflict_regions(lines):
    regions = []
    index = 0
    while index < len(lines):
        region = region_at(lines, index)
        if region is None:
            index += 1
        else:
            regions.append(region)
            index = region.end
    return regions


class Workspace:
    def __init__(self):
        self.files = {}
        self.history = {}
        self.output = []
        self.handlers = {
            "FILE": self.load_file,
            "COPY": self.copy,
            "PRINT": self.print_file,
            "FILES": self.list_files,
            "DIFF": self.diff,
            "WORDDIFF": self.word_diff,
            "CHARDIFF": self.char_diff,
            "STAT": self.stat,
            "PATCH": self.patch,
            "EDIT": self.edit,
            "DIFF3": self.diff3,
            "MERGE": self.merge,
            "CONFLICTS": self.conflicts,
            "RESOLVE": self.resolve,
            "UNDO": self.undo,
        }

    def emit(self, line):
        self.output.append(line)

    def require(self, *names):
        for name in names:
            if name not in self.files:
                raise CommandError("ERROR no such file " + name)

    def save(self, name, lines):
        self.history.setdefault(name, []).append(self.files.get(name))
        self.files[name] = list(lines)

    def load_file(self, arguments, data):
        name = arguments[0]
        self.save(name, data)
        self.emit(f"FILE {name} lines={len(data)}")

    def copy(self, arguments):
        source, target = arguments
        self.require(source)
        lines = self.files[source]
        self.save(target, lines)
        self.emit(f"COPY {source} {target} lines={len(lines)}")

    def print_file(self, arguments):
        name = arguments[0]
        self.require(name)
        lines = self.files[name]
        self.emit(f"PRINT {name} lines={len(lines)}")
        for number, line in enumerate(lines, 1):
            self.emit(f"{number:>3}| {line}")

    def list_files(self, arguments):
        self.emit(f"FILES count={len(self.files)}")
        for name in sorted(self.files):
            self.emit(f"{name} lines={len(self.files[name])} undo={len(self.history[name])}")

    def undo(self, arguments):
        name = arguments[0]
        states = self.history.get(name, [])
        if not states:
            raise CommandError("ERROR nothing to undo " + name)
        state = states.pop()
        if state is None:
            del self.files[name]
            self.emit(f"UNDO {name} removed")
        else:
            self.files[name] = state
            self.emit(f"UNDO {name} lines={len(state)}")

    def diff(self, arguments):
        old_name, new_name, form = arguments[:3]
        self.require(old_name, new_name)
        parameter = None
        options = arguments[3:]
        if form in FORMATS_WITH_ARGUMENT:
            parameter = arguments[3]
            options = arguments[4:]
        diff = LineDiff(self.files[old_name], self.files[new_name], options)
        if not diff.blocks:
            self.emit(f"Files {old_name} and {new_name} are identical")
        elif form == "BRIEF":
            self.emit(f"Files {old_name} and {new_name} differ")
        elif form == "NORMAL":
            self.output.extend(diff.normal())
        elif form == "ED":
            self.output.extend(diff.ed())
        elif form == "RCS":
            self.output.extend(diff.rcs())
        elif form == "IFDEF":
            self.output.extend(diff.ifdef(parameter))
        elif form == "UNIFIED":
            self.output.extend(diff.unified(int(parameter), old_name, new_name))
        elif form == "CONTEXT":
            self.output.extend(diff.context(int(parameter), old_name, new_name))
        else:
            self.output.extend(diff.side_by_side(int(parameter)))

    def token_diff(self, arguments, by_word):
        old_name, new_name = arguments
        self.require(old_name, new_name)
        old, new = self.files[old_name], self.files[new_name]
        diff = LineDiff(old, new)
        if not diff.blocks:
            self.emit(f"Files {old_name} and {new_name} are identical")
            return
        separator = " " if by_word else ""
        totals = TokenTotals()
        for block in diff.blocks:
            for row in range(max(block.x, block.y)):
                old_number, new_number = block.p + row + 1, block.q + row + 1
                if row < block.x and row < block.y:
                    old_tokens = split_tokens(old[old_number - 1], by_word)
                    new_tokens = split_tokens(new[new_number - 1], by_word)
                    text = compare_tokens(old_tokens, new_tokens, separator, totals)
                    self.emit(f"a{old_number} b{new_number}: {text}")
                elif row < block.x:
                    old_tokens = split_tokens(old[old_number - 1], by_word)
                    totals.deleted += len(old_tokens)
                    self.emit(f"a{old_number}: {deletion(old_tokens, separator)}")
                else:
                    new_tokens = split_tokens(new[new_number - 1], by_word)
                    totals.inserted += len(new_tokens)
                    self.emit(f"b{new_number}: {insertion(new_tokens, separator)}")
        label = "WORDS" if by_word else "CHARS"
        self.emit(
            f"{label} deleted={totals.deleted} inserted={totals.inserted} common={totals.common}"
        )

    def word_diff(self, arguments):
        self.token_diff(arguments, True)

    def char_diff(self, arguments):
        self.token_diff(arguments, False)

    def stat(self, arguments):
        old_name, new_name = arguments[:2]
        self.require(old_name, new_name)
        old, new = self.files[old_name], self.files[new_name]
        diff = LineDiff(old, new, arguments[2:])
        deleted = sum(block.x for block in diff.blocks)
        inserted = sum(block.y for block in diff.blocks)
        total = deleted + inserted
        unchanged = len(old) - deleted
        summary = f"{old_name} -> {new_name} | {total}"
        if total > 0:
            summary += " " + stat_graph(inserted, deleted)
        self.emit(summary)
        line_total = len(old) + len(new)
        similarity = 200 * unchanged // line_total if line_total > 0 else 100
        self.emit(
            f"changes={len(diff.blocks)} insertions={inserted} deletions={deleted}"
            f" unchanged={unchanged} similarity={similarity}%"
        )

    def patch(self, arguments, data):
        name = arguments[0]
        self.require(name)
        options = arguments[2:]
        reverse = "REVERSE" in options
        dry_run = "DRYRUN" in options
        max_fuzz = int(options[options.index("FUZZ") + 1]) if "FUZZ" in options else 0
        hunks = parse_patch(data)
        self.emit(("checking file " if dry_run else "patching file ") + name)
        lines = self.files[name]
        first = hunks[0]
        if (
            search_hunk(first, lines, 0, reverse, max_fuzz) is None
            and search_hunk(first, lines, 0, not reverse, max_fuzz) is not None
        ):
            self.emit("Reversed (or previously applied) patch detected! Skipping patch.")
            self.emit(f"RESULT applied=0 failed=0 ignored={len(hunks)} lines={len(lines)}")
            return
        adjustment = 0
        applied = failed = 0
        for number, hunk in enumerate(hunks, 1):
            match = search_hunk(hunk, lines, adjustment, reverse, max_fuzz)
            if match is None:
                failed += 1
                self.emit(f"Hunk #{number} FAILED at {hunk.start(reverse)}")
                continue
            old, new = hunk.sequences(reverse)
            lines = match.lines
            adjustment += match.delta + len(new) - len(old)
            applied += 1
            self.emit(match.report(number))
        self.emit(f"RESULT applied={applied} failed={failed} ignored=0 lines={len(lines)}")
        if not dry_run and applied >= 1:
            self.save(name, lines)

    def edit(self, arguments, data):
        name = arguments[0]
        self.require(name)
        lines, executed = run_edit_script(self.files[name], data)
        self.emit(f"EDIT {name} commands={executed} lines={len(lines)}")
        self.save(name, lines)

    def three_way(self, base_name, ours_name, theirs_name):
        self.require(base_name, ours_name, theirs_name)
        return three_way_chunks(
            self.files[base_name], self.files[ours_name], self.files[theirs_name]
        )

    def diff3(self, arguments):
        base_name, ours_name, theirs_name = arguments
        chunks = self.three_way(base_name, ours_name, theirs_name)
        changes = [chunk for chunk in chunks if chunk.kind != "stable"]
        for chunk in changes:
            self.emit(f"==== {chunk.kind} {chunk.location()}")
            self.output.extend("O " + line for line in chunk.base)
            if chunk.kind != "b":
                self.output.extend("A " + line for line in chunk.ours)
            if chunk.kind in ("b", "conflict"):
                self.output.extend("B " + line for line in chunk.theirs)
        self.emit(f"DIFF3 chunks={len(changes)} {kind_counts(chunks)}")

    def merge(self, arguments):
        base_name, ours_name, theirs_name, target = arguments[:4]
        mode = arguments[4] if len(arguments) == 5 else "MARKERS"
        chunks = self.three_way(base_name, ours_name, theirs_name)
        result = []
        conflicts = []
        for chunk in chunks:
            if chunk.kind == "b":
                result.extend(chunk.theirs)
            elif chunk.kind == "conflict":
                result.extend(conflict_lines(chunk, mode, base_name, ours_name, theirs_name))
                conflicts.append(chunk)
            else:
                result.extend(chunk.ours)
        self.emit(f"MERGE {target} lines={len(result)} {kind_counts(chunks)}")
        for number, chunk in enumerate(conflicts, 1):
            self.emit(f"CONFLICT {number} {chunk.location()}")
        self.save(target, result)

    def conflicts(self, arguments):
        name = arguments[0]
        self.require(name)
        regions = conflict_regions(self.files[name])
        self.emit(f"CONFLICTS {name} count={len(regions)}")
        for number, region in enumerate(regions, 1):
            base = "none" if region.base is None else len(region.base)
            self.emit(
                f"{number}: lines {region.start}-{region.end} ours={len(region.ours)}"
                f" base={base} theirs={len(region.theirs)}"
            )

    def resolve(self, arguments):
        name, number_text, side = arguments
        self.require(name)
        number = int(number_text)
        lines = self.files[name]
        regions = conflict_regions(lines)
        if len(regions) < number:
            raise CommandError(f"ERROR no conflict {number} in {name}")
        region = regions[number - 1]
        if side == "BASE" and region.base is None:
            raise CommandError(f"ERROR no base section in conflict {number}")
        content = lines[:region.start - 1] + region.part(side) + lines[region.end:]
        remaining = len(conflict_regions(content))
        self.emit(f"RESOLVE {name} {number} {side} lines={len(content)} remaining={remaining}")
        self.save(name, content)

    def execute(self, words, data):
        command, arguments = words[0], words[1:]
        try:
            if command in DATA_COMMANDS:
                self.handlers[command](arguments, data)
            else:
                self.handlers[command](arguments)
        except CommandError as error:
            self.emit(str(error))


def main():
    lines = sys.stdin.read().splitlines()
    workspace = Workspace()
    position = 1
    for _ in range(int(lines[0])):
        words = lines[position].split(" ")
        position += 1
        data = []
        if words[0] in DATA_COMMANDS:
            count = int(words[2])
            data = lines[position:position + count]
            position += count
        workspace.execute(words, data)
    sys.stdout.write("\n".join(workspace.output) + "\n")


if __name__ == "__main__":
    main()
