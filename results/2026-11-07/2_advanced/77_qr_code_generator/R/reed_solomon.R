QR_EXP <- rep(1L, 255L)
for (exponent in 2:255) {
    doubled <- QR_EXP[exponent - 1L] * 2L
    QR_EXP[exponent] <- if (doubled >= 256L) bitwXor(doubled, 285L) else doubled
}
QR_LOG <- integer(256L)
for (exponent in seq_along(QR_EXP)) QR_LOG[QR_EXP[exponent] + 1L] <- exponent - 1L
QR_GENERATORS <- new.env(parent = emptyenv())

gf_multiply <- function(left, right) {
    if (left == 0L || right == 0L) return(0L)
    QR_EXP[(QR_LOG[left + 1L] + QR_LOG[right + 1L]) %% 255L + 1L]
}

gf_divide <- function(numerator, denominator) {
    if (numerator == 0L) return(0L)
    QR_EXP[(QR_LOG[numerator + 1L] - QR_LOG[denominator + 1L]) %% 255L + 1L]
}

rs_generator <- function(degree) {
    key <- as.character(degree)
    if (exists(key, QR_GENERATORS, inherits = FALSE)) return(QR_GENERATORS[[key]])
    coefficients <- 1L
    for (exponent in seq_len(degree) - 1L) {
        product <- integer(length(coefficients) + 1L)
        for (index in seq_along(coefficients)) {
            product[index] <- bitwXor(product[index], coefficients[index])
            product[index + 1L] <- bitwXor(
                product[index + 1L],
                gf_multiply(coefficients[index], QR_EXP[exponent + 1L])
            )
        }
        coefficients <- product
    }
    QR_GENERATORS[[key]] <- coefficients
    coefficients
}

rs_parity <- function(data, degree) {
    polynomial <- rs_generator(degree)
    remainder <- c(data, integer(degree))
    for (index in seq_along(data)) {
        leading <- remainder[index]
        if (leading != 0L) {
            for (offset in seq_along(polynomial)) {
                target <- index + offset - 1L
                remainder[target] <- bitwXor(remainder[target], gf_multiply(leading, polynomial[offset]))
            }
        }
    }
    tail(remainder, degree)
}

rs_syndromes <- function(words, degree) {
    result <- integer(degree)
    for (exponent in seq_len(degree) - 1L) {
        value <- 0L
        for (word in words) value <- bitwXor(gf_multiply(value, QR_EXP[exponent + 1L]), word)
        result[exponent + 1L] <- value
    }
    result
}

gf_evaluate <- function(coefficients, argument) {
    value <- 0L
    for (coefficient in rev(coefficients)) value <- bitwXor(gf_multiply(value, argument), coefficient)
    value
}

rs_correct <- function(received, degree) {
    syndromes <- rs_syndromes(received, degree)
    failure <- list(syndromes = syndromes, corrected = NULL, positions = integer())
    if (all(syndromes == 0L)) return(list(syndromes = syndromes, corrected = received, positions = integer()))
    locator <- c(1L, integer(degree))
    previous <- locator
    locator_length <- 0L
    shift <- 1L
    beta <- 1L
    for (step in seq_len(degree) - 1L) {
        discrepancy <- syndromes[step + 1L]
        for (index in seq_len(locator_length)) {
            discrepancy <- bitwXor(
                discrepancy,
                gf_multiply(locator[index + 1L], syndromes[step - index + 1L])
            )
        }
        if (discrepancy == 0L) {
            shift <- shift + 1L
            next
        }
        saved <- locator
        multiplier <- gf_divide(discrepancy, beta)
        for (index in seq_len(max(0L, degree + 1L - shift)) - 1L) {
            target <- index + shift + 1L
            locator[target] <- bitwXor(locator[target], gf_multiply(multiplier, previous[index + 1L]))
        }
        if (2L * locator_length <= step) {
            locator_length <- step + 1L - locator_length
            previous <- saved
            beta <- discrepancy
            shift <- 1L
        } else {
            shift <- shift + 1L
        }
    }
    if (locator_length > degree %/% 2L) return(failure)
    locator <- locator[seq_len(locator_length + 1L)]
    positions <- integer()
    word_count <- length(received)
    for (index in seq_len(word_count) - 1L) {
        inverse <- QR_EXP[(255L - (word_count - 1L - index)) %% 255L + 1L]
        if (gf_evaluate(locator, inverse) == 0L) positions <- c(positions, index)
    }
    if (length(positions) != locator_length) return(failure)
    omega <- integer(degree)
    for (index in seq_along(syndromes)) {
        for (offset in seq_len(min(locator_length, degree - index) + 1L) - 1L) {
            omega[index + offset] <- bitwXor(
                omega[index + offset],
                gf_multiply(syndromes[index], locator[offset + 1L])
            )
        }
    }
    derivative <- integer(locator_length)
    if (locator_length > 0L) {
        for (exponent in seq.int(1L, locator_length, by = 2L)) derivative[exponent] <- locator[exponent + 1L]
    }
    corrected <- received
    for (index in positions) {
        location <- QR_EXP[(word_count - 1L - index) %% 255L + 1L]
        inverse <- QR_EXP[(255L - (word_count - 1L - index)) %% 255L + 1L]
        denominator <- gf_evaluate(derivative, inverse)
        if (denominator == 0L) return(failure)
        magnitude <- gf_multiply(location, gf_divide(gf_evaluate(omega, inverse), denominator))
        corrected[index + 1L] <- bitwXor(corrected[index + 1L], magnitude)
    }
    if (any(rs_syndromes(corrected, degree) != 0L)) return(failure)
    changed <- positions[corrected[positions + 1L] != received[positions + 1L]]
    list(syndromes = syndromes, corrected = corrected, positions = changed)
}
