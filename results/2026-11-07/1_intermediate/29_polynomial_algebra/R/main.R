suppressPackageStartupMessages(library(gmp))

ZERO <- as.bigq(0L)
ONE <- as.bigq(1L)
EMPTY <- ZERO[integer()]
X <- as.bigq(c(0L, 1L))

fail <- function(message) {
    stop(structure(list(message = message, call = NULL), class = c("command_error", "error", "condition")))
}
degree <- function(a) length(a) - 1L
leading <- function(a) a[length(a)]
trim <- function(a) {
    end <- length(a)
    while (end > 0L && a[end] == ZERO) end <- end - 1L
    a[seq_len(end)]
}
constant <- function(value) trim(as.bigq(value))
linear <- function(value, slope = ONE) trim(c(value, slope))
is_one <- function(a) length(a) == 1L && a[1L] == ONE
nonzero <- function(a) if (!length(a)) fail("ZERO POLYNOMIAL")
degree_limit <- function(condition) if (condition) fail("DEGREE LIMIT")
product_limit <- function(a, b) degree_limit(length(a) > 0L && length(b) > 0L && degree(a) + degree(b) > 30L)
composition_limit <- function(a, b) degree_limit(degree(a) >= 1L && degree(b) >= 1L && degree(a) * degree(b) > 30L)

fraction <- function(value) {
    n <- as.character(numerator(value))
    d <- denominator(value)
    if (d == 1L) n else paste0(n, "/", as.character(d))
}
literal <- function(word) {
    parts <- strsplit(word, "/", fixed = TRUE)[[1L]]
    n <- as.integer(parts[1L])
    d <- if (length(parts) == 2L) as.integer(parts[2L]) else 1L
    if (d == 0L) fail("ZERO DENOMINATOR")
    as.bigq(n, d)
}
notation <- function(a, variable = "x") {
    terms <- character()
    for (i in rev(seq_along(a))) {
        value <- a[i]
        if (value == ZERO) next
        exponent <- i - 1L
        coefficient <- if (exponent > 0L && abs(value) == ONE) "" else fraction(abs(value))
        suffix <- if (exponent == 0L) "" else if (exponent == 1L) variable else paste0(variable, "^", exponent)
        prefix <- if (!length(terms)) {
            if (value < ZERO) "-" else ""
        } else if (value < ZERO) " - " else " + "
        terms <- c(terms, paste0(prefix, coefficient, suffix))
    }
    if (length(terms)) paste(terms, collapse = "") else "0"
}

