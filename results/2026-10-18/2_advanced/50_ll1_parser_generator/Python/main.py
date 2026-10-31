"""LL(1) grammar generator, conflict explanation and parsing reports."""

from collections import deque
from pathlib import Path

from driver import parse_tokens, tree_label
from first_follow import analyze_sets, terminal_order, terminals_of, first_sequence
from grammar_parser import (
    format_alternative, format_production, is_nonterminal, parse_grammar,
)
from table import build_table, number_productions
from transform import clone_grammar, eliminate_left_recursion, left_factor


def check_declarations(source):
    if not source["has_declaration"]:
        return []
    return [
        f"undeclared terminal {name} at line {source['words'][name]}"
        for name in sorted(source["words"])
        if name not in source["declared"]
    ]


def reachable(grammar):
    visited = {grammar["start"]}
    queue = deque([grammar["start"]])
    while queue:
        for rhs in grammar["rules"].get(queue.popleft(), []):
            for symbol in rhs:
                if is_nonterminal(symbol) and symbol not in visited:
                    visited.add(symbol)
                    queue.append(symbol)
    return visited


def clean_grammar(source):
    grammar = clone_grammar(source)
    diagnostics = []
    defined = set(grammar["order"])
    undefined = {
        symbol for lhs in grammar["order"] for rhs in grammar["rules"][lhs]
        for symbol in rhs
        if is_nonterminal(symbol) and symbol not in defined
    }
    for name in sorted(undefined, key=lambda word: word[1:-1]):
        diagnostics.append(f"undefined nonterminal {name}")
    for lhs in grammar["order"]:
        kept = []
        for rhs in grammar["rules"][lhs]:
            bad = next((symbol for symbol in rhs if symbol in undefined), None)
            if bad is not None:
                diagnostics.append(
                    f"removed {format_production(lhs, rhs)} (undefined {bad})"
                )
            else:
                kept.append(rhs)
        grammar["rules"][lhs] = kept
    productive = set()
    while True:
        changed = False
        for lhs in grammar["order"]:
            if lhs not in productive and any(
                all(not is_nonterminal(s) or s in productive for s in rhs)
                for rhs in grammar["rules"][lhs]
            ):
                productive.add(lhs)
                changed = True
        if not changed:
            break
    discarded = set(grammar["order"]) - productive
    for lhs in grammar["order"]:
        if lhs in discarded:
            diagnostics.append(f"unproductive nonterminal {lhs}")
    grammar["order"] = [s for s in grammar["order"] if s not in discarded]
    for lhs in grammar["order"]:
        kept = []
        for rhs in grammar["rules"][lhs]:
            bad = next((s for s in rhs if s in discarded), None)
            if bad is not None:
                diagnostics.append(
                    f"removed {format_production(lhs, rhs)} (unproductive {bad})"
                )
            else:
                kept.append(rhs)
        grammar["rules"][lhs] = kept
    for lhs in discarded:
        del grammar["rules"][lhs]
    reached = reachable(grammar)
    for lhs in grammar["order"]:
        if lhs not in reached:
            diagnostics.append(f"unreachable nonterminal {lhs}")
    grammar["order"] = [s for s in grammar["order"] if s in reached]
    grammar["rules"] = {s: grammar["rules"][s] for s in grammar["order"]}
    return grammar, diagnostics


def left_recursion_diagnostics(grammar):
    log = []
    for start in grammar["order"]:
        queue = deque([start])
        parent = {start: None}
        path = None
        while queue and path is None:
            lhs = queue.popleft()
            for rhs in grammar["rules"][lhs]:
                if not rhs or not is_nonterminal(rhs[0]):
                    continue
                successor = rhs[0]
                if successor == start:
                    backwards = [lhs]
                    while parent[backwards[-1]] is not None:
                        backwards.append(parent[backwards[-1]])
                    path = list(reversed(backwards)) + [start]
                    break
                if successor not in parent:
                    parent[successor] = lhs
                    queue.append(successor)
        if path is not None:
            log.append("left recursion: " + " -> ".join(path))
    return log


