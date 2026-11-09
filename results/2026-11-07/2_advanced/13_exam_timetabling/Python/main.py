import os
from collections import Counter

from coloring import Attempt, greedy_numbering
from conflict_graph import ConflictGraph, reachable
from enrolment import load_courses, load_enrolments
from report import fixed_width_line, rounded_percent, write_files
from rooms import load_rooms, pack


INPUT_DIR = "input"
OUTPUT_DIR = "output"
BACK_TO_BACK = 0
SAME_DAY = 1
OVERNIGHT = 2
FRONT_LOAD = 3
RELATIONS = ("back_to_back", "same_day", "overnight")
EXCHANGE_VERDICTS = ("fixed", "invalid", "worse", "applied")
SWAP_VERDICTS = ("fixed", "invalid", "rooms", "worse", "applied")
GRID_LABEL_WIDTH = 4
GRID_CELL_WIDTH = 10
MATRIX_WIDTH = 9
MATRIX_COURSES = 8
DEGREE_LINES = 5
COURSE_LINES = 10
WORST_LINES = 5


def read_lines(name):
    with open(os.path.join(INPUT_DIR, name)) as file:
        return file.read().splitlines()


def ceil_div(numerator, denominator):
    return (numerator + denominator - 1) // denominator


def verdict_counts(tally, verdicts):
    return " ".join(f"{verdict} {tally[verdict]}" for verdict in verdicts)


class Calendar:
    def __init__(self, lines):
        settings = [[int(value) for value in line.split()[1:]] for line in lines[:6]]
        self.days = settings[0][0]
        self.lengths = settings[1]
        self.periods = len(self.lengths)
        self.limit = settings[2][0]
        self.weights = settings[3]
        self.front_count, self.deadline = settings[4]
        self.ratio = settings[5][0]
        self.slot_count = self.days * self.periods
        self.closed = set()
        self.unavailable = {}
        self.fixed = {}
        self.orders = []
        self.arrows = {}

    def slots(self):
        return range(1, self.slot_count + 1)

    def slot_at(self, day_text, period_text):
        day = int(day_text)
        period = int(period_text)
        if 1 <= day <= self.days and 1 <= period <= self.periods:
            return (day - 1) * self.periods + period
        return None

    def day_of(self, slot):
        return (slot - 1) // self.periods + 1

    def name(self, slot):
        return f"D{self.day_of(slot)}P{(slot - 1) % self.periods + 1}"

    def length(self, slot):
        return self.lengths[(slot - 1) % self.periods]

    def relation(self, first, second):
        low = min(first, second)
        high = max(first, second)
        if self.day_of(low) == self.day_of(high):
            if high - low == 1:
                return BACK_TO_BACK
            if high - low >= 2:
                return SAME_DAY
        elif high - low == 1:
            return OVERNIGHT
        return None


class Breakdown:
    def __init__(self, counts, late, weights):
        self.counts = counts
        self.late = late
        self.total = weights[FRONT_LOAD] * late
        for relation, count in enumerate(counts):
            self.total += weights[relation] * count

    def text(self):
        return (
            f"back_to_back {self.counts[BACK_TO_BACK]} same_day {self.counts[SAME_DAY]} "
            f"overnight {self.counts[OVERNIGHT]} front_load {self.late} penalty {self.total}"
        )


