import sys
from collections import defaultdict

EPSILON = "e"
ENUM_LIMIT = 50
POSTFIX_OPERATORS = ("*", "+", "?")

REFERENCE = "reference"
DFA_REFERENCE = "DFA reference"
NEW_NAME = "new name"
OTHER = "other"

COMMAND_ROLES = {
    "ACCEPT": (REFERENCE, OTHER),
    "CLOSURE": (REFERENCE, OTHER),
    "ENUM": (REFERENCE, OTHER),
    "COUNT": (REFERENCE, OTHER),
    "TODFA": (REFERENCE, NEW_NAME),
    "EPSFREE": (REFERENCE, NEW_NAME),
    "REVERSE": (REFERENCE, NEW_NAME),
    "STAR": (REFERENCE, NEW_NAME),
    "MINIMIZE": (DFA_REFERENCE, NEW_NAME),
    "COMPLEMENT": (DFA_REFERENCE, NEW_NAME),
    "EQUIV": (REFERENCE, REFERENCE),
    "UNION": (DFA_REFERENCE, DFA_REFERENCE, NEW_NAME),
    "INTERSECT": (DFA_REFERENCE, DFA_REFERENCE, NEW_NAME),
    "DIFF": (DFA_REFERENCE, DFA_REFERENCE, NEW_NAME),
    "CONCAT": (REFERENCE, REFERENCE, NEW_NAME),
    "EMPTY": (REFERENCE,),
    "FINITE": (REFERENCE,),
    "INFO": (REFERENCE,),
    "TABLE": (REFERENCE,),
    "SHOW": (REFERENCE,),
    "DELETE": (REFERENCE,),
    "SYNC": (DFA_REFERENCE,),
    "LIST": (),
}


class CommandError(Exception):
    pass


def series(prefix, count):
    return [f"{prefix}{index}" for index in range(count)]


def show_word(word):
    return word or EPSILON


def yes_no(flag):
    return "yes" if flag else "no"


def is_symbol_char(char):
    return char.isdigit() or char.islower()


def reachable_from(sources, successors):
    seen = set(sources)
    pending = list(seen)
    while pending:
        for target in successors(pending.pop()):
            if target not in seen:
                seen.add(target)
                pending.append(target)
    return seen


def explore(origin, alphabet, step):
    nodes = [origin]
    words = [""]
    index_of = {origin: 0}
    edges = []
    current = 0
    while current < len(nodes):
        for symbol in alphabet:
            target = step(nodes[current], symbol)
            if target not in index_of:
                index_of[target] = len(nodes)
                nodes.append(target)
                words.append(words[current] + symbol)
            edges.append((current, symbol, index_of[target]))
        current += 1
    return nodes, words, edges


class Automaton:
    def __init__(self, kind, states, alphabet, start, accepting, transitions):
        self.kind = kind
        self.states = states
        self.index_of = {state: index for index, state in enumerate(states)}
        self.alphabet = "".join(sorted(alphabet))
        self.start = start
        self.accepting = frozenset(accepting)
        self.transitions = frozenset(transitions)
        self.targets = {}
        for source, symbol, target in self.transitions:
            self.targets.setdefault((source, symbol), set()).add(target)

    def summary(self, name):
        return (
            f"{self.kind} {name}: alphabet={self.alphabet} states={len(self.states)} "
            f"accepting={len(self.accepting)} transitions={len(self.transitions)}"
        )

    def join_names(self, states):
        return ",".join(self.states[state] for state in sorted(states))

    def format_set(self, states):
        return "{" + self.join_names(states) + "}"

    def format_list(self, states):
        return self.join_names(states) or "none"

    def successors(self, state, symbol):
        return self.targets.get((state, symbol), set())

    def delta(self, state, symbol):
        (target,) = self.targets[state, symbol]
        return target

    def closure(self, states):
        return frozenset(reachable_from(states, lambda state: self.successors(state, EPSILON)))

    def initial_set(self):
        return self.closure([self.start])

    def destination(self, states, symbol):
        return self.closure(
            {target for state in states for target in self.successors(state, symbol)}
        )

    def contains_accepting(self, states):
        return not self.accepting.isdisjoint(states)

    def epsilon_count(self):
        return sum(1 for _, symbol, _ in self.transitions if symbol == EPSILON)

    def neighbors(self, state):
        return [
            target
            for symbol in self.alphabet + EPSILON
            for target in self.successors(state, symbol)
        ]

    def reachable_states(self):
        return reachable_from([self.start], self.neighbors)

    def live_states(self):
        predecessors = defaultdict(set)
        for source, _, target in self.transitions:
            predecessors[target].add(source)
        return reachable_from(self.accepting, lambda state: predecessors[state])


