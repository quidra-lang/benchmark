import os
from bisect import bisect_right

from copying import Copying
from generational import Generational
from heap import (
    CollectionRecord, HeapObject, Pair, class_table, dec2, heap_map, largest_free, pct,
    total_free,
)
from mark_sweep import MarkCompact, MarkSweep, mark, sweep
from mutator import COMMAND_NAMES, read_config, read_script


INPUT_DIR = "input"
OUTPUT_DIR = "output"
STACK_LIMIT = 64
LIFETIME_CLASSES = ("0-63", "64-255", "256-1023", "1024-4095", "4096+")
LIFETIME_LIMITS = (63, 255, 1023, 4095)
GENERATIONAL_KINDS = ("minor", "major", "tenure", "full")
SUMMARY_HEADER = (
    "collector,type,status,collections,pauses,live,moved,moved_objects,max_moves,freed,"
    "total_work,p50_pause,p90_pause,max_pause,peak_used,end_used,end_free,largest_free,"
    "fragmentation"
)


def reachable_numbers(roots):
    reached = set()
    stack = [root for root in roots if root is not None]
    while stack:
        obj = stack.pop()
        if obj.number in reached:
            continue
        reached.add(obj.number)
        for child in obj.fields:
            if child is not None:
                stack.append(child)
    return reached


def lifetime_class(lifetime):
    for index, limit in enumerate(LIFETIME_LIMITS):
        if lifetime <= limit:
            return index
    return len(LIFETIME_LIMITS)


def used_words(objects):
    return sum(obj.size for obj in objects)


def fragmentation(blocks):
    total = total_free(blocks)
    return pct(total - largest_free(blocks), total)


def join_blocks(blocks):
    lines = []
    for index, block in enumerate(blocks):
        if index > 0:
            lines.append("")
        lines.extend(block)
    return lines


class Checkpoint:
    def __init__(self, command, stack, live, allocated, phase, survivors, reachable):
        self.label = command.label
        self.line = command.line
        self.stack = stack
        self.live = live
        self.allocated = allocated
        self.phase = phase
        self.survivors = survivors
        self.reachable = reachable


