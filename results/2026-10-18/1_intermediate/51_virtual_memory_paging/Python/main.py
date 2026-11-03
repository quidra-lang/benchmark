from collections import Counter
import copy
import sys


POLICIES = ("FIFO", "LRU", "LFU", "NRU", "AGING", "CLOCK", "ECLOCK", "WSCLOCK", "RANDOM", "OPT")
CLOCK_POLICIES = ("CLOCK", "ECLOCK", "WSCLOCK")
DEFAULT_SETTINGS = {
    "page": 256, "frames": 4, "tlb": 4, "sets": 1, "policy": "FIFO",
    "scope": "GLOBAL", "asid": "OFF", "tick": 0, "tau": 8, "seed": 1,
}
PAGE_SIZES = (16, 32, 64, 128, 256, 512, 1024, 2048, 4096)
NUMBER_LIMITS = {
    "frames": (1, 16), "tlb": (1, 8), "sets": (1, 8),
    "tick": (0, 1000), "tau": (1, 1000), "seed": (1, 2147483646),
}
WORD_CHOICES = {"policy": POLICIES, "scope": ("GLOBAL", "LOCAL"), "asid": ("ON", "OFF")}
RANDOM_MULTIPLIER = 48271
RANDOM_MODULUS = 2147483647
MAX_PROCESSES = 8
MAX_PAGE_COUNT = 256
MAX_FRAMES = 16


class CommandError(Exception):
    pass


def next_random(state):
    return RANDOM_MULTIPLIER * state % RANDOM_MODULUS


def parse_address(text):
    return int(text[2:], 16)


def hex_text(value):
    return f"0x{value:X}"


def ratio_text(part, whole):
    if whole == 0:
        return "0.00%"
    value = 10000 * part // whole
    return f"{value // 100}.{value % 100:02d}%"


class Access:
    def __init__(self, pid, op, address):
        self.pid = pid
        self.op = op
        self.address = address


def loop_accesses(arguments):
    pid, op = int(arguments[0]), arguments[1]
    start = parse_address(arguments[2])
    interval, length, repeats = (int(value) for value in arguments[3:])
    return [
        Access(pid, op, start + index * interval)
        for _ in range(repeats)
        for index in range(length)
    ]


def random_accesses(arguments):
    pid = int(arguments[0])
    low, high = parse_address(arguments[1]), parse_address(arguments[2])
    count, state, write_rate = (int(value) for value in arguments[3:])
    accesses = []
    for _ in range(count):
        state = next_random(state)
        address = low + state % (high - low)
        state = next_random(state)
        op = "W" if state % 100 < write_rate else "R"
        accesses.append(Access(pid, op, address))
    return accesses


def expand(lines):
    items = []
    for line in lines:
        words = line.split()
        if words[0][0].isdigit():
            items.append(Access(int(words[0]), words[1], parse_address(words[2])))
        elif words[0] == "LOOP":
            items.extend(loop_accesses(words[1:]))
        elif words[0] == "RAND":
            items.extend(random_accesses(words[1:]))
        else:
            items.append(words)
    return items


def segment_accesses(items, start):
    accesses = []
    for item in items[start:]:
        if isinstance(item, Access):
            accesses.append(item)
        elif item[0] == "SYSTEM":
            break
    return accesses


class Settings:
    def __init__(self, values):
        self.page = values["page"]
        self.frames = values["frames"]
        self.tlb = values["tlb"]
        self.sets = values["sets"]
        self.policy = values["policy"]
        self.scope = values["scope"]
        self.asid = values["asid"]
        self.tick = values["tick"]
        self.tau = values["tau"]
        self.seed = values["seed"]

    def variant(self, policy, frames):
        settings = copy.copy(self)
        settings.policy = policy
        settings.frames = frames
        return settings

    def describe(self):
        return (
            f"SYSTEM page={self.page} frames={self.frames} tlb={self.tlb} sets={self.sets} "
            f"policy={self.policy} scope={self.scope} asid={self.asid} "
            f"tick={self.tick} tau={self.tau} seed={self.seed}"
        )


def setting_value(key, text):
    if key in WORD_CHOICES:
        value = text
        valid = value in WORD_CHOICES[key]
    elif key == "page":
        value = int(text)
        valid = value in PAGE_SIZES
    else:
        value = int(text)
        low, high = NUMBER_LIMITS[key]
        valid = low <= value <= high
    if not valid:
        raise CommandError(f"invalid {key}")
    return value


