from collections import Counter
import sys


ALGORITHMS = ("FCFS", "SJF", "SRTF", "RR", "PRIORITY", "HRRN", "EDF", "LOTTERY", "MLFQ")
PARAMETER_KEYS = ("cs", "q", "k", "s", "seed")
PARAMETER_RANGES = {
    "cs": (0, 5),
    "q": (1, 20),
    "k": (1, 50),
    "s": (0, 500),
    "seed": (1, 2147483646),
}
DEFAULT_PARAMETERS = {"cs": 0, "q": 4, "k": 5, "s": 0, "seed": 1}
ALGORITHM_KEYS = {
    "FCFS": ("cs",),
    "SJF": ("cs",),
    "SRTF": ("cs",),
    "RR": ("cs", "q"),
    "PRIORITY": ("cs", "k"),
    "HRRN": ("cs",),
    "EDF": ("cs",),
    "LOTTERY": ("cs", "q", "seed"),
    "MLFQ": ("cs", "s"),
}
METRICS = ("turnaround", "waiting", "response")
RANK_METRICS = METRICS + ("end", "switches", "missed")
EVENT_KINDS = ("PREEMPT", "EXPIRE", "DEMOTE", "BOOST", "AGE")
TABLE_HEADER = ("ALGO", "TURN", "WAIT", "RESP", "UTIL", "END", "SWITCH", "MISS")
STATE_SYMBOLS = {
    "FUTURE": "-",
    "READY": ".",
    "SWITCH": "s",
    "RUN": "#",
    "IO": "i",
    "DONE": "-",
}
ALLOTMENTS = (4, 8)
LEVELS = 3
MAX_PROCESSES = 10
MAX_ARRIVAL = 200
MAX_PRIORITY = 9
MAX_DEADLINE = 1000
MAX_BURST = 30
MAX_WINDOW = 1000
MAX_SWEEP = 20
TIMELINE_LIMIT = 100
GANTT_GROUP = 8
ID_WIDTH = 8
COLUMN_WIDTH = 8
RANDOM_MULTIPLIER = 48271
RANDOM_MODULUS = 2147483647


def truncated(numerator, denominator):
    hundredths = 100 * numerator // denominator
    return f"{hundredths // 100}.{hundredths % 100:02d}"


def median_text(values):
    ordered = sorted(values)
    middle = len(ordered) // 2
    if len(ordered) % 2 == 1:
        return f"{ordered[middle]}.0"
    doubled = ordered[middle - 1] + ordered[middle]
    return f"{doubled // 2}.{5 * (doubled % 2)}"


def burst_kind(index):
    return "C" if index % 2 == 0 else "I"


def parse_bursts(words):
    if len(words) % 2 == 0:
        return None
    lengths = []
    for index, word in enumerate(words):
        length = int(word[1:])
        if word[0] != burst_kind(index) or not 1 <= length <= MAX_BURST:
            return None
        lengths.append(length)
    return lengths


def notation(params, algorithm=None):
    keys = PARAMETER_KEYS if algorithm is None else ALGORITHM_KEYS[algorithm]
    return " ".join(f"{key}={params[key]}" for key in keys)


def queue_text(queue):
    if not queue:
        return "none"
    return " ".join(job.pid for job in queue)


def table_row(columns):
    cells = [columns[0].ljust(COLUMN_WIDTH)]
    cells.extend(column.rjust(COLUMN_WIDTH) for column in columns[1:])
    return " ".join(cells)


class CommandError(Exception):
    pass


def parse_params(words, algorithm=None, preset=()):
    allowed = PARAMETER_KEYS if algorithm is None else ALGORITHM_KEYS[algorithm]
    specified = set(preset)
    params = dict(DEFAULT_PARAMETERS)
    for word in words:
        key, text = word.split("=")
        if key not in PARAMETER_RANGES:
            raise CommandError(f"unknown key {key}")
        if key not in allowed:
            raise CommandError(f"key {key} not allowed for {algorithm}")
        if key in specified:
            raise CommandError(f"duplicate key {key}")
        minimum, maximum = PARAMETER_RANGES[key]
        value = int(text)
        if not minimum <= value <= maximum:
            raise CommandError(f"invalid {key}")
        specified.add(key)
        params[key] = value
    return params


