import copy
import re
import sys


TIME_PATTERN = re.compile(r"([0-9]{2}):([0-9]{2}):([0-9]{2}),([0-9]{3})")
POSITION_CODE = re.compile(r"\{\\an[1-9]\}")
ASS_TAGS = {
    "<i>": r"{\i1}", "</i>": r"{\i0}",
    "<b>": r"{\b1}", "</b>": r"{\b0}",
    "<u>": r"{\u1}", "</u>": r"{\u0}",
}
SCHEMAS = {
    "LIST": (), "VALIDATE": (), "SEARCH": ("string",), "AT": ("time",),
    "GAPS": ("gap",), "STATS": (), "PRINT": (), "TOVTT": (), "TOASS": (),
    "FRAMES": ("fps",), "SHIFT": ("signed",),
    "SHIFTFROM": ("position", "signed"), "SCALE": ("factor", "factor"),
    "SYNC": ("position", "time", "position", "time"), "SNAP": ("fps",),
    "FIXOVERLAP": ("gap",), "EXTEND": ("minimum",),
    "TIME": ("position", "time", "time"), "SORT": (), "RENUMBER": (),
    "MERGE": ("gap",), "SPLIT": ("width",),
    "INSERT": ("position", "time", "time", "text"), "DELETE": ("position",),
    "TEXT": ("position", "text"), "BALANCE": (), "STRIP": (), "CLEANHI": (),
    "REPLACE": ("replacement",), "UNDO": (),
}
STRING_COMMANDS = {"SEARCH", "INSERT", "TEXT", "REPLACE"}
MODIFYING = set((
    "SHIFT SHIFTFROM SCALE SYNC SNAP FIXOVERLAP EXTEND TIME SORT RENUMBER "
    "MERGE SPLIT INSERT DELETE TEXT BALANCE STRIP CLEANHI REPLACE"
).split())


class CommandError(Exception):
    pass


def bad_arguments():
    raise CommandError("bad arguments")


def integer(text, minimum=0, maximum=999999999, signed=False):
    pattern = r"-?[0-9]{1,9}" if signed else r"[0-9]{1,9}"
    if re.fullmatch(pattern, text) is None:
        bad_arguments()
    value = int(text)
    if not minimum <= value <= maximum:
        bad_arguments()
    return value


def parse_time(text):
    match = TIME_PATTERN.fullmatch(text)
    if match is None:
        bad_arguments()
    hours, minutes, seconds, milliseconds = map(int, match.groups())
    if minutes > 59 or seconds > 59:
        bad_arguments()
    return hours * 3600000 + minutes * 60000 + seconds * 1000 + milliseconds


def frame_rate(text):
    parts = text.split("/")
    if len(parts) not in (1, 2):
        bad_arguments()
    numerator = integer(parts[0], 1, 100000)
    denominator = integer(parts[1], 1, 100000) if len(parts) == 2 else 1
    return numerator, denominator


def argument(text, kind):
    if kind == "time":
        return parse_time(text)
    if kind == "fps":
        return frame_rate(text)
    if kind == "signed":
        return integer(text, -999999999, 999999999, True)
    if kind in ("position", "factor", "gap", "minimum", "width"):
        minimum, maximum = {
            "position": (1, 999999999), "factor": (1, 100000),
            "gap": (0, 60000), "minimum": (1, 60000), "width": (10, 80),
        }[kind]
        return integer(text, minimum, maximum)
    if kind == "text":
        parts = text.split("|")
        if not all(parts):
            bad_arguments()
        return parts
    if kind == "replacement":
        old, separator, new = text.partition("|")
        if not separator or not old or not new or "|" in new:
            bad_arguments()
        return old, new
    if not text:
        bad_arguments()
    return text


def round_ratio(numerator, denominator):
    if denominator < 0:
        numerator, denominator = -numerator, -denominator
    return (2 * numerator + denominator) // (2 * denominator)


