new_byte_reader <- function(data, position = 0L) {
    reader <- new.env(parent = emptyenv())
    reader$data <- data
    reader$position <- position
    reader
}

read_bytes <- function(reader, count) {
    count <- as.integer(count)
    indices <- reader$position + seq_len(count)
    reader$position <- reader$position + count
    reader$data[indices]
}

read_byte <- function(reader) {
    reader$position <- reader$position + 1L
    reader$data[reader$position]
}

read_uleb <- function(reader) {
    value <- 0
    multiplier <- 1
    repeat {
        byte <- read_byte(reader)
        value <- value + (byte %% 128) * multiplier
        if (byte < 128) return(value)
        multiplier <- multiplier * 128
    }
}

read_zigzag <- function(reader) {
    value <- read_uleb(reader)
    if (value %% 2 == 0) value %/% 2 else -(value + 1) %/% 2
}

read_integer <- function(reader, signed = FALSE) {
    value <- sum(read_bytes(reader, 4L) * c(1, 256, 65536, 16777216))
    if (signed && value >= 2147483648) value - 4294967296 else value
}

uleb_bytes <- function(value) {
    output <- integer()
    while (value >= 128) {
        output <- c(output, as.integer(value %% 128 + 128))
        value <- value %/% 128
    }
    c(output, as.integer(value))
}

zigzag_bytes <- function(value) uleb_bytes(if (value >= 0) 2 * value else -2 * value - 1)
integer_bytes <- function(value) as.integer((value %/% c(1, 256, 65536, 16777216)) %% 256)
bit_width <- function(value) {
    width <- 0L
    while (value > 0) {
        width <- width + 1L
        value <- value %/% 2
    }
    width
}
hex_bytes <- function(data) paste0(sprintf("%02x", as.integer(data)), collapse = "")
hex_checksum <- function(value) paste0(
    sprintf("%04x", as.integer(value %/% 65536)),
    sprintf("%04x", as.integer(value %% 65536))
)
ascii_bytes <- function(text) utf8ToInt(text)
ascii_text <- function(bytes) intToUtf8(as.integer(bytes))

pack_values <- function(values, width) {
    output <- integer((length(values) * width) %/% 8L)
    for (index in seq_along(values)) {
        value <- as.numeric(values[index])
        for (bit in seq_len(width) - 1L) {
            serial <- (index - 1L) * width + bit
            target <- serial %/% 8L + 1L
            output[target] <- output[target] + as.integer(value %% 2) * 2L^(serial %% 8L)
            value <- value %/% 2
        }
    }
    as.integer(output)
}

unpack_values <- function(reader, width, count) {
    bytes <- read_bytes(reader, (count * width) %/% 8L)
    values <- numeric(count)
    for (index in seq_len(count) - 1L) {
        for (bit in seq_len(width) - 1L) {
            serial <- index * width + bit
            digit <- (bytes[serial %/% 8L + 1L] %/% 2^(serial %% 8L)) %% 2
            values[index + 1L] <- values[index + 1L] + digit * 2^bit
        }
    }
    values
}

adler32 <- function(data) {
    first <- 1
    second <- 0
    for (byte in data) {
        first <- (first + byte) %% 65521
        second <- (second + first) %% 65521
    }
    second * 65536 + first
}

hybrid_encode <- function(values, width) {
    count <- length(values)
    runs <- rep(1L, count)
    if (count > 1L) for (index in seq.int(
        count - 1L,
        1L
    )) if (values[index] == values[index + 1L]) runs[index] <- runs[index] + runs[index + 1L]
    output <- integer()
    index <- 1L
    while (index <= count) {
        if (runs[index] >= 8L) {
            output <- c(
                output,
                uleb_bytes(2L * runs[index]),
                as.integer((as.numeric(values[index]) %/% 256^(seq_len((width + 7L) %/% 8L) - 1L)) %% 256)
            )
            index <- index + runs[index]
        } else {
            stop <- index
            groups <- 0L
            repeat {
                stop <- stop + 8L
                groups <- groups + 1L
                if (stop > count || groups == 63L || runs[stop] >= 8L) break
            }
            block <- c(values[index:min(stop - 1L, count)], rep(0, max(0L, stop - count - 1L)))
            output <- c(output, uleb_bytes(2L * groups + 1L), pack_values(block, width))
            index <- stop
        }
    }
    output
}

hybrid_decode <- function(reader, width, count) {
    values <- numeric()
    while (length(values) < count) {
        header <- read_uleb(reader)
        if (header %% 2 == 0) {
            bytes <- read_bytes(reader, (width + 7L) %/% 8L)
            value <- sum(bytes * 256^(seq_along(bytes) - 1L))
            values <- c(values, rep(value, header %/% 2))
        } else {
            values <- c(values, unpack_values(reader, width, ((header - 1) %/% 2) * 8))
        }
    }
    values[seq_len(count)]
}
