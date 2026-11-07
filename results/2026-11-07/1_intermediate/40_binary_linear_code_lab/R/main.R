suppressPackageStartupMessages(library(gmp))

fail <- function(message) {
    stop(structure(list(message = message, call = NULL), class = c("command_error", "error", "condition")))
}
format_spec <- function(types, minimum, maximum = minimum) list(types = types, minimum = minimum, maximum = maximum)
FORMATS <- list(
    GEN = format_spec("NV", 2L, 25L), PCHECK = format_spec("NV", 2L, 25L),
    HAMMING = format_spec("NI", 2L), SIMPLEX = format_spec("NI", 2L),
    REPETITION = format_spec("NI", 2L), PARITY = format_spec("NI", 2L),
    RM = format_spec("NII", 3L), CYCLIC = format_spec("NIV", 3L),
    DUAL = format_spec("NA", 2L), EXTEND = format_spec("NA", 2L),
    PUNCTURE = format_spec("NAI", 3L), SHORTEN = format_spec("NAI", 3L),
    AUGMENT = format_spec("NA", 2L), EXPURGATE = format_spec("NA", 2L),
    PERMUTE = format_spec("NAI", 3L, 26L), DIRECTSUM = format_spec("NAB", 3L),
    UUV = format_spec("NAB", 3L), PRODUCT = format_spec("NAB", 3L),
    LIST = format_spec("", 0L), DELETE = format_spec("A", 1L),
    SHOW = format_spec("A", 1L), INFO = format_spec("A", 1L), SYSTEMATIC = format_spec("A", 1L),
    WEIGHTS = format_spec("A", 1L), COVERING = format_spec("A", 1L), BURST = format_spec("A", 1L),
    TRELLIS = format_spec("A", 1L), STDARRAY = format_spec("A", 1L), EQUAL = format_spec("AB", 2L),
    ENCODE = format_spec("AV", 2L), SYNDROME = format_spec("AV", 2L), DECODE = format_spec("AV", 2L),
    BOUNDED = format_spec("AIV", 3L), COSET = format_spec("AV", 2L), ERASURE = format_spec("AX", 2L),
    INTERLEAVE = format_spec("AIIV", 4L, 11L), CRC = format_spec("VV", 2L), CRCCHECK = format_spec("VV", 2L),
    FACTOR = format_spec("I", 1L), MACWILLIAMS = format_spec("II", 2L, 26L), BOUNDS = format_spec("II", 2L)
)
DEFINITIONS <- names(FORMATS)[seq_len(18L)]
INDEPENDENT <- c("CRC", "CRCCHECK", "FACTOR", "MACWILLIAMS", "BOUNDS")
valid_word <- function(text, kind) {
    pattern <- if (kind %in% c("N", "A", "B")) "^[A-Za-z][A-Za-z0-9]{0,7}$" else
        if (kind == "I") "^(0|[1-9][0-9]{0,3})$" else if (kind == "X") "^[01?]{1,30}$" else "^[01]{1,30}$"
    grepl(pattern, text, perl = TRUE)
}
power2 <- function(exponent) bitwShiftL(1L, exponent)
mask <- function(size) power2(size) - 1L
bit_at <- function(size, column) power2(size - column)
parse_bits <- function(text) strtoi(text, base = 2L)
weight <- function(values) {
    result <- integer(length(values))
    while (any(values != 0L)) {
        active <- values != 0L
        result[active] <- result[active] + 1L
        values[active] <- bitwAnd(values[active], values[active] - 1L)
    }
    result
}
bit_length <- function(values) {
    result <- integer(length(values))
    while (any(values != 0L)) {
        active <- values != 0L
        result[active] <- result[active] + 1L
        values[active] <- bitwShiftR(values[active], 1L)
    }
    result
}
bits <- function(value, size) paste(as.integer(bitwAnd(value, bit_at(size, seq_len(size))) != 0L), collapse = "")
yes <- function(value) if (value) "yes" else "no"
joined <- function(values) paste(values, collapse = " ")
matrix_text <- function(label, rows, size) vapply(rows, function(row) paste(label, bits(row, size)), character(1L))

