"""Consulting, explicit SLD execution, term writing, and the five reports."""

from collections import Counter
from dataclasses import dataclass
from pathlib import Path
from types import SimpleNamespace

from database import Clause, Database
from predicates import DETERMINISTIC, execute, require_integer
from reader import INFIX, PREFIX, SYMBOLS, Reader, SyntaxError
from terms import (Ball, Compound, Fault, Variable, copy_term, dereference, domain_error,
                   indicator, indicator_term, list_parts, make_list, type_error, variables_in)
from unify import Trail


CONTROLS = {(",", 2), ("!", 0), (";", 2), ("->", 2), ("\\+", 1), ("catch", 3)}
CONTROLS.update(("call", arity) for arity in range(1, 9))
BUILTINS = DETERMINISTIC | {("findall", 3), ("throw", 1), ("between", 3), ("length", 2)}


def goal_conversion(term):
    term = dereference(term)
    if isinstance(term, Variable):
        return Compound("call", term)
    if isinstance(term, int):
        return None
    if isinstance(term, Compound) and term.name in {",", ";", "->"} and len(term.args) == 2:
        left = goal_conversion(term.args[0])
        if left is None:
            return None
        right = goal_conversion(term.args[1])
        return None if right is None else Compound(term.name, left, right)
    return term


def atom_name(name, quoted):
    plain = (name in {"[]", "!", ";"}
             or bool(name) and name[0].islower() and all(c.isalnum() or c == "_" for c in name)
             or bool(name) and name != "." and all(c in SYMBOLS for c in name))
    if not quoted or plain:
        return name
    escaped = name.replace("\\", "\\\\").replace("'", "\\'").replace("\n", "\\n").replace("\t", "\\t")
    return "'" + escaped + "'"


class Writer:
    def __init__(self, names=None, quoted=True):
        self.names = {} if names is None else names.copy()
        self.next_name = 1
        self.quoted = quoted

    def write(self, term, limit=1200, operand=False):
        term = dereference(term)
        if isinstance(term, Variable):
            if term not in self.names:
                self.names[term] = f"_G{self.next_name}"
                self.next_name += 1
            return self.names[term]
        if isinstance(term, int):
            return str(term)
        if isinstance(term, str):
            text = atom_name(term, self.quoted)
            return "(" + text + ")" if operand and (term in INFIX or term in PREFIX) else text
        name, arguments = term.name, term.args
        if name == "." and len(arguments) == 2:
            elements, tail = list_parts(term)
            text = "[" + ",".join(self.write(element, 999) for element in elements)
            if tail != "[]":
                text += "|" + self.write(tail, 999)
            return text + "]"
        if len(arguments) == 2 and name in INFIX:
            priority, left_limit, right_limit = INFIX[name]
            left = self.write(arguments[0], left_limit, True)
            right = self.write(arguments[1], right_limit, True)
            if name == ",":
                text = left + "," + right
            elif name[0].isalpha():
                text = left + " " + name + " " + right
            else:
                before = " " if left and left[-1] in SYMBOLS else ""
                after = " " if right and right[0] in SYMBOLS else ""
                text = left + before + name + after + right
            return "(" + text + ")" if priority > limit else text
        if len(arguments) == 1 and name in PREFIX:
            priority = PREFIX[name]
            argument = self.write(arguments[0], priority, True)
            space = " " if argument and (argument[0] in SYMBOLS or argument[0].isdigit() or argument[0] == "(") else ""
            text = name + space + argument
            return "(" + text + ")" if priority > limit else text
        return atom_name(name, self.quoted) + "(" + ",".join(self.write(a, 999) for a in arguments) + ")"


def predicate_name(key):
    return Writer().write(indicator_term(key))