add <- function(a, b) {
    size <- max(length(a), length(b))
    trim(c(a, rep(ZERO, size - length(a))) + c(b, rep(ZERO, size - length(b))))
}
subtract <- function(a, b) add(a, -b)
scale <- function(a, value) trim(a * value)
divide_scalar <- function(a, value) trim(a / value)
multiply <- function(a, b) {
    if (!length(a) || !length(b)) return(EMPTY)
    result <- rep(ZERO, length(a) + length(b) - 1L)
    for (i in seq_along(a)) {
        for (j in seq_along(b)) result[i + j - 1L] <- result[i + j - 1L] + a[i] * b[j]
    }
    trim(result)
}
power <- function(a, exponent) {
    if (exponent == 0L) return(ONE)
    if (!length(a)) return(EMPTY)
    if (length(a) == 1L && abs(a[1L]) == ONE) return(if (exponent %% 2L) a else ONE)
    result <- ONE
    for (i in seq_len(exponent)) result <- multiply(result, a)
    result
}
fraction_power <- function(value, exponent) {
    result <- ONE
    for (i in seq_len(exponent)) result <- result * value
    result
}
divide <- function(a, b) {
    quotient <- rep(ZERO, max(0L, length(a) - length(b) + 1L))
    remainder <- a
    while (length(remainder) > 0L && length(remainder) >= length(b)) {
        offset <- length(remainder) - length(b)
        factor <- leading(remainder) / leading(b)
        quotient[offset + 1L] <- factor
        for (j in seq_along(b)) remainder[offset + j] <- remainder[offset + j] - factor * b[j]
        remainder <- trim(remainder)
    }
    list(quotient = trim(quotient), remainder = remainder)
}
modulo <- function(a, b) divide(a, b)$remainder
monic <- function(a) if (length(a)) divide_scalar(a, leading(a)) else a
derivative <- function(a, count = 1L) {
    for (i in seq_len(count)) {
        if (length(a) <= 1L) return(EMPTY)
        a <- trim(a[-1L] * seq_len(length(a) - 1L))
    }
    a
}
integral <- function(a) trim(c(ZERO, a / seq_along(a)))
evaluate <- function(a, value) {
    result <- ZERO
    for (i in rev(seq_along(a))) result <- result * value + a[i]
    result
}
compose <- function(a, b) {
    result <- EMPTY
    for (i in rev(seq_along(a))) result <- add(multiply(result, b), constant(a[i]))
    result
}
polynomial_gcd <- function(a, b) {
    while (length(b)) {
        remainder <- modulo(a, b)
        a <- b
        b <- remainder
    }
    monic(a)
}
extended_gcd <- function(a, b) {
    s0 <- ONE
    s1 <- EMPTY
    t0 <- EMPTY
    t1 <- ONE
    while (length(b)) {
        division <- divide(a, b)
        next_s <- subtract(s0, multiply(division$quotient, s1))
        next_t <- subtract(t0, multiply(division$quotient, t1))
        a <- b
        b <- division$remainder
        s0 <- s1
        s1 <- next_s
        t0 <- t1
        t1 <- next_t
    }
    if (length(a)) {
        divisor <- leading(a)
        a <- divide_scalar(a, divisor)
        s0 <- divide_scalar(s0, divisor)
        t0 <- divide_scalar(t0, divisor)
    }
    list(a, s0, t0)
}
content <- function(a) {
    multiple <- as.bigz(1L)
    common <- as.bigz(0L)
    for (i in seq_along(a)) {
        d <- denominator(a[i])
        multiple <- (multiple * d) %/% gcd.bigz(multiple, d)
        common <- gcd.bigz(common, abs(numerator(a[i])))
    }
    if (leading(a) < ZERO) common <- -common
    as.bigq(common, multiple)
}
primitive <- function(a) divide_scalar(a, content(a))
squarefree <- function(a) if (degree(a) >= 1L) divide(a, polynomial_gcd(a, derivative(a)))$quotient else a

