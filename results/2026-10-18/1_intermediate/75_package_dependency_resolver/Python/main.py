import operator
import re
import sys
from collections import deque
from dataclasses import dataclass, field
from functools import total_ordering
from itertools import takewhile
from typing import NamedTuple


NUMBER = "0|[1-9][0-9]{0,3}"
NUMBER_PATTERN = re.compile(NUMBER)
VERSION_PATTERN = re.compile(
    rf"({NUMBER})\.({NUMBER})\.({NUMBER})(?:-([0-9a-z]+(?:\.[0-9a-z]+)*))?"
)
WILDCARDS = ("x", "*")
OPERATORS = (">=", "<=", ">", "<", "=", "^", "~")
COMPARISONS = {
    "=": operator.eq,
    ">": operator.gt,
    ">=": operator.ge,
    "<": operator.lt,
    "<=": operator.le,
}
PLAN_WORDS = ("install", "upgrade", "downgrade", "remove")


class CommandError(Exception):
    pass


@total_ordering
@dataclass(frozen=True)
class Version:
    core: tuple
    # Each identifier is (0, number) or (1, text), so numeric ones sort first.
    prerelease: tuple = ()

    @property
    def stable(self):
        return not self.prerelease

    def sort_key(self):
        return self.core, self.stable, self.prerelease

    def __lt__(self, other):
        return self.sort_key() < other.sort_key()

    def __str__(self):
        text = ".".join(map(str, self.core))
        if self.prerelease:
            text += "-" + ".".join(str(value) for _, value in self.prerelease)
        return text


MIN_VERSION = Version((0, 0, 0), ((0, 0),))


def parse_version(text):
    match = VERSION_PATTERN.fullmatch(text)
    if match is None:
        return None
    major, minor, patch, prerelease = match.groups()
    identifiers = []
    if prerelease is not None:
        for identifier in prerelease.split("."):
            if not identifier.isdigit():
                identifiers.append((1, identifier))
            elif NUMBER_PATTERN.fullmatch(identifier):
                identifiers.append((0, int(identifier)))
            else:
                return None
    return Version((int(major), int(minor), int(patch)), tuple(identifiers))


def upper_bound(core, position):
    index = position - 1
    return Version(core[:index] + (core[index] + 1,) + (0,) * (2 - index))


def parse_term(term):
    symbol = next((candidate for candidate in OPERATORS if term.startswith(candidate)), "")
    pattern = term[len(symbol):]
    version = parse_version(pattern)
    if version is not None and not version.stable:
        count = 3
        lower = version
        prerelease_core = version.core
    else:
        parts = pattern.split(".")
        count = len(list(takewhile(NUMBER_PATTERN.fullmatch, parts)))
        if len(parts) > 3 or not all(part in WILDCARDS for part in parts[count:]):
            return None
        numbers = [int(part) for part in parts[:count]] + [0] * (3 - count)
        lower = Version(tuple(numbers))
        prerelease_core = None
    core = lower.core
    if count == 0:
        comparators = [("<", MIN_VERSION)] if symbol in (">", "<") else []
        return comparators, prerelease_core
    match symbol:
        case "" | "=":
            if count == 3:
                comparators = [("=", lower)]
            else:
                comparators = [(">=", lower), ("<", upper_bound(core, count))]
        case ">":
            comparators = [(">", lower)] if count == 3 else [(">=", upper_bound(core, count))]
        case "<=":
            comparators = [("<=", lower)] if count == 3 else [("<", upper_bound(core, count))]
        case ">=":
            comparators = [(">=", lower)]
        case "<":
            comparators = [("<", lower)]
        case "~":
            comparators = [(">=", lower), ("<", upper_bound(core, 1 if count == 1 else 2))]
        case _:
            major, minor, _ = core
            if major != 0 or count == 1:
                position = 1
            elif minor != 0 or count == 2:
                position = 2
            else:
                position = 3
            comparators = [(">=", lower), ("<", upper_bound(core, position))]
    return comparators, prerelease_core


@dataclass
class Alternative:
    comparators: list
    prerelease_cores: set

    def allows(self, version):
        if not version.stable and version.core not in self.prerelease_cores:
            return False
        return all(COMPARISONS[symbol](version, bound) for symbol, bound in self.comparators)

    def __str__(self):
        return " ".join(f"{symbol}{bound}" for symbol, bound in self.comparators) or "*"


