suppressPackageStartupMessages(library(gmp))

INVALID <- 1L
DIVBYZERO <- 2L
OVERFLOW <- 4L
UNDERFLOW <- 8L
INEXACT <- 16L
MODES <- c("RNE", "RNA", "RTZ", "RUP", "RDN")
TYPES <- list(I8 = as.bigz(c("-128", "127")), U8 = as.bigz(c("0", "255")),
              I16 = as.bigz(c("-32768", "32767")), U16 = as.bigz(c("0", "65535")),
              I32 = as.bigz(c("-2147483648", "2147483647")), U32 = as.bigz(c("0", "4294967295")))
ZERO <- as.bigz(0L)
ONE <- as.bigz(1L)

fail <- function(message) stop(structure(list(message = message, call = NULL), class = c("command_error", "error", "condition")))
mode_word <- function(words, index) {
    mode <- if (index <= length(words)) words[index] else "RNE"
    if (!mode %in% MODES) fail(paste("BAD MODE", mode))
    mode
}
flags_text <- function(flags) {
    names <- c("invalid", "divbyzero", "overflow", "underflow", "inexact")
    raised <- names[bitwAnd(flags, c(INVALID, DIVBYZERO, OVERFLOW, UNDERFLOW, INEXACT)) != 0L]
    paste0("flags=", if (length(raised)) paste(raised, collapse = ",") else "none")
}
combine_flags <- function(...) Reduce(bitwOr, list(...), init = 0L)
result <- function(pattern, flags = 0L) list(pattern = pattern, flags = flags)
small_integer <- function(value) as.integer(as.character(value))
power_two <- function(exponent) as.bigz(2L)^exponent
decimal_integer <- function(word) {
    digits <- sub("^0+", "", word)
    as.bigz(if (nzchar(digits)) digits else "0")
}

exact <- function(n = ZERO, e = 0L, d = ONE, negative = FALSE) {
    list(n = as.bigz(n), e = e, d = as.bigz(d), negative = negative)
}
negated <- function(value) {
    value$negative <- !value$negative
    value
}
scaled <- function(n, d, exponent) {
    if (exponent >= 0L) list(n = n * power_two(exponent), d = d)
    else list(n = n, d = d * power_two(-exponent))
}
log_two_floor <- function(value) {
    exponent <- sizeinbase(value$n, 2L) - sizeinbase(value$d, 2L) + value$e
    ratio <- scaled(value$n, value$d, value$e - exponent)
    exponent - if (ratio$n < ratio$d) 1L else 0L
}
integer_sqrt <- function(value) {
    if (value == 0L) return(ZERO)
    root <- power_two((sizeinbase(value, 2L) + 1L) %/% 2L)
    repeat {
        next_root <- (root + value %/% root) %/% 2L
        if (next_root >= root) return(root)
        root <- next_root
    }
}
fraction_text <- function(value) {
    if (value$n == 0L) return("0")
    ratio <- scaled(value$n, value$d, value$e)
    divisor <- gcd.bigz(ratio$n, ratio$d)
    n <- ratio$n %/% divisor
    d <- ratio$d %/% divisor
    paste0(if (value$negative) "-" else "", as.character(n), if (d == 1L) "" else paste0("/", as.character(d)))
}
decimal_text <- function(value, keep_zero_sign = FALSE) {
    ratio <- scaled(value$n, value$d, value$e)
    text <- as.character(ratio$n %/% ratio$d)
    remainder <- ratio$n %% ratio$d
    if (remainder != 0L) {
        text <- paste0(text, ".")
        while (remainder != 0L) {
            remainder <- remainder * 10L
            text <- paste0(text, as.character(remainder %/% ratio$d))
            remainder <- remainder %% ratio$d
        }
    }
    paste0(if (value$negative && (value$n != 0L || keep_zero_sign)) "-" else "", text)
}
exact_product <- function(a, b) exact(a$n * b$n, a$e + b$e, a$d * b$d, xor(a$negative, b$negative))
exact_sum <- function(terms, mode) {
    nonzero <- terms[vapply(terms, function(term) term$n != 0L, logical(1L))]
    if (!length(nonzero)) {
        signs <- vapply(terms, function(term) term$negative, logical(1L))
        return(exact(negative = if (all(signs == signs[1L])) signs[1L] else mode == "RDN"))
    }
    exponent <- min(vapply(nonzero, function(term) term$e, integer(1L)))
    aligned <- c_bigz(lapply(nonzero, function(term) {
        value <- term$n * power_two(term$e - exponent)
        if (term$negative) -value else value
    }))
    total <- sum(aligned)
    exact(abs(total), exponent, negative = total < 0L || (total == 0L && mode == "RDN"))
}