divisors <- function(value) {
    candidates <- seq_len(value)
    candidates[value %% candidates == 0L]
}
rational_roots <- function(a) {
    remaining <- primitive(a)
    zeros <- 0L
    while (remaining[1L] == ZERO) {
        remaining <- remaining[-1L]
        zeros <- zeros + 1L
    }
    numerator_limit <- as.integer(abs(remaining[1L]))
    denominator_limit <- as.integer(leading(remaining))
    keys <- integer()
    for (s in divisors(numerator_limit)) {
        for (t in divisors(denominator_limit)) {
            if (gcd.bigz(as.bigz(s), as.bigz(t)) != 1L) next
            key <- s * (denominator_limit %/% t)
            keys <- c(keys, -key, key)
        }
    }
    roots <- list()
    for (key in sort(keys, method = "radix")) {
        value <- as.bigq(key, denominator_limit)
        factor <- as.bigq(c(-numerator(value), denominator(value)))
        multiplicity <- 0L
        while (degree(remaining) >= 1L && evaluate(remaining, value) == ZERO) {
            remaining <- divide(remaining, factor)$quotient
            multiplicity <- multiplicity + 1L
        }
        if (multiplicity > 0L) roots[[length(roots) + 1L]] <- list(value = value, multiplicity = multiplicity, key = key)
    }
    if (zeros > 0L) roots[[length(roots) + 1L]] <- list(value = ZERO, multiplicity = zeros, key = 0L)
    if (length(roots)) roots <- roots[order(vapply(roots, function(root) root$key, integer(1L)), method = "radix")]
    list(roots = roots, remaining = remaining)
}
factor_text <- function(text, multiplicity) {
    paste0(" * ", text, if (multiplicity > 1L) paste0("^", multiplicity) else "")
}
factorization <- function(a, found) {
    result <- fraction(content(a))
    for (root in found$roots) {
        text <- if (root$value == ZERO) "x" else {
            factor <- as.bigq(c(-numerator(root$value), denominator(root$value)))
            paste0("(", notation(factor), ")")
        }
        result <- paste0(result, factor_text(text, root$multiplicity))
    }
    if (degree(found$remaining) >= 1L) result <- paste0(result, " * (", notation(found$remaining), ")")
    result
}
squarefree_factors <- function(a) {
    result <- fraction(content(a))
    if (degree(a) == 0L) return(result)
    normalized <- monic(a)
    common <- polynomial_gcd(normalized, derivative(normalized))
    remaining <- divide(normalized, common)$quotient
    multiplicity <- 1L
    while (degree(remaining) >= 1L) {
        shared <- polynomial_gcd(remaining, common)
        factor <- divide(remaining, shared)$quotient
        if (degree(factor) >= 1L) {
            text <- notation(primitive(factor))
            if (text != "x") text <- paste0("(", text, ")")
            result <- paste0(result, factor_text(text, multiplicity))
        }
        common <- divide(common, shared)$quotient
        remaining <- shared
        multiplicity <- multiplicity + 1L
    }
    result
}
sign_of <- function(value) if (value < ZERO) -1L else if (value > ZERO) 1L else 0L
sign_changes <- function(signs) {
    signs <- signs[signs != 0L]
    if (length(signs) < 2L) 0L else sum(signs[-1L] != signs[-length(signs)])
}
sturm_sequence <- function(a) {
    first <- squarefree(a)
    second <- derivative(first)
    sequence <- list(first)
    while (length(second)) {
        sequence[[length(sequence) + 1L]] <- second
        next_value <- -modulo(first, second)
        first <- second
        second <- next_value
    }
    sequence
}
bound <- function(value = ZERO, kind = 0L) list(value = value, kind = kind)
parse_bound <- function(word) {
    if (word == "-inf") bound(kind = -1L) else if (word == "inf") bound(kind = 1L) else bound(literal(word))
}
bound_text <- function(endpoint) {
    if (endpoint$kind < 0L) "-inf" else if (endpoint$kind > 0L) "inf" else fraction(endpoint$value)
}
bound_compare <- function(a, b) {
    if (a$kind != b$kind) return(if (a$kind < b$kind) -1L else 1L)
    if (a$kind != 0L) return(0L)
    if (a$value < b$value) -1L else if (a$value > b$value) 1L else 0L
}
variations <- function(sequence, endpoint) {
    signs <- vapply(sequence, function(a) {
        if (endpoint$kind == 0L) return(sign_of(evaluate(a, endpoint$value)))
        value <- sign_of(leading(a))
        if (endpoint$kind < 0L && degree(a) %% 2L) -value else value
    }, integer(1L))
    sign_changes(signs)
}
isolate <- function(a, precision) {
    sequence <- sturm_sequence(a)
    first <- sequence[[1L]]
    beta <- if (degree(first) == 0L) ONE else ONE + max(abs(first[-length(first)] / leading(first)))
    width <- as.bigq(1L, bitwShiftL(1L, precision))
    intervals <- character()
    count_roots <- function(low, high) variations(sequence, bound(low)) - variations(sequence, bound(high))
    examine <- function(low, high) {
        count <- count_roots(low, high)
        if (count >= 2L) {
            middle <- (low + high) / 2L
            examine(low, middle)
            examine(middle, high)
        } else if (count == 1L) {
            while (high - low > width) {
                middle <- (low + high) / 2L
                if (count_roots(low, middle) >= 1L) high <- middle else low <- middle
            }
            intervals <<- c(intervals, paste0("(", fraction(low), ", ", fraction(high), "]"))
        }
    }
    examine(-beta, beta)
    if (length(intervals)) paste(intervals, collapse = ", ") else "none"
}
resultant <- function(a, b) {
    result <- ONE
    while (degree(b) >= 1L) {
        remainder <- modulo(a, b)
        if (!length(remainder)) return(ZERO)
        result <- result * fraction_power(leading(b), degree(a) - degree(remainder))
        if ((degree(a) * degree(b)) %% 2L) result <- -result
        a <- b
        b <- remainder
    }
    result * fraction_power(b[1L], degree(a))
}
power_sums <- function(a, count) {
    d <- degree(a)
    normalized <- monic(a)
    sums <- rep(ZERO, count)
    for (j in seq_len(count)) {
        value <- if (j <= d) j * normalized[d - j + 1L] else ZERO
        for (i in seq_len(min(j - 1L, d))) value <- value + normalized[d - i + 1L] * sums[j - i]
        sums[j] <- -value
    }
    paste(vapply(seq_along(sums), function(i) fraction(sums[i]), character(1L)), collapse = ", ")
}
interpolate <- function(values) {
    count <- length(values) %/% 2L
    x <- values[seq.int(1L, length(values), by = 2L)]
    differences <- values[seq.int(2L, length(values), by = 2L)]
    for (j in seq_len(count)) {
        if (any(x[j] == x[seq_len(j - 1L)])) fail(paste("DUPLICATE X", fraction(x[j])))
    }
    for (j in seq_len(count - 1L)) {
        for (i in rev(seq.int(j + 1L, count))) {
            differences[i] <- (differences[i] - differences[i - 1L]) / (x[i] - x[i - j])
        }
    }
    result <- EMPTY
    for (i in rev(seq_len(count))) result <- add(multiply(result, linear(-x[i])), constant(differences[i]))
    result
}
special <- function(kind, count) {
    if (!kind %in% c("chebyshev", "chebyshev2", "legendre", "hermite", "laguerre")) fail(paste("UNKNOWN KIND", kind))
    degree_limit(count > 30L)
    previous <- ONE
    if (count == 0L) return(previous)
    current <- switch(kind, chebyshev = X, chebyshev2 = scale(X, as.bigq(2L)), legendre = X,
                      hermite = scale(X, as.bigq(2L)), laguerre = as.bigq(c(1L, -1L)))
    for (j in seq_len(count - 1L)) {
        if (kind %in% c("chebyshev", "chebyshev2", "hermite")) {
            factor <- if (kind == "hermite") 2L * j else 1L
            next_value <- subtract(multiply(scale(X, as.bigq(2L)), current), scale(previous, as.bigq(factor)))
        } else {
            factor <- if (kind == "legendre") linear(ZERO, as.bigq(2L * j + 1L)) else linear(as.bigq(2L * j + 1L), -ONE)
            next_value <- scale(subtract(multiply(factor, current), scale(previous, as.bigq(j))), as.bigq(1L, j + 1L))
        }
        previous <- current
        current <- next_value
    }
    current
}