poly_div <- function(value, divisor) {
    quotient <- 0L
    while (value != 0L && bit_length(value) >= bit_length(divisor)) {
        shift <- bit_length(value) - bit_length(divisor)
        quotient <- bitwXor(quotient, power2(shift))
        value <- bitwXor(value, bitwShiftL(divisor, shift))
    }
    list(quotient = quotient, remainder = value)
}
basis <- function(source, size) {
    pivots <- integer(size)
    result <- integer()
    for (original in source) {
        row <- original
        for (column in seq_len(size)) {
            if (bitwAnd(row, bit_at(size, column)) == 0L) next
            if (pivots[column] != 0L) row <- bitwXor(row, pivots[column]) else {
                pivots[column] <- row
                result <- c(result, original)
                break
            }
        }
    }
    result
}
rref <- function(source, size) {
    rows <- source
    columns <- integer()
    for (column in seq_len(size)) {
        pivot <- length(columns) + 1L
        found <- which(seq_along(rows) >= pivot & bitwAnd(rows, bit_at(size, column)) != 0L)
        if (!length(found)) next
        rows[c(pivot, found[1L])] <- rows[c(found[1L], pivot)]
        others <- which(seq_along(rows) != pivot & bitwAnd(rows, bit_at(size, column)) != 0L)
        rows[others] <- bitwXor(rows[others], rows[pivot])
        columns <- c(columns, column)
    }
    list(rows = rows[seq_along(columns)], columns = columns)
}
null_space <- function(source, size) {
    reduced <- rref(source, size)
    vapply(setdiff(seq_len(size), reduced$columns), function(column) {
        selected <- bitwAnd(reduced$rows, bit_at(size, column)) != 0L
        Reduce(bitwOr, bit_at(size, reduced$columns[selected]), init = bit_at(size, column))
    }, integer(1L))
}
span <- function(rows) {
    result <- 0L
    for (row in rows) result <- c(result, bitwXor(result, row))
    result
}
reed_muller <- function(order, variables) {
    if (order == 0L) return(mask(power2(variables)))
    half <- power2(variables - 1L)
    first <- reed_muller(min(order, variables - 1L), variables - 1L)
    c(bitwOr(bitwShiftL(first, half), first), reed_muller(order - 1L, variables - 1L))
}
check_dimension <- function(size, dimension) {
    if (dimension < 1L || dimension > 12L || size - dimension < 1L || size - dimension > 12L)
        fail(paste("bad dimension", size, dimension))
}
make_code <- function(size, generator, parity = NULL, polynomial = NULL) {
    check_dimension(size, length(generator))
    list(n = size, k = length(generator), g = generator,
         h = if (is.null(parity)) null_space(generator, size) else parity, polynomial = polynomial)
}
encoder <- function(code) if (is.null(code$polynomial)) "matrix" else "polynomial"
encode <- function(code, message) {
    if (!is.null(code$polynomial)) {
        shifted <- bitwShiftL(message, code$n - code$k)
        return(bitwOr(shifted, poly_div(shifted, code$polynomial)$remainder))
    }
    selected <- bitwAnd(message, bit_at(code$k, seq_len(code$k))) != 0L
    Reduce(bitwXor, code$g[selected], init = 0L)
}
encoded_words <- function(code) {
    if (is.null(code$polynomial)) span(rev(code$g)) else
        vapply(seq_len(power2(code$k)) - 1L, function(message) encode(code, message), integer(1L))
}
syndrome <- function(code, words) {
    result <- integer(length(words))
    for (row in code$h) result <- bitwOr(bitwShiftL(result, 1L), weight(bitwAnd(row, words)) %% 2L)
    result
}
leaders <- function(code) {
    result <- rep(-1L, power2(code$n - code$k))
    result[1L] <- 0L
    found <- 1L
    for (size in seq_len(code$n)) {
        word <- mask(size)
        while (word < power2(code$n)) {
            state <- syndrome(code, word) + 1L
            if (result[state] == -1L) {
                result[state] <- word
                found <- found + 1L
                if (found == length(result)) return(result)
            }
            lowest <- bitwAnd(word, -word)
            following <- word + lowest
            word <- bitwOr(following, bitwShiftR(bitwXor(following, word), 2L) %/% lowest)
        }
    }
    result
}
decode <- function(code, received, errors, encoding) {
    pattern <- errors[syndrome(code, received) + 1L]
    word <- bitwXor(received, pattern)
    list(word = word, message = match(word, encoding) - 1L, error = pattern)
}
decoded_text <- function(code, result) paste("codeword", bits(result$word, code$n), "message", bits(result$message, code$k),
                                          "error", bits(result$error, code$n), "weight", weight(result$error))