class RegexParser:
    def __init__(self, expression):
        self.expression = expression
        self.position = 0

    def peek(self):
        if self.position < len(self.expression):
            return self.expression[self.position]
        return ""

    def error(self):
        return CommandError(f"syntax error at {self.position + 1}")

    def parse(self):
        node = self.alternation()
        if self.peek():
            raise self.error()
        return node

    def alternation(self):
        terms = [self.concatenation()]
        while self.peek() == "|":
            self.position += 1
            terms.append(self.concatenation())
        return terms[0] if len(terms) == 1 else ("alternation", terms)

    def concatenation(self):
        factors = [self.factor()]
        while is_symbol_char(self.peek()) or self.peek() == "(":
            factors.append(self.factor())
        return factors[0] if len(factors) == 1 else ("concatenation", factors)

    def factor(self):
        node = self.atom()
        while self.peek() in POSTFIX_OPERATORS:
            node = (self.peek(), node)
            self.position += 1
        return node

    def atom(self):
        char = self.peek()
        if is_symbol_char(char):
            self.position += 1
            return ("symbol", char)
        if char != "(":
            raise self.error()
        self.position += 1
        node = self.alternation()
        if self.peek() != ")":
            raise self.error()
        self.position += 1
        return node


class ThompsonBuilder:
    def __init__(self):
        self.state_count = 0
        self.transitions = set()

    def new_state(self):
        self.state_count += 1
        return self.state_count - 1

    def link(self, source, target):
        self.transitions.add((source, EPSILON, target))

    def build(self, node):
        kind, content = node
        if kind == "concatenation":
            parts = [self.build(factor) for factor in content]
            for (_, previous_exit), (next_entry, _) in zip(parts, parts[1:]):
                self.link(previous_exit, next_entry)
            return parts[0][0], parts[-1][1]
        entry = self.new_state()
        if kind == "symbol":
            exit_state = self.new_state()
            self.transitions.add((entry, content, exit_state))
            return entry, exit_state
        if kind == "alternation":
            parts = [self.build(term) for term in content]
            exit_state = self.new_state()
            for part_entry, part_exit in parts:
                self.link(entry, part_entry)
                self.link(part_exit, exit_state)
            return entry, exit_state
        inner_entry, inner_exit = self.build(content)
        exit_state = self.new_state()
        self.link(entry, inner_entry)
        self.link(inner_exit, exit_state)
        if kind != "?":
            self.link(inner_exit, inner_entry)
        if kind != "+":
            self.link(entry, exit_state)
        return entry, exit_state


def determinize(automaton):
    subsets, _, edges = explore(automaton.initial_set(), automaton.alphabet, automaton.destination)
    accepting = {
        index for index, subset in enumerate(subsets) if automaton.contains_accepting(subset)
    }
    dfa = Automaton("DFA", series("D", len(subsets)), automaton.alphabet, 0, accepting, edges)
    return dfa, subsets


def remove_epsilon(automaton):
    accepting = set()
    transitions = set()
    for state in range(len(automaton.states)):
        reach = automaton.closure([state])
        if automaton.contains_accepting(reach):
            accepting.add(state)
        for symbol in automaton.alphabet:
            transitions.update(
                (state, symbol, target) for target in automaton.destination(reach, symbol)
            )
    return Automaton(
        "NFA", automaton.states, automaton.alphabet, automaton.start, accepting, transitions
    )


def number_blocks(keys):
    numbers = {}
    return {state: numbers.setdefault(key, len(numbers)) for state, key in keys.items()}


def group_blocks(blocks):
    groups = [[] for _ in set(blocks.values())]
    for state, block in blocks.items():
        groups[block].append(state)
    return groups