node <- function(kind, ...) list(kind = kind, ...)
parse_definition <- function(source) {
    positions <- gregexpr("[0-9]+|[A-Z][A-Z0-9]*|[^ ]", source, perl = TRUE)[[1L]]
    words <- regmatches(source, list(positions))[[1L]]
    position <- 1L
    peek <- function() if (position <= length(words)) words[position] else ""
    syntax_error <- function() fail(paste("SYNTAX AT", if (position <= length(words)) positions[position] else "END"))
    take <- function() {
        word <- peek()
        position <<- position + 1L
        word
    }
    expect <- function(word) {
        if (peek() != word) syntax_error()
        take()
    }
    parse_primary <- function() {
        word <- peek()
        if (grepl("^[0-9]+$", word)) return(node("number", value = as.integer(take())))
        if (word == "x") {
            take()
            return(node("x"))
        }
        if (grepl("^[A-Z]", word)) {
            name <- take()
            count <- 0L
            while (peek() == "'") {
                take()
                count <- count + 1L
            }
            result <- node("name", name = name, count = count)
            if (peek() == "(") {
                take()
                argument <- parse_sum()
                expect(")")
                result <- node("call", left = result, right = argument)
            }
            return(result)
        }
        if (word == "(") {
            take()
            result <- parse_sum()
            expect(")")
            return(result)
        }
        syntax_error()
    }
    parse_factor <- function() {
        result <- parse_primary()
        if (peek() == "^") {
            take()
            if (!grepl("^[0-9]+$", peek())) syntax_error()
            result <- node("power", left = result, exponent = as.integer(take()))
        }
        result
    }
    parse_term <- function() {
        result <- parse_factor()
        repeat {
            word <- peek()
            if (word %in% c("*", "/")) {
                take()
            } else if (word == "x" || word == "(" || grepl("^[A-Z]", word)) {
                word <- "*"
            } else break
            right <- parse_factor()
            result <- node(word, left = result, right = right)
        }
        result
    }
    parse_sum <- function() {
        negative <- peek() == "-"
        if (negative) take()
        result <- parse_term()
        if (negative) result <- node("negate", left = result)
        while (peek() %in% c("+", "-")) {
            operation <- take()
            right <- parse_term()
            result <- node(operation, left = result, right = right)
        }
        result
    }
    result <- parse_sum()
    if (position <= length(words)) syntax_error()
    result
}

