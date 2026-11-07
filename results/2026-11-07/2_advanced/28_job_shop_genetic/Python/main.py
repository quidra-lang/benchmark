import math
import os

from dispatch_rules import giffler_thompson
from gantt import busy_row, chart_row, chart_scale, rule_row, time_row
from genetic import crossover, decode, gene_operations, insert_mutation, swap_mutation, tournament
from instance import load_instance
from minstd import Minstd


INPUT_DIR = "input"
OUTPUT_DIR = "output"
RULES = ("SPT", "LPT", "MWKR", "FIFO")
TOP_LIMIT = 5


def percentage(part, whole):
    tenths = (2000 * part + whole) // (2 * whole)
    return f"{tenths // 10}.{tenths % 10}%"


def job_letter(number):
    return chr(ord("A") + number - 1)


def fraction(text):
    numerator, denominator = text.split("/")
    return int(numerator), int(denominator)


def makespan_of(starts, durations):
    return max(start + duration for start, duration in zip(starts, durations))


def write_lines(name, lines):
    with open(os.path.join(OUTPUT_DIR, name), "w", newline="\n") as file:
        file.write("\n".join(lines) + "\n")


class Parameters:
    def __init__(self, fields):
        self.seed = int(fields["seed"][0])
        self.population = int(fields["population"][0])
        self.generations = int(fields["generations"][0])
        self.tournament = int(fields["tournament"][0])
        self.crossover = fraction(fields["crossover"][0])
        self.swap = fraction(fields["swap_mutation"][0])
        self.insert = fraction(fields["insert_mutation"][0])
        self.elitism = int(fields["elitism"][0])
        self.checkpoints = [int(value) for value in fields["checkpoints"]]
        self.tabu_iterations = int(fields["tabu_iterations"][0])
        self.tabu_tenure = int(fields["tabu_tenure"][0])
        self.gantt_width = int(fields["gantt_width"][0])


def load_parameters(path):
    fields = {}
    with open(path) as file:
        for line in file.read().splitlines():
            key, *values = line.split(" ")
            fields[key] = values
    return Parameters(fields)


def jackson_bound(machine):
    tasks = machine.operations
    remaining = [task.duration for task in tasks]
    time = 0
    bound = 0
    while any(remaining):
        pending = [index for index in range(len(tasks)) if remaining[index] > 0]
        if all(tasks[index].head > time for index in pending):
            time = min(tasks[index].head for index in pending)
        released = [index for index in pending if tasks[index].head <= time]
        selected = max(released, key=lambda index: (tasks[index].tail, -tasks[index].job))
        step = remaining[selected]
        later = [task.head for task in tasks if task.head > time]
        if later:
            step = min(step, min(later) - time)
        time += step
        remaining[selected] -= step
        if remaining[selected] == 0:
            bound = max(bound, time + tasks[selected].tail)
    return bound


def copy_order(order):
    return [list(sequence) for sequence in order]


def order_starts(instance, order, durations):
    count = len(instance.operations)
    starts = [None] * count
    completions = [0] * count
    positions = [0] * instance.machine_count
    placed = 0
    while placed < count:
        for machine, sequence in enumerate(order):
            while positions[machine] < len(sequence):
                position = positions[machine]
                ident = sequence[position]
                previous = instance.operations[ident].job_prev
                if previous is not None and starts[previous] is None:
                    break
                ready = 0 if previous is None else completions[previous]
                free = 0 if position == 0 else completions[sequence[position - 1]]
                starts[ident] = max(ready, free)
                completions[ident] = starts[ident] + durations[ident]
                positions[machine] += 1
                placed += 1
    return starts


def order_makespan(instance, order, durations):
    return makespan_of(order_starts(instance, order, durations), durations)


def schedule_of_order(instance, order):
    return Schedule(instance, order_starts(instance, order, instance.durations))


def apply_move(instance, order, move):
    first, second = move
    result = copy_order(order)
    sequence = result[instance.operations[first].machine - 1]
    position = sequence.index(first)
    sequence[position], sequence[position + 1] = second, first
    return result


def sequence_distance(first, second):
    rank = {ident: position for position, ident in enumerate(second)}
    count = 0
    for low in range(len(first)):
        for high in range(low + 1, len(first)):
            if rank[first[low]] > rank[first[high]]:
                count += 1
    return count