class RandomState:
    def __init__(self, value):
        self.value = value

    def draw(self, modulus):
        self.value = RANDOM_MULTIPLIER * self.value % RANDOM_MODULUS
        return self.value % modulus


class Process:
    def __init__(self, pid, arrival, priority, bursts):
        self.pid = pid
        self.arrival = arrival
        self.priority = priority
        self.bursts = bursts
        self.deadline = None

    def absolute_deadline(self):
        return self.arrival + self.deadline

    def describe(self):
        deadline = "none" if self.deadline is None else self.deadline
        bursts = ",".join(
            burst_kind(index) + str(length) for index, length in enumerate(self.bursts)
        )
        return (
            f"{self.pid} arrival={self.arrival} priority={self.priority} "
            f"deadline={deadline} bursts={bursts}"
        )


class BurstRecord:
    def __init__(self, length, ready):
        self.length = length
        self.ready = ready
        self.start = None
        self.end = None
        self.slices = 0


class Job:
    def __init__(self, process):
        self.process = process
        self.pid = process.pid
        self.state = "FUTURE"
        self.burst = 0
        self.remaining = process.bursts[0]
        self.effective = process.priority
        self.wait = 0
        self.level = 0
        self.usage = 0
        self.enqueued = 0
        self.start = None
        self.finish = None
        self.records = []
        self.timeline = []

    def advance(self):
        self.burst += 1
        self.remaining = self.process.bursts[self.burst]

    def on_last_burst(self):
        return self.burst == len(self.process.bursts) - 1

    def has_deadline(self):
        return self.process.deadline is not None

    def absolute_deadline(self):
        return self.process.absolute_deadline()

    def tickets(self):
        return 10 - self.process.priority

    def slices(self):
        return sum(record.slices for record in self.records)

    def metrics(self):
        turnaround = self.finish - self.process.arrival
        waiting = turnaround - sum(self.process.bursts)
        return turnaround, waiting, self.start - self.process.arrival

    def missed(self):
        return self.has_deadline() and self.finish > self.absolute_deadline()