burst_correction <- function(code) {
    seen <- logical(power2(code$n - code$k))
    seen[1L] <- TRUE
    for (size in seq_len(code$n)) {
        variants <- if (size == 1L) 1L else power2(size - 2L)
        for (offset in seq_len(code$n - size + 1L) - 1L) {
            for (middle in seq_len(variants) - 1L) {
                word <- if (size == 1L) 1L else bitwOr(bitwOr(power2(size - 1L), bitwShiftL(middle, 1L)), 1L)
                state <- syndrome(code, bitwShiftL(word, offset)) + 1L
                if (seen[state]) return(size - 1L)
                seen[state] <- TRUE
            }
        }
    }
    0L
}

construct <- function(command, args, sources) {
    if (command %in% c("GEN", "PCHECK")) {
        size <- nchar(args[2L])
        if (any(nchar(args[-1L]) != size)) fail("bad length")
        rows <- basis(parse_bits(args[-1L]), size)
        return(if (command == "GEN") make_code(size, rows) else make_code(size, null_space(rows, size), rows))
    }
    if (command %in% c("HAMMING", "SIMPLEX")) {
        order <- as.integer(args[2L])
        if (!order %in% 2L:4L) fail("bad parameter")
        size <- mask(order)
        rows <- vapply(seq_len(order), function(i) {
            Reduce(function(row, column) bitwOr(bitwShiftL(row, 1L), bitwAnd(bitwShiftR(column, order - i), 1L)),
                   seq_len(size), init = 0L)
        }, integer(1L))
        return(if (command == "SIMPLEX") make_code(size, rows) else make_code(size, null_space(rows, size), rows))
    }
    if (command %in% c("REPETITION", "PARITY")) {
        size <- as.integer(args[2L])
        if (!size %in% 2L:24L) fail("bad parameter")
        rows <- if (command == "REPETITION") mask(size) else bitwOr(bit_at(size, seq_len(size - 1L)), 1L)
        return(make_code(size, rows))
    }
    if (command == "RM") {
        order <- as.integer(args[2L]); variables <- as.integer(args[3L])
        if (!variables %in% 1L:4L || order > variables) fail("bad parameter")
        return(make_code(power2(variables), reed_muller(order, variables)))
    }
    if (command == "CYCLIC") {
        size <- as.integer(args[2L]); degree <- nchar(args[3L]) - 1L
        if (!size %in% 2L:24L || substr(args[3L], 1L, 1L) != "1" || degree < 1L || degree >= size) fail("bad parameter")
        polynomial <- parse_bits(args[3L])
        if (poly_div(bitwOr(power2(size), 1L), polynomial)$remainder != 0L) fail("not a divisor")
        dimension <- size - degree
        rows <- bitwShiftL(polynomial, dimension - seq_len(dimension))
        parity <- integer(degree)
        for (column in seq_len(size)) {
            residue <- poly_div(bit_at(size, column), polynomial)$remainder
            parity <- bitwOr(bitwShiftL(parity, 1L), as.integer(bitwAnd(residue, bit_at(degree, seq_len(degree))) != 0L))
        }
        return(make_code(size, rows, parity, polynomial))
    }
    source <- sources[[1L]]
    size <- source$n
    if (command == "DUAL") return(make_code(size, source$h, source$g))
    if (command == "EXTEND") return(make_code(size + 1L, bitwOr(bitwShiftL(source$g, 1L), weight(source$g) %% 2L)))
    if (command %in% c("PUNCTURE", "SHORTEN", "EXPURGATE")) {
        expurgating <- command == "EXPURGATE"
        position <- if (expurgating) 0L else as.integer(args[3L])
        if (!expurgating && !position %in% seq_len(size)) fail("bad position")
        selected <- if (expurgating) weight(source$g) %% 2L != 0L else bitwAnd(source$g, bit_at(size, position)) != 0L
        removed <- if (command == "PUNCTURE" || !any(selected)) 0L else which(selected)[1L]
        rows <- source$g
        if (removed != 0L) {
            rows[selected] <- bitwXor(rows[selected], source$g[removed])
            rows <- rows[-removed]
        }
        if (!expurgating) {
            low <- size - position
            rows <- bitwOr(bitwShiftL(bitwShiftR(rows, low + 1L), low), bitwAnd(rows, mask(low)))
            size <- size - 1L
        }
        if (command == "PUNCTURE") rows <- basis(rows, size)
        return(make_code(size, rows))
    }
    if (command == "AUGMENT") return(make_code(size, basis(c(source$g, mask(size)), size)))
    if (command == "PERMUTE") {
        permutation <- as.integer(args[-c(1L, 2L)])
        if (!identical(sort(permutation), seq_len(size))) fail("bad permutation")
        rows <- vapply(source$g, function(row) {
            Reduce(function(value, column) bitwOr(bitwShiftL(value, 1L), as.integer(bitwAnd(row, bit_at(size, column)) != 0L)),
                   permutation, init = 0L)
        }, integer(1L))
        return(make_code(size, rows))
    }
    other <- sources[[2L]]
    if (command == "UUV" && size != other$n) fail("bad length")
    product <- command == "PRODUCT"
    combined <- if (product) size * other$n else size + other$n
    dimension <- if (product) source$k * other$k else source$k + other$k
    check_dimension(combined, dimension)
    if (product) {
        rows <- unlist(lapply(source$g, function(left) vapply(other$g, function(right) {
            Reduce(function(value, column) bitwOr(bitwShiftL(value, other$n), if (bitwAnd(left, bit_at(size, column)) != 0L) right else 0L),
                   seq_len(size), init = 0L)
        }, integer(1L))), use.names = FALSE)
    } else rows <- c(bitwOr(bitwShiftL(source$g, other$n), if (command == "UUV") source$g else 0L), other$g)
    make_code(combined, rows)
}

