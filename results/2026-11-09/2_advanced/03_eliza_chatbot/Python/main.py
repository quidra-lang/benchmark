import copy
import os
import re

from linter import ERROR_CODES, lint
from matcher import match_pattern
from memory import MemoryQueue
from responder import build_reply, eliza_lines, reflect, restated_words
from script_loader import load_script


SCRIPT_PATH = os.path.join("input", "script.txt")
DIALOGUE_PATH = os.path.join("input", "dialogue.txt")
OUTPUT_DIR = "output"
SESSION_PREFIX = "SESSION "
USER_PREFIX = "YOU: "
OUTPUT_INDENT = "  "
SOURCES = ("keyword", "memory", "question", "default", "repeat")
UNRECOGNIZED_SOURCES = ("question", "default")
CYCLED_LISTS = ("DEFAULT", "QUESTION", "REPEAT")
TOP_LIMIT = 5
HISTORY_LIMIT = 5
KEYS_PER_LINE = 8
UNUSED_PER_LINE = 12
NO_ARGUMENT_COMMANDS = (
    ":keys", ":why", ":history", ":memory", ":forget", ":reset", ":unused", ":stats", ":undo",
)
TEXT_COMMANDS = (":prepare", ":reflect", ":say", ":explain")
SINGLE_ARGUMENT_COMMANDS = (":groups", ":find", ":script", ":cycles", ":coverage")
KEYWORD_COMMANDS = (":script", ":cycles", ":coverage", ":test")
TRACE_SWITCHES = ("on", "off")


def normalize(text):
    clauses = []
    for part in re.split(r"[,.?!;]", text.lower()):
        pieces = re.sub(r"[^a-z0-9']", " ", part).split()
        words = [piece.strip("'") for piece in pieces]
        words = [word for word in words if word]
        if words:
            clauses.append(words)
    return clauses


def all_words(clauses):
    return [word for clause in clauses for word in clause]


def arguments_fit(name, text, arguments):
    if name in NO_ARGUMENT_COMMANDS:
        return not arguments
    if name in TEXT_COMMANDS:
        return text != ""
    if name in SINGLE_ARGUMENT_COMMANDS:
        return len(arguments) == 1
    if name == ":trace":
        return len(arguments) == 1 and arguments[0] in TRACE_SWITCHES
    if name == ":test":
        return len(arguments) >= 2
    return True


def rule_entries(keyword):
    entries = [("memory", number, rule) for number, rule in enumerate(keyword.memories, 1)]
    entries.extend(("decomp", number, rule) for number, rule in enumerate(keyword.decomps, 1))
    return entries


def ranked_counts(counts):
    ranked = sorted(counts.items(), key=lambda pair: (-pair[1], pair[0]))[:TOP_LIMIT]
    if not ranked:
        return "none"
    return ", ".join(f"{word} {count}" for word, count in ranked)


def source_line(turns, sources):
    counts = " ".join(f"{source}={sources[source]}" for source in SOURCES)
    return f"turns={turns} {counts}"


def grouped_lines(values, size):
    return [" ".join(values[start:start + size]) for start in range(0, len(values), size)]


def pick(texts, session_number):
    return texts[(session_number - 1) % len(texts)]


def split_sessions(lines):
    sessions = []
    for line in lines:
        if line.startswith(SESSION_PREFIX):
            sessions.append((line[len(SESSION_PREFIX):], []))
        else:
            sessions[-1][1].append(line)
    return sessions


def lint_lines(diagnostics):
    if not diagnostics:
        return ["OK"]
    lines = [
        f"{diagnostic.line_number} {diagnostic.code} {diagnostic.message}"
        for diagnostic in diagnostics
    ]
    errors = sum(1 for diagnostic in diagnostics if diagnostic.code in ERROR_CODES)
    warnings = len(diagnostics) - errors
    lines.append(f"TOTAL {len(diagnostics)} errors={errors} warnings={warnings}")
    return lines


def read_lines(path):
    with open(path) as file:
        return file.read().splitlines()


def write_lines(name, lines):
    with open(os.path.join(OUTPUT_DIR, name), "w") as file:
        file.write("".join(line + "\n" for line in lines))


