suppressPackageStartupMessages(library(gmp))

ZERO <- as.bigq(0L)
ONE <- as.bigq(1L)
DIMENSIONLESS <- as.bigz(rep(0L, 7L))
BASE_NAMES <- c("kg", "m", "s", "A", "K", "mol", "cd")

fail <- function(message) {
    stop(structure(list(message = message, call = NULL), class = c("command_error", "error", "condition")))
}
quantity <- function(value = ONE, dimension = DIMENSIONLESS) list(value = value, dimension = dimension)
integer_text <- function(text) {
    negative <- startsWith(text, "-")
    body <- if (negative) substring(text, 2L) else text
    body <- sub("^0+", "", body)
    value <- as.bigz(if (nzchar(body)) body else "0")
    if (negative) -value else value
}
integer_power <- function(base, exponent) {
    result <- as.bigz(1L)
    for (i in seq_len(exponent)) result <- result * base
    result
}
fraction <- function(value) {
    n <- as.character(numerator(value))
    d <- denominator(value)
    if (d == 1L) n else paste0(n, "/", as.character(d))
}
decimal <- function(value) {
    n <- abs(numerator(value))
    d <- denominator(value)
    whole <- n %/% d
    tail <- ((n %% d) * 1000000L) %/% d
    digits <- as.character(tail)
    paste0(if (value < ZERO) "-" else "", as.character(whole), ".", strrep("0", 6L - nchar(digits)), digits)
}
notation <- function(value, unit) paste0(fraction(value), " ", unit, " (", decimal(value), ")")
is_letter <- function(character) character %in% c(LETTERS, letters)
is_digit <- function(character) character %in% as.character(0L:9L)
parse_number <- function(text) {
    if (!grepl("^-?[0-9]+([./][0-9]+)?$", text, perl = TRUE)) fail(paste("BAD NUMBER", text))
    negative <- startsWith(text, "-")
    body <- if (negative) substring(text, 2L) else text
    if (grepl("/", body, fixed = TRUE)) {
        parts <- strsplit(body, "/", fixed = TRUE)[[1L]]
        divisor <- integer_text(parts[2L])
        if (divisor == 0L) fail(paste("BAD NUMBER", text))
        value <- as.bigq(integer_text(parts[1L]), divisor)
    } else if (grepl(".", body, fixed = TRUE)) {
        parts <- strsplit(body, ".", fixed = TRUE)[[1L]]
        divisor <- integer_power(as.bigz(10L), nchar(parts[2L]))
        value <- as.bigq(integer_text(parts[1L]) * divisor + integer_text(parts[2L]), divisor)
    } else value <- as.bigq(integer_text(body))
    if (negative) -value else value
}
checked_exponent <- function(text) {
    value <- as.integer(text)
    if (!value %in% c(-3L, -2L, -1L, 1L, 2L, 3L)) fail(paste("BAD EXPONENT", text))
    value
}
scalar_power <- function(value, exponent) {
    if (exponent < 0L) value <- ONE / value
    result <- ONE
    for (i in seq_len(abs(exponent))) result <- result * value
    result
}
check_name <- function(name, variable = FALSE) {
    if (!grepl("^[A-Za-z]{1,12}$", name, perl = TRUE) ||
        (variable && name %in% c("abs", "sqrt", "min", "max"))) fail(paste("BAD NAME", name))
}
dimension_text <- function(dimension) {
    selected <- which(dimension != 0L)
    if (!length(selected)) return("1")
    parts <- vapply(selected, function(i) {
        if (dimension[i] == 1L) BASE_NAMES[i] else paste0(BASE_NAMES[i], "^", as.character(dimension[i]))
    }, character(1L))
    paste(parts, collapse = " ")
}
same_dimension <- function(a, b) all(a == b)
match_dimensions <- function(a, b) {
    if (!same_dimension(a, b)) fail(paste("DIMENSION MISMATCH", dimension_text(a), "vs", dimension_text(b)))
}