def final_pruning(grammar):
    g = clone_grammar(grammar)
    reached = reachable(g)
    removed = [s for s in g["order"] if s not in reached]
    g["order"] = [s for s in g["order"] if s in reached]
    g["rules"] = {s: g["rules"][s] for s in g["order"]}
    return (g, [f"remove unreachable {s}" for s in removed],
            [f"unreachable after transformation {s}" for s in removed])


def unused_declarations(source, final):
    if not source["has_declaration"]:
        return []
    return [
        f"unused token {name}"
        for name in sorted(source["declared"] - terminals_of(final))
    ]


def grammar_summary(g):
    alternatives = [rhs for lhs in g["order"] for rhs in g["rules"][lhs]]
    return (
        f"start={g['start']} nonterminals={len(g['order'])} "
        f"terminals={len(terminals_of(g))} "
        f"productions={len(alternatives)} "
        f"empty={sum(len(rhs) == 0 for rhs in alternatives)} "
        f"unit={sum(len(rhs) == 1 and is_nonterminal(rhs[0])
                    for rhs in alternatives)}"
    )


def grammar_listing(g, numbered=False):
    lines = []
    total = sum(len(g["rules"][s]) for s in g["order"])
    width = len(str(total))
    number = 0
    for lhs in g["order"]:
        for i, rhs in enumerate(g["rules"][lhs]):
            number += 1
            line = (
                format_production(lhs, rhs) if i == 0
                else " " * len(lhs) + " | " + format_alternative(rhs)
            )
            lines.append(f"{number:>{width}}  {line}" if numbered else line)
    return lines


def cross_reference(g):
    items = number_productions(g)
    result = []
    for symbol in g["order"] + sorted(terminals_of(g)):
        numbers = [p["number"] for p in items if symbol in p["rhs"]]
        name = symbol if is_nonterminal(symbol) else f'"{symbol}"'
        result.append(
            name + (" used in " + " ".join(map(str, numbers))
                    if numbers else " not used")
        )
    return result


def grammar_file(cleaned, recursion, factors, final, first_log,
                 second_log, last_log):
    lines = ["== cleaned grammar ==", grammar_summary(cleaned)]
    lines += grammar_listing(cleaned)
    for title, g, log, numbered in (
        ("left recursion elimination", recursion, first_log, False),
        ("left factoring", factors, second_log, False),
        ("final grammar", final, last_log, True),
    ):
        lines += ["", f"== {title} =="]
        lines += log or ["none"]
        lines += [grammar_summary(g)]
        lines += grammar_listing(g, numbered)
    lines += ["", "== cross reference =="]
    lines += cross_reference(final)
    return lines


def shortest_sentences(g):
    scores = {}
    while True:
        changed = False
        for lhs in g["order"]:
            for rhs in g["rules"][lhs]:
                if any(is_nonterminal(s) and s not in scores for s in rhs):
                    continue
                length = sum(scores[s][0] if is_nonterminal(s) else 1
                             for s in rhs)
                height = max((scores[s][1] for s in rhs
                              if is_nonterminal(s)), default=0) + 1
                candidate = length, height
                if lhs not in scores or candidate < scores[lhs]:
                    scores[lhs] = candidate
                    changed = True
        if not changed:
            break
    selected = {}
    for lhs in g["order"]:
        for rhs in g["rules"][lhs]:
            if any(is_nonterminal(s) and s not in scores for s in rhs):
                continue
            measure = (
                sum(scores[s][0] if is_nonterminal(s) else 1 for s in rhs),
                max((scores[s][1] for s in rhs if is_nonterminal(s)),
                    default=0) + 1,
            )
            if measure == scores[lhs]:
                selected[lhs] = rhs
                break
    memo = {}
    def expand(symbol):
        if not is_nonterminal(symbol):
            return (symbol,)
        if symbol not in memo:
            result = []
            for child in selected[symbol]:
                result.extend(expand(child))
            memo[symbol] = tuple(result)
        return memo[symbol]
    for symbol in g["order"]:
        expand(symbol)
    return scores, memo