class Session:
    def __init__(self, name):
        self.name = name
        self.turns = 0
        self.sources = dict.fromkeys(SOURCES, 0)
        self.previous = None
        self.history = []
        self.last_trace = None
        self.trace_on = False
        self.topics = {}
        self.words = {}
        self.stored = 0
        self.recalled = 0
        self.unrecognized = []
        self.undo = None

    def copy(self):
        other = copy.copy(self)
        other.sources = dict(self.sources)
        other.history = list(self.history)
        other.topics = dict(self.topics)
        other.words = dict(self.words)
        other.unrecognized = list(self.unrecognized)
        return other


class State:
    def __init__(self, script):
        self.positions = [0] * len(script.rules)
        self.hits = [0] * len(script.rules)
        self.item_uses = [0] * len(script.items)
        self.keyword_uses = [0] * len(script.keywords)
        self.keyword_replies = [0] * len(script.keywords)
        self.list_positions = dict.fromkeys(CYCLED_LISTS, 0)
        self.memory = MemoryQueue(script.memsize)
        self.session = None

    def copy(self):
        other = copy.copy(self)
        other.positions = list(self.positions)
        other.hits = list(self.hits)
        other.item_uses = list(self.item_uses)
        other.keyword_uses = list(self.keyword_uses)
        other.keyword_replies = list(self.keyword_replies)
        other.list_positions = dict(self.list_positions)
        other.memory = self.memory.copy()
        other.session = self.session.copy()
        return other

    def snapshot(self):
        other = self.copy()
        other.session.undo = None
        return other


