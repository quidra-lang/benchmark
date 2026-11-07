import re
import sys
from dataclasses import dataclass, field
from enum import Enum, auto

FUNCTIONS = {
    "subst": (3, 3),
    "patsubst": (3, 3),
    "strip": (1, 1),
    "findstring": (2, 2),
    "filter": (2, 2),
    "filter-out": (2, 2),
    "sort": (1, 1),
    "word": (2, 2),
    "wordlist": (3, 3),
    "words": (1, 1),
    "firstword": (1, 1),
    "lastword": (1, 1),
    "dir": (1, 1),
    "notdir": (1, 1),
    "suffix": (1, 1),
    "basename": (1, 1),
    "addsuffix": (2, 2),
    "addprefix": (2, 2),
    "wildcard": (1, 1),
    "foreach": (3, 3),
    "if": (2, 3),
    "call": (1, None),
    "value": (1, 1),
    "info": (1, 1),
    "warning": (1, 1),
    "error": (1, 1),
}
CONDITIONALS = ("ifeq", "ifneq", "ifdef", "ifndef", "else", "endif")
CLOSING = {"(": ")", "{": "}"}
OPTIONS = "nBkis"


class MakeError(Exception):
    pass


class BuildAborted(Exception):
    pass


class Result(Enum):
    SUCCESS = auto()
    FAILURE = auto()
    DEPENDENCY_FAILURE = auto()


@dataclass
class Variable:
    recursive: bool
    value: str


@dataclass
class RecipeLine:
    line_number: int
    command: str


@dataclass
class ExplicitRule:
    prerequisites: list[str] = field(default_factory=list)
    recipe: list[RecipeLine] | None = None
    stem: str = ""


@dataclass
class PatternRule:
    target: str
    prerequisites: list[str]
    recipe: list[RecipeLine] | None = None


@dataclass
class Makefile:
    loaded: bool = False
    variables: dict[str, Variable] = field(default_factory=dict)
    rules: dict[str, ExplicitRule] = field(default_factory=dict)
    pattern_rules: list[PatternRule] = field(default_factory=list)
    phony: set[str] = field(default_factory=set)
    default_goal: str | None = None


@dataclass
class RuleGroup:
    targets: list[str] = field(default_factory=list)
    patterns: list[PatternRule] = field(default_factory=list)
    recipe: list[RecipeLine] | None = None


@dataclass
class Condition:
    outer_active: bool
    value: bool
    line_number: int
    else_seen: bool = False


@dataclass
class ForeachScope:
    name: str
    word: str


@dataclass
class CallScope:
    values: list[str]


@dataclass
class ResolvedRule:
    prerequisites: list[str]
    recipe: list[RecipeLine] | None
    stem: str
    is_source: bool = False


def unique(items):
    return list(dict.fromkeys(items))


def find_closing(text, start):
    opening = text[start]
    closing = CLOSING[opening]
    depth = 0
    for index in range(start, len(text)):
        if text[index] == opening:
            depth += 1
        elif text[index] == closing:
            depth -= 1
            if depth == 0:
                return index
    return -1


def find_outside(text, char):
    found = -1
    index = 0
    while index < len(text):
        if text[index] != "$":
            if text[index] == char and found < 0:
                found = index
            index += 1
        elif index + 1 < len(text) and text[index + 1] in CLOSING:
            close = find_closing(text, index + 1)
            if close < 0:
                raise MakeError("unterminated variable reference")
            index = close + 1
        else:
            index += 2
    return found


def match_pattern(pattern, word):
    if "%" not in pattern:
        return "" if word == pattern else None
    prefix, _, suffix = pattern.partition("%")
    if (
        len(word) >= len(prefix) + len(suffix)
        and word.startswith(prefix)
        and word.endswith(suffix)
    ):
        return word[len(prefix) : len(word) - len(suffix)]
    return None


def substitute(text, stem):
    return text.replace("%", stem, 1)


def replace_word(word, pattern, replacement):
    stem = match_pattern(pattern, word)
    if stem is None:
        return word
    return substitute(replacement, stem) if "%" in pattern else replacement