def shortest_contexts(g, scores, sentences):
    positions = number_productions(g)
    costs = {g["start"]: (0, 0)}
    parent = {}
    while True:
        changed = False
        for production in positions:
            lhs = production["lhs"]
            if lhs not in costs:
                continue
            rhs = production["rhs"]
            for index, symbol in enumerate(rhs):
                if not is_nonterminal(symbol) or symbol == g["start"]:
                    continue
                before, after = rhs[:index], rhs[index + 1:]
                cost = (
                    costs[lhs][0] + sum(
                        scores[s][0] if is_nonterminal(s) else 1
                        for s in before + after
                    ),
                    costs[lhs][1] + 1,
                )
                key = (production["number"], index)
                if (symbol not in costs or cost < costs[symbol]
                        or (cost == costs[symbol] and key < parent[symbol][0])):
                    costs[symbol] = cost
                    parent[symbol] = (key, lhs, before, after)
                    changed = True
        if not changed:
            break
    memo = {g["start"]: ((), ())}
    def context(symbol):
        if symbol not in memo:
            _, lhs, before, after = parent[symbol]
            pre, post = context(lhs)
            own_pre, own_post = list(pre), []
            for s in before:
                own_pre.extend(sentences[s] if is_nonterminal(s) else (s,))
            for s in after:
                own_post.extend(sentences[s] if is_nonterminal(s) else (s,))
            own_post.extend(post)
            memo[symbol] = tuple(own_pre), tuple(own_post)
        return memo[symbol]
    for symbol in g["order"]:
        context(symbol)
    return memo


def example_sentence(production, sentences, contexts):
    prefix, suffix = contexts[production["lhs"]]
    body = []
    for symbol in production["rhs"]:
        body.extend(sentences[symbol] if is_nonterminal(symbol) else (symbol,))
    return tuple(prefix) + tuple(body) + tuple(suffix)


def sets_file(g, sets, shortest):
    passes = sets["passes"]
    lines = [
        "passes: " + " ".join(f"{key}={passes[key]}"
                             for key in ("nullable", "first", "follow")),
        "",
    ]
    for lhs in g["order"]:
        lines += [
            lhs,
            "  nullable: " + ("yes" if sets["nullable"][lhs] else "no"),
            "  first:" + "".join(" " + t for t in terminal_order(sets["first"][lhs])),
            "  follow:" + "".join(" " + t for t in terminal_order(sets["follow"][lhs])),
            "  shortest:" + "".join(" " + t for t in shortest[lhs]),
        ]
    return lines


def first_path(item, token, table, sets):
    by_lhs = {}
    for p in table["productions"]:
        by_lhs.setdefault(p["lhs"], []).append(p)
    start = item["number"]
    queue = deque([start])
    parent = {start: None}
    while queue:
        current = queue.popleft()
        for symbol in table["productions"][current - 1]["rhs"]:
            if symbol == token:
                path = []
                while current != start:
                    path.append(current)
                    current = parent[current]
                return list(reversed(path))
            if is_nonterminal(symbol):
                for child in by_lhs[symbol]:
                    number = child["number"]
                    if number not in parent:
                        parent[number] = current
                        queue.append(number)
                if not sets["nullable"][symbol]:
                    break
            else:
                break
    return []


