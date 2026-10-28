source("bitstream.R")
source("reed_solomon.R")
source("matrix.R")
source("masking.R")
source("render.R")

QR_LEVELS <- c("L", "M", "Q", "H")
QR_MODES <- c("NUMERIC", "ALPHANUMERIC", "BYTE")
QR_INDICATORS <- c(NUMERIC = 1L, ALPHANUMERIC = 2L, BYTE = 4L)
QR_ERROR_KINDS <- c("level", "mode", "version", "mask", "text", "charset", "capacity")

count_width <- function(mode, version) {
    widths <- if (version == 10L) c(12L, 11L, 16L) else c(10L, 9L, 8L)
    widths[match(mode, QR_MODES)]
}

data_width <- function(mode, count) {
    if (mode == "NUMERIC") return(10L * (count %/% 3L) + c(0L, 4L, 7L)[count %% 3L + 1L])
    if (mode == "ALPHANUMERIC") return(11L * (count %/% 2L) + 6L * (count %% 2L))
    8L * count
}

encodable <- function(mode, character) {
    if (mode == "NUMERIC") return(character >= "0" && character <= "9")
    if (mode == "ALPHANUMERIC") return(character %in% QR_ALPHANUMERIC)
    code <- utf8ToInt(character)
    code >= 32L && code <= 126L
}

text_characters <- function(text) strsplit(text, "", fixed = TRUE)[[1L]]
segment_width <- function(mode, text, version) 4L + count_width(mode, version) + data_width(mode, nchar(text))

mixed_segments <- function(text, version) {
    characters <- text_characters(text)
    invalid <- lapply(
        QR_MODES,
        function(mode) c(0L, cumsum(!vapply(characters, encodable, FALSE, mode = mode)))
    )
    names(invalid) <- QR_MODES
    costs <- integer(length(characters) + 1L)
    choices <- vector("list", length(characters))
    for (stop in seq_along(characters)) {
        best <- .Machine$integer.max
        for (start in seq_len(stop) - 1L) for (mode in QR_MODES) {
            if (invalid[[mode]][stop + 1L] != invalid[[mode]][start + 1L]) next
            cost <- costs[start + 1L] + 4L + count_width(mode, version) + data_width(mode, stop - start)
            if (cost < best) {
                best <- cost
                choices[[stop]] <- list(start = start, mode = mode)
            }
        }
        costs[stop + 1L] <- best
    }
    segments <- list()
    stop <- length(characters)
    while (stop > 0L) {
        choice <- choices[[stop]]
        segments[[length(segments) + 1L]] <- list(
            mode = choice$mode,
            text = substr(text, choice$start + 1L, stop)
        )
        stop <- choice$start
    }
    list(segments = rev(segments), bits = tail(costs, 1L))
}

assemble_bits <- function(segments, version) {
    writer <- new_bit_writer()
    lines <- character()
    for (segment in segments) {
        mode <- segment$mode
        text <- segment$text
        indicator <- QR_INDICATORS[[mode]]
        width <- count_width(mode, version)
        write_bits(writer, indicator, 4L)
        write_bits(writer, nchar(text), width)
        lines <- c(
            lines,
            sprintf(
                "segment %s indicator %s count %d %s",
                mode,
                binary_digits(indicator, 4L),
                nchar(text),
                binary_digits(nchar(text), width)
            )
        )
        step <- switch(mode, NUMERIC = 3L, ALPHANUMERIC = 2L, BYTE = 1L)
        for (start in seq.int(1L, nchar(text), by = step)) {
            characters <- substr(text, start, min(nchar(text), start + step - 1L))
            if (mode == "NUMERIC") {
                value <- as.integer(characters)
                group_width <- c(0L, 4L, 7L, 10L)[nchar(characters) + 1L]
            } else if (mode == "ALPHANUMERIC") {
                value <- QR_ALPHA_VALUES[[substr(characters, 1L, 1L)]]
                group_width <- 6L
                if (nchar(characters) == 2L) {
                    value <- 45L * value + QR_ALPHA_VALUES[[substr(characters, 2L, 2L)]]
                    group_width <- 11L
                }
            } else {
                value <- utf8ToInt(characters)
                group_width <- 8L
            }
            digits <- binary_digits(value, group_width)
            write_bits(writer, value, group_width)
            lines <- c(lines, sprintf('group %d %s "%s"', value, digits, characters))
        }
    }
    list(bits = bit_value(writer), trace = lines)
}

pad_bits <- function(bits, capacity) {
    terminator <- min(4L, capacity - nchar(bits))
    padded <- paste0(bits, strrep("0", terminator))
    zero_fill <- (-nchar(padded)) %% 8L
    padded <- paste0(padded, strrep("0", zero_fill))
    pad_count <- (capacity - nchar(padded)) %/% 8L
    padding <- if (pad_count) paste0(
        ifelse((seq_len(pad_count) - 1L) %% 2L == 0L, "11101100", "00010001"),
        collapse = ""
    ) else ""
    list(bits = paste0(padded, padding), padding = c(terminator, zero_fill, pad_count))
}