class Constraint:
    def __init__(self, text, alternatives):
        self.text = text
        self.alternatives = alternatives

    @classmethod
    def parse(cls, text):
        alternatives = []
        for alternative_text in text.split(" || "):
            alternative = Alternative([], set())
            for term in alternative_text.split(" "):
                parsed = parse_term(term)
                if parsed is None:
                    return None
                comparators, prerelease_core = parsed
                alternative.comparators.extend(comparators)
                if prerelease_core is not None:
                    alternative.prerelease_cores.add(prerelease_core)
            alternatives.append(alternative)
        return cls(text, alternatives)

    def allows(self, version):
        return any(alternative.allows(version) for alternative in self.alternatives)

    def normal_form(self):
        return " || ".join(str(alternative) for alternative in self.alternatives)


@dataclass
class Release:
    dependencies: list = field(default_factory=list)
    conflicts: list = field(default_factory=list)
    yanked: bool = False

    def dependency_names(self):
        return [name for name, _ in self.dependencies]

    def conflicts_with(self, name, version):
        return any(
            other == name and constraint.allows(version)
            for other, constraint in self.conflicts
        )


class Requirement(NamedTuple):
    name: str
    constraint: Constraint
    origin: tuple | None

    def describe(self):
        if self.origin is None:
            return f"requested {self.name} {self.constraint.text}"
        parent, version = self.origin
        return f"{parent}@{version} requires {self.name} {self.constraint.text}"


class Resolver:
    def __init__(self, manager, preferred, audit):
        self.manager = manager
        self.preferred = preferred
        self.audit = audit
        self.selection = {}
        self.reasons = {}
        self.failure_size = -1
        self.failure = None

    def usable(self, name, version):
        manager = self.manager
        if manager.release(name, version).yanked and manager.installed.get(name) != version:
            return False
        return not (self.audit and manager.advisories_for(name, version))

    def chain(self, requirement, indent):
        lines = []
        while requirement is not None:
            lines.append(indent + requirement.describe())
            origin = requirement.origin
            requirement = None if origin is None else self.reasons[origin[0]]
        return lines[::-1]

    def fail(self, requirement, reason, culprit=None):
        size = len(self.selection)
        if size > self.failure_size:
            self.failure_size = size
            lines = self.chain(requirement, "  ")
            lines.append("  " + reason)
            if culprit is not None:
                lines.extend(self.chain(self.reasons[culprit], "    "))
            self.failure = lines
        return False

    def find_conflict(self, name, version):
        release = self.manager.release(name, version)
        for other in sorted(self.selection):
            selected = self.selection[other]
            if release.conflicts_with(other, selected):
                return other
            if self.manager.release(other, selected).conflicts_with(name, version):
                return other
        return None

    def candidates(self, name, constraint):
        manager = self.manager
        versions = manager.packages.get(name, {})
        candidates = sorted(
            (
                version
                for version in versions
                if constraint.allows(version) and self.usable(name, version)
            ),
            reverse=True,
        )
        installed = manager.installed.get(name)
        if name in self.preferred and installed in candidates:
            candidates.remove(installed)
            candidates.insert(0, installed)
        return candidates

    def search(self, pending):
        if not pending:
            return True
        requirement, rest = pending[0], pending[1:]
        name, constraint = requirement.name, requirement.constraint
        if name in self.selection:
            selected = self.selection[name]
            if constraint.allows(selected):
                return self.search(rest)
            return self.fail(requirement, f"{name}@{selected} was selected by:", name)
        if name in self.manager.held:
            installed = self.manager.installed[name]
            if not (constraint.allows(installed) and self.usable(name, installed)):
                return self.fail(requirement, f"{name}@{installed} is held")
            candidates = [installed]
        else:
            candidates = self.candidates(name, constraint)
            if not candidates:
                return self.fail(requirement, f"no version of {name} matches {constraint.text}")
        for version in candidates:
            culprit = self.find_conflict(name, version)
            if culprit is not None:
                reason = (
                    f"{name}@{version} conflicts with {culprit}@{self.selection[culprit]}, "
                    "which was selected by:"
                )
                self.fail(requirement, reason, culprit)
                continue
            self.selection[name] = version
            self.reasons[name] = requirement
            release = self.manager.release(name, version)
            dependencies = [
                Requirement(dependency, dependency_constraint, (name, version))
                for dependency, dependency_constraint in release.dependencies
            ]
            if self.search(dependencies + rest):
                return True
            del self.selection[name]
            del self.reasons[name]
        return False


