ENCODING_METHODS <- c("PLAIN", "DICTIONARY", "RLE", "DELTA_BINARY_PACKED", "DELTA_LENGTH_BYTE_ARRAY")
ENCODING_CANDIDATES <- list(
    INT = c(0L, 1L, 3L),
    DATE = c(0L, 1L, 3L),
    STRING = c(0L, 1L, 4L),
    BOOL = c(0L, 2L)
)

delta_encode <- function(values) {
    values <- as.numeric(values)
    output <- c(
        uleb_bytes(128L),
        uleb_bytes(4L),
        uleb_bytes(length(values)),
        zigzag_bytes(if (length(values)) values[1L] else 0)
    )
    deltas <- diff(values)
    if (length(deltas)) for (start in seq.int(1L, length(deltas), by = 128L)) {
        block <- deltas[start:min(start + 127L, length(deltas))]
        low <- min(block)
        miniblocks <- lapply(seq.int(1L, 128L, by = 32L), function(index) {
            if (index > length(block)) numeric() else block[index:min(index + 31L, length(block))] - low
        })
        widths <- vapply(
            miniblocks,
            function(miniblock) bit_width(if (length(miniblock)) max(miniblock) else 0),
            0L
        )
        output <- c(output, zigzag_bytes(low), widths)
        for (index in seq_along(miniblocks)) {
            miniblock <- miniblocks[[index]]
            if (length(miniblock)) output <- c(
                output,
                pack_values(c(miniblock, rep(0, 32L - length(miniblock))), widths[index])
            )
        }
    }
    output
}

delta_decode <- function(reader) {
    block_size <- read_uleb(reader)
    miniblock_count <- read_uleb(reader)
    count <- read_uleb(reader)
    first <- read_zigzag(reader)
    values <- if (count > 0) first else numeric()
    miniblock_size <- block_size %/% miniblock_count
    while (length(values) < count) {
        low <- read_zigzag(reader)
        widths <- vapply(seq_len(miniblock_count), function(index) read_byte(reader), 0L)
        for (width in widths) {
            if (length(values) == count) break
            differences <- unpack_values(reader, width, miniblock_size)
            for (difference in head(
                differences,
                min(miniblock_size, count - length(values))
            )) values <- c(values, tail(values, 1L) + low + difference)
        }
    }
    values
}

encode_values <- function(kind, method, values, dictionary = list()) {
    if (method == 0L) {
        output <- integer()
        if (kind %in% c("INT", "DATE")) {
            for (value in values) output <- c(output, integer_bytes(value))
        } else if (kind == "STRING") {
            for (value in values) output <- c(output, integer_bytes(nchar(value)), ascii_bytes(value))
        } else {
            output <- pack_values(c(as.integer(unlist(values)), integer((-length(values)) %% 8L)), 1L)
        }
        return(output)
    }
    if (method == 1L) {
        width <- bit_width(length(dictionary) - 1L)
        ranks <- vapply(values, function(value) match(value, unlist(dictionary, use.names = FALSE)) - 1L, 0L)
        return(c(width, hybrid_encode(ranks, width)))
    }
    if (method == 2L) {
        encoded <- hybrid_encode(as.integer(unlist(values)), 1L)
        return(c(integer_bytes(length(encoded)), encoded))
    }
    if (method == 3L) return(delta_encode(unlist(values, use.names = FALSE)))
    lengths <- vapply(values, nchar, 0L)
    c(delta_encode(lengths), unlist(lapply(values, ascii_bytes), use.names = FALSE))
}

decode_values <- function(reader, kind, method, count, dictionary = list()) {
    if (method == 0L) {
        if (kind %in% c("INT", "DATE")) return(lapply(
            seq_len(count),
            function(index) read_integer(reader, signed = TRUE)
        ))
        if (kind == "STRING") return(lapply(
            seq_len(count),
            function(index) ascii_text(read_bytes(reader, read_integer(reader)))
        ))
        return(as.list(head(unpack_values(reader, 1L, ((count + 7L) %/% 8L) * 8L), count) == 1))
    }
    if (method == 1L) {
        width <- read_byte(reader)
        ranks <- hybrid_decode(reader, width, count)
        return(dictionary[ranks + 1L])
    }
    if (method == 2L) {
        encoded <- new_byte_reader(read_bytes(reader, read_integer(reader)))
        return(as.list(hybrid_decode(encoded, 1L, count) == 1))
    }
    if (method == 3L) return(as.list(delta_decode(reader)))
    lengths <- delta_decode(reader)
    lapply(lengths, function(length) ascii_text(read_bytes(reader, length)))
}

encode_statistics <- function(kind, bounds) {
    if (is.null(bounds)) return(0L)
    output <- 1L
    for (value in bounds) {
        if (kind %in% c("INT", "DATE")) output <- c(
            output,
            zigzag_bytes(value)
        ) else if (kind == "STRING") output <- c(
            output,
            uleb_bytes(nchar(value)),
            ascii_bytes(value)
        ) else output <- c(output, as.integer(value))
    }
    output
}

decode_statistics <- function(reader, kind) {
    if (read_byte(reader) == 0L) return(NULL)
    lapply(1:2, function(index) {
        if (kind %in% c("INT", "DATE")) return(read_zigzag(reader))
        if (kind == "STRING") return(ascii_text(read_bytes(reader, read_uleb(reader))))
        read_byte(reader) == 1L
    })
}