class Script:
    def __init__(self):
        self.line_count = 0
        self.commands = []
        self.errors = []
        self.counts = dict.fromkeys(COMMAND_NAMES, 0)
        self.roots = []
        self.objects = []
        self.births = []
        self.deaths = []
        self.lifetimes = []
        self.clock = 0
        self.alive = set()
        self.live = Pair()
        self.peak = Pair()
        self.peak_line = None
        self.checkpoints = []
        self.labels = set()
        self.phase_start = 0

    def analyze(self, parsed_lines):
        self.line_count = len(parsed_lines)
        for line, (command, reason) in enumerate(parsed_lines, 1):
            if reason is None:
                reason = self.check(command)
            if reason is None:
                self.run(command)
            else:
                self.errors.append((line, reason))

    def check(self, command):
        name = command.name
        depth = len(self.roots)
        if name in ("ALLOC", "PUSH", "LOAD") and depth == STACK_LIMIT:
            return "stack"
        if name in ("LOAD", "SET", "OVERWRITE") and command.slot >= depth:
            return "stack"
        if name in ("PUSH", "SET", "OVERWRITE"):
            if command.source is not None and command.source >= depth:
                return "stack"
        if name == "POP" and command.count > depth:
            return "stack"
        if name in ("LOAD", "SET"):
            target = self.roots[command.slot]
            if target is None:
                return "null"
            if command.field >= len(target.fields):
                return "field"
        if name == "CHECKPOINT" and command.label in self.labels:
            return "duplicate"
        return None

    def value(self, source):
        if source is None:
            return None
        return self.roots[source]

    def execute(self, command):
        name = command.name
        if name == "ALLOC":
            obj = HeapObject(len(self.objects) + 1, command.pointers, command.data)
            self.objects.append(obj)
            self.births.append(self.clock)
            self.deaths.append(None)
            self.lifetimes.append(None)
            self.clock += obj.size
            self.roots.append(obj)
        elif name == "PUSH":
            self.roots.append(self.value(command.source))
        elif name == "LOAD":
            self.roots.append(self.roots[command.slot].fields[command.field])
        elif name == "POP":
            del self.roots[len(self.roots) - command.count:]
        elif name == "SET":
            self.roots[command.slot].fields[command.field] = self.value(command.source)
        elif name == "OVERWRITE":
            self.roots[command.slot] = self.value(command.source)

    def run(self, command):
        self.commands.append(command)
        self.counts[command.name] += 1
        self.execute(command)
        reachable = reachable_numbers(self.roots)
        for number in self.alive - reachable:
            obj = self.objects[number - 1]
            self.deaths[number - 1] = command.line
            self.lifetimes[number - 1] = self.clock - self.births[number - 1] - obj.size
        self.alive = reachable
        self.live = Pair()
        for number in reachable:
            self.live.add(self.objects[number - 1])
        if self.peak_line is None or self.live.words > self.peak.words:
            self.peak = self.live
            self.peak_line = command.line
        if command.name == "CHECKPOINT":
            self.add_checkpoint(command, reachable)

    def add_checkpoint(self, command, reachable):
        self.labels.add(command.label)
        allocated = Pair()
        for obj in self.objects:
            allocated.add(obj)
        phase = Pair()
        survivors = Pair()
        for obj in self.objects[self.phase_start:]:
            phase.add(obj)
            if obj.number in reachable:
                survivors.add(obj)
        self.phase_start = len(self.objects)
        checkpoint = Checkpoint(
            command, len(self.roots), self.live, allocated, phase, survivors, reachable
        )
        self.checkpoints.append(checkpoint)

    def report(self):
        lines = [
            f"script lines {self.line_count} valid {len(self.commands)} errors {len(self.errors)}"
        ]
        for line, reason in self.errors:
            lines.append(f"error line {line} {reason}")
        counts = " ".join(f"{name} {self.counts[name]}" for name in COMMAND_NAMES)
        lines.append(f"commands {counts}")
        sizes = [obj.size for obj in self.objects]
        lines.append(
            f"allocated objects {len(sizes)} words {sum(sizes)} sizes {class_table(sizes)}"
        )
        lines.append(
            f"peak_live objects {self.peak.count} words {self.peak.words} line {self.peak_line}"
        )
        lines.append(
            f"end_live objects {self.live.count} words {self.live.words} stack {len(self.roots)}"
        )
        lifetime_counts = [0] * (len(LIFETIME_CLASSES) + 1)
        for lifetime in self.lifetimes:
            if lifetime is None:
                lifetime_counts[-1] += 1
            else:
                lifetime_counts[lifetime_class(lifetime)] += 1
        parts = [f"{label} {count}" for label, count in zip(LIFETIME_CLASSES, lifetime_counts)]
        lines.append(f"lifetimes {' '.join(parts)} live {lifetime_counts[-1]}")
        for checkpoint in self.checkpoints:
            survival = pct(checkpoint.survivors.words, checkpoint.phase.words)
            lines.append(
                f"checkpoint {checkpoint.label} line {checkpoint.line} stack {checkpoint.stack} "
                f"live {checkpoint.live} allocated {checkpoint.allocated} "
                f"phase {checkpoint.phase} survivors {checkpoint.survivors} survival {survival}"
            )
        return lines


def leak_groups(members):
    neighbors = {number: [] for number in members}
    for obj in members.values():
        for child in obj.fields:
            if child is not None and child.number in members:
                neighbors[obj.number].append(child.number)
                neighbors[child.number].append(obj.number)
    groups = []
    grouped = set()
    for number in sorted(members):
        if number in grouped:
            continue
        grouped.add(number)
        stack = [number]
        group = []
        while stack:
            current = stack.pop()
            group.append(members[current])
            for other in neighbors[current]:
                if other not in grouped:
                    grouped.add(other)
                    stack.append(other)
        groups.append(sorted(group, key=lambda obj: obj.number))
    return groups


