import sys


TYPES = ("BUG", "TASK", "STORY")
PRIORITIES = ("LOW", "MEDIUM", "HIGH", "CRITICAL")
WORKFLOWS = {
    "BUG": ("OPEN", "TRIAGED", "IN_PROGRESS", "REVIEW", "RESOLVED", "CLOSED", "REOPENED"),
    "TASK": ("OPEN", "IN_PROGRESS", "DONE"),
    "STORY": ("BACKLOG", "READY", "IN_PROGRESS", "REVIEW", "DONE"),
}
TRANSITIONS = {
    "BUG": (
        ("OPEN", "TRIAGED"), ("TRIAGED", "IN_PROGRESS"), ("IN_PROGRESS", "REVIEW"),
        ("REVIEW", "IN_PROGRESS"), ("REVIEW", "RESOLVED"), ("RESOLVED", "CLOSED"),
        ("RESOLVED", "REOPENED"), ("CLOSED", "REOPENED"), ("REOPENED", "IN_PROGRESS"),
    ),
    "TASK": (
        ("OPEN", "IN_PROGRESS"), ("IN_PROGRESS", "OPEN"), ("IN_PROGRESS", "DONE"),
    ),
    "STORY": (
        ("BACKLOG", "READY"), ("READY", "BACKLOG"), ("READY", "IN_PROGRESS"),
        ("IN_PROGRESS", "REVIEW"), ("REVIEW", "IN_PROGRESS"), ("REVIEW", "DONE"),
    ),
}
ALL_STATES = (
    "OPEN", "TRIAGED", "IN_PROGRESS", "REVIEW", "RESOLVED",
    "CLOSED", "REOPENED", "DONE", "BACKLOG", "READY",
)
DONE_STATES = ("RESOLVED", "CLOSED", "DONE")
DUPLICATE_STATES = {"BUG": "CLOSED", "TASK": "DONE", "STORY": "DONE"}
ESTIMATES = (0, 1, 2, 3, 5, 8, 13, 21)
WIP_LIMIT = 3
EQUALITY_OPERATORS = ("=", "!=")
ORDER_OPERATORS = ("=", "!=", "<", "<=", ">", ">=")
CONDITION_OPERATORS = (">=", "<=", "!=", "=", "<", ">", "~")
FIELD_OPERATORS = {
    "id": ORDER_OPERATORS,
    "type": EQUALITY_OPERATORS,
    "status": EQUALITY_OPERATORS,
    "priority": ORDER_OPERATORS,
    "assignee": EQUALITY_OPERATORS,
    "reviewer": EQUALITY_OPERATORS,
    "estimate": ORDER_OPERATORS,
    "sprint": EQUALITY_OPERATORS,
    "comments": ORDER_OPERATORS,
    "blocked": EQUALITY_OPERATORS,
    "done": EQUALITY_OPERATORS,
    "title": ("~",),
}
NONE_FIELDS = ("assignee", "reviewer", "estimate", "sprint")


class CommandError(Exception):
    pass


def display(value):
    return "-" if value is None else str(value)


def yes_no(flag):
    return "yes" if flag else "no"


def number_list(numbers):
    if not numbers:
        return "-"
    return ",".join(str(number) for number in sorted(numbers))


def tokenize(query):
    tokens = []
    current = ""
    for character in query:
        if character in " ()":
            if current:
                tokens.append(current)
                current = ""
            if character != " ":
                tokens.append(character)
        else:
            current += character
    if current:
        tokens.append(current)
    return tokens


def split_condition(token):
    length = 0
    while length < len(token) and "a" <= token[length] <= "z":
        length += 1
    rest = token[length:]
    for operator in CONDITION_OPERATORS:
        if rest.startswith(operator):
            return token[:length], operator, rest[len(operator):]
    return token[:length], None, ""


def is_number(text):
    return len(text) <= 6 and text.isdigit()


def compare(actual, operator, expected):
    if operator == "=":
        return actual == expected
    if operator == "!=":
        return actual != expected
    if actual is None:
        return False
    if operator == "<":
        return actual < expected
    if operator == "<=":
        return actual <= expected
    if operator == ">":
        return actual > expected
    return actual >= expected


class Issue:
    def __init__(self, number, kind, priority, title):
        self.number = number
        self.kind = kind
        self.priority = priority
        self.title = title
        self.state = WORKFLOWS[kind][0]
        self.assignee = None
        self.reviewer = None
        self.estimate = None
        self.sprint = None
        self.comments = 0
        self.blocks = set()
        self.blockers = set()
        self.duplicate = None
        self.duplicates = set()
        self.history = []

    def done(self):
        return self.state in DONE_STATES

    def points(self):
        return 0 if self.estimate is None else self.estimate

    def level(self):
        return PRIORITIES.index(self.priority)