COMBINATIONS <- matrix(0L, 25L, 25L)
for (n in 0L:24L) {
    COMBINATIONS[n + 1L, 1L] <- 1L
    for (k in seq_len(n)) COMBINATIONS[n + 1L, k + 1L] <- COMBINATIONS[n, k] + COMBINATIONS[n, k + 1L]
}
choose_count <- function(size, selected) if (selected < 0L || selected > size) 0L else COMBINATIONS[size + 1L, selected + 1L]
volume <- function(size, radius) sum(COMBINATIONS[size + 1L, seq_len(radius + 1L)])
krawtchouk <- function(size, index, argument) sum(vapply(0L:index, function(selected) {
    sign <- if (selected %% 2L == 0L) 1L else -1L
    sign * choose_count(argument, selected) * choose_count(size - argument, index - selected)
}, integer(1L)))
fraction_text <- function(numerator, denominator) {
    common <- gcd.bigz(numerator, denominator)
    top <- as.bigz(numerator) %/% common
    bottom <- as.bigz(denominator) %/% common
    if (bottom == 1L) as.character(top) else paste0(as.character(top), "/", as.character(bottom))
}
distribution <- function(words, size, offset = 0L) tabulate(weight(bitwXor(words, offset)) + 1L, nbins = size + 1L)
weight_items <- function(counts) {
    selected <- which(counts != 0L)
    paste(paste0(selected - 1L, ":", counts[selected]), collapse = " ")
}