block_layout <- function(degree, first_count, first_size, second_count, second_size) {
    lengths <- c(rep(first_size, first_count), rep(second_size, second_count))
    placement <- list()
    for (index in seq_len(max(lengths))) for (block in seq_along(lengths)) {
        if (index <= lengths[block]) placement[[length(placement) + 1L]] <- c(block, index)
    }
    for (offset in seq_len(degree)) for (block in seq_along(lengths)) {
        placement[[length(placement) + 1L]] <- c(block, lengths[block] + offset)
    }
    data <- sum(lengths)
    list(
        degree = degree,
        lengths = lengths,
        placement = do.call(rbind, placement),
        count = length(lengths),
        data = data,
        capacity = 8L * data,
        total = data + degree * length(lengths)
    )
}

encode_blocks <- function(data, layout) {
    blocks <- list()
    start <- 1L
    for (count in layout$lengths) {
        words <- data[start:(start + count - 1L)]
        blocks[[length(blocks) + 1L]] <- c(words, rs_parity(words, layout$degree))
        start <- start + count
    }
    interleaved <- vapply(seq_len(nrow(layout$placement)), function(index) {
        blocks[[layout$placement[index, 1L]]][layout$placement[index, 2L]]
    }, 0L)
    list(blocks = blocks, codewords = interleaved)
}

deinterleave <- function(words, layout) {
    blocks <- lapply(layout$lengths, function(count) integer(count + layout$degree))
    for (index in seq_along(words)) {
        blocks[[layout$placement[index, 1L]]][layout$placement[index, 2L]] <- words[index]
    }
    blocks
}

new_request <- function(fields, text) {
    request <- new.env(parent = emptyenv())
    for (index in seq_along(fields)) request[[c(
        "identifier",
        "level_token",
        "mode_token",
        "version_token",
        "mask_token"
    )[index]]] <- fields[index]
    request$text <- text
    request$splits <- new.env(parent = emptyenv())
    request$mode <- request$level <- ""
    request$version <- 0L
    request$segments <- list()
    request$bit_count <- 0L
    request$boosted <- FALSE
    request
}

split_request <- function(request, version) {
    category <- if (version == 10L) "10" else "1"
    if (!exists(category, request$splits, inherits = FALSE)) {
        request$splits[[category]] <- if (request$mode == "MIXED") mixed_segments(
            request$text,
            version
        ) else list(
            segments = list(list(mode = request$mode, text = request$text)),
            bits = segment_width(request$mode, request$text, version)
        )
    }
    request$splits[[category]]
}

new_codec <- function(tables, alignments) {
    codec <- new.env(parent = emptyenv())
    codec$tables <- tables
    codec$alignments <- alignments
    codec$geometries <- new.env(parent = emptyenv())
    codec$formats <- list()
    for (level in QR_LEVELS) for (mask in 0:7) codec$formats[[length(codec$formats) + 1L]] <- list(
        value = format_information(level, mask),
        level = level,
        mask = mask
    )
    codec$versions <- lapply(
        7:40,
        function(version) list(value = version_information(version), version = version)
    )
    codec
}

table_layout <- function(codec, version, level) codec$tables[[paste(version, level)]]

geometry <- function(codec, version) {
    key <- as.character(version)
    if (!exists(key, codec$geometries, inherits = FALSE)) {
        pattern <- function_matrix(version, codec$alignments[[key]])
        order <- reading_order(pattern$areas)
        indices <- matrix(-1L, nrow(pattern$symbol), ncol(pattern$symbol))
        for (index in seq_len(nrow(order))) indices[
            order[index, 2L] + 1L,
            order[index, 1L] + 1L
        ] <- index - 1L
        codec$geometries[[key]] <- list(
            symbol = pattern$symbol,
            areas = pattern$areas,
            order = order,
            indices = indices,
            side = nrow(pattern$symbol),
            data_modules = nrow(order),
            function_modules = length(pattern$symbol) - nrow(order)
        )
    }
    codec$geometries[[key]]
}