def minimize(dfa):
    reachable = sorted(dfa.reachable_states())
    unreachable = set(range(len(dfa.states))) - set(reachable)
    details = [f"  unreachable: {dfa.format_list(unreachable)}"]
    blocks = number_blocks({state: state in dfa.accepting for state in reachable})
    groups = group_blocks(blocks)
    round_number = 0
    while True:
        partition = " ".join(dfa.format_set(group) for group in groups)
        details.append(f"  round {round_number}: {partition}")
        refined = number_blocks(
            {
                state: (
                    blocks[state],
                    tuple(blocks[dfa.delta(state, symbol)] for symbol in dfa.alphabet),
                )
                for state in reachable
            }
        )
        refined_groups = group_blocks(refined)
        if len(refined_groups) == len(groups):
            break
        blocks, groups = refined, refined_groups
        round_number += 1
    named, _, edges = explore(
        blocks[dfa.start],
        dfa.alphabet,
        lambda block, symbol: blocks[dfa.delta(groups[block][0], symbol)],
    )
    accepting = {index for index, block in enumerate(named) if groups[block][0] in dfa.accepting}
    details += [
        f"  M{index} = {dfa.format_set(groups[block])}" for index, block in enumerate(named)
    ]
    minimal = Automaton("DFA", series("M", len(named)), dfa.alphabet, 0, accepting, edges)
    return minimal, details


def product_pairs(left, right):
    return explore(
        (left.start, right.start),
        left.alphabet,
        lambda pair, symbol: (left.delta(pair[0], symbol), right.delta(pair[1], symbol)),
    )


def product_dfa(left, right, accepts):
    pairs, _, edges = product_pairs(left, right)
    accepting = {
        index
        for index, (first, second) in enumerate(pairs)
        if accepts(first in left.accepting, second in right.accepting)
    }
    dfa = Automaton("DFA", series("P", len(pairs)), left.alphabet, 0, accepting, edges)
    return dfa, pairs


def find_difference(first, second):
    left, _ = determinize(first)
    right, _ = determinize(second)
    pairs, words, _ = product_pairs(left, right)
    for (p, q), word in zip(pairs, words):
        if (p in left.accepting) != (q in right.accepting):
            return word, p in left.accepting
    return None


def complement(dfa):
    rejecting = set(range(len(dfa.states))) - dfa.accepting
    return Automaton("DFA", dfa.states, dfa.alphabet, dfa.start, rejecting, dfa.transitions)


def reverse(automaton):
    transitions = {
        (target + 1, symbol, source + 1) for source, symbol, target in automaton.transitions
    }
    transitions |= {(0, EPSILON, state + 1) for state in automaton.accepting}
    states = series("N", len(automaton.states) + 1)
    return Automaton("NFA", states, automaton.alphabet, 0, {automaton.start + 1}, transitions)


def concatenate(first, second):
    offset = len(first.states)
    second_start = second.start + offset
    transitions = set(first.transitions)
    transitions |= {
        (source + offset, symbol, target + offset) for source, symbol, target in second.transitions
    }
    transitions |= {(state, EPSILON, second_start) for state in first.accepting}
    accepting = {state + offset for state in second.accepting}
    states = series("N", offset + len(second.states))
    return Automaton("NFA", states, first.alphabet, first.start, accepting, transitions)


def star(automaton):
    start = automaton.start + 1
    transitions = {
        (source + 1, symbol, target + 1) for source, symbol, target in automaton.transitions
    }
    transitions.add((0, EPSILON, start))
    transitions |= {(state + 1, EPSILON, start) for state in automaton.accepting}
    accepting = {0} | {state + 1 for state in automaton.accepting}
    states = series("N", len(automaton.states) + 1)
    return Automaton("NFA", states, automaton.alphabet, 0, accepting, transitions)


def accepted_strings(dfa, max_length):
    accepted = []
    level = [("", dfa.start)]
    for length in range(max_length + 1):
        accepted += [word for word, state in level if state in dfa.accepting]
        if length < max_length:
            level = [
                (word + symbol, dfa.delta(state, symbol))
                for word, state in level
                for symbol in dfa.alphabet
            ]
    return accepted