def on_cycle(obj, members):
    visited = set()
    stack = [child for child in obj.fields if child is not None and child.number in members]
    while stack:
        current = stack.pop()
        if current is obj:
            return True
        if current.number in visited:
            continue
        visited.add(current.number)
        for child in current.fields:
            if child is not None and child.number in members:
                stack.append(child)
    return False


def leak_report(title, garbage, deaths):
    members = {obj.number: obj for obj in garbage}
    groups = leak_groups(members)
    lines = [
        f"{title} groups {len(groups)} objects {len(garbage)} words {used_words(garbage)}"
    ]
    for index, group in enumerate(groups, 1):
        ids = []
        cycles = 0
        for obj in group:
            if on_cycle(obj, members):
                cycles += 1
                ids.append(f"{obj.number}*")
            else:
                ids.append(str(obj.number))
        died = max(deaths[obj.number - 1] for obj in group)
        lines.append(
            f"group {index} objects {len(group)} words {used_words(group)} cycle {cycles} "
            f"died {died} ids {' '.join(ids)}"
        )
    return lines


class Cascade:
    def __init__(self, line):
        self.line = line
        self.freed = Pair()
        self.work = 0


class RefCounting(MarkSweep):
    def __init__(self, size, deaths):
        super().__init__(size)
        self.deaths = deaths
        self.increments = 0
        self.decrements = 0
        self.released = []
        self.reports = []

    def retain(self, obj):
        if obj is None:
            return
        obj.count += 1
        self.increments += 1

    def release(self, obj):
        if obj is None:
            return
        self.decrements += 1
        obj.count -= 1
        if obj.count > 0:
            return
        pending = [obj]
        while pending:
            current = pending.pop()
            self.objects.remove(current)
            self.released.append(current)
            for child in current.fields:
                if child is None:
                    continue
                self.decrements += 1
                child.count -= 1
                if child.count == 0:
                    pending.append(child)

    def take_cascade(self, line):
        if not self.released:
            return None
        cascade = Cascade(line)
        for obj in self.released:
            cascade.freed.add(obj)
            cascade.work += 1 + len(obj.fields)
        self.released = []
        return cascade

    def collect(self, roots, line, request):
        number = len(self.records) + 1
        record = CollectionRecord(number, line, request, "backup", self.free_list())
        mark(record, roots, self.objects)
        garbage = [obj for obj in self.objects if not obj.marked]
        title = f"backup {record.number} line {line}"
        self.reports.append(leak_report(title, garbage, self.deaths))
        self.objects = sweep(record, self.objects)
        for obj in garbage:
            for child in obj.fields:
                if child is not None and child.marked:
                    child.count -= 1
                    self.decrements += 1
        record.finish(self.free_list())
        self.records.append(record)

    def finish(self, reachable):
        garbage = [obj for obj in self.objects if obj.number not in reachable]
        self.reports.append(leak_report("end", garbage, self.deaths))


class Pause:
    def __init__(self, line, work, freed_words, collection):
        self.line = line
        self.work = work
        self.freed_words = freed_words
        self.collection = collection