prepare_request <- function(request, codec) {
    if (!request$level_token %in% c(
        QR_LEVELS,
        paste0(QR_LEVELS, "+")
    )) return(paste("level", request$level_token))
    if (!request$mode_token %in% c(QR_MODES, "AUTO", "MIXED")) return(paste("mode", request$mode_token))
    if (!request$version_token %in% c("AUTO", as.character(1:10))) return(paste(
        "version",
        request$version_token
    ))
    if (!request$mask_token %in% c("AUTO", as.character(0:7))) return(paste("mask", request$mask_token))
    if (!nzchar(request$text)) return("text")
    characters <- text_characters(request$text)
    if (request$mode_token %in% c("NUMERIC", "ALPHANUMERIC")) {
        for (index in seq_along(characters)) {
            if (!encodable(
                request$mode_token,
                characters[index]
            )) return(paste("charset position", index - 1L))
        }
    }
    request$mode <- request$mode_token
    if (request$mode == "AUTO") {
        request$mode <- QR_MODES[which(vapply(
            QR_MODES,
            function(mode) all(vapply(characters, encodable, FALSE, mode = mode)),
            FALSE
        ))[1L]]
    }
    base_level <- substr(request$level_token, 1L, 1L)
    candidates <- if (request$version_token == "AUTO") 1:10 else as.integer(request$version_token)
    bits <- capacity <- 0L
    for (version in candidates) {
        bits <- split_request(request, version)$bits
        capacity <- table_layout(codec, version, base_level)$capacity
        if (bits <= capacity) {
            request$version <- version
            break
        }
    }
    if (request$version == 0L) return(sprintf("capacity bits %d capacity %d", bits, capacity))
    chosen <- split_request(request, request$version)
    request$segments <- chosen$segments
    request$bit_count <- chosen$bits
    request$level <- base_level
    if (endsWith(request$level_token, "+")) {
        for (level in QR_LEVELS[match(base_level, QR_LEVELS):length(QR_LEVELS)]) {
            if (request$bit_count <= table_layout(
                codec,
                request$version,
                level
            )$capacity) request$level <- level
        }
    }
    request$boosted <- request$level != base_level
    NULL
}

read_inputs <- function() {
    requests <- lapply(readLines("input/requests.txt", warn = FALSE), function(line) {
        colon <- regexpr(":", line, fixed = TRUE)[1L]
        new_request(
            strsplit(substr(line, 1L, colon - 1L), " ", fixed = TRUE)[[1L]],
            substr(line, colon + 1L, nchar(line))
        )
    })
    params <- list()
    for (line in readLines("input/params.txt", warn = FALSE)) {
        fields <- strsplit(line, " ", fixed = TRUE)[[1L]]
        params[[fields[1L]]] <- as.integer(fields[2L])
    }
    tables <- alignments <- list()
    for (line in readLines("input/tables.txt", warn = FALSE)) {
        fields <- strsplit(line, " ", fixed = TRUE)[[1L]]
        if (fields[1L] == "block") {
            tables[[paste(fields[2L], fields[3L])]] <- do.call(
                block_layout,
                as.list(as.integer(fields[4L:length(fields)]))
            )
        } else {
            alignments[fields[2L]] <- list(as.integer(fields[-c(1L, 2L)]))
        }
    }
    damage <- list()
    for (line in readLines("input/damage.txt", warn = FALSE)) {
        fields <- strsplit(line, " ", fixed = TRUE)[[1L]]
        operation <- fields[2L]
        arguments <- if (operation == "flip") as.integer(fields[3:4]) else if (operation == "fill") c(
            as.integer(fields[3:6]),
            as.integer(fields[7L] == "dark")
        ) else integer()
        identifier <- fields[1L]
        damage[[identifier]] <- c(
            damage[[identifier]],
            list(list(operation = operation, arguments = arguments))
        )
    }
    lines <- readLines("input/scans.txt", warn = FALSE)
    scans <- list()
    index <- 1L
    while (index <= length(lines)) {
        name <- strsplit(lines[index], " ", fixed = TRUE)[[1L]][2L]
        side <- nchar(lines[index + 1L])
        symbol <- matrix(0L, side, side)
        for (y in seq_len(side)) symbol[y, ] <- as.integer(text_characters(lines[index + y]) == "#")
        scans[[length(scans) + 1L]] <- list(name = name, symbol = symbol)
        index <- index + side + 1L
    }
    list(
        requests = requests,
        params = params,
        tables = tables,
        alignments = alignments,
        damage = damage,
        scans = scans
    )
}

encode_request <- function(request, codec) {
    layout <- geometry(codec, request$version)
    blockspec <- table_layout(codec, request$version, request$level)
    assembled <- assemble_bits(request$segments, request$version)
    padded <- pad_bits(assembled$bits, blockspec$capacity)
    words <- encode_blocks(bits_codewords(padded$bits), blockspec)
    unmasked <- layout$symbol
    bits <- text_characters(codeword_bits(words$codewords))
    for (index in seq_along(bits)) {
        unmasked[layout$order[index, 2L] + 1L, layout$order[index, 1L] + 1L] <- as.integer(bits[index] == "1")
    }
    candidates <- penalties <- list()
    for (mask in 0:7) {
        symbol <- apply_mask(unmasked, layout$order, mask)
        for (positions in format_positions(layout$side)) symbol <- write_matrix_value(
            symbol,
            positions,
            format_information(request$level, mask)
        )
        candidates[[mask + 1L]] <- symbol
        penalties[[mask + 1L]] <- mask_penalties(symbol)
    }
    mask <- if (request$mask_token == "AUTO") which.min(vapply(
        penalties,
        sum,
        0
    )) - 1L else as.integer(request$mask_token)
    symbol <- candidates[[mask + 1L]]
    list(
        request = request,
        layout = layout,
        blockspec = blockspec,
        raw_bits = assembled$bits,
        trace = assembled$trace,
        padded_bits = padded$bits,
        padding = padded$padding,
        blocks = words$blocks,
        codewords = words$codewords,
        penalties = penalties,
        mask = mask,
        symbol = symbol,
        dark = sum(symbol)
    )
}