def machine_distances(first, second):
    return [sequence_distance(a, b) for a, b in zip(first.order, second.order)]


class Schedule:
    def __init__(self, instance, starts):
        self.instance = instance
        self.starts = starts
        self.durations = instance.durations
        self.completions = [start + duration for start, duration in zip(starts, self.durations)]
        self.makespan = max(self.completions)
        count = len(starts)
        self.order = [[] for _ in range(instance.machine_count)]
        for ident in self.by_start():
            self.order[instance.operations[ident].machine - 1].append(ident)
        self.machine_prev = [None] * count
        self.machine_next = [None] * count
        for sequence in self.order:
            for first, second in zip(sequence, sequence[1:]):
                self.machine_next[first] = second
                self.machine_prev[second] = first

    def by_start(self):
        return sorted(range(len(self.starts)), key=lambda ident: (self.starts[ident], ident))

    def chromosome(self):
        return [self.instance.operations[ident].job for ident in self.by_start()]

    def critical_path(self):
        current = self.completions.index(self.makespan)
        path = [current]
        while self.starts[current] != 0:
            previous = self.machine_prev[current]
            if previous is not None and self.completions[previous] == self.starts[current]:
                current = previous
            else:
                current = self.instance.operations[current].job_prev
            path.append(current)
        path.reverse()
        return path

    def link(self, path, position):
        if position == 0:
            return "start"
        if self.machine_prev[path[position]] == path[position - 1]:
            return "machine"
        return "job"

    def blocks(self, path):
        blocks = []
        for ident in path:
            machine = self.instance.operations[ident].machine
            if blocks and self.instance.operations[blocks[-1][-1]].machine == machine:
                blocks[-1].append(ident)
            else:
                blocks.append([ident])
        return blocks

    def moves(self):
        moves = []
        for block in self.blocks(self.critical_path()):
            moves.extend(zip(block, block[1:]))
        return moves

    def path_count(self):
        ways = [0] * len(self.starts)
        for ident in self.by_start():
            if self.starts[ident] == 0:
                ways[ident] = 1
                continue
            sources = (self.instance.operations[ident].job_prev, self.machine_prev[ident])
            for source in sources:
                if source is not None and self.completions[source] == self.starts[ident]:
                    ways[ident] += ways[source]
        return sum(
            ways[ident] for ident in range(len(ways))
            if self.completions[ident] == self.makespan
        )

    def left_shift(self, ident):
        operation = self.instance.operations[ident]
        sequence = self.order[operation.machine - 1]
        position = sequence.index(ident)
        if position == 0:
            return None
        ready = 0 if operation.job_prev is None else self.completions[operation.job_prev]
        intervals = [(0, self.starts[sequence[0]], 0)]
        for index in range(1, position):
            intervals.append(
                (self.completions[sequence[index - 1]], self.starts[sequence[index]], index)
            )
        for begin, end, insertion in intervals:
            start = max(begin, ready)
            if start + operation.duration <= end:
                return start, insertion
        return None

    def shiftable_count(self):
        return sum(self.left_shift(ident) is not None for ident in range(len(self.starts)))

    def slacks(self):
        count = len(self.starts)
        latest = [0] * count
        slack = [0] * count
        free = [0] * count
        for ident in reversed(self.by_start()):
            following = (self.instance.operations[ident].job_next, self.machine_next[ident])
            successors = [other for other in following if other is not None]
            latest_limit = min((latest[other] for other in successors), default=self.makespan)
            start_limit = min((self.starts[other] for other in successors), default=self.makespan)
            latest[ident] = latest_limit - self.durations[ident]
            slack[ident] = latest[ident] - self.starts[ident]
            free[ident] = start_limit - self.completions[ident]
        return slack, free

    def path_counts(self, path):
        counts = [0] * self.instance.machine_count
        for ident in path:
            counts[self.instance.operations[ident].machine - 1] += 1
        return counts

    def bottleneck(self, path):
        counts = self.path_counts(path)
        best = max(range(len(counts)), key=lambda index: (counts[index], -index))
        return best + 1, counts[best]

    def job_completion(self, job):
        return self.completions[job.operations[-1].ident]

    def flow_time(self):
        return sum(self.job_completion(job) for job in self.instance.jobs)

    def idle_time(self, machine):
        return self.makespan - machine.load

    def total_idle(self):
        return sum(self.idle_time(machine) for machine in self.instance.machines)

    def utilization(self, machine):
        return percentage(machine.load, self.makespan)

    def gaps(self, machine):
        sequence = self.order[machine.number - 1]
        return [
            self.starts[second] - self.completions[first]
            for first, second in zip(sequence, sequence[1:])
            if self.starts[second] > self.completions[first]
        ]

    def idle_intervals(self, machine):
        sequence = self.order[machine.number - 1]
        intervals = [(0, self.starts[sequence[0]])]
        for first, second in zip(sequence, sequence[1:]):
            intervals.append((self.completions[first], self.starts[second]))
        intervals.append((self.completions[sequence[-1]], self.makespan))
        return [(begin, end) for begin, end in intervals if end > begin]

    def letters(self, machine):
        sequence = self.order[machine.number - 1]
        return "".join(job_letter(self.instance.operations[ident].job) for ident in sequence)


