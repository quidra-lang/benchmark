# Task B: 99_expression_evaluator / R

The prior assignments leave height=7. Parsing the RHS begins with term 100 / (...); factor enters parentheses, and the nested expression computes height-7 =0 from the existing table. The division guard reports division by zero before the outer expression can evaluate its +bonus term, so no bonus lookup occurs. Assignment is committed only after successful RHS evaluation; the error exits first, preserving the previous height. The output is `error: division by zero`.

The recursive functions use stop on the zero divisor; tryCatch turns it into the error output. The variable assignment follows the successful evaluation, so failure prevents any height update.

Evidence is from `main.R`, L1,L2,L3,L4,L5,L6,L7,L8,L9,L10,L11,L12,L13,L14,L15,L16,L17,L18,L19,L21,L22,L23,L24,L25,L26,L27,L28,L29,L30,L31,L33,L34,L35,L36,L37,L38,L39,L40,L41,L42,L43,L44,L46,L47,L48,L50,L51,L52,L53,L54,L55,L56,L57,L58,L59,L60,L61,L62,L64,L65,L66.

- L1: `evaluate_tokens <- function(tokens, variables, start) {`
- L2: `position <- start`
- L3: `factor <- function() {`
- L4: `token <- tokens[position]`
- L5: `position <<- position + 1`
- L6: `if (token == "-") {`
- L7: `return(-factor())`
- L8: `}`
- L9: `if (token == "(") {`
- L10: `value <- expression()`
- L11: `position <<- position + 1`
- L12: `return(value)`
- L13: `}`
- L14: `if (grepl("^[0-9]", token)) {`
- L15: `return(as.numeric(token))`
- L16: `}`
- L17: `if (!token %in% names(variables)) stop(paste("undefined variable", token), call. = FALSE)`
- L18: `unname(variables[token])`
- L19: `}`
- L21: `term <- function() {`
- L22: `value <- factor()`
- L23: `while (position <= length(tokens) && tokens[position] %in% c("*", "/")) {`
- L24: `operation <- tokens[position]`
- L25: `position <<- position + 1`
- L26: `right <- factor()`
- L27: `if (operation == "/" && right == 0) stop("division by zero", call. = FALSE)`
- L28: `value <- if (operation == "*") value * right else trunc(value / right)`
- L29: `}`
- L30: `value`
- L31: `}`
- L33: `expression <- function() {`
- L34: `value <- term()`
- L35: `while (position <= length(tokens) && tokens[position] %in% c("+", "-")) {`
- L36: `operation <- tokens[position]`
- L37: `position <<- position + 1`
- L38: `right <- term()`
- L39: `value <- if (operation == "+") value + right else value - right`
- L40: `}`
- L41: `value`
- L42: `}`
- L43: `expression()`
- L44: `}`
- L46: `lines <- c(`
- L47: `"width = 12", "height = width - 5", "area = width * height", "(area + 6) / 4",`
- L48: `"shift = -area / 8 + 3", "height = 100 / (height - 7) + bonus", "volume = area * depth",`
- L50: `)`
- L51: `variables <- numeric(0)`
- L52: `for (line in lines) {`
- L53: `tokens <- regmatches(line, gregexpr("[0-9]+|[a-z]+|[()+*/=-]", line, perl = TRUE))[[1]]`
- L54: `assignment <- length(tokens) >= 2 && tokens[2] == "="`
- L55: `result <- tryCatch(`
- L56: `list(ok = TRUE, value = evaluate_tokens(tokens, variables, if (assignment) 3 else 1)),`
- L57: `error = function(e) list(ok = FALSE, error = conditionMessage(e))`
- L58: `)`
- L59: `if (!result$ok) {`
- L60: `cat("error: ", result$error, "\n", sep = "")`
- L61: `} else if (assignment) {`
- L62: `variables[tokens[1]] <- result$value`
- L64: `} else {`
- L65: `cat(sprintf("%d\n", result$value))`
- L66: `}`

Minimization: The parser binding/precedence path, zero guard, deferred assignment and error-to-output path are necessary. Prior width/height statements establish the table state; unrelated later input expressions and unused error cases are omitted where complete-line granularity allows. The selected complete original lines, in source order, cost 916 lexical tokens with `metric/tokenizer.py`; the enclosing contiguous span costs 982, and the complete source costs 984. The selection retains the concrete bindings/operations used in this answer and uses standard arithmetic/library semantics where applicable. It is a reviewed sufficient minimum candidate, not a proof of a unique global optimum. Source review only; no Task A program was compiled or executed.
