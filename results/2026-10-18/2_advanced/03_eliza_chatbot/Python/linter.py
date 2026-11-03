from matcher import is_wildcard, pattern_covers
from script_loader import Diagnostic, is_reference


CODE_ORDER = (
    "SYNTAX", "ORPHAN", "DUPLICATE", "KEY_NO_DECOMP", "KEY_UNREACHABLE", "SYNON_UNUSED",
    "PRE_CHAIN", "SYNON_UNKNOWN", "RULE_NO_REASM", "RULE_SHADOWED", "REF_UNBOUND",
    "TARGET_UNDEFINED", "TARGET_CYCLE",
)
ERROR_CODES = (
    "SYNTAX", "ORPHAN", "DUPLICATE", "SYNON_UNKNOWN", "REF_UNBOUND",
    "TARGET_UNDEFINED", "TARGET_CYCLE",
)
MOVE_KINDS = ("GOTO", "RESTATE")


def unknown_groups(pattern, group_words):
    return [
        element[1:] for element in pattern
        if element.startswith("@") and element[1:] not in group_words
    ]


def references(item):
    if item.kind == "REASM":
        text = item.text
        return [
            int(text[index + 1]) for index in range(len(text))
            if is_reference(text[index:index + 3])
        ]
    if item.kind == "RESTATE":
        return [int(argument[1]) for argument in item.arguments[1:] if is_reference(argument)]
    return []


def move_graph(script):
    graph = {keyword.word: [] for keyword in script.keywords}
    for keyword in script.keywords:
        for rule in keyword.decomps:
            for item in rule.items:
                if item.kind in MOVE_KINDS and item.arguments[0] in script.keyword_map:
                    graph[keyword.word].append(item.arguments[0])
    return graph


def reaches(graph, start, goal):
    seen = {start}
    pending = [start]
    while pending:
        word = pending.pop()
        if word == goal:
            return True
        for target in graph[word]:
            if target not in seen:
                seen.add(target)
                pending.append(target)
    return False


def shadowing_rule(earlier_rules, rule, group_words):
    if unknown_groups(rule.pattern, group_words):
        return None
    for earlier in earlier_rules:
        if unknown_groups(earlier.pattern, group_words):
            continue
        if pattern_covers(earlier.pattern, rule.pattern, group_words):
            return earlier
    return None


class Linter:
    def __init__(self, script):
        self.script = script
        self.found = list(script.diagnostics)

    def add(self, line_number, code, message):
        self.found.append(Diagnostic(line_number, code, message))

    def check_keywords(self):
        script = self.script
        replacement_words = {word for pre in script.pres for word in pre.replacement}
        targets = {item.arguments[0] for item in script.items if item.kind in MOVE_KINDS}
        for keyword in script.keywords:
            word = keyword.word
            if not keyword.decomps:
                self.add(keyword.line_number, "KEY_NO_DECOMP", f"keyword {word} has no DECOMP")
            if (
                word in script.pre_table
                and word not in replacement_words
                and word not in targets
            ):
                self.add(
                    keyword.line_number, "KEY_UNREACHABLE", f"keyword {word} is replaced by PRE"
                )

    def check_groups(self):
        used = {
            element[1:] for rule in self.script.rules
            for element in rule.pattern if element.startswith("@")
        }
        for group in self.script.groups:
            if group.name not in used:
                self.add(group.line_number, "SYNON_UNUSED", f"group {group.name} is never used")

    def check_pres(self):
        for pre in self.script.pres:
            for word in pre.replacement:
                if word in self.script.pre_table:
                    self.add(
                        pre.line_number, "PRE_CHAIN",
                        f"replacement {word} is itself replaced by PRE",
                    )

    def check_rules(self):
        group_words = self.script.group_words
        for keyword in self.script.keywords:
            for rules in (keyword.memories, keyword.decomps):
                for position, rule in enumerate(rules):
                    for name in unknown_groups(rule.pattern, group_words):
                        self.add(rule.line_number, "SYNON_UNKNOWN", f"unknown group {name}")
                    if not rule.items:
                        self.add(rule.line_number, "RULE_NO_REASM", "rule has no reassembly")
                    shadow = shadowing_rule(rules[:position], rule, group_words)
                    if shadow is not None:
                        self.add(
                            rule.line_number, "RULE_SHADOWED",
                            f"pattern is shadowed by line {shadow.line_number}",
                        )

    def check_items(self):
        script = self.script
        graph = move_graph(script)
        for keyword in script.keywords:
            for rule in keyword.memories + keyword.decomps:
                wildcards = sum(1 for element in rule.pattern if is_wildcard(element))
                for item in rule.items:
                    for number in references(item):
                        if number == 0 or number > wildcards:
                            self.add(
                                item.line_number, "REF_UNBOUND",
                                f"reference ({number}) is not bound",
                            )
                    if item.kind not in MOVE_KINDS:
                        continue
                    target = item.arguments[0]
                    if target not in script.keyword_map:
                        self.add(
                            item.line_number, "TARGET_UNDEFINED",
                            f"target {target} is not a keyword",
                        )
                    elif reaches(graph, target, keyword.word):
                        self.add(
                            item.line_number, "TARGET_CYCLE",
                            f"edge {keyword.word} -> {target} is on a cycle",
                        )


def lint(script):
    linter = Linter(script)
    linter.check_keywords()
    linter.check_groups()
    linter.check_pres()
    linter.check_rules()
    linter.check_items()
    return sorted(
        linter.found,
        key=lambda diagnostic: (diagnostic.line_number, CODE_ORDER.index(diagnostic.code)),
    )