def srt_time(value, separator=","):
    return (f"{value // 3600000:02d}:{value // 60000 % 60:02d}:"
            f"{value // 1000 % 60:02d}{separator}{value % 1000:03d}")


def ass_time(value):
    centiseconds = (value + 5) // 10
    return (f"{centiseconds // 360000}:{centiseconds // 6000 % 60:02d}:"
            f"{centiseconds // 100 % 60:02d}.{centiseconds % 100:02d}")


def two_decimals(value):
    return f"{value // 100}.{value % 100:02d}"


def markup(line):
    position = 0
    while position < len(line):
        tag = next((tag for tag in ASS_TAGS if line.startswith(tag, position)), None)
        if tag is not None:
            yield "format", tag
            position += len(tag)
            continue
        if line.startswith("</font>", position):
            yield "font", "</font>"
            position += 7
            continue
        if (line.startswith("<font", position) and position + 5 < len(line)
                and line[position + 5] in (" ", ">")):
            end = line.find(">", position + 5)
            if end != -1:
                yield "font", line[position:end + 1]
                position = end + 1
                continue
        match = POSITION_CODE.match(line, position)
        if match is not None:
            yield "position", match.group()
            position = match.end()
            continue
        yield "character", line[position]
        position += 1


def words(lines):
    return [word for word in " ".join(lines).split(" ") if word]


def wrap(sequence, width):
    lines = []
    for word in sequence:
        if lines and len(lines[-1]) + 1 + len(word) <= width:
            lines[-1] += " " + word
        else:
            lines.append(word)
    return lines


def clean_hi_line(line):
    pieces = []
    segments = 0
    position = 0
    while position < len(line):
        closing = {"[": "]", "(": ")"}.get(line[position])
        end = line.find(closing, position + 1) if closing is not None else -1
        if end != -1:
            segments += 1
            position = end + 1
        else:
            pieces.append(line[position])
            position += 1
    normalized = " ".join(words(["".join(pieces)]))
    prefix = "- " if normalized.startswith("- ") else ""
    body = normalized[len(prefix):]
    label, separator, rest = body.partition(":")
    labels = 0
    if separator and re.fullmatch(r"[A-Z][A-Z0-9 ]*", label):
        normalized = " ".join(words([prefix + rest]))
        labels = 1
    return normalized, segments, labels


class Cue:
    def __init__(self, index, start, end, lines):
        self.index = index
        self.start = start
        self.end = end
        self.lines = lines

    @property
    def duration(self):
        return self.end - self.start

    @property
    def characters(self):
        return sum(map(len, self.lines))

    @property
    def dialogue(self):
        return any(line.startswith("- ") for line in self.lines)


def load_cues(blocks):
    cues = []
    output = []
    for number, block in enumerate(blocks, 1):
        if re.fullmatch(r"[0-9]{1,6}", block[0]) is None:
            output.append(f"BAD CUE {number}: index")
            continue
        try:
            if len(block) < 2 or len(block[1]) != 29 or block[1][12:17] != " --> ":
                bad_arguments()
            start, end = parse_time(block[1][:12]), parse_time(block[1][17:])
        except CommandError:
            output.append(f"BAD CUE {number}: time")
            continue
        if len(block) < 3:
            output.append(f"BAD CUE {number}: no text")
            continue
        cues.append(Cue(int(block[0]), start, end, block[2:]))
    output.append(f"LOAD cues={len(cues)} bad={len(output)}")
    return cues, output


