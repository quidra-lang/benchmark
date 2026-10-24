from itertools import combinations
import sys


EVENT_KINDS = (
    "granted", "blocked", "unblocked", "released", "finished", "aborted", "cancelled"
)
TABLE_HEADINGS = ("Allocation", "Max", "Need", "Request")
HEADING_WIDTH = 9


class CommandError(Exception):
    pass


def type_name(index):
    return chr(ord("A") + index)


def type_list(indices):
    return ",".join(type_name(index) for index in indices)


def process_name(number):
    return f"P{number}"


def process_list(numbers):
    return " ".join(process_name(number) for number in numbers)


def blocked_message(number):
    return f"process {process_name(number)} is blocked"


def vector_text(vector):
    return "(" + ",".join(str(value) for value in vector) + ")"


def fits(vector, limit):
    return all(value <= bound for value, bound in zip(vector, limit))


def add(first, second):
    return [a + b for a, b in zip(first, second)]


def subtract(first, second):
    return [a - b for a, b in zip(first, second)]


def is_zero(vector):
    return all(value == 0 for value in vector)


def unit_vector(size, index, amount):
    vector = [0] * size
    vector[index] = amount
    return vector


def truncated(numerator, denominator, digits):
    scale = 10 ** digits
    value = numerator * scale // denominator
    return f"{value // scale}.{value % scale:0{digits}d}"


def order_violation(allocation, vector):
    held = [index for index, value in enumerate(allocation) if value > 0]
    if not held:
        return False
    return any(value > 0 for value in vector[:held[-1] + 1])


def table_form(values, widths):
    return " ".join(str(value).rjust(width) for value, width in zip(values, widths))


def table_row(heading, contents, widths):
    line = heading.ljust(HEADING_WIDTH)
    for content, width in zip(contents, widths):
        line += "  " + content.ljust(width)
    return line.rstrip()


class Process:
    def __init__(self, number, maximum, created):
        self.number = number
        self.maximum = maximum
        self.allocation = [0] * len(maximum)
        self.created = created

    def need(self):
        return subtract(self.maximum, self.allocation)

    def copy(self):
        process = Process(self.number, list(self.maximum), self.created)
        process.allocation = list(self.allocation)
        return process


class WaitingRequest:
    def __init__(self, process, vector, since):
        self.process = process
        self.vector = vector
        self.since = since


class Event:
    def __init__(self, time, kind, process, vector, waited):
        self.time = time
        self.kind = kind
        self.process = process
        self.vector = vector
        self.waited = waited

    def text(self):
        line = f"t={self.time} {self.kind} {process_name(self.process)} {vector_text(self.vector)}"
        if self.kind == "unblocked":
            line += f" waited {self.waited}"
        return line


class Candidate:
    def __init__(self, number, demand, allocation, finished):
        self.number = number
        self.demand = demand
        self.allocation = allocation
        self.finished = finished


def next_ready(candidates, work):
    for candidate in candidates:
        if not candidate.finished and fits(candidate.demand, work):
            return candidate
    return None


class SystemState:
    def __init__(self, total):
        self.total = list(total)
        self.available = list(total)
        self.processes = {}
        self.queue = []
        self.history = []

    def copy(self):
        state = SystemState(self.total)
        state.available = list(self.available)
        state.processes = {
            number: process.copy() for number, process in self.processes.items()
        }
        state.queue = list(self.queue)
        state.history = list(self.history)
        return state

    def type_count(self):
        return len(self.total)

    def ordered(self):
        return [self.processes[number] for number in sorted(self.processes)]

    def waiting(self, number):
        for entry in self.queue:
            if entry.process == number:
                return entry
        return None

    def request_of(self, process):
        entry = self.waiting(process.number)
        if entry is None:
            return [0] * self.type_count()
        return entry.vector

    def held_units(self, numbers):
        return sum(sum(self.processes[number].allocation) for number in numbers)