def parse_settings(pairs):
    values = {}
    for pair in pairs:
        key, text = pair.split("=")
        if key not in DEFAULT_SETTINGS:
            raise CommandError(f"unknown key {key}")
        if key in values:
            raise CommandError(f"duplicate key {key}")
        values[key] = setting_value(key, text)
    for key, value in DEFAULT_SETTINGS.items():
        values.setdefault(key, value)
    if values["tlb"] % values["sets"] != 0:
        raise CommandError("invalid sets")
    return Settings(values)


class Page:
    def __init__(self, pid, number):
        self.pid = pid
        self.number = number
        self.frame = None
        self.slot = None
        self.readonly = False
        self.locked = False
        self.referenced = 0
        self.modified = 0
        self.load = 0
        self.last = 0
        self.uses = 0
        self.age = 0
        self.accessed = False

    def label(self):
        return f"P{self.pid}:{self.number}"


class Process:
    def __init__(self, pid, page_count):
        self.pid = pid
        self.page_count = page_count
        self.pages = [Page(pid, number) for number in range(page_count)]
        self.faults = 0
        self.writebacks = 0
        self.segfaults = 0
        self.protfaults = 0
        self.resident = 0
        self.peak = 0
        self.hand = 0
        self.exited = False
        self.history = []


class Tlb:
    def __init__(self, entries, set_count):
        self.capacity = entries // set_count
        self.sets = [[] for _ in range(set_count)]

    def set_of(self, page):
        return self.sets[page.number % len(self.sets)]

    def lookup(self, page):
        entries = self.set_of(page)
        if page not in entries:
            return False
        entries.remove(page)
        entries.insert(0, page)
        return True

    def insert(self, page):
        entries = self.set_of(page)
        if len(entries) == self.capacity:
            entries.pop()
        entries.insert(0, page)

    def remove(self, page):
        entries = self.set_of(page)
        if page in entries:
            entries.remove(page)

    def remove_process(self, pid):
        for index, entries in enumerate(self.sets):
            self.sets[index] = [page for page in entries if page.pid != pid]

    def clear(self):
        for entries in self.sets:
            entries.clear()

    def used(self):
        return sum(len(entries) for entries in self.sets)


