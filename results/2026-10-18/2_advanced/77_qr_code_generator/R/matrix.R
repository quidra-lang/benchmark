QR_DATA <- 0L
QR_FUNCTION <- 1L
QR_FORMAT <- 2L
QR_VERSION <- 3L

polynomial_remainder <- function(value, divisor) {
    bit_length <- function(number) {
        width <- 0L
        while (number != 0L) {
            width <- width + 1L
            number <- bitwShiftR(number, 1L)
        }
        width
    }
    while (value != 0L && bit_length(value) >= bit_length(divisor)) {
        value <- bitwXor(value, bitwShiftL(divisor, bit_length(value) - bit_length(divisor)))
    }
    value
}

format_information <- function(level, mask) {
    indicator <- c(L = 1L, M = 0L, Q = 3L, H = 2L)[[level]]
    shifted <- bitwShiftL(8L * indicator + mask, 10L)
    bitwXor(shifted + polynomial_remainder(shifted, 1335L), 21522L)
}

version_information <- function(version) {
    shifted <- bitwShiftL(version, 12L)
    shifted + polynomial_remainder(shifted, 7973L)
}

format_positions <- function(side) {
    first_copy <- rbind(cbind(8L, 0:5), c(8L, 7L), c(8L, 8L), c(7L, 8L), cbind(14L - 9:14, 8L))
    second_copy <- rbind(cbind(side - 1L - 0:7, 8L), cbind(8L, side - 15L + 8:14))
    list(first_copy, second_copy)
}

version_positions <- function(side) {
    index <- 0:17
    list(cbind(side - 11L + index %% 3L, index %/% 3L), cbind(index %/% 3L, side - 11L + index %% 3L))
}

write_matrix_value <- function(symbol, positions, value) {
    for (index in seq_len(nrow(positions))) {
        symbol[
            positions[index, 2L] + 1L,
            positions[index, 1L] + 1L
        ] <- bitwAnd(bitwShiftR(value, index - 1L), 1L)
    }
    symbol
}

read_matrix_value <- function(symbol, positions) {
    value <- 0L
    for (index in seq_len(nrow(positions))) {
        value <- bitwOr(
            value,
            bitwShiftL(symbol[positions[index, 2L] + 1L, positions[index, 1L] + 1L], index - 1L)
        )
    }
    value
}

function_matrix <- function(version, alignments) {
    side <- 17L + 4L * version
    symbol <- matrix(0L, side, side)
    areas <- matrix(QR_DATA, side, side)
    for (center in list(c(3L, 3L), c(side - 4L, 3L), c(3L, side - 4L))) {
        for (dy in -4:4) for (dx in -4:4) {
            x <- center[1L] + dx
            y <- center[2L] + dy
            if (x >= 0L && x < side && y >= 0L && y < side) {
                symbol[y + 1L, x + 1L] <- as.integer(max(abs(dx), abs(dy)) %in% c(0L, 1L, 3L))
                areas[y + 1L, x + 1L] <- QR_FUNCTION
            }
        }
    }
    for (index in 8L:(side - 9L)) {
        symbol[index + 1L, 7L] <- symbol[7L, index + 1L] <- as.integer(index %% 2L == 0L)
        areas[index + 1L, 7L] <- areas[7L, index + 1L] <- QR_FUNCTION
    }
    if (length(alignments)) {
        low <- alignments[1L]
        high <- tail(alignments, 1L)
        for (cy in alignments) for (cx in alignments) {
            if ((cx == low && cy == low) || (cx == low && cy == high) || (cx == high && cy == low)) next
            for (dy in -2:2) for (dx in -2:2) {
                symbol[cy + dy + 1L, cx + dx + 1L] <- as.integer(max(abs(dx), abs(dy)) != 1L)
                areas[cy + dy + 1L, cx + dx + 1L] <- QR_FUNCTION
            }
        }
    }
    symbol[side - 7L, 9L] <- 1L
    areas[side - 7L, 9L] <- QR_FUNCTION
    for (positions in format_positions(side)) {
        for (index in seq_len(nrow(positions))) {
            areas[positions[index, 2L] + 1L, positions[index, 1L] + 1L] <- QR_FORMAT
            symbol[positions[index, 2L] + 1L, positions[index, 1L] + 1L] <- 0L
        }
    }
    if (version >= 7L) {
        for (positions in version_positions(side)) {
            for (index in seq_len(nrow(positions))) areas[
                positions[index, 2L] + 1L,
                positions[index, 1L] + 1L
            ] <- QR_VERSION
            symbol <- write_matrix_value(symbol, positions, version_information(version))
        }
    }
    list(symbol = symbol, areas = areas)
}

reading_order <- function(areas) {
    side <- nrow(areas)
    columns <- c(seq.int(side - 1L, 8L, by = -2L), 5L, 3L, 1L)
    positions <- vector("list", side * side)
    count <- 0L
    for (pair in seq_along(columns)) {
        rows <- if (pair %% 2L == 1L) seq.int(side - 1L, 0L) else seq_len(side) - 1L
        for (y in rows) for (x in c(columns[pair], columns[pair] - 1L)) {
            if (areas[y + 1L, x + 1L] == QR_DATA) {
                count <- count + 1L
                positions[[count]] <- c(x, y)
            }
        }
    }
    do.call(rbind, positions[seq_len(count)])
}