class Sprint:
    def __init__(self, name):
        self.name = name
        self.phase = "PLANNED"
        self.start = None
        self.end = None
        self.velocity = 0
        self.records = {}


class Condition:
    def __init__(self, field, operator, value):
        self.field = field
        self.operator = operator
        self.value = value

    def matches(self, tracker, issue):
        actual = tracker.field_value(issue, self.field)
        if self.operator == "~":
            return self.value in actual
        return compare(actual, self.operator, self.value)


class NotNode:
    def __init__(self, operand):
        self.operand = operand

    def matches(self, tracker, issue):
        return not self.operand.matches(tracker, issue)


class BinaryNode:
    def __init__(self, operator, left, right):
        self.operator = operator
        self.left = left
        self.right = right

    def matches(self, tracker, issue):
        if self.operator == "AND":
            return self.left.matches(tracker, issue) and self.right.matches(tracker, issue)
        return self.left.matches(tracker, issue) or self.right.matches(tracker, issue)


class QueryParser:
    def __init__(self, tokens, conditions):
        self.tokens = tokens
        self.conditions = conditions
        self.position = 0

    def accept(self, token):
        if self.position < len(self.tokens) and self.tokens[self.position] == token:
            self.position += 1
            return True
        return False

    def expression(self):
        node = self.term()
        while self.accept("OR"):
            node = BinaryNode("OR", node, self.term())
        return node

    def term(self):
        node = self.factor()
        while self.accept("AND"):
            node = BinaryNode("AND", node, self.factor())
        return node

    def factor(self):
        if self.accept("NOT"):
            return NotNode(self.factor())
        if self.accept("("):
            node = self.expression()
            self.accept(")")
            return node
        condition = self.conditions[self.position]
        self.position += 1
        return condition