def split_arguments(text, opening, limit):
    closing = CLOSING[opening]
    arguments = []
    depth = 0
    start = 0
    for index, char in enumerate(text):
        if char == opening:
            depth += 1
        elif char == closing:
            depth -= 1
        elif char == "," and depth == 0 and (limit is None or len(arguments) < limit - 1):
            arguments.append(text[start:index])
            start = index + 1
    arguments.append(text[start:])
    return arguments


def wildcard_regex(pattern):
    parts = []
    for char in pattern:
        if char == "*":
            parts.append("[^/]*")
        elif char == "?":
            parts.append("[^/]")
        else:
            parts.append(re.escape(char))
    return re.compile("".join(parts))


def has_extension(word):
    return word.rfind(".") > word.rfind("/")


def is_active(conditions):
    return not conditions or (conditions[-1].outer_active and conditions[-1].value)


def print_rule(target, prerequisites, recipe):
    print(" ".join([f"{target}:", *prerequisites]))
    for line in recipe or []:
        print(">" + line.command)


class Simulator:
    def __init__(self, files):
        self.files = files
        self.clock = max(files.values(), default=0)
        self.makefile = Makefile()
        self.scopes = []
        self.expanding = set()
        self.automatic = None
        self.location = "make"

    def give_new_time(self, name):
        self.clock += 1
        self.files[name] = self.clock

    def wildcard(self, pattern):
        if "*" in pattern or "?" in pattern:
            regex = wildcard_regex(pattern)
            return [name for name in sorted(self.files) if regex.fullmatch(name)]
        return [pattern] if pattern in self.files else []

    def expand(self, text):
        parts = []
        position = 0
        while (dollar := text.find("$", position)) >= 0:
            parts.append(text[position:dollar])
            if dollar + 1 == len(text):
                return "".join(parts)
            following = text[dollar + 1]
            if following == "$":
                parts.append("$")
                position = dollar + 2
            elif following in CLOSING:
                close = find_closing(text, dollar + 1)
                if close < 0:
                    raise MakeError("unterminated variable reference")
                parts.append(self.reference(text[dollar + 2 : close], following))
                position = close + 1
            else:
                parts.append(self.reference_value(following))
                position = dollar + 2
        parts.append(text[position:])
        return "".join(parts)

    def reference(self, content, opening):
        function, space, argument_part = content.partition(" ")
        if space and function in FUNCTIONS:
            return self.call_function(function, argument_part.lstrip(), opening)
        name = self.expand(content)
        variable, colon, substitution = name.partition(":")
        if colon and "=" in substitution:
            pattern, _, replacement = substitution.partition("=")
            if "%" not in pattern:
                pattern = "%" + pattern
                replacement = "%" + replacement
            words = self.reference_value(variable).split()
            return " ".join(replace_word(word, pattern, replacement) for word in words)
        return self.reference_value(name)

    def reference_value(self, name):
        for scope in reversed(self.scopes):
            if isinstance(scope, ForeachScope):
                if scope.name == name:
                    return scope.word
            elif name.isdigit():
                index = int(name)
                return scope.values[index] if index < len(scope.values) else ""
        if self.automatic is not None and name in self.automatic:
            return self.automatic[name]
        return self.variable_value(name)

    def variable_value(self, name):
        variable = self.makefile.variables.get(name)
        if variable is None:
            return ""
        if not variable.recursive:
            return variable.value
        if name in self.expanding:
            raise MakeError(f"Recursive variable '{name}' references itself (eventually)")
        self.expanding.add(name)
        try:
            return self.expand(variable.value)
        finally:
            self.expanding.discard(name)

    def call_function(self, name, argument_part, opening):
        minimum, maximum = FUNCTIONS[name]
        arguments = split_arguments(argument_part, opening, maximum)
        if len(arguments) < minimum:
            raise MakeError(
                f"insufficient number of arguments ({len(arguments)}) to function '{name}'"
            )
        if name == "foreach":
            return self.foreach(*arguments)
        if name == "if":
            if self.expand(arguments[0]).strip():
                return self.expand(arguments[1])
            return self.expand(arguments[2]) if len(arguments) == 3 else ""
        values = [self.expand(argument) for argument in arguments]
        if name not in ("subst", "call"):
            values = [value.strip() for value in values]
        return self.evaluate_function(name, values)

    def foreach(self, variable, items, text):
        name = self.expand(variable).strip()
        results = []
        for word in self.expand(items).split():
            self.scopes.append(ForeachScope(name, word))
            try:
                results.append(self.expand(text))
            finally:
                self.scopes.pop()
        return " ".join(results)

    def call_variable(self, values):
        name = values[0].strip()
        variable = self.makefile.variables.get(name)
        if variable is None:
            return ""
        if not variable.recursive:
            return variable.value
        self.scopes.append(CallScope([name] + values[1:]))
        try:
            return self.expand(variable.value)
        finally:
            self.scopes.pop()

    def evaluate_function(self, name, values):
        match name:
            case "subst":
                old, new, text = values
                return text.replace(old, new) if old else text
            case "patsubst":
                pattern, replacement, text = values
                return " ".join(
                    replace_word(word, pattern, replacement) for word in text.split()
                )
            case "strip":
                return " ".join(values[0].split())
            case "findstring":
                find, text = values
                return find if find in text else ""
            case "filter" | "filter-out":
                patterns = values[0].split()
                keep = name == "filter"
                return " ".join(
                    word
                    for word in values[1].split()
                    if any(match_pattern(pattern, word) is not None for pattern in patterns)
                    == keep
                )
            case "sort":
                return " ".join(sorted(set(values[0].split())))
            case "word":
                index, text = values
                if not index.isdigit():
                    raise MakeError(f"non-numeric first argument to 'word' function: '{index}'")
                if int(index) == 0:
                    raise MakeError("first argument to 'word' function must be greater than 0")
                words = text.split()
                return words[int(index) - 1] if int(index) <= len(words) else ""
            case "wordlist":
                start, end, text = values
                if not start.isdigit():
                    raise MakeError(
                        f"non-numeric first argument to 'wordlist' function: '{start}'"
                    )
                if not end.isdigit():
                    raise MakeError(
                        f"non-numeric second argument to 'wordlist' function: '{end}'"
                    )
                if int(start) == 0:
                    raise MakeError(f"invalid first argument to 'wordlist' function: '{start}'")
                return " ".join(text.split()[int(start) - 1 : int(end)])
            case "words":
                return str(len(values[0].split()))
            case "firstword":
                words = values[0].split()
                return words[0] if words else ""
            case "lastword":
                words = values[0].split()
                return words[-1] if words else ""
            case "dir":
                return " ".join(
                    word[: word.rfind("/") + 1] if "/" in word else "./"
                    for word in values[0].split()
                )
            case "notdir":
                return " ".join(word[word.rfind("/") + 1 :] for word in values[0].split())
            case "suffix":
                return " ".join(
                    word[word.rfind(".") :] for word in values[0].split() if has_extension(word)
                )
            case "basename":
                return " ".join(
                    word[: word.rfind(".")] if has_extension(word) else word
                    for word in values[0].split()
                )
            case "addsuffix":
                suffix, names = values
                return " ".join(word + suffix for word in names.split())
            case "addprefix":
                prefix, names = values
                return " ".join(prefix + word for word in names.split())
            case "wildcard":
                return " ".join(
                    found for pattern in values[0].split() for found in self.wildcard(pattern)
                )
            case "call":
                return self.call_variable(values)
            case "value":
                variable = self.makefile.variables.get(values[0])
                return variable.value if variable is not None else ""
            case "info":
                print(values[0])
            case "warning":
                print(f"{self.location}: {values[0]}")
            case "error":
                raise MakeError(values[0])
        return ""

    def load_makefile(self, lines):
        self.makefile = Makefile()
        conditions = []
        current_rule = None
        index = 0
        try:
            while index < len(lines):
                line_number = index + 1
                line = lines[index]
                index += 1
                self.location = f"Makefile:{line_number}"
                if line.startswith(">"):
                    if is_active(conditions):
                        if current_rule is None:
                            raise MakeError("recipe commences before first target")
                        recipe_line = RecipeLine(line_number, line[1:].lstrip())
                        self.add_recipe_line(current_rule, recipe_line)
                    continue
                while line.endswith("\\") and index < len(lines):
                    line = line[:-1].rstrip() + " " + lines[index].lstrip()
                    index += 1
                text = line.partition("#")[0].strip()
                keyword, _, rest = text.partition(" ")
                if keyword in CONDITIONALS:
                    self.process_conditional(keyword, rest.strip(), conditions, line_number)
                elif text and is_active(conditions):
                    current_rule = self.process_statement(text, line_number, current_rule)
            if conditions:
                self.location = f"Makefile:{conditions[-1].line_number}"
                raise MakeError("missing 'endif'")
        except MakeError as error:
            print(f"{self.location}: *** {error}.  Stop.")
            self.makefile = Makefile()
            return
        finally:
            self.location = "make"
        makefile = self.makefile
        makefile.pattern_rules = [
            rule for rule in makefile.pattern_rules if rule.recipe is not None
        ]
        makefile.loaded = True
        print(
            f"Makefile loaded: lines={len(lines)} variables={len(makefile.variables)} "
            f"targets={len(makefile.rules)} patterns={len(makefile.pattern_rules)} "
            f"goal={makefile.default_goal or '(none)'}"
        )

    def process_conditional(self, keyword, rest, conditions, line_number):
        match keyword:
            case "else":
                if not conditions:
                    raise MakeError("extraneous 'else'")
                top = conditions[-1]
                if top.else_seen:
                    raise MakeError("only one 'else' per conditional")
                top.value = not top.value
                top.else_seen = True
            case "endif":
                if not conditions:
                    raise MakeError("extraneous 'endif'")
                conditions.pop()
            case _:
                active = is_active(conditions)
                value = active and self.evaluate_condition(keyword, rest)
                conditions.append(Condition(active, value, line_number))

    def evaluate_condition(self, keyword, rest):
        if keyword in ("ifdef", "ifndef"):
            variable = self.makefile.variables.get(self.expand(rest).strip())
            defined = variable is not None and variable.value != ""
            return defined == (keyword == "ifdef")
        if len(rest) < 2 or not rest.startswith("(") or not rest.endswith(")"):
            raise MakeError("invalid syntax in conditional")
        inner = rest[1:-1]
        depth = 0
        for index, char in enumerate(inner):
            if char == "(":
                depth += 1
            elif char == ")":
                depth -= 1
            elif char == "," and depth == 0:
                left = self.expand(inner[:index]).strip()
                right = self.expand(inner[index + 1 :]).strip()
                return (left == right) == (keyword == "ifeq")
        raise MakeError("invalid syntax in conditional")

    def process_statement(self, text, line_number, current_rule):
        equals = find_outside(text, "=")
        colon = find_outside(text, ":")
        if equals >= 0 and (colon < 0 or colon >= equals - 1):
            self.assign(text, equals)
            return None
        if colon >= 0:
            return self.define_rule(text[:colon], text[colon + 1 :], line_number)
        if self.expand(text).strip():
            raise MakeError("missing separator")
        return current_rule

    def assign(self, text, equals):
        operator = text[equals - 1] if equals > 0 and text[equals - 1] in ":+?" else ""
        name = text[: equals - len(operator)].strip()
        value = text[equals + 1 :].strip()
        if not name:
            raise MakeError("empty variable name")
        variables = self.makefile.variables
        variable = variables.get(name)
        if operator == ":":
            variables[name] = Variable(False, self.expand(value))
        elif operator == "+" and variable is not None:
            addition = value if variable.recursive else self.expand(value)
            variable.value = f"{variable.value} {addition}" if variable.value else addition
        elif operator != "?" or variable is None:
            variables[name] = Variable(True, value)

    def define_rule(self, target_text, rest, line_number):
        targets = unique(self.expand(target_text).split())
        inline_recipe = None
        semicolon = find_outside(rest, ";")
        if semicolon >= 0:
            inline_recipe = rest[semicolon + 1 :].lstrip()
            rest = rest[:semicolon]
        target_pattern = None
        colon = find_outside(rest, ":")
        if colon >= 0:
            target_pattern = self.expand(rest[:colon]).strip()
            rest = rest[colon + 1 :]
        prerequisites = self.expand(rest).split()
        makefile = self.makefile
        group = RuleGroup()
        if targets == [".PHONY"]:
            makefile.phony.update(prerequisites)
        elif target_pattern is not None:
            if "%" not in target_pattern:
                raise MakeError("target pattern contains no '%'")
            for target in targets:
                stem = match_pattern(target_pattern, target)
                if stem:
                    self.register(target, [substitute(item, stem) for item in prerequisites])
                    makefile.rules[target].stem = stem
                    group.targets.append(target)
                else:
                    print(
                        f"Makefile:{line_number}: target '{target}' "
                        "doesn't match the target pattern"
                    )
        elif any("%" in target for target in targets):
            if not all("%" in target for target in targets):
                raise MakeError("mixed implicit and normal rules")
            for target in targets:
                pattern_rule = PatternRule(target, prerequisites)
                makefile.pattern_rules.append(pattern_rule)
                group.patterns.append(pattern_rule)
        else:
            for target in targets:
                self.register(target, prerequisites)
            group.targets = targets
        if inline_recipe is not None:
            self.add_recipe_line(group, RecipeLine(line_number, inline_recipe))
        return group

    def register(self, target, prerequisites):
        rule = self.makefile.rules.setdefault(target, ExplicitRule())
        for prerequisite in prerequisites:
            if prerequisite not in rule.prerequisites:
                rule.prerequisites.append(prerequisite)
        if self.makefile.default_goal is None and not target.startswith("."):
            self.makefile.default_goal = target

    def add_recipe_line(self, group, recipe_line):
        if group.recipe is None:
            group.recipe = []
            for target in group.targets:
                rule = self.makefile.rules[target]
                if rule.recipe is not None:
                    print(
                        f"Makefile:{recipe_line.line_number}: warning: "
                        f"overriding recipe for target '{target}'"
                    )
                    print(
                        f"Makefile:{rule.recipe[0].line_number}: warning: "
                        f"ignoring old recipe for target '{target}'"
                    )
                rule.recipe = group.recipe
            for pattern_rule in group.patterns:
                pattern_rule.recipe = group.recipe
        group.recipe.append(recipe_line)

    def make(self, arguments):
        options = set()
        goals = []
        for argument in arguments:
            if not argument.startswith("-"):
                goals.append(argument)
                continue
            for option in argument[1:]:
                if option not in OPTIONS:
                    print(f"make: invalid option -- '{option}'")
                    return
                options.add(option)
        if not goals:
            if not self.makefile.loaded:
                print("make: *** No targets specified and no makefile found.  Stop.")
                return
            if self.makefile.default_goal is None:
                print("make: *** No targets.  Stop.")
                return
            goals = [self.makefile.default_goal]
        dry_run = "n" in options
        if dry_run:
            saved_files, saved_clock = dict(self.files), self.clock
        Builder(self, options).run(goals)
        if dry_run:
            self.files, self.clock = saved_files, saved_clock

    def touch_files(self, names):
        for name in names:
            self.give_new_time(name)

    def remove_files(self, names):
        for name in names:
            if name in self.files:
                del self.files[name]
            else:
                print(f"rm: cannot remove '{name}': No such file or directory")

    def show_files(self):
        print(f"clock {self.clock}")
        for name in sorted(self.files):
            print(f"{name} {self.files[name]}")

    def show_variables(self):
        variables = self.makefile.variables
        try:
            for name in sorted(variables):
                symbol = "=" if variables[name].recursive else ":="
                value = self.variable_value(name).strip()
                print(f"{name} {symbol} {value}" if value else f"{name} {symbol}")
        except MakeError as error:
            print(f"make: *** {error}.  Stop.")

    def show_rules(self):
        makefile = self.makefile
        for target in sorted(makefile.rules):
            rule = makefile.rules[target]
            print_rule(target, rule.prerequisites, rule.recipe)
        for rule in makefile.pattern_rules:
            print_rule(rule.target, rule.prerequisites, rule.recipe)
        if makefile.phony:
            print(" ".join([".PHONY:", *sorted(makefile.phony)]))

    def show_expansion(self, text):
        try:
            print(f"[{self.expand(text)}]")
        except MakeError as error:
            print(f"make: *** {error}.  Stop.")