def follow_path(lhs, token, g, table, sets):
    queue = deque([(lhs, ())])
    visited = {lhs}
    while queue:
        symbol, path = queue.popleft()
        if symbol == g["start"] and token == "$":
            return list(path)
        for production in table["productions"]:
            for index, rhs_symbol in enumerate(production["rhs"]):
                if rhs_symbol != symbol:
                    continue
                more, empty = first_sequence(
                    production["rhs"][index + 1:],
                    sets["nullable"], sets["first"],
                )
                if token in more:
                    return list(path) + [production["number"]]
                outer = production["lhs"]
                if empty and outer not in visited:
                    visited.add(outer)
                    queue.append((outer, path + (production["number"],)))
    return []


def table_file(g, sets, table, conflicts_before):
    lines = ["== predict sets =="]
    for production in table["productions"]:
        lines += [
            f"{production['number']}: {production['notation']}",
            "  predict:" + "".join(
                " " + s for s in terminal_order(production["predict"])
            ),
        ]
    lines += ["", "== parse table =="]
    tokens = sets["terminals"] + ["$"]
    matrix = [[""] + tokens]
    for lhs in g["order"]:
        matrix.append([lhs] + [
            "/".join(str(item["number"]) for item in table["cells"][(lhs, t)])
            if table["cells"][(lhs, t)] else "." for t in tokens
        ])
    widths = [max(len(row[i]) for row in matrix)
              for i in range(len(matrix[0]))]
    for row in matrix:
        lines.append(row[0].ljust(widths[0]) + "".join(
            "  " + value.rjust(widths[index])
            for index, value in enumerate(row[1:], 1)
        ))
    lines += ["", "== conflicts =="]
    if not table["conflicts"]:
        lines.append("none")
    for conflict in table["conflicts"]:
        lhs, token = conflict["lhs"], conflict["token"]
        lines.append(
            f"conflict {lhs} on {token}: {conflict['kind']}, "
            f"chosen {conflict['chosen']}"
        )
        for entry in conflict["entries"]:
            production = table["productions"][entry["number"] - 1]
            path = (
                first_path(production, token, table, sets)
                if entry["reason"] == "FIRST"
                else follow_path(lhs, token, g, table, sets)
            )
            reason = entry["reason"]
            if path:
                reason += " via " + " ".join(map(str, path))
            lines.append(
                f"  {entry['number']}: {production['notation']} ({reason})"
            )
    lines += [
        "LL(1): " + ("yes" if not table["conflicts"] else "no"),
        f"conflicts before transformation: {conflicts_before}",
    ]
    return lines


def compact_tree(node):
    """Drop epsilon/empty nodes, inline helper nonterminals and collapse unaries."""
    children = []
    for original in node["children"]:
        if original["symbol"] == "%empty":
            continue
        child = compact_tree(original)
        if (is_nonterminal(child["symbol"]) and not child["mark"]
                and not child["children"]):
            continue
        if (is_nonterminal(child["symbol"])
                and "'" in child["symbol"] and not child["mark"]):
            children.extend(child["children"])
        else:
            children.append(child)
    result = {
        "symbol": node["symbol"], "mark": node["mark"],
        "children": children,
    }
    return children[0] if len(children) == 1 and not node["mark"] else result


def tree_lines(root):
    lines = [tree_label(root)]
    def visit(node, prefix, last):
        branch = (chr(96) + "-- ") if last else "|-- "
        lines.append(prefix + branch + tree_label(node))
        next_prefix = prefix + ("    " if last else "|   ")
        for i, child in enumerate(node["children"]):
            visit(child, next_prefix, i == len(node["children"]) - 1)
    for i, child in enumerate(root["children"]):
        visit(child, "", i == len(root["children"]) - 1)
    return lines


def trace_lines(trace):
    rows = [("step", "stack", "input", "action")] + list(trace)
    widths = [max(len(row[i]) for row in rows) for i in range(3)]
    return [
        row[0].ljust(widths[0]) + "  "
        + row[1].ljust(widths[1]) + "  "
        + row[2].ljust(widths[2]) + "  " + row[3]
        for row in rows
    ]