increment <- function(mode, negative, integer, inexact, halfway) {
    if (!inexact) return(FALSE)
    switch(mode,
           RNE = halfway > 0L || (halfway == 0L && integer %% 2L == 1L),
           RNA = halfway >= 0L, RTZ = FALSE, RUP = !negative, RDN = negative)
}
rounded_units <- function(value, exponent, mode) {
    ratio <- scaled(value$n, value$d, value$e - exponent)
    integer <- ratio$n %/% ratio$d
    remainder <- ratio$n %% ratio$d
    inexact <- remainder != 0L
    if (increment(mode, value$negative, integer, inexact, 2L * remainder - ratio$d)) integer <- integer + 1L
    list(value = integer, inexact = inexact)
}
rounded_sqrt_units <- function(value, exponent, mode) {
    ratio <- scaled(value$n, value$d, value$e - 2L * exponent)
    integer <- integer_sqrt(ratio$n %/% ratio$d)
    inexact <- integer * integer * ratio$d != ratio$n
    midpoint <- 2L * integer + 1L
    halfway <- 4L * ratio$n - ratio$d * midpoint * midpoint
    if (increment(mode, FALSE, integer, inexact, halfway)) integer <- integer + 1L
    list(value = integer, inexact = inexact)
}

new_format <- function(name, e, m) {
    bias <- bitwShiftL(1L, e - 1L) - 1L
    hidden <- bitwShiftL(1L, m)
    exponent_mask <- bitwShiftL(1L, e) - 1L
    infinity <- exponent_mask * hidden
    list(name = name, e = e, m = m, w = 1L + e + m, bias = bias, emin = 1L - bias,
         emax = bias, hidden = hidden, exponent_mask = exponent_mask,
         sign_bit = bitwShiftL(1L, e + m), infinity = infinity,
         nan = infinity + hidden %/% 2L, maximum = infinity - 1L)
}
fields <- function(format, pattern) {
    exponent <- pattern %/% format$hidden %% (format$exponent_mask + 1L)
    list(negative = bitwAnd(pattern, format$sign_bit) != 0L,
         exponent = exponent, fraction = pattern %% format$hidden,
         q = (if (exponent == 0L) format$emin else exponent - format$bias) - format$m)
}
is_nan <- function(format, pattern) {
    field <- fields(format, pattern)
    field$exponent == format$exponent_mask && field$fraction != 0L
}
is_signaling <- function(format, pattern) is_nan(format, pattern) && fields(format, pattern)$fraction < format$hidden %/% 2L
is_infinite <- function(format, pattern) bitwAnd(pattern, format$sign_bit - 1L) == format$infinity
is_zero <- function(format, pattern) bitwAnd(pattern, format$sign_bit - 1L) == 0L
is_finite <- function(format, pattern) fields(format, pattern)$exponent != format$exponent_mask
zero_pattern <- function(format, negative) if (negative) format$sign_bit else 0L
infinity_pattern <- function(format, negative) zero_pattern(format, negative) + format$infinity
flip <- function(format, pattern) bitwXor(pattern, format$sign_bit)
pattern_exact <- function(format, pattern) {
    field <- fields(format, pattern)
    n <- field$fraction + if (field$exponent == 0L) 0L else format$hidden
    exact(n, field$q, negative = field$negative)
}
binary_text <- function(value, width) {
    text <- as.character(as.bigz(value), b = 2L)
    paste0(strrep("0", width - nchar(text)), text)
}
bits_text <- function(format, pattern) {
    field <- fields(format, pattern)
    paste(as.integer(field$negative), binary_text(field$exponent, format$e), binary_text(field$fraction, format$m), sep = "|")
}
hex_text <- function(format, pattern) sprintf("0x%0*X", (format$w + 3L) %/% 4L, pattern)
value_text <- function(format, pattern) {
    if (is_nan(format, pattern)) return("nan")
    if (is_infinite(format, pattern)) return(if (fields(format, pattern)$negative) "-inf" else "inf")
    decimal_text(pattern_exact(format, pattern), TRUE)
}
pattern_text <- function(format, pattern) paste(bits_text(format, pattern), hex_text(format, pattern), value_text(format, pattern))
result_text <- function(format, value) paste(pattern_text(format, value$pattern), flags_text(value$flags))