class Simulation:
    def __init__(self, settings, references):
        self.settings = settings
        self.references = references
        self.position = 0
        self.processes = {}
        self.frames = [None] * settings.frames
        self.tlb = Tlb(settings.tlb, settings.sets)
        self.slots = []
        self.time = 0
        self.faults = 0
        self.zeros = 0
        self.swapins = 0
        self.tlbhits = 0
        self.writebacks = 0
        self.switches = 0
        self.last_pid = None
        self.hand = 0
        self.random_state = settings.seed
        self.fault_history = []

    def declare(self, pid, page_count):
        self.processes[pid] = Process(pid, page_count)

    def ordered_processes(self):
        return [self.processes[pid] for pid in sorted(self.processes)]

    def quota(self, process):
        pids = sorted(self.processes)
        share, extra = divmod(self.settings.frames, len(pids))
        return share + 1 if pids.index(process.pid) < extra else share

    def free_frame(self):
        for frame, page in enumerate(self.frames):
            if page is None:
                return frame
        return None

    def free_slot(self):
        for slot, page in enumerate(self.slots):
            if page is None:
                return slot
        self.slots.append(None)
        return len(self.slots) - 1

    def write_back(self, page):
        self.processes[page.pid].writebacks += 1
        self.writebacks += 1
        page.modified = 0
        if page.slot is None:
            page.slot = self.free_slot()
            self.slots[page.slot] = page

    def next_use(self, page):
        key = (page.pid, page.number)
        for index in range(self.position + 1, len(self.references)):
            if self.references[index] == key:
                return index
        return len(self.references)

    def clock(self, order):
        for frame in order:
            page = self.frames[frame]
            if page.referenced == 0:
                return frame
            page.referenced = 0
        return order[0]

    def enhanced_clock(self, order):
        while True:
            for frame in order:
                page = self.frames[frame]
                if page.referenced == 0 and page.modified == 0:
                    return frame
            for frame in order:
                page = self.frames[frame]
                if page.referenced == 0 and page.modified == 1:
                    return frame
                page.referenced = 0

    def wsclock(self, order):
        for frame in order:
            page = self.frames[frame]
            if page.referenced == 1:
                page.referenced = 0
                page.last = self.time
            elif self.time - page.last > self.settings.tau:
                if page.modified == 0:
                    return frame
                self.write_back(page)
        for frame in order:
            if self.frames[frame].modified == 0:
                return frame
        return order[0]

    def select_clock(self, process, candidates):
        local = self.settings.scope == "LOCAL"
        hand = process.hand if local else self.hand
        count = len(self.frames)
        order = sorted(candidates, key=lambda frame: (frame - hand + count) % count)
        if self.settings.policy == "CLOCK":
            chosen = self.clock(order)
        elif self.settings.policy == "ECLOCK":
            chosen = self.enhanced_clock(order)
        else:
            chosen = self.wsclock(order)
        if local:
            process.hand = (chosen + 1) % count
        else:
            self.hand = (chosen + 1) % count
        return chosen

    def select(self, process, candidates):
        policy = self.settings.policy
        frames = self.frames
        if policy == "FIFO":
            return min(candidates, key=lambda frame: frames[frame].load)
        if policy == "LRU":
            return min(candidates, key=lambda frame: frames[frame].last)
        if policy == "LFU":
            return min(candidates, key=lambda frame: (frames[frame].uses, frames[frame].load))
        if policy == "NRU":
            return min(
                candidates,
                key=lambda frame: (2 * frames[frame].referenced + frames[frame].modified, frame),
            )
        if policy == "AGING":
            return min(candidates, key=lambda frame: (frames[frame].age, frames[frame].load))
        if policy == "RANDOM":
            self.random_state = next_random(self.random_state)
            return candidates[self.random_state % len(candidates)]
        if policy == "OPT":
            return min(candidates, key=lambda frame: (-self.next_use(frames[frame]), frame))
        return self.select_clock(process, candidates)

    def target_frame(self, process):
        if self.settings.scope == "GLOBAL":
            frame = self.free_frame()
            if frame is not None:
                return frame
            candidates = list(range(len(self.frames)))
        else:
            if process.resident < self.quota(process):
                return self.free_frame()
            candidates = [
                frame for frame, page in enumerate(self.frames)
                if page is not None and page.pid == process.pid
            ]
        unlocked = [frame for frame in candidates if not self.frames[frame].locked]
        if unlocked:
            candidates = unlocked
        return self.select(process, candidates)

    def evict(self, frame):
        victim = self.frames[frame]
        self.frames[frame] = None
        victim.frame = None
        self.processes[victim.pid].resident -= 1
        self.tlb.remove(victim)
        if victim.modified == 0:
            return False
        self.write_back(victim)
        return True

    def fault(self, process, page):
        process.faults += 1
        self.faults += 1
        if page.slot is None:
            self.zeros += 1
            result = "FAULT ZERO"
        else:
            self.swapins += 1
            result = "FAULT SWAPIN"
        frame = self.target_frame(process)
        victim = self.frames[frame]
        if victim is not None:
            result += f" evict={victim.label()}"
            if self.evict(frame):
                result += " writeback"
        self.frames[frame] = page
        page.frame = frame
        page.load = self.time
        page.uses = 0
        page.modified = 0
        page.age = 0
        process.resident += 1
        process.peak = max(process.peak, process.resident)
        return result

    def timer_interrupt(self):
        for page in self.frames:
            if page is not None:
                page.age = page.age // 2 + 128 * page.referenced
                page.referenced = 0

    def access(self, pid, op, address, position):
        self.position = position
        self.time += 1
        process = self.processes[pid]
        switched = self.last_pid is not None and self.last_pid != pid
        if switched:
            self.switches += 1
            if self.settings.asid == "OFF":
                self.tlb.clear()
        self.last_pid = pid
        number, offset = divmod(address, self.settings.page)
        page = process.pages[number]
        faulted = False
        if self.tlb.lookup(page):
            self.tlbhits += 1
            result = "TLBHIT"
        else:
            if page.frame is not None:
                result = "HIT"
            else:
                result = self.fault(process, page)
                faulted = True
            self.tlb.insert(page)
        page.referenced = 1
        if op == "W":
            page.modified = 1
        page.last = self.time
        page.uses += 1
        page.accessed = True
        process.history.append(number)
        self.fault_history.append(faulted)
        physical = page.frame * self.settings.page + offset
        line = (
            f"t={self.time} P{pid} {op} {hex_text(address)} page={number} "
            f"frame={page.frame} phys={hex_text(physical)} {result}"
        )
        if switched:
            line += " switch"
        lines = [line]
        if self.settings.tick > 0 and self.time % self.settings.tick == 0:
            self.timer_interrupt()
            lines.append(f"t={self.time} tick")
        return lines

    def exit_process(self, pid):
        freed = 0
        for frame, page in enumerate(self.frames):
            if page is not None and page.pid == pid:
                self.frames[frame] = None
                page.frame = None
                freed += 1
        self.tlb.remove_process(pid)
        released = 0
        for slot, page in enumerate(self.slots):
            if page is not None and page.pid == pid:
                self.slots[slot] = None
                page.slot = None
                released += 1
        process = self.processes[pid]
        process.resident = 0
        process.exited = True
        return freed, released

    def clean(self):
        written = 0
        for page in self.frames:
            if page is not None and page.modified == 1:
                self.write_back(page)
                written += 1
        return written

    def set_lock(self, pid, first, last, locked):
        for page in self.processes[pid].pages[first:last + 1]:
            page.locked = locked