class SubtitleEditor:
    def __init__(self, cues):
        self.cues = cues
        self.history = []
        self.handlers = {
            "LIST": self.list_cues, "VALIDATE": self.validate, "SEARCH": self.search,
            "AT": self.at, "GAPS": self.gaps, "STATS": self.stats,
            "PRINT": self.print_srt, "TOVTT": self.to_vtt, "TOASS": self.to_ass,
            "FRAMES": self.frames, "SHIFT": self.shift, "SHIFTFROM": self.shift_from,
            "SCALE": self.scale, "SYNC": self.sync, "SNAP": self.snap,
            "FIXOVERLAP": self.fix_overlap, "EXTEND": self.extend, "TIME": self.set_time,
            "SORT": self.sort, "RENUMBER": self.renumber, "MERGE": self.merge,
            "SPLIT": self.split, "INSERT": self.insert, "DELETE": self.delete,
            "TEXT": self.set_text, "BALANCE": self.balance, "STRIP": self.strip,
            "CLEANHI": self.clean_hi, "REPLACE": self.replace, "UNDO": self.undo,
        }

    def parse(self, line):
        command = line.split(" ", 1)[0]
        if command not in SCHEMAS:
            raise CommandError("unknown command")
        schema = SCHEMAS[command]
        if command in STRING_COMMANDS:
            parts = line.split(" ", len(schema))
        else:
            parts = line.split(" ")
        if command == "DELETE" and len(parts) == 3:
            schema = ("position", "position")
        if len(parts) != len(schema) + 1:
            bad_arguments()
        values = [argument(text, kind) for text, kind in zip(parts[1:], schema)]
        if command == "DELETE" and len(values) == 2 and values[1] < values[0]:
            bad_arguments()
        limit = len(self.cues) + (1 if command == "INSERT" else 0)
        for value, kind in zip(values, schema):
            if kind == "position" and value > limit:
                raise CommandError(f"no cue {value}")
        return command, values

    def execute(self, line):
        try:
            command, values = self.parse(line)
            before = copy.deepcopy(self.cues) if command in MODIFYING else None
            output = self.handlers[command](*values)
            if command in MODIFYING:
                self.history.append((command, before))
            return output
        except CommandError as error:
            return ["ERROR " + str(error)]

    def cue_line(self, position, cue):
        return (f"{position} {cue.index} {srt_time(cue.start)} {srt_time(cue.end)} "
                + "|".join(cue.lines))

    def list_cues(self):
        return [self.cue_line(position, cue) for position, cue in enumerate(self.cues, 1)]

    def validate(self):
        output = []
        for position, cue in enumerate(self.cues, 1):
            prefix = f"cue {position}: "
            duration = cue.duration
            if cue.index != position:
                output.append(prefix + f"index {cue.index} (expected {position})")
            if duration <= 0:
                output.append(prefix + "end not after start")
            if position >= 2 and cue.start < self.cues[position - 2].end:
                overlap = self.cues[position - 2].end - cue.start
                output.append(prefix + f"overlaps previous by {overlap} ms")
            if 1 <= duration < 700:
                output.append(prefix + f"too short ({duration} ms)")
            elif duration > 7000:
                output.append(prefix + f"too long ({duration} ms)")
            for line_number, line in enumerate(cue.lines, 1):
                if len(line) > 42:
                    output.append(prefix + f"line {line_number} too long ({len(line)} chars)")
            if len(cue.lines) >= 3:
                output.append(prefix + f"too many lines ({len(cue.lines)})")
            if duration >= 1 and cue.characters * 1000 > 21 * duration:
                speed = two_decimals(cue.characters * 100000 // duration)
                output.append(prefix + f"too fast ({speed} cps)")
        output.append(f"VALIDATE problems={len(output)}")
        return output

    def search(self, text):
        output = []
        for position, cue in enumerate(self.cues, 1):
            line = next((line for line in cue.lines if text in line), None)
            if line is not None:
                output.append(f"{position} {srt_time(cue.start)} {line}")
        output.append(f"SEARCH found={len(output)}")
        return output

    def at(self, time):
        output = [self.cue_line(position, cue) for position, cue in enumerate(self.cues, 1)
                  if cue.start <= time < cue.end]
        output.append(f"AT active={len(output)}")
        return output

    def gaps(self, minimum):
        output = []
        for index in range(len(self.cues) - 1):
            gap = self.cues[index + 1].start - self.cues[index].end
            if gap < minimum:
                output.append(f"{index + 1} {index + 2} {gap}")
        output.append(f"GAPS count={len(output)}")
        return output

    def stats(self):
        count = len(self.cues)
        output = [f"STATS cues={count}"]
        if count == 0:
            return output
        durations = [max(0, cue.duration) for cue in self.cues]
        total = sum(durations)
        output.append(f"duration total={srt_time(total)} mean={srt_time(total // count)}")
        characters = sum(cue.characters for cue, duration in zip(self.cues, durations) if duration >= 1)
        output.append("speed " + (two_decimals(characters * 100000 // total) if total else "-"))
        longest = max(range(count), key=lambda index: durations[index])
        output.append(f"longest cue={longest + 1} duration={srt_time(durations[longest])}")
        if count == 1:
            output.append("gap none")
        else:
            gaps = [self.cues[i + 1].start - self.cues[i].end for i in range(count - 1)]
            largest = max(range(len(gaps)), key=lambda index: gaps[index])
            output.append(f"gap cue={largest + 1} ms={gaps[largest]}")
        return output

    def print_srt(self):
        output = []
        for cue in self.cues:
            output.extend([str(cue.index), f"{srt_time(cue.start)} --> {srt_time(cue.end)}"])
            output.extend(cue.lines)
            output.append("")
        return output

    def to_vtt(self):
        output = ["WEBVTT", ""]
        escapes = {"&": "&amp;", "<": "&lt;", ">": "&gt;"}
        for cue in self.cues:
            lines = []
            first_code = None
            for line in cue.lines:
                parts = []
                for kind, item in markup(line):
                    if kind == "position" and first_code is None:
                        first_code = int(item[4])
                    if kind == "format":
                        parts.append(item)
                    elif kind == "character":
                        parts.append(escapes.get(item, item))
                converted = "".join(parts).strip(" ")
                if converted:
                    lines.append(converted)
            if not lines:
                continue
            settings = ""
            if first_code in (7, 8, 9):
                settings += " line:0"
            elif first_code in (4, 5, 6):
                settings += " line:50%"
            if first_code in (1, 4, 7):
                settings += " align:start"
            elif first_code in (3, 6, 9):
                settings += " align:end"
            output.extend([str(cue.index), f"{srt_time(cue.start, '.')} --> {srt_time(cue.end, '.')}{settings}"])
            output.extend(lines)
            output.append("")
        return output

    def to_ass(self):
        output = ["[Events]", "Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text"]
        for cue in self.cues:
            lines = []
            for line in cue.lines:
                parts = []
                for kind, item in markup(line):
                    if kind == "format":
                        parts.append(ASS_TAGS[item])
                    elif kind != "font":
                        parts.append(item)
                lines.append("".join(parts))
            text = r"\N".join(lines)
            output.append(f"Dialogue: 0,{ass_time(cue.start)},{ass_time(cue.end)},Default,,0,0,0,,{text}")
        return output

    def frames(self, rate):
        numerator, denominator = rate
        return [f"{position} {cue.start * numerator // (1000 * denominator)} "
                f"{cue.end * numerator // (1000 * denominator)}"
                for position, cue in enumerate(self.cues, 1)]

    def transform_times(self, transform, first=0):
        clamped = 0
        for cue in self.cues[first:]:
            start, end = transform(cue.start), transform(cue.end)
            clamped += start < 0 or end < 0
            cue.start, cue.end = max(0, start), max(0, end)
        return clamped

    def shift(self, milliseconds):
        clamped = self.transform_times(lambda time: time + milliseconds)
        return [f"SHIFT cues={len(self.cues)} clamped={clamped}"]

    def shift_from(self, position, milliseconds):
        clamped = self.transform_times(lambda time: time + milliseconds, position - 1)
        return [f"SHIFTFROM cues={len(self.cues) - position + 1} clamped={clamped}"]

    def scale(self, numerator, denominator):
        self.transform_times(lambda time: round_ratio(time * numerator, denominator))
        return [f"SCALE cues={len(self.cues)}"]

    def sync(self, first, target_first, second, target_second):
        source_first, source_second = self.cues[first - 1].start, self.cues[second - 1].start
        if source_first == source_second:
            raise CommandError("sync points coincide")
        denominator = source_second - source_first
        clamped = self.transform_times(lambda time: round_ratio(
            target_first * denominator + (time - source_first) * (target_second - target_first), denominator
        ))
        return [f"SYNC cues={len(self.cues)} clamped={clamped}"]

    def snap(self, rate):
        numerator, denominator = rate
        changed = 0
        for cue in self.cues:
            old = cue.start, cue.end
            updated = []
            for time in old:
                frame = round_ratio(time * numerator, 1000 * denominator)
                updated.append(round_ratio(frame * 1000 * denominator, numerator))
            changed += sum(first != second for first, second in zip(old, updated))
            cue.start, cue.end = updated
        return [f"SNAP changed={changed}"]

    def fix_overlap(self, gap):
        output = []
        fixed = 0
        for index in range(len(self.cues) - 1):
            cue = self.cues[index]
            candidate = self.cues[index + 1].start - gap
            if cue.end > candidate:
                if candidate > cue.start:
                    cue.end = candidate
                    fixed += 1
                else:
                    output.append(f"cue {index + 1}: cannot fix")
        output.append(f"FIXOVERLAP fixed={fixed} failed={len(output)}")
        return output

    def extend(self, minimum):
        extended = 0
        for index, cue in enumerate(self.cues):
            if cue.duration < minimum:
                candidate = cue.start + minimum
                if index + 1 < len(self.cues):
                    candidate = min(candidate, self.cues[index + 1].start)
                if candidate > cue.end:
                    cue.end = candidate
                    extended += 1
        short = sum(cue.duration < minimum for cue in self.cues)
        return [f"EXTEND extended={extended} short={short}"]

    def set_time(self, position, start, end):
        cue = self.cues[position - 1]
        cue.start, cue.end = start, end
        return [f"TIME cue={position}"]

    def sort(self):
        ordered = sorted(enumerate(self.cues, 1), key=lambda item: (item[1].start, item[1].end))
        moved = sum(old != new for new, (old, cue) in enumerate(ordered, 1))
        self.cues = [cue for old, cue in ordered]
        return [f"SORT moved={moved}"]

    def renumber(self):
        changed = 0
        for position, cue in enumerate(self.cues, 1):
            changed += cue.index != position
            cue.index = position
        return [f"RENUMBER changed={changed}"]

    def merge(self, gap):
        merged = []
        joins = 0
        for cue in self.cues:
            if merged:
                previous = merged[-1]
                if cue.start - previous.end < gap and not previous.dialogue and not cue.dialogue:
                    lines = wrap(words(previous.lines + cue.lines), 42)
                    if len(lines) <= 2:
                        previous.end = max(previous.end, cue.end)
                        previous.lines = lines
                        joins += 1
                        continue
            merged.append(cue)
        self.cues = merged
        return [f"MERGE merged={joins} cues={len(self.cues)}"]

    def split(self, width):
        rebuilt = []
        split_count = 0
        for cue in self.cues:
            if cue.duration <= 0 or cue.dialogue:
                rebuilt.append(cue)
                continue
            lines = wrap(words(cue.lines), width)
            if len(lines) <= 2:
                cue.lines = lines
                rebuilt.append(cue)
                continue
            split_count += 1
            parts = [lines[index:index + 2] for index in range(0, len(lines), 2)]
            counts = [sum(map(len, part)) for part in parts]
            total = sum(counts)
            durations = [cue.duration * count // total for count in counts]
            remainders = [cue.duration * count % total for count in counts]
            missing = cue.duration - sum(durations)
            order = sorted(range(len(parts)), key=lambda index: (-remainders[index], index))
            for index in order[:missing]:
                durations[index] += 1
            start = cue.start
            for part, duration in zip(parts, durations):
                rebuilt.append(Cue(cue.index, start, start + duration, part))
                start += duration
        self.cues = rebuilt
        return [f"SPLIT split={split_count} cues={len(self.cues)}"]

    def insert(self, position, start, end, lines):
        self.cues.insert(position - 1, Cue(position, start, end, lines))
        return [f"INSERT cue={position} cues={len(self.cues)}"]

    def delete(self, position, last=None):
        last = position if last is None else last
        del self.cues[position - 1:last]
        return [f"DELETE removed={last - position + 1} cues={len(self.cues)}"]

    def set_text(self, position, lines):
        self.cues[position - 1].lines = lines
        return [f"TEXT cue={position} lines={len(lines)}"]

    def balance(self):
        changed = skipped = dialogue = 0
        for cue in self.cues:
            if cue.dialogue:
                dialogue += 1
                continue
            sequence = words(cue.lines)
            joined = " ".join(sequence)
            updated = [joined] if len(joined) <= 42 else None
            if updated is None:
                best_key = None
                for position in range(1, len(sequence)):
                    first = " ".join(sequence[:position])
                    second = " ".join(sequence[position:])
                    if len(first) <= 42 and len(second) <= 42:
                        key = abs(len(first) - len(second)), len(first)
                        if best_key is None or key < best_key:
                            updated, best_key = [first, second], key
            if updated is None:
                skipped += 1
            else:
                changed += updated != cue.lines
                cue.lines = updated
        return [f"BALANCE changed={changed} skipped={skipped} dialogue={dialogue}"]

    def strip(self):
        tags = removed_lines = removed_cues = 0
        remaining = []
        for cue in self.cues:
            lines = []
            for line in cue.lines:
                parts = []
                for kind, item in markup(line):
                    if kind == "character":
                        parts.append(item)
                    else:
                        tags += 1
                converted = "".join(parts).strip(" ")
                if converted:
                    lines.append(converted)
                else:
                    removed_lines += 1
            if lines:
                cue.lines = lines
                remaining.append(cue)
            else:
                removed_cues += 1
        self.cues = remaining
        return [f"STRIP tags={tags} removed_lines={removed_lines} removed_cues={removed_cues}"]

    def clean_hi(self):
        segments = labels = removed_lines = removed_cues = 0
        remaining = []
        for cue in self.cues:
            lines = []
            for line in cue.lines:
                converted, bracket_count, label_count = clean_hi_line(line)
                segments += bracket_count
                labels += label_count
                if converted and converted != "-":
                    lines.append(converted)
                else:
                    removed_lines += 1
            if lines:
                cue.lines = lines
                remaining.append(cue)
            else:
                removed_cues += 1
        self.cues = remaining
        return [f"CLEANHI segments={segments} labels={labels} removed_lines={removed_lines} removed_cues={removed_cues}"]

    def replace(self, replacement):
        old, new = replacement
        replacements = affected_cues = 0
        for cue in self.cues:
            count = sum(line.count(old) for line in cue.lines)
            replacements += count
            affected_cues += count > 0
            cue.lines = [line.replace(old, new) for line in cue.lines]
        return [f"REPLACE count={replacements} cues={affected_cues}"]

    def undo(self):
        if not self.history:
            raise CommandError("nothing to undo")
        command, self.cues = self.history.pop()
        return [f"UNDO command={command}"]


def read_blocks(stream):
    blocks = []
    current = []
    for raw in stream:
        line = raw.rstrip("\n")
        if line == "###":
            break
        if line:
            current.append(line)
        elif current:
            blocks.append(current)
            current = []
    if current:
        blocks.append(current)
    return blocks


def main():
    cues, output = load_cues(read_blocks(sys.stdin))
    for line in output:
        print(line)
    editor = SubtitleEditor(cues)
    count = int(sys.stdin.readline())
    for _ in range(count):
        for line in editor.execute(sys.stdin.readline().rstrip("\n")):
            print(line)


if __name__ == "__main__":
    main()