overflow_result <- function(format, negative, mode) {
    infinite <- mode %in% c("RNE", "RNA") || (mode == "RUP" && !negative) || (mode == "RDN" && negative)
    result(zero_pattern(format, negative) + if (infinite) format$infinity else format$maximum, bitwOr(OVERFLOW, INEXACT))
}
finish_round <- function(format, negative, order, exponent, units, unbounded, mode) {
    n <- units$value
    if (n == 2L * format$hidden) {
        n <- as.bigz(format$hidden)
        exponent <- exponent + 1L
    }
    if (exponent > format$emax - format$m) return(overflow_result(format, negative, mode))
    magnitude <- if (n >= format$hidden) (exponent + format$m + format$bias) * format$hidden + small_integer(n - format$hidden) else small_integer(n)
    flags <- if (units$inexact) INEXACT else 0L
    if (units$inexact && order < format$emin && (order < format$emin - 1L || unbounded()$value < 2L * format$hidden)) {
        flags <- bitwOr(flags, UNDERFLOW)
    }
    result(zero_pattern(format, negative) + magnitude, flags)
}
round_exact <- function(format, value, mode) {
    if (value$n == 0L) return(result(zero_pattern(format, value$negative)))
    order <- log_two_floor(value)
    if (order > format$emax) return(overflow_result(format, value$negative, mode))
    exponent <- max(order, format$emin) - format$m
    finish_round(format, value$negative, order, exponent, rounded_units(value, exponent, mode),
                 function() rounded_units(value, order - format$m, mode), mode)
}
round_sqrt <- function(format, value, mode) {
    order <- log_two_floor(value) %/% 2L
    exponent <- max(order, format$emin) - format$m
    finish_round(format, FALSE, order, exponent, rounded_sqrt_units(value, exponent, mode),
                 function() rounded_sqrt_units(value, order - format$m, mode), mode)
}

parse_real <- function(word) {
    if (word %in% c("inf", "-inf", "nan")) return(list(special = word))
    if (startsWith(word, "0b") || startsWith(word, "0x")) fail(paste("BAD OPERAND", word))
    negative <- startsWith(word, "-")
    body <- if (negative) substring(word, 2L) else word
    if (grepl("/", body, fixed = TRUE)) {
        parts <- strsplit(body, "/", fixed = TRUE)[[1L]]
        numerator <- decimal_integer(parts[1L])
        denominator <- decimal_integer(parts[2L])
        if (denominator == 0L) fail(paste("BAD OPERAND", word))
        return(list(exact = exact(numerator, d = denominator, negative = negative)))
    }
    parts <- strsplit(body, ".", fixed = TRUE)[[1L]]
    fraction <- if (length(parts) == 2L) parts[2L] else ""
    list(exact = exact(decimal_integer(paste0(parts[1L], fraction)), d = as.bigz(10L)^nchar(fraction), negative = negative))
}
encoded <- function(format, real, mode) {
    if (!is.null(real$special)) return(result(switch(real$special, nan = format$nan, inf = format$infinity, "-inf" = infinity_pattern(format, TRUE))))
    round_exact(format, real$exact, mode)
}
operand <- function(format, word) {
    if (startsWith(word, "0b")) {
        if (nchar(word) - 2L != format$w) fail(paste("BAD OPERAND", word))
        return(small_integer(as.bigz(word)))
    }
    if (startsWith(word, "0x")) {
        pattern <- small_integer(as.bigz(word))
        if (nchar(word) - 2L != (format$w + 3L) %/% 4L || pattern >= bitwShiftL(1L, format$w)) fail(paste("BAD OPERAND", word))
        return(pattern)
    }
    encoded(format, parse_real(word), "RNE")$pattern
}