systematic <- function(name, code) {
    rows <- code$g
    permutation <- seq_len(code$n)
    for (pivot in seq_len(code$k)) {
        column <- pivot
        repeat {
            found <- which(seq_along(rows) >= pivot & bitwAnd(rows, bit_at(code$n, column)) != 0L)
            if (length(found)) break
            column <- column + 1L
        }
        if (column != pivot) {
            left <- bit_at(code$n, pivot); right <- bit_at(code$n, column)
            different <- (bitwAnd(rows, left) != 0L) != (bitwAnd(rows, right) != 0L)
            rows[different] <- bitwXor(rows[different], bitwOr(left, right))
            permutation[c(pivot, column)] <- permutation[c(column, pivot)]
        }
        rows[c(pivot, found[1L])] <- rows[c(found[1L], pivot)]
        others <- which(seq_along(rows) != pivot & bitwAnd(rows, bit_at(code$n, pivot)) != 0L)
        rows[others] <- bitwXor(rows[others], rows[pivot])
    }
    checks <- vapply(seq_len(code$n - code$k), function(column) {
        first <- Reduce(function(value, row) bitwOr(bitwShiftL(value, 1L), as.integer(bitwAnd(row, bit_at(code$n, code$k + column)) != 0L)),
                        rows, init = 0L)
        bitwOr(bitwShiftL(first, code$n - code$k), bit_at(code$n - code$k, column))
    }, integer(1L))
    c(paste("systematic", name, "perm", joined(permutation)), matrix_text("G", rows, code$n), matrix_text("H", checks, code$n))
}
inspect_code <- function(command, args, sources) {
    code <- sources[[1L]]
    name <- args[1L]; n <- code$n; k <- code$k
    if (command == "SHOW") {
        output <- paste("code", name, "n", n, "k", k, "encoder", encoder(code))
        if (!is.null(code$polynomial)) {
            quotient <- poly_div(bitwOr(power2(n), 1L), code$polynomial)$quotient
            output <- c(output, paste("poly g", bits(code$polynomial, n - k + 1L), "h", bits(quotient, k + 1L)))
        }
        return(c(output, matrix_text("G", code$g, n), matrix_text("H", code$h, n)))
    }
    if (command == "SYSTEMATIC") return(systematic(name, code))
    if (command == "EQUAL") {
        other <- sources[[2L]]
        if (n != other$n) return(paste("equal", name, args[2L], "no lengths", n, other$n))
        common <- k + other$k - length(basis(c(code$g, other$g), n))
        return(paste("equal", name, args[2L], yes(k == common && other$k == common), "intersection", common))
    }
    if (command == "TRELLIS") {
        profile <- vapply(0L:n, function(column) {
            length(basis(bitwShiftR(code$g, n - column), column)) +
                length(basis(bitwAnd(code$g, mask(n - column)), n - column)) - k
        }, integer(1L))
        return(paste("trellis", name, "profile", joined(profile), "max", max(profile)))
    }
    if (command == "COVERING") {
        counts <- distribution(leaders(code), n)
        radius <- max(which(counts != 0L)) - 1L
        items <- paste0(0L:radius, ":", counts[seq_len(radius + 1L)])
        return(paste("covering", name, "radius", radius, "leaders", joined(items)))
    }
    if (command == "STDARRAY" && (n - k > 6L || k > 4L)) fail("too large")
    words <- span(code$g)
    if (command == "INFO") {
        distance <- min(weight(words[-1L]))
        correction <- (distance - 1L) %/% 2L
        rotated <- bitwOr(bitwAnd(bitwShiftL(code$g, 1L), mask(n)), bitwShiftR(code$g, n - 1L))
        first <- min(words[-1L])
        cyclic <- if (all(syndrome(code, rotated) == 0L)) bits(first, bit_length(first)) else "no"
        return(paste("info", name, "n", n, "k", k, "rate", fraction_text(k, n), "d", distance, "t", correction,
                     "perfect", yes(volume(n, correction) == power2(n - k)), "mds", yes(distance == n - k + 1L), "cyclic", cyclic))
    }
    if (command == "WEIGHTS") {
        primal <- distribution(words, n); dual <- distribution(span(code$h), n)
        orthogonal <- all(weight(base::outer(code$g, code$g, bitwAnd)) %% 2L == 0L)
        return(c(paste("weights", name, weight_items(primal)), paste("dual", name, weight_items(dual)),
                 paste("duality", name, "self-orthogonal", yes(orthogonal), "self-dual", yes(orthogonal && n == 2L * k),
                       "formally-self-dual", yes(identical(primal, dual)))))
    }
    if (command == "BURST") {
        nonzero <- words[-1L]
        detection <- min(bit_length(nonzero) - bit_length(bitwAnd(nonzero, -nonzero)))
        return(paste("burst", name, "detect", detection, "correct", burst_correction(code)))
    }
    errors <- leaders(code)
    ordering <- order(weight(errors), errors, method = "radix")
    words <- sort(words)
    output <- paste("stdarray", name, "rows", length(errors), "columns", length(words))
    for (state in ordering) {
        row <- vapply(bitwXor(errors[state], words), bits, character(1L), size = n)
        output <- c(output, paste0(bits(state - 1L, n - k), ": ", joined(row)))
    }
    output
}
encoding_report <- function(command, args, code) {
    name <- args[1L]; n <- code$n; k <- code$k
    if (command == "INTERLEAVE") {
        messages <- args[-c(1L, 2L, 3L)]
        if (any(nchar(messages) != k)) fail("bad length")
        start <- as.integer(args[2L]); burst_length <- as.integer(args[3L]); depth <- length(messages)
        if (start < 1L || burst_length < 1L || start + burst_length - 1L > depth * n) fail("bad burst")
        encoded <- vapply(parse_bits(messages), function(message) encode(code, message), integer(1L))
        sent_matrix <- matrix(FALSE, depth, n)
        for (column in seq_len(n)) sent_matrix[, column] <- bitwAnd(encoded, bit_at(n, column)) != 0L
        sent <- as.vector(sent_matrix)
        received <- sent
        selected <- seq_len(burst_length) + start - 1L
        received[selected] <- !received[selected]
        received_matrix <- matrix(received, nrow = depth)
        received_words <- integer(depth)
        for (column in seq_len(n)) received_words <- bitwOr(bitwShiftL(received_words, 1L), as.integer(received_matrix[, column]))
        output <- c(paste("interleave", name, "depth", depth, "burst", start, burst_length),
                    paste("sent", paste(as.integer(sent), collapse = "")), paste("recv", paste(as.integer(received), collapse = "")))
        errors <- leaders(code); encoding <- encoded_words(code); correct <- 0L
        for (row in seq_len(depth)) {
            result <- decode(code, received_words[row], errors, encoding)
            success <- result$message == parse_bits(messages[row])
            if (success) correct <- correct + 1L
            output <- c(output, paste("row", row, "errors", weight(bitwXor(received_words[row], encoded[row])),
                                     "corrected", weight(result$error), "message", bits(result$message, k), if (success) "ok" else "wrong"))
        }
        return(c(output, paste("result ok", correct, "wrong", depth - correct)))
    }
    text <- args[if (command == "BOUNDED") 3L else 2L]
    expected <- if (command == "ENCODE") k else n
    if (nchar(text) != expected) fail("bad length")
    if (command == "ENCODE") return(paste("encode", name, "message", text, "codeword", bits(encode(code, parse_bits(text)), n)))
    if (command == "ERASURE") {
        units <- strsplit(text, "", fixed = TRUE)[[1L]]
        erased <- sum(units == "?")
        known <- Reduce(bitwOr, bit_at(n, which(units != "?")), init = 0L)
        value <- Reduce(bitwOr, bit_at(n, which(units == "1")), init = 0L)
        words <- span(code$g)
        candidates <- words[bitwAnd(words, known) == value]
        output <- paste("erasure", name, "erased", erased, "candidates", length(candidates))
        if (length(candidates) == 1L) output <- paste(output, "codeword", bits(candidates[1L], n),
                                                   "message", bits(match(candidates[1L], encoded_words(code)) - 1L, k))
        return(output)
    }
    word <- parse_bits(text)
    state <- syndrome(code, word)
    if (command == "SYNDROME") return(paste("syndrome", name, bits(state, n - k), "codeword", yes(state == 0L)))
    errors <- leaders(code)
    if (command == "COSET") return(paste("coset", name, "syndrome", bits(state, n - k), "leader", bits(errors[state + 1L], n),
                                        "weights", weight_items(distribution(span(code$g), n, word))))
    result <- decode(code, word, errors, encoded_words(code))
    if (command == "BOUNDED" && weight(result$error) > as.integer(args[2L]))
        return(paste("bounded", name, "fail weight", weight(result$error)))
    paste(tolower(command), name, decoded_text(code, result))
}