codes_lines <- function(encoding, codec) {
    request <- encoding$request
    layout <- encoding$layout
    blocks <- encoding$blockspec
    version <- request$version
    level <- request$level
    lines <- sprintf("symbol version %d level %s mask %d size %d", version, level, encoding$mask, layout$side)
    segments <- paste(
        vapply(request$segments, function(segment) paste0(segment$mode, ":", nchar(segment$text)), ""),
        collapse = " "
    )
    lines <- c(lines, sprintf("segments %d %s", length(request$segments), segments))
    alternatives <- character()
    for (mode in QR_MODES) {
        possible <- all(vapply(text_characters(request$text), encodable, FALSE, mode = mode))
        value <- if (possible) as.character(segment_width(mode, request$text, version)) else "-"
        alternatives <- c(alternatives, paste(mode, value))
    }
    mixed_bits <- if (request$mode == "MIXED") request$bit_count else mixed_segments(
        request$text,
        version
    )$bits
    alternatives <- c(alternatives, paste("MIXED", mixed_bits))
    lines <- c(
        lines,
        sprintf(
            "bits data %d capacity %d alternatives %s",
            request$bit_count,
            blocks$capacity,
            paste(alternatives, collapse = " ")
        )
    )
    fits <- character()
    for (candidate_level in QR_LEVELS) {
        fitting <- "-"
        for (candidate in 1:10) {
            if (split_request(request, candidate)$bits <= table_layout(
                codec,
                candidate,
                candidate_level
            )$capacity) {
                fitting <- as.character(candidate)
                break
            }
        }
        fits <- c(fits, paste(candidate_level, fitting))
    }
    lines <- c(lines, paste("fits", paste(fits, collapse = " ")))
    lines <- c(
        lines,
        sprintf(
            "modules function %d data %d remainder %d dark %d",
            layout$function_modules,
            layout$data_modules,
            layout$data_modules - 8L * blocks$total,
            encoding$dark
        )
    )
    version_text <- if (version >= 7L) binary_digits(version_information(version), 18L) else "none"
    lines <- c(
        lines,
        sprintf(
            "format %s version %s",
            binary_digits(format_information(level, encoding$mask), 15L),
            version_text
        )
    )
    for (index in seq_along(encoding$penalties)) {
        penalty <- encoding$penalties[[index]]
        lines <- c(
            lines,
            sprintf(
                "penalty %d n1 %d n2 %d n3 %d n4 %d total %d",
                index - 1L,
                penalty[1L],
                penalty[2L],
                penalty[3L],
                penalty[4L],
                sum(penalty)
            )
        )
    }
    c(lines, symbol_lines(encoding$symbol))
}

codeword_lines <- function(encoding) {
    request <- encoding$request
    layout <- encoding$blockspec
    lines <- sprintf(
        "request %s version %d level %s blocks %d data %d ec_per_block %d total %d",
        request$identifier,
        request$version,
        request$level,
        layout$count,
        layout$data,
        layout$degree,
        layout$total
    )
    for (index in seq_along(encoding$blocks)) {
        words <- encoding$blocks[[index]]
        count <- layout$lengths[index]
        lines <- c(
            lines,
            sprintf("block %d data %s", index - 1L, hex_words(words[seq_len(count)])),
            sprintf("block %d ec %s", index - 1L, hex_words(words[(count + 1L):length(words)]))
        )
    }
    c(lines, paste("interleaved", hex_words(encoding$codewords)))
}

bitstream_lines <- function(encoding) {
    request <- encoding$request
    c(
        sprintf(
            "request %s version %d bits %d capacity %d",
            request$identifier,
            request$version,
            request$bit_count,
            encoding$blockspec$capacity
        ),
        encoding$trace,
        sprintf(
            "terminator %d zero_fill %d pad_bytes %d",
            encoding$padding[1L],
            encoding$padding[2L],
            encoding$padding[3L]
        )
    )
}