def leftmost_derivation(start, numbers, productions):
    symbols = [start]
    lines = ["  " + start]
    for number in numbers:
        production = productions[number - 1]
        position = next(i for i, symbol in enumerate(symbols)
                        if is_nonterminal(symbol))
        symbols[position:position + 1] = production["rhs"]
        lines.append("  => " + format_alternative(symbols))
    return lines


def recognize_original_language(grammar, tokens):
    """Earley membership test for the cleaned grammar, including left recursion."""
    count = len(tokens)
    chart = [set() for _ in range(count + 1)]
    pending = [[] for _ in range(count + 1)]
    seed = ("<__root>", (grammar["start"],), 0, 0)
    chart[0].add(seed)
    pending[0].append(seed)

    def add(index, item):
        if item not in chart[index]:
            chart[index].add(item)
            pending[index].append(item)

    for position in range(count + 1):
        cursor = 0
        while cursor < len(pending[position]):
            lhs, rhs, dot, origin = pending[position][cursor]
            cursor += 1
            if dot == len(rhs):
                for a, body, consumed, start in list(pending[origin]):
                    if consumed < len(body) and body[consumed] == lhs:
                        add(position, (a, body, consumed + 1, start))
            elif is_nonterminal(rhs[dot]):
                next_symbol = rhs[dot]
                for alternative in grammar["rules"][next_symbol]:
                    add(position, (next_symbol, alternative, 0, position))
                for a, body, consumed, start in list(pending[position]):
                    if (a == next_symbol and consumed == len(body)
                            and start == position):
                        add(position, (lhs, rhs, dot + 1, origin))
            elif position < count and rhs[dot] == tokens[position]:
                add(position + 1, (lhs, rhs, dot + 1, origin))
    return ("<__root>", (grammar["start"],), 1, 0) in chart[count]


def parse_input(tokens, grammar, sets, table):
    known = set(sets["terminals"])
    kept = []
    errors = []
    for i, token in enumerate(tokens, 1):
        if token in known:
            kept.append((token, i))
        else:
            errors.append(f'unknown "{token}" at token {i}; removed')
    parsed = parse_tokens(kept, grammar, sets, table)
    parsed["original"] = list(tokens)
    parsed["unknown_errors"] = errors
    parsed["accepted"] = not errors and not parsed["errors"]
    parsed["language"] = None
    return parsed


def one_parse_report(number, parsed, grammar, table):
    errors = parsed["unknown_errors"] + parsed["errors"]
    counts = parsed["counts"]
    lines = [
        f"== input {number} ==",
        "tokens:" + "".join(" " + item for item in parsed["original"]),
    ]
    lines.extend(trace_lines(parsed["trace"]))
    lines.append(
        "left parse:" + "".join(" " + str(x) for x in parsed["left_parse"])
    )
    lines.append(
        f"stats: steps={len(parsed['trace'])} "
        f"predicts={counts['predict']} matches={counts['match']} "
        f"max_stack={counts['max_stack']}"
    )
    if errors:
        lines.append("errors:")
        lines.extend("  " + error for error in errors)
    lines.append(
        "result: accepted" if parsed["accepted"]
        else f"result: rejected (errors: {len(errors)})"
    )
    lines.append("language: " + ("yes" if parsed["language"] else "no"))
    if parsed["accepted"]:
        lines.append("derivation:")
        lines.extend(leftmost_derivation(
            grammar["start"], parsed["left_parse"], table["productions"]
        ))
    lines.append("tree:")
    lines.extend(tree_lines(parsed["root"]))
    lines.append("compact tree:")
    lines.extend(tree_lines(compact_tree(parsed["root"])))
    return lines