class Simulation:
    def __init__(self, processes, algorithm, params, snapshot_time=None):
        self.algorithm = algorithm
        self.params = params
        self.snapshot_time = snapshot_time
        self.jobs = [Job(process) for process in sorted(processes, key=lambda p: p.pid)]
        self.queues = [[] for _ in range(LEVELS)]
        self.cpu = "IDLE"
        self.current = None
        self.switch_left = 0
        self.run_length = 0
        self.previous = None
        self.switches = 0
        self.random = RandomState(params["seed"])
        self.events = []
        self.event_counts = Counter()
        self.labels = []
        self.cpu_states = []
        self.queue_lengths = []
        self.snapshot = None
        self.end = None

    def run(self):
        time = 0
        while True:
            if self.algorithm == "PRIORITY":
                self.age(time)
            self.complete_io(time)
            self.admit(time)
            self.check_cpu(time)
            if all(job.state == "DONE" for job in self.jobs):
                break
            if self.algorithm == "MLFQ":
                self.boost(time)
            self.select(time)
            if time == self.snapshot_time:
                self.capture()
            self.execute(time)
            time += 1
        self.end = time
        if self.snapshot_time is not None and self.snapshot is None:
            self.capture()

    def record(self, time, kind, *details):
        self.events.append(" ".join(str(part) for part in (time, kind, *details)))
        self.event_counts[kind] += 1

    def enqueue(self, job, time):
        job.state = "READY"
        job.enqueued = time
        self.queues[job.level].append(job)

    def release(self):
        self.cpu = "IDLE"
        self.current = None

    def start_running(self, job, time):
        self.cpu = "RUN"
        self.current = job
        self.run_length = 0
        job.state = "RUN"
        if job.start is None:
            job.start = time
        record = job.records[-1]
        if record.start is None:
            record.start = time

    def age(self, time):
        for job in self.queues[0]:
            job.wait += 1
            if job.wait == self.params["k"]:
                job.wait = 0
                if job.effective >= 1:
                    job.effective -= 1
                    self.record(time, "AGE", job.pid, job.effective)

    def complete_io(self, time):
        for job in self.jobs:
            if job.state == "IO" and job.remaining == 0:
                job.advance()
                job.records.append(BurstRecord(job.remaining, time))
                self.enqueue(job, time)
                self.record(time, "IODONE", job.pid)

    def admit(self, time):
        for job in self.jobs:
            if job.state == "FUTURE" and job.process.arrival == time:
                job.records.append(BurstRecord(job.remaining, time))
                self.enqueue(job, time)
                self.record(time, "ARRIVE", job.pid)

    def check_cpu(self, time):
        job = self.current
        if self.cpu == "SWITCH" and self.switch_left == 0:
            self.start_running(job, time)
            self.record(time, "START", job.pid)
        elif self.cpu == "RUN":
            if job.remaining == 0 and job.on_last_burst():
                job.state = "DONE"
                job.finish = time
                self.record(time, "DONE", job.pid)
                self.release()
            else:
                self.check_running(job, time)

    def check_running(self, job, time):
        demoted = (
            self.algorithm == "MLFQ"
            and job.level < LEVELS - 1
            and job.usage == ALLOTMENTS[job.level]
        )
        if demoted:
            job.level += 1
            job.usage = 0
            self.record(time, "DEMOTE", job.pid, job.level)
        if job.remaining == 0:
            job.advance()
            job.state = "IO"
            self.record(time, "IO", job.pid, job.remaining)
        elif demoted:
            self.enqueue(job, time)
        elif self.algorithm in ("RR", "LOTTERY") and self.run_length == self.params["q"]:
            self.enqueue(job, time)
            self.record(time, "EXPIRE", job.pid)
        elif self.preempts(job):
            self.enqueue(job, time)
            self.record(time, "PREEMPT", job.pid)
        else:
            return
        self.release()

    def preempts(self, job):
        queue = self.queues[0]
        if self.algorithm == "SRTF":
            return any(other.remaining < job.remaining for other in queue)
        if self.algorithm == "PRIORITY":
            return any(other.effective < job.effective for other in queue)
        if self.algorithm == "EDF":
            if not job.has_deadline():
                return any(other.has_deadline() for other in queue)
            return any(
                other.has_deadline() and other.absolute_deadline() < job.absolute_deadline()
                for other in queue
            )
        if self.algorithm == "MLFQ":
            return any(self.queues[level] for level in range(job.level))
        return False

    def boost(self, time):
        interval = self.params["s"]
        if interval >= 1 and time >= 1 and time % interval == 0:
            merged = [job for queue in self.queues for job in queue]
            self.queues = [merged] + [[] for _ in range(LEVELS - 1)]
            for job in self.jobs:
                job.level = 0
                job.usage = 0
            self.record(time, "BOOST")

    def select(self, time):
        if self.cpu != "IDLE" or not any(self.queues):
            return
        if self.algorithm == "MLFQ":
            queue = next(queue for queue in self.queues if queue)
            job = queue[0]
        else:
            queue = self.queues[0]
            job = self.choose(queue, time)
        queue.remove(job)
        job.effective = job.process.priority
        job.wait = 0
        job.records[-1].slices += 1
        switched = job is not self.previous
        if switched:
            self.switches += 1
        if switched and self.params["cs"] >= 1:
            self.cpu = "SWITCH"
            self.current = job
            self.switch_left = self.params["cs"]
            job.state = "SWITCH"
            self.record(time, "SWITCH", job.pid)
        else:
            self.start_running(job, time)
            self.record(time, "DISPATCH", job.pid)

    def choose(self, queue, time):
        if self.algorithm in ("SJF", "SRTF"):
            return min(queue, key=lambda job: job.remaining)
        if self.algorithm == "PRIORITY":
            return min(queue, key=lambda job: job.effective)
        if self.algorithm == "HRRN":
            return self.highest_ratio(queue, time)
        if self.algorithm == "EDF":
            candidates = [job for job in queue if job.has_deadline()]
            if candidates:
                return min(candidates, key=lambda job: job.absolute_deadline())
            return queue[0]
        if self.algorithm == "LOTTERY":
            return self.draw(queue)
        return queue[0]

    def highest_ratio(self, queue, time):
        best = queue[0]
        for job in queue[1:]:
            job_ratio = (time - job.enqueued + job.remaining) * best.remaining
            best_ratio = (time - best.enqueued + best.remaining) * job.remaining
            if job_ratio > best_ratio:
                best = job
        return best

    def draw(self, queue):
        target = self.random.draw(sum(job.tickets() for job in queue))
        tickets = 0
        for job in queue:
            tickets += job.tickets()
            if tickets > target:
                return job
        return queue[-1]

    def execute(self, time):
        for job in self.jobs:
            job.timeline.append(STATE_SYMBOLS[job.state])
        self.queue_lengths.append(sum(len(queue) for queue in self.queues))
        self.cpu_states.append(self.cpu)
        if self.cpu == "RUN":
            job = self.current
            job.remaining -= 1
            job.usage += 1
            self.run_length += 1
            self.previous = job
            self.labels.append(job.pid)
            if job.remaining == 0:
                job.records[-1].end = time + 1
        elif self.cpu == "SWITCH":
            self.switch_left -= 1
            self.labels.append("CS")
        else:
            self.labels.append("IDLE")
        for job in self.jobs:
            if job.state == "IO":
                job.remaining -= 1

    def capture(self):
        if self.cpu == "IDLE":
            lines = ["CPU IDLE"]
        else:
            lines = [f"CPU {self.cpu} {self.current.pid}"]
        if self.algorithm == "MLFQ":
            for level, queue in enumerate(self.queues):
                lines.append(f"QUEUE{level} {queue_text(queue)}")
        else:
            lines.append(f"QUEUE {queue_text(self.queues[0])}")
        lines.extend(self.job_status(job) for job in self.jobs)
        self.snapshot = lines

    def job_status(self, job):
        if job.state == "FUTURE":
            return f"{job.pid} FUTURE at={job.process.arrival}"
        if job.state == "DONE":
            return f"{job.pid} DONE at={job.finish}"
        status = f"{job.pid} {job.state} burst={job.burst + 1} left={job.remaining}"
        if self.algorithm == "PRIORITY":
            status += f" prio={job.effective}"
        elif self.algorithm == "MLFQ":
            status += f" level={job.level} used={job.usage}"
        return status

    def segments(self):
        segments = []
        start = 0
        for tick in range(1, self.end + 1):
            if tick == self.end or self.labels[tick] != self.labels[start]:
                segments.append(f"[{start}-{tick} {self.labels[start]}]")
                start = tick
        return segments

    def tick_counts(self, start, stop):
        states = self.cpu_states[start:stop]
        return states.count("RUN"), states.count("SWITCH"), states.count("IDLE")

    def top_process(self, start, stop):
        counts = Counter(
            self.labels[tick] for tick in range(start, stop) if self.cpu_states[tick] == "RUN"
        )
        if not counts:
            return "none"
        return min(counts, key=lambda pid: (-counts[pid], pid))

    def totals(self):
        return [
            sum(job.metrics()[index] for job in self.jobs) for index in range(len(METRICS))
        ]

    def averages(self):
        return [truncated(total, len(self.jobs)) for total in self.totals()]

    def utilization(self):
        return truncated(self.cpu_states.count("RUN") * 100, self.end)

    def missed_count(self):
        return sum(job.missed() for job in self.jobs)

    def met_count(self):
        return sum(job.has_deadline() and not job.missed() for job in self.jobs)