independent_report <- function(command, args) {
    if (command %in% c("CRC", "CRCCHECK")) {
        degree <- nchar(args[1L]) - 1L
        if (substr(args[1L], 1L, 1L) != "1" || !degree %in% 1L:16L) fail("bad parameter")
        if (command == "CRC" && nchar(args[2L]) + degree > 30L) fail("bad length")
        word <- bitwShiftL(parse_bits(args[2L]), if (command == "CRC") degree else 0L)
        residue <- poly_div(word, parse_bits(args[1L]))$remainder
        suffix <- bits(residue, degree)
        return(if (command == "CRC") paste("crc remainder", suffix, "frame", paste0(args[2L], suffix)) else
            paste("crccheck", if (residue == 0L) "ok" else "error", "remainder", suffix))
    }
    size <- as.integer(args[1L])
    if (command == "BOUNDS") {
        distance <- as.integer(args[2L])
        if (distance < 1L || distance > size || size > 24L) fail("bad parameter")
        ball <- as.bigz(volume(size, (distance - 1L) %/% 2L))
        hamming <- max(which(as.bigz(power2(0L:size)) * ball <= power2(size))) - 1L
        requirements <- (distance + power2(0L:(size - 1L)) - 1L) %/% power2(0L:(size - 1L))
        griesmer <- max(which(cumsum(requirements) <= size))
        return(paste("bounds n", size, "d", distance, "singleton", size - distance + 1L, "hamming", hamming, "griesmer", griesmer))
    }
    if (!size %in% 1L:24L) fail("bad parameter")
    if (command == "FACTOR") {
        remaining <- bitwOr(power2(size), 1L)
        factor <- 3L; divisors <- 1L; factors <- character()
        while (2L * (bit_length(factor) - 1L) <= bit_length(remaining) - 1L) {
            exponent <- 0L
            repeat {
                divided <- poly_div(remaining, factor)
                if (divided$remainder != 0L) break
                remaining <- divided$quotient
                exponent <- exponent + 1L
            }
            if (exponent != 0L) {
                factors <- c(factors, paste0(bits(factor, bit_length(factor)), "^", exponent))
                divisors <- divisors * (exponent + 1L)
            }
            factor <- factor + 2L
        }
        if (remaining != 1L) {
            factors <- c(factors, paste0(bits(remaining, bit_length(remaining)), "^1"))
            divisors <- divisors * 2L
        }
        return(paste("factor", size, joined(factors), "divisors", divisors))
    }
    if (length(args) != size + 2L) fail("bad length")
    counts <- as.integer(args[-1L])
    if (counts[1L] != 1L) fail("bad parameter")
    total <- sum(counts)
    numerators <- c_bigz(lapply(0L:size, function(index) {
        coefficients <- vapply(0L:size, function(argument) krawtchouk(size, index, argument), integer(1L))
        sum(as.bigz(counts) * coefficients)
    }))
    feasible <- bitwAnd(total, total - 1L) == 0L && all(numerators >= 0L & numerators %% total == 0L)
    dual <- vapply(seq_len(size + 1L), function(i) fraction_text(numerators[i], total), character(1L))
    c(paste("macwilliams n", size, "size", total), paste("dual", joined(dual)), paste("feasible", yes(feasible)))
}