def percentile(works, rank):
    if not works:
        return "-"
    return works[(rank * len(works) + 99) // 100 - 1]


class PauseStats:
    def __init__(self, pauses):
        works = sorted(pause.work for pause in pauses)
        self.count = len(pauses)
        self.collections = sum(1 for pause in pauses if pause.collection)
        self.work = sum(works)
        self.freed_words = sum(pause.freed_words for pause in pauses)
        self.maximum = works[-1] if works else 0
        self.p50 = percentile(works, 50)
        self.p90 = percentile(works, 90)


class Timeline:
    def __init__(self):
        self.starts = []
        self.lengths = []
        self.mutator_flags = []
        self.mutator_before = []
        self.length = 0
        self.mutator = 0

    def add(self, mutator, units):
        if units == 0:
            return
        if self.mutator_flags and self.mutator_flags[-1] == mutator:
            self.lengths[-1] += units
        else:
            self.starts.append(self.length)
            self.lengths.append(units)
            self.mutator_flags.append(mutator)
            self.mutator_before.append(self.mutator)
        self.length += units
        if mutator:
            self.mutator += units

    def mutator_until(self, position):
        index = bisect_right(self.starts, position) - 1
        if self.mutator_flags[index]:
            return self.mutator_before[index] + position - self.starts[index]
        return self.mutator_before[index]

    def utilization(self):
        return pct(self.mutator, self.length)

    def minimum_utilization(self, width):
        if width > self.length:
            return "-"
        lowest = width
        for start, length in zip(self.starts, self.lengths):
            for begin in (start, start + length - width):
                if 0 <= begin <= self.length - width:
                    count = self.mutator_until(begin + width) - self.mutator_until(begin)
                    lowest = min(lowest, count)
        return pct(lowest, width)


def create_collector(entry, size, deaths):
    if entry.algorithm == "MARK_SWEEP":
        return MarkSweep(size)
    if entry.algorithm == "MARK_COMPACT":
        return MarkCompact(size)
    if entry.algorithm == "COPYING":
        return Copying(size)
    if entry.algorithm == "GENERATIONAL":
        return Generational(size, entry.young, entry.age)
    return RefCounting(size, deaths)


def free_line(blocks):
    lengths = [length for _, length in blocks]
    return (
        f"free total {total_free(blocks)} largest {largest_free(blocks)} blocks {len(blocks)} "
        f"sizes {class_table(lengths)} fragmentation {fragmentation(blocks)}"
    )


def locality_line(objects, reachable):
    pointers = 0
    forward = 0
    backward = 0
    distance = 0
    for obj in objects:
        if obj.number not in reachable:
            continue
        for child in obj.fields:
            if child is None:
                continue
            pointers += 1
            if child.address > obj.address:
                forward += 1
            elif child.address < obj.address:
                backward += 1
            distance += abs(child.address - obj.address)
    mean = "-" if pointers == 0 else dec2(distance, pointers)
    return (
        f"locality pointers {pointers} forward {forward} backward {backward} "
        f"mean_distance {mean}"
    )


def generations_line(collector):
    young = Pair()
    old = Pair()
    ages = [0, 0, 0, 0]
    for obj in collector.objects:
        if collector.is_young(obj):
            young.add(obj)
            ages[min(obj.age, 3)] += 1
        else:
            old.add(obj)
    return (
        f"generations young {young} old {old} remembered {len(collector.remembered)} "
        f"ages 0:{ages[0]} 1:{ages[1]} 2:{ages[2]} 3+:{ages[3]}"
    )


def record_line(record):
    return (
        f"{record.number} line {record.line} size {record.request} kind {record.kind} "
        f"live {record.live} freed {record.freed} moved {record.moved} "
        f"promoted {record.promoted} stack {record.stack} work {record.work} "
        f"before {record.before[0]} {record.before[1]} after {record.after[0]} {record.after[1]}"
    )


class Run:
    def __init__(self, entry, config, script):
        self.entry = entry
        self.config = config
        self.script = script
        self.collector = create_collector(entry, config.heap_size, script.deaths)
        self.generational = entry.algorithm == "GENERATIONAL"
        self.refcount = entry.algorithm == "REFCOUNT"
        self.roots = []
        self.placed = []
        self.cascades = []
        self.timeline = Timeline()
        self.observations = []
        self.peak_used = 0
        self.failed_line = None
        self.failed_size = 0

    def completed(self):
        return self.failed_line is None

    def simulate(self):
        for command in self.script.commands:
            if not self.step(command):
                return
        if self.refcount:
            self.collector.finish(self.script.alive)

    def step(self, command):
        collections = len(self.collector.records)
        if command.name == "ALLOC":
            obj = HeapObject(len(self.placed) + 1, command.pointers, command.data)
            placed = self.allocate(obj, command.line)
            units = obj.size
        else:
            self.execute(command)
            placed = True
            units = 1
        for record in self.collector.records[collections:]:
            self.timeline.add(False, record.work)
        if not placed:
            self.failed_line = command.line
            self.failed_size = units
            return False
        self.timeline.add(True, units)
        if self.refcount:
            cascade = self.collector.take_cascade(command.line)
            if cascade is not None:
                self.cascades.append(cascade)
                self.timeline.add(False, cascade.work)
        return True

    def retain(self, obj):
        if self.refcount:
            self.collector.retain(obj)

    def release(self, obj):
        if self.refcount:
            self.collector.release(obj)

    def value(self, source):
        if source is None:
            return None
        return self.roots[source]

    def push(self, obj):
        self.retain(obj)
        self.roots.append(obj)

    def allocate(self, obj, line):
        if not self.collector.allocate(obj, self.roots, line):
            return False
        self.placed.append(obj)
        self.push(obj)
        self.peak_used = max(self.peak_used, used_words(self.collector.objects))
        return True

    def execute(self, command):
        name = command.name
        if name == "PUSH":
            self.push(self.value(command.source))
        elif name == "LOAD":
            self.push(self.roots[command.slot].fields[command.field])
        elif name == "POP":
            for _ in range(command.count):
                self.release(self.roots.pop())
        elif name == "SET":
            target = self.roots[command.slot]
            value = self.value(command.source)
            if self.generational:
                self.collector.write_barrier(target, value)
            self.retain(value)
            previous = target.fields[command.field]
            target.fields[command.field] = value
            self.release(previous)
        elif name == "OVERWRITE":
            value = self.value(command.source)
            self.retain(value)
            previous = self.roots[command.slot]
            self.roots[command.slot] = value
            self.release(previous)
        elif name == "CHECKPOINT":
            checkpoint = self.script.checkpoints[len(self.observations)]
            self.observations.append(self.observe(checkpoint))

    def observe(self, checkpoint):
        objects = self.collector.objects
        reachable = checkpoint.reachable
        in_heap = Pair()
        live = Pair()
        garbage = Pair()
        for obj in objects:
            in_heap.add(obj)
            if obj.number in reachable:
                live.add(obj)
            else:
                garbage.add(obj)
        lines = [
            f"heap objects {in_heap} reachable {live} garbage {garbage}",
            free_line(self.collector.free_list()),
            locality_line(objects, reachable),
        ]
        if self.generational:
            lines.append(generations_line(self.collector))
        if checkpoint.label in self.config.maps:
            text = heap_map(
                self.config.heap_size, objects, reachable, self.collector.inactive_range()
            )
            width = self.config.width
            for start in range(0, len(text), width):
                lines.append(f"{start:04d} {text[start:start + width]}")
        return lines

    def pauses(self):
        pauses = [
            Pause(record.line, record.work, record.freed.words, True)
            for record in self.collector.records
        ]
        for cascade in self.cascades:
            pauses.append(Pause(cascade.line, cascade.work, cascade.freed.words, False))
        return pauses

    def failed_before(self, line):
        return not self.completed() and self.failed_line < line

    def generational_line(self):
        parts = ["generational"]
        promoted = Pair()
        for kind in GENERATIONAL_KINDS:
            records = [record for record in self.collector.records if record.kind == kind]
            parts.append(f"{kind} {len(records)} {sum(record.work for record in records)}")
        for record in self.collector.records:
            promoted.add_pair(record.promoted)
        parts.append(f"promoted {promoted}")
        parts.append(f"barrier {self.collector.barriers}")
        parts.append(f"remembered {self.collector.remembers}")
        return " ".join(parts)

    def refcount_line(self):
        freed = Pair()
        largest = None
        for cascade in self.cascades:
            freed.add_pair(cascade.freed)
            if largest is None or cascade.work > largest.work:
                largest = cascade
        if largest is None:
            maximum = "max_cascade 0 0 line -"
        else:
            maximum = f"max_cascade {largest.freed.count} {largest.work} line {largest.line}"
        return (
            f"refcount increments {self.collector.increments} "
            f"decrements {self.collector.decrements} cascades {len(self.cascades)} "
            f"freed {freed} {maximum}"
        )

    def phase_lines(self, pauses):
        lines = []
        previous = 0
        for checkpoint in self.script.checkpoints:
            if self.failed_before(checkpoint.line):
                lines.append(f"phase {checkpoint.label} out_of_memory")
            else:
                stats = PauseStats(
                    [pause for pause in pauses if previous < pause.line <= checkpoint.line]
                )
                lines.append(
                    f"phase {checkpoint.label} collections {stats.collections} "
                    f"pauses {stats.count} work {stats.work} freed {stats.freed_words} "
                    f"max_pause {stats.maximum}"
                )
            previous = checkpoint.line
        return lines

    def collection_block(self):
        lines = [f"collector {self.entry.name} {self.entry.algorithm}"]
        for record in self.collector.records:
            lines.append(record_line(record))
        pauses = self.pauses()
        stats = PauseStats(pauses)
        lines.append(
            f"totals collections {stats.collections} pauses {stats.count} work {stats.work} "
            f"freed {stats.freed_words} pause p50 {stats.p50} p90 {stats.p90} max {stats.maximum}"
        )
        windows = " ".join(
            f"{width}:{self.timeline.minimum_utilization(width)}"
            for width in self.config.windows
        )
        lines.append(f"utilization {self.timeline.utilization()} mmu {windows}")
        if self.generational:
            lines.append(self.generational_line())
        if self.refcount:
            lines.append(self.refcount_line())
        lines.extend(self.phase_lines(pauses))
        if self.completed():
            lines.append("status completed")
        else:
            lines.append(f"status out_of_memory line {self.failed_line} size {self.failed_size}")
        return lines

    def summary_row(self):
        records = self.collector.records
        stats = PauseStats(self.pauses())
        moves = [obj.moves for obj in self.placed if obj.moves > 0]
        if self.completed():
            blocks = self.collector.free_list()
            status = "completed"
            ending = [
                used_words(self.collector.objects), total_free(blocks), largest_free(blocks),
                fragmentation(blocks),
            ]
        else:
            status = "out_of_memory"
            ending = ["-", "-", "-", "-"]
        values = [
            self.entry.name, self.entry.algorithm, status, len(records), stats.count,
            sum(record.live.count for record in records),
            sum(record.moved.count for record in records),
            len(moves), max(moves, default=0), stats.freed_words, stats.work,
            stats.p50, stats.p90, stats.maximum, self.peak_used,
        ]
        return ",".join(str(value) for value in values + ending)

    def leak_block(self):
        lines = [f"collector {self.entry.name}"]
        for report in self.collector.reports:
            lines.extend(report)
        if not self.completed():
            lines.append("status out_of_memory")
        return lines


def heap_map_lines(script, runs):
    blocks = []
    for index, checkpoint in enumerate(script.checkpoints):
        header = f"checkpoint {checkpoint.label} line {checkpoint.line}"
        for run in runs:
            block = [f"{header} collector {run.entry.name}"]
            if index < len(run.observations):
                block.extend(run.observations[index])
            else:
                block.append("out_of_memory")
            blocks.append(block)
    return join_blocks(blocks)


def leak_lines(runs):
    blocks = [run.leak_block() for run in runs if run.refcount]
    if not blocks:
        return ["none"]
    return join_blocks(blocks)


def write_lines(name, lines):
    with open(os.path.join(OUTPUT_DIR, name), "w") as handle:
        handle.write("".join(line + "\n" for line in lines))


def main():
    config = read_config(os.path.join(INPUT_DIR, "config.txt"))
    script = Script()
    script.analyze(read_script(os.path.join(INPUT_DIR, "mutator.txt")))
    runs = []
    for entry in config.collectors:
        run = Run(entry, config, script)
        run.simulate()
        runs.append(run)
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    write_lines("mutator.txt", script.report())
    write_lines("heap_maps.txt", heap_map_lines(script, runs))
    write_lines("collections.txt", join_blocks([run.collection_block() for run in runs]))
    write_lines("summary.csv", [SUMMARY_HEADER] + [run.summary_row() for run in runs])
    write_lines("leaks.txt", leak_lines(runs))


if __name__ == "__main__":
    main()