class Pager:
    def __init__(self):
        self.simulation = None
        self.trace = False
        self.position = 0
        self.events = []
        self.output = []

    def emit(self, *parts):
        self.output.append(" ".join(str(part) for part in parts))

    def require_system(self):
        if self.simulation is None:
            raise CommandError("no system")

    def require_process(self, pid):
        processes = self.simulation.processes
        if pid not in processes:
            raise CommandError(f"unknown process {pid}")
        if processes[pid].exited:
            raise CommandError(f"process {pid} exited")
        return processes[pid]

    def start_system(self, arguments, accesses):
        self.simulation = None
        settings = parse_settings(arguments)
        references = [(access.pid, access.address // settings.page) for access in accesses]
        self.simulation = Simulation(settings, references)
        self.trace = False
        self.position = 0
        self.events = []
        self.emit(settings.describe())

    def access_line(self, access):
        self.require_system()
        position = self.position
        self.position += 1
        process = self.require_process(access.pid)
        page_size = self.simulation.settings.page
        if access.address >= process.page_count * page_size:
            process.segfaults += 1
            self.emit("SEGFAULT", f"P{access.pid}", hex_text(access.address))
            return
        if access.op == "W" and process.pages[access.address // page_size].readonly:
            process.protfaults += 1
            self.emit("PROTFAULT", f"P{access.pid}", hex_text(access.address))
            return
        lines = self.simulation.access(access.pid, access.op, access.address, position)
        self.events.append(("ACCESS", access.pid, access.op, access.address))
        if self.trace:
            self.output.extend(lines)

    def declare_process(self, arguments):
        pid, page_count = int(arguments[0]), int(arguments[1])
        simulation = self.simulation
        if self.position > 0:
            raise CommandError("processes are fixed")
        if pid in simulation.processes:
            raise CommandError(f"duplicate process {pid}")
        if not 1 <= page_count <= MAX_PAGE_COUNT:
            raise CommandError("invalid page count")
        declared = len(simulation.processes)
        local = simulation.settings.scope == "LOCAL"
        if declared >= MAX_PROCESSES or (local and declared >= simulation.settings.frames):
            raise CommandError("too many processes")
        simulation.declare(pid, page_count)

    def exit_process(self, arguments):
        process = self.require_process(int(arguments[0]))
        freed, released = self.simulation.exit_process(process.pid)
        self.events.append(("EXIT", process.pid))
        self.emit("EXIT", f"P{process.pid}", f"freed={freed}", f"slots={released}")

    def page_range(self, arguments):
        process = self.require_process(int(arguments[0]))
        first, last = int(arguments[1]), int(arguments[2])
        if first > last or last >= process.page_count:
            raise CommandError("invalid page range")
        return process, first, last

    def protect(self, arguments):
        process, first, last = self.page_range(arguments)
        for page in process.pages[first:last + 1]:
            page.readonly = arguments[3] == "RO"

    def change_lock(self, arguments, locked):
        process, first, last = self.page_range(arguments)
        self.simulation.set_lock(process.pid, first, last, locked)
        self.events.append(("LOCK", process.pid, first, last, locked))

    def lock(self, arguments):
        self.change_lock(arguments, True)

    def unlock(self, arguments):
        self.change_lock(arguments, False)

    def set_trace(self, arguments):
        self.trace = arguments[0] == "ON"

    def summary(self, arguments):
        simulation = self.simulation
        settings = simulation.settings
        processes = simulation.ordered_processes()
        self.emit(
            "SUMMARY", f"policy={settings.policy}", f"scope={settings.scope}",
            f"time={simulation.time}",
        )
        self.emit(
            "total", f"faults={simulation.faults}", f"zero={simulation.zeros}",
            f"swapin={simulation.swapins}",
            f"faultrate={ratio_text(simulation.faults, simulation.time)}",
            f"tlbhits={simulation.tlbhits}",
            f"tlbrate={ratio_text(simulation.tlbhits, simulation.time)}",
            f"writebacks={simulation.writebacks}", f"switches={simulation.switches}",
            f"segfaults={sum(process.segfaults for process in processes)}",
            f"protfaults={sum(process.protfaults for process in processes)}",
        )
        for process in processes:
            parts = [
                f"P{process.pid}", f"accesses={len(process.history)}",
                f"faults={process.faults}", f"writebacks={process.writebacks}",
                f"segfaults={process.segfaults}", f"protfaults={process.protfaults}",
                f"resident={process.resident}", f"peak={process.peak}",
            ]
            if settings.scope == "LOCAL":
                parts.append(f"quota={simulation.quota(process)}")
            if process.exited:
                parts.append("exited")
            self.emit(*parts)

    def show_frames(self, arguments):
        simulation = self.simulation
        settings = simulation.settings
        used = sum(page is not None for page in simulation.frames)
        self.emit("FRAMES", f"used={used}/{settings.frames}")
        for frame, page in enumerate(simulation.frames):
            if page is None:
                self.emit(frame, "free")
                continue
            parts = [
                frame, page.label(), f"R={page.referenced}", f"M={page.modified}",
                f"load={page.load}", f"last={page.last}", f"uses={page.uses}",
                f"age={page.age}",
            ]
            if page.locked:
                parts.append("locked")
            self.emit(*parts)
        if settings.policy in CLOCK_POLICIES:
            if settings.scope == "GLOBAL":
                self.emit(f"hand={simulation.hand}")
            else:
                processes = simulation.ordered_processes()
                self.emit("hand", *(f"P{process.pid}={process.hand}" for process in processes))

    def page_table(self, arguments):
        process = self.require_process(int(arguments[0]))
        self.emit(
            "PAGETABLE", f"P{process.pid}", f"pages={process.page_count}",
            f"resident={process.resident}",
        )
        for page in process.pages:
            if not page.accessed:
                continue
            if page.frame is not None:
                parts = [
                    page.number, f"frame={page.frame}",
                    f"R={page.referenced}", f"M={page.modified}",
                ]
            elif page.slot is not None:
                parts = [page.number, f"swap={page.slot}"]
            else:
                parts = [page.number, "zero"]
            if page.readonly:
                parts.append("RO")
            if page.locked:
                parts.append("locked")
            self.emit(*parts)

    def show_tlb(self, arguments):
        settings = self.simulation.settings
        tlb = self.simulation.tlb
        self.emit("TLB", f"used={tlb.used()}/{settings.tlb}", f"sets={settings.sets}")
        for index, entries in enumerate(tlb.sets):
            self.emit(f"set {index}:", *(f"{page.label()}->{page.frame}" for page in entries))

    def show_swap(self, arguments):
        used = [(slot, page) for slot, page in enumerate(self.simulation.slots) if page is not None]
        self.emit("SWAP", f"used={len(used)}")
        for slot, page in used:
            self.emit(slot, page.label())

    def clean(self, arguments):
        written = self.simulation.clean()
        self.events.append(("CLEAN",))
        self.emit(f"CLEAN written={written}")

    def rerun(self, policy, frames):
        current = self.simulation
        settings = current.settings.variant(policy, frames)
        accesses = [values for kind, *values in self.events if kind == "ACCESS"]
        references = [(pid, address // settings.page) for pid, _, address in accesses]
        simulation = Simulation(settings, references)
        for process in current.ordered_processes():
            simulation.declare(process.pid, process.page_count)
        position = 0
        for kind, *values in self.events:
            if kind == "ACCESS":
                pid, op, address = values
                simulation.access(pid, op, address, position)
                position += 1
            elif kind == "EXIT":
                simulation.exit_process(values[0])
            elif kind == "CLEAN":
                simulation.clean()
            else:
                pid, first, last, locked = values
                simulation.set_lock(pid, first, last, locked)
        return simulation

    def compare(self, arguments):
        frames = self.simulation.settings.frames
        self.emit("COMPARE", f"accesses={self.simulation.time}", f"frames={frames}")
        results = []
        for index, policy in enumerate(POLICIES):
            rerun = self.rerun(policy, frames)
            results.append((rerun.faults, rerun.writebacks, index, policy))
            self.emit(
                policy, f"faults={rerun.faults}", f"writebacks={rerun.writebacks}",
                f"tlbhits={rerun.tlbhits}",
            )
        results.sort()
        self.emit("ranking", *(policy for _, _, _, policy in results))

    def curve(self, arguments):
        policy, low, high = arguments[0], int(arguments[1]), int(arguments[2])
        if policy not in POLICIES:
            raise CommandError("unknown policy")
        simulation = self.simulation
        local = simulation.settings.scope == "LOCAL"
        if not 1 <= low <= high <= MAX_FRAMES or (local and low < len(simulation.processes)):
            raise CommandError("invalid frame range")
        self.emit("CURVE", policy, f"frames={low}..{high}")
        previous = None
        for frames in range(low, high + 1):
            faults = self.rerun(policy, frames).faults
            line = f"F={frames} faults={faults}"
            if previous is not None and faults > previous:
                line += " ANOMALY"
            self.emit(line)
            previous = faults

    def effective_access_time(self, arguments):
        lookup, memory, disk = (int(value) for value in arguments)
        simulation = self.simulation
        accesses = simulation.time
        if accesses == 0:
            self.emit("EAT accesses=0")
            return
        total = (
            lookup * accesses
            + memory * (2 * accesses - simulation.tlbhits)
            + disk * (simulation.swapins + simulation.writebacks)
        )
        average = 100 * total // accesses
        self.emit(
            "EAT", f"accesses={accesses}", f"total={total}",
            f"average={average // 100}.{average % 100:02d}",
        )

    def timeline(self, arguments):
        window = int(arguments[0])
        if window < 1:
            raise CommandError("invalid window")
        history = self.simulation.fault_history
        counts = [sum(history[start:start + window]) for start in range(0, len(history), window)]
        self.emit(f"TIMELINE window={window}", *counts)

    def working_set(self, arguments):
        process = self.require_process(int(arguments[0]))
        window = int(arguments[1])
        if window < 1:
            raise CommandError("invalid window")
        pages = sorted(set(process.history[-window:]))
        self.emit("WSET", f"P{process.pid}", f"window={window}", f"size={len(pages)}", *pages)

    def hot_pages(self, arguments):
        process = self.require_process(int(arguments[0]))
        count = int(arguments[1])
        if count < 1:
            raise CommandError("invalid count")
        ranked = sorted(Counter(process.history).items(), key=lambda item: (-item[1], item[0]))
        hot = [f"{number}:{total}" for number, total in ranked[:count]]
        self.emit("HOT", f"P{process.pid}", *hot)

    def execute(self, words):
        self.require_system()
        handlers = {
            "PROCESS": self.declare_process,
            "EXIT": self.exit_process,
            "PROTECT": self.protect,
            "LOCK": self.lock,
            "UNLOCK": self.unlock,
            "TRACE": self.set_trace,
            "SUMMARY": self.summary,
            "FRAMES": self.show_frames,
            "PAGETABLE": self.page_table,
            "TLB": self.show_tlb,
            "SWAP": self.show_swap,
            "CLEAN": self.clean,
            "COMPARE": self.compare,
            "CURVE": self.curve,
            "EAT": self.effective_access_time,
            "TIMELINE": self.timeline,
            "WSET": self.working_set,
            "HOT": self.hot_pages,
        }
        handlers[words[0]](words[1:])

    def run(self, items):
        for index, item in enumerate(items):
            try:
                if isinstance(item, Access):
                    self.access_line(item)
                elif item[0] == "SYSTEM":
                    self.start_system(item[1:], segment_accesses(items, index + 1))
                else:
                    self.execute(item)
            except CommandError as error:
                self.emit("ERROR", error)


def main():
    count = int(sys.stdin.readline())
    lines = [sys.stdin.readline().rstrip("\n") for _ in range(count)]
    pager = Pager()
    pager.run(expand(lines))
    if pager.output:
        sys.stdout.write("\n".join(pager.output) + "\n")


if __name__ == "__main__":
    main()