def parse_report(parsed_inputs, grammar, sets, table, sentences, contexts):
    lines = []
    for index, parsed in enumerate(parsed_inputs, 1):
        lines.extend(one_parse_report(index, parsed, grammar, table))
        lines.append("")
    accepted = sum(parsed["accepted"] for parsed in parsed_inputs)
    in_language = sum(parsed["language"] for parsed in parsed_inputs)
    mismatches = [
        i for i, parsed in enumerate(parsed_inputs, 1)
        if parsed["accepted"] != parsed["language"]
    ]
    used = {
        number for parsed in parsed_inputs
        for number in parsed["left_parse"]
    }
    unused = [
        item for item in table["productions"] if item["number"] not in used
    ]
    lines.extend([
        "== summary ==",
        f"inputs={len(parsed_inputs)} accepted={accepted} "
        f"rejected={len(parsed_inputs) - accepted} in_language={in_language}",
        "mismatches:" + "".join(" " + str(index) for index in mismatches),
        "recovery: "
        f"unknown={sum(len(p['unknown_errors']) for p in parsed_inputs)} "
        f"skip={sum(p['counts']['skip'] for p in parsed_inputs)} "
        f"pop={sum(p['counts']['pop'] for p in parsed_inputs)} "
        f"missing={sum(p['counts']['missing'] for p in parsed_inputs)}",
        f"coverage: {len(used)} of {len(table['productions'])} productions used",
        "unused:" + "".join(" " + str(p["number"]) for p in unused),
    ])
    for production in unused:
        sentence = example_sentence(production, sentences, contexts)
        parsed = parse_tokens(
            [(word, i + 1) for i, word in enumerate(sentence)],
            grammar, sets, table
        )
        errors = sum(
            parsed["counts"][name] for name in ("skip", "pop", "missing")
        )
        lines.extend([
            f"  {production['number']}: {production['notation']}",
            "    example:" + "".join(" " + word for word in sentence),
            ("    result: accepted" if errors == 0
             else f"    result: rejected (errors: {errors})"),
            ("    used: yes" if production["number"] in parsed["left_parse"]
             else "    used: no"),
        ])
    return lines


def save(name, lines):
    output = Path("output") / name
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text("\n".join(lines) + "\n", encoding="ascii")


def main():
    source = parse_grammar()
    declarations = check_declarations(source)
    cleaned, clean_diags = clean_grammar(source)
    recursion_diags = left_recursion_diagnostics(cleaned)
    recursion, recursion_log = eliminate_left_recursion(cleaned)
    factored, factoring_log = left_factor(recursion)
    final, final_log, final_diags = final_pruning(factored)
    unused_diags = unused_declarations(source, final)

    before_sets = analyze_sets(cleaned)
    before_table = build_table(cleaned, before_sets)
    sets = analyze_sets(final)
    table = build_table(final, sets)
    scores, sentences = shortest_sentences(final)
    contexts = shortest_contexts(final, scores, sentences)
    tokens_by_line = [
        line.split(" ") if line else []
        for line in Path("input/inputs.txt").read_text(
            encoding="ascii"
        ).splitlines()
    ]
    parses = [
        parse_input(tokens, final, sets, table)
        for tokens in tokens_by_line
    ]
    for tokens, parsed in zip(tokens_by_line, parses):
        parsed["language"] = recognize_original_language(cleaned, tokens)

    diagnostics = (
        source["diagnostics"] + declarations + clean_diags
        + recursion_diags + final_diags + unused_diags
    )
    if table["conflicts"]:
        diagnostics.append(
            f"result: not LL(1) (conflicts: {len(table['conflicts'])})"
        )
    else:
        diagnostics.append("result: LL(1)")
    save("grammar.txt", grammar_file(
        cleaned, recursion, factored, final,
        recursion_log, factoring_log, final_log
    ))
    save("sets.txt", sets_file(final, sets, sentences))
    save("table.txt", table_file(
        final, sets, table, len(before_table["conflicts"])
    ))
    save("parses.txt", parse_report(
        parses, final, sets, table, sentences, contexts
    ))
    save("diagnostics.txt", diagnostics)


if __name__ == "__main__":
    main()