class SequenceSearch:
    def __init__(self, processes, limit):
        self.processes = processes
        self.needs = [process.need() for process in processes]
        self.used = [False] * len(processes)
        self.prefix = []
        self.limit = limit
        self.found = []

    def count(self, work):
        if len(self.prefix) == len(self.processes):
            if len(self.found) < self.limit:
                self.found.append(list(self.prefix))
            return 1
        total = 0
        for index, process in enumerate(self.processes):
            if not self.used[index] and fits(self.needs[index], work):
                self.used[index] = True
                self.prefix.append(process.number)
                total += self.count(add(work, process.allocation))
                self.prefix.pop()
                self.used[index] = False
        return total


def wait_cycles(path, edges, cycles):
    start = path[0]
    for target in edges[path[-1]]:
        if target == start:
            cycles.append(path + [start])
        elif target > start and target not in path:
            path.append(target)
            wait_cycles(path, edges, cycles)
            path.pop()


def resource_cycles(path, types, requests, holders, cycles):
    start = path[0]
    for index in requests[path[-1]]:
        holder = holders[index]
        if holder == start:
            cycles.append(resource_cycle_text(path, types + [index]))
        elif holder is not None and holder > start and holder not in path:
            path.append(holder)
            types.append(index)
            resource_cycles(path, types, requests, holders, cycles)
            path.pop()
            types.pop()


def resource_cycle_text(path, types):
    parts = []
    for number, index in zip(path, types):
        parts.append(process_name(number))
        parts.append(type_name(index))
    parts.append(process_name(path[0]))
    return "cycle: " + " -> ".join(parts)