def arrange(names, blocked):
    pending = sorted(names)
    order = []
    while pending:
        name = next(name for name in pending if not blocked(name, pending))
        pending.remove(name)
        order.append(name)
    return order


def require_version(text):
    version = parse_version(text)
    if version is None:
        raise CommandError(f"invalid version '{text}'")
    return version


def require_constraint(text):
    constraint = Constraint.parse(text)
    if constraint is None:
        raise CommandError(f"invalid constraint '{text}'")
    return constraint


class PackageManager:
    def __init__(self):
        self.packages = {}
        self.requests = {}
        self.installed = {}
        self.held = set()
        self.advisories = {}
        self.history = []

    def execute(self, line):
        command, _, rest = line.partition(" ")
        arguments = rest.split(" ")
        try:
            match command:
                case "PKG":
                    return self.register(rest)
                case "YANK":
                    return self.yank(*arguments)
                case "INFO":
                    return self.info(*arguments)
                case "VERSIONS":
                    return self.versions(*rest.split(" ", 1))
                case "DEPENDENTS":
                    return self.dependents(*arguments)
                case "COMPARE":
                    return self.compare(*arguments)
                case "MATCH":
                    return self.match_version(*rest.split(" ", 1))
                case "RANGE":
                    return [require_constraint(rest).normal_form()]
                case "INSTALL":
                    return self.install(*rest.split(" ", 1))
                case "SIMULATE":
                    return self.install(*rest.split(" ", 1), simulate=True)
                case "REMOVE":
                    return self.remove(rest)
                case "UPGRADE":
                    return self.upgrade(rest or None)
                case "ROLLBACK":
                    return self.rollback()
                case "HOLD":
                    return self.hold(rest)
                case "UNHOLD":
                    return self.unhold(rest)
                case "WHY":
                    return self.why(rest)
                case "TREE":
                    return self.tree(rest or None)
                case "OUTDATED":
                    return self.outdated()
                case "LOCK":
                    return self.lock()
                case "STATUS":
                    return self.status()
                case "ADVISORY":
                    return self.add_advisory(*rest.split(" ", 2))
                case "AUDIT":
                    return self.audit_fix() if rest == "FIX" else self.audit()
        except CommandError as error:
            return [f"error: {error}"]

    def release(self, name, version):
        return self.packages[name][version]

    def dependency_names(self, name, version):
        return self.release(name, version).dependency_names()

    def newest_first(self, name):
        return sorted(self.packages.get(name, {}), reverse=True)

    def find_release(self, name, text):
        version = parse_version(text)
        release = self.packages.get(name, {}).get(version)
        if release is None:
            raise CommandError(f"{name}@{text} is not registered")
        return version, release

    def installed_version(self, name):
        if name not in self.installed:
            raise CommandError(f"{name} is not installed")
        return self.installed[name]

    def advisories_for(self, name, version):
        return sorted(
            identifier
            for identifier, (package, constraint) in self.advisories.items()
            if package == name and constraint.allows(version)
        )

    def display(self, name, version):
        notes = []
        if self.release(name, version).yanked:
            notes.append("yanked")
        if self.installed.get(name) == version:
            notes.append("installed")
        text = f"{name}@{version}"
        return f"{text} ({', '.join(notes)})" if notes else text

    def first_dependent(self, name):
        return min(
            package
            for package, version in self.installed.items()
            if name in self.dependency_names(package, version)
        )

    def reachable(self, roots):
        found = set()
        stack = list(roots)
        while stack:
            name = stack.pop()
            if name not in found:
                found.add(name)
                stack.extend(self.dependency_names(name, self.installed[name]))
        return found

    def plan(self, new):
        old = self.installed

        def waits_for_dependency(name, pending):
            return any(
                dependency in pending for dependency in self.dependency_names(name, new[name])
            )

        def needed_by_other(name, pending):
            return any(
                name in self.dependency_names(other, old[other])
                for other in pending
                if other != name
            )

        lines = []
        for name in arrange(new, waits_for_dependency):
            version = new[name]
            previous = old.get(name)
            if previous is None:
                lines.append(f"install {name}@{version}")
            elif version > previous:
                lines.append(f"upgrade {name} {previous} -> {version}")
            elif version < previous:
                lines.append(f"downgrade {name} {previous} -> {version}")
        removed = [name for name in old if name not in new]
        for name in arrange(removed, needed_by_other):
            lines.append(f"remove {name}@{old[name]}")
        if not lines:
            return ["no changes"]
        tallies = [sum(line.startswith(word) for line in lines) for word in PLAN_WORDS]
        lines.append("{} installed, {} upgraded, {} downgraded, {} removed".format(*tallies))
        return lines

    def update_state(self, requests, installed):
        self.history.append((self.requests, self.installed))
        self.requests = requests
        self.installed = installed
        self.held.intersection_update(installed)

    def resolve(self, requests, preferred, audit=False, apply=True):
        resolver = Resolver(self, preferred, audit)
        pending = [Requirement(name, constraint, None) for name, constraint in requests.items()]
        if not resolver.search(pending):
            return ["UNSATISFIABLE", *resolver.failure]
        lines = self.plan(resolver.selection)
        if apply:
            self.update_state(requests, resolver.selection)
        return lines

    def register(self, arguments):
        head, *clauses = arguments.split("; ")
        name, text = head.split(" ")
        version = require_version(text)
        if version in self.packages.get(name, {}):
            raise CommandError(f"{name}@{text} is already registered")
        release = Release()
        for clause in clauses:
            kind, other, constraint_text = clause.split(" ", 2)
            entry = (other, require_constraint(constraint_text))
            if kind == "DEP":
                release.dependencies.append(entry)
            else:
                release.conflicts.append(entry)
        self.packages.setdefault(name, {})[version] = release
        return [f"registered {name}@{text}"]

    def yank(self, name, text):
        _, release = self.find_release(name, text)
        if release.yanked:
            raise CommandError(f"{name}@{text} is already yanked")
        release.yanked = True
        return [f"yanked {name}@{text}"]

    def info(self, name, text):
        version, release = self.find_release(name, text)
        lines = [self.display(name, version)]
        lines.extend(
            f"  requires {other} {constraint.text}" for other, constraint in release.dependencies
        )
        lines.extend(
            f"  conflicts with {other} {constraint.text}"
            for other, constraint in release.conflicts
        )
        lines.extend(f"  advisory {identifier}" for identifier in self.advisories_for(name, version))
        return lines

    def versions(self, name, text=None):
        constraint = None if text is None else require_constraint(text)
        if name not in self.packages:
            raise CommandError(f"unknown package {name}")
        lines = [
            self.display(name, version)
            for version in self.newest_first(name)
            if constraint is None or constraint.allows(version)
        ]
        return lines or ["no matching versions"]

    def dependents(self, name, text=None):
        version = None if text is None else require_version(text)
        lines = []
        for package in sorted(self.packages):
            for candidate in self.newest_first(package):
                for other, constraint in self.release(package, candidate).dependencies:
                    if other == name and (version is None or constraint.allows(version)):
                        lines.append(f"{package}@{candidate} requires {name} {constraint.text}")
        return lines or ["no dependents"]

    def compare(self, first_text, second_text):
        first = require_version(first_text)
        second = require_version(second_text)
        if first < second:
            symbol = "<"
        elif first == second:
            symbol = "="
        else:
            symbol = ">"
        return [f"{first_text} {symbol} {second_text}"]

    def match_version(self, version_text, constraint_text):
        version = require_version(version_text)
        constraint = require_constraint(constraint_text)
        return ["yes" if constraint.allows(version) else "no"]

    def install(self, name, text="*", simulate=False):
        constraint = require_constraint(text)
        if name not in self.packages:
            raise CommandError(f"unknown package {name}")
        requests = dict(self.requests)
        requests[name] = constraint
        return self.resolve(requests, set(self.installed), apply=not simulate)

    def remove(self, name):
        if name not in self.requests:
            if name in self.installed:
                raise CommandError(f"{name} is required by {self.first_dependent(name)}")
            raise CommandError(f"{name} is not installed")
        requests = {package: c for package, c in self.requests.items() if package != name}
        kept = self.reachable(requests)
        if name in kept:
            version = self.installed[name]
            lines = [f"{name}@{version} is still required by {self.first_dependent(name)}"]
            self.update_state(requests, self.installed)
            return lines
        installed = {package: v for package, v in self.installed.items() if package in kept}
        lines = self.plan(installed)
        self.update_state(requests, installed)
        return lines

    def upgrade(self, name=None):
        if name is None:
            preferred = set()
        else:
            self.installed_version(name)
            preferred = set(self.installed) - {name}
        return self.resolve(self.requests, preferred)

    def rollback(self):
        if not self.history:
            raise CommandError("nothing to roll back")
        requests, installed = self.history.pop()
        lines = self.plan(installed)
        self.requests = requests
        self.installed = installed
        self.held.intersection_update(installed)
        return lines

    def hold(self, name):
        version = self.installed_version(name)
        if name in self.held:
            raise CommandError(f"{name} is already held")
        self.held.add(name)
        return [f"held {name}@{version}"]

    def unhold(self, name):
        if name not in self.held:
            raise CommandError(f"{name} is not held")
        self.held.remove(name)
        return [f"released {name}"]

    def why(self, name):
        version = self.installed_version(name)
        if name in self.requests:
            return [f"{name}@{version} is explicitly installed"]
        parents = dict.fromkeys(self.requests)
        queue = deque(sorted(self.requests))
        while queue:
            current = queue.popleft()
            for dependency in sorted(self.dependency_names(current, self.installed[current])):
                if dependency not in parents:
                    parents[dependency] = current
                    queue.append(dependency)
        path = [name]
        while parents[path[-1]] is not None:
            path.append(parents[path[-1]])
        return [" -> ".join(f"{package}@{self.installed[package]}" for package in reversed(path))]

    def tree(self, name=None):
        if name is not None:
            self.installed_version(name)
            roots = [name]
        elif self.requests:
            roots = sorted(self.requests)
        else:
            return ["(empty)"]
        lines = []
        shown = set()
        for root in roots:
            self.show_tree(root, self.requests.get(root), "", "", shown, lines)
        return lines

    def show_tree(self, name, constraint, prefix, indent, shown, lines):
        version = self.installed[name]
        body = f"{prefix}{name}@{version}"
        if constraint is not None:
            body += f" [{constraint.text}]"
        if name in shown:
            lines.append(body + " (*)")
            return
        shown.add(name)
        lines.append(body)
        dependencies = self.release(name, version).dependencies
        for index, (dependency, dependency_constraint) in enumerate(dependencies):
            if index < len(dependencies) - 1:
                branch, extension = "|-- ", "|   "
            else:
                branch, extension = "`-- ", "    "
            self.show_tree(
                dependency, dependency_constraint, indent + branch, indent + extension, shown, lines
            )

    def outdated(self):
        lines = []
        for name in sorted(self.installed):
            current = self.installed[name]
            constraints = [
                constraint
                for package, version in self.installed.items()
                for other, constraint in self.release(package, version).dependencies
                if other == name
            ]
            if name in self.requests:
                constraints.append(self.requests[name])
            versions = self.packages[name]
            wanted = max(
                version
                for version, release in versions.items()
                if (not release.yanked or version == current)
                and all(constraint.allows(version) for constraint in constraints)
            )
            latest = max(
                (
                    version
                    for version, release in versions.items()
                    if version.stable and not release.yanked
                ),
                default=None,
            )
            if wanted != current or (latest is not None and latest > current):
                latest_text = "-" if latest is None else latest
                lines.append(f"{name} {current} {wanted} {latest_text}")
        return lines or ["all packages are up to date"]

    def lock(self):
        lines = [f"{name}@{self.installed[name]}" for name in sorted(self.installed)]
        return lines or ["(empty)"]

    def status(self):
        lines = [
            f"{name} {constraint.text} -> {self.installed[name]}"
            for name, constraint in self.requests.items()
        ]
        if not lines:
            lines.append("no requests")
        lines.append(
            f"{len(self.installed)} installed, {len(self.held)} held, "
            f"{len(self.history)} snapshots"
        )
        return lines

    def add_advisory(self, identifier, name, text):
        if identifier in self.advisories:
            raise CommandError(f"advisory {identifier} already exists")
        self.advisories[identifier] = (name, require_constraint(text))
        return [f"advisory {identifier} recorded"]

    def audit(self):
        lines = []
        for name in sorted(self.installed):
            version = self.installed[name]
            identifiers = self.advisories_for(name, version)
            if not identifiers:
                continue
            fixes = [
                candidate
                for candidate, release in self.packages[name].items()
                if candidate > version
                and candidate.stable
                and not release.yanked
                and not self.advisories_for(name, candidate)
            ]
            fix = f"fix: {min(fixes)}" if fixes else "no fix"
            lines.append(f"{name}@{version}: {', '.join(identifiers)} ({fix})")
        return lines or ["no known vulnerabilities"]

    def audit_fix(self):
        return self.resolve(self.requests, set(self.installed), audit=True)


def main():
    manager = PackageManager()
    count = int(sys.stdin.readline())
    for _ in range(count):
        for line in manager.execute(sys.stdin.readline().rstrip("\n")):
            print(line)


if __name__ == "__main__":
    main()