polynomials <- new.env(hash = TRUE, parent = emptyenv())
lookup <- function(name) {
    if (!exists(name, envir = polynomials, inherits = FALSE)) fail(paste("UNKNOWN", name))
    get(name, envir = polynomials, inherits = FALSE)
}
evaluate_node <- function(tree) {
    if (tree$kind == "number") return(constant(as.bigq(tree$value)))
    if (tree$kind == "x") return(X)
    if (tree$kind == "name") return(derivative(lookup(tree$name), tree$count))
    left <- evaluate_node(tree$left)
    if (tree$kind == "negate") return(-left)
    if (tree$kind == "power") {
        degree_limit(length(left) > 0L && degree(left) * tree$exponent > 30L)
        return(power(left, tree$exponent))
    }
    right <- evaluate_node(tree$right)
    if (tree$kind == "+") return(add(left, right))
    if (tree$kind == "-") return(subtract(left, right))
    if (tree$kind == "*") {
        product_limit(left, right)
        return(multiply(left, right))
    }
    if (tree$kind == "call") {
        composition_limit(left, right)
        return(compose(left, right))
    }
    if (!length(right)) fail("DIVISION BY ZERO")
    if (degree(right) >= 1L) fail("NONCONSTANT DIVISOR")
    divide_scalar(left, right[1L])
}

REFERENCES <- list(
    PRINT = 2L, DELETE = 2L, DEGREE = 2L, ADD = 3L:4L, SUB = 3L:4L, MUL = 3L:4L, POW = 3L,
    DIV = 4L:5L, GCD = 3L:4L, XGCD = 5L:6L, LCM = 3L:4L, INVMOD = 3L:4L, CRT = 3L:6L,
    MODPOW = c(3L, 5L), DERIV = 3L, INTEG = 3L, AREA = 2L, TANGENT = 3L, TAYLOR = 2L,
    COMPOSE = 3L:4L, EVAL = 2L, ROOTS = 2L, FACTOR = 2L, SQFREE = 2L, DESCARTES = 2L,
    STURM = 2L, ISOLATE = 2L, RESULTANT = 2L:3L, DISCRIM = 2L, POWERSUM = 2L
)