operation <- function(format, command, inputs, mode) {
    if (command == "SUB") return(operation(format, "ADD", c(inputs[1L], flip(format, inputs[2L])), mode))
    if (any(vapply(inputs, function(pattern) is_nan(format, pattern), logical(1L)))) {
        return(result(format$nan, if (any(vapply(inputs, function(pattern) is_signaling(format, pattern), logical(1L)))) INVALID else 0L))
    }
    invalid <- function() result(format$nan, INVALID)
    a <- inputs[1L]
    negative <- fields(format, a)$negative
    if (command == "SQRT") {
        if (is_zero(format, a)) return(result(a))
        if (negative) return(invalid())
        if (is_infinite(format, a)) return(result(a))
        return(round_sqrt(format, pattern_exact(format, a), mode))
    }
    b <- inputs[2L]
    sigma <- xor(negative, fields(format, b)$negative)
    if (command == "ADD") {
        if (is_infinite(format, a) && is_infinite(format, b) && sigma) return(invalid())
        if (is_infinite(format, a)) return(result(a))
        if (is_infinite(format, b)) return(result(b))
        return(round_exact(format, exact_sum(list(pattern_exact(format, a), pattern_exact(format, b)), mode), mode))
    }
    if (command == "MUL") {
        if (is_infinite(format, a) || is_infinite(format, b)) {
            return(if (is_zero(format, a) || is_zero(format, b)) invalid() else result(infinity_pattern(format, sigma)))
        }
        if (is_zero(format, a) || is_zero(format, b)) return(result(zero_pattern(format, sigma)))
        return(round_exact(format, exact_product(pattern_exact(format, a), pattern_exact(format, b)), mode))
    }
    if (command == "DIV") {
        if (is_infinite(format, a)) return(if (is_infinite(format, b)) invalid() else result(infinity_pattern(format, sigma)))
        if (is_infinite(format, b)) return(result(zero_pattern(format, sigma)))
        if (is_zero(format, b)) return(if (is_zero(format, a)) invalid() else result(infinity_pattern(format, sigma), DIVBYZERO))
        if (is_zero(format, a)) return(result(zero_pattern(format, sigma)))
        x <- pattern_exact(format, a)
        y <- pattern_exact(format, b)
        return(round_exact(format, exact(x$n * y$d, x$e - y$e, x$d * y$n, sigma), mode))
    }
    c <- inputs[3L]
    if (is_infinite(format, a) || is_infinite(format, b)) {
        if (is_zero(format, a) || is_zero(format, b) || (is_infinite(format, c) && fields(format, c)$negative != sigma)) return(invalid())
        return(result(infinity_pattern(format, sigma)))
    }
    if (is_infinite(format, c)) return(result(c))
    terms <- list(exact_product(pattern_exact(format, a), pattern_exact(format, b)), pattern_exact(format, c))
    round_exact(format, exact_sum(terms, mode), mode)
}
next_up <- function(format, pattern) {
    if (pattern == format$infinity) return(pattern)
    if (is_zero(format, pattern)) return(1L)
    pattern + if (fields(format, pattern)$negative) -1L else 1L
}
difference_text <- function(format, pattern, value) {
    if (!is_finite(format, pattern)) return(value_text(format, pattern))
    fraction_text(exact_sum(list(pattern_exact(format, pattern), negated(value)), "RNE"))
}
relation <- function(a, b) if (a < b) "LT" else if (a > b) "GT" else "EQ"