class Tracker:
    def __init__(self):
        self.day = 1
        self.users = set()
        self.issues = {}
        self.sprints = {}
        self.output = []

    def emit(self, *parts):
        self.output.append(" ".join(str(part) for part in parts))

    def require_issue(self, text):
        number = int(text)
        if number not in self.issues:
            raise CommandError("unknown issue")
        return self.issues[number]

    def require_user(self, spec):
        if spec == "-":
            return None
        if spec not in self.users:
            raise CommandError("unknown user")
        return spec

    def require_sprint(self, name):
        if name not in self.sprints:
            raise CommandError("unknown sprint")
        return self.sprints[name]

    def require_not_done(self, issue):
        if issue.done():
            raise CommandError("issue done")

    def ordered_issues(self):
        return [self.issues[number] for number in sorted(self.issues)]

    def unfinished_blockers(self, issue):
        return [
            number for number in sorted(issue.blockers)
            if not self.issues[number].done()
        ]

    def is_blocked(self, issue):
        return not issue.done() and len(self.unfinished_blockers(issue)) > 0

    def wip_count(self, user):
        return sum(
            issue.assignee == user and issue.state == "IN_PROGRESS"
            for issue in self.issues.values()
        )

    def active_sprint(self):
        for sprint in self.sprints.values():
            if sprint.phase == "ACTIVE":
                return sprint
        return None

    def members(self, sprint):
        return [issue for issue in self.ordered_issues() if issue.sprint == sprint.name]

    def remaining_points(self, sprint):
        return sum(issue.points() for issue in self.members(sprint) if not issue.done())

    def summary(self, sprint):
        members = self.members(sprint)
        total = sum(issue.points() for issue in members)
        return f"issues {len(members)} points {total}"

    def record(self, issue, content):
        issue.history.append(f"day {self.day} {content}")

    def blocked_states(self, numbers):
        return {number: self.is_blocked(self.issues[number]) for number in numbers}

    def notify(self, before):
        for number in sorted(before):
            after = self.is_blocked(self.issues[number])
            if after and not before[number]:
                self.emit("BLOCKED", number)
            elif before[number] and not after:
                self.emit("UNBLOCKED", number)

    def change_state(self, issue, state):
        before = self.blocked_states(issue.blocks)
        self.emit("MOVE", issue.number, issue.state, state)
        self.record(issue, f"MOVE {issue.state} {state}")
        issue.state = state
        self.notify(before)

    def reaches(self, start, goal):
        pending = [start.number]
        visited = set()
        while pending:
            number = pending.pop()
            if number == goal.number:
                return True
            if number in visited:
                continue
            visited.add(number)
            pending.extend(self.issues[number].blocks)
        return False

    def set_day(self, arguments):
        day = int(arguments[0])
        if day < self.day:
            raise CommandError("day backwards")
        self.day = day
        self.emit("DAY", day)

    def add_user(self, arguments):
        user = arguments[0]
        if user in self.users:
            raise CommandError("user exists")
        self.users.add(user)
        self.emit("USER", user)

    def create(self, arguments):
        number = int(arguments[0])
        kind, priority = arguments[1], arguments[2]
        if number in self.issues:
            raise CommandError("issue exists")
        if kind not in TYPES:
            raise CommandError("bad type")
        if priority not in PRIORITIES:
            raise CommandError("bad priority")
        issue = Issue(number, kind, priority, " ".join(arguments[3:]))
        self.issues[number] = issue
        self.record(issue, f"CREATE {kind} {priority}")
        self.emit("CREATE", number, kind, priority, issue.state)

    def set_priority(self, arguments):
        issue = self.require_issue(arguments[0])
        priority = arguments[1]
        if priority not in PRIORITIES:
            raise CommandError("bad priority")
        self.require_not_done(issue)
        if priority == issue.priority:
            raise CommandError("no change")
        previous = issue.priority
        issue.priority = priority
        self.record(issue, f"PRIORITY {previous} {priority}")
        self.emit("PRIORITY", issue.number, previous, priority)

    def assign(self, arguments):
        issue = self.require_issue(arguments[0])
        spec = arguments[1]
        user = self.require_user(spec)
        self.require_not_done(issue)
        if user == issue.assignee:
            raise CommandError("no change")
        if user is None and issue.state in ("IN_PROGRESS", "REVIEW"):
            raise CommandError("assignee required")
        if issue.state == "IN_PROGRESS" and self.wip_count(user) >= WIP_LIMIT:
            raise CommandError(f"wip limit {spec}")
        if issue.state == "REVIEW" and user == issue.reviewer:
            raise CommandError("reviewer is assignee")
        issue.assignee = user
        self.record(issue, f"ASSIGN {spec}")
        self.emit("ASSIGN", issue.number, spec)

    def set_reviewer(self, arguments):
        issue = self.require_issue(arguments[0])
        spec = arguments[1]
        user = self.require_user(spec)
        self.require_not_done(issue)
        if user == issue.reviewer:
            raise CommandError("no change")
        if user is None and issue.state == "REVIEW":
            raise CommandError("reviewer required")
        if issue.state == "REVIEW" and user == issue.assignee:
            raise CommandError("reviewer is assignee")
        issue.reviewer = user
        self.record(issue, f"REVIEWER {spec}")
        self.emit("REVIEWER", issue.number, spec)

    def set_estimate(self, arguments):
        issue = self.require_issue(arguments[0])
        points = int(arguments[1])
        if points not in ESTIMATES:
            raise CommandError("bad estimate")
        self.require_not_done(issue)
        if points == issue.estimate:
            raise CommandError("no change")
        previous = display(issue.estimate)
        issue.estimate = points
        self.record(issue, f"ESTIMATE {previous} {points}")
        self.emit("ESTIMATE", issue.number, previous, points)

    def comment(self, arguments):
        issue = self.require_issue(arguments[0])
        user = self.require_user(arguments[1])
        text = " ".join(arguments[2:])
        issue.comments += 1
        self.record(issue, f"COMMENT {user} {text}")
        self.emit("COMMENT", issue.number, issue.comments)

    def move(self, arguments):
        issue = self.require_issue(arguments[0])
        target = arguments[1]
        if issue.duplicate is not None:
            raise CommandError(f"duplicate of {issue.duplicate}")
        if target not in WORKFLOWS[issue.kind]:
            raise CommandError("bad state")
        if (issue.state, target) not in TRANSITIONS[issue.kind]:
            raise CommandError(f"cannot move {issue.state} to {target}")
        if target == "IN_PROGRESS":
            active = self.active_sprint()
            if issue.kind == "STORY" and (active is None or issue.sprint != active.name):
                raise CommandError("not in active sprint")
            if issue.assignee is None:
                raise CommandError("no assignee")
            if self.wip_count(issue.assignee) >= WIP_LIMIT:
                raise CommandError(f"wip limit {issue.assignee}")
        if target == "REVIEW":
            if issue.reviewer is None:
                raise CommandError("no reviewer")
            if issue.reviewer == issue.assignee:
                raise CommandError("reviewer is assignee")
        if target in ("DONE", "RESOLVED"):
            blockers = self.unfinished_blockers(issue)
            if blockers:
                raise CommandError(f"blocked by {blockers[0]}")
        if target == "READY" and issue.estimate is None:
            raise CommandError("no estimate")
        self.change_state(issue, target)

    def link(self, arguments):
        relation = arguments[1]
        if relation not in ("BLOCKS", "DUPLICATES"):
            raise CommandError("bad link")
        source = self.require_issue(arguments[0])
        target = self.require_issue(arguments[2])
        if source is target:
            raise CommandError("self link")
        if relation == "BLOCKS":
            self.link_blocks(source, target)
        else:
            self.link_duplicates(source, target)

    def link_blocks(self, source, target):
        if target.number in source.blocks:
            raise CommandError("link exists")
        if self.reaches(target, source):
            raise CommandError("cycle")
        self.require_not_done(target)
        before = self.blocked_states([target.number])
        source.blocks.add(target.number)
        target.blockers.add(source.number)
        self.record(source, f"LINK BLOCKS {target.number}")
        self.record(target, f"LINK BLOCKED_BY {source.number}")
        self.emit("LINK", source.number, "BLOCKS", target.number)
        self.notify(before)

    def link_duplicates(self, source, target):
        if source.kind != target.kind:
            raise CommandError("type mismatch")
        self.require_not_done(source)
        if target.duplicate is not None:
            raise CommandError("target is duplicate")
        source.duplicate = target.number
        target.duplicates.add(source.number)
        self.record(source, f"LINK DUPLICATES {target.number}")
        self.record(target, f"LINK DUPLICATED_BY {source.number}")
        self.emit("LINK", source.number, "DUPLICATES", target.number)
        self.change_state(source, DUPLICATE_STATES[source.kind])
        if source.sprint is not None and self.sprints[source.sprint].phase != "ENDED":
            self.record(source, f"SPRINT REMOVE {source.sprint}")
            source.sprint = None

    def unlink(self, arguments):
        if arguments[1] != "BLOCKS":
            raise CommandError("bad link")
        source = self.require_issue(arguments[0])
        target = self.require_issue(arguments[2])
        if target.number not in source.blocks:
            raise CommandError("no link")
        before = self.blocked_states([target.number])
        source.blocks.remove(target.number)
        target.blockers.remove(source.number)
        self.record(source, f"UNLINK BLOCKS {target.number}")
        self.record(target, f"UNLINK BLOCKED_BY {source.number}")
        self.emit("UNLINK", source.number, "BLOCKS", target.number)
        self.notify(before)

    def new_sprint(self, arguments):
        name = arguments[0]
        if name in self.sprints:
            raise CommandError("sprint exists")
        self.sprints[name] = Sprint(name)
        self.emit("SPRINT", "NEW", name)

    def add_to_sprint(self, arguments):
        sprint = self.require_sprint(arguments[0])
        issue = self.require_issue(arguments[1])
        if sprint.phase == "ENDED":
            raise CommandError("sprint ended")
        self.require_not_done(issue)
        if issue.sprint is not None and self.sprints[issue.sprint].phase != "ENDED":
            raise CommandError(f"in sprint {issue.sprint}")
        if issue.state == "BACKLOG":
            raise CommandError("not ready")
        issue.sprint = sprint.name
        self.record(issue, f"SPRINT ADD {sprint.name}")
        self.emit("SPRINT", "ADD", sprint.name, issue.number, self.summary(sprint))

    def remove_from_sprint(self, arguments):
        sprint = self.require_sprint(arguments[0])
        issue = self.require_issue(arguments[1])
        if sprint.phase == "ENDED":
            raise CommandError("sprint ended")
        if issue.sprint != sprint.name:
            raise CommandError("not in sprint")
        self.require_not_done(issue)
        issue.sprint = None
        self.record(issue, f"SPRINT REMOVE {sprint.name}")
        self.emit("SPRINT", "REMOVE", sprint.name, issue.number, self.summary(sprint))

    def start_sprint(self, arguments):
        sprint = self.require_sprint(arguments[0])
        if sprint.phase != "PLANNED":
            raise CommandError("sprint not planned")
        active = self.active_sprint()
        if active is not None:
            raise CommandError(f"sprint active {active.name}")
        if not self.members(sprint):
            raise CommandError("sprint empty")
        sprint.phase = "ACTIVE"
        sprint.start = self.day
        remaining = self.remaining_points(sprint)
        sprint.records[self.day] = remaining
        self.emit(
            "SPRINT", "START", sprint.name, "day", sprint.start,
            self.summary(sprint), "remaining", remaining,
        )

    def end_sprint(self, arguments):
        sprint = self.require_sprint(arguments[0])
        if sprint.phase != "ACTIVE":
            raise CommandError("sprint not active")
        sprint.records[self.day] = self.remaining_points(sprint)
        members = self.members(sprint)
        finished = [issue for issue in members if issue.done()]
        returned = [issue for issue in members if not issue.done()]
        sprint.velocity = sum(issue.points() for issue in finished)
        sprint.phase = "ENDED"
        sprint.end = self.day
        self.emit(
            "SPRINT", "END", sprint.name, "day", sprint.end,
            "velocity", sprint.velocity, "done", len(finished), "returned", len(returned),
        )
        for issue in returned:
            issue.sprint = None
            self.record(issue, f"SPRINT RETURN {sprint.name}")
            self.emit("RETURNED", issue.number)

    def sprint(self, arguments):
        handlers = {
            "NEW": self.new_sprint,
            "ADD": self.add_to_sprint,
            "REMOVE": self.remove_from_sprint,
            "START": self.start_sprint,
            "END": self.end_sprint,
        }
        handlers[arguments[0]](arguments[1:])

    def field_value(self, issue, field):
        if field == "id":
            return issue.number
        if field == "type":
            return issue.kind
        if field == "status":
            return issue.state
        if field == "priority":
            return issue.level()
        if field == "assignee":
            return issue.assignee
        if field == "reviewer":
            return issue.reviewer
        if field == "estimate":
            return issue.estimate
        if field == "sprint":
            return issue.sprint
        if field == "comments":
            return issue.comments
        if field == "blocked":
            return yes_no(self.is_blocked(issue))
        if field == "done":
            return yes_no(issue.done())
        return issue.title.lower()

    def condition_value(self, token, field, operator, text):
        if text == "-" and field in NONE_FIELDS and operator in EQUALITY_OPERATORS:
            return None
        if field in ("id", "estimate", "comments") and is_number(text):
            return int(text)
        if field == "priority" and text in PRIORITIES:
            return PRIORITIES.index(text)
        if field == "type" and text in TYPES:
            return text
        if field == "status" and text in ALL_STATES:
            return text
        if field in ("assignee", "reviewer") and text in self.users:
            return text
        if field == "sprint" and text in self.sprints:
            return text
        if field in ("blocked", "done") and text in ("yes", "no"):
            return text
        if field == "title":
            return text.lower()
        raise CommandError(f"bad value {token}")

    def condition(self, token):
        field, operator, text = split_condition(token)
        if not field or operator is None or not text:
            raise CommandError(f"syntax near {token}")
        if field not in FIELD_OPERATORS:
            raise CommandError(f"unknown field {field}")
        if operator not in FIELD_OPERATORS[field]:
            raise CommandError(f"bad operator {token}")
        return Condition(field, operator, self.condition_value(token, field, operator, text))

    def check_query(self, tokens):
        conditions = []
        expecting_operand = True
        depth = 0
        for token in tokens:
            condition = None
            if expecting_operand:
                if token == "(":
                    depth += 1
                elif token in ("AND", "OR", ")"):
                    raise CommandError(f"syntax near {token}")
                elif token != "NOT":
                    condition = self.condition(token)
                    expecting_operand = False
            elif token in ("AND", "OR"):
                expecting_operand = True
            elif token == ")" and depth > 0:
                depth -= 1
            else:
                raise CommandError(f"syntax near {token}")
            conditions.append(condition)
        if expecting_operand or depth != 0:
            raise CommandError("syntax at end")
        return conditions

    def query(self, arguments):
        tokens = tokenize(" ".join(arguments))
        conditions = self.check_query(tokens)
        tree = QueryParser(tokens, conditions).expression()
        matches = [issue for issue in self.issues.values() if tree.matches(self, issue)]
        matches.sort(key=lambda issue: (-issue.level(), issue.number))
        self.emit("QUERY", len(matches))
        for issue in matches:
            self.emit(
                issue.number, issue.kind, issue.priority, issue.state,
                display(issue.assignee), display(issue.estimate), issue.title,
            )

    def show(self, arguments):
        issue = self.require_issue(arguments[0])
        self.emit(
            "ISSUE", issue.number, issue.kind, issue.priority, issue.state,
            "blocked", yes_no(self.is_blocked(issue)),
        )
        self.emit("TITLE", issue.title)
        self.emit("PEOPLE", "assignee", display(issue.assignee), "reviewer", display(issue.reviewer))
        self.emit(
            "PLAN", "estimate", display(issue.estimate),
            "sprint", display(issue.sprint), "comments", issue.comments,
        )
        self.emit(
            "LINKS", "blocks", number_list(issue.blocks),
            "blocked_by", number_list(issue.blockers),
            "duplicate_of", display(issue.duplicate),
            "duplicated_by", number_list(issue.duplicates),
        )

    def show_history(self, arguments):
        issue = self.require_issue(arguments[0])
        self.emit("HISTORY", issue.number, len(issue.history))
        for line in issue.history:
            self.emit(line)

    def board(self, arguments):
        issues = list(self.issues.values())
        self.emit("BOARD")
        for kind in TYPES:
            parts = [kind]
            for state in WORKFLOWS[kind]:
                count = sum(issue.kind == kind and issue.state == state for issue in issues)
                parts.extend((state, count))
            self.emit(*parts)
        finished = sum(issue.done() for issue in issues)
        self.emit("TOTAL", len(issues), "open", len(issues) - finished, "done", finished)

    def workload(self, arguments):
        issues = list(self.issues.values())
        self.emit("WORKLOAD", len(self.users))
        for user in sorted(self.users):
            assigned = [issue for issue in issues if issue.assignee == user and not issue.done()]
            in_progress = sum(issue.state == "IN_PROGRESS" for issue in assigned)
            review = sum(issue.state == "REVIEW" for issue in assigned)
            reviewing = sum(
                issue.reviewer == user and issue.state == "REVIEW" for issue in issues
            )
            points = sum(issue.points() for issue in assigned)
            self.emit(
                user, "assigned", len(assigned), "in_progress", in_progress,
                "review", review, "reviewing", reviewing, "points", points,
            )

    def list_sprints(self, arguments):
        self.emit("SPRINTS", len(self.sprints))
        for sprint in self.sprints.values():
            if sprint.phase == "PLANNED":
                self.emit(sprint.name, "PLANNED", self.summary(sprint))
            elif sprint.phase == "ACTIVE":
                self.emit(
                    sprint.name, "ACTIVE", "start", sprint.start, self.summary(sprint),
                    "remaining", self.remaining_points(sprint),
                )
            else:
                self.emit(
                    sprint.name, "ENDED", "start", sprint.start, "end", sprint.end,
                    "velocity", sprint.velocity,
                )

    def burndown(self, arguments):
        sprint = self.require_sprint(arguments[0])
        if sprint.phase == "PLANNED":
            raise CommandError("sprint not started")
        last = self.day if sprint.phase == "ACTIVE" else sprint.end
        self.emit("BURNDOWN", sprint.name, sprint.phase, "days", last - sprint.start + 1)
        value = 0
        for day in range(sprint.start, last + 1):
            if day in sprint.records:
                value = sprint.records[day]
            self.emit("day", day, value)

    def execute(self, line):
        command, *arguments = line.split(" ")
        handlers = {
            "DAY": self.set_day,
            "USER": self.add_user,
            "CREATE": self.create,
            "PRIORITY": self.set_priority,
            "ASSIGN": self.assign,
            "REVIEWER": self.set_reviewer,
            "ESTIMATE": self.set_estimate,
            "COMMENT": self.comment,
            "MOVE": self.move,
            "LINK": self.link,
            "UNLINK": self.unlink,
            "SPRINT": self.sprint,
            "QUERY": self.query,
            "SHOW": self.show,
            "HISTORY": self.show_history,
            "BOARD": self.board,
            "WORKLOAD": self.workload,
            "SPRINTS": self.list_sprints,
            "BURNDOWN": self.burndown,
        }
        try:
            handlers[command](arguments)
        except CommandError as error:
            self.emit("ERROR", error)
        active = self.active_sprint()
        if active is not None:
            active.records[self.day] = self.remaining_points(active)


def main():
    tracker = Tracker()
    count = int(sys.stdin.readline())
    for _ in range(count):
        tracker.execute(sys.stdin.readline().rstrip("\n"))
    sys.stdout.write("\n".join(tracker.output) + "\n")


if __name__ == "__main__":
    main()
