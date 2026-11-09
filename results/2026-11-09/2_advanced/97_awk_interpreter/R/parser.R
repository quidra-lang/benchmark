record <- function(...) list2env(list(...), parent = emptyenv())
ASSIGNMENTS <- c("=", "+=", "-=", "*=", "/=", "%=", "^=")
COMPARISONS <- c("<", "<=", "==", "!=", ">=", ">")
LVALUE_KINDS <- c("name", "array", "field")
STATEMENTS <- c("if", "while", "do", "for", "for_in", "print", "printf", "delete", "next", "break", "continue", "exit", "return", "expression_statement")
awk_node <- function(kind, position, children = list(), ...) {
    list2env(c(list(kind = kind, position = position, children = Filter(Negate(is.null), children)), list(...)), parent = emptyenv())
}
new_parser <- function(tokens) record(tokens = tokens, index = 1L, in_function = FALSE, phase = NULL, loop_depth = 0L)
current_token <- function(parser) parser$tokens[[parser$index]]
take_token <- function(parser) {
    token <- current_token(parser)
    parser$index <- parser$index + 1L
    token
}
syntax_error <- function(parser, position = current_token(parser)$position) syntax_issue(position)
accept_token <- function(parser, spelling) {
    if (current_token(parser)$spelling == spelling) take_token(parser) else NULL
}
expect_token <- function(parser, spelling) {
    if (current_token(parser)$spelling != spelling) syntax_error(parser)
    take_token(parser)
}
parse_name <- function(parser) {
    if (current_token(parser)$kind != "name") syntax_error(parser)
    token <- take_token(parser)
    awk_node("name", token$position, name = token$spelling)
}
skip_newlines <- function(parser) while (!is.null(accept_token(parser, "\n"))) {}
parse_program <- function(parser) {
    items <- list()
    while (current_token(parser)$kind != "end") {
        if (current_token(parser)$spelling %in% c("\n", ";")) {
            take_token(parser)
            next
        }
        opening <- current_token(parser)
        if (!is.null(accept_token(parser, "function"))) {
            if (!current_token(parser)$kind %in% c("name", "function_name")) syntax_error(parser)
            name <- take_token(parser)
            expect_token(parser, "(")
            parameters <- list()
            if (current_token(parser)$spelling != ")") {
                repeat {
                    parameter <- parse_name(parser)
                    parameter$kind <- "parameter"
                    parameters[[length(parameters) + 1L]] <- parameter
                    if (is.null(accept_token(parser, ","))) break
                    skip_newlines(parser)
                }
            }
            expect_token(parser, ")")
            skip_newlines(parser)
            parser$in_function <- TRUE
            body <- parse_block(parser)
            parser$in_function <- FALSE
            items[[length(items) + 1L]] <- awk_node("function", opening$position, c(parameters, list(body)),
                name = name$spelling, name_position = name$position, parameters = parameters, body = body)
            next
        }
        patterns <- list()
        if (opening$spelling %in% c("BEGIN", "END")) flavor <- take_token(parser)$spelling else if (opening$spelling == "{") flavor <- "all" else {
            patterns[[1L]] <- parse_expression(parser)
            if (!is.null(accept_token(parser, ","))) {
                skip_newlines(parser)
                patterns[[2L]] <- parse_expression(parser)
            }
            flavor <- if (length(patterns) == 2L) "range" else "pattern"
        }
        parser$phase <- flavor
        if (flavor %in% c("BEGIN", "END", "all") || current_token(parser)$spelling == "{") {
            action <- parse_block(parser)
        } else {
            if (!current_token(parser)$spelling %in% c("\n", ";") && current_token(parser)$kind != "end") syntax_error(parser)
            action <- NULL
        }
        parser$phase <- NULL
        items[[length(items) + 1L]] <- awk_node("rule", opening$position, c(patterns, list(action)), flavor = flavor, patterns = patterns, action = action)
    }
    items
}
parse_block <- function(parser) {
    opening <- expect_token(parser, "{")
    statements <- list()
    while (current_token(parser)$spelling != "}") {
        if (current_token(parser)$spelling %in% c("\n", ";")) take_token(parser) else statements[[length(statements) + 1L]] <- parse_statement(parser)
    }
    expect_token(parser, "}")
    awk_node("block", opening$position, statements, statements = statements)
}
parse_condition <- function(parser) {
    expect_token(parser, "(")
    value <- parse_expression(parser)
    expect_token(parser, ")")
    value
}
parse_loop_body <- function(parser) {
    skip_newlines(parser)
    parser$loop_depth <- parser$loop_depth + 1L
    body <- parse_statement(parser)
    parser$loop_depth <- parser$loop_depth - 1L
    body
}
parse_terminator <- function(parser) {
    if (current_token(parser)$spelling %in% c(";", "\n")) take_token(parser) else if (current_token(parser)$spelling != "}") syntax_error(parser)
}
parse_statement <- function(parser) {
    token <- current_token(parser)
    spelling <- token$spelling
    if (spelling == "{") return(parse_block(parser))
    if (!is.null(accept_token(parser, ";"))) return(awk_node("empty", token$position))
    if (!is.null(accept_token(parser, "if"))) {
        condition <- parse_condition(parser)
        skip_newlines(parser)
        first <- parse_statement(parser)
        skip_newlines(parser)
        second <- NULL
        if (!is.null(accept_token(parser, "else"))) {
            skip_newlines(parser)
            second <- parse_statement(parser)
        }
        return(awk_node("if", token$position, list(condition, first, second), condition = condition, first = first, second = second))
    }
    if (!is.null(accept_token(parser, "while"))) {
        condition <- parse_condition(parser)
        body <- parse_loop_body(parser)
        return(awk_node("while", token$position, list(condition, body), condition = condition, body = body))
    }
    if (!is.null(accept_token(parser, "do"))) {
        body <- parse_loop_body(parser)
        skip_newlines(parser)
        expect_token(parser, "while")
        condition <- parse_condition(parser)
        parse_terminator(parser)
        return(awk_node("do", token$position, list(body, condition), body = body, condition = condition))
    }
    if (!is.null(accept_token(parser, "for"))) {
        expect_token(parser, "(")
        index <- parser$index
        if (index + 3L <= length(parser$tokens) && parser$tokens[[index]]$kind == "name" &&
            parser$tokens[[index + 1L]]$spelling == "in" && parser$tokens[[index + 2L]]$kind == "name" && parser$tokens[[index + 3L]]$spelling == ")") {
            variable <- parse_name(parser)
            expect_token(parser, "in")
            array <- parse_name(parser)
            expect_token(parser, ")")
            body <- parse_loop_body(parser)
            return(awk_node("for_in", token$position, list(variable, array, body), variable = variable, array = array, body = body))
        }
        initial <- if (current_token(parser)$spelling == ";") NULL else parse_expression(parser)
        expect_token(parser, ";")
        skip_newlines(parser)
        condition <- if (current_token(parser)$spelling == ";") NULL else parse_expression(parser)
        expect_token(parser, ";")
        skip_newlines(parser)
        update <- if (current_token(parser)$spelling == ")") NULL else parse_expression(parser)
        expect_token(parser, ")")
        body <- parse_loop_body(parser)
        return(awk_node("for", token$position, list(initial, condition, update, body), initial = initial, condition = condition, update = update, body = body))
    }
    if (spelling %in% c("print", "printf")) {
        take_token(parser)
        result <- parse_output(parser, token)
    } else if (spelling == "delete") {
        take_token(parser)
        array <- parse_name(parser)
        indexes <- NULL
        if (!is.null(accept_token(parser, "["))) {
            indexes <- parse_expression_list(parser)
            expect_token(parser, "]")
        }
        result <- awk_node("delete", token$position, c(list(array), indexes), array = array, indexes = indexes)
    } else if (spelling %in% c("next", "break", "continue", "exit", "return")) {
        take_token(parser)
        if (spelling == "next" && !parser$in_function && parser$phase %in% c("BEGIN", "END")) syntax_error(parser, token$position)
        if (spelling == "return" && !parser$in_function) syntax_error(parser, token$position)
        if (spelling %in% c("break", "continue") && parser$loop_depth == 0L) syntax_error(parser, token$position)
        value <- if (spelling %in% c("exit", "return") && !current_token(parser)$spelling %in% c(";", "\n", "}")) parse_expression(parser) else NULL
        result <- awk_node(spelling, token$position, list(value), value = value)
    } else {
        expression <- parse_expression(parser)
        result <- awk_node("expression_statement", token$position, list(expression), expression = expression)
    }
    parse_terminator(parser)
    result
}
parenthesized_output <- function(parser) {
    if (current_token(parser)$spelling != "(") return(FALSE)
    depth <- 0L
    for (index in seq.int(parser$index, length(parser$tokens) - 1L)) {
        spelling <- parser$tokens[[index]]$spelling
        if (spelling == "(") depth <- depth + 1L else if (spelling == ")") {
            depth <- depth - 1L
            if (depth == 0L) {
                following <- parser$tokens[[index + 1L]]
                return(following$spelling %in% c(";", "\n", "}", ">", ">>") || following$kind == "end")
            }
        }
    }
    FALSE
}
parse_output <- function(parser, token) {
    arguments <- list()
    if (parenthesized_output(parser)) {
        expect_token(parser, "(")
        arguments <- parse_expression_list(parser)
        expect_token(parser, ")")
    } else if (!current_token(parser)$spelling %in% c(";", "\n", "}", ">", ">>")) arguments <- parse_expression_list(parser, FALSE)
    if (token$spelling == "printf" && !length(arguments)) syntax_error(parser)
    redirect <- if (current_token(parser)$spelling %in% c(">", ">>")) take_token(parser) else NULL
    filename <- if (is.null(redirect)) NULL else parse_concatenation(parser)
    awk_node(token$spelling, token$position, c(arguments, list(filename)), arguments = arguments,
        redirect = if (is.null(redirect)) NULL else redirect$spelling,
        redirect_position = if (is.null(redirect)) NULL else redirect$position, filename = filename)
}
parse_expression_list <- function(parser, greater = TRUE) {
    result <- list(parse_expression(parser, greater))
    while (!is.null(accept_token(parser, ","))) {
        skip_newlines(parser)
        result[[length(result) + 1L]] <- parse_expression(parser, greater)
    }
    result
}
parse_expression <- function(parser, greater = TRUE) {
    left <- parse_conditional(parser, greater)
    if (left$kind %in% LVALUE_KINDS && current_token(parser)$spelling %in% ASSIGNMENTS) {
        operator <- take_token(parser)
        right <- parse_expression(parser, greater)
        return(awk_node("assignment", operator$position, list(left, right), operator = operator$spelling, location = left, value = right))
    }
    left
}
parse_conditional <- function(parser, greater) {
    condition <- parse_logical(parser, 0L, greater)
    operator <- accept_token(parser, "?")
    if (is.null(operator)) return(condition)
    first <- parse_conditional(parser, greater)
    expect_token(parser, ":")
    second <- parse_conditional(parser, greater)
    awk_node("conditional", operator$position, list(condition, first, second), condition = condition, first = first, second = second)
}
binary_node <- function(operator, left, right) {
    awk_node("binary", operator$position, list(left, right), operator = operator$spelling, left = left, right = right)
}
parse_logical <- function(parser, level, greater) {
    if (level == 2L) return(parse_membership(parser, greater))
    spelling <- if (level == 0L) "||" else "&&"
    left <- parse_logical(parser, level + 1L, greater)
    while (current_token(parser)$spelling == spelling) {
        operator <- take_token(parser)
        skip_newlines(parser)
        left <- binary_node(operator, left, parse_logical(parser, level + 1L, greater))
    }
    left
}
parse_membership <- function(parser, greater) {
    left <- parse_comparison(parser, greater)
    while (current_token(parser)$spelling == "in") {
        operator <- take_token(parser)
        array <- parse_name(parser)
        left <- awk_node("membership", operator$position, list(left, array), indexes = list(left), array = array)
    }
    left
}
parse_comparison <- function(parser, greater) {
    left <- parse_concatenation(parser)
    while (current_token(parser)$spelling %in% COMPARISONS && (greater || current_token(parser)$spelling != ">")) {
        operator <- take_token(parser)
        left <- binary_node(operator, left, parse_concatenation(parser))
    }
    left
}
parse_concatenation <- function(parser) {
    left <- parse_additive(parser)
    while (current_token(parser)$kind %in% c("number", "string", "name", "function_name", "builtin") || current_token(parser)$spelling %in% c("$", "(", "++", "--")) {
        position <- current_token(parser)$position
        right <- parse_additive(parser)
        left <- awk_node("binary", position, list(left, right), operator = "concat", left = left, right = right)
    }
    left
}
parse_additive <- function(parser) {
    left <- parse_multiplicative(parser)
    while (current_token(parser)$spelling %in% c("+", "-")) {
        operator <- take_token(parser)
        left <- binary_node(operator, left, parse_multiplicative(parser))
    }
    left
}
parse_multiplicative <- function(parser) {
    left <- parse_unary(parser)
    while (current_token(parser)$spelling %in% c("*", "/", "%")) {
        operator <- take_token(parser)
        left <- binary_node(operator, left, parse_unary(parser))
    }
    left
}
parse_unary <- function(parser) {
    if (current_token(parser)$spelling %in% c("!", "-", "+")) {
        operator <- take_token(parser)
        operand <- parse_unary(parser)
        return(awk_node("unary", operator$position, list(operand), operator = operator$spelling, operand = operand))
    }
    left <- parse_postfix(parser)
    if (current_token(parser)$spelling == "^") {
        operator <- take_token(parser)
        left <- binary_node(operator, left, parse_unary(parser))
    }
    left
}
parse_prefix <- function(parser) {
    operator <- take_token(parser)
    location <- parse_lvalue(parser)
    awk_node("increment", operator$position, list(location), location = location,
        delta = if (operator$spelling == "++") 1L else -1L, prefix = TRUE)
}
parse_postfix <- function(parser) {
    if (current_token(parser)$spelling %in% c("++", "--")) return(parse_prefix(parser))
    left <- parse_atom(parser)
    if (left$kind %in% LVALUE_KINDS && current_token(parser)$spelling %in% c("++", "--")) {
        operator <- take_token(parser)
        return(awk_node("increment", operator$position, list(left), location = left,
            delta = if (operator$spelling == "++") 1L else -1L, prefix = FALSE))
    }
    left
}
parse_lvalue <- function(parser) {
    if (current_token(parser)$kind == "name") {
        node <- parse_name(parser)
        if (!is.null(accept_token(parser, "["))) {
            indexes <- parse_expression_list(parser)
            expect_token(parser, "]")
            return(awk_node("array", node$position, indexes, name = node$name, indexes = indexes))
        }
        return(node)
    }
    dollar <- accept_token(parser, "$")
    if (!is.null(dollar)) {
        index <- if (current_token(parser)$spelling %in% c("++", "--")) parse_prefix(parser) else parse_atom(parser)
        return(awk_node("field", dollar$position, list(index), index = index))
    }
    syntax_error(parser)
}
parse_atom <- function(parser) {
    token <- current_token(parser)
    if (token$kind %in% c("number", "string")) {
        take_token(parser)
        return(awk_node(token$kind, token$position, value = token$value))
    }
    if (token$kind == "name" || token$spelling == "$") return(parse_lvalue(parser))
    if (!is.null(accept_token(parser, "("))) {
        expressions <- parse_expression_list(parser)
        expect_token(parser, ")")
        if (length(expressions) == 1L) return(awk_node("paren", token$position, expressions, expression = expressions[[1L]]))
        expect_token(parser, "in")
        array <- parse_name(parser)
        return(awk_node("membership", token$position, c(expressions, list(array)), indexes = expressions, array = array))
    }
    if (token$kind %in% c("function_name", "builtin")) {
        take_token(parser)
        arguments <- list()
        if (!is.null(accept_token(parser, "("))) {
            if (current_token(parser)$spelling != ")") arguments <- parse_expression_list(parser)
            expect_token(parser, ")")
        } else if (token$kind == "function_name" || token$spelling != "length") syntax_error(parser)
        kind <- if (token$kind == "function_name") "call" else "builtin"
        if (kind == "builtin") check_builtin(parser, token, arguments)
        return(awk_node(kind, token$position, arguments, name = token$spelling, arguments = arguments))
    }
    if (!is.null(accept_token(parser, "getline"))) {
        target <- if (current_token(parser)$kind == "name" || current_token(parser)$spelling == "$") parse_lvalue(parser) else NULL
        filename <- if (!is.null(accept_token(parser, "<"))) parse_atom(parser) else NULL
        return(awk_node("getline", token$position, list(target, filename), target = target, filename = filename))
    }
    syntax_error(parser)
}
check_builtin <- function(parser, token, arguments) {
    count <- length(arguments)
    name <- token$spelling
    valid <- if (name == "length") {
        count %in% c(0L, 1L)
    } else if (name %in% c("substr", "split")) {
        count %in% c(2L, 3L)
    } else if (name == "index") {
        count == 2L
    } else if (name == "sprintf") {
        count >= 1L
    } else count == 1L
    if (!valid || (name == "split" && arguments[[2L]]$kind != "name")) syntax_error(parser, token$position)
}