summation <- function(command, format, mode, patterns) {
    if (any(!vapply(patterns, function(pattern) is_finite(format, pattern), logical(1L)))) fail("NOT FINITE")
    output <- paste(command, format$name, mode, paste0("count=", length(patterns)))
    current <- patterns[1L]
    compensation <- 0L
    flags <- 0L
    for (index in seq_along(patterns)[-1L]) {
        if (command == "SUM") {
            added <- operation(format, "ADD", c(current, patterns[index]), mode)
            current <- added$pattern
            flags <- bitwOr(flags, added$flags)
            output <- c(output, paste("PARTIAL", index, result_text(format, added)))
        } else {
            y <- operation(format, "SUB", c(patterns[index], compensation), mode)
            t <- operation(format, "ADD", c(current, y$pattern), mode)
            d <- operation(format, "SUB", c(t$pattern, current), mode)
            correction <- operation(format, "SUB", c(d$pattern, y$pattern), mode)
            current <- t$pattern
            compensation <- correction$pattern
            step_flags <- combine_flags(y$flags, t$flags, d$flags, correction$flags)
            flags <- bitwOr(flags, step_flags)
            output <- c(output, paste("KSTEP", index, paste0("sum=", value_text(format, current)),
                                      paste0("comp=", value_text(format, compensation)), flags_text(step_flags)))
        }
    }
    value <- exact_sum(lapply(patterns, function(pattern) pattern_exact(format, pattern)), mode)
    c(output, paste("RESULT", result_text(format, result(current, flags))),
      paste("EXACT", decimal_text(value)), paste("ROUNDED", result_text(format, round_exact(format, value, mode))),
      paste("DIFF", difference_text(format, current, value)))
}
dot_product <- function(format, mode, a, b) {
    if (length(a) != length(b)) fail("LENGTH MISMATCH")
    if (any(!vapply(c(a, b), function(pattern) is_finite(format, pattern), logical(1L)))) fail("NOT FINITE")
    naive <- operation(format, "MUL", c(a[1L], b[1L]), mode)
    chained <- naive
    for (index in seq_along(a)[-1L]) {
        product <- operation(format, "MUL", c(a[index], b[index]), mode)
        added <- operation(format, "ADD", c(naive$pattern, product$pattern), mode)
        naive <- result(added$pattern, combine_flags(naive$flags, product$flags, added$flags))
        fused <- operation(format, "FMA", c(a[index], b[index], chained$pattern), mode)
        chained <- result(fused$pattern, bitwOr(chained$flags, fused$flags))
    }
    terms <- lapply(seq_along(a), function(index) exact_product(pattern_exact(format, a[index]), pattern_exact(format, b[index])))
    value <- exact_sum(terms, mode)
    c(paste("DOT", format$name, mode, paste0("n=", length(a))),
      paste("NAIVE", result_text(format, naive)), paste("CHAINED", result_text(format, chained)),
      paste("EXACT", decimal_text(value)), paste("FUSED", result_text(format, round_exact(format, value, mode))),
      paste("DIFF", paste0("naive=", difference_text(format, naive$pattern, value)),
            paste0("chained=", difference_text(format, chained$pattern, value))))
}
table_lines <- function(format) {
    if (format$w > 8L) fail("TABLE TOO LARGE")
    count <- format$infinity
    entries <- vapply(seq_len(count) - 1L, function(pattern) {
        gap <- if (pattern == count - 1L) "-" else decimal_text(exact_sum(list(pattern_exact(format, pattern + 1L), negated(pattern_exact(format, pattern))), "RNE"))
        paste("ENTRY", pattern, pattern_text(format, pattern), paste0("gap=", gap))
    }, character(1L))
    c(paste("TABLE", format$name, paste0("count=", count)), entries,
      paste("MAX", pattern_text(format, format$maximum)), paste("MINNORMAL", pattern_text(format, format$hidden)),
      paste("MINSUBNORMAL", pattern_text(format, 1L)), paste("EPSILON", decimal_text(exact(ONE, -format$m))),
      paste("PATTERNS", paste0("finite=", 2L * count), "infinite=2", paste0("nan=", 2L * (format$hidden - 1L)),
            paste0("total=", bitwShiftL(1L, format$w))))
}

formats <- list2env(list(HALF = new_format("HALF", 5L, 10L), E5M2 = new_format("E5M2", 5L, 2L),
                         E4M3 = new_format("E4M3", 4L, 3L)), parent = emptyenv())
format_named <- function(name) {
    if (!exists(name, envir = formats, inherits = FALSE)) fail(paste("UNKNOWN FORMAT", name))
    formats[[name]]
}