execute <- function(source) {
    words <- strsplit(source, " ", fixed = TRUE)[[1L]]
    command <- words[1L]
    name <- words[2L]
    pending <- list()
    output <- character()
    store <- function(destination, value) {
        pending[[length(pending) + 1L]] <<- list(name = destination, value = value)
        output <<- c(output, paste0(destination, " = ", notation(value)))
    }
    if (command == "DEF") {
        syntax <- parse_definition(substr(source, nchar(name) + 6L, nchar(source)))
        store(name, evaluate_node(syntax))
    } else {
        if ((command == "DIV" && words[2L] == words[3L]) ||
            (command == "XGCD" && anyDuplicated(words[2L:4L]))) fail("SAME NAME")
        operands <- lapply(REFERENCES[[command]], function(index) lookup(words[index]))
        a <- if (length(operands) >= 1L) operands[[1L]] else EMPTY
        b <- if (length(operands) >= 2L) operands[[2L]] else EMPTY
        c <- if (length(operands) >= 3L) operands[[3L]] else EMPTY
        d <- if (length(operands) >= 4L) operands[[4L]] else EMPTY
        literal_words <- switch(command, AREA = words[3L:4L], STURM = words[3L:4L], TANGENT = words[4L],
                                TAYLOR = words[3L], EVAL = words[-(1L:2L)], INTERP = words[-(1L:2L)], character())
        if (command == "STURM") {
            endpoints <- lapply(literal_words, parse_bound)
        } else values <- if (length(literal_words)) c_bigq(lapply(literal_words, literal)) else EMPTY
        switch(command,
            PRINT = { output <- paste0(name, " = ", notation(a)) },
            DELETE = {
                rm(list = name, envir = polynomials)
                output <- paste("deleted", name)
            },
            LIST = {
                names <- sort(ls(polynomials, all.names = TRUE), method = "radix")
                output <- if (length(names)) vapply(names, function(key) paste0(key, " = ", notation(lookup(key))), character(1L)) else "no polynomials"
            },
            DEGREE = { output <- paste0("deg(", name, ") = ", if (length(a)) degree(a) else "-inf") },
            ADD = { store(name, add(a, b)) },
            SUB = { store(name, subtract(a, b)) },
            MUL = { product_limit(a, b); store(name, multiply(a, b)) },
            POW = {
                exponent <- as.integer(words[4L])
                degree_limit(length(a) > 0L && degree(a) * exponent > 30L)
                store(name, power(a, exponent))
            },
            DIV = {
                if (!length(b)) fail("DIVISION BY ZERO")
                division <- divide(a, b)
                store(name, division$quotient)
                store(words[3L], division$remainder)
            },
            GCD = { store(name, polynomial_gcd(a, b)) },
            XGCD = {
                result <- extended_gcd(a, b)
                for (i in 1L:3L) store(words[i + 1L], result[[i]])
            },
            LCM = {
                if (!length(a) || !length(b)) {
                    store(name, EMPTY)
                } else {
                    common <- polynomial_gcd(a, b)
                    degree_limit(degree(a) + degree(b) - degree(common) > 30L)
                    store(name, monic(multiply(divide(a, common)$quotient, b)))
                }
            },
            INVMOD = {
                if (!length(b)) fail("DIVISION BY ZERO")
                if (degree(b) == 0L) fail("DEGREE TOO LOW")
                result <- extended_gcd(a, b)
                if (!is_one(result[[1L]])) fail("NOT COPRIME")
                store(name, modulo(result[[2L]], b))
            },
            CRT = {
                if (!length(b) || !length(d)) fail("DIVISION BY ZERO")
                degree_limit(degree(b) + degree(d) > 30L)
                result <- extended_gcd(b, d)
                if (!is_one(result[[1L]])) fail("NOT COPRIME")
                first <- modulo(a, b)
                second <- modulo(c, d)
                correction <- modulo(multiply(subtract(second, first), result[[2L]]), d)
                store(name, add(first, multiply(b, correction)))
            },
            MODPOW = {
                if (!length(b)) fail("DIVISION BY ZERO")
                degree_limit(2L * degree(b) - 2L > 30L)
                result <- modulo(ONE, b)
                base <- modulo(a, b)
                exponent <- as.integer(words[4L])
                while (exponent > 0L) {
                    if (exponent %% 2L) result <- modulo(multiply(result, base), b)
                    exponent <- exponent %/% 2L
                    if (exponent > 0L) base <- modulo(multiply(base, base), b)
                }
                store(name, result)
            },
            DERIV = { store(name, derivative(a, as.integer(words[4L]))) },
            INTEG = {
                degree_limit(length(a) > 0L && degree(a) + 1L > 30L)
                store(name, integral(a))
            },
            AREA = {
                antiderivative <- integral(a)
                value <- evaluate(antiderivative, values[2L]) - evaluate(antiderivative, values[1L])
                output <- paste0("integral(", name, ", ", fraction(values[1L]), ", ", fraction(values[2L]), ") = ", fraction(value))
            },
            TANGENT = {
                point <- values[1L]
                value <- evaluate(a, point)
                slope <- evaluate(derivative(a), point)
                store(name, linear(value - slope * point, slope))
            },
            TAYLOR = {
                point <- values[1L]
                variable <- if (point == ZERO) "x" else if (point > ZERO) paste0("(x - ", fraction(point), ")") else paste0("(x + ", fraction(-point), ")")
                output <- paste0("taylor(", name, ", ", fraction(point), ") = ", notation(compose(a, linear(point)), variable))
            },
            COMPOSE = { composition_limit(a, b); store(name, compose(a, b)) },
            EVAL = {
                output <- vapply(seq_along(values), function(i) paste0(name, "(", fraction(values[i]), ") = ", fraction(evaluate(a, values[i]))), character(1L))
            },
            ROOTS = {
                nonzero(a)
                roots <- rational_roots(a)$roots
                text <- if (length(roots)) paste(vapply(roots, function(root) paste0(fraction(root$value), " (", root$multiplicity, ")"), character(1L)), collapse = ", ") else "none"
                output <- paste0("roots(", name, ") = ", text)
            },
            FACTOR = {
                nonzero(a)
                found <- rational_roots(a)
                output <- paste0("factor(", name, ") = ", factorization(a, found))
            },
            SQFREE = { nonzero(a); output <- paste0("sqfree(", name, ") = ", squarefree_factors(a)) },
            DESCARTES = {
                nonzero(a)
                signs <- vapply(seq_along(a), function(i) sign_of(a[i]), integer(1L))
                positive <- sign_changes(rev(signs))
                signs[seq_along(signs) %% 2L == 0L] <- -signs[seq_along(signs) %% 2L == 0L]
                output <- paste0("descartes(", name, ") = positive ", positive, ", negative ", sign_changes(rev(signs)))
            },
            STURM = {
                nonzero(a)
                if (bound_compare(endpoints[[1L]], endpoints[[2L]]) >= 0L) fail("BAD INTERVAL")
                sequence <- sturm_sequence(a)
                count <- variations(sequence, endpoints[[1L]]) - variations(sequence, endpoints[[2L]])
                output <- paste0("sturm(", name, ", ", bound_text(endpoints[[1L]]), ", ", bound_text(endpoints[[2L]]), ") = ", count)
            },
            ISOLATE = {
                nonzero(a)
                precision <- as.integer(words[3L])
                output <- paste0("isolate(", name, ", ", precision, ") = ", isolate(a, precision))
            },
            RESULTANT = {
                nonzero(a)
                nonzero(b)
                output <- paste0("res(", name, ", ", words[3L], ") = ", fraction(resultant(a, b)))
            },
            DISCRIM = {
                nonzero(a)
                if (degree(a) == 0L) fail("DEGREE TOO LOW")
                value <- resultant(a, derivative(a)) / leading(a)
                if (((degree(a) * (degree(a) - 1L)) %/% 2L) %% 2L) value <- -value
                output <- paste0("disc(", name, ") = ", fraction(value))
            },
            POWERSUM = {
                nonzero(a)
                if (degree(a) == 0L) fail("DEGREE TOO LOW")
                output <- paste0("powersum(", name, ") = ", power_sums(a, as.integer(words[3L])))
            },
            INTERP = { store(name, interpolate(values)) },
            SPECIAL = { store(name, special(words[3L], as.integer(words[4L]))) }
        )
    }
    for (entry in pending) assign(entry$name, entry$value, envir = polynomials)
    output
}

input <- readLines(file("stdin"), warn = FALSE)
for (i in seq_len(as.integer(input[1L]))) {
    output <- tryCatch(execute(input[i + 1L]), command_error = function(error) paste("ERROR", conditionMessage(error)))
    cat(paste(output, collapse = "\n"), "\n", sep = "")
}