KIND_ROWS <- c(
    "dimensionless 0 0 0 0 0 0 0", "length 0 1 0 0 0 0 0", "mass 1 0 0 0 0 0 0",
    "time 0 0 1 0 0 0 0", "current 0 0 0 1 0 0 0", "temperature 0 0 0 0 1 0 0",
    "amount 0 0 0 0 0 1 0", "luminous_intensity 0 0 0 0 0 0 1", "area 0 2 0 0 0 0 0",
    "volume 0 3 0 0 0 0 0", "speed 0 1 -1 0 0 0 0", "acceleration 0 1 -2 0 0 0 0",
    "density 1 -3 0 0 0 0 0", "momentum 1 1 -1 0 0 0 0", "force 1 1 -2 0 0 0 0",
    "energy 1 2 -2 0 0 0 0", "power 1 2 -3 0 0 0 0", "pressure 1 -1 -2 0 0 0 0",
    "frequency 0 0 -1 0 0 0 0", "charge 0 0 1 1 0 0 0", "voltage 1 2 -3 -1 0 0 0",
    "resistance 1 2 -3 -2 0 0 0", "conductance -1 -2 3 2 0 0 0", "capacitance -1 -2 4 2 0 0 0",
    "magnetic_flux 1 2 -2 -1 0 0 0", "flux_density 1 0 -2 -1 0 0 0", "inductance 1 2 -2 -2 0 0 0",
    "illuminance 0 -2 0 0 0 0 1", "catalytic_activity 0 0 -1 0 0 1 0"
)
KINDS <- setNames(lapply(KIND_ROWS, function(row) as.bigz(strsplit(row, " ", fixed = TRUE)[[1L]][-1L])),
                  vapply(strsplit(KIND_ROWS, " ", fixed = TRUE), `[`, character(1L), 1L))
BUILTIN_ROWS <- c(
    "m 1 length yes", "g 1/1000 mass yes", "s 1 time yes", "A 1 current yes",
    "K 1 temperature yes", "mol 1 amount yes", "cd 1 luminous_intensity yes",
    "N 1 force yes", "J 1 energy yes", "W 1 power yes", "Pa 1 pressure yes",
    "Hz 1 frequency yes", "C 1 charge yes", "V 1 voltage yes", "ohm 1 resistance yes",
    "S 1 conductance yes", "F 1 capacitance yes", "Wb 1 magnetic_flux yes",
    "T 1 flux_density yes", "H 1 inductance yes", "lx 1 illuminance yes",
    "kat 1 catalytic_activity yes", "L 1/1000 volume yes", "t 1000 mass no",
    "min 60 time no", "h 3600 time no", "day 86400 time no", "in 127/5000 length no",
    "ft 381/1250 length no", "yd 1143/1250 length no", "mi 201168/125 length no",
    "nmi 1852 length no", "ha 10000 area no", "kn 463/900 speed no",
    "bar 100000 pressure yes", "atm 101325 pressure no", "Torr 20265/152 pressure no",
    "cal 523/125 energy yes", "Wh 3600 energy yes", "Ah 3600 charge yes",
    "dC 1 temperature no", "dF 5/9 temperature no"
)
PREFIXES <- c("G", "M", "k", "h", "da", "d", "c", "m", "u", "n")
PREFIX_FACTORS <- c_bigq(lapply(c("1000000000", "1000000", "1000", "100", "10",
                                "1/10", "1/100", "1/1000", "1/1000000", "1/1000000000"), parse_number))