class Chatbot:
    def __init__(self, script):
        self.script = script
        self.state = State(script)
        self.transcript = []
        self.total_turns = 0
        self.total_sources = dict.fromkeys(SOURCES, 0)

    def log_prefix(self):
        session = self.state.session
        return f"{session.name} {session.turns}"

    def cycle_reset(self):
        self.state.positions = [0] * len(self.script.rules)
        self.state.list_positions = dict.fromkeys(CYCLED_LISTS, 0)

    def take_text(self, name):
        texts = self.script.texts[name]
        position = self.state.list_positions[name]
        self.state.list_positions[name] = (position + 1) % len(texts)
        return texts[position]

    def take_item(self, rule):
        state = self.state
        position = state.positions[rule.index]
        item = rule.items[position]
        state.item_uses[item.index] += 1
        state.positions[rule.index] = (position + 1) % len(rule.items)
        return position + 1, item

    def pre_substitute(self, clauses):
        substituted = []
        for clause in clauses:
            words = []
            for word in clause:
                words.extend(self.script.pre_table.get(word, [word]))
            substituted.append(words)
        return substituted

    def prepared(self, text):
        return self.pre_substitute(normalize(text))

    def is_quit(self, text):
        words = all_words(normalize(text))
        return len(words) == 1 and words[0] in self.script.quit_words

    def select_clause(self, clauses):
        for number, clause in enumerate(clauses, 1):
            if any(word in self.script.keyword_map for word in clause):
                return number, clause
        return None

    def keyword_list(self, words):
        found = []
        for word in words:
            keyword = self.script.keyword_map.get(word)
            if keyword is not None and keyword not in found:
                found.append(keyword)
        return sorted(found, key=lambda keyword: -keyword.rank)

    def find_rule(self, rules, words):
        for number, rule in enumerate(rules, 1):
            bindings = match_pattern(rule.pattern, words, self.script.group_words)
            if bindings is not None:
                return number, rule, bindings
        return None

    def apply_memory(self, keyword, words, trace):
        found = self.find_rule(keyword.memories, words)
        if found is None:
            return
        number, rule, bindings = found
        trace.append(f"MEMORY {keyword.word} {number}")
        self.state.hits[rule.index] += 1
        if not rule.items:
            return
        _, item = self.take_item(rule)
        text = build_reply(item.text, bindings, self.script.post_table)
        if self.state.memory.store(self.log_prefix(), keyword.word, text):
            self.state.session.stored += 1

    def follow_keyword(self, keyword, words, entered, trace):
        state = self.state
        while True:
            entered.add(keyword.word)
            state.keyword_uses[keyword.index] += 1
            found = self.find_rule(keyword.decomps, words)
            if found is None:
                trace.append("NOMATCH " + keyword.word)
                return None
            number, rule, bindings = found
            state.hits[rule.index] += 1
            if not rule.items:
                trace.append(f"DECOMP {keyword.word} {number} 0")
                return None
            item_number, item = self.take_item(rule)
            trace.append(f"DECOMP {keyword.word} {number} {item_number}")
            if item.kind == "REASM":
                state.keyword_replies[keyword.index] += 1
                topics = state.session.topics
                topics[keyword.word] = topics.get(keyword.word, 0) + 1
                return build_reply(item.text, bindings, self.script.post_table)
            if item.kind == "NEWKEY":
                return None
            target = item.arguments[0]
            if target not in self.script.keyword_map or target in entered:
                trace.append("BLOCKED " + target)
                return None
            if item.kind == "RESTATE":
                words = restated_words(item.arguments[1:], bindings)
                trace.append(" ".join(["RESTATE", target] + words))
            else:
                trace.append("GOTO " + target)
            keyword = self.script.keyword_map[target]

    def keyword_reply(self, clauses, trace):
        selected = self.select_clause(clauses)
        if selected is None:
            trace.append("CLAUSE none")
            return None
        number, words = selected
        trace.append(f"CLAUSE {number} {' '.join(words)}")
        keywords = self.keyword_list(words)
        trace.append("KEYS " + " ".join(keyword.word for keyword in keywords))
        self.apply_memory(keywords[0], words, trace)
        entered = set()
        for keyword in keywords:
            if keyword.word in entered:
                continue
            trace.append("ENTER " + keyword.word)
            reply = self.follow_keyword(keyword, words, entered, trace)
            if reply is not None:
                return reply
        return None

    def fallback_reply(self, text):
        state = self.state
        if state.memory.texts:
            state.session.recalled += 1
            return state.memory.recall(self.log_prefix()), "memory"
        if text.endswith("?") and self.script.texts["QUESTION"]:
            return self.take_text("QUESTION"), "question"
        return self.take_text("DEFAULT"), "default"

    def decide(self, text):
        session = self.state.session
        clauses = normalize(text)
        trace = []
        if self.script.texts["REPEAT"] and clauses and clauses == session.previous:
            trace.append("REPEAT")
            reply = self.take_text("REPEAT")
            source = "repeat"
        else:
            reply = self.keyword_reply(self.pre_substitute(clauses), trace)
            source = "keyword"
            if reply is None:
                reply, source = self.fallback_reply(text)
        trace.append("REPLY " + source)
        session.previous = clauses
        session.sources[source] += 1
        if source in UNRECOGNIZED_SOURCES:
            session.unrecognized.append(session.turns)
        return reply, trace

    def speculate(self, text):
        saved = self.state.copy()
        reply, trace = self.decide(text)
        self.state = saved
        return reply, trace

    def write_eliza(self, text):
        self.transcript.extend(eliza_lines(text))

    def write_indented(self, lines):
        self.transcript.extend(OUTPUT_INDENT + line for line in lines)

    def respond(self, line):
        state = self.state
        session = state.session
        session.undo = state.snapshot()
        session.turns += 1
        for word in all_words(normalize(line)):
            if word not in self.script.stop_words:
                session.words[word] = session.words.get(word, 0) + 1
        session.history.append(f"{session.turns}: {line}")
        reply, trace = self.decide(line)
        self.write_eliza(reply)
        session.last_trace = trace
        if session.trace_on:
            self.write_indented(trace)

    def prepare(self, text, arguments):
        clauses = self.prepared(text)
        output = [
            f"clause {number}: {' '.join(clause)}" for number, clause in enumerate(clauses, 1)
        ]
        if not clauses:
            output.append("no words")
        selected = self.select_clause(clauses)
        if selected is None:
            output.append("selected none")
            return output
        number, words = selected
        labels = [f"{keyword.word}/{keyword.rank}" for keyword in self.keyword_list(words)]
        output.append(f"selected {number}")
        output.append("keys " + " ".join(labels))
        return output

    def test(self, text, arguments):
        keyword = self.script.keyword_map[arguments[0]]
        words = all_words(self.prepared(text.partition(" ")[2]))
        output = []
        for label, number, rule in rule_entries(keyword):
            bindings = match_pattern(rule.pattern, words, self.script.group_words)
            if bindings is None:
                result = "no match"
            elif not bindings:
                result = "match"
            else:
                result = " ".join("[" + " ".join(bound) + "]" for bound in bindings)
            output.append(f"{label} {number}: {result}")
        return output or ["no rules"]

    def reflect_text(self, text, arguments):
        clauses = self.prepared(text)
        if not clauses:
            return ["no words"]
        return [" ".join(reflect(clause, self.script.post_table)) for clause in clauses]

    def keys(self, text, arguments):
        ranked = sorted(self.script.keywords, key=lambda keyword: (-keyword.rank, keyword.word))
        labels = [f"{keyword.word}/{keyword.rank}" for keyword in ranked]
        return grouped_lines(labels, KEYS_PER_LINE)

    def groups(self, text, arguments):
        word = arguments[0]
        names = sorted(group.name for group in self.script.groups if word in group.members)
        return [" ".join(names) if names else "none"]

    def find(self, text, arguments):
        script = self.script
        word = arguments[0]
        output = []
        if word in script.keyword_map:
            output.append(f"keyword rank {script.keyword_map[word].rank}")
        for label, substitutions in (("pre", script.pres), ("post", script.posts)):
            for substitution in substitutions:
                if substitution.source == word or word in substitution.replacement:
                    replacement = " ".join(substitution.replacement)
                    output.append(
                        f"{label} {substitution.line_number}: "
                        f"{substitution.source} -> {replacement}"
                    )
        for group in script.groups:
            if word in group.members:
                output.append(f"group {group.name} line {group.line_number}")
        for keyword in script.keywords:
            for label, number, rule in rule_entries(keyword):
                if word in rule.pattern:
                    output.append(f"pattern {keyword.word} {label} {number}")
        if word in script.stop_words:
            output.append("stop word")
        if word in script.quit_words:
            output.append("quit word")
        return output or ["not found"]

    def show_script(self, text, arguments):
        keyword = self.script.keyword_map[arguments[0]]
        numbers = [keyword.line_number]
        for rule in keyword.memories + keyword.decomps:
            numbers.append(rule.line_number)
            numbers.extend(item.line_number for item in rule.items)
        return [f"{number} {self.script.lines[number - 1]}" for number in sorted(numbers)]

    def why(self, text, arguments):
        trace = self.state.session.last_trace
        if trace is None:
            return ["no reply yet"]
        return list(trace)

    def trace(self, text, arguments):
        self.state.session.trace_on = arguments[0] == "on"
        return ["trace " + arguments[0]]

    def history(self, text, arguments):
        history = self.state.session.history
        if not history:
            return ["no turns yet"]
        return history[-HISTORY_LIMIT:]

    def show_memory(self, text, arguments):
        memory = self.state.memory
        output = [f"memory {len(memory.texts)}/{memory.capacity}"]
        output.extend(f"{number}: {stored}" for number, stored in enumerate(memory.texts, 1))
        return output

    def forget(self, text, arguments):
        count = len(self.state.memory.texts)
        self.state.memory.clear(self.log_prefix())
        return [f"forgot {count}"]

    def cycles(self, text, arguments):
        keyword = self.script.keyword_map[arguments[0]]
        output = []
        for label, number, rule in rule_entries(keyword):
            if rule.items:
                position = self.state.positions[rule.index] + 1
                output.append(f"{label} {number}: next {position}/{len(rule.items)}")
            else:
                output.append(f"{label} {number}: empty")
        return output or ["no rules"]

    def coverage(self, text, arguments):
        keyword = self.script.keyword_map[arguments[0]]
        state = self.state
        output = []
        for label, number, rule in rule_entries(keyword):
            uses = " ".join(str(state.item_uses[item.index]) for item in rule.items) or "-"
            output.append(f"{label} {number}: hits {state.hits[rule.index]} entries {uses}")
        return output or ["no rules"]

    def reset(self, text, arguments):
        self.cycle_reset()
        return ["cycles reset"]

    def unused(self, text, arguments):
        numbers = sorted(
            item.line_number for item in self.script.items
            if self.state.item_uses[item.index] == 0
        )
        output = [f"unused {len(numbers)}"]
        output.extend(grouped_lines([str(number) for number in numbers], UNUSED_PER_LINE))
        return output

    def stats(self, text, arguments):
        session = self.state.session
        return [source_line(session.turns, session.sources)]

    def say(self, text, arguments):
        if self.is_quit(text):
            return ["would quit"]
        reply, _ = self.speculate(text)
        return [reply]

    def explain(self, text, arguments):
        if self.is_quit(text):
            return ["would quit"]
        _, trace = self.speculate(text)
        return trace

    def undo(self, text, arguments):
        snapshot = self.state.session.undo
        if snapshot is None:
            return ["nothing to undo"]
        self.state = snapshot
        return [f"undone turn {snapshot.session.turns + 1}"]

    def execute(self, line):
        name, _, text = line.partition(" ")
        arguments = text.split()
        handlers = {
            ":prepare": self.prepare,
            ":test": self.test,
            ":reflect": self.reflect_text,
            ":keys": self.keys,
            ":groups": self.groups,
            ":find": self.find,
            ":script": self.show_script,
            ":why": self.why,
            ":trace": self.trace,
            ":history": self.history,
            ":memory": self.show_memory,
            ":forget": self.forget,
            ":cycles": self.cycles,
            ":coverage": self.coverage,
            ":reset": self.reset,
            ":unused": self.unused,
            ":stats": self.stats,
            ":say": self.say,
            ":explain": self.explain,
            ":undo": self.undo,
        }
        if name not in handlers:
            return ["unknown command " + name]
        if not arguments_fit(name, text, arguments):
            return ["bad arguments"]
        if name in KEYWORD_COMMANDS and arguments[0] not in self.script.keyword_map:
            return ["unknown keyword " + arguments[0]]
        return handlers[name](text, arguments)

    def write_notes(self):
        session = self.state.session
        pending = len(self.state.memory.texts)
        unrecognized = " ".join(str(turn) for turn in session.unrecognized) or "none"
        self.transcript.append("NOTES " + session.name)
        self.write_indented([
            source_line(session.turns, session.sources),
            "topics: " + ranked_counts(session.topics),
            "words: " + ranked_counts(session.words),
            f"memory: stored={session.stored} recalled={session.recalled} pending={pending}",
            "unrecognized: " + unrecognized,
        ])
        self.total_turns += session.turns
        for source in SOURCES:
            self.total_sources[source] += session.sources[source]

    def run_session(self, number, name, lines):
        script = self.script
        if number >= 2:
            self.transcript.append("")
            if "cycles" not in script.persist:
                self.cycle_reset()
            if "memory" not in script.persist:
                self.state.memory.clear(f"{name} 0")
        self.state.session = Session(name)
        self.transcript.append(SESSION_PREFIX + name)
        self.write_eliza(pick(script.texts["INITIAL"], number))
        for line in lines:
            if line.startswith(":"):
                self.transcript.append(line)
                self.write_indented(self.execute(line))
                continue
            self.transcript.append(USER_PREFIX + line)
            if self.is_quit(line):
                self.write_eliza(pick(script.texts["FINAL"], number))
                break
            self.respond(line)
        self.write_notes()

    def run(self, lines):
        sessions = split_sessions(lines)
        for number, (name, session_lines) in enumerate(sessions, 1):
            self.run_session(number, name, session_lines)
        totals = source_line(self.total_turns, self.total_sources)
        self.transcript.append("")
        self.transcript.append(f"SUMMARY sessions={len(sessions)} {totals}")

    def keyword_stats(self):
        state = self.state
        ranked = sorted(
            self.script.keywords,
            key=lambda keyword: (-state.keyword_uses[keyword.index], keyword.word),
        )
        lines = ["keyword,rank,uses,replies,decomposition_hits"]
        for keyword in ranked:
            hits = "/".join(str(state.hits[rule.index]) for rule in keyword.decomps) or "-"
            uses = state.keyword_uses[keyword.index]
            replies = state.keyword_replies[keyword.index]
            lines.append(f"{keyword.word},{keyword.rank},{uses},{replies},{hits}")
        return lines


def main():
    script = load_script(SCRIPT_PATH)
    diagnostics = lint(script)
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    write_lines("lint.txt", lint_lines(diagnostics))
    chatbot = Chatbot(script)
    chatbot.run(read_lines(DIALOGUE_PATH))
    write_lines("transcript.txt", chatbot.transcript)
    write_lines("keyword_stats.csv", chatbot.keyword_stats())
    write_lines("memory_log.txt", chatbot.state.memory.log)


if __name__ == "__main__":
    main()
