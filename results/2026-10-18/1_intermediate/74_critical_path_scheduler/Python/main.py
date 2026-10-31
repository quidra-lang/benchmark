import math
import sys
from collections import Counter, defaultdict
from datetime import date, timedelta
from fractions import Fraction

MAX_CHART_DAYS = 60
CPM_COLUMNS = ("DUR", "ES", "EF", "LS", "LF", "TF", "FF")


class CommandError(Exception):
    pass


class Task:
    def __init__(self, name, duration, resource, units):
        self.name = name
        self.base_duration = duration
        self.resource = resource
        self.units = units
        self.not_before = 0
        self.crash_limit = None
        self.crash_cost = None
        self.crashed = 0
        self.estimate = None
        self.preds = {}
        self.succs = {}

    @property
    def duration(self):
        return self.base_duration - self.crashed

    def three_point(self):
        if self.estimate is None:
            return (self.duration, self.duration, self.duration)
        return self.estimate


class Dependency:
    def __init__(self, pred, succ, kind, lag):
        self.pred = pred
        self.succ = succ
        self.kind = kind
        self.lag = lag


def signed(value):
    return f"+{value}" if value >= 0 else str(value)


def two_decimals(value):
    whole, cents = divmod(math.floor(value * 100), 100)
    return f"{whole}.{cents:02d}"


def name_list(names):
    return " ".join(sorted(names))


def date_notation(day):
    return day.strftime("%Y-%m-%d %a")


def parse_date(text):
    try:
        return date.fromisoformat(text)
    except ValueError:
        raise CommandError(f"invalid date {text}") from None


def pert_moments(estimate):
    o, m, p = estimate
    return Fraction(o + 4 * m + p, 6), Fraction((p - o) ** 2, 36)


def dependency_list(links):
    if not links:
        return "none"
    return ", ".join(f"{name} {dep.kind}{signed(dep.lag)}" for name, dep in sorted(links.items()))


def start_bound(dep, starts, finishes, duration):
    if dep.kind == "FS":
        return finishes[dep.pred] + dep.lag
    if dep.kind == "SS":
        return starts[dep.pred] + dep.lag
    return finishes[dep.pred] + dep.lag - duration


def finish_bound(dep, latest_starts, latest_finishes, duration):
    if dep.kind == "FS":
        return latest_starts[dep.succ] - dep.lag
    if dep.kind == "SS":
        return latest_starts[dep.succ] - dep.lag + duration
    return latest_finishes[dep.succ] - dep.lag


def earliest_start(task, starts, finishes, duration):
    bounds = [start_bound(dep, starts, finishes, duration) for dep in task.preds.values()]
    return max([task.not_before] + bounds)


class Schedule:
    def __init__(self, tasks, order, durations):
        self.es = {}
        self.ef = {}
        for name in order:
            self.es[name] = earliest_start(tasks[name], self.es, self.ef, durations[name])
            self.ef[name] = self.es[name] + durations[name]
        self.length = max(self.ef.values())
        self.ls = {}
        self.lf = {}
        for name in reversed(order):
            bounds = [
                finish_bound(dep, self.ls, self.lf, durations[name])
                for dep in tasks[name].succs.values()
            ]
            self.lf[name] = min([self.length] + bounds)
            self.ls[name] = self.lf[name] - durations[name]
        self.total_float = {name: self.ls[name] - self.es[name] for name in order}
        self.free_float = {}
        for name in order:
            margins = [self.margin(dep) for dep in tasks[name].succs.values()]
            self.free_float[name] = min([self.length - self.ef[name]] + margins)
        self.critical = {name for name in order if self.total_float[name] == 0}

    def margin(self, dep):
        if dep.kind == "FS":
            return self.es[dep.succ] - self.ef[dep.pred] - dep.lag
        if dep.kind == "SS":
            return self.es[dep.succ] - self.es[dep.pred] - dep.lag
        return self.ef[dep.succ] - self.ef[dep.pred] - dep.lag

    def values(self, name):
        return (
            self.es[name],
            self.ef[name],
            self.ls[name],
            self.lf[name],
            self.total_float[name],
            self.free_float[name],
        )

    def by_start(self):
        return sorted(self.es, key=lambda name: (self.es[name], name))


