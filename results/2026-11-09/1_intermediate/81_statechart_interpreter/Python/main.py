import operator
import re
import sys
from collections import Counter, deque
from dataclasses import dataclass
from functools import cached_property, partial
from itertools import takewhile
from typing import NamedTuple

TOKEN = re.compile(r"\d+|\w+|\|\||&&|[=!<>]=|[-+*/%!()<>]")
PRECEDENCE = [
    ("||",),
    ("&&",),
    ("==", "!=", "<", "<=", ">", ">="),
    ("+", "-"),
    ("*", "/", "%"),
]
OPERATORS = {
    "+": operator.add,
    "-": operator.sub,
    "*": operator.mul,
    "==": operator.eq,
    "!=": operator.ne,
    "<": operator.lt,
    "<=": operator.le,
    ">": operator.gt,
    ">=": operator.ge,
}
ON_LINE = re.compile(
    r"on (\S+) (always|after (\d+)|\S+)(?: \[(.*?)\])?(?: ([-~])> (\S+))?(?: / (.*))?"
)
STATE_KINDS = ("state", "parallel", "final", "history")
LIVELOCK_LIMIT = 1000
RESERVATION_ORDER = operator.attrgetter("due", "number")


class EvaluationError(Exception):
    pass


class Event(NamedTuple):
    name: str
    value: int = 0

    @property
    def display_name(self):
        return self.name if self.value == 0 else f"{self.name}={self.value}"


ERROR_EVENT = Event("error.execution")


class ExpressionParser:
    def __init__(self, text):
        self.tokens = TOKEN.findall(text)
        self.position = 0

    def peek(self):
        if self.position < len(self.tokens):
            return self.tokens[self.position]
        return None

    def advance(self):
        token = self.tokens[self.position]
        self.position += 1
        return token

    def parse(self, level=0):
        if level == len(PRECEDENCE):
            return self.parse_unary()
        node = self.parse(level + 1)
        while self.peek() in PRECEDENCE[level]:
            op = self.advance()
            node = (op, node, self.parse(level + 1))
        return node

    def parse_unary(self):
        token = self.advance()
        if token == "!":
            return ("!", self.parse_unary())
        if token == "-":
            return ("neg", self.parse_unary())
        if token == "(":
            node = self.parse()
            self.advance()
            return node
        if token.isdigit():
            return ("num", int(token))
        if token == "_data":
            return ("data",)
        if token == "in":
            self.advance()
            name = self.advance()
            self.advance()
            return ("in", name)
        return ("var", token)


def parse_expression(text):
    return ExpressionParser(text).parse()


def parse_optional_expression(text):
    return parse_expression(text) if text else None


def expression_references(node):
    match node:
        case ("var", name):
            yield "variable", name
        case ("in", name):
            yield "state", name
        case ("!" | "neg", operand):
            yield from expression_references(operand)
        case (_, left, right):
            yield from expression_references(left)
            yield from expression_references(right)


def apply_operator(op, left, right):
    if op not in ("/", "%"):
        return int(OPERATORS[op](left, right))
    if right == 0:
        raise EvaluationError
    quotient = abs(left) // abs(right)
    if (left < 0) != (right < 0):
        quotient = -quotient
    return quotient if op == "/" else left - quotient * right


@dataclass
class Action:
    kind: str
    name: str = ""
    expression: tuple | None = None
    delay: int = 0
    text: str = ""


def parse_action(text):
    word, _, rest = text.partition(" ")
    match word:
        case "raise":
            event, _, expression = rest.partition(" ")
            return Action("raise", event, parse_optional_expression(expression))
        case "send":
            event, _, rest = rest.partition(" ")
            delay, _, expression = rest.partition(" ")
            return Action("send", event, parse_optional_expression(expression), int(delay))
        case "cancel":
            return Action("cancel", rest)
        case "log" if rest.startswith('"'):
            end = rest.index('"', 1)
            expression = parse_optional_expression(rest[end + 2 :])
            return Action("log", expression=expression, text=rest[1:end])
        case "log":
            return Action("log", expression=parse_expression(rest))
        case _:
            return Action("assign", word, parse_expression(rest.removeprefix("= ")))


def parse_actions(text):
    return [parse_action(part) for part in text.split("; ")]


def action_references(actions):
    for action in actions:
        if action.kind == "assign":
            yield "variable", action.name
        if action.expression is not None:
            yield from expression_references(action.expression)


