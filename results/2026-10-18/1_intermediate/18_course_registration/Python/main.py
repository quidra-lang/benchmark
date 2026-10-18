import sys


DAYS = ("MO", "TU", "WE", "TH", "FR", "SA", "SU")
GRADE_POINTS = {"A": 4, "B": 3, "C": 2, "D": 1, "F": 0}


class CommandError(Exception):
    pass


class ParseError(Exception):
    pass


def time_text(minutes):
    return f"{minutes // 60:02d}:{minutes % 60:02d}"


def rate_text(count, capacity):
    return str(count * 100 // capacity) + "%" if capacity else "n/a"


def course_word(word):
    prefix, suffix = word[:-3], word[-3:]
    return 2 <= len(prefix) <= 4 and all("A" <= char <= "Z" for char in prefix) and len(suffix) == 3 and all("0" <= char <= "9" for char in suffix)


def year_word(word):
    return len(word) == 2 and word[0] == "Y" and "1" <= word[1] <= "9"


class Expression:
    def __init__(self, kind, children=(), word=None):
        self.kind = kind
        self.children = children
        self.word = word
        self.references = {word} if kind == "WORD" and not year_word(word) else set()
        for child in children:
            self.references.update(child.references)

    def canonical(self):
        if self.kind == "TRUE":
            return "-"
        if self.kind == "WORD":
            return self.word
        parts = []
        for child in self.children:
            text = child.canonical()
            if self.kind == "AND" and child.kind == "OR":
                text = "(" + text + ")"
            parts.append(text)
        return ("&" if self.kind == "AND" else "|").join(parts)

    def evaluate(self, student):
        if self.kind == "TRUE":
            return True
        if self.kind == "WORD":
            return student.year >= int(self.word[1]) if year_word(self.word) else self.word in student.passed
        if self.kind == "AND":
            return all(child.evaluate(student) for child in self.children)
        return any(child.evaluate(student) for child in self.children)


def combine(kind, children):
    flattened = []
    for child in children:
        if child.kind == kind:
            flattened.extend(child.children)
        else:
            flattened.append(child)
    return flattened[0] if len(flattened) == 1 else Expression(kind, flattened)


class PrerequisiteParser:
    def __init__(self, text):
        self.tokens = []
        self.position = 0
        index = 0
        while index < len(text):
            if text[index] in "&|()":
                self.tokens.append(text[index])
                index += 1
                continue
            start = index
            while index < len(text) and ("A" <= text[index] <= "Z" or "0" <= text[index] <= "9"):
                index += 1
            if start == index:
                raise ParseError()
            word = text[start:index]
            if not (course_word(word) or year_word(word)):
                raise ParseError()
            self.tokens.append(word)

    def peek(self):
        return self.tokens[self.position] if self.position < len(self.tokens) else None

    def factor(self):
        token = self.peek()
        if token is None or token in ("&", "|", ")"):
            raise ParseError()
        self.position += 1
        if token == "(":
            expression = self.expression()
            if self.peek() != ")":
                raise ParseError()
            self.position += 1
            return expression
        return Expression("WORD", word=token)

    def term(self):
        children = [self.factor()]
        while self.peek() == "&":
            self.position += 1
            children.append(self.factor())
        return combine("AND", children)

    def expression(self):
        children = [self.term()]
        while self.peek() == "|":
            self.position += 1
            children.append(self.term())
        return combine("OR", children)

    def parse(self):
        result = self.expression()
        if self.position != len(self.tokens):
            raise ParseError()
        return result


def prerequisite(code, text):
    if text == "-":
        return Expression("TRUE")
    try:
        expression = PrerequisiteParser(text).parse()
    except ParseError:
        raise CommandError(f"invalid prereq {code}") from None
    if code in expression.references:
        raise CommandError(f"self prereq {code}")
    return expression


class Slot:
    def __init__(self, text):
        day = text[:2]
        start_hour, start_minute = int(text[2:4]), int(text[4:6])
        end_hour, end_minute = int(text[7:9]), int(text[9:11])
        if day not in DAYS or start_hour > 23 or end_hour > 23 or start_minute > 59 or end_minute > 59:
            raise CommandError(f"invalid slot {text}")
        self.start = start_hour * 60 + start_minute
        self.end = end_hour * 60 + end_minute
        if self.start >= self.end:
            raise CommandError(f"invalid slot {text}")
        self.day = DAYS.index(day)
        self.original = text

    def overlaps(self, other):
        return self.day == other.day and self.start < other.end and other.start < self.end

    def text(self):
        return time_text(self.start) + "-" + time_text(self.end)


class Course:
    def __init__(self, code, credits, capacity, slots, expression):
        self.code = code
        self.credits = credits
        self.capacity = capacity
        self.slots = slots
        self.prerequisite = expression
        self.open = True
        self.enrolled = set()
        self.waitlist = []
        self.conflicts = set()

    def status(self):
        return "open" if self.open else "closed"

    def weekly(self):
        return sum(slot.end - slot.start for slot in self.slots)

    def department(self):
        return self.code[:-3]


class Student:
    def __init__(self, identifier, year, limit, records):
        self.identifier = identifier
        self.year = year
        self.limit = limit
        self.records = records
        self.passed = {code: grade for code, (grade, _) in records.items() if grade in ("A", "B", "C")}
        self.courses = set()
        self.waiting = set()
        self.credits = 0
        self.history = []

    def earned(self):
        return sum(credits for grade, credits in self.records.values() if grade != "F")

    def gpa(self):
        if not self.records:
            return "n/a"
        points = sum(GRADE_POINTS[grade] * credits for grade, credits in self.records.values())
        credits = sum(credits for _, credits in self.records.values())
        value = (200 * points + credits) // (2 * credits)
        return f"{value // 100}.{value % 100:02d}"


class Registrar:
    def __init__(self):
        self.courses = {}
        self.students = {}
        self.command = 0
        self.output = []

    def emit(self, *parts, indent=0):
        self.output.append(" " * indent + " ".join(str(part) for part in parts))

    def student(self, identifier):
        if identifier not in self.students:
            raise CommandError(f"unknown student {identifier}")
        return self.students[identifier]

    def course(self, code):
        if code not in self.courses:
            raise CommandError(f"unknown course {code}")
        return self.courses[code]

    def record(self, student, event):
        student.history.append((self.command, event))

    def conflict(self, student, course, excluded=None):
        codes = student.courses & course.conflicts
        codes.discard(excluded)
        return min(codes) if codes else None

    def eligibility(self, student, course, excluded=None):
        if not course.open:
            return "course closed", ()
        if course.code in student.courses:
            return "already enrolled", ()
        if course.code in student.waiting:
            return "already waitlisted", ()
        if course.code in student.passed:
            return "already completed", (student.passed[course.code],)
        if not course.prerequisite.evaluate(student):
            return "prereq not met", ()
        conflict = self.conflict(student, course, excluded)
        if conflict is not None:
            return "time conflict", (conflict,)
        total = student.credits + course.credits
        if excluded is not None:
            total -= self.courses[excluded].credits
        if total > student.limit:
            return "credit limit", (total, student.limit)
        return None

    def wait_position(self, student, course):
        return 1 + sum(other.year >= student.year for other in course.waitlist)

    def request(self, student, course):
        failure = self.eligibility(student, course)
        if failure is not None:
            return failure
        if len(course.enrolled) < course.capacity:
            return "enroll", ()
        if len(student.waiting) >= 3:
            return "waitlist limit", ()
        return "waitlist", (self.wait_position(student, course),)

    def fail_request(self, decision, student, course):
        reason, extra = decision
        raise CommandError(" ".join(str(part) for part in (reason, student.identifier, course.code, *extra)))

    def enroll(self, student, course):
        course.enrolled.add(student.identifier)
        student.courses.add(course.code)
        student.credits += course.credits

    def withdraw(self, student, course):
        course.enrolled.remove(student.identifier)
        student.courses.remove(course.code)
        student.credits -= course.credits

    def unlist(self, student, course):
        course.waitlist.remove(student)
        student.waiting.remove(course.code)

    def promotion(self):
        for code in sorted(self.courses):
            course = self.courses[code]
            if not course.open:
                continue
            for student in course.waitlist.copy():
                if len(course.enrolled) >= course.capacity:
                    break
                if self.conflict(student, course) is not None or student.credits + course.credits > student.limit:
                    continue
                self.unlist(student, course)
                self.enroll(student, course)
                self.record(student, "promote " + code)
                self.emit(
                    "PROMOTE", student.identifier, code, "enrolled", f"{len(course.enrolled)}/{course.capacity}",
                    "credits", f"{student.credits}/{student.limit}", indent=2,
                )

    def cmd_course(self, code, credits, capacity, timetable, text):
        if code in self.courses:
            raise CommandError(f"duplicate course {code}")
        slots = [] if timetable == "-" else [Slot(value) for value in timetable.split(",")]
        for first in range(len(slots)):
            for second in range(first + 1, len(slots)):
                if slots[first].overlaps(slots[second]):
                    raise CommandError(f"overlapping slots {slots[first].original} {slots[second].original}")
        expression = prerequisite(code, text)
        course = Course(code, int(credits), int(capacity), slots, expression)
        for other in self.courses.values():
            if any(first.overlaps(second) for first in slots for second in other.slots):
                course.conflicts.add(other.code)
                other.conflicts.add(code)
        self.courses[code] = course
        self.emit(
            "COURSE", code, "credits", credits, "capacity", capacity, "meetings", len(slots),
            "weekly", time_text(course.weekly()), "prereq", expression.canonical(),
        )

    def cmd_student(self, identifier, year, limit, text):
        if identifier in self.students:
            raise CommandError(f"duplicate student {identifier}")
        records = {}
        if text != "-":
            for value in text.split(","):
                code, grade, credits = value.split(":")
                if grade not in GRADE_POINTS:
                    raise CommandError(f"invalid grade {identifier} {code} {grade}")
                if code in records:
                    raise CommandError(f"duplicate record {identifier} {code}")
                records[code] = grade, int(credits)
        student = Student(identifier, int(year), int(limit), records)
        self.students[identifier] = student
        self.emit(
            "STUDENT", identifier, "year", year, "limit", limit, "records", len(records),
            "earned", student.earned(), "gpa", student.gpa(),
        )

    def cmd_enroll(self, identifier, code):
        student = self.student(identifier)
        course = self.course(code)
        decision = self.request(student, course)
        kind, extra = decision
        if kind not in ("enroll", "waitlist"):
            self.fail_request(decision, student, course)
        if kind == "enroll":
            self.enroll(student, course)
            self.record(student, "enroll " + code)
            self.emit(
                "ENROLL", identifier, code, "enrolled", f"{len(course.enrolled)}/{course.capacity}",
                "credits", f"{student.credits}/{student.limit}",
            )
        else:
            position = extra[0]
            course.waitlist.insert(position - 1, student)
            student.waiting.add(code)
            self.record(student, f"waitlist {code} {position}")
            self.emit("ENROLL", identifier, code, "waitlist", position)

    def cmd_check(self, identifier, code):
        student = self.student(identifier)
        course = self.course(code)
        kind, extra = self.request(student, course)
        self.emit("CHECK", identifier, code, kind, *extra)

    def cmd_options(self, identifier):
        student = self.student(identifier)
        self.emit("OPTIONS", identifier, "courses", len(self.courses))
        for code in sorted(self.courses):
            kind, extra = self.request(student, self.courses[code])
            self.emit(code, kind, *extra, indent=2)

    def cmd_drop(self, identifier, code):
        student = self.student(identifier)
        course = self.course(code)
        if code in student.courses:
            self.withdraw(student, course)
            self.record(student, "drop " + code)
            self.emit(
                "DROP", identifier, code, "enrolled", f"{len(course.enrolled)}/{course.capacity}",
                "credits", f"{student.credits}/{student.limit}",
            )
        elif code in student.waiting:
            self.unlist(student, course)
            self.record(student, "drop " + code + " waitlist")
            self.emit("DROP", identifier, code, "waitlist removed")
        else:
            raise CommandError(f"not registered {identifier} {code}")
        self.promotion()

    def cmd_swap(self, identifier, first, second):
        student = self.student(identifier)
        source = self.course(first)
        destination = self.course(second)
        if first not in student.courses:
            raise CommandError(f"not enrolled {identifier} {first}")
        if first == second:
            raise CommandError(f"same course {first}")
        failure = self.eligibility(student, destination, first)
        if failure is not None:
            self.fail_request(failure, student, destination)
        if len(destination.enrolled) >= destination.capacity:
            raise CommandError(f"course full {second}")
        self.withdraw(student, source)
        self.enroll(student, destination)
        self.record(student, f"swap {first} {second}")
        self.emit("SWAP", identifier, first, "->", second, "credits", f"{student.credits}/{student.limit}")
        self.promotion()

    def cmd_close(self, code):
        course = self.course(code)
        if not course.open:
            raise CommandError(f"already closed {code}")
        course.open = False
        self.emit("CLOSE", code, "enrolled", f"{len(course.enrolled)}/{course.capacity}", "waitlist", len(course.waitlist))

    def cmd_open(self, code):
        course = self.course(code)
        if course.open:
            raise CommandError(f"already open {code}")
        course.open = True
        self.emit("OPEN", code, "enrolled", f"{len(course.enrolled)}/{course.capacity}", "waitlist", len(course.waitlist))
        self.promotion()

    def cmd_capacity(self, code, number):
        course = self.course(code)
        capacity = int(number)
        if capacity < len(course.enrolled):
            raise CommandError(f"capacity below enrollment {code} {len(course.enrolled)}")
        previous = course.capacity
        course.capacity = capacity
        self.emit("CAPACITY", code, previous, "->", number)
        self.promotion()

    def cmd_limit(self, identifier, number):
        student = self.student(identifier)
        limit = int(number)
        if limit < student.credits:
            raise CommandError(f"limit below enrolled {identifier} {student.credits}")
        previous = student.limit
        student.limit = limit
        self.emit("LIMIT", identifier, previous, "->", number)
        self.promotion()

    def cmd_prereq(self, code, text):
        course = self.course(code)
        expression = prerequisite(code, text)
        course.prerequisite = expression
        self.emit("PREREQ", code, expression.canonical())
        for student in course.waitlist.copy():
            if not expression.evaluate(student):
                self.unlist(student, course)
                self.record(student, "unlist " + code)
                self.emit("UNLIST", student.identifier, code, indent=2)

    def cmd_cancel(self, code):
        course = self.course(code)
        self.emit("CANCEL", code, "enrolled", len(course.enrolled), "waitlist", len(course.waitlist))
        for identifier in sorted(course.enrolled):
            student = self.students[identifier]
            student.courses.remove(code)
            student.credits -= course.credits
            self.record(student, "cancel " + code)
        for student in course.waitlist:
            student.waiting.remove(code)
            self.record(student, "cancel " + code + " waitlist")
        for other in course.conflicts:
            self.courses[other].conflicts.discard(code)
        del self.courses[code]
        self.promotion()

    def cmd_roster(self, code):
        course = self.course(code)
        self.emit("ROSTER", code, course.status(), "enrolled", f"{len(course.enrolled)}/{course.capacity}", "waitlist", len(course.waitlist))
        for identifier in sorted(course.enrolled):
            self.emit("enrolled", identifier, "year", self.students[identifier].year, indent=2)
        for position, student in enumerate(course.waitlist, 1):
            self.emit("waitlist", position, student.identifier, "year", student.year, indent=2)

    def student_slots(self, student, day):
        return sorted(
            (slot.start, slot.end, code)
            for code in student.courses
            for slot in self.courses[code].slots
            if slot.day == day
        )

    def cmd_schedule(self, identifier):
        student = self.student(identifier)
        weekly = sum(self.courses[code].weekly() for code in student.courses)
        self.emit("SCHEDULE", identifier, "courses", len(student.courses), "credits", student.credits, "weekly", time_text(weekly))
        for day, name in enumerate(DAYS):
            slots = self.student_slots(student, day)
            if slots:
                parts = [name]
                for start, end, code in slots:
                    parts.extend((time_text(start) + "-" + time_text(end), code))
                self.emit(*parts, indent=2)
        pending_times = sorted(code for code in student.courses if not self.courses[code].slots)
        if pending_times:
            self.emit("TBA", *pending_times, indent=2)

    def cmd_free(self, identifier, day):
        student = self.student(identifier)
        if day not in DAYS:
            raise CommandError(f"invalid day {day}")
        occupied = []
        for start, end, _ in self.student_slots(student, DAYS.index(day)):
            start, end = max(480, start), min(1320, end)
            if start < end:
                occupied.append((start, end))
        free = []
        cursor = 480
        for start, end in occupied:
            if cursor < start:
                free.append((cursor, start))
            cursor = max(cursor, end)
        if cursor < 1320:
            free.append((cursor, 1320))
        total = sum(end - start for start, end in free)
        self.emit("FREE", identifier, day, "total", time_text(total), *(time_text(start) + "-" + time_text(end) for start, end in free))

    def cmd_info(self, code):
        course = self.course(code)
        self.emit(
            "INFO", code, course.status(), "credits", course.credits, "capacity", course.capacity,
            "prereq", course.prerequisite.canonical(),
        )
        for slot in sorted(course.slots, key=lambda slot: (slot.day, slot.start)):
            self.emit("meet", DAYS[slot.day], slot.text(), indent=2)
        if not course.slots:
            self.emit("meet TBA", indent=2)
        required_by = sorted(other.code for other in self.courses.values() if code in other.prerequisite.references)
        self.emit("required by", *(required_by or ["none"]), indent=2)

    def cmd_audit(self, identifier):
        student = self.student(identifier)
        self.emit("AUDIT", identifier, "year", student.year, "limit", student.limit)
        for code in sorted(student.records):
            grade, credits = student.records[code]
            self.emit("record", code, grade, credits, indent=2)
        self.emit("earned", student.earned(), "gpa", student.gpa(), indent=2)
        for code in sorted(student.courses):
            self.emit("enrolled", code, self.courses[code].credits, indent=2)
        self.emit("credits", student.credits, "remaining", student.limit - student.credits, indent=2)
        for code in sorted(student.waiting):
            position = self.courses[code].waitlist.index(student) + 1
            self.emit("waitlist", code, position, indent=2)

    def cmd_history(self, identifier):
        student = self.student(identifier)
        self.emit("HISTORY", identifier, "events", len(student.history))
        for number, event in student.history:
            self.emit(number, event, indent=2)

    def cmd_students(self):
        self.emit("STUDENTS", len(self.students))
        for identifier in sorted(self.students):
            student = self.students[identifier]
            self.emit(
                identifier, "year", student.year, "credits", f"{student.credits}/{student.limit}",
                "courses", len(student.courses), "waitlists", len(student.waiting), indent=2,
            )

    def group_counts(self, courses):
        enrolled = sum(len(course.enrolled) for course in courses)
        capacity = sum(course.capacity for course in courses)
        waitlisted = sum(len(course.waitlist) for course in courses)
        return "enrolled", f"{enrolled}/{capacity}", "rate", rate_text(enrolled, capacity), "waitlisted", waitlisted

    def cmd_report(self):
        self.emit("REPORT", "courses", len(self.courses), *self.group_counts(list(self.courses.values())))
        departments = {}
        for code in sorted(self.courses):
            course = self.courses[code]
            self.emit(
                code, course.status(), f"{len(course.enrolled)}/{course.capacity}",
                rate_text(len(course.enrolled), course.capacity), "waitlist", len(course.waitlist), indent=2,
            )
            departments.setdefault(course.department(), []).append(course)
        for department in sorted(departments):
            courses = departments[department]
            self.emit("dept", department, "courses", len(courses), *self.group_counts(courses), indent=2)

    def execute(self, text):
        self.command += 1
        command, *arguments = text.split()
        try:
            getattr(self, "cmd_" + command.lower())(*arguments)
        except CommandError as error:
            self.emit("ERROR", str(error))


def main():
    count = int(sys.stdin.readline())
    registrar = Registrar()
    for _ in range(count):
        registrar.execute(sys.stdin.readline())
    sys.stdout.write("\n".join(registrar.output) + "\n")


if __name__ == "__main__":
    main()