class Project:
    def __init__(self):
        self.tasks = {}
        self.start = None
        self.holidays = set()
        self.deadline = None
        self.capacities = {}
        self.baseline = None
        self.handlers = {
            "TASK": self.add_task,
            "DEP": self.add_dependency,
            "UNDEP": self.remove_dependency,
            "REMOVE": self.remove_task,
            "NOTBEFORE": self.set_not_before,
            "CRASHCOST": self.set_crash_cost,
            "UNCRASH": self.uncrash,
            "PERT": self.set_estimate,
            "CAPACITY": self.set_capacity,
            "START": self.set_start,
            "HOLIDAY": self.add_holiday,
            "DEADLINE": self.set_deadline,
            "LIST": self.list_tasks,
            "SHOW": self.show_task,
            "IMPACT": self.impact,
            "CPM": self.cpm_table,
            "CRITICAL": self.critical_report,
            "SLACK": self.slack,
            "DRAG": self.drag,
            "STATS": self.stats,
            "CALENDAR": self.calendar,
            "GANTT": self.gantt,
            "LEVEL": self.level,
            "LOAD": self.load,
            "PERTSUM": self.pert_sum,
            "CRASH": self.crash,
            "WHATIF": self.what_if,
            "BASELINE": self.save_baseline,
            "VARIANCE": self.variance,
        }

    def execute(self, line):
        command, *arguments = line.split(" ")
        try:
            self.handlers[command](*arguments)
        except CommandError as error:
            print(f"error: {error}")

    def task(self, name):
        if name not in self.tasks:
            raise CommandError(f"unknown task {name}")
        return self.tasks[name]

    def sorted_tasks(self):
        return [self.tasks[name] for name in sorted(self.tasks)]

    def topological_order(self):
        waiting = {name: len(task.preds) for name, task in self.tasks.items()}
        ready = [name for name, count in waiting.items() if count == 0]
        order = []
        while ready:
            name = ready.pop()
            order.append(name)
            for succ in self.tasks[name].succs:
                waiting[succ] -= 1
                if waiting[succ] == 0:
                    ready.append(succ)
        return order

    def cycle_notation(self, order):
        remaining = set(self.tasks) - set(order)
        walk = [min(remaining)]
        while True:
            pred = min(name for name in self.tasks[walk[-1]].preds if name in remaining)
            if pred in walk:
                break
            walk.append(pred)
        cycle = [pred] + walk[walk.index(pred) + 1 :][::-1]
        first = cycle.index(min(cycle))
        cycle = cycle[first:] + cycle[:first]
        return " -> ".join(cycle + [cycle[0]])

    def analysis_order(self):
        if not self.tasks:
            raise CommandError("no tasks")
        order = self.topological_order()
        if len(order) < len(self.tasks):
            raise CommandError("cycle " + self.cycle_notation(order))
        return order

    def schedule(self, order, changed=None, duration=None):
        durations = {name: task.duration for name, task in self.tasks.items()}
        if changed is not None:
            durations[changed] = duration
        return Schedule(self.tasks, order, durations)

    def critical_paths(self, schedule):
        links = {}
        for name in schedule.critical:
            links[name] = [
                succ
                for succ, dep in sorted(self.tasks[name].succs.items())
                if succ in schedule.critical and schedule.margin(dep) == 0
            ]
        targets = {succ for following in links.values() for succ in following}
        paths = []

        def extend(path):
            following = links[path[-1]]
            if not following:
                paths.append(path)
            for succ in following:
                extend(path + [succ])

        for head in sorted(schedule.critical - targets):
            extend([head])
        return paths

    def resource_usage(self, resource, starts, finishes):
        usage = Counter()
        for task in self.tasks.values():
            if task.resource == resource:
                for day in range(starts[task.name], finishes[task.name]):
                    usage[day] += task.units
        return usage

    def is_working_day(self, day):
        return day.weekday() < 5 and day not in self.holidays

    def working_dates(self, count):
        dates = []
        day = self.start
        while len(dates) < count:
            if self.is_working_day(day):
                dates.append(day)
            day += timedelta(days=1)
        return dates

    def working_days_between(self, after, until):
        span = (until - after).days
        return sum(self.is_working_day(after + timedelta(days=k)) for k in range(1, span + 1))

    def add_task(self, name, duration, resource, units):
        if name in self.tasks:
            raise CommandError(f"task {name} already exists")
        self.tasks[name] = Task(name, int(duration), resource, int(units))
        print(f"task {name} added")

    def add_dependency(self, pred, succ, kind, lag):
        first = self.task(pred)
        second = self.task(succ)
        if pred == succ:
            raise CommandError(f"self dependency {pred}")
        if succ in first.succs:
            raise CommandError(f"dependency {pred} -> {succ} already exists")
        dep = Dependency(pred, succ, kind, int(lag))
        first.succs[succ] = dep
        second.preds[pred] = dep
        print(f"dependency {pred} -> {succ} {kind}{signed(dep.lag)} added")

    def remove_dependency(self, pred, succ):
        first = self.task(pred)
        second = self.task(succ)
        if succ not in first.succs:
            raise CommandError(f"no dependency {pred} -> {succ}")
        del first.succs[succ]
        del second.preds[pred]
        print(f"dependency {pred} -> {succ} removed")

    def remove_task(self, name):
        task = self.task(name)
        for pred in task.preds:
            del self.tasks[pred].succs[name]
        for succ in task.succs:
            del self.tasks[succ].preds[name]
        del self.tasks[name]
        print(f"task {name} removed with {len(task.preds) + len(task.succs)} dependencies")

    def set_not_before(self, name, day):
        self.task(name).not_before = int(day)
        print(f"notbefore {name} {day}")

    def set_crash_cost(self, name, maxdays, cost):
        task = self.task(name)
        limit = int(maxdays)
        if limit >= task.base_duration:
            raise CommandError(f"crash limit too large for {name}")
        if limit < task.crashed:
            raise CommandError(f"crash limit below used days for {name}")
        task.crash_limit = limit
        task.crash_cost = int(cost)
        print(f"crash {name} max {limit} cost {cost}")

    def uncrash(self, name):
        task = self.task(name)
        print(f"uncrash {name} restored {task.crashed} days")
        task.crashed = 0

    def set_estimate(self, name, optimistic, likely, pessimistic):
        task = self.task(name)
        estimate = (int(optimistic), int(likely), int(pessimistic))
        o, m, p = estimate
        if not o <= m <= p:
            raise CommandError("invalid estimate")
        task.estimate = estimate
        expected, variance = pert_moments(estimate)
        print(f"pert {name} expected {two_decimals(expected)} variance {two_decimals(variance)}")

    def set_capacity(self, resource, limit):
        self.capacities[resource] = int(limit)
        print(f"capacity {resource} {limit}")

    def set_start(self, text):
        self.start = parse_date(text)
        print(f"start {date_notation(self.start)}")

    def add_holiday(self, text):
        holiday = parse_date(text)
        if holiday in self.holidays:
            raise CommandError(f"duplicate holiday {text}")
        self.holidays.add(holiday)
        print(f"holiday {date_notation(holiday)}")

    def set_deadline(self, text):
        self.deadline = parse_date(text)
        print(f"deadline {date_notation(self.deadline)}")

    def list_tasks(self):
        dependencies = sum(len(task.preds) for task in self.tasks.values())
        print(
            f"tasks {len(self.tasks)}, dependencies {dependencies}, "
            f"holidays {len(self.holidays)}"
        )
        for task in self.sorted_tasks():
            preds = name_list(task.preds) or "none"
            print(
                f"{task.name} duration {task.duration} resource {task.resource} "
                f"units {task.units} preds {preds}"
            )

    def show_task(self, name):
        task = self.task(name)
        header = f"task {name} duration {task.duration} resource {task.resource} units {task.units}"
        if task.not_before:
            header += f" notbefore {task.not_before}"
        print(header)
        print("preds: " + dependency_list(task.preds))
        print("succs: " + dependency_list(task.succs))
        if task.crash_limit is None:
            print("crash: none")
        else:
            print(f"crash: max {task.crash_limit} used {task.crashed} cost {task.crash_cost}")
        if task.estimate is None:
            print("pert: none")
        else:
            print("pert: " + " ".join(map(str, task.estimate)))
        order = self.topological_order()
        if len(order) < len(self.tasks):
            print("schedule: unavailable")
            return
        schedule = self.schedule(order)
        labels = ("ES", "EF", "LS", "LF", "TF", "FF")
        fields = " ".join(f"{label} {value}" for label, value in zip(labels, schedule.values(name)))
        line = "schedule: " + fields
        if name in schedule.critical:
            line += " critical"
        print(line)

    def impact(self, name):
        self.task(name)
        reached = set()
        stack = [name]
        while stack:
            current = stack.pop()
            for succ in self.tasks[current].succs:
                if succ not in reached:
                    reached.add(succ)
                    stack.append(succ)
        reached.discard(name)
        print(f"impact {name}: {name_list(reached) or 'none'}")

    def cpm_table(self):
        schedule = self.schedule(self.analysis_order())
        width = max(4, *map(len, self.tasks))
        print("TASK".ljust(width) + "".join(f"{title:>5}" for title in CPM_COLUMNS))
        for task in self.sorted_tasks():
            values = (task.duration, *schedule.values(task.name))
            line = task.name.ljust(width) + "".join(f"{value:>5}" for value in values)
            if task.name in schedule.critical:
                line += " *"
            print(line)
        print(f"project duration {schedule.length}")

    def critical_report(self):
        schedule = self.schedule(self.analysis_order())
        paths = self.critical_paths(schedule)
        print(f"critical paths: {len(paths)}")
        for path in paths:
            print(" -> ".join(path))

    def slack(self):
        schedule = self.schedule(self.analysis_order())
        groups = defaultdict(list)
        for name, value in schedule.total_float.items():
            groups[value].append(name)
        for value in sorted(groups):
            print(f"float {value}: {name_list(groups[value])}")

    def drag(self):
        order = self.analysis_order()
        schedule = self.schedule(order)
        for name in sorted(schedule.critical):
            shortened = self.schedule(order, name, 0)
            print(f"{name} drag {schedule.length - shortened.length}")

    def stats(self):
        schedule = self.schedule(self.analysis_order())
        count = len(self.tasks)
        critical = len(schedule.critical)
        kinds = Counter(dep.kind for task in self.tasks.values() for dep in task.preds.values())
        print(
            f"tasks {count}, critical {critical}, dependencies {kinds.total()} "
            f"(FS {kinds['FS']}, SS {kinds['SS']}, FF {kinds['FF']})"
        )
        work = defaultdict(int)
        for task in self.tasks.values():
            work[task.resource] += task.duration * task.units
        totals = ", ".join(f"{resource} {amount}" for resource, amount in sorted(work.items()))
        print(f"work {totals}")
        float_sum = sum(schedule.total_float.values())
        average = two_decimals(Fraction(float_sum, count))
        print(f"float total {float_sum}, average {average}")
        share = two_decimals(Fraction(100 * critical, count))
        print(f"duration {schedule.length}, critical share {share}%")

    def calendar(self):
        order = self.analysis_order()
        if self.start is None:
            raise CommandError("no start date")
        schedule = self.schedule(order)
        dates = self.working_dates(schedule.length)
        for name in schedule.by_start():
            first = date_notation(dates[schedule.es[name]])
            last = date_notation(dates[schedule.ef[name] - 1])
            print(f"{name} {first} - {last}")
        begin = dates[0]
        end = dates[-1]
        print(
            f"project {date_notation(begin)} - {date_notation(end)}, "
            f"{schedule.length} working days, {(end - begin).days + 1} calendar days"
        )
        if self.deadline is not None:
            deadline = date_notation(self.deadline)
            if end <= self.deadline:
                spare = self.working_days_between(end, self.deadline)
                print(f"deadline {deadline} met, {spare} working days to spare")
            else:
                late = self.working_days_between(self.deadline, end)
                print(f"deadline {deadline} missed by {late} working days")
        spanned = sorted(
            holiday
            for holiday in self.holidays
            if holiday.weekday() < 5 and begin <= holiday <= end
        )
        print("holidays in span: " + (", ".join(map(date_notation, spanned)) or "none"))

    def gantt(self):
        schedule = self.schedule(self.analysis_order())
        length = schedule.length
        if length > MAX_CHART_DAYS:
            raise CommandError(f"chart too wide ({length} days)")
        width = max(map(len, self.tasks))
        print(" " * width + " |" + "".join(str(day % 10) for day in range(length)) + "|")
        for name in schedule.by_start():
            es = schedule.es[name]
            ef = schedule.ef[name]
            lf = schedule.lf[name]
            mark = "=" if name in schedule.critical else "-"
            bar = " " * es + mark * (ef - es) + "." * (lf - ef) + " " * (length - lf)
            print(f"{name.ljust(width)} |{bar}|")

    def level(self, limit):
        order = self.analysis_order()
        capacity = {
            task.resource: self.capacities.get(task.resource, int(limit))
            for task in self.tasks.values()
        }
        for task in self.sorted_tasks():
            if task.units > capacity[task.resource]:
                raise CommandError(f"capacity {capacity[task.resource]} too small for {task.name}")
        schedule = self.schedule(order)
        starts = {}
        finishes = {}
        usage = defaultdict(int)
        while len(starts) < len(self.tasks):
            ready = [
                task
                for task in self.tasks.values()
                if task.name not in starts and all(pred in starts for pred in task.preds)
            ]
            task = min(ready, key=lambda candidate: (schedule.ls[candidate.name], candidate.name))
            available = capacity[task.resource]
            start = earliest_start(task, starts, finishes, task.duration)
            while any(
                usage[task.resource, day] + task.units > available
                for day in range(start, start + task.duration)
            ):
                start += 1
            for day in range(start, start + task.duration):
                usage[task.resource, day] += task.units
            starts[task.name] = start
            finishes[task.name] = start + task.duration
        print(f"level capacity {limit}: duration {schedule.length} -> {max(finishes.values())}")
        for name, start in starts.items():
            shift = start - schedule.es[name]
            print(f"{name} start {start} finish {finishes[name]} shift {shift}")
        for resource in sorted(capacity):
            planned = max(self.resource_usage(resource, schedule.es, schedule.ef).values())
            leveled = max(self.resource_usage(resource, starts, finishes).values())
            print(f"resource {resource} capacity {capacity[resource]} peak {planned} -> {leveled}")

    def load(self, resource):
        order = self.analysis_order()
        if all(task.resource != resource for task in self.tasks.values()):
            raise CommandError(f"unknown resource {resource}")
        schedule = self.schedule(order)
        usage = self.resource_usage(resource, schedule.es, schedule.ef)
        daily = [usage[day] for day in range(schedule.length)]
        print(f"load {resource}: " + " ".join(map(str, daily)))
        peak = max(daily)
        print(f"peak {peak} on day {daily.index(peak)}")
        if resource in self.capacities:
            limit = self.capacities[resource]
            exceeded = sum(value > limit for value in daily)
            print(f"capacity {limit} exceeded on {exceeded} days")

    def pert_sum(self):
        schedule = self.schedule(self.analysis_order())
        for path in self.critical_paths(schedule):
            moments = [pert_moments(self.tasks[name].three_point()) for name in path]
            expected = two_decimals(sum(mean for mean, _ in moments))
            variance = two_decimals(sum(spread for _, spread in moments))
            print(f"{' -> '.join(path)}: expected {expected} variance {variance}")

    def crash(self, budget):
        order = self.analysis_order()
        remaining = int(budget)
        steps = 0
        schedule = self.schedule(order)
        initial = schedule.length
        while True:
            candidates = [
                task
                for task in self.sorted_tasks()
                if task.name in schedule.critical
                and task.crash_limit is not None
                and task.crashed < task.crash_limit
                and self.schedule(order, task.name, task.duration - 1).length < schedule.length
            ]
            if not candidates:
                reason = "no candidate"
                break
            task = min(candidates, key=lambda candidate: candidate.crash_cost)
            if task.crash_cost > remaining:
                reason = "insufficient budget"
                break
            previous = task.duration
            task.crashed += 1
            remaining -= task.crash_cost
            steps += 1
            schedule = self.schedule(order)
            print(
                f"step {steps}: {task.name} {previous} -> {task.duration}, "
                f"cost {task.crash_cost}, project {schedule.length}"
            )
        print(
            f"crash done: {steps} days, cost {int(budget) - remaining}, "
            f"project {initial} -> {schedule.length}, budget left {remaining}, {reason}"
        )

    def what_if(self, name, duration):
        order = self.analysis_order()
        task = self.task(name)
        before = self.schedule(order)
        after = self.schedule(order, name, int(duration))
        print(
            f"whatif {name} {task.duration} -> {duration}: "
            f"project {before.length} -> {after.length}"
        )
        for other in sorted(self.tasks):
            old = (before.es[other], before.ef[other], before.total_float[other])
            new = (after.es[other], after.ef[other], after.total_float[other])
            changes = [
                f"{label} {previous}->{current}"
                for label, previous, current in zip(("ES", "EF", "TF"), old, new)
                if previous != current
            ]
            if changes:
                print(other + " " + " ".join(changes))
        if before.critical != after.critical:
            print(f"critical {name_list(before.critical)} -> {name_list(after.critical)}")

    def save_baseline(self):
        self.baseline = self.schedule(self.analysis_order())
        print(f"baseline saved: {len(self.tasks)} tasks, duration {self.baseline.length}")

    def variance(self):
        order = self.analysis_order()
        if self.baseline is None:
            raise CommandError("no baseline")
        schedule = self.schedule(order)
        base = self.baseline
        print(
            f"variance: duration {base.length} -> {schedule.length} "
            f"({signed(schedule.length - base.length)})"
        )
        lines = []
        for name in sorted(set(base.es) | set(self.tasks)):
            if name not in self.tasks:
                lines.append(f"{name} removed")
            elif name not in base.es:
                lines.append(f"{name} new")
            elif (base.es[name], base.ef[name]) != (schedule.es[name], schedule.ef[name]):
                start = signed(schedule.es[name] - base.es[name])
                finish = signed(schedule.ef[name] - base.ef[name])
                lines.append(f"{name} start {start} finish {finish}")
        print("\n".join(lines or ["no task changes"]))


def main():
    project = Project()
    count = int(sys.stdin.readline())
    for _ in range(count):
        project.execute(sys.stdin.readline().rstrip("\n"))


if __name__ == "__main__":
    main()