class State:
    def __init__(self, name, kind, parent, line):
        self.name = name
        self.kind = kind
        self.parent = parent
        self.line = line
        self.deep = False
        self.initial_name = None
        self.default_name = None
        self.initial = None
        self.default = None
        self.children = []
        self.entry_actions = []
        self.exit_actions = []
        self.transitions = []
        self.order = 0
        self.depth = 0

    @cached_property
    def child_states(self):
        return [child for child in self.children if child.kind != "history"]

    @property
    def is_compound(self):
        return self.kind == "state" and bool(self.child_states)

    @property
    def is_parallel(self):
        return self.kind == "parallel" and bool(self.child_states)

    @property
    def is_atomic(self):
        return self.kind != "history" and not self.child_states

    @property
    def initial_child(self):
        return self.initial or self.child_states[0]

    @property
    def default_target(self):
        return self.default or self.parent.initial_child

    def ancestors(self):
        state = self.parent
        while state is not None:
            yield state
            state = state.parent

    def is_descendant_of(self, other):
        return other in self.ancestors()

    def encloses(self, states):
        return all(state.is_descendant_of(self) for state in states)


@dataclass(eq=False)
class Transition:
    source: State
    kind: str
    descriptors: list[str]
    delay: int
    guard: tuple | None
    target: State | None
    local: bool
    actions: list[Action]

    @property
    def timer_name(self):
        return f"after({self.delay})@{self.source.name}"

    def handles(self, event_name):
        return self.kind == "event" and any(
            descriptor in ("*", event_name) or event_name.startswith(descriptor + ".")
            for descriptor in self.descriptors
        )


@dataclass
class Reservation:
    due: int
    number: int
    transition: Transition | None = None
    event: Event | None = None

    def is_timer_of(self, state):
        return self.transition is not None and self.transition.source is state


def document_order(states):
    return sorted(states, key=lambda state: state.order)


def join_names(states):
    return ",".join(state.name for state in states) or "-"


def complete_entry_set(states):
    entering = set(states)
    pending = list(entering)
    while pending:
        state = pending.pop()
        if state.is_parallel:
            children = state.child_states
        elif state.is_compound and entering.isdisjoint(state.child_states):
            children = [state.initial_child]
        else:
            continue
        for child in children:
            if child not in entering:
                entering.add(child)
                pending.append(child)
    return entering