read_image <- function(path) {
    lines <- readLines(path, warn = FALSE)
    dimensions <- as.integer(strsplit(lines[2L], " ", fixed = TRUE)[[1L]])
    width <- dimensions[1L]
    height <- dimensions[2L]
    pixels <- matrix(0L, height, width)
    for (y in seq_len(height)) pixels[y, ] <- as.integer(text_characters(lines[y + 2L]))
    dark <- which(pixels == 1L, arr.ind = TRUE)
    left <- min(dark[, 2L]) - 1L
    right <- max(dark[, 2L]) - 1L
    top <- min(dark[, 1L]) - 1L
    run <- 0L
    while (left + run < width && pixels[top + 1L, left + run + 1L] == 1L) run <- run + 1L
    unit <- run %/% 7L
    side <- (right - left + 1L) %/% unit
    symbol <- matrix(0L, side, side)
    for (y in seq_len(side) - 1L) for (x in seq_len(side) - 1L) symbol[y + 1L, x + 1L] <- pixels[
        top + unit * y + 1L,
        left + unit * x + 1L
    ]
    well_formed <- TRUE
    for (y in seq_len(height) - 1L) for (x in seq_len(width) - 1L) {
        expected <- 0L
        if (x >= left && x < left + unit * side && y >= top && y < top + unit * side) expected <- symbol[
            (y - top) %/% unit + 1L,
            (x - left) %/% unit + 1L
        ]
        if (pixels[y + 1L, x + 1L] != expected) well_formed <- FALSE
    }
    status <- if (well_formed) "ok" else "bad"
    list(
        symbol = symbol,
        line = sprintf(
            "image %d %d quiet %d scale %d size %d %s",
            width,
            height,
            left %/% unit,
            unit,
            side,
            status
        )
    )
}

rotate_symbol <- function(symbol) t(symbol[nrow(symbol):1L, , drop = FALSE])

finder_rotation <- function(symbol) {
    side <- nrow(symbol)
    corners <- list(c(side - 7L, side - 7L), c(side - 7L, 0L), c(0L, 0L), c(0L, side - 7L))
    scores <- vapply(corners, function(corner) {
        score <- 0L
        for (y in 0:6) for (x in 0:6) {
            expected <- as.integer(max(abs(x - 3L), abs(y - 3L)) != 2L)
            score <- score + as.integer(symbol[corner[2L] + y + 1L, corner[1L] + x + 1L] == expected)
        }
        score
    }, 0L)
    which.min(scores) - 1L
}

new_attempt <- function() {
    attempt <- new.env(parent = emptyenv())
    attempt$lines <- character()
    attempt$text <- NULL
    attempt$blocks <- list()
    attempt
}

read_segment <- function(reader, mode, count) {
    characters <- character()
    while (count > 0L) {
        if (mode == "NUMERIC") {
            group_size <- min(3L, count)
            value <- read_bits(reader, c(0L, 4L, 7L, 10L)[group_size + 1L])
            if (value >= 10L^group_size) return(NULL)
            characters <- c(characters, sprintf(paste0("%0", group_size, "d"), value))
        } else if (mode == "ALPHANUMERIC") {
            group_size <- min(2L, count)
            value <- read_bits(reader, if (group_size == 2L) 11L else 6L)
            if (value >= if (group_size == 2L) 2025L else 45L) return(NULL)
            if (group_size == 2L) characters <- c(characters, QR_ALPHANUMERIC[value %/% 45L + 1L])
            characters <- c(characters, QR_ALPHANUMERIC[value %% 45L + 1L])
        } else {
            group_size <- 1L
            value <- read_bits(reader, 8L)
            if (value < 32L || value > 126L) return(NULL)
            characters <- c(characters, intToUtf8(value))
        }
        count <- count - group_size
    }
    paste0(characters, collapse = "")
}

parse_data <- function(attempt, bits, version) {
    reader <- new_bit_reader(bits)
    text <- character()
    stop <- 0L
    while (remaining_bits(reader) >= 4L) {
        indicator <- read_bits(reader, 4L)
        if (indicator == 0L) break
        if (!indicator %in% QR_INDICATORS) {
            attempt$lines <- c(attempt$lines, paste("parse failed indicator", binary_digits(indicator, 4L)))
            return(invisible(NULL))
        }
        mode <- names(QR_INDICATORS)[match(indicator, QR_INDICATORS)]
        width <- count_width(mode, version)
        if (remaining_bits(reader) < width) {
            attempt$lines <- c(attempt$lines, paste("parse failed length", mode))
            return(invisible(NULL))
        }
        count <- read_bits(reader, width)
        if (remaining_bits(reader) < data_width(mode, count)) {
            attempt$lines <- c(attempt$lines, paste("parse failed length", mode))
            return(invisible(NULL))
        }
        segment <- read_segment(reader, mode, count)
        if (is.null(segment)) {
            attempt$lines <- c(attempt$lines, paste("parse failed value", mode))
            return(invisible(NULL))
        }
        text <- c(text, segment)
        attempt$lines <- c(attempt$lines, paste("segment", mode, count))
        stop <- reader$position
    }
    expected <- pad_bits(substr(bits, 1L, stop), nchar(bits))$bits
    attempt$lines <- c(attempt$lines, paste("padding", if (expected == bits) "ok" else "bad"))
    attempt$text <- paste0(text, collapse = "")
    attempt$lines <- c(attempt$lines, sprintf('text "%s"', attempt$text))
}