kind_name <- function(dimension) {
    for (name in names(KINDS)) if (same_dimension(KINDS[[name]], dimension)) return(name)
    "-"
}
new_database <- function() {
    database <- new.env(parent = emptyenv())
    database$variables <- new.env(parent = emptyenv())
    database$units <- lapply(BUILTIN_ROWS, function(row) {
        parts <- strsplit(row, " ", fixed = TRUE)[[1L]]
        list(symbol = parts[1L], quantity = quantity(parse_number(parts[2L]), KINDS[[parts[3L]]]),
             prefixable = parts[4L] == "yes", definition = NULL)
    })
    database
}
resolve <- function(database, name) {
    for (unit in database$units) if (unit$symbol == name) return(unit$quantity)
    for (i in seq_along(PREFIXES)) {
        if (startsWith(name, PREFIXES[i])) {
            rest <- substring(name, nchar(PREFIXES[i]) + 1L)
            for (unit in database$units[seq_len(42L)]) {
                if (unit$prefixable && unit$symbol == rest) {
                    return(quantity(PREFIX_FACTORS[i] * unit$quantity$value, unit$quantity$dimension))
                }
            }
        }
    }
    NULL
}
simplified <- function(database, dimension) {
    for (unit in database$units) {
        if (unit$quantity$value == ONE && same_dimension(unit$quantity$dimension, dimension)) return(unit$symbol)
    }
    dimension_text(dimension)
}
selected_units <- function(database, dimension) {
    remaining <- Filter(function(unit) same_dimension(unit$quantity$dimension, dimension), database$units)
    result <- list()
    while (length(remaining)) {
        smallest <- min(c_bigq(lapply(remaining, function(unit) unit$quantity$value)))
        selected <- vapply(remaining, function(unit) unit$quantity$value == smallest, logical(1L))
        group <- remaining[selected]
        symbols <- vapply(group, function(unit) unit$symbol, character(1L))
        result <- c(result, group[order(symbols, method = "radix")])
        remaining <- remaining[!selected]
    }
    result
}

