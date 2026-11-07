# Task B: 99_expression_evaluator / Julia

The prior assignments leave height=7. Parsing the RHS begins with term 100 / (...); factor enters parentheses, and the nested expression computes height-7 =0 from the existing table. The division guard reports division by zero before the outer expression can evaluate its +bonus term, so no bonus lookup occurs. Assignment is committed only after successful RHS evaluation; the error exits first, preserving the previous height. The output is `error: division by zero`.

The nested parser uses normal left-to-right calls; term checks right==0 and throws before returning to expression. The try block writes variables[target] only after evaluate_tokens returns, and catch prints the error message.

Evidence is from `main.jl`, L1,L2,L3,L4,L5,L6,L7,L8,L9,L10,L11,L12,L13,L14,L15,L16,L17,L19,L20,L21,L22,L23,L24,L25,L26,L27,L28,L29,L31,L32,L33,L34,L35,L36,L37,L38,L39,L40,L41,L42,L45,L46,L47,L51,L55,L56,L57,L58,L59,L60,L61,L62,L63,L64,L68,L69,L70,L71,L72.

- L1: `function evaluate_tokens(tokens, variables, start)`
- L2: `position = start`
- L3: `function factor()`
- L4: `token = tokens[position]`
- L5: `position += 1`
- L6: `if token == "-"`
- L7: `return -factor()`
- L8: `elseif token == "("`
- L9: `value = expression()`
- L10: `position += 1`
- L11: `return value`
- L12: `elseif isdigit(first(token))`
- L13: `return parse(Int, token)`
- L14: `end`
- L15: `haskey(variables, token) || error("undefined variable "*token)`
- L16: `return variables[token]`
- L17: `end`
- L19: `function term()`
- L20: `value = factor()`
- L21: `while position <= length(tokens) && tokens[position] in ("*", "/")`
- L22: `operation = tokens[position]`
- L23: `position += 1`
- L24: `right = factor()`
- L25: `operation == "/" && right == 0 && error("division by zero")`
- L26: `value = operation == "*" ? value*right : div(value, right)`
- L27: `end`
- L28: `return value`
- L29: `end`
- L31: `function expression()`
- L32: `value = term()`
- L33: `while position <= length(tokens) && tokens[position] in ("+", "-")`
- L34: `operation = tokens[position]`
- L35: `position += 1`
- L36: `right = term()`
- L37: `value = operation == "+" ? value+right : value-right`
- L38: `end`
- L39: `return value`
- L40: `end`
- L41: `return expression()`
- L42: `end`
- L45: `lines = [`
- L46: `"width = 12",`
- L47: `"height = width - 5",`
- L51: `"height = 100 / (height - 7) + bonus",`
- L55: `]`
- L56: `variables = Dict{String,Int}()`
- L57: `for line in lines`
- L58: `tokens =`
- L59: `[String(match.match) for match in eachmatch(r"[0-9]+|[a-z]+|[()+*/=-]", line)]`
- L60: `assignment = length(tokens) >= 2 && tokens[2] == "="`
- L61: `try`
- L62: `value = evaluate_tokens(tokens, variables, assignment ? 3 : 1)`
- L63: `if assignment`
- L64: `variables[tokens[1]] = value`
- L68: `end`
- L69: `catch exception`
- L70: `exception isa ErrorException || rethrow()`
- L71: `println("error: ", exception.msg)`
- L72: `end`

Minimization: The parser binding/precedence path, zero guard, deferred assignment and error-to-output path are necessary. Prior width/height statements establish the table state; unrelated later input expressions and unused error cases are omitted where complete-line granularity allows. The selected complete original lines, in source order, cost 721 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 869, and the complete source costs 878. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