class TabuRecord:
    def __init__(self, iteration, move_count, tabu_count, move, aspiration, value, best):
        self.iteration = iteration
        self.move_count = move_count
        self.tabu_count = tabu_count
        self.move = move
        self.aspiration = aspiration
        self.value = value
        self.best = best


class TabuSearch:
    def __init__(self, instance, order, iterations, tenure):
        self.instance = instance
        self.start_order = order
        self.iterations = iterations
        self.tenure = tenure
        self.start_value = order_makespan(instance, order, instance.durations)
        self.best_order = order
        self.best_value = self.start_value
        self.found = 0
        self.records = []
        self.reason = "limit"

    def run(self):
        current = self.start_order
        expiry = {}
        for iteration in range(1, self.iterations + 1):
            moves = schedule_of_order(self.instance, current).moves()
            if not moves:
                self.reason = "no_moves"
                return
            values = [
                order_makespan(
                    self.instance, apply_move(self.instance, current, move),
                    self.instance.durations,
                )
                for move in moves
            ]
            tabu = [move in expiry and expiry[move] >= iteration for move in moves]
            selectable = [
                index for index in range(len(moves))
                if not tabu[index] or values[index] < self.best_value
            ]
            if not selectable:
                self.reason = "all_tabu"
                return
            chosen = min(selectable, key=lambda index: (values[index], index))
            first, second = moves[chosen]
            current = apply_move(self.instance, current, moves[chosen])
            expiry[(second, first)] = iteration + self.tenure
            if values[chosen] < self.best_value:
                self.best_order = current
                self.best_value = values[chosen]
                self.found = iteration
            self.records.append(TabuRecord(
                iteration, len(moves), sum(tabu), moves[chosen],
                tabu[chosen], values[chosen], self.best_value,
            ))


class Baseline:
    def __init__(self, instance, rule, params):
        self.rule = rule
        starts, self.decisions, self.ties = giffler_thompson(instance, rule)
        self.schedule = Schedule(instance, starts)
        self.path = self.schedule.critical_path()
        self.search = TabuSearch(
            instance, self.schedule.order, params.tabu_iterations, params.tabu_tenure
        )
        self.search.run()


class Shift:
    def __init__(self, ident, old_start, new_start):
        self.ident = ident
        self.old_start = old_start
        self.new_start = new_start


def activate(instance, order):
    current = copy_order(order)
    shifts = []
    while True:
        schedule = schedule_of_order(instance, current)
        shiftable = [
            ident for ident in schedule.by_start() if schedule.left_shift(ident) is not None
        ]
        if not shiftable:
            return current, shifts
        ident = shiftable[0]
        new_start, insertion = schedule.left_shift(ident)
        sequence = current[instance.operations[ident].machine - 1]
        sequence.remove(ident)
        sequence.insert(insertion, ident)
        shifts.append(Shift(ident, schedule.starts[ident], new_start))


class Progress:
    def __init__(self, generation, values, population):
        self.generation = generation
        self.best = min(values)
        self.total = sum(values)
        self.size = len(values)
        self.worst = max(values)
        self.distinct = len({tuple(chromosome) for chromosome in population})

    def mean(self):
        divisor = math.gcd(self.total, self.size)
        return f"{self.total // divisor}/{self.size // divisor}"