def rank_value(simulation, metric):
    if metric in METRICS:
        total = simulation.totals()[METRICS.index(metric)]
        return total, truncated(total, len(simulation.jobs))
    if metric == "end":
        value = simulation.end
    elif metric == "switches":
        value = simulation.switches
    else:
        value = simulation.missed_count()
    return value, str(value)


class Scheduler:
    def __init__(self):
        self.registry = {}
        self.output = []

    def emit(self, *parts):
        self.output.append(" ".join(str(part) for part in parts))

    def require_process(self, pid):
        if pid not in self.registry:
            raise CommandError(f"unknown process {pid}")
        return self.registry[pid]

    def require_algorithm(self, algorithm):
        if algorithm not in ALGORITHMS:
            raise CommandError(f"unknown algorithm {algorithm}")

    def prepare(self, words, algorithm=None, preset=()):
        params = parse_params(words, algorithm, preset)
        if not self.registry:
            raise CommandError("no processes")
        return params

    def simulate(self, algorithm, params, snapshot_time=None):
        simulation = Simulation(self.registry.values(), algorithm, params, snapshot_time)
        simulation.run()
        return simulation

    def simulate_command(self, arguments):
        algorithm, *words = arguments
        self.require_algorithm(algorithm)
        params = self.prepare(words, algorithm)
        return algorithm, params, self.simulate(algorithm, params)

    def sorted_processes(self):
        return [self.registry[pid] for pid in sorted(self.registry)]

    def add_process(self, arguments):
        pid, arrival_text, priority_text, *words = arguments
        if pid in self.registry:
            raise CommandError(f"duplicate process {pid}")
        if len(self.registry) >= MAX_PROCESSES:
            raise CommandError("too many processes")
        arrival, priority = int(arrival_text), int(priority_text)
        if arrival > MAX_ARRIVAL:
            raise CommandError(f"invalid arrival {pid}")
        if priority > MAX_PRIORITY:
            raise CommandError(f"invalid priority {pid}")
        bursts = parse_bursts(words)
        if bursts is None:
            raise CommandError(f"invalid bursts {pid}")
        self.registry[pid] = Process(pid, arrival, priority, bursts)
        self.emit(f"PROC {pid} cpu={sum(bursts[0::2])} io={sum(bursts[1::2])}")

    def generate(self, arguments):
        prefix, count_text, seed_text = arguments
        count = int(count_text)
        pids = [prefix + str(number) for number in range(1, count + 1)]
        for pid in pids:
            if pid in self.registry:
                raise CommandError(f"duplicate process {pid}")
        if len(self.registry) + count > MAX_PROCESSES:
            raise CommandError("too many processes")
        self.emit(f"GEN count={count}")
        random = RandomState(int(seed_text))
        for pid in pids:
            arrival = random.draw(21)
            priority = random.draw(10)
            cpu_bursts = 1 + random.draw(3)
            bursts = []
            for number in range(1, cpu_bursts + 1):
                if number >= 2:
                    bursts.append(1 + random.draw(8))
                bursts.append(1 + random.draw(9))
            process = Process(pid, arrival, priority, bursts)
            self.registry[pid] = process
            self.emit(process.describe())

    def set_priority(self, arguments):
        pid, priority_text = arguments
        process = self.require_process(pid)
        priority = int(priority_text)
        if priority > MAX_PRIORITY:
            raise CommandError(f"invalid priority {pid}")
        process.priority = priority
        self.emit(f"SETPRIO {pid} priority={priority}")

    def set_deadline(self, arguments):
        pid, deadline_text = arguments
        process = self.require_process(pid)
        deadline = int(deadline_text)
        if deadline > MAX_DEADLINE:
            raise CommandError(f"invalid deadline {pid}")
        process.deadline = deadline if deadline >= 1 else None
        self.emit("DEADLINE", pid, "none" if process.deadline is None else deadline)

    def drop(self, arguments):
        pid = arguments[0]
        self.require_process(pid)
        del self.registry[pid]
        self.emit("DROP", pid)

    def clear(self, arguments):
        count = len(self.registry)
        self.registry.clear()
        self.emit(f"CLEAR count={count}")

    def list_processes(self, arguments):
        self.emit(f"LIST count={len(self.registry)}")
        for process in self.sorted_processes():
            self.emit(process.describe())

    def run(self, arguments):
        algorithm, params, simulation = self.simulate_command(arguments)
        self.emit("RUN", algorithm, notation(params, algorithm))
        segments = simulation.segments()
        for start in range(0, len(segments), GANTT_GROUP):
            self.emit("GANTT " + "".join(segments[start:start + GANTT_GROUP]))
        for job in simulation.jobs:
            turnaround, waiting, response = job.metrics()
            line = (
                f"{job.pid} arrival={job.process.arrival} done={job.finish} "
                f"turnaround={turnaround} waiting={waiting} response={response} "
                f"slices={job.slices()}"
            )
            if job.has_deadline():
                deadline = job.absolute_deadline()
                line += f" deadline={deadline} late={max(0, job.finish - deadline)}"
            self.emit(line)
        turnaround, waiting, response = simulation.averages()
        self.emit(f"AVERAGE turnaround={turnaround} waiting={waiting} response={response}")
        busy, switch, idle = simulation.tick_counts(0, simulation.end)
        self.emit(
            f"CPU end={simulation.end} busy={busy} switch={switch} idle={idle} "
            f"switches={simulation.switches} util={simulation.utilization()}"
        )
        queue_average = truncated(sum(simulation.queue_lengths), simulation.end)
        self.emit(f"QUEUE max={max(simulation.queue_lengths)} avg={queue_average}")
        counts = simulation.event_counts
        self.emit("EVENTS", *(f"{kind.lower()}={counts[kind]}" for kind in EVENT_KINDS))
        self.emit(f"DEADLINE met={simulation.met_count()} missed={simulation.missed_count()}")

    def trace(self, arguments):
        algorithm, params, simulation = self.simulate_command(arguments)
        self.emit("TRACE", algorithm, notation(params, algorithm))
        self.output.extend(simulation.events)
        self.emit("END", simulation.end)

    def timeline(self, arguments):
        algorithm, params, simulation = self.simulate_command(arguments)
        if simulation.end > TIMELINE_LIMIT:
            raise CommandError(f"too long {simulation.end}")
        self.emit("TIMELINE", algorithm, notation(params, algorithm), f"end={simulation.end}")
        for job in simulation.jobs:
            self.emit(job.pid.ljust(ID_WIDTH), "".join(job.timeline))

    def snapshot(self, arguments):
        algorithm, time_text, *words = arguments
        self.require_algorithm(algorithm)
        params = self.prepare(words, algorithm)
        time = int(time_text)
        simulation = self.simulate(algorithm, params, time)
        self.emit("SNAPSHOT", algorithm, notation(params, algorithm), f"t={time}")
        self.output.extend(simulation.snapshot)

    def bursts(self, arguments):
        algorithm, params, simulation = self.simulate_command(arguments)
        self.emit("BURSTS", algorithm, notation(params, algorithm))
        for job in simulation.jobs:
            for number, record in enumerate(job.records, 1):
                wait = record.end - record.ready - record.length
                self.emit(
                    f"{job.pid} #{number} len={record.length} ready={record.ready} "
                    f"start={record.start} end={record.end} wait={wait} slices={record.slices}"
                )

    def window(self, arguments):
        algorithm, width_text, *words = arguments
        self.require_algorithm(algorithm)
        width = int(width_text)
        if not 1 <= width <= MAX_WINDOW:
            raise CommandError("invalid window")
        params = self.prepare(words, algorithm)
        simulation = self.simulate(algorithm, params)
        self.emit("WINDOW", algorithm, notation(params, algorithm), f"width={width}")
        for start in range(0, simulation.end, width):
            stop = min(start + width, simulation.end)
            busy, switch, idle = simulation.tick_counts(start, stop)
            self.emit(
                f"{start}-{stop} busy={busy} switch={switch} idle={idle} "
                f"util={truncated(busy * 100, stop - start)} "
                f"top={simulation.top_process(start, stop)}"
            )

    def stats(self, arguments):
        algorithm, params, simulation = self.simulate_command(arguments)
        self.emit("STATS", algorithm, notation(params, algorithm))
        for index, name in enumerate(METRICS):
            values = [job.metrics()[index] for job in simulation.jobs]
            low, high = min(values), max(values)
            low_pid = simulation.jobs[values.index(low)].pid
            high_pid = simulation.jobs[values.index(high)].pid
            self.emit(
                f"{name} min={low} ({low_pid}) max={high} ({high_pid}) "
                f"median={median_text(values)} total={sum(values)}"
            )

    def sweep(self, arguments):
        algorithm, key, low_text, high_text, *words = arguments
        self.require_algorithm(algorithm)
        if key not in PARAMETER_RANGES:
            raise CommandError(f"unknown key {key}")
        if key not in ALGORITHM_KEYS[algorithm]:
            raise CommandError(f"key {key} not allowed for {algorithm}")
        low, high = int(low_text), int(high_text)
        minimum, maximum = PARAMETER_RANGES[key]
        valid_ends = minimum <= low <= maximum and minimum <= high <= maximum
        if low > high or not valid_ends or high - low > MAX_SWEEP:
            raise CommandError("invalid range")
        params = self.prepare(words, algorithm, (key,))
        self.emit("SWEEP", algorithm, key, low, high)
        best_value = low
        best_total = None
        for value in range(low, high + 1):
            params[key] = value
            simulation = self.simulate(algorithm, params)
            turnaround, waiting, response = simulation.averages()
            self.emit(
                notation(params, algorithm),
                f"turnaround={turnaround} waiting={waiting} response={response} "
                f"util={simulation.utilization()} end={simulation.end} "
                f"switches={simulation.switches}"
            )
            total = simulation.totals()[1]
            if best_total is None or total < best_total:
                best_value = value
                best_total = total
        self.emit(f"BEST {key}={best_value}")

    def diff(self, arguments):
        first, second, *words = arguments
        self.require_algorithm(first)
        self.require_algorithm(second)
        params = self.prepare(words)
        one = self.simulate(first, params)
        two = self.simulate(second, params)
        self.emit("DIFF", first, second, notation(params))
        first_wins = second_wins = ties = 0
        for job, other in zip(one.jobs, two.jobs):
            mine, theirs = job.metrics(), other.metrics()
            pairs = [
                f"{name}={value}/{other_value}"
                for name, value, other_value in zip(METRICS, mine, theirs)
            ]
            self.emit(job.pid, *pairs)
            if mine[0] < theirs[0]:
                first_wins += 1
            elif mine[0] > theirs[0]:
                second_wins += 1
            else:
                ties += 1
        self.emit(f"WINS {first}={first_wins} {second}={second_wins} ties={ties}")

    def compare(self, arguments):
        params = self.prepare(arguments)
        self.emit("COMPARE", notation(params))
        self.emit(table_row(TABLE_HEADER))
        totals = []
        for algorithm in ALGORITHMS:
            simulation = self.simulate(algorithm, params)
            totals.append(simulation.totals())
            self.emit(table_row((
                algorithm, *simulation.averages(), simulation.utilization(),
                str(simulation.end), str(simulation.switches),
                str(simulation.missed_count()),
            )))
        best = []
        for index, metric in enumerate(METRICS):
            column = [row[index] for row in totals]
            best.append(f"{metric}={ALGORITHMS[column.index(min(column))]}")
        self.emit("BEST", *best)

    def rank(self, arguments):
        metric, *words = arguments
        if metric not in RANK_METRICS:
            raise CommandError(f"unknown metric {metric}")
        params = self.prepare(words)
        entries = []
        for algorithm in ALGORITHMS:
            value, text = rank_value(self.simulate(algorithm, params), metric)
            entries.append((value, text, algorithm))
        self.emit("RANK", metric, notation(params))
        for value, text, algorithm in sorted(entries, key=lambda entry: entry[0]):
            position = 1 + sum(other < value for other, _, _ in entries)
            self.emit(position, algorithm, text)

    def execute(self, line):
        command, *arguments = line.split()
        handlers = {
            "PROC": self.add_process,
            "GEN": self.generate,
            "SETPRIO": self.set_priority,
            "DEADLINE": self.set_deadline,
            "DROP": self.drop,
            "CLEAR": self.clear,
            "LIST": self.list_processes,
            "RUN": self.run,
            "TRACE": self.trace,
            "TIMELINE": self.timeline,
            "SNAPSHOT": self.snapshot,
            "BURSTS": self.bursts,
            "WINDOW": self.window,
            "STATS": self.stats,
            "SWEEP": self.sweep,
            "DIFF": self.diff,
            "COMPARE": self.compare,
            "RANK": self.rank,
        }
        try:
            handlers[command](arguments)
        except CommandError as error:
            self.emit("ERROR", error)


def main():
    scheduler = Scheduler()
    count = int(sys.stdin.readline())
    for _ in range(count):
        scheduler.execute(sys.stdin.readline().rstrip("\n"))
    sys.stdout.write("\n".join(scheduler.output) + "\n")


if __name__ == "__main__":
    main()