class Builder:
    def __init__(self, simulator, options):
        self.simulator = simulator
        self.makefile = simulator.makefile
        self.files = simulator.files
        self.dry_run = "n" in options
        self.always_make = "B" in options
        self.keep_going = "k" in options
        self.ignore_errors = "i" in options
        self.silent = "s" in options
        self.results = {}
        self.resolved = {}
        self.building = set()
        self.recipe_runs = 0

    def run(self, goals):
        try:
            for goal in goals:
                runs_before = self.recipe_runs
                result = self.build(goal, None)
                if result is Result.SUCCESS and self.recipe_runs == runs_before:
                    if goal in self.makefile.phony or self.resolved[goal].recipe is None:
                        print(f"make: Nothing to be done for '{goal}'.")
                    else:
                        print(f"make: '{goal}' is up to date.")
                elif result is Result.DEPENDENCY_FAILURE:
                    print(f"make: Target '{goal}' not remade because of errors.")
        except BuildAborted:
            pass

    def resolve_rule(self, target):
        explicit = self.makefile.rules.get(target)
        if explicit is not None and explicit.recipe is not None:
            return ResolvedRule(explicit.prerequisites, explicit.recipe, explicit.stem)
        if target not in self.makefile.phony:
            found = self.find_pattern_rule(target)
            if found is not None:
                stem, pattern_rule, prerequisites = found
                if explicit is not None:
                    prerequisites += explicit.prerequisites
                return ResolvedRule(unique(prerequisites), pattern_rule.recipe, stem)
        if explicit is not None:
            return ResolvedRule(explicit.prerequisites, None, explicit.stem)
        if target in self.makefile.phony:
            return ResolvedRule([], None, "")
        if target in self.files:
            return ResolvedRule([], None, "", is_source=True)
        return None

    def find_pattern_rule(self, target):
        candidates = []
        for pattern_rule in self.makefile.pattern_rules:
            stem = match_pattern(pattern_rule.target, target)
            if stem:
                candidates.append((stem, pattern_rule))
        candidates.sort(key=lambda candidate: len(candidate[0]))
        for stem, pattern_rule in candidates:
            prerequisites = [substitute(item, stem) for item in pattern_rule.prerequisites]
            if all(item in self.files or item in self.makefile.rules for item in prerequisites):
                return stem, pattern_rule, prerequisites
        return None

    def target_time(self, name):
        if name in self.makefile.phony:
            return None
        return self.files.get(name)

    def is_newer(self, name, reference_time):
        time = self.target_time(name)
        return time is None or time > reference_time

    def build(self, target, parent):
        if target in self.results:
            return self.results[target]
        rule = self.resolve_rule(target)
        if rule is None:
            self.results[target] = Result.FAILURE
            message = f"make: *** No rule to make target '{target}'"
            message += f", needed by '{parent}'." if parent is not None else "."
            if not self.keep_going:
                print(message + "  Stop.")
                raise BuildAborted
            print(message)
            return Result.FAILURE
        self.resolved[target] = rule
        if rule.is_source:
            self.results[target] = Result.SUCCESS
            return Result.SUCCESS
        self.building.add(target)
        prerequisites = []
        failed = False
        for prerequisite in rule.prerequisites:
            if prerequisite in self.building:
                print(f"make: Circular {target} <- {prerequisite} dependency dropped.")
                continue
            prerequisites.append(prerequisite)
            if self.build(prerequisite, target) is not Result.SUCCESS:
                failed = True
        self.building.remove(target)
        if failed:
            result = Result.DEPENDENCY_FAILURE
        else:
            result = self.update(target, rule, prerequisites)
        self.results[target] = result
        return result

    def update(self, target, rule, prerequisites):
        target_time = self.target_time(target)
        if self.always_make or target_time is None:
            changed = prerequisites
        else:
            changed = [item for item in prerequisites if self.is_newer(item, target_time)]
        if rule.recipe is None:
            return Result.SUCCESS
        if not self.always_make and target_time is not None and not changed:
            return Result.SUCCESS
        self.recipe_runs += 1
        if not self.run_recipe(target, rule, prerequisites, changed):
            return Result.FAILURE
        if target not in self.makefile.phony:
            self.simulator.give_new_time(target)
        return Result.SUCCESS

    def run_recipe(self, target, rule, prerequisites, changed):
        simulator = self.simulator
        simulator.automatic = {
            "@": target,
            "<": prerequisites[0] if prerequisites else "",
            "^": " ".join(prerequisites),
            "?": " ".join(changed),
            "*": rule.stem,
        }
        expanded_lines = []
        try:
            for line in rule.recipe:
                simulator.location = f"Makefile:{line.line_number}"
                expanded_lines.append(simulator.expand(line.command))
        except MakeError as error:
            print(f"{simulator.location}: *** {error}.  Stop.")
            raise BuildAborted
        finally:
            simulator.automatic = None
            simulator.location = "make"
        for line, expanded in zip(rule.recipe, expanded_lines):
            command = expanded.lstrip(" @-")
            prefix = expanded[: len(expanded) - len(command)]
            command = command.rstrip()
            if not command:
                continue
            if self.dry_run or ("@" not in prefix and not self.silent):
                print(command)
            if self.dry_run:
                continue
            exit_code = self.execute(command)
            if exit_code == 0:
                continue
            location = f"Makefile:{line.line_number}: {target}"
            if "-" in prefix or self.ignore_errors:
                print(f"make: [{location}] Error {exit_code} (ignored)")
                continue
            print(f"make: *** [{location}] Error {exit_code}")
            if not self.keep_going:
                raise BuildAborted
            return False
        return True

    def execute(self, command):
        name, *arguments = command.split()
        match name:
            case "echo":
                print(" ".join(arguments))
            case "touch":
                for argument in arguments:
                    self.simulator.give_new_time(argument)
            case "rm":
                return self.run_rm(arguments)
            case "false":
                return 1
            case "exit":
                return int(arguments[0]) if arguments else 0
        return 0

    def run_rm(self, arguments):
        forced = arguments[:1] == ["-f"]
        if forced:
            arguments = arguments[1:]
        exit_code = 0
        for argument in arguments:
            for name in self.simulator.wildcard(argument) or [argument]:
                if name in self.files:
                    del self.files[name]
                elif not forced:
                    print(f"rm: cannot remove '{name}': No such file or directory")
                    exit_code = 1
        return exit_code


def main():
    lines = sys.stdin.read().splitlines()
    files = {}
    index = 1
    while lines[index] != "END FILES":
        name, time = lines[index].split(" ")
        files[name] = int(time)
        index += 1
    index += 1
    simulator = Simulator(files)
    while lines[index] != "QUIT":
        line = lines[index]
        index += 1
        print(f"$ {line}")
        command, _, argument = line.partition(" ")
        match command:
            case "MAKEFILE":
                end = lines.index("END MAKEFILE", index)
                simulator.load_makefile(lines[index:end])
                index = end + 1
            case "MAKE":
                simulator.make(argument.split())
            case "TOUCH":
                simulator.touch_files(argument.split())
            case "RM":
                simulator.remove_files(argument.split())
            case "FILES":
                simulator.show_files()
            case "VARS":
                simulator.show_variables()
            case "RULES":
                simulator.show_rules()
            case "EXPAND":
                simulator.show_expansion(argument)


if __name__ == "__main__":
    main()