class Consultant:
    def __init__(self):
        self.database = Database()
        self.lines = []
        self.counts = {"prelude.pl": [0, 0, 0], "program.pl": [0, 0, 0]}
        self.last = {"prelude.pl": None, "program.pl": None}
        self.discontiguous = set()

    def warning(self, file, line, message):
        self.lines.append(f"{file}:{line}: warning: {message}")
        self.counts[file][2] += 1

    def add(self, term, file, line, reader):
        head, body = term, None
        if isinstance(term, Compound) and indicator(term) == (":-", 2):
            head, body = term.args
        error = None
        if isinstance(head, Variable):
            error = "instantiation_error"
        elif isinstance(head, int):
            error = type_error("callable", head)
        elif indicator(head) in CONTROLS | BUILTINS:
            error = Compound("permission_error", "modify", "static_procedure", indicator_term(indicator(head)))
        elif body is not None:
            converted = goal_conversion(body)
            if converted is None:
                error = type_error("callable", body)
            else:
                body = converted
        if error is not None:
            self.lines.append(f"{file}:{line}: error: {Writer().write(error)}")
            self.counts[file][1] += 1
            return
        key = indicator(head)
        previous = self.database.predicates.get(key, [])
        if file == "program.pl" and any(clause.file == "prelude.pl" for clause in previous):
            self.warning(file, line, f"redefining prelude procedure {predicate_name(key)}")
            self.database.predicates[key] = []
            previous = []
        if (any(clause.file == file for clause in previous) and self.last[file] != key
                and (file, key) not in self.discontiguous):
            self.warning(file, line, f"clauses of {predicate_name(key)} are not together")
            self.discontiguous.add((file, key))
        self.database.add(Clause(head, body, file, line))
        self.last[file] = key
        self.counts[file][0] += 1
        singletons = [name for name, count in reader.counts.items() if not name.startswith("_") and count == 1]
        repeated = [name for name, count in reader.counts.items() if len(name) > 1 and name.startswith("_") and count > 1]
        if singletons:
            self.warning(file, line, "singleton variables: " + ", ".join(singletons))
        if repeated:
            self.warning(file, line, "variables starting with _ occur more than once: " + ", ".join(repeated))

    def consult(self, file, text):
        reader = Reader(text)
        source_lines = text.split("\n")
        while reader.peek().kind != "eof":
            line = reader.peek().line
            try:
                term = reader.clause()
            except SyntaxError as error:
                token = error.token
                self.counts[file][1] += 1
                self.lines.append(f"{file}:{token.line}:{token.column}: syntax error: {error.message}")
                if token.kind != "eof":
                    self.lines.extend(["    " + source_lines[token.line - 1], " " * (token.column + 3) + "^"])
                reader.position = token.index
                while reader.peek().kind not in {"end", "eof"}:
                    reader.take()
                if reader.peek().kind == "end":
                    reader.take()
                continue
            self.add(term, file, line, reader)

    def finish(self):
        reported = set()
        for source, clauses in self.database.predicates.items():
            for clause in clauses:
                pending = [] if clause.body is None else [clause.body]
                while pending:
                    term = dereference(pending.pop())
                    if isinstance(term, (Variable, int)):
                        continue
                    key = indicator(term)
                    if key in {(",", 2), (";", 2), ("->", 2)}:
                        pending.extend(reversed(term.args))
                    elif key in {("\\+", 1), ("call", 1)}:
                        pending.append(term.args[0])
                    elif key == ("findall", 3):
                        pending.append(term.args[1])
                    elif key == ("catch", 3):
                        pending.extend([term.args[2], term.args[0]])
                    elif key not in CONTROLS | BUILTINS and key not in self.database.predicates and key not in reported:
                        reported.add(key)
                        self.warning(clause.file, clause.line,
                                     f"undefined procedure {predicate_name(key)} called from {predicate_name(source)}")
        for file, (clauses, errors, warnings) in self.counts.items():
            self.lines.append(f"{file}: clauses={clauses} errors={errors} warnings={warnings}")
        count = sum(len(clauses) for clauses in self.database.predicates.values())
        self.lines.append(f"database: predicates={len(self.database.predicates)} clauses={count}")