class ChartDefinition:
    def __init__(self, lines):
        self.root = State("", "state", None, 0)
        self.states = {}
        self.variables = {}
        self.errors = {}
        self.ordered = []
        deferred = []
        for number, text in lines:
            kind = text.partition(" ")[0]
            if kind in STATE_KINDS:
                self.record(number, self.define_state(text.split(" "), number))
            elif kind == "var":
                self.record(number, self.declare_variable(text))
            else:
                deferred.append((number, kind, text))
        self.number_states(self.root)
        for state in self.states.values():
            self.record(state.line, self.check_state(state))
        for number, kind, text in deferred:
            if kind == "on":
                self.record(number, self.add_transition(text))
            else:
                self.record(number, self.add_actions(kind, text))

    def record(self, number, error):
        if error is not None:
            self.errors[number] = error

    def define_state(self, words, number):
        kind, name, *rest = words
        parent_name = rest.pop(0) if rest and rest[0] != "initial" else None
        if name in self.states:
            return f"duplicate state {name}"
        parent = self.root
        if parent_name is not None:
            parent = self.states.get(parent_name)
            if parent is None:
                return f"unknown state {parent_name}"
            if parent.kind in ("final", "history"):
                return f"{parent_name} cannot have children"
        state = State(name, kind, parent, number)
        if kind == "history":
            state.deep = rest[0] == "deep"
            state.default_name = rest[1] if len(rest) > 1 else None
        elif rest:
            state.initial_name = rest[1]
        parent.children.append(state)
        self.states[name] = state
        return None

    def declare_variable(self, text):
        _, name, value = text.split(" ")
        if name in self.variables:
            return f"duplicate variable {name}"
        self.variables[name] = int(value)
        return None

    def number_states(self, parent):
        for child in parent.children:
            child.order = len(self.ordered)
            child.depth = parent.depth + 1
            self.ordered.append(child)
            self.number_states(child)

    def check_state(self, state):
        if state.initial_name is not None:
            child = self.states.get(state.initial_name)
            if child is None:
                return f"unknown state {state.initial_name}"
            if child.parent is not state or child.kind == "history":
                return f"{child.name} is not a child of {state.name}"
            state.initial = child
        if state.kind in ("final", "history") and not state.parent.is_compound:
            return f"{state.name} needs a compound parent"
        if state.default_name is not None:
            default = self.states.get(state.default_name)
            if default is None:
                return f"unknown state {state.default_name}"
            if default.kind == "history" or not default.is_descendant_of(state.parent):
                return f"{default.name} is not a descendant of {state.parent.name}"
            state.default = default
        return None

    def find_unknown(self, references):
        for kind, name in references:
            if kind == "variable" and name not in self.variables:
                return f"unknown variable {name}"
            if kind == "state" and name not in self.states:
                return f"unknown state {name}"
        return None

    def add_actions(self, kind, text):
        _, name, _, body = text.split(" ", 3)
        state = self.states.get(name)
        if state is None:
            return f"unknown state {name}"
        if state.kind == "history":
            return f"{name} cannot have actions"
        actions = parse_actions(body)
        error = self.find_unknown(action_references(actions))
        if error is None:
            action_lists = state.entry_actions if kind == "entry" else state.exit_actions
            action_lists.append(actions)
        return error

    def add_transition(self, text):
        match = ON_LINE.fullmatch(text)
        source_name, trigger, delay, guard_text, arrow, target_name, actions_text = match.groups()
        source = self.states.get(source_name)
        if source is None:
            return f"unknown state {source_name}"
        if source.kind in ("final", "history"):
            return f"{source_name} cannot have transitions"
        guard = parse_optional_expression(guard_text)
        actions = parse_actions(actions_text) if actions_text else []
        references = []
        if guard is not None:
            references.extend(expression_references(guard))
        if target_name is not None:
            references.append(("state", target_name))
        references.extend(action_references(actions))
        error = self.find_unknown(references)
        if error is not None:
            return error
        if trigger == "always":
            kind = "always"
        elif delay is not None:
            kind = "after"
        else:
            kind = "event"
        transition = Transition(
            source=source,
            kind=kind,
            descriptors=trigger.split("|") if kind == "event" else [],
            delay=int(delay or 0),
            guard=guard,
            target=self.states[target_name] if target_name else None,
            local=arrow == "~",
            actions=actions,
        )
        source.transitions.append(transition)
        return None

    def unreachable_states(self):
        reachable = set()
        pending = [self.root.initial_child]
        while pending:
            state = pending.pop()
            if state is self.root or state in reachable:
                continue
            reachable.add(state)
            pending.append(state.parent)
            if state.is_compound:
                pending.append(state.initial_child)
            elif state.is_parallel:
                pending.extend(state.child_states)
            for transition in state.transitions:
                target = transition.target
                if target is not None:
                    pending.append(target.default_target if target.kind == "history" else target)
        return [s for s in self.ordered if s.kind != "history" and s not in reachable]