execute <- function(line, registry) {
    words <- strsplit(line, " ", fixed = TRUE)[[1L]]
    command <- words[1L]
    form <- FORMATS[[command]]
    if (is.null(form)) fail(paste("unknown command", command))
    args <- words[-1L]
    if (length(args) < form$minimum || length(args) > form$maximum) fail("bad arguments")
    types <- strsplit(form$types, "", fixed = TRUE)[[1L]]
    for (i in seq_along(args)) if (!valid_word(args[i], types[min(i, length(types))])) fail("bad arguments")
    sources <- list()
    for (i in seq_along(types)) if (types[i] %in% c("A", "B")) {
        if (!exists(args[i], registry, inherits = FALSE)) fail(paste("no code", args[i]))
        sources[[length(sources) + 1L]] <- get(args[i], registry, inherits = FALSE)
    }
    if (command %in% DEFINITIONS) {
        code <- construct(command, args, sources)
        action <- if (exists(args[1L], registry, inherits = FALSE)) "redefined" else "defined"
        assign(args[1L], code, registry)
        return(paste(action, args[1L], "n", code$n, "k", code$k))
    }
    if (command %in% INDEPENDENT) return(independent_report(command, args))
    if (command == "LIST") {
        names <- sort(ls(registry, all.names = TRUE), method = "radix")
        rows <- vapply(names, function(name) {
            code <- get(name, registry, inherits = FALSE)
            paste(name, "n", code$n, "k", code$k, "encoder", encoder(code))
        }, character(1L))
        return(c(paste("codes", length(names)), rows))
    }
    if (command == "DELETE") {
        rm(list = args[1L], envir = registry)
        return(paste("deleted", args[1L]))
    }
    if (command %in% c("ENCODE", "SYNDROME", "DECODE", "BOUNDED", "COSET", "ERASURE", "INTERLEAVE"))
        encoding_report(command, args, sources[[1L]]) else inspect_code(command, args, sources)
}

registry <- new.env(hash = TRUE, parent = emptyenv())
input <- file("stdin", open = "r")
command_count <- as.integer(readLines(input, n = 1L, warn = FALSE))
for (command_index in seq_len(command_count)) {
    line <- readLines(input, n = 1L, warn = FALSE)
    output <- tryCatch(execute(line, registry), command_error = function(problem) paste("error:", problem$message))
    cat(paste0(output, "\n"), sep = "")
}
close(input)