def listing(database):
    lines = []
    for clauses in database.predicates.values():
        if lines:
            lines.append("")
        for clause in clauses:
            occurrences = variables_in(clause.head, clause.body)
            counts = Counter(occurrences)
            names = {}
            number = 0
            for variable in occurrences:
                if variable in names:
                    continue
                if counts[variable] == 1:
                    names[variable] = "_"
                else:
                    suffix = "" if number < 26 else str(number // 26)
                    names[variable] = chr(65 + number % 26) + suffix
                    number += 1
            writer = Writer(names)
            head = writer.write(clause.head)
            if clause.body is None:
                lines.append(head + ".")
                continue
            lines.append(head + " :-")
            goals, body = [], clause.body
            while isinstance(body, Compound) and indicator(body) == (",", 2):
                goals.append(body.args[0])
                body = body.args[1]
            goals.append(body)
            for i, goal in enumerate(goals):
                lines.append("    " + writer.write(goal, 999) + ("." if i + 1 == len(goals) else ","))
    return lines


def answer(query_variables):
    names = {}
    for name, variable in query_variables:
        value = dereference(variable)
        if isinstance(value, Variable):
            names.setdefault(value, name)
    writer = Writer(names)
    previous = {}
    items = []
    for name, variable in query_variables:
        value = dereference(variable)
        if isinstance(value, Variable):
            if value in previous:
                items.append(f"{previous[value]} = {name}")
            previous[value] = name
        else:
            items.append(f"{name} = {writer.write(value, 699, True)}")
    return ", ".join(items) if items else "true"


@dataclass
class Marker:
    kind: str
    payload: object


class InferenceLimit(Exception):
    pass


def prepend(continuation, *entries):
    for entry in reversed(entries):
        continuation = (entry, continuation)
    return continuation


class Engine:
    def __init__(self, database, query, query_variables, limit, calls, tries):
        self.database = database
        self.query_variables = query_variables
        self.limit = limit
        self.calls, self.tries = calls, tries
        self.trail = Trail()
        self.goals = prepend(None, (Compound("call", query), 0, None))
        self.choices = []
        self.context = None
        self.current_key = None
        self.solutions = self.inferences = self.choicepoints = self.backtracks = 0
        self.answers = []
        self.output = []

    def create_choice(self, kind, resume, **fields):
        choice = SimpleNamespace(kind=kind, mark=self.trail.mark(), resume=resume, **fields)
        self.choices.append(choice)
        self.choicepoints += 1
        return choice

    def infer(self, key):
        if self.inferences == 20000:
            raise InferenceLimit()
        self.inferences += 1
        self.calls[key] += 1

    def write_output(self, term, quoted):
        self.output.append("\n" if term is None else Writer(quoted=quoted).write(term))

    def try_clause(self, clause, goal, barrier, context, continuation):
        self.tries[indicator(goal)] += 1
        head, body = clause.copy()
        if not self.trail.unify(head, goal):
            return False
        self.goals = continuation if body is None else prepend(continuation, (body, barrier, context))
        return True

    def user_call(self, goal, context):
        key = indicator(goal)
        if key not in self.database.predicates:
            raise Fault(Compound("existence_error", "procedure", indicator_term(key)))
        candidates = self.database.candidates(goal)
        if not candidates:
            return False
        height = len(self.choices)
        if len(candidates) > 1:
            self.create_choice("CLAUSES", self.goals, goal=goal, candidates=candidates,
                               next=1, barrier=height, context=context)
        return self.try_clause(candidates[0], goal, height, context, self.goals)

    def control(self, goal, barrier, context):
        key = indicator(goal)
        args = goal.args if isinstance(goal, Compound) else ()
        continuation = self.goals
        height = len(self.choices)
        if key == (",", 2):
            self.goals = prepend(continuation, (args[0], barrier, context), (args[1], barrier, context))
        elif key == ("!", 0):
            del self.choices[barrier:]
        elif key == (";", 2):
            self.create_choice("ALT", prepend(continuation, (args[1], barrier, context)))
            left = dereference(args[0])
            if isinstance(left, Compound) and indicator(left) == ("->", 2):
                condition, then = left.args
                self.goals = prepend(continuation, (condition, height + 1, context),
                                     (Marker("ITE", height), barrier, context), (then, barrier, context))
            else:
                self.goals = prepend(continuation, (left, barrier, context))
        elif key == ("->", 2):
            self.goals = prepend(continuation, (args[0], height, context),
                                 (Marker("ITE", height), barrier, context), (args[1], barrier, context))
        elif key == ("\\+", 1):
            self.create_choice("ALT", continuation)
            self.goals = prepend(continuation, (Compound("call", args[0]), barrier, context),
                                 (Marker("NAF", height), barrier, context))
        elif key[0] == "call":
            target = dereference(args[0])
            if isinstance(target, Variable):
                raise Fault("instantiation_error")
            if isinstance(target, int):
                raise Fault(type_error("callable", target))
            if len(args) > 1:
                target = (Compound(target, *args[1:]) if isinstance(target, str)
                          else Compound(target.name, *target.args, *args[1:]))
            converted = goal_conversion(target)
            if converted is None:
                raise Fault(type_error("callable", target))
            self.goals = prepend(continuation, (converted, height, context))
        elif key == ("catch", 3):
            frame = self.create_choice("CATCH", continuation, catcher=args[1], recovery=args[2], parent=context)
            self.goals = prepend(continuation, (Compound("call", args[0]), barrier, frame),
                                 (Marker("EXIT", frame), barrier, context))
        return True

    def marker(self, marker):
        kind, payload = marker.kind, marker.payload
        if kind in {"ITE", "NAF"}:
            del self.choices[payload:]
            return kind == "ITE"
        if kind == "EXIT":
            if self.choices and self.choices[-1] is payload:
                self.choices.pop()
            return True
        payload.results.append(copy_term(payload.template))
        return False

    def between(self, args):
        lower = require_integer(args[0])
        upper = require_integer(args[1])
        value = dereference(args[2])
        if not isinstance(value, (Variable, int)):
            raise Fault(type_error("integer", value))
        if isinstance(value, int):
            return lower <= value <= upper
        if lower > upper:
            return False
        if lower < upper:
            self.create_choice("BETWEEN", self.goals, upper=upper, target=value, next=lower + 1)
        return self.trail.unify(value, lower)

    def length(self, args):
        sequence, number = args[0], dereference(args[1])
        if not isinstance(number, (Variable, int)):
            raise Fault(type_error("integer", number))
        if isinstance(number, int) and number < 0:
            raise Fault(domain_error("not_less_than_zero", number))
        elements, tail = list_parts(sequence)
        count = len(elements)
        if tail == "[]":
            return self.trail.unify(number, count)
        if not isinstance(tail, Variable):
            raise Fault(type_error("list", sequence))
        if isinstance(number, int):
            if number < count:
                return False
            return self.trail.unify(tail, make_list([Variable() for _ in range(number - count)]))
        self.create_choice("LENGTH", self.goals, tail=tail, number=number, count=count, next=count + 1)
        return self.trail.unify(tail, "[]") and self.trail.unify(number, count)

    def step(self):
        (goal, barrier, context), self.goals = self.goals
        self.context = context
        if isinstance(goal, Marker):
            return self.marker(goal)
        goal = dereference(goal)
        key = self.current_key = indicator(goal)
        if key in CONTROLS:
            return self.control(goal, barrier, context)
        self.infer(key)
        if key == ("findall", 3):
            template, body, result = goal.args
            frame = self.create_choice("FINDALL", self.goals, template=template, result=result, results=[])
            self.goals = prepend(None, (Compound("call", body), barrier, context),
                                 (Marker("COLLECT", frame), barrier, context))
            return True
        if key == ("throw", 1):
            ball = dereference(goal.args[0])
            if isinstance(ball, Variable):
                raise Fault("instantiation_error")
            raise Ball(ball)
        if key == ("between", 3):
            return self.between(goal.args)
        if key == ("length", 2):
            return self.length(goal.args)
        if key in DETERMINISTIC:
            return execute(goal, self.trail, self.write_output)
        return self.user_call(goal, context)

    def backtrack(self):
        while True:
            self.backtracks += 1
            while self.choices:
                choice = self.choices[-1]
                self.trail.undo(choice.mark)
                if choice.kind == "CATCH":
                    self.choices.pop()
                    continue
                break
            if not self.choices:
                return False
            if choice.kind == "ALT":
                self.choices.pop()
                self.goals = choice.resume
                return True
            if choice.kind == "CLAUSES":
                clause = choice.candidates[choice.next]
                if choice.next + 1 == len(choice.candidates):
                    self.choices.pop()
                else:
                    choice.next += 1
                if self.try_clause(clause, choice.goal, choice.barrier, choice.context, choice.resume):
                    return True
            elif choice.kind == "BETWEEN":
                self.infer(("between", 3))
                value = choice.next
                if value == choice.upper:
                    self.choices.pop()
                else:
                    choice.next += 1
                if self.trail.unify(choice.target, value):
                    self.goals = choice.resume
                    return True
            elif choice.kind == "LENGTH":
                self.infer(("length", 2))
                count = choice.next
                choice.next += 1
                value = make_list([Variable() for _ in range(count - choice.count)])
                if self.trail.unify(choice.tail, value) and self.trail.unify(choice.number, count):
                    self.goals = choice.resume
                    return True
            elif choice.kind == "FINDALL":
                self.choices.pop()
                if self.trail.unify(make_list(choice.results), choice.result):
                    self.goals = choice.resume
                    return True

    def handle_exception(self, ball):
        ball = copy_term(ball)
        frame = self.context
        while frame is not None:
            index = next(i for i, choice in enumerate(self.choices) if choice is frame)
            del self.choices[index:]
            self.trail.undo(frame.mark)
            mark = self.trail.mark()
            if self.trail.unify(copy_term(ball), frame.catcher):
                self.goals = prepend(frame.resume, (Compound("call", frame.recovery), len(self.choices), frame.parent))
                return True
            self.trail.undo(mark)
            frame = frame.parent
        self.answers.append("uncaught exception: " + Writer().write(ball))
        return False

    def run(self):
        while True:
            try:
                if self.goals is None:
                    self.solutions += 1
                    text = answer(self.query_variables)
                    if self.solutions == self.limit or not self.choices:
                        self.answers.append(text + ".")
                        break
                    self.answers.append(text + " ;")
                    success = self.backtrack()
                else:
                    success = self.step()
                    if not success:
                        success = self.backtrack()
                if not success:
                    self.answers.append("false.")
                    break
            except Fault as error:
                if not self.handle_exception(Compound("error", error.term, indicator_term(self.current_key))):
                    break
            except Ball as error:
                if not self.handle_exception(error.term):
                    break
            except InferenceLimit:
                self.answers.append("inference limit exceeded")
                break
        return self.solutions, self.inferences, self.choicepoints, self.backtracks


def statistics(prefix, counts):
    solutions, inferences, choices, backtracks = counts
    return f"{prefix} solutions={solutions} inferences={inferences} choicepoints={choices} backtracks={backtracks}"


def main():
    consultant = Consultant()
    for file in ("prelude.pl", "program.pl"):
        consultant.consult(file, (Path("input") / file).read_bytes().decode("ascii"))
    consultant.finish()
    answers, writes, stats = [], [], []
    calls, tries = Counter(), Counter()
    totals = [0, 0, 0, 0]
    queries = Path("input/queries.txt").read_bytes().decode("ascii").split("\n")[:-1]
    for number, source in enumerate(queries, 1):
        answers.append(source)
        writes.append(f"== query {number} ==\n")
        marker = source.index("?- ")
        limit = None if marker == 0 else int(source[:marker].strip())
        body_start = marker + 3
        reader = Reader(source[body_start:], body_start + 1)
        try:
            query = reader.clause(query=True)
        except SyntaxError as error:
            answers.append(f"syntax error at column {error.token.column}: {error.message}")
            stats.append(f"query {number}: syntax error")
            continue
        variables = [(name, variable) for name, variable in reader.names.items() if not name.startswith("_")]
        engine = Engine(consultant.database, query, variables, limit, calls, tries)
        counts = engine.run()
        totals = [total + count for total, count in zip(totals, counts)]
        answers.extend(engine.answers)
        text = "".join(engine.output)
        writes.append(text + ("\n" if text and not text.endswith("\n") else ""))
        stats.append(statistics(f"query {number}:", counts))
    stats.append(statistics("total:", totals))
    stats.append("== profile ==")
    for key in sorted(calls, key=lambda key: (-calls[key], predicate_name(key))):
        line = f"{predicate_name(key)} calls={calls[key]}"
        if key in consultant.database.predicates:
            line += f" tries={tries[key]}"
        stats.append(line)
    output = Path("output")
    output.mkdir(exist_ok=True)
    reports = {"consult.txt": consultant.lines, "listing.txt": listing(consultant.database),
               "answers.txt": answers, "stats.txt": stats}
    for name, lines in reports.items():
        text = "\n".join(lines) + ("\n" if lines else "")
        (output / name).write_bytes(text.encode("ascii"))
    (output / "write_output.txt").write_bytes("".join(writes).encode("ascii"))


if __name__ == "__main__":
    main()