tokenize <- function(source, quantity_mode) {
    characters <- strsplit(source, "", fixed = TRUE)[[1L]]
    count <- length(characters)
    tokens <- list()
    position <- 1L
    while (position <= count) {
        start <- position
        character <- characters[position]
        position <- position + 1L
        kind <- "invalid"
        if (is_letter(character)) {
            kind <- "name"
            while (position <= count && is_letter(characters[position])) position <- position + 1L
        } else if (is_digit(character)) {
            kind <- "number"
            while (position <= count && is_digit(characters[position])) position <- position + 1L
            if (quantity_mode && position < count && characters[position] == "." && is_digit(characters[position + 1L])) {
                position <- position + 1L
                while (position <= count && is_digit(characters[position])) position <- position + 1L
            }
        } else if (quantity_mode && character == "[") {
            closing <- position
            while (closing <= count && characters[closing] != "]") closing <- closing + 1L
            if (closing > position && closing <= count) {
                kind <- "unit"
                position <- closing + 1L
            }
        } else if (character %in% strsplit(if (quantity_mode) "+-*/^()," else "*/^()-", "", fixed = TRUE)[[1L]]) kind <- "punctuation"
        tokens[[length(tokens) + 1L]] <- list(kind = kind, text = substring(source, start, position - 1L), position = start)
    }
    tokens[[length(tokens) + 1L]] <- list(kind = "end", text = "", position = count + 1L)
    parser <- new.env(parent = emptyenv())
    parser$source <- source
    parser$tokens <- tokens
    parser$position <- 1L
    parser
}
current <- function(parser) parser$tokens[[parser$position]]
syntax_error <- function(parser) {
    token <- current(parser)
    fail(paste("SYNTAX", parser$source, "AT", if (token$kind == "end") "END" else token$position))
}
take <- function(parser, text) {
    if (current(parser)$text != text) return(FALSE)
    parser$position <- parser$position + 1L
    TRUE
}
expect <- function(parser, text) if (!take(parser, text)) syntax_error(parser)
node <- function(kind, ...) c(list(kind = kind), list(...))
parse_exponent <- function(parser) {
    sign <- if (take(parser, "-")) "-" else ""
    token <- current(parser)
    if (token$kind != "number" || grepl(".", token$text, fixed = TRUE)) syntax_error(parser)
    parser$position <- parser$position + 1L
    paste0(sign, token$text)
}
unit_term <- function(parser) {
    token <- current(parser)
    if (token$kind == "name") {
        parser$position <- parser$position + 1L
        result <- node("name", text = token$text)
    } else if (token$kind == "number" && !startsWith(token$text, "0")) {
        parser$position <- parser$position + 1L
        result <- node("number", text = token$text)
    } else if (take(parser, "(")) {
        result <- unit_expression(parser)
        expect(parser, ")")
    } else syntax_error(parser)
    if (take(parser, "^")) result <- node("power", left = result, text = parse_exponent(parser))
    result
}
unit_expression <- function(parser) {
    first <- unit_term(parser)
    result <- node("*", left = node("number", text = "1"), right = first)
    while (current(parser)$text %in% c("*", "/")) {
        operation <- current(parser)$text
        parser$position <- parser$position + 1L
        following <- unit_term(parser)
        result <- node(operation, left = result, right = following)
    }
    result
}
validate_unit <- function(database, tree) {
    if (tree$kind == "name") {
        resolved <- resolve(database, tree$text)
        if (is.null(resolved)) fail(paste("UNKNOWN UNIT", tree$text))
        tree$resolved <- resolved
    } else if (tree$kind == "power") {
        tree$left <- validate_unit(database, tree$left)
        tree$exponent <- checked_exponent(tree$text)
    } else if (tree$kind %in% c("*", "/")) {
        tree$left <- validate_unit(database, tree$left)
        tree$right <- validate_unit(database, tree$right)
    }
    tree
}
parse_unit <- function(database, source) {
    parser <- tokenize(source, FALSE)
    tree <- unit_expression(parser)
    if (current(parser)$kind != "end") syntax_error(parser)
    validate_unit(database, tree)
}
evaluate_unit <- function(tree) {
    if (tree$kind == "number") return(quantity(as.bigq(integer_text(tree$text))))
    if (tree$kind == "name") return(tree$resolved)
    left <- evaluate_unit(tree$left)
    if (tree$kind == "power") return(quantity(scalar_power(left$value, tree$exponent), left$dimension * tree$exponent))
    right <- evaluate_unit(tree$right)
    if (tree$kind == "*") quantity(left$value * right$value, left$dimension + right$dimension)
    else quantity(left$value / right$value, left$dimension - right$dimension)
}
unit_value <- function(database, source) evaluate_unit(parse_unit(database, source))
reduced <- function(tree) {
    if (tree$kind == "number") return(list(coefficient = as.bigq(integer_text(tree$text)), names = character(), powers = as.bigz(integer())))
    if (tree$kind == "name") return(list(coefficient = ONE, names = tree$text, powers = as.bigz(1L)))
    left <- reduced(tree$left)
    if (tree$kind == "power") {
        left$coefficient <- scalar_power(left$coefficient, tree$exponent)
        left$powers <- left$powers * tree$exponent
        return(left)
    }
    right <- reduced(tree$right)
    sign <- if (tree$kind == "*") 1L else -1L
    left$coefficient <- if (sign == 1L) left$coefficient * right$coefficient else left$coefficient / right$coefficient
    for (i in seq_along(right$names)) {
        index <- match(right$names[i], left$names)
        if (is.na(index)) {
            left$names <- c(left$names, right$names[i])
            left$powers <- c(left$powers, sign * right$powers[i])
        } else left$powers[index] <- left$powers[index] + sign * right$powers[i]
    }
    left
}
reduced_text <- function(tree) {
    result <- reduced(tree)
    parts <- if (result$coefficient != ONE) fraction(result$coefficient) else character()
    for (i in seq_along(result$names)) {
        exponent <- result$powers[i]
        if (exponent != 0L) parts <- c(parts, if (exponent == 1L) result$names[i] else paste0(result$names[i], "^", as.character(exponent)))
    }
    if (length(parts)) paste(parts, collapse = " ") else "1"
}
quantity_primary <- function(parser) {
    token <- current(parser)
    if (token$kind == "number") {
        parser$position <- parser$position + 1L
        if (current(parser)$kind == "unit") {
            unit <- current(parser)$text
            parser$position <- parser$position + 1L
            result <- node("unit", text = token$text, unit = substring(unit, 2L, nchar(unit) - 1L))
        } else result <- node("number", text = token$text)
    } else if (token$kind == "unit") {
        parser$position <- parser$position + 1L
        result <- node("unit", text = "1", unit = substring(token$text, 2L, nchar(token$text) - 1L))
    } else if (token$kind == "name") {
        parser$position <- parser$position + 1L
        if (take(parser, "(")) {
            arguments <- list(quantity_expression(parser))
            while (take(parser, ",")) arguments[[length(arguments) + 1L]] <- quantity_expression(parser)
            expect(parser, ")")
            result <- node("call", text = token$text, arguments = arguments)
        } else result <- node("variable", text = token$text)
    } else if (take(parser, "(")) {
        result <- quantity_expression(parser)
        expect(parser, ")")
    } else syntax_error(parser)
    if (take(parser, "^")) result <- node("power", left = result, text = parse_exponent(parser))
    result
}
quantity_unary <- function(parser) {
    if (take(parser, "-")) node("negative", left = quantity_unary(parser)) else quantity_primary(parser)
}
quantity_product <- function(parser) {
    result <- quantity_unary(parser)
    while (current(parser)$text %in% c("*", "/")) {
        operation <- current(parser)$text
        parser$position <- parser$position + 1L
        following <- quantity_unary(parser)
        result <- node(operation, left = result, right = following)
    }
    result
}
quantity_expression <- function(parser) {
    result <- quantity_product(parser)
    while (current(parser)$text %in% c("+", "-")) {
        operation <- current(parser)$text
        parser$position <- parser$position + 1L
        following <- quantity_product(parser)
        result <- node(operation, left = result, right = following)
    }
    result
}
integer_sqrt <- function(value) {
    if (value < 2L) return(value)
    current_value <- value
    following <- (value + 1L) %/% 2L
    while (following < current_value) {
        current_value <- following
        following <- (current_value + value %/% current_value) %/% 2L
    }
    current_value
}
evaluate_quantity <- function(database, tree) {
    if (tree$kind == "number") return(quantity(parse_number(tree$text)))
    if (tree$kind == "unit") {
        unit <- unit_value(database, tree$unit)
        return(quantity(parse_number(tree$text) * unit$value, unit$dimension))
    }
    if (tree$kind == "variable") {
        if (!exists(tree$text, database$variables, inherits = FALSE)) fail(paste("UNKNOWN VARIABLE", tree$text))
        return(database$variables[[tree$text]])
    }
    if (tree$kind == "call") {
        if (!tree$text %in% c("abs", "sqrt", "min", "max")) fail(paste("UNKNOWN FUNCTION", tree$text))
        required <- if (tree$text %in% c("abs", "sqrt")) 1L else 2L
        if (length(tree$arguments) != required) fail(paste("BAD ARGUMENTS", tree$text))
        first <- evaluate_quantity(database, tree$arguments[[1L]])
        if (tree$text == "abs") return(quantity(abs(first$value), first$dimension))
        if (tree$text == "sqrt") {
            if (first$value < ZERO) fail("NEGATIVE ROOT")
            if (any(first$dimension %% 2L != 0L)) fail(paste("ODD DIMENSION", dimension_text(first$dimension)))
            n <- numerator(first$value)
            d <- denominator(first$value)
            root_n <- integer_sqrt(n)
            root_d <- integer_sqrt(d)
            if (root_n * root_n != n || root_d * root_d != d) fail("NOT EXACT")
            return(quantity(as.bigq(root_n, root_d), first$dimension %/% 2L))
        }
        second <- evaluate_quantity(database, tree$arguments[[2L]])
        match_dimensions(first$dimension, second$dimension)
        take_first <- if (tree$text == "min") first$value <= second$value else first$value >= second$value
        return(if (take_first) first else second)
    }
    left <- evaluate_quantity(database, tree$left)
    if (tree$kind == "negative") return(quantity(-left$value, left$dimension))
    if (tree$kind == "power") {
        exponent <- checked_exponent(tree$text)
        if (left$value == ZERO && exponent < 0L) fail("DIVISION BY ZERO")
        return(quantity(scalar_power(left$value, exponent), left$dimension * exponent))
    }
    right <- evaluate_quantity(database, tree$right)
    if (tree$kind %in% c("+", "-")) {
        match_dimensions(left$dimension, right$dimension)
        value <- if (tree$kind == "+") left$value + right$value else left$value - right$value
        return(quantity(value, left$dimension))
    }
    if (tree$kind == "*") return(quantity(left$value * right$value, left$dimension + right$dimension))
    if (right$value == ZERO) fail("DIVISION BY ZERO")
    quantity(left$value / right$value, left$dimension - right$dimension)
}
quantity_value <- function(database, source) {
    parser <- tokenize(source, TRUE)
    tree <- quantity_expression(parser)
    if (current(parser)$kind != "end") syntax_error(parser)
    evaluate_quantity(database, tree)
}