def count_by_length(dfa, max_length):
    counts = []
    weights = {dfa.start: 1}
    for length in range(max_length + 1):
        counts.append(sum(weight for state, weight in weights.items() if state in dfa.accepting))
        if length < max_length:
            following = defaultdict(int)
            for state, weight in weights.items():
                for symbol in dfa.alphabet:
                    following[dfa.delta(state, symbol)] += weight
            weights = following
    return counts


def is_infinite(dfa):
    live = dfa.live_states()

    def live_successors(state):
        return [target for target in dfa.neighbors(state) if target in live]

    return any(state in reachable_from(live_successors(state), live_successors) for state in live)


def smallest_accepted(automaton):
    subsets, words, _ = explore(automaton.initial_set(), automaton.alphabet, automaton.destination)
    for subset, word in zip(subsets, words):
        if automaton.contains_accepting(subset):
            return word
    return None


def synchronizing_word(dfa):
    images, words, _ = explore(
        frozenset(range(len(dfa.states))),
        dfa.alphabet,
        lambda image, symbol: frozenset(dfa.delta(state, symbol) for state in image),
    )
    for image, word in zip(images, words):
        if len(image) == 1:
            (state,) = image
            return word, state
    return None


def transition_table(automaton):
    columns = list(automaton.alphabet)
    if automaton.kind == "NFA" and automaton.epsilon_count() > 0:
        columns.append(EPSILON)
    rows = [[""] + columns]
    for state, name in enumerate(automaton.states):
        start_mark = "->" if state == automaton.start else "  "
        accepting_mark = "*" if state in automaton.accepting else " "
        row = [start_mark + accepting_mark + name]
        for symbol in columns:
            if automaton.kind == "DFA":
                row.append(automaton.states[automaton.delta(state, symbol)])
            else:
                targets = automaton.successors(state, symbol)
                row.append(automaton.format_set(targets) if targets else "-")
        rows.append(row)
    widths = [max(len(cell) for cell in column) for column in zip(*rows)]
    return [
        "  ".join(cell.ljust(width) for cell, width in zip(row, widths)).rstrip() for row in rows
    ]


def definition_line(name, automaton):
    symbol_order = automaton.alphabet + EPSILON
    transitions = sorted(
        automaton.transitions,
        key=lambda transition: (transition[0], symbol_order.index(transition[1]), transition[2]),
    )
    words = [
        automaton.kind,
        name,
        ",".join(automaton.states),
        automaton.alphabet,
        automaton.states[automaton.start],
        automaton.join_names(automaton.accepting) or "-",
    ]
    words += [
        f"{automaton.states[source]}:{symbol}:{automaton.states[target]}"
        for source, symbol, target in transitions
    ]
    return " ".join(words)