bit_distance <- function(left, right) sum(as.integer(intToBits(bitwXor(left, right))))

nearest_information <- function(values, value) {
    values[[which.min(vapply(values, function(item) bit_distance(value, item$value), 0L))]]
}

decode_attempt <- function(codec, symbol) {
    attempt <- new_attempt()
    side <- nrow(symbol)
    version <- (side - 17L) %/% 4L
    values <- vapply(format_positions(side), read_matrix_value, 0L, symbol = symbol)
    first <- nearest_information(codec$formats, values[1L])
    second <- nearest_information(codec$formats, values[2L])
    d1 <- bit_distance(values[1L], first$value)
    d2 <- bit_distance(values[2L], second$value)
    prefix <- sprintf(
        "format %s %s distance %d %d",
        binary_digits(values[1L], 15L),
        binary_digits(values[2L], 15L),
        d1,
        d2
    )
    chosen <- if (d2 < d1) second else first
    if (min(d1, d2) > 3L) {
        attempt$lines <- c(attempt$lines, paste(prefix, "unreadable"))
        return(attempt)
    }
    level <- chosen$level
    mask <- chosen$mask
    attempt$lines <- c(attempt$lines, sprintf("%s level %s mask %d", prefix, level, mask))
    if (version >= 7L) {
        values <- vapply(version_positions(side), read_matrix_value, 0L, symbol = symbol)
        first <- nearest_information(codec$versions, values[1L])
        second <- nearest_information(codec$versions, values[2L])
        d1 <- bit_distance(values[1L], first$value)
        d2 <- bit_distance(values[2L], second$value)
        prefix <- sprintf(
            "version %s %s distance %d %d",
            binary_digits(values[1L], 18L),
            binary_digits(values[2L], 18L),
            d1,
            d2
        )
        chosen <- if (d2 < d1) second else first
        if (min(d1, d2) > 3L) {
            attempt$lines <- c(attempt$lines, paste(prefix, "unreadable"))
            return(attempt)
        }
        attempt$lines <- c(attempt$lines, paste(prefix, "decoded", chosen$version))
        if (chosen$version != version) return(attempt)
    }
    shape <- geometry(codec, version)
    layout <- table_layout(codec, version, level)
    unmasked <- apply_mask(symbol, shape$order, mask)
    bits <- paste0(
        vapply(
            seq_len(8L * layout$total),
            function(index) as.character(unmasked[shape$order[index, 2L] + 1L, shape$order[index, 1L] + 1L]),
            ""
        ),
        collapse = ""
    )
    blocks <- deinterleave(bits_codewords(bits), layout)
    corrected_blocks <- vector("list", length(blocks))
    failed <- FALSE
    for (index in seq_along(blocks)) {
        correction <- rs_correct(blocks[[index]], layout$degree)
        prefix <- sprintf("block %d syndromes %s", index - 1L, hex_words(correction$syndromes))
        if (is.null(correction$corrected)) {
            status <- "failed"
            attempt$lines <- c(attempt$lines, paste(prefix, "failed"))
            failed <- TRUE
        } else if (length(correction$positions)) {
            status <- "corrected"
            attempt$lines <- c(
                attempt$lines,
                paste(prefix, "corrected", paste(correction$positions, collapse = " "))
            )
        } else {
            status <- "ok"
            attempt$lines <- c(attempt$lines, paste(prefix, "ok"))
        }
        attempt$blocks[[length(attempt$blocks) + 1L]] <- list(
            status = status,
            positions = length(correction$positions)
        )
        corrected_blocks[index] <- list(correction$corrected)
    }
    if (failed) return(attempt)
    data <- unlist(
        lapply(
            seq_along(corrected_blocks),
            function(index) corrected_blocks[[index]][seq_len(layout$lengths[index])]
        ),
        use.names = FALSE
    )
    parse_data(attempt, codeword_bits(data), version)
    attempt
}

decode_symbol <- function(codec, symbol) {
    rotations <- finder_rotation(symbol)
    oriented <- symbol
    for (index in seq_len(rotations)) oriented <- rotate_symbol(oriented)
    adopted <- decode_attempt(codec, oriented)
    mirrored <- FALSE
    if (is.null(adopted$text)) {
        second <- decode_attempt(codec, t(oriented))
        if (!is.null(second$text)) {
            adopted <- second
            mirrored <- TRUE
        }
    }
    adopted$lines <- c(
        sprintf("orientation rotations %d mirrored %s", rotations, if (mirrored) "yes" else "no"),
        adopted$lines
    )
    adopted
}