execute <- function(database, line) {
    words <- strsplit(line, " ", fixed = TRUE)[[1L]]
    command <- words[1L]
    if (command == "DEFINE") {
        name <- words[2L]
        check_name(name)
        value <- parse_number(words[4L])
        unit <- unit_value(database, words[5L])
        if (name %in% names(KINDS) || !is.null(resolve(database, name))) fail(paste("NAME TAKEN", name))
        if (value <= ZERO) fail(paste("NOT POSITIVE", words[4L]))
        factor <- value * unit$value
        database$units[[length(database$units) + 1L]] <- list(
            symbol = name, quantity = quantity(factor, unit$dimension), prefixable = FALSE,
            definition = list(value = value, expression = words[5L]))
        return(paste0("DEFINE ", name, " factor=", fraction(factor), " dim=", dimension_text(unit$dimension), " kind=", kind_name(unit$dimension)))
    }
    if (command == "UNDEF") {
        name <- words[2L]
        symbols <- vapply(database$units, function(unit) unit$symbol, character(1L))
        index <- match(name, symbols)
        if (!is.na(index) && index <= 42L) fail(paste("BUILTIN UNIT", name))
        if (is.na(index)) fail(paste("NOT DEFINED", name))
        database$units <- database$units[-index]
        return(paste("UNDEF", name))
    }
    if (command == "DEFS") {
        output <- paste0("DEFS count=", length(database$units) - 42L)
        for (unit in database$units[-seq_len(42L)]) {
            definition <- unit$definition
            output <- c(output, paste0("DEF ", unit$symbol, " = ", fraction(definition$value), " ", definition$expression,
                                      " factor=", fraction(unit$quantity$value), " dim=", dimension_text(unit$quantity$dimension)))
        }
        return(output)
    }
    if (command %in% c("CONVERT", "INVERT")) {
        value <- parse_number(words[2L])
        source <- unit_value(database, words[3L])
        target <- unit_value(database, words[5L])
        if (command == "INVERT") {
            if (same_dimension(source$dimension, DIMENSIONLESS) || !same_dimension(source$dimension + target$dimension, DIMENSIONLESS)) {
                fail(paste("NOT RECIPROCAL", dimension_text(source$dimension), "vs", dimension_text(target$dimension)))
            }
            if (value == ZERO) fail("DIVISION BY ZERO")
        } else match_dimensions(source$dimension, target$dimension)
        result <- value * source$value
        if (command == "INVERT") result <- ONE / result
        return(paste(command, fraction(value), words[3L], "=", notation(result / target$value, words[5L])))
    }
    if (command %in% c("DIM", "REDUCE", "SIMPLIFY")) {
        tree <- parse_unit(database, words[2L])
        unit <- evaluate_unit(tree)
        result <- switch(command,
            DIM = paste0(dimension_text(unit$dimension), " factor=", fraction(unit$value), " kind=", kind_name(unit$dimension)),
            REDUCE = reduced_text(tree),
            SIMPLIFY = notation(unit$value, simplified(database, unit$dimension)))
        return(paste(command, words[2L], "=", result))
    }
    if (command %in% c("ADD", "SUB", "MUL", "DIV", "COMPARE")) {
        a <- parse_number(words[2L])
        first <- unit_value(database, words[3L])
        b <- parse_number(words[4L])
        second <- unit_value(database, words[5L])
        has_target <- length(words) == 7L
        target <- if (has_target) unit_value(database, words[7L]) else first
        prefix <- paste(command, fraction(a), words[3L])
        suffix <- paste(fraction(b), words[5L])
        if (command %in% c("ADD", "SUB", "COMPARE")) {
            match_dimensions(first$dimension, second$dimension)
            if (has_target) match_dimensions(first$dimension, target$dimension)
            left <- a * first$value
            right <- b * second$value
            if (command == "COMPARE") {
                relation <- if (left < right) "<" else if (left > right) ">" else "="
                ratio <- if (right == ZERO) "undefined" else fraction(left / right)
                return(paste(prefix, relation, suffix, paste0("ratio=", ratio)))
            }
            operation <- if (command == "ADD") "+" else "-"
            result <- if (command == "ADD") left + right else left - right
            label <- if (has_target) words[7L] else words[3L]
            return(paste(prefix, operation, suffix, "=", notation(result / target$value, label)))
        }
        multiply <- command == "MUL"
        dimension <- first$dimension + second$dimension * (if (multiply) 1L else -1L)
        if (!multiply && b == ZERO) fail("DIVISION BY ZERO")
        if (has_target) match_dimensions(dimension, target$dimension)
        raw <- if (multiply) a * b else a / b
        left <- a * first$value
        right <- b * second$value
        coherent <- if (multiply) left * right else left / right
        operation <- if (multiply) "*" else "/"
        prefix <- paste(prefix, operation, suffix, "=")
        if (has_target) return(paste(prefix, notation(coherent / target$value, words[7L])))
        right_unit <- words[5L]
        if (!multiply && grepl("[*/]", right_unit)) right_unit <- paste0("(", right_unit, ")")
        return(paste(prefix, fraction(raw), paste0(words[3L], operation, right_unit), "=", notation(coherent, simplified(database, dimension))))
    }
    if (command == "TEMP") {
        value <- parse_number(words[2L])
        for (scale in words[c(3L, 5L)]) if (!scale %in% c("C", "F", "K", "R")) fail(paste("UNKNOWN SCALE", scale))
        kelvin <- switch(words[3L], C = value + as.bigq(5463L, 20L),
                         F = (value + as.bigq(45967L, 100L)) * 5L / 9L,
                         R = value * 5L / 9L, K = value)
        if (kelvin < ZERO) fail("BELOW ABSOLUTE ZERO")
        result <- switch(words[5L], C = kelvin - as.bigq(5463L, 20L),
                         F = kelvin * 9L / 5L - as.bigq(45967L, 100L),
                         R = kelvin * 9L / 5L, K = kelvin)
        return(paste("TEMP", fraction(value), words[3L], "=", notation(result, words[5L])))
    }
    if (command %in% c("LIST", "TABLE")) {
        value <- ONE
        unit <- quantity()
        if (command == "TABLE") {
            value <- parse_number(words[2L])
            unit <- unit_value(database, words[3L])
            dimension <- unit$dimension
        } else if (words[2L] %in% names(KINDS)) dimension <- KINDS[[words[2L]]]
        else dimension <- unit_value(database, words[2L])$dimension
        selected <- selected_units(database, dimension)
        if (command == "TABLE") {
            output <- paste0("TABLE ", fraction(value), " ", words[3L], " dim=", dimension_text(dimension), " count=", length(selected))
        } else output <- paste0("LIST ", words[2L], " dim=", dimension_text(dimension), " kind=", kind_name(dimension), " count=", length(selected))
        for (item in selected) {
            if (command == "TABLE") output <- c(output, paste("ROW", notation((value * unit$value) / item$quantity$value, item$symbol)))
            else output <- c(output, paste0("UNIT ", item$symbol, " factor=", fraction(item$quantity$value),
                                            " origin=", if (is.null(item$definition)) "builtin" else "user",
                                            " prefix=", if (item$prefixable) "yes" else "no"))
        }
        return(output)
    }
    if (command == "AUTO") {
        value <- parse_number(words[2L])
        unit <- unit_value(database, words[3L])
        reference <- NULL
        for (item in database$units[seq_len(42L)]) {
            if (item$prefixable && same_dimension(item$quantity$dimension, unit$dimension)) {
                reference <- item
                break
            }
        }
        if (is.null(reference)) fail(paste("NO PREFIXABLE UNIT", dimension_text(unit$dimension)))
        scaled <- (value * unit$value) / reference$quantity$value
        magnitude <- abs(scaled)
        exponent <- 0L
        if (magnitude >= ONE) {
            while (exponent < 9L && magnitude >= scalar_power(as.bigq(10L), exponent + 3L)) exponent <- exponent + 3L
        } else if (magnitude > ZERO) {
            while (exponent > -9L && magnitude < scalar_power(as.bigq(10L), exponent)) exponent <- exponent - 3L
        }
        prefix <- c("n", "u", "m", "", "k", "M", "G")[(exponent + 9L) %/% 3L + 1L]
        return(paste("AUTO", fraction(value), words[3L], "=", notation(scaled / scalar_power(as.bigq(10L), exponent), paste0(prefix, reference$symbol))))
    }
    if (command == "SPLIT") {
        value <- parse_number(words[2L])
        unit <- unit_value(database, words[3L])
        parts <- strsplit(words[5L], ",", fixed = TRUE)[[1L]]
        targets <- lapply(parts, function(part) unit_value(database, part))
        if (value < ZERO) fail("NEGATIVE VALUE")
        for (target in targets) match_dimensions(unit$dimension, target$dimension)
        for (i in seq_len(length(targets) - 1L)) if (targets[[i]]$value <= targets[[i + 1L]]$value) fail("UNIT ORDER")
        remaining <- value * unit$value
        pieces <- character()
        for (i in seq_len(length(parts) - 1L)) {
            quotient <- remaining / targets[[i]]$value
            count <- numerator(quotient) %/% denominator(quotient)
            remaining <- remaining - as.bigq(count) * targets[[i]]$value
            pieces <- c(pieces, paste(as.character(count), parts[i]))
        }
        last <- length(parts)
        pieces <- c(pieces, notation(remaining / targets[[last]]$value, parts[last]))
        return(paste("SPLIT", fraction(value), words[3L], "=", paste(pieces, collapse = " ")))
    }
    if (command == "LET") {
        check_name(words[2L], TRUE)
        result <- quantity_value(database, words[4L])
        database$variables[[words[2L]]] <- result
        return(paste("LET", words[2L], "=", notation(result$value, simplified(database, result$dimension))))
    }
    if (command == "EVAL") {
        result <- quantity_value(database, words[2L])
        value <- result$value
        label <- simplified(database, result$dimension)
        if (length(words) == 4L) {
            unit <- unit_value(database, words[4L])
            match_dimensions(result$dimension, unit$dimension)
            value <- value / unit$value
            label <- words[4L]
        }
        return(paste("EVAL", words[2L], "=", notation(value, label)))
    }
    if (command == "VARS") {
        names <- sort(ls(database$variables, all.names = TRUE), method = "radix")
        output <- paste0("VARS count=", length(names))
        for (name in names) {
            result <- database$variables[[name]]
            output <- c(output, paste("VAR", name, "=", notation(result$value, simplified(database, result$dimension))))
        }
        return(output)
    }
    fail(paste("UNKNOWN COMMAND", command))
}

main <- function() {
    input <- file("stdin", open = "r")
    on.exit(close(input))
    count <- as.integer(readLines(input, n = 1L, warn = FALSE))
    database <- new_database()
    for (i in seq_len(count)) {
        line <- readLines(input, n = 1L, warn = FALSE)
        output <- tryCatch(execute(database, line), command_error = function(problem) paste("ERROR", conditionMessage(problem)))
        cat(paste0(output, "\n"), sep = "")
    }
}
main()