class GeneticAlgorithm:
    def __init__(self, instance, params, seeds):
        self.instance = instance
        self.params = params
        self.rng = Minstd(params.seed)
        self.job_numbers = [job.number for job in instance.jobs]
        self.population = [list(seed) for seed in seeds]
        self.values = []
        self.records = []
        self.progress = []
        self.crossovers = 0
        self.swaps = 0
        self.inserts = 0

    def basic_sequence(self):
        return [job.number for job in self.instance.jobs for _ in job.operations]

    def evaluate(self, chromosome):
        return makespan_of(decode(self.instance, chromosome), self.instance.durations)

    def ranking(self):
        return sorted(range(len(self.values)), key=lambda index: (self.values[index], index))

    def run(self):
        while len(self.population) < self.params.population:
            sequence = self.basic_sequence()
            self.rng.shuffle(sequence)
            self.population.append(sequence)
        previous_best = None
        for generation in range(self.params.generations + 1):
            self.values = [self.evaluate(chromosome) for chromosome in self.population]
            best = self.best_index()
            if previous_best is None or self.values[best] < previous_best:
                self.records.append((generation, self.values[best], best + 1))
            previous_best = self.values[best]
            if generation in self.params.checkpoints:
                self.progress.append(Progress(generation, self.values, self.population))
            if generation < self.params.generations:
                self.population = self.next_generation()

    def mutate(self, child):
        if self.rng.chance(*self.params.swap):
            self.swaps += 1
            swap_mutation(self.rng, child)
        if self.rng.chance(*self.params.insert):
            self.inserts += 1
            insert_mutation(self.rng, child)

    def next_generation(self):
        params = self.params
        offspring = [list(self.population[index]) for index in self.ranking()[:params.elitism]]
        for _ in range((params.population - params.elitism) // 2):
            first = self.population[tournament(self.rng, self.values, params.tournament)]
            second = self.population[tournament(self.rng, self.values, params.tournament)]
            if self.rng.chance(*params.crossover):
                self.crossovers += 1
                first_child, second_child = crossover(self.rng, first, second, self.job_numbers)
            else:
                first_child, second_child = list(first), list(second)
            self.mutate(first_child)
            self.mutate(second_child)
            offspring.append(first_child)
            offspring.append(second_child)
        return offspring

    def best_index(self):
        return self.ranking()[0]

    def top_individuals(self):
        seen = set()
        top = []
        for index in self.ranking():
            chromosome = tuple(self.population[index])
            if chromosome not in seen:
                seen.add(chromosome)
                top.append(index)
        return top[:TOP_LIMIT]


class Solver:
    def __init__(self, instance, params):
        self.instance = instance
        self.params = params
        self.jacksons = [jackson_bound(machine) for machine in instance.machines]
        self.job_bound = max(instance.jobs, key=lambda job: (job.work, -job.number))
        self.machine_bound = max(
            instance.machines, key=lambda machine: (machine.bound, -machine.number)
        )
        self.jackson_index = max(
            range(len(self.jacksons)), key=lambda index: (self.jacksons[index], -index)
        )
        self.lower_bound = max(
            self.job_bound.work, self.machine_bound.bound, self.jacksons[self.jackson_index]
        )
        self.baselines = []
        self.genetic = None
        self.ga_schedule = None
        self.active_makespan = 0
        self.active_decisions = 0
        self.activated_value = 0
        self.shifts = []
        self.search = None
        self.final = None

    def solve(self):
        instance = self.instance
        params = self.params
        self.baselines = [Baseline(instance, rule, params) for rule in RULES]
        seeds = [baseline.schedule.chromosome() for baseline in self.baselines]
        self.genetic = GeneticAlgorithm(instance, params, seeds)
        self.genetic.run()
        chromosome = self.genetic.population[self.genetic.best_index()]
        self.ga_schedule = Schedule(instance, decode(instance, chromosome))
        gene_positions = [0] * len(instance.operations)
        for position, operation in enumerate(gene_operations(instance, chromosome), 1):
            gene_positions[operation.ident] = position
        starts, self.active_decisions, _ = giffler_thompson(instance, "GENES", gene_positions)
        self.active_makespan = makespan_of(starts, instance.durations)
        activated, self.shifts = activate(instance, self.ga_schedule.order)
        self.activated_value = order_makespan(instance, activated, instance.durations)
        self.search = TabuSearch(instance, activated, params.tabu_iterations, params.tabu_tenure)
        self.search.run()
        self.final = schedule_of_order(instance, self.search.best_order)

    def sensitivity(self, machine):
        durations = [
            operation.duration + (operation.duration + 9) // 10
            if operation.machine == machine.number else operation.duration
            for operation in self.instance.operations
        ]
        return order_makespan(self.instance, self.final.order, durations)

    def baseline_lines(self):
        instance = self.instance
        total_work = sum(job.work for job in instance.jobs)
        lines = [
            f"INSTANCE jobs {len(instance.jobs)} machines {instance.machine_count} "
            f"operations {len(instance.operations)} work {total_work} "
            f"errors {len(instance.errors)}"
        ]
        lines.extend(f"ERROR {error}" for error in instance.errors)
        for job in instance.jobs:
            route = " ".join(f"M{operation.machine}" for operation in job.operations)
            lines.append(
                f"JOB J{job.number} operations {len(job.operations)} work {job.work} route {route}"
            )
        for machine, jackson in zip(instance.machines, self.jacksons):
            lines.append(
                f"MACHINE M{machine.number} operations {len(machine.operations)} "
                f"load {machine.load} head {machine.head} tail {machine.tail} "
                f"bound {machine.bound} jackson {jackson}"
            )
        lines.append(f"BOUND job {self.job_bound.work} J{self.job_bound.number}")
        lines.append(f"BOUND machine {self.machine_bound.bound} M{self.machine_bound.number}")
        lines.append(
            f"BOUND jackson {self.jacksons[self.jackson_index]} M{self.jackson_index + 1}"
        )
        lines.append(f"BOUND lower {self.lower_bound}")
        for baseline in self.baselines:
            lines.extend(self.rule_lines(baseline))
        best = min(self.baselines, key=lambda baseline: baseline.schedule.makespan)
        lines.append(f"BEST {best.rule} makespan {best.schedule.makespan}")
        for machine in instance.machines:
            parts = [f"UTILIZATION M{machine.number}"]
            for baseline in self.baselines:
                parts.append(f"{baseline.rule} {baseline.schedule.utilization(machine)}")
            lines.append(" ".join(parts))
        return lines

    def rule_lines(self, baseline):
        schedule = baseline.schedule
        rule = baseline.rule
        gap = percentage(schedule.makespan - self.lower_bound, self.lower_bound)
        bottleneck, _ = schedule.bottleneck(baseline.path)
        search = baseline.search
        return [
            f"RULE {rule} makespan {schedule.makespan} gap {gap} flow {schedule.flow_time()} "
            f"idle {schedule.total_idle()} decisions {baseline.decisions} ties {baseline.ties}",
            f"PATH {rule} operations {len(baseline.path)} "
            f"blocks {len(schedule.blocks(baseline.path))} "
            f"critical_paths {schedule.path_count()} bottleneck M{bottleneck}",
            f"TABU {rule} makespan {schedule.makespan} -> {search.best_value} "
            f"found {search.found} iterations {len(search.records)} stop {search.reason}",
        ]

    def progress_lines(self):
        lines = ["generation,best,mean,worst,distinct"]
        for progress in self.genetic.progress:
            lines.append(
                f"{progress.generation},{progress.best},{progress.mean()},"
                f"{progress.worst},{progress.distinct}"
            )
        return lines

    def genetic_lines(self):
        genetic = self.genetic
        best_value = self.ga_schedule.makespan
        last_record = genetic.records[-1][0]
        lines = [
            f"GA best {best_value} generation {last_record} crossovers {genetic.crossovers} "
            f"swaps {genetic.swaps} inserts {genetic.inserts}"
        ]
        for generation, value, individual in genetic.records:
            lines.append(f"RECORD generation {generation} makespan {value} individual {individual}")
        for rank, index in enumerate(genetic.top_individuals(), 1):
            schedule = Schedule(self.instance, decode(self.instance, genetic.population[index]))
            distance = sum(machine_distances(schedule, self.ga_schedule))
            lines.append(
                f"TOP {rank} individual {index + 1} makespan {genetic.values[index]} "
                f"distance {distance}"
            )
        chromosome = genetic.population[genetic.best_index()]
        lines.append("GA_CHROMOSOME " + " ".join(str(gene) for gene in chromosome))
        lines.append(
            f"ACTIVE_DECODE makespan {self.active_makespan} decisions {self.active_decisions}"
        )
        for number, shift in enumerate(self.shifts, 1):
            operation = self.instance.operations[shift.ident]
            lines.append(
                f"SHIFT {number} {operation.code} M{operation.machine} "
                f"start {shift.old_start} -> {shift.new_start}"
            )
        lines.append(
            f"ACTIVATED makespan {best_value} -> {self.activated_value} shifts {len(self.shifts)}"
        )
        return lines

    def gantt_lines(self, path):
        instance = self.instance
        final = self.final
        scale, columns = chart_scale(final.makespan, self.params.gantt_width)
        on_path = set(path)
        machine_intervals = [[] for _ in instance.machines]
        for operation in instance.operations:
            letter = job_letter(operation.job)
            mark = letter.lower() if operation.ident in on_path else letter
            interval = (final.starts[operation.ident], final.completions[operation.ident], mark)
            machine_intervals[operation.machine - 1].append(interval)
        lines = [f"GANTT scale {scale} columns {columns}", time_row(scale, columns)]
        lines.append(rule_row(columns))
        for machine, intervals in zip(instance.machines, machine_intervals):
            lines.append(chart_row(f"M{machine.number}", intervals, scale, columns))
        lines.append(busy_row(machine_intervals, scale, columns))
        for job in instance.jobs:
            intervals = [
                (final.starts[op.ident], final.completions[op.ident], str(op.machine % 10))
                for op in job.operations
            ]
            lines.append(chart_row(f"J{job.number}", intervals, scale, columns))
        return lines

    def machine_lines(self):
        final = self.final
        lines = []
        for machine in self.instance.machines:
            gaps = final.gaps(machine)
            sequence = " ".join(
                f"J{self.instance.operations[ident].job}:"
                f"{final.starts[ident]}-{final.completions[ident]}"
                for ident in final.order[machine.number - 1]
            )
            lines.append(
                f"MACHINE M{machine.number} load {machine.load} "
                f"idle {final.idle_time(machine)} utilization {final.utilization(machine)} "
                f"gaps {len(gaps)} longest_gap {max(gaps, default=0)} sequence {sequence}"
            )
            intervals = final.idle_intervals(machine)
            if intervals:
                idle = " ".join(f"{begin}-{end}" for begin, end in intervals)
            else:
                idle = "none"
            lines.append(f"IDLE M{machine.number} {idle}")
        return lines

    def job_lines(self):
        final = self.final
        lines = []
        total_waiting = 0
        for job in self.instance.jobs:
            completion = final.job_completion(job)
            waiting = completion - job.work
            total_waiting += waiting
            lines.append(
                f"JOB J{job.number} operations {len(job.operations)} work {job.work} "
                f"start {final.starts[job.operations[0].ident]} completion {completion} "
                f"waiting {waiting}"
            )
        lines.append(
            f"TOTAL flow {final.flow_time()} waiting {total_waiting} idle {final.total_idle()}"
        )
        return lines

    def distance_lines(self):
        others = [baseline.schedule for baseline in self.baselines] + [self.ga_schedule]
        labels = list(RULES) + ["GA"]
        distances = [machine_distances(self.final, other) for other in others]
        lines = []
        total_pairs = 0
        for machine in self.instance.machines:
            count = len(machine.operations)
            pairs = count * (count - 1) // 2
            total_pairs += pairs
            parts = [f"DISTANCE M{machine.number} pairs {pairs}"]
            for label, values in zip(labels, distances):
                parts.append(f"{label} {values[machine.number - 1]}")
            lines.append(" ".join(parts))
        parts = [f"DISTANCE total pairs {total_pairs}"]
        for label, values in zip(labels, distances):
            parts.append(f"{label} {sum(values)}")
        lines.append(" ".join(parts))
        return lines

    def schedule_lines(self):
        instance = self.instance
        final = self.final
        path = final.critical_path()
        gap = percentage(final.makespan - self.lower_bound, self.lower_bound)
        lines = self.genetic_lines()
        lines.append(
            f"SCHEDULE makespan {final.makespan} lower_bound {self.lower_bound} gap {gap} "
            f"improvement {self.ga_schedule.makespan - final.makespan} "
            f"shiftable {final.shiftable_count()}"
        )
        lines.append("CHROMOSOME " + " ".join(str(gene) for gene in final.chromosome()))
        legend = " ".join(f"{job_letter(job.number)}=J{job.number}" for job in instance.jobs)
        lines.append("LEGEND " + legend)
        lines.extend(self.gantt_lines(path))
        for machine in instance.machines:
            parts = [f"ORDER M{machine.number} FINAL {final.letters(machine)}"]
            for baseline in self.baselines:
                parts.append(f"{baseline.rule} {baseline.schedule.letters(machine)}")
            lines.append(" ".join(parts))
        lines.extend(self.machine_lines())
        lines.extend(self.job_lines())
        lines.extend(self.distance_lines())
        return lines

    def search_lines(self):
        search = self.search
        lines = [
            f"SEARCH start {search.start_value} iterations {search.iterations} "
            f"tenure {search.tenure}"
        ]
        for record in search.records:
            first, second = (self.instance.operations[ident] for ident in record.move)
            kind = "aspiration" if record.aspiration else "free"
            lines.append(
                f"ITER {record.iteration} moves {record.move_count} tabu {record.tabu_count} "
                f"swap M{first.machine} {first.code} {second.code} {kind} "
                f"makespan {record.value} best {record.best}"
            )
        lines.append(
            f"STOP iterations {len(search.records)} reason {search.reason} "
            f"best {search.best_value} found {search.found}"
        )
        return lines

    def path_lines(self):
        instance = self.instance
        operations = instance.operations
        final = self.final
        path = final.critical_path()
        blocks = final.blocks(path)
        lines = self.search_lines()
        lines.append(
            f"PATH operations {len(path)} blocks {len(blocks)} makespan {final.makespan} "
            f"critical_paths {final.path_count()}"
        )
        for number, ident in enumerate(path, 1):
            operation = operations[ident]
            lines.append(
                f"NODE {number} {operation.code} M{operation.machine} "
                f"{final.starts[ident]}-{final.completions[ident]} "
                f"{final.link(path, number - 1)}"
            )
        for number, block in enumerate(blocks, 1):
            codes = " ".join(operations[ident].code for ident in block)
            lines.append(
                f"BLOCK {number} M{operations[block[0]].machine} "
                f"{final.starts[block[0]]}-{final.completions[block[-1]]} {codes}"
            )
        for number, move in enumerate(final.moves(), 1):
            first, second = (operations[ident] for ident in move)
            value = order_makespan(
                instance, apply_move(instance, final.order, move), instance.durations
            )
            lines.append(
                f"NEIGHBOUR {number} M{first.machine} {first.code} {second.code} "
                f"makespan {value}"
            )
        slack, free = final.slacks()
        lines.append(f"CRITICAL operations {slack.count(0)} total {len(operations)}")
        for job in instance.jobs:
            values = " ".join(str(slack[operation.ident]) for operation in job.operations)
            lines.append(f"SLACK J{job.number} {values}")
        for job in instance.jobs:
            values = " ".join(str(free[operation.ident]) for operation in job.operations)
            lines.append(f"FREE J{job.number} {values}")
        counts = final.path_counts(path)
        for machine in instance.machines:
            critical = sum(slack[operation.ident] == 0 for operation in machine.operations)
            sensitivity = self.sensitivity(machine)
            lines.append(
                f"MACHINE M{machine.number} critical {critical} "
                f"path {counts[machine.number - 1]} sensitivity {sensitivity} "
                f"delta {sensitivity - final.makespan}"
            )
        bottleneck, count = final.bottleneck(path)
        lines.append(f"BOTTLENECK M{bottleneck} path {count}")
        return lines


def main():
    instance = load_instance(os.path.join(INPUT_DIR, "instance.txt"))
    params = load_parameters(os.path.join(INPUT_DIR, "ga_params.txt"))
    solver = Solver(instance, params)
    solver.solve()
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    write_lines("baselines.txt", solver.baseline_lines())
    write_lines("ga_progress.csv", solver.progress_lines())
    write_lines("best_schedule.txt", solver.schedule_lines())
    write_lines("critical_path.txt", solver.path_lines())


if __name__ == "__main__":
    main()