class Machine:
    def __init__(self, chart):
        self.chart = chart
        self.variables = dict(chart.variables)
        self.configuration = set()
        self.current_value = 0
        self.queue = deque()
        self.reservations = []
        self.reservations_created = 0
        self.history = {}
        self.time = 0
        self.trace = False
        self.halted = False
        self.macrosteps = 0
        self.microsteps = 0
        self.steps_in_macrostep = 0
        self.entered = Counter()
        self.taken = Counter()
        self.dwell = Counter()
        self.entry_time = {}

    def evaluate(self, node):
        match node:
            case ("num", value):
                return value
            case ("var", name):
                return self.variables[name]
            case ("data",):
                return self.current_value
            case ("in", name):
                return int(self.chart.states[name] in self.configuration)
            case ("!", operand):
                return int(self.evaluate(operand) == 0)
            case ("neg", operand):
                return -self.evaluate(operand)
            case ("&&", left, right):
                return int(self.evaluate(left) != 0 and self.evaluate(right) != 0)
            case ("||", left, right):
                return int(self.evaluate(left) != 0 or self.evaluate(right) != 0)
            case (op, left, right):
                return apply_operator(op, self.evaluate(left), self.evaluate(right))

    def run_actions(self, actions):
        for action in actions:
            try:
                self.run_action(action)
            except EvaluationError:
                self.queue.append(ERROR_EVENT)
                return

    def run_action(self, action):
        value = 0 if action.expression is None else self.evaluate(action.expression)
        match action.kind:
            case "assign":
                self.variables[action.name] = value
            case "raise":
                self.queue.append(Event(action.name, value))
            case "send":
                self.reserve(action.delay, event=Event(action.name, value))
            case "cancel":
                self.reservations = [
                    reservation
                    for reservation in self.reservations
                    if reservation.event is None or reservation.event.name != action.name
                ]
            case "log":
                print(action.text if action.expression is None else f"{action.text}{value}")

    def reserve(self, delay, transition=None, event=None):
        self.reservations_created += 1
        reservation = Reservation(self.time + delay, self.reservations_created, transition, event)
        self.reservations.append(reservation)

    def guard_holds(self, transition):
        if transition.guard is None:
            return True
        try:
            return self.evaluate(transition.guard) != 0
        except EvaluationError:
            self.queue.append(ERROR_EVENT)
            return False

    def find_transition(self, atomic, matches):
        state = atomic
        while state is not self.chart.root:
            for transition in state.transitions:
                if matches(transition) and self.guard_holds(transition):
                    return transition
            state = state.parent
        return None

    def select(self, matches):
        candidates = []
        for atomic in document_order(s for s in self.configuration if s.is_atomic):
            transition = self.find_transition(atomic, matches)
            if transition is not None and transition not in candidates:
                candidates.append(transition)
        selected = []
        exited = set()
        for transition in candidates:
            exit_set = self.exit_set(self.scope(transition))
            if exited.isdisjoint(exit_set):
                selected.append(transition)
                exited |= exit_set
        return selected

    def effective_targets(self, transition):
        target = transition.target
        if target.kind != "history":
            return [target]
        return self.history.get(target, [target.default_target])

    def scope(self, transition):
        if transition.target is None:
            return None
        targets = self.effective_targets(transition)
        source = transition.source
        if transition.local and source.is_compound and source.encloses(targets):
            return source
        return next(
            ancestor
            for ancestor in source.ancestors()
            if ancestor.is_compound and ancestor.encloses(targets)
        )

    def exit_set(self, scope):
        if scope is None:
            return set()
        return {state for state in self.configuration if state.is_descendant_of(scope)}

    def is_complete(self, state):
        if state.is_compound:
            return any(
                child.kind == "final" and child in self.configuration for child in state.children
            )
        if state.is_parallel:
            return all(self.is_complete(child) for child in state.child_states)
        return False

    def record_history(self, exiting):
        for state in exiting:
            for history in state.children:
                if history.kind != "history":
                    continue
                if history.deep:
                    recorded = [
                        s for s in self.configuration if s.is_atomic and s.is_descendant_of(state)
                    ]
                else:
                    recorded = [s for s in state.child_states if s in self.configuration]
                self.history[history] = document_order(recorded)

    def microstep(self, display_name, transitions):
        scopes = [self.scope(transition) for transition in transitions]
        exiting = set()
        for scope in scopes:
            exiting |= self.exit_set(scope)
        self.record_history(exiting)
        entering = set()
        for transition, scope in zip(transitions, scopes):
            if scope is None:
                continue
            for target in self.effective_targets(transition):
                entering.add(target)
                entering.update(takewhile(lambda state: state is not scope, target.ancestors()))
        exit_order = document_order(exiting)[::-1]
        entry_order = document_order(complete_entry_set(entering))
        if self.trace:
            sources = join_names(transition.source for transition in transitions)
            print(
                f"[t={self.time}] {display_name} ({sources}): "
                f"exit {join_names(exit_order)}; enter {join_names(entry_order)}"
            )
        for state in exit_order:
            self.exit_state(state)
        for transition in transitions:
            self.run_actions(transition.actions)
            self.taken[transition.source] += 1
        self.enter(entry_order)

    def exit_state(self, state):
        for actions in state.exit_actions:
            self.run_actions(actions)
        self.configuration.remove(state)
        self.dwell[state] += self.time - self.entry_time[state]
        self.reservations = [r for r in self.reservations if not r.is_timer_of(state)]

    def enter(self, states):
        for state in states:
            self.configuration.add(state)
            self.entered[state] += 1
            self.entry_time[state] = self.time
            for transition in state.transitions:
                if transition.kind == "after":
                    self.reserve(transition.delay, transition=transition)
            for actions in state.entry_actions:
                self.run_actions(actions)
            if state.kind == "final":
                parent = state.parent
                self.queue.append(Event(f"done.state.{parent.name}"))
                grandparent = parent.parent
                if grandparent.is_parallel and self.is_complete(grandparent):
                    self.queue.append(Event(f"done.state.{grandparent.name}"))

    def take_transitions(self, display_name, matches):
        transitions = self.select(matches)
        if not transitions:
            return False
        if self.steps_in_macrostep == LIVELOCK_LIMIT:
            print(f"LIVELOCK t={self.time}")
            self.halted = True
        else:
            self.steps_in_macrostep += 1
            self.microsteps += 1
            self.microstep(display_name, transitions)
        return True

    def process_event(self, event):
        self.current_value = event.value
        self.take_transitions(event.display_name, lambda t: t.handles(event.name))

    def fire_timer(self, timer):
        self.current_value = 0
        self.take_transitions(timer.timer_name, lambda t: t is timer)

    def enter_initial(self):
        self.current_value = 0
        self.enter(document_order(complete_entry_set([self.chart.root.initial_child])))

    def macrostep(self, first_step):
        self.macrosteps += 1
        self.steps_in_macrostep = 0
        first_step()
        while not self.halted:
            self.current_value = 0
            if self.take_transitions("always", lambda t: t.kind == "always"):
                continue
            if not self.queue:
                break
            self.process_event(self.queue.popleft())

    def tick(self, amount):
        limit = self.time + amount
        while not self.halted:
            due = [r for r in self.reservations if r.due <= limit]
            if not due:
                break
            reservation = min(due, key=RESERVATION_ORDER)
            self.reservations.remove(reservation)
            self.time = reservation.due
            if reservation.event is None:
                self.macrostep(partial(self.fire_timer, reservation.transition))
            else:
                self.macrostep(partial(self.process_event, reservation.event))
        if not self.halted:
            self.time = limit

    def execute(self, command):
        word, _, argument = command.partition(" ")
        match word:
            case "event":
                name, _, value = argument.partition(" ")
                self.macrostep(partial(self.process_event, Event(name, int(value or 0))))
            case "tick":
                self.tick(int(argument))
            case "set":
                name, value = argument.split(" ")
                if name in self.variables:
                    self.variables[name] = int(value)
                else:
                    print(f"error: unknown variable {name}")
            case "trace":
                self.trace = argument == "on"
            case "eval":
                self.evaluate_command(argument)
            case "dump":
                self.dump()

    def evaluate_command(self, text):
        expression = parse_expression(text)
        error = self.chart.find_unknown(expression_references(expression))
        if error is not None:
            print(f"error: {error}")
            return
        self.current_value = 0
        try:
            value = self.evaluate(expression)
        except EvaluationError:
            print("error: division by zero")
        else:
            print(f"{text} -> {value}")

    def dump(self):
        print(f"dump t={self.time}")
        for state in document_order(self.configuration):
            print("  " * state.depth + state.name)
        for name in sorted(self.variables):
            print(f"  var {name} = {self.variables[name]}")
        for state in self.chart.ordered:
            if state in self.history:
                print(f"  history {state.name} = {join_names(self.history[state])}")
        for reservation in sorted(self.reservations, key=RESERVATION_ORDER):
            if reservation.event is None:
                print(f"  timer {reservation.due} {reservation.transition.timer_name}")
            else:
                event = reservation.event
                print(f"  send {reservation.due} {event.name} {event.value}")

    def print_statistics(self):
        print(f"end t={self.time} macrosteps={self.macrosteps} microsteps={self.microsteps}")
        for state in self.chart.ordered:
            if state.kind == "history":
                continue
            dwell = self.dwell[state]
            if state in self.configuration:
                dwell += self.time - self.entry_time[state]
            print(
                f"  {state.name} entered={self.entered[state]} "
                f"taken={self.taken[state]} time={dwell}"
            )


def run_chart(name, definitions, script):
    print(f"chart {name}")
    chart = ChartDefinition(definitions)
    if chart.errors:
        for number in sorted(chart.errors):
            print(f"error line {number}: {chart.errors[number]}")
        return
    for state in chart.unreachable_states():
        print(f"warning: unreachable state {state.name}")
    machine = Machine(chart)
    machine.macrostep(machine.enter_initial)
    for command in script:
        if machine.halted:
            break
        machine.execute(command)
    machine.print_statistics()


def main():
    lines = sys.stdin.read().splitlines()
    position = 1
    for _ in range(int(lines[0])):
        run = lines.index("RUN", position)
        end = lines.index("END", run)
        name = lines[position].removeprefix("CHART ")
        definitions = [(index + 1, lines[index]) for index in range(position + 1, run)]
        run_chart(name, definitions, lines[run + 1 : end])
        position = end + 1


if __name__ == "__main__":
    main()