damaged_symbol <- function(encoding, operations) {
    symbol <- encoding$symbol
    for (entry in operations) {
        arguments <- entry$arguments
        if (entry$operation == "flip") {
            symbol[arguments[2L] + 1L, arguments[1L] + 1L] <- bitwXor(
                symbol[arguments[2L] + 1L, arguments[1L] + 1L],
                1L
            )
        } else if (entry$operation == "fill") {
            symbol[
                seq.int(arguments[2L] + 1L, length.out = arguments[4L]),
                seq.int(arguments[1L] + 1L, length.out = arguments[3L])
            ] <- arguments[5L]
        }
    }
    kinds <- c("function", "format", "version", "data", "remainder")
    counts <- setNames(integer(length(kinds)), kinds)
    damaged_words <- rep(list(integer()), encoding$blockspec$count)
    for (y in seq_len(encoding$layout$side)) for (x in seq_len(encoding$layout$side)) {
        if (symbol[y, x] == encoding$symbol[y, x]) next
        area <- encoding$layout$areas[y, x]
        if (area != QR_DATA) {
            counts[kinds[area]] <- counts[kinds[area]] + 1L
        } else {
            index <- encoding$layout$indices[y, x]
            if (index < 8L * encoding$blockspec$total) {
                counts["data"] <- counts["data"] + 1L
                placement <- encoding$blockspec$placement[index %/% 8L + 1L, ]
                damaged_words[[placement[1L]]] <- union(damaged_words[[placement[1L]]], placement[2L])
            } else {
                counts["remainder"] <- counts["remainder"] + 1L
            }
        }
    }
    for (entry in operations) {
        if (entry$operation == "rotate") symbol <- rotate_symbol(symbol)
        if (entry$operation == "mirror") symbol <- t(symbol)
    }
    details <- paste(paste(kinds, counts), collapse = " ")
    errors <- paste(lengths(damaged_words), collapse = " ")
    list(
        symbol = symbol,
        lines = c(
            sprintf("check damaged operations %d", length(operations)),
            sprintf("damage changed %d %s", sum(counts), details),
            sprintf("errors %s limit %d", errors, encoding$blockspec$degree %/% 2L)
        )
    )
}

damage_tolerance <- function(encoding, codec, color) {
    side <- encoding$layout$side
    for (span in seq_len(side)) {
        symbol <- encoding$symbol
        start <- (side - span) %/% 2L
        symbol[(start + 1L):(start + span), (start + 1L):(start + span)] <- color
        attempt <- decode_symbol(codec, symbol)
        if (is.null(attempt$text) || attempt$text != encoding$request$text) return(span - 1L)
    }
    side
}

new_summary <- function() {
    summary <- new.env(parent = emptyenv())
    for (group in c(
        "totals",
        "errors",
        "modes",
        "levels",
        "versions",
        "masks",
        "checks",
        "blocks",
        "scans"
    )) summary[[group]] <- new.env(parent = emptyenv())
    summary
}

counter <- function(summary, group, key) {
    value <- summary[[group]][[as.character(key)]]
    if (is.null(value)) 0L else value
}

increment <- function(summary, group, key, amount = 1L) {
    summary[[group]][[as.character(key)]] <- counter(summary, group, key) + amount
}

record_encoding <- function(summary, encoding) {
    request <- encoding$request
    layout <- encoding$blockspec
    increment(summary, "totals", "encoded")
    increment(summary, "modes", request$mode)
    increment(summary, "levels", request$level)
    increment(summary, "versions", request$version)
    increment(summary, "masks", encoding$mask)
    amounts <- c(
        boosted = as.integer(request$boosted),
        segments = length(request$segments),
        data = layout$data,
        ec = layout$degree * layout$count,
        modules = encoding$layout$side^2L,
        dark = encoding$dark
    )
    for (key in names(amounts)) increment(summary, "totals", key, amounts[[key]])
}

record_check <- function(summary, attempt, text) {
    result <- if (is.null(attempt$text)) "failed" else if (attempt$text == text) "ok" else "mismatch"
    increment(summary, "checks", result)
    for (block in attempt$blocks) {
        increment(summary, "blocks", block$status)
        increment(summary, "totals", "corrected_positions", block$positions)
    }
    result
}

summary_lines <- function(summary, request_count) {
    total <- function(key) counter(summary, "totals", key)
    pairs <- function(group, keys) paste(
        vapply(keys, function(key) paste(key, counter(summary, group, key)), ""),
        collapse = " "
    )
    group_sum <- function(group) sum(unlist(as.list(summary[[group]]), use.names = FALSE))
    c(sprintf("requests %d encoded %d errors %d", request_count, total("encoded"), group_sum("errors")),
      paste("error_kinds", pairs("errors", QR_ERROR_KINDS)),
      paste("modes", pairs("modes", c(QR_MODES, "MIXED"))),
      sprintf("levels %s boosted %d", pairs("levels", QR_LEVELS), total("boosted")),
      paste(
          "versions",
          paste(vapply(1:10, function(version) counter(summary, "versions", version), 0L), collapse = " ")
      ),
      paste("masks", paste(vapply(0:7, function(mask) counter(summary, "masks", mask), 0L), collapse = " ")),
      sprintf("segments %d data_codewords %d ec_codewords %d", total("segments"), total("data"), total("ec")),
      sprintf("modules %d dark %d", total("modules"), total("dark")),
      sprintf("checks %d %s", group_sum("checks"), pairs("checks", c("ok", "mismatch", "failed"))),
      sprintf(
          "blocks %s codewords %d",
          pairs("blocks", c("ok", "corrected", "failed")),
          total("corrected_positions")
      ),
      sprintf(
          "scans %d decoded %d failed %d",
          group_sum("scans"),
          counter(summary, "scans", "decoded"),
          counter(summary, "scans", "failed")
      ))
}