class Scheduler:
    def __init__(self, courses, student_courses, rooms, calendar, errors):
        self.courses = courses
        self.student_courses = student_courses
        self.rooms = rooms
        self.calendar = calendar
        self.errors = errors
        self.largest_room = max(room.capacity for room in rooms)
        course_ids = sorted(courses)
        self.empty = [c for c in course_ids if courses[c].size() == 0]
        self.oversized = [c for c in course_ids if courses[c].size() > self.largest_room]
        self.schedulable = [
            c for c in course_ids if c not in self.empty and c not in self.oversized
        ]
        vertices = [c for c in course_ids if courses[c].size() > 0]
        self.graph = ConflictGraph(vertices, student_courses.values())
        self.edges = self.graph.edges()
        self.front_load = self.by_size(self.schedulable)[:calendar.front_count]
        self.open_slots = []
        self.fixed_slots = set()
        self.assignment = {}
        self.penalty = 0
        self.attempts = []
        self.assignment_order = []
        self.excluded = []
        self.insertions = []
        self.reasons = {}
        self.initial = None
        self.exchanged = None
        self.exchange_log = []
        self.swap_log = []
        self.placements = {}
        self.slot_placements = {}

    def by_size(self, course_ids):
        return sorted(course_ids, key=lambda c: (-self.courses[c].size(), c))

    def by_degree(self, course_ids):
        return sorted(course_ids, key=lambda c: (-self.graph.degree(c), c))

    def blocked_students(self, course, slot):
        unavailable = self.calendar.unavailable
        return [s for s in course.students if slot in unavailable.get(s, ())]

    def suitable(self, course, slot):
        if self.calendar.length(slot) < course.duration:
            return False
        return not self.blocked_students(course, slot)

    def packs(self, course_ids):
        return pack(self.rooms, [self.courses[c] for c in course_ids]) is not None

    def outside(self, day_text, period_text):
        return f"slot {day_text} {period_text} outside calendar"

    def validate_calendar(self, lines):
        handlers = {
            "closed": self.accept_closed,
            "unavailable": self.accept_unavailable,
            "fixed": self.accept_fixed,
            "after": self.accept_after,
        }
        for number, line in enumerate(lines[6:], 7):
            kind, *fields = line.split()
            message = handlers[kind](fields)
            if message is not None:
                self.errors.append(f"calendar.txt line {number}: {message}")
        self.open_slots = [s for s in self.calendar.slots() if s not in self.calendar.closed]
        self.fixed_slots = set(self.calendar.fixed.values())

    def accept_closed(self, fields):
        day_text, period_text = fields
        slot = self.calendar.slot_at(day_text, period_text)
        if slot is None:
            return self.outside(day_text, period_text)
        if slot in self.calendar.closed:
            return f"duplicate closed {self.calendar.name(slot)}"
        self.calendar.closed.add(slot)
        return None

    def accept_unavailable(self, fields):
        student, day_text, period_text = fields
        if student not in self.student_courses:
            return f"unknown student {student}"
        slot = self.calendar.slot_at(day_text, period_text)
        if slot is None:
            return self.outside(day_text, period_text)
        blocked = self.calendar.unavailable.setdefault(student, set())
        if slot in blocked:
            return f"duplicate unavailable {student} {self.calendar.name(slot)}"
        blocked.add(slot)
        return None

    def accept_fixed(self, fields):
        course_id, day_text, period_text = fields
        if course_id not in self.courses:
            return f"unknown course {course_id}"
        if course_id not in self.schedulable:
            return f"course {course_id} not schedulable"
        slot = self.calendar.slot_at(day_text, period_text)
        if slot is None:
            return self.outside(day_text, period_text)
        name = self.calendar.name(slot)
        if slot in self.calendar.closed:
            return f"slot {name} closed"
        if not self.suitable(self.courses[course_id], slot):
            return f"slot {name} unsuitable for {course_id}"
        if course_id in self.calendar.fixed:
            return f"duplicate fixed {course_id}"
        group = [c for c, fixed_slot in self.calendar.fixed.items() if fixed_slot == slot]
        clashes = [c for c in group if c in self.graph.neighbours(course_id)]
        if clashes:
            return f"conflict {course_id} {min(clashes)}"
        if not self.packs(group + [course_id]):
            return f"rooms full {name}"
        self.calendar.fixed[course_id] = slot
        return None

    def accept_after(self, fields):
        later, earlier = fields
        for course_id in fields:
            if course_id not in self.courses:
                return f"unknown course {course_id}"
        for course_id in fields:
            if course_id not in self.schedulable:
                return f"course {course_id} not schedulable"
        if later == earlier:
            return f"bad order {later} {earlier}"
        if (later, earlier) in self.calendar.orders:
            return f"duplicate order {later} {earlier}"
        if reachable(self.calendar.arrows, earlier, later):
            return f"cycle {later} {earlier}"
        fixed = self.calendar.fixed
        if later in fixed and earlier in fixed and fixed[later] <= fixed[earlier]:
            return f"fixed order {later} {earlier}"
        self.calendar.orders.append((later, earlier))
        self.calendar.arrows.setdefault(later, []).append(earlier)
        return None

    def courses_at(self, assignment, slot):
        return sorted(c for c, other in assignment.items() if other == slot)

    def order_conflicts(self, course_id, slot, assignment):
        conflicts = []
        for later, earlier in self.calendar.orders:
            if later == course_id and earlier in assignment and slot <= assignment[earlier]:
                conflicts.append(earlier)
            elif earlier == course_id and later in assignment and slot >= assignment[later]:
                conflicts.append(later)
        return conflicts

    def orders_satisfied(self, assignment):
        return all(
            assignment[later] > assignment[earlier]
            for later, earlier in self.calendar.orders
            if later in assignment and earlier in assignment
        )

    def candidate_slots(self, course_id, assignment):
        course = self.courses[course_id]
        neighbours = self.graph.neighbours(course_id)
        candidates = []
        for slot in self.open_slots:
            if not self.suitable(course, slot):
                continue
            if any(assignment.get(other) == slot for other in neighbours):
                continue
            if self.order_conflicts(course_id, slot, assignment):
                continue
            if self.packs(self.courses_at(assignment, slot) + [course_id]):
                candidates.append(slot)
        return candidates

    def build_timetable(self):
        fixed = self.calendar.fixed
        while True:
            pending = [c for c in self.schedulable if c not in fixed and c not in self.excluded]
            assignment = dict(fixed)
            attempt = Attempt(pending, self.graph, self.calendar.limit, self.candidate_slots)
            succeeded = attempt.search(assignment)
            failed_course = None if succeeded else attempt.dead_end_course
            self.attempts.append((len(pending), attempt.dead_ends, failed_course))
            if succeeded:
                break
            self.excluded.append(failed_course)
        self.assignment = assignment
        self.assignment_order = [
            (course_id, assignment[course_id], saturation)
            for course_id, saturation in attempt.chosen
        ]

    def penalty_pairs(self, assignment):
        pairs = []
        for first, second, shared in self.edges:
            if first in assignment and second in assignment:
                relation = self.calendar.relation(assignment[first], assignment[second])
                if relation is not None:
                    pairs.append((first, second, relation, shared))
        return pairs

    def late_courses(self, assignment):
        return [
            c for c in self.front_load
            if c in assignment and assignment[c] > self.calendar.deadline
        ]

    def breakdown(self, assignment):
        counts = [0] * len(RELATIONS)
        for _, _, relation, shared in self.penalty_pairs(assignment):
            counts[relation] += shared
        return Breakdown(counts, len(self.late_courses(assignment)), self.calendar.weights)

    def contributions(self):
        weights = self.calendar.weights
        result = dict.fromkeys(self.assignment, 0)
        for first, second, relation, shared in self.penalty_pairs(self.assignment):
            result[first] += weights[relation] * shared
            result[second] += weights[relation] * shared
        for course_id in self.late_courses(self.assignment):
            result[course_id] += weights[FRONT_LOAD]
        return result

    def blocking_reason(self, course_id, slot):
        course = self.courses[course_id]
        if slot in self.calendar.closed:
            return "closed"
        if self.calendar.length(slot) < course.duration:
            return "too_short"
        blocked = self.blocked_students(course, slot)
        if blocked:
            return f"unavailable {min(blocked)}"
        clashes = [
            (-shared, other)
            for other, shared in self.graph.neighbours(course_id).items()
            if self.assignment.get(other) == slot
        ]
        if clashes:
            shared, other = min(clashes)
            return f"conflict {other} shared {-shared}"
        conflicts = self.order_conflicts(course_id, slot, self.assignment)
        if conflicts:
            return f"order {min(conflicts)}"
        return "rooms"

    def insert_excluded(self):
        for course_id in sorted(self.excluded):
            slots = self.candidate_slots(course_id, self.assignment)
            if not slots:
                self.reasons[course_id] = [
                    self.blocking_reason(course_id, slot) for slot in self.calendar.slots()
                ]
                continue
            before = self.breakdown(self.assignment).total
            totals = {}
            for slot in slots:
                trial = dict(self.assignment)
                trial[course_id] = slot
                totals[slot] = self.breakdown(trial).total
            best = min(slots, key=lambda slot: (totals[slot], slot))
            self.assignment[course_id] = best
            self.insertions.append((course_id, best, totals[best] - before))
        self.initial = self.breakdown(self.assignment)
        self.penalty = self.initial.total

    def unscheduled(self):
        missing = [c for c in self.excluded if c not in self.assignment]
        return sorted(missing + self.oversized)

    def valid_trial(self, trial, moved):
        for course_id in moved:
            if not self.suitable(self.courses[course_id], trial[course_id]):
                return False
        return self.orders_satisfied(trial)

    def moved_courses(self, trial):
        return sorted(c for c in trial if trial[c] != self.assignment[c])

    def exchange_trial(self, first, second):
        if first in self.fixed_slots or second in self.fixed_slots:
            return "fixed", None, None
        trial = dict(self.assignment)
        for course_id, slot in self.assignment.items():
            if slot == first:
                trial[course_id] = second
            elif slot == second:
                trial[course_id] = first
        if not self.valid_trial(trial, self.moved_courses(trial)):
            return "invalid", None, None
        total = self.breakdown(trial).total
        if total >= self.penalty:
            return "worse", None, None
        return "applied", trial, total

    def exchange_slots(self):
        name = self.calendar.name
        round_number = 0
        serial = 0
        while True:
            round_number += 1
            tally = dict.fromkeys(EXCHANGE_VERDICTS, 0)
            records = []
            pairs = 0
            for index, first in enumerate(self.open_slots):
                for second in self.open_slots[index + 1:]:
                    pairs += 1
                    verdict, trial, total = self.exchange_trial(first, second)
                    tally[verdict] += 1
                    if verdict == "applied":
                        serial += 1
                        records.append(
                            f"EXCHANGE {serial} {name(first)} {name(second)} "
                            f"penalty {self.penalty} -> {total}"
                        )
                        self.assignment = trial
                        self.penalty = total
            self.exchange_log.append(
                f"ROUND {round_number} pairs {pairs} {verdict_counts(tally, EXCHANGE_VERDICTS)}"
            )
            self.exchange_log.extend(records)
            if tally["applied"] == 0:
                break
        self.exchanged = self.breakdown(self.assignment)

    def swap_trial(self, course_id, home, target):
        chain = self.graph.kempe_chain(self.assignment, course_id, home, target)
        if any(member in self.calendar.fixed for member in chain):
            return "fixed", None, None
        trial = dict(self.assignment)
        for member in chain:
            trial[member] = target if self.assignment[member] == home else home
        if not self.valid_trial(trial, chain):
            return "invalid", None, None
        if not self.packs(self.courses_at(trial, home)):
            return "rooms", None, None
        if not self.packs(self.courses_at(trial, target)):
            return "rooms", None, None
        total = self.breakdown(trial).total
        if total >= self.penalty:
            return "worse", None, None
        return "applied", trial, total

    def swap_chains(self):
        name = self.calendar.name
        pass_number = 0
        serial = 0
        while True:
            pass_number += 1
            tally = dict.fromkeys(SWAP_VERDICTS, 0)
            records = []
            candidates = 0
            movable = sorted(c for c in self.assignment if c not in self.calendar.fixed)
            for course_id in movable:
                home = self.assignment[course_id]
                for target in self.open_slots:
                    if target == home:
                        continue
                    candidates += 1
                    verdict, trial, total = self.swap_trial(course_id, home, target)
                    tally[verdict] += 1
                    if verdict != "applied":
                        continue
                    serial += 1
                    chain = self.moved_courses(trial)
                    records.append(
                        f"SWAP {serial} {course_id} {name(home)} {name(target)} "
                        f"chain {len(chain)} penalty {self.penalty} -> {total}"
                    )
                    for member in chain:
                        before = name(self.assignment[member])
                        records.append(f"  MOVE {member} {before} -> {name(trial[member])}")
                    self.assignment = trial
                    self.penalty = total
                    break
            self.swap_log.append(
                f"PASS {pass_number} candidates {candidates} "
                f"{verdict_counts(tally, SWAP_VERDICTS)}"
            )
            self.swap_log.extend(records)
            if tally["applied"] == 0:
                break

    def assign_rooms(self):
        for slot in self.open_slots:
            group = [self.courses[c] for c in self.courses_at(self.assignment, slot)]
            placements = pack(self.rooms, group)
            self.slot_placements[slot] = placements
            for placement in placements:
                self.placements[placement.course.id] = placement

    def room_groups(self, slot):
        groups = []
        for room in self.rooms:
            placed = [p for p in self.slot_placements[slot] if p.room is room]
            if placed:
                groups.append((room, placed))
        return groups

    def invigilators(self, slot):
        return sum(
            ceil_div(sum(p.course.size() for p in placed), self.calendar.ratio)
            for _, placed in self.room_groups(slot)
        )

    def slot_load(self, slot):
        course_ids = self.courses_at(self.assignment, slot)
        return len(course_ids), sum(self.courses[c].size() for c in course_ids)

    def student_pairs(self, student):
        assigned = sorted(
            (self.assignment[c], c) for c in self.student_courses[student] if c in self.assignment
        )
        pairs = []
        for index, (low_slot, low_course) in enumerate(assigned):
            for high_slot, high_course in assigned[index + 1:]:
                relation = self.calendar.relation(low_slot, high_slot)
                if relation is not None:
                    pairs.append((relation, low_slot, low_course, high_slot, high_course))
        return pairs

    def student_penalty(self, student):
        counts = [0] * len(RELATIONS)
        for relation, _, _, _, _ in self.student_pairs(student):
            counts[relation] += 1
        weights = self.calendar.weights
        penalty = sum(weights[relation] * count for relation, count in enumerate(counts))
        return counts, penalty

    def assigned_slots(self, student):
        return sorted(
            self.assignment[c] for c in self.student_courses[student] if c in self.assignment
        )

    def timetable_lines(self):
        calendar = self.calendar
        name = calendar.name
        lines = [
            f"TIMETABLE days {calendar.days} periods {calendar.periods} "
            f"open {len(self.open_slots)} courses {len(self.courses)} "
            f"scheduled {len(self.assignment)} unscheduled {len(self.unscheduled())} "
            f"empty {len(self.empty)}"
        ]
        header = [f"P{period}" for period in range(1, calendar.periods + 1)] + ["TOTAL"]
        lines.append(fixed_width_line("DAY", header, GRID_LABEL_WIDTH, GRID_CELL_WIDTH))
        for day in range(1, calendar.days + 1):
            cells = []
            day_exams = 0
            day_students = 0
            for period in range(1, calendar.periods + 1):
                slot = (day - 1) * calendar.periods + period
                if slot in calendar.closed:
                    cells.append("closed")
                    continue
                exams, students = self.slot_load(slot)
                cells.append(f"{exams}/{students}")
                day_exams += exams
                day_students += students
            cells.append(f"{day_exams}/{day_students}")
            lines.append(fixed_width_line(f"D{day}", cells, GRID_LABEL_WIDTH, GRID_CELL_WIDTH))
        for slot in calendar.slots():
            prefix = f"SLOT {slot} {name(slot)} minutes {calendar.length(slot)}"
            if slot in calendar.closed:
                lines.append(prefix + " closed")
                continue
            exams, students = self.slot_load(slot)
            groups = self.room_groups(slot)
            seats = sum(room.capacity for room, _ in groups)
            lines.append(
                f"{prefix} exams {exams} students {students} rooms {len(groups)} "
                f"seats {seats} invigilators {self.invigilators(slot)}"
            )
            for placement in self.slot_placements[slot]:
                course = placement.course
                marker = " fixed" if course.id in calendar.fixed else ""
                lines.append(
                    f"  {course.id} {course.duration}min students {course.size()} "
                    f"room {placement.room.id} seats {placement.first_seat}-{placement.last_seat}"
                    f"{marker} {course.name}"
                )
        for room in self.rooms:
            slots_used = 0
            exams = 0
            seated = 0
            for slot in self.open_slots:
                for group_room, placed in self.room_groups(slot):
                    if group_room is room:
                        slots_used += 1
                        exams += len(placed)
                        seated += sum(p.course.size() for p in placed)
            utilization = rounded_percent(seated, room.capacity * len(self.open_slots))
            lines.append(
                f"ROOM {room.id} capacity {room.capacity} slots {slots_used} exams {exams} "
                f"seated {seated} utilization {utilization}"
            )
        total = sum(self.invigilators(slot) for slot in self.open_slots)
        lines.append(f"INVIGILATORS total {total} ratio {calendar.ratio}")
        return lines

    def room_lines(self):
        lines = ["slot,room,course,students,first_seat,last_seat"]
        for slot in self.open_slots:
            for room, placed in self.room_groups(slot):
                for p in placed:
                    lines.append(
                        f"{self.calendar.name(slot)},{room.id},{p.course.id},"
                        f"{p.course.size()},{p.first_seat},{p.last_seat}"
                    )
        return lines

    def penalty_lines(self):
        calendar = self.calendar
        name = calendar.name
        weights = calendar.weights
        final = self.breakdown(self.assignment)
        lines = [
            f"WEIGHTS back_to_back {weights[BACK_TO_BACK]} same_day {weights[SAME_DAY]} "
            f"overnight {weights[OVERNIGHT]} front_load {weights[FRONT_LOAD]}",
            f"FRONT_LOAD courses {len(self.front_load)} last_slot {name(calendar.deadline)}",
            f"INITIAL {self.initial.text()}",
        ]
        lines.extend(self.exchange_log)
        lines.append(f"EXCHANGED {self.exchanged.text()}")
        lines.extend(self.swap_log)
        lines.append(f"FINAL {final.text()}")
        lines.append(f"SAVED {self.initial.total - final.total}")
        daily = {day: [0] * len(RELATIONS) for day in range(1, calendar.days + 1)}
        for first, second, relation, shared in self.penalty_pairs(self.assignment):
            day = calendar.day_of(min(self.assignment[first], self.assignment[second]))
            daily[day][relation] += shared
        for day, counts in daily.items():
            lines.append(
                f"DAY D{day} back_to_back {counts[BACK_TO_BACK]} same_day {counts[SAME_DAY]} "
                f"overnight {counts[OVERNIGHT]}"
            )
        for course_id in self.late_courses(self.assignment):
            slot = self.assignment[course_id]
            lines.append(
                f"LATE {course_id} {name(slot)} students {self.courses[course_id].size()}"
            )
        contributions = self.contributions()
        ranked = sorted(contributions, key=lambda c: (-contributions[c], c))[:COURSE_LINES]
        for course_id in ranked:
            if contributions[course_id] > 0:
                slot = self.assignment[course_id]
                lines.append(
                    f"COURSE {course_id} {name(slot)} penalty {contributions[course_id]}"
                )
        lines.extend(self.student_statistics())
        return lines

    def student_statistics(self):
        histogram = Counter()
        gaps = Counter()
        day_loads = Counter()
        ranking = []
        for student in self.student_courses:
            counts, penalty = self.student_penalty(student)
            histogram[penalty] += 1
            ranking.append((-penalty, student, counts))
            slots = self.assigned_slots(student)
            for low, high in zip(slots, slots[1:]):
                gaps[high - low] += 1
            if slots:
                per_day = Counter(self.calendar.day_of(slot) for slot in slots)
                day_loads[max(per_day.values())] += 1
        lines = [f"HISTOGRAM {value} {histogram[value]}" for value in sorted(histogram)]
        lines.extend(f"GAP {gap} {gaps[gap]}" for gap in sorted(gaps))
        lines.extend(f"DAYLOAD {load} {day_loads[load]}" for load in sorted(day_loads))
        ranking.sort()
        for negative_penalty, student, counts in ranking[:WORST_LINES]:
            if negative_penalty < 0:
                lines.append(
                    f"WORST {student} penalty {-negative_penalty} "
                    f"back_to_back {counts[BACK_TO_BACK]} same_day {counts[SAME_DAY]} "
                    f"overnight {counts[OVERNIGHT]}"
                )
        return lines

    def schedule_lines(self, queries):
        name = self.calendar.name
        lines = []
        for student in queries:
            if student not in self.student_courses:
                lines.append(f"STUDENT {student} not found")
                continue
            course_ids = self.student_courses[student]
            assigned = sorted((self.assignment[c], c) for c in course_ids if c in self.assignment)
            _, penalty = self.student_penalty(student)
            lines.append(
                f"STUDENT {student} exams {len(course_ids)} scheduled {len(assigned)} "
                f"penalty {penalty}"
            )
            for slot, course_id in assigned:
                placement = self.placements[course_id]
                course = placement.course
                seat = placement.first_seat + course.students.index(student)
                lines.append(
                    f"  {name(slot)} {course_id} room {placement.room.id} "
                    f"seat {seat} {course.name}"
                )
            for course_id in course_ids:
                if course_id not in self.assignment:
                    lines.append(f"  UNSCHEDULED {course_id} {self.courses[course_id].name}")
            pairs = self.student_pairs(student)
            for relation, low_slot, low_course, high_slot, high_course in pairs:
                lines.append(
                    f"  {RELATIONS[relation].upper()} {name(low_slot)} {low_course} "
                    f"{name(high_slot)} {high_course}"
                )
            for slot in sorted(self.calendar.unavailable.get(student, ())):
                lines.append(f"  UNAVAILABLE {name(slot)}")
        return lines

    def status_lines(self):
        contributions = self.contributions()
        lines = ["course,status,slot,students,minutes,degree,penalty"]
        for course_id in sorted(self.courses):
            course = self.courses[course_id]
            if course_id in self.calendar.fixed:
                status = "fixed"
            elif course_id in self.assignment:
                status = "scheduled"
            elif course_id in self.oversized:
                status = "too_large"
            elif course_id in self.empty:
                status = "empty"
            else:
                status = "no_slot"
            if course_id in self.assignment:
                slot = self.calendar.name(self.assignment[course_id])
            else:
                slot = "-"
            fields = [
                course_id, status, slot, course.size(), course.duration,
                self.graph.degree(course_id), contributions.get(course_id, 0),
            ]
            lines.append(",".join(str(field) for field in fields))
        return lines

    def graph_lines(self):
        graph = self.graph
        vertex_count = len(graph.vertices)
        edge_count = len(self.edges)
        shared = sum(count for _, _, count in self.edges)
        density = 0
        if vertex_count >= 2:
            density = 2000 * edge_count // (vertex_count * (vertex_count - 1))
        lines = [
            f"GRAPH courses {vertex_count} edges {edge_count} shared {shared} density {density}"
        ]
        for course_id in self.by_degree(graph.vertices)[:DEGREE_LINES]:
            lines.append(
                f"DEGREE {course_id} neighbours {graph.degree(course_id)} "
                f"shared {graph.shared_total(course_id)} "
                f"students {self.courses[course_id].size()}"
            )
        components = graph.components()
        lines.append(f"COMPONENTS {len(components)}")
        for number, component in enumerate(components, 1):
            lines.append(f"COMPONENT {number} size {len(component)} first {component[0]}")
        clique = graph.greedy_clique(self.schedulable)
        lines.append(" ".join(["CLIQUE", "size", str(len(clique))] + clique))
        return lines

    def capacity_lines(self):
        loads = [len(course_ids) for course_ids in self.student_courses.values()]
        most = max(loads)
        demand = sum(self.courses[c].size() for c in self.schedulable)
        capacity = sum(room.capacity for room in self.rooms)
        degree_slots = greedy_numbering(self.by_degree(self.schedulable), self.graph)
        size_slots = greedy_numbering(self.by_size(self.schedulable), self.graph)
        lines = [
            f"LOAD max_exams {most} students {loads.count(most)}",
            f"SEATS demand {demand} capacity {capacity} min_slots {ceil_div(demand, capacity)}",
            f"HEURISTIC largest_degree slots {degree_slots}",
            f"HEURISTIC largest_enrolment slots {size_slots}",
        ]
        table = self.by_size(self.graph.vertices)[:MATRIX_COURSES]
        lines.append(fixed_width_line("MATRIX", table, MATRIX_WIDTH, MATRIX_WIDTH))
        for row in table:
            neighbours = self.graph.neighbours(row)
            cells = ["-" if column == row else str(neighbours.get(column, 0)) for column in table]
            lines.append(fixed_width_line(row, cells, MATRIX_WIDTH, MATRIX_WIDTH))
        return lines

    def report_lines(self):
        calendar = self.calendar
        name = calendar.name
        enrolments = sum(len(course_ids) for course_ids in self.student_courses.values())
        lines = [
            f"INPUT courses {len(self.courses)} enrolments {enrolments} rooms {len(self.rooms)} "
            f"students {len(self.student_courses)} errors {len(self.errors)}"
        ]
        lines.extend(f"ERROR {error}" for error in self.errors)
        lines.extend(self.graph_lines())
        lines.extend(self.capacity_lines())
        lines.extend(f"EMPTY {course_id}" for course_id in self.empty)
        for course_id in self.oversized:
            lines.append(
                f"TOO_LARGE {course_id} students {self.courses[course_id].size()} "
                f"largest_room {self.largest_room}"
            )
        lines.extend(f"CLOSED {name(slot)}" for slot in sorted(calendar.closed))
        for course_id in sorted(calendar.fixed):
            lines.append(f"FIXED {course_id} {name(calendar.fixed[course_id])}")
        lines.extend(f"AFTER {later} {earlier}" for later, earlier in calendar.orders)
        for number, (size, dead_ends, failed_course) in enumerate(self.attempts, 1):
            result = "success" if failed_course is None else f"failed {failed_course}"
            lines.append(f"ATTEMPT {number} courses {size} backtracks {dead_ends} {result}")
        for number, (course_id, slot, saturation) in enumerate(self.assignment_order, 1):
            lines.append(
                f"ORDER {number} {course_id} {name(slot)} saturation {saturation} "
                f"degree {self.graph.degree(course_id)}"
            )
        for course_id, slot, increase in self.insertions:
            lines.append(f"INSERTED {course_id} {name(slot)} penalty {increase}")
        for course_id in self.unscheduled():
            reason = "too_large" if course_id in self.oversized else "no_slot"
            lines.append(
                f"UNSCHEDULED {course_id} reason {reason} "
                f"students {self.courses[course_id].size()}"
            )
            for slot, slot_reason in zip(calendar.slots(), self.reasons.get(course_id, [])):
                lines.append(f"  {name(slot)} {slot_reason}")
        slots_used = len(set(self.assignment.values()))
        lines.append(
            f"SUMMARY scheduled {len(self.assignment)} unscheduled {len(self.unscheduled())} "
            f"slots_used {slots_used} penalty {self.penalty}"
        )
        return lines


def main():
    errors = []
    courses = load_courses(os.path.join(INPUT_DIR, "courses.csv"), errors)
    student_courses = load_enrolments(os.path.join(INPUT_DIR, "enrolments.csv"), courses, errors)
    rooms = load_rooms(os.path.join(INPUT_DIR, "rooms.csv"), errors)
    calendar_lines = read_lines("calendar.txt")
    scheduler = Scheduler(courses, student_courses, rooms, Calendar(calendar_lines), errors)
    scheduler.validate_calendar(calendar_lines)
    scheduler.build_timetable()
    scheduler.insert_excluded()
    scheduler.exchange_slots()
    scheduler.swap_chains()
    scheduler.assign_rooms()
    queries = read_lines("queries.txt")
    write_files(OUTPUT_DIR, [
        ("timetable.txt", scheduler.timetable_lines()),
        ("rooms.csv", scheduler.room_lines()),
        ("penalties.txt", scheduler.penalty_lines()),
        ("student_schedules.txt", scheduler.schedule_lines(queries)),
        ("course_status.csv", scheduler.status_lines()),
        ("report.txt", scheduler.report_lines()),
    ])


if __name__ == "__main__":
    main()