run_command <- function(line) {
    words <- strsplit(line, " ", fixed = TRUE)[[1L]]
    command <- words[1L]
    if (command == "FORMAT") {
        name <- words[2L]
        e <- as.integer(words[3L])
        m <- as.integer(words[4L])
        if (exists(name, envir = formats, inherits = FALSE)) fail(paste("FORMAT EXISTS", name))
        if (e < 2L || e > 5L || m < 1L || m > 10L) fail("BAD FORMAT")
        format <- new_format(name, e, m)
        formats[[name]] <- format
        return(paste("FORMAT", name, paste0("e=", e), paste0("m=", m), paste0("bits=", format$w),
                     paste0("bias=", format$bias), paste0("emin=", format$emin), paste0("emax=", format$emax)))
    }
    format <- format_named(words[2L])
    name <- format$name
    if (command == "ENCODE") {
        real <- parse_real(words[3L])
        mode <- mode_word(words, 4L)
        value <- if (is.null(real$special)) fraction_text(real$exact) else real$special
        return(paste("ENCODE", name, mode, value, result_text(format, encoded(format, real, mode))))
    }
    if (command == "CONVERT") {
        target <- format_named(words[3L])
        a <- operand(format, words[4L])
        mode <- mode_word(words, 5L)
        converted <- if (is_nan(format, a)) result(target$nan, if (is_signaling(format, a)) INVALID else 0L)
                     else if (is_infinite(format, a)) result(infinity_pattern(target, fields(format, a)$negative))
                     else round_exact(target, pattern_exact(format, a), mode)
        return(paste("CONVERT", name, target$name, mode, result_text(target, converted)))
    }
    if (command %in% c("SUM", "KAHAN", "DOT")) {
        mode <- mode_word(words, 3L)
        if (command == "DOT") {
            separator <- match("|", words)
            a <- vapply(words[seq.int(4L, separator - 1L)], function(word) operand(format, word), integer(1L))
            b <- vapply(words[seq.int(separator + 1L, length(words))], function(word) operand(format, word), integer(1L))
            return(dot_product(format, mode, a, b))
        }
        patterns <- vapply(words[-seq_len(3L)], function(word) operand(format, word), integer(1L))
        return(summation(command, format, mode, patterns))
    }
    if (command == "TABLE") return(table_lines(format))
    if (command %in% c("ADD", "SUB", "MUL", "DIV", "SQRT", "FMA")) {
        count <- if (command == "SQRT") 1L else if (command == "FMA") 3L else 2L
        patterns <- vapply(words[seq.int(3L, 2L + count)], function(word) operand(format, word), integer(1L))
        mode <- mode_word(words, 3L + count)
        return(paste(command, name, mode, result_text(format, operation(format, command, patterns, mode))))
    }
    a <- operand(format, words[3L])
    field <- fields(format, a)
    if (command == "DECODE") {
        classification <- if (is_nan(format, a)) if (is_signaling(format, a)) "snan" else "qnan"
                          else if (is_infinite(format, a)) "infinity" else if (is_zero(format, a)) "zero"
                          else if (field$exponent == 0L) "subnormal" else "normal"
        header <- paste("DECODE", name, bits_text(format, a), hex_text(format, a), classification, paste0("sign=", as.integer(field$negative)))
        description <- paste("FIELDS", paste0("exponent=", field$exponent), paste0("fraction=", field$fraction))
        if (is_finite(format, a)) {
            description <- paste(description, paste0("unbiased=", field$q + format$m),
                                 paste0("significand=", if (field$exponent == 0L) "0" else "1", ".", binary_text(field$fraction, format$m)))
            return(c(header, description, paste("VALUE", fraction_text(pattern_exact(format, a)), value_text(format, a))))
        }
        if (is_nan(format, a)) description <- paste(description, paste0("payload=", field$fraction %% (format$hidden %/% 2L)))
        return(c(header, description))
    }
    if (command == "COMPARE") {
        b <- operand(format, words[4L])
        key <- function(pattern) if (fields(format, pattern)$negative) -(pattern - format$sign_bit) - 1L else pattern
        total <- relation(key(a), key(b))
        numeric <- if (is_nan(format, a) || is_nan(format, b)) "UN" else if (is_zero(format, a) && is_zero(format, b)) "EQ" else total
        flags <- if (is_signaling(format, a) || is_signaling(format, b)) INVALID else 0L
        return(paste("COMPARE", name, hex_text(format, a), hex_text(format, b), numeric, paste0("total=", total), flags_text(flags)))
    }
    if (command == "TOINT") {
        type <- words[4L]
        if (!type %in% names(TYPES)) fail(paste("BAD TYPE", type))
        mode <- mode_word(words, 5L)
        prefix <- paste("TOINT", name, type, mode)
        if (!is_finite(format, a)) return(paste(prefix, "invalid flags=invalid"))
        units <- rounded_units(pattern_exact(format, a), 0L, mode)
        integer <- if (field$negative) -units$value else units$value
        bounds <- TYPES[[type]]
        if (integer < bounds[1L] || integer > bounds[2L]) return(paste(prefix, "invalid flags=invalid"))
        return(paste(prefix, as.character(integer), flags_text(if (units$inexact) INEXACT else 0L)))
    }
    value <- if (is_nan(format, a)) result(format$nan, if (is_signaling(format, a)) INVALID else 0L)
             else if (command == "NEXTUP") result(next_up(format, a))
             else if (command == "NEXTDOWN") result(flip(format, next_up(format, flip(format, a))))
             else result(if (is_infinite(format, a)) format$infinity else round_exact(format, exact(ONE, field$q), "RNE")$pattern)
    paste(command, name, result_text(format, value))
}

input <- readLines(file("stdin"), warn = FALSE)
for (index in seq_len(as.integer(input[1L]))) {
    output <- tryCatch(run_command(input[index + 1L]), command_error = function(error) paste("ERROR", conditionMessage(error)))
    cat(paste(output, collapse = "\n"), "\n", sep = "")
}