class Toolkit:
    def __init__(self):
        self.table = {}

    def execute(self, words):
        command, args = words[0], words[1:]
        try:
            if command in ("DFA", "NFA"):
                return [self.define(command, args)]
            if command == "REGEX":
                return [self.define_regex(args)]
            if command not in COMMAND_ROLES:
                raise CommandError(f"unknown command {command}")
            self.check_arguments(COMMAND_ROLES[command], args)
            return getattr(self, "do_" + command.lower())(*args)
        except CommandError as error:
            return [f"error: {error}"]

    def check_arguments(self, roles, args):
        if len(args) != len(roles):
            raise CommandError("wrong number of arguments")
        arguments = list(zip(roles, args))
        references = [name for role, name in arguments if role in (REFERENCE, DFA_REFERENCE)]
        for name in references:
            if name not in self.table:
                raise CommandError(f"unknown automaton {name}")
        for role, name in arguments:
            if role == NEW_NAME and name in self.table:
                raise CommandError(f"{name} already exists")
        for role, name in arguments:
            if role == DFA_REFERENCE and self.table[name].kind != "DFA":
                raise CommandError(f"{name} is not a DFA")
        if len(references) == 2:
            first, second = (self.table[name] for name in references)
            if first.alphabet != second.alphabet:
                raise CommandError("alphabets differ")

    def register(self, name, automaton):
        self.table[name] = automaton
        return automaton.summary(name)

    def define(self, kind, args):
        if len(args) < 5:
            raise CommandError("wrong number of arguments")
        name, state_list, alphabet, start, accepting_list, *transition_words = args
        if name in self.table:
            raise CommandError(f"{name} already exists")
        states = state_list.split(",")
        index_of = {}
        for state in states:
            if state in index_of:
                raise CommandError(f"duplicate state {state}")
            index_of[state] = len(index_of)
        if start not in index_of:
            raise CommandError(f"unknown state {start}")
        accepting = set()
        if accepting_list != "-":
            for state in accepting_list.split(","):
                if state not in index_of:
                    raise CommandError(f"unknown state {state}")
                if index_of[state] in accepting:
                    raise CommandError(f"duplicate state {state}")
                accepting.add(index_of[state])
        transitions = set()
        defined = set()
        for word in transition_words:
            source, symbol, target = word.split(":")
            if source not in index_of:
                raise CommandError(f"unknown state {source}")
            if symbol == EPSILON and kind == "DFA":
                raise CommandError("epsilon transition in DFA")
            if symbol != EPSILON and symbol not in alphabet:
                raise CommandError(f"unknown symbol {symbol}")
            if target not in index_of:
                raise CommandError(f"unknown state {target}")
            transition = (index_of[source], symbol, index_of[target])
            if transition in transitions:
                raise CommandError(f"duplicate transition {word}")
            if kind == "DFA" and transition[:2] in defined:
                raise CommandError(f"conflicting transition {word}")
            transitions.add(transition)
            defined.add(transition[:2])
        if kind == "DFA":
            for state in states:
                for symbol in sorted(alphabet):
                    if (index_of[state], symbol) not in defined:
                        raise CommandError(f"missing transition {state}:{symbol}")
        automaton = Automaton(kind, states, alphabet, index_of[start], accepting, transitions)
        return self.register(name, automaton)

    def define_regex(self, args):
        if len(args) != 3:
            raise CommandError("wrong number of arguments")
        name, alphabet, expression = args
        if name in self.table:
            raise CommandError(f"{name} already exists")
        for char in expression:
            if is_symbol_char(char) and char != EPSILON and char not in alphabet:
                raise CommandError(f"unknown symbol {char}")
        tree = RegexParser(expression).parse()
        builder = ThompsonBuilder()
        entry, exit_state = builder.build(tree)
        states = series("N", builder.state_count)
        automaton = Automaton("NFA", states, alphabet, entry, {exit_state}, builder.transitions)
        return self.register(name, automaton)

    def do_accept(self, name, text):
        automaton = self.table[name]
        word = "" if text == EPSILON else text
        for symbol in word:
            if symbol not in automaton.alphabet:
                raise CommandError(f"unknown symbol {symbol}")

        def describe(subset):
            if automaton.kind == "NFA":
                return automaton.format_set(subset)
            (state,) = subset
            return automaton.states[state]

        current = automaton.initial_set()
        parts = [describe(current)]
        for symbol in word:
            current = automaton.destination(current, symbol)
            parts.append(f"-{symbol}-> {describe(current)}")
        verdict = "ACCEPT" if automaton.contains_accepting(current) else "REJECT"
        return [f"{verdict} {' '.join(parts)}"]

    def do_closure(self, name, state_list):
        automaton = self.table[name]
        members = []
        for state in state_list.split(","):
            if state not in automaton.index_of:
                raise CommandError(f"unknown state {state}")
            members.append(automaton.index_of[state])
        return [automaton.format_set(automaton.closure(members))]

    def do_todfa(self, name, new_name):
        source = self.table[name]
        dfa, subsets = determinize(source)
        lines = [self.register(new_name, dfa)]
        lines += [
            f"  D{index} = {source.format_set(subset)}" for index, subset in enumerate(subsets)
        ]
        return lines

    def do_epsfree(self, name, new_name):
        return [self.register(new_name, remove_epsilon(self.table[name]))]

    def do_minimize(self, name, new_name):
        minimal, details = minimize(self.table[name])
        return [self.register(new_name, minimal)] + details

    def do_equiv(self, first, second):
        difference = find_difference(self.table[first], self.table[second])
        if difference is None:
            return ["EQUIVALENT"]
        word, first_accepts = difference
        owner = first if first_accepts else second
        return [f"NOT EQUIVALENT: {show_word(word)} is accepted only by {owner}"]

    def combine(self, first, second, new_name, accepts):
        left, right = self.table[first], self.table[second]
        dfa, pairs = product_dfa(left, right, accepts)
        lines = [self.register(new_name, dfa)]
        lines += [
            f"  P{index} = ({left.states[p]},{right.states[q]})"
            for index, (p, q) in enumerate(pairs)
        ]
        return lines

    def do_union(self, first, second, new_name):
        return self.combine(first, second, new_name, lambda p, q: p or q)

    def do_intersect(self, first, second, new_name):
        return self.combine(first, second, new_name, lambda p, q: p and q)

    def do_diff(self, first, second, new_name):
        return self.combine(first, second, new_name, lambda p, q: p and not q)

    def do_complement(self, name, new_name):
        return [self.register(new_name, complement(self.table[name]))]

    def do_reverse(self, name, new_name):
        return [self.register(new_name, reverse(self.table[name]))]

    def do_concat(self, first, second, new_name):
        return [self.register(new_name, concatenate(self.table[first], self.table[second]))]

    def do_star(self, name, new_name):
        return [self.register(new_name, star(self.table[name]))]

    def do_enum(self, name, limit):
        dfa, _ = determinize(self.table[name])
        accepted = accepted_strings(dfa, int(limit))
        parts = [str(len(accepted))] + [show_word(word) for word in accepted[:ENUM_LIMIT]]
        if len(accepted) > ENUM_LIMIT:
            parts.append("...")
        return [" ".join(parts)]

    def do_count(self, name, length):
        dfa, _ = determinize(self.table[name])
        return [str(count_by_length(dfa, int(length))[-1])]

    def do_empty(self, name):
        word = smallest_accepted(self.table[name])
        if word is None:
            return ["EMPTY"]
        return [f"NOT EMPTY {show_word(word)}"]

    def do_finite(self, name):
        automaton = self.table[name]
        dfa, _ = determinize(automaton)
        if is_infinite(dfa):
            return ["INFINITE"]
        total = sum(count_by_length(dfa, len(automaton.states) - 1))
        return [f"FINITE {total}"]

    def do_sync(self, name):
        dfa = self.table[name]
        result = synchronizing_word(dfa)
        if result is None:
            return ["NOT SYNCHRONIZING"]
        word, state = result
        return [f"SYNCHRONIZING {show_word(word)} -> {dfa.states[state]}"]

    def do_info(self, name):
        automaton = self.table[name]
        epsilon_count = automaton.epsilon_count()
        deterministic = epsilon_count == 0 and all(
            len(targets) == 1 for targets in automaton.targets.values()
        )
        complete = all(
            (state, symbol) in automaton.targets
            for state in range(len(automaton.states))
            for symbol in automaton.alphabet
        )
        dfa, _ = determinize(automaton)
        if not dfa.accepting:
            language = "empty"
        elif is_infinite(dfa):
            language = "infinite"
        else:
            language = "finite"
        minimal, _ = minimize(dfa)
        return [
            automaton.summary(name),
            f"  epsilon transitions: {epsilon_count}",
            f"  reachable: {automaton.format_list(automaton.reachable_states())}",
            f"  live: {automaton.format_list(automaton.live_states())}",
            f"  deterministic: {yes_no(deterministic)}",
            f"  complete: {yes_no(complete)}",
            f"  language: {language}",
            f"  minimal DFA states: {len(minimal.states)}",
        ]

    def do_table(self, name):
        return transition_table(self.table[name])

    def do_show(self, name):
        return [definition_line(name, self.table[name])]

    def do_list(self):
        return [automaton.summary(name) for name, automaton in self.table.items()] or ["(none)"]

    def do_delete(self, name):
        del self.table[name]
        return [f"deleted {name}"]


def main():
    lines = sys.stdin.read().splitlines()
    toolkit = Toolkit()
    output = []
    for line in lines[1 : int(lines[0]) + 1]:
        if not line.startswith("#"):
            output.extend(toolkit.execute(line.split(" ")))
    sys.stdout.write("".join(line + "\n" for line in output))


if __name__ == "__main__":
    main()