class DeadlockManager:
    def __init__(self):
        self.state = SystemState([])
        self.mode = "AVOID"
        self.policy = "ALLOC"
        self.tracing = False
        self.autodetect = False
        self.snapshots = {}
        self.command = 0
        self.output = []

    def emit(self, line):
        self.output.append(line)

    def vector(self, texts):
        if len(texts) != self.state.type_count():
            raise CommandError("wrong vector length")
        return [int(text) for text in texts]

    def require_process(self, number):
        process = self.state.processes.get(number)
        if process is None:
            raise CommandError(f"unknown process {process_name(number)}")
        return process

    def require_unblocked(self, number):
        process = self.require_process(number)
        if self.state.waiting(number) is not None:
            raise CommandError(blocked_message(number))
        return process

    def record(self, kind, number, vector, waited=0):
        self.state.history.append(Event(self.command, kind, number, vector, waited))

    def reduction(self, label, work, candidates, traced):
        order = []
        chosen = next_ready(candidates, work)
        while chosen is not None:
            chosen.finished = True
            work = add(work, chosen.allocation)
            order.append(chosen.number)
            if traced:
                name = process_name(chosen.number)
                self.emit(f"{label} {name} can finish, work={vector_text(work)}")
            chosen = next_ready(candidates, work)
        remaining = [candidate.number for candidate in candidates if not candidate.finished]
        if traced and remaining:
            self.emit(
                f"{label} stuck work={vector_text(work)} remaining {process_list(remaining)}"
            )
        return order, remaining

    def safety_check(self, available, traced):
        candidates = [
            Candidate(process.number, process.need(), process.allocation, False)
            for process in self.state.ordered()
        ]
        if traced:
            self.emit(f"[safety] start work={vector_text(available)}")
        return self.reduction("[safety]", available, candidates, traced)

    def detect(self, traced, excluded=()):
        work = self.state.available
        candidates = []
        for process in self.state.ordered():
            if process.number in excluded:
                work = add(work, process.allocation)
            else:
                candidates.append(Candidate(
                    process.number, self.state.request_of(process),
                    process.allocation, is_zero(process.allocation),
                ))
        if traced:
            idle = [candidate.number for candidate in candidates if candidate.finished]
            line = f"[detect] start work={vector_text(work)}"
            if idle:
                line += " idle " + process_list(idle)
            self.emit(line)
        return self.reduction("[detect]", work, candidates, traced)[1]

    def rejection(self, process, vector):
        if self.state.waiting(process.number) is not None:
            return blocked_message(process.number)
        if is_zero(vector):
            return "zero vector"
        if not fits(vector, process.need()):
            return "request exceeds need"
        if self.mode == "ORDER" and order_violation(process.allocation, vector):
            return "resource order violation"
        return None

    def decision(self, process, vector, traced):
        available = self.state.available
        if not fits(vector, available):
            return "insufficient resources", []
        if self.mode != "AVOID":
            return None, []
        process.allocation = add(process.allocation, vector)
        sequence, remaining = self.safety_check(subtract(available, vector), traced)
        process.allocation = subtract(process.allocation, vector)
        if remaining:
            return "unsafe state", []
        return None, sequence

    def would_grant(self, process, vector):
        if self.rejection(process, vector) is not None:
            return False
        reason, _ = self.decision(process, vector, False)
        return reason is None

    def allocate(self, process, vector):
        process.allocation = add(process.allocation, vector)
        self.state.available = subtract(self.state.available, vector)

    def retry(self):
        remaining = []
        for entry in self.state.queue:
            process = self.state.processes[entry.process]
            reason, _ = self.decision(process, entry.vector, self.tracing)
            if reason is None:
                self.allocate(process, entry.vector)
                self.emit(f"unblocked {process_name(entry.process)} {vector_text(entry.vector)}")
                self.record("unblocked", entry.process, entry.vector, self.command - entry.since)
            else:
                remaining.append(entry)
        self.state.queue = remaining

    def terminate(self, process, kind):
        state = self.state
        state.queue = [entry for entry in state.queue if entry.process != process.number]
        state.available = add(state.available, process.allocation)
        del state.processes[process.number]
        released = vector_text(process.allocation)
        self.emit(f"{kind} {process_name(process.number)} released {released}")
        self.record(kind, process.number, process.allocation)

    def resources(self, arguments):
        self.state = SystemState([int(text) for text in arguments])
        self.emit(f"resources {vector_text(self.state.total)}")

    def set_mode(self, arguments):
        self.mode = arguments[0]
        self.emit(f"mode {self.mode}")

    def set_policy(self, arguments):
        self.policy = arguments[0]
        self.emit(f"policy {self.policy}")

    def set_trace(self, arguments):
        self.tracing = arguments[0] == "ON"
        self.emit(f"trace {arguments[0]}")

    def set_autodetect(self, arguments):
        self.autodetect = arguments[0] == "ON"
        self.emit(f"autodetect {arguments[0]}")

    def create_process(self, arguments):
        number = int(arguments[0])
        vector = self.vector(arguments[1:])
        if number in self.state.processes:
            raise CommandError(f"duplicate process {process_name(number)}")
        if not fits(vector, self.state.total):
            raise CommandError("max exceeds total")
        self.state.processes[number] = Process(number, vector, self.command)
        self.emit(f"process {process_name(number)} max {vector_text(vector)}")

    def claim(self, arguments):
        number = int(arguments[0])
        vector = self.vector(arguments[1:])
        process = self.require_unblocked(number)
        if not fits(process.allocation, vector):
            raise CommandError("claim below allocation")
        if not fits(vector, self.state.total):
            raise CommandError("max exceeds total")
        if self.mode == "AVOID":
            previous = process.maximum
            process.maximum = vector
            _, remaining = self.safety_check(self.state.available, self.tracing)
            process.maximum = previous
            if remaining:
                raise CommandError("claim makes state unsafe")
        process.maximum = vector
        self.emit(f"claim {process_name(number)} max {vector_text(vector)}")
        self.retry()

    def add_resources(self, arguments):
        vector = self.vector(arguments)
        if is_zero(vector):
            raise CommandError("zero vector")
        state = self.state
        state.total = add(state.total, vector)
        state.available = add(state.available, vector)
        self.emit(f"added {vector_text(vector)} total {vector_text(state.total)}")
        self.retry()

    def remove_resources(self, arguments):
        vector = self.vector(arguments)
        state = self.state
        if is_zero(vector):
            raise CommandError("zero vector")
        if not fits(vector, state.available):
            raise CommandError("remove exceeds available")
        total = subtract(state.total, vector)
        if any(value == 0 for value in total):
            raise CommandError("total must stay positive")
        if any(not fits(process.maximum, total) for process in state.ordered()):
            raise CommandError("max exceeds total")
        available = subtract(state.available, vector)
        if self.mode == "AVOID":
            _, remaining = self.safety_check(available, self.tracing)
            if remaining:
                raise CommandError("removal makes state unsafe")
        state.total = total
        state.available = available
        self.emit(f"removed {vector_text(vector)} total {vector_text(total)}")

    def request(self, arguments):
        number = int(arguments[0])
        vector = self.vector(arguments[1:])
        process = self.require_process(number)
        rejection = self.rejection(process, vector)
        if rejection is not None:
            raise CommandError(rejection)
        reason, _ = self.decision(process, vector, self.tracing)
        name = process_name(number)
        if reason is None:
            self.allocate(process, vector)
            self.emit(f"granted {name} {vector_text(vector)}")
            self.record("granted", number, vector)
            return
        self.state.queue.append(WaitingRequest(number, vector, self.command))
        self.emit(f"blocked {name} {vector_text(vector)}: {reason}")
        self.record("blocked", number, vector)
        if self.autodetect:
            deadlocked = self.detect(self.tracing)
            if deadlocked:
                self.emit("deadlock detected: " + process_list(deadlocked))

    def whatif(self, arguments):
        number = int(arguments[0])
        vector = self.vector(arguments[1:])
        process = self.require_process(number)
        prefix = f"whatif {process_name(number)} {vector_text(vector)}"
        rejection = self.rejection(process, vector)
        if rejection is not None:
            self.emit(f"{prefix}: rejected ({rejection})")
            return
        reason, sequence = self.decision(process, vector, self.tracing)
        if reason is not None:
            self.emit(f"{prefix}: blocked ({reason})")
        elif self.mode == "AVOID":
            self.emit(f"{prefix}: granted, safe sequence {process_list(sequence)}")
        else:
            self.emit(f"{prefix}: granted")

    def release(self, arguments):
        number = int(arguments[0])
        vector = self.vector(arguments[1:])
        process = self.require_unblocked(number)
        if is_zero(vector):
            raise CommandError("zero vector")
        if not fits(vector, process.allocation):
            raise CommandError("release exceeds allocation")
        process.allocation = subtract(process.allocation, vector)
        self.state.available = add(self.state.available, vector)
        self.emit(f"released {process_name(number)} {vector_text(vector)}")
        self.record("released", number, vector)
        self.retry()

    def finish(self, arguments):
        process = self.require_unblocked(int(arguments[0]))
        self.terminate(process, "finished")
        self.retry()

    def abort(self, arguments):
        process = self.require_process(int(arguments[0]))
        self.terminate(process, "aborted")
        self.retry()

    def cancel(self, arguments):
        number = int(arguments[0])
        self.require_process(number)
        entry = self.state.waiting(number)
        if entry is None:
            raise CommandError(f"process {process_name(number)} is not blocked")
        self.state.queue.remove(entry)
        self.emit(f"cancelled {process_name(number)} {vector_text(entry.vector)}")
        self.record("cancelled", number, entry.vector)

    def maxgrant(self, arguments):
        number = int(arguments[0])
        process = self.require_unblocked(number)
        need = process.need()
        size = self.state.type_count()
        amounts = []
        for index in range(size):
            best = 0
            for amount in range(need[index], 0, -1):
                if self.would_grant(process, unit_vector(size, index, amount)):
                    best = amount
                    break
            amounts.append(best)
        self.emit(f"maxgrant {process_name(number)}: {vector_text(amounts)}")

    def safe(self, arguments):
        if not self.state.processes:
            self.emit("safe: no processes")
            return
        sequence, remaining = self.safety_check(self.state.available, self.tracing)
        if remaining:
            self.emit(f"unsafe: {process_list(remaining)} cannot finish")
        else:
            self.emit(f"safe: {process_list(sequence)}")

    def sequences(self, arguments):
        if not self.state.processes:
            self.emit("safe sequences: no processes")
            return
        search = SequenceSearch(self.state.ordered(), int(arguments[0]))
        count = search.count(self.state.available)
        self.emit(f"safe sequences: {count}")
        for order in search.found:
            self.emit(process_list(order))

    def deficit(self, arguments):
        state = self.state
        processes = state.ordered()
        size = state.type_count()
        results = []
        for index in range(size):
            limit = sum(process.need()[index] for process in processes)
            result = "-"
            for extra in range(limit + 1):
                available = add(state.available, unit_vector(size, index, extra))
                _, remaining = self.safety_check(available, False)
                if not remaining:
                    result = str(extra)
                    break
            results.append(result)
        self.emit("deficit: (" + ",".join(results) + ")")

    def show_state(self, arguments):
        state = self.state
        widths = [len(str(value)) for value in state.total]
        names = table_form([type_name(index) for index in range(len(widths))], widths)
        columns = [max(len(heading), len(names)) for heading in TABLE_HEADINGS]
        self.emit(table_row("Process", TABLE_HEADINGS, columns))
        self.emit(table_row("", [names] * len(columns), columns))
        for process in state.ordered():
            vectors = (
                process.allocation, process.maximum,
                process.need(), state.request_of(process),
            )
            contents = [table_form(vector, widths) for vector in vectors]
            self.emit(table_row(process_name(process.number), contents, columns))
        self.emit(table_row("Available", [table_form(state.available, widths), "", "", ""], columns))
        self.emit(table_row("Total", [table_form(state.total, widths), "", "", ""], columns))
        if not state.queue:
            self.emit("blocked queue: empty")
            return
        entries = [
            f"{process_name(entry.process)} {vector_text(entry.vector)} since t={entry.since}"
            for entry in state.queue
        ]
        self.emit("blocked queue: " + ", ".join(entries))

    def stats(self, arguments):
        state = self.state
        for index in range(state.type_count()):
            total = state.total[index]
            used = total - state.available[index]
            requested = sum(entry.vector[index] for entry in state.queue)
            self.emit(
                f"{type_name(index)}: allocated {used}/{total} "
                f"({truncated(used * 100, total, 1)}%), requested {requested}"
            )
        counts = [
            f"{kind} {sum(event.kind == kind for event in state.history)}"
            for kind in EVENT_KINDS
        ]
        self.emit("events: " + ", ".join(counts))
        waits = [event.waited for event in state.history if event.kind == "unblocked"]
        if not waits:
            self.emit("waits: none")
            return
        total_wait = sum(waits)
        self.emit(
            f"waits: {len(waits)} unblocked, total {total_wait}, "
            f"average {truncated(total_wait, len(waits), 2)}"
        )

    def detect_deadlock(self, arguments):
        deadlocked = self.detect(self.tracing)
        if deadlocked:
            self.emit("deadlocked: " + process_list(deadlocked))
        else:
            self.emit("no deadlock")

    def victims(self, arguments):
        deadlocked = self.detect(False)
        if not deadlocked:
            self.emit("no deadlock")
            return
        for size in range(1, len(deadlocked) + 1):
            groups = [list(group) for group in combinations(deadlocked, size)]
            groups.sort(key=lambda group: (self.state.held_units(group), group))
            for group in groups:
                if not self.detect(False, group):
                    self.emit("victims: " + process_list(group))
                    return

    def choose_victim(self, deadlocked):
        candidates = [self.state.processes[number] for number in deadlocked]
        if self.policy == "ALLOC":
            return min(
                candidates, key=lambda process: (sum(process.allocation), -process.number)
            )
        if self.policy == "NEED":
            return max(candidates, key=lambda process: (sum(process.need()), process.number))
        return max(candidates, key=lambda process: process.created)

    def recover(self, arguments):
        if arguments:
            self.recover_all()
            return
        aborted = 0
        deadlocked = self.detect(self.tracing)
        while deadlocked:
            self.terminate(self.choose_victim(deadlocked), "aborted")
            self.retry()
            aborted += 1
            deadlocked = self.detect(self.tracing)
        if aborted:
            self.emit(f"recovered: {aborted} aborted")
        else:
            self.emit("no deadlock")

    def recover_all(self):
        deadlocked = self.detect(self.tracing)
        if not deadlocked:
            self.emit("no deadlock")
            return
        for number in deadlocked:
            self.terminate(self.state.processes[number], "aborted")
        self.retry()
        self.emit(f"recovered: {len(deadlocked)} aborted")

    def wait_graph(self, arguments):
        state = self.state
        processes = state.ordered()
        edges = {process.number: [] for process in processes}
        for process in processes:
            entry = state.waiting(process.number)
            if entry is None:
                continue
            short = [
                index for index, value in enumerate(entry.vector)
                if value > state.available[index]
            ]
            for other in processes:
                if other is process:
                    continue
                label = [index for index in short if other.allocation[index] > 0]
                if label:
                    edges[process.number].append(other.number)
                    self.emit(
                        f"{process_name(process.number)} -> "
                        f"{process_name(other.number)} on {type_list(label)}"
                    )
        if not any(edges.values()):
            self.emit("no wait edges")
        cycles = []
        for process in processes:
            wait_cycles([process.number], edges, cycles)
        for cycle in cycles:
            self.emit("cycle: " + " -> ".join(process_name(number) for number in cycle))
        if not cycles:
            self.emit("no cycles")

    def resource_graph(self, arguments):
        state = self.state
        if any(value != 1 for value in state.total):
            raise CommandError("not single-instance")
        processes = state.ordered()
        size = state.type_count()
        holders = [None] * size
        for process in processes:
            for index in range(size):
                if process.allocation[index] > 0:
                    holders[index] = process.number
        for index in range(size):
            if holders[index] is not None:
                self.emit(f"assign {type_name(index)} -> {process_name(holders[index])}")
        requests = {}
        for process in processes:
            requested = state.request_of(process)
            requests[process.number] = [index for index in range(size) if requested[index] > 0]
            for index in requests[process.number]:
                self.emit(f"request {process_name(process.number)} -> {type_name(index)}")
        for process in processes:
            requested = state.request_of(process)
            need = process.need()
            for index in range(size):
                if need[index] > 0 and requested[index] == 0:
                    self.emit(f"claim {process_name(process.number)} -> {type_name(index)}")
        cycles = []
        for process in processes:
            resource_cycles([process.number], [], requests, holders, cycles)
        for cycle in cycles:
            self.emit(cycle)
        if not cycles:
            self.emit("no cycles")

    def history(self, arguments):
        events = self.state.history
        if arguments:
            key = arguments[0]
            if key.isdigit():
                events = [event for event in events if event.process == int(key)]
            else:
                events = [event for event in events if event.kind == key]
        if not events:
            self.emit("no events")
        for event in events:
            self.emit(event.text())

    def snapshot(self, arguments):
        name = arguments[0]
        self.snapshots[name] = self.state.copy()
        self.emit(f"saved {name}")

    def restore(self, arguments):
        name = arguments[0]
        if name not in self.snapshots:
            raise CommandError(f"unknown snapshot {name}")
        self.state = self.snapshots[name].copy()
        self.emit(f"restored {name}")

    def execute(self, line):
        self.command += 1
        command, *arguments = line.split()
        handlers = {
            "RESOURCES": self.resources,
            "MODE": self.set_mode,
            "POLICY": self.set_policy,
            "TRACE": self.set_trace,
            "AUTODETECT": self.set_autodetect,
            "PROCESS": self.create_process,
            "CLAIM": self.claim,
            "ADD": self.add_resources,
            "REMOVE": self.remove_resources,
            "REQUEST": self.request,
            "WHATIF": self.whatif,
            "RELEASE": self.release,
            "FINISH": self.finish,
            "ABORT": self.abort,
            "CANCEL": self.cancel,
            "MAXGRANT": self.maxgrant,
            "SAFE": self.safe,
            "SEQUENCES": self.sequences,
            "DEFICIT": self.deficit,
            "STATE": self.show_state,
            "STATS": self.stats,
            "DETECT": self.detect_deadlock,
            "VICTIMS": self.victims,
            "RECOVER": self.recover,
            "WAITGRAPH": self.wait_graph,
            "GRAPH": self.resource_graph,
            "HISTORY": self.history,
            "SNAPSHOT": self.snapshot,
            "RESTORE": self.restore,
        }
        try:
            handlers[command](arguments)
        except CommandError as error:
            self.emit(f"error: {error}")


def main():
    manager = DeadlockManager()
    count = int(sys.stdin.readline())
    for _ in range(count):
        manager.execute(sys.stdin.readline().rstrip("\n"))
    sys.stdout.write("\n".join(manager.output) + "\n")


if __name__ == "__main__":
    main()
