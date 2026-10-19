"""Table-driven LL(1) parsing, panic recovery, action trace and tree nodes."""

from grammar_parser import is_nonterminal
from first_follow import terminal_order


def new_node(symbol):
    return {"symbol": symbol, "mark": None, "children": []}


def tree_label(node):
    mark = node["mark"]
    return node["symbol"] + (f" ({mark})" if mark else "")


def parse_tokens(tokens, grammar, sets, table):
    """The passed tokens are (name, original-position) pairs, sans unknowns."""
    input_tokens = list(tokens) + [("$", len(tokens) + 1)]
    root = new_node(grammar["start"])
    stack = [("$", None), (grammar["start"], root)]
    cursor = 0
    left_parse = []
    traces = []
    errors = []
    counts = {"predict": 0, "match": 0, "skip": 0,
              "pop": 0, "missing": 0, "max_stack": 0}

    def expected_for(symbol):
        if not is_nonterminal(symbol):
            return [symbol]
        possible = [
            token for token in sets["terminals"] + ["$"]
            if (symbol, token) in table["choices"]
        ]
        return terminal_order(possible)

    for step in range(1, 1002):
        top, node = stack[-1]
        current, original_position = input_tokens[cursor]
        counts["max_stack"] = max(counts["max_stack"], len(stack))
        before_stack = " ".join(name for name, _ in stack)
        before_input = " ".join(name for name, _ in input_tokens[cursor:])
        event = None
        if top == "$" and current == "$":
            action = "accept"
            terminate = True
        elif top == "$":
            action = "error: skip " + current
            event = ("skip", top, current, original_position)
            cursor += 1
            counts["skip"] += 1
            terminate = False
        elif not is_nonterminal(top):
            if top == current:
                action = "match " + current
                stack.pop()
                cursor += 1
                counts["match"] += 1
            else:
                action = "error: missing " + top
                node["mark"] = "missing"
                stack.pop()
                counts["missing"] += 1
                event = ("missing", top, current, original_position)
            terminate = False
        elif (top, current) in table["choices"]:
            number = table["choices"][(top, current)]
            production = table["productions"][number - 1]
            action = f"predict {number}: {production['notation']}"
            left_parse.append(number)
            stack.pop()
            if production["rhs"]:
                children = [new_node(symbol) for symbol in production["rhs"]]
                node["children"].extend(children)
                for child in reversed(children):
                    stack.append((child["symbol"], child))
            else:
                node["children"].append(new_node("%empty"))
            counts["predict"] += 1
            terminate = False
        elif current == "$" or current in sets["follow"][top]:
            action = "error: pop " + top
            node["mark"] = "error"
            stack.pop()
            counts["pop"] += 1
            event = ("pop", top, current, original_position)
            terminate = False
        else:
            action = "error: skip " + current
            cursor += 1
            counts["skip"] += 1
            event = ("skip", top, current, original_position)
            terminate = False

        traces.append((str(step), before_stack, before_input, action))
        if event is not None:
            kind, symbol, token, position = event
            unexpected = (
                "end of input" if token == "$"
                else f'"{token}" at token {position}'
            )
            if is_nonterminal(symbol):
                expected = " ".join(
                    name if name == "$" else f'"{name}"'
                    for name in expected_for(symbol)
                )
            elif symbol == "$":
                expected = "$"
            else:
                expected = f'"{symbol}"'
            if kind == "skip":
                recovery = f'skipped "{token}"'
            elif kind == "pop":
                recovery = f"popped {symbol}"
            else:
                recovery = f'inserted "{symbol}"'
            errors.append(
                f"step {step}: unexpected {unexpected}; "
                f"expected {expected}; {recovery}"
            )
        if terminate:
            break
    return {
        "root": root, "trace": traces, "left_parse": left_parse,
        "errors": errors, "counts": counts,
    }