check_lines <- function(encoding, codec, params, operations, summary) {
    request <- encoding$request
    path <- paste0("output/qr_", request$identifier, ".pbm")
    writeChar(pbm_text(encoding$symbol, params$quiet_zone, params$scale), path, eos = NULL, useBytes = TRUE)
    image <- read_image(path)
    lines <- c(paste("request", request$identifier), image$line, "check clean")
    attempt <- decode_symbol(codec, image$symbol)
    lines <- c(lines, attempt$lines, paste("result", record_check(summary, attempt, request$text)))
    if (length(operations)) {
        damaged <- damaged_symbol(encoding, operations)
        attempt <- decode_symbol(codec, damaged$symbol)
        lines <- c(
            lines,
            damaged$lines,
            attempt$lines,
            paste("result", record_check(summary, attempt, request$text))
        )
    }
    light <- damage_tolerance(encoding, codec, 0L)
    dark <- damage_tolerance(encoding, codec, 1L)
    c(lines, sprintf("tolerance light %d dark %d", light, dark))
}

capacity_lines <- function(codec) {
    lines <- character()
    for (version in 1:10) {
        shape <- geometry(codec, version)
        total <- table_layout(codec, version, "L")$total
        centers <- codec$alignments[[as.character(version)]]
        alignment <- if (length(centers)) paste(centers, collapse = " ") else "none"
        lines <- c(
            lines,
            sprintf(
                "version %d size %d data_modules %d codewords %d remainder %d alignment %s",
                version,
                shape$side,
                shape$data_modules,
                total,
                shape$data_modules - 8L * total,
                alignment
            )
        )
        for (level in QR_LEVELS) {
            layout <- table_layout(codec, version, level)
            maxima <- vapply(QR_MODES, function(mode) {
                count <- 0L
                while (4L + count_width(mode, version) + data_width(
                    mode,
                    count + 1L
                ) <= layout$capacity) count <- count + 1L
                count
            }, 0L)
            lines <- c(
                lines,
                sprintf(
                    "level %s blocks %d data %d ec_per_block %d numeric %d alphanumeric %d byte %d",
                    level,
                    layout$count,
                    layout$data,
                    layout$degree,
                    maxima[1L],
                    maxima[2L],
                    maxima[3L]
                )
            )
        }
    }
    lines
}

main <- function() {
    input <- read_inputs()
    codec <- new_codec(input$tables, input$alignments)
    summary <- new_summary()
    dir.create("output", showWarnings = FALSE)
    reports <- setNames(
        rep(list(character()), 5L),
        c("codes", "codewords", "bitstream", "selfcheck", "scans")
    )
    for (request in input$requests) {
        reports$codes <- c(reports$codes, paste("request", request$identifier))
        error <- prepare_request(request, codec)
        if (!is.null(error)) {
            reports$codes <- c(reports$codes, paste("error", error))
            increment(summary, "errors", strsplit(error, " ", fixed = TRUE)[[1L]][1L])
            next
        }
        encoding <- encode_request(request, codec)
        reports$codes <- c(reports$codes, codes_lines(encoding, codec))
        reports$codewords <- c(reports$codewords, codeword_lines(encoding))
        reports$bitstream <- c(reports$bitstream, bitstream_lines(encoding))
        record_encoding(summary, encoding)
        reports$selfcheck <- c(
            reports$selfcheck,
            check_lines(encoding, codec, input$params, input$damage[[request$identifier]], summary)
        )
    }
    for (scan in input$scans) {
        reports$scans <- c(reports$scans, sprintf("scan %s size %d", scan$name, nrow(scan$symbol)))
        attempt <- decode_symbol(codec, scan$symbol)
        result <- if (is.null(attempt$text)) "failed" else "decoded"
        reports$scans <- c(reports$scans, attempt$lines, paste("result", result))
        increment(summary, "scans", result)
    }
    reports$capacity <- capacity_lines(codec)
    reports$summary <- summary_lines(summary, length(input$requests))
    for (name in names(reports)) writeLines(reports[[name]], paste0("output/", name, ".txt"), useBytes = TRUE)
}

main()
