options(scipen = 999)
line <- function(...) cat(..., "\n", sep = "")
channel_names <- c("NOTE_OFF", "NOTE_ON", "POLY_PRESSURE", "CONTROL", "PROGRAM", "CHANNEL_PRESSURE", "PITCH_BEND")
meta_names <- c(`0` = "SEQUENCE_NUMBER", `1` = "TEXT_EVENT", `2` = "COPYRIGHT", `3` = "TRACK_NAME", `4` = "INSTRUMENT_NAME", `5` = "LYRIC", `6` = "MARKER", `7` = "CUE_POINT", `32` = "CHANNEL_PREFIX", `47` = "END_OF_TRACK", `81` = "TEMPO", `84` = "SMPTE_OFFSET", `88` = "TIME_SIGNATURE", `89` = "KEY_SIGNATURE", `127` = "SEQUENCER_SPECIFIC")
key_names <- list(
    c("Cb", "Gb", "Db", "Ab", "Eb", "Bb", "F", "C", "G", "D", "A", "E", "B", "F#", "C#"),
    c("Ab", "Eb", "Bb", "F", "C", "G", "D", "A", "E", "B", "F#", "C#", "G#", "D#", "A#")
)
event <- function(tick, status, data = numeric(), meta = 0) list(tick = tick, status = status, data = data, meta = meta)
eot <- function(tick) event(tick, 255, meta = 47)
channel <- function(e) e$status %% 16 + 1
is_meta <- function(e, code) e$status == 255 && e$meta == code
is_on <- function(e) e$status %/% 16 == 9 && e$data[2] > 0
is_off <- function(e) e$status %/% 16 == 8 || (e$status %/% 16 == 9 && e$data[2] == 0)
note_name <- function(n) paste0(c("C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B")[n %% 12 + 1], n %/% 12 - 1)
kind <- function(e) {
    if (e$status < 240) return(channel_names[e$status %/% 16 - 7])
    if (e$status == 240) return("SYSEX")
    if (e$status == 247) return("SYSEX_ESCAPE")
    if (as.character(e$meta) %in% names(meta_names)) meta_names[[as.character(e$meta)]] else "META"
}
bigendian <- function(data) {
    result <- 0
    for (b in data) result <- result * 256 + b
    result
}
bytes_be <- function(value, size) {
    result <- numeric(size)
    for (i in seq(size, 1L)) {
        result[i] <- value %% 256
        value <- value %/% 256
    }
    result
}
summary_song <- function(s) {
    paste("format", s$format, "tracks", length(s$tracks), "division", s$division, "events", sum(lengths(s$tracks)))
}
song_length <- function(s) max(vapply(s$tracks, function(track) track[[length(track)]]$tick, numeric(1)))
ordered <- function(s) {
    items <- list()
    for (t in seq_along(s$tracks)) {
        for (i in seq_along(s$tracks[[t]])) {
            items[[length(items) + 1L]] <- list(event = s$tracks[[t]][[i]], track = t - 1L, index = i, order = 0)
        }
    }
    ticks <- vapply(items, function(p) p$event$tick, numeric(1))
    items <- items[order(ticks, seq_along(items))]
    for (i in seq_along(items)) items[[i]]$order <- i
    items
}
event_line <- function(e, track) {
    fields <- c(e$tick, track, kind(e))
    d <- e$data
    if (e$status < 240) {
        fields <- c(fields, channel(e))
        high <- e$status %/% 16
        if (high %in% c(8, 9, 10)) {
            fields <- c(fields, note_name(d[1]), d[2])
        } else if (high == 14) {
            fields <- c(fields, d[1] + 128 * d[2] - 8192)
        } else {
            fields <- c(fields, d)
        }
    } else if (e$status == 255 && e$meta >= 1 && e$meta <= 7) {
        text <- if (length(d)) rawToChar(as.raw(d)) else ""
        fields <- c(fields, paste0('"', text, '"'))
    } else if (is_meta(e, 0) || is_meta(e, 81)) {
        fields <- c(fields, bigendian(d))
    } else if (is_meta(e, 32)) {
        fields <- c(fields, d[1] + 1)
    } else if (is_meta(e, 47)) {
        # No fields.
    } else if (is_meta(e, 84)) {
        fields <- c(fields, d)
    } else if (is_meta(e, 88)) {
        fields <- c(fields, paste0(d[1], "/", 2^d[2]), d[3:4])
    } else if (is_meta(e, 89)) {
        sf <- if (d[1] >= 128) d[1] - 256 else d[1]
        fields <- c(fields, key_names[[d[2] + 1]][sf + 8], if (d[2] == 0) "major" else "minor")
    } else {
        if (e$status == 255 && e$meta != 127) fields <- c(fields, sprintf("%02X", as.integer(e$meta)))
        fields <- c(fields, length(d))
        if (length(d)) fields <- c(fields, paste(sprintf("%02X", as.integer(d)), collapse = ""))
    }
    paste(fields, collapse = " ")
}
parse_failure <- function(pos, reason) {
    stop(structure(list(message = reason, call = NULL, position = pos, reason = reason), class = c("midi_error", "error", "condition")))
}
slice <- function(data, from, to) {
    if (to < from) numeric() else data[seq(from, to)]
}
parse_hex <- function(data) {
    chunk <- function(pos, id) {
        if (length(data) - pos < 8) parse_failure(pos, "truncated chunk")
        if (!identical(as.integer(data[(pos + 1):(pos + 4)]), as.integer(charToRaw(id)))) parse_failure(pos, "bad chunk id")
        len <- bigendian(data[(pos + 5):(pos + 8)])
        if (pos + 8 + len > length(data)) parse_failure(pos, "truncated chunk")
        c(pos + 8, pos + 8 + len)
    }
    bounds <- chunk(0, "MThd")
    if (diff(bounds) != 6) parse_failure(4, "bad header length")
    f <- bigendian(data[9:10])
    count <- bigendian(data[11:12])
    division <- bigendian(data[13:14])
    if (f > 2) parse_failure(8, "bad format")
    if (!count || (f == 0 && count != 1)) parse_failure(10, "bad track count")
    if (division >= 32768) parse_failure(12, "smpte timing not supported")
    if (!division) parse_failure(12, "bad division")
    s <- list(format = f, division = division, tracks = list())
    pos <- bounds[2]
    for (t in seq_len(count)) {
        if (pos == length(data)) parse_failure(pos, "missing track")
        bounds <- chunk(pos, "MTrk")
        pos <- bounds[1]
        finish <- bounds[2]
        tick <- 0
        running <- 0
        track <- list()
        while (pos < finish) {
            if (length(track) && is_meta(track[[length(track)]], 47)) parse_failure(pos, "event after end of track")
            event_start <- pos
            read_byte <- function() {
                if (pos >= finish) parse_failure(event_start, "truncated event")
                pos <<- pos + 1
                data[pos]
            }
            vlq <- function() {
                at <- pos
                result <- 0
                for (i in 1:4) {
                    b <- read_byte()
                    result <- result * 128 + b %% 128
                    if (b < 128) return(result)
                }
                parse_failure(at, "variable-length value too long")
            }
            tick <- tick + vlq()
            status_pos <- pos
            if (pos >= finish) parse_failure(event_start, "truncated event")
            status <- data[pos + 1]
            if (status < 128) {
                if (!running) parse_failure(pos, "data byte without running status")
                status <- running
            } else {
                pos <- pos + 1
            }
            e <- event(tick, status)
            if (status < 240) {
                running <- status
                n <- if (status %/% 16 %in% c(12, 13)) 1L else 2L
                for (j in seq_len(n)) {
                    at <- pos
                    b <- read_byte()
                    if (b >= 128) parse_failure(at, "bad data byte")
                    e$data <- c(e$data, b)
                }
            } else if (status %in% c(240, 247, 255)) {
                running <- 0
                if (status == 255) e$meta <- read_byte()
                len <- vlq()
                if (pos + len > finish) parse_failure(event_start, "truncated event")
                e$data <- slice(data, pos + 1, pos + len)
                pos <- pos + len
                if (status == 255) {
                    sizes <- c(`0` = 2, `32` = 1, `47` = 0, `81` = 3, `84` = 5, `88` = 4, `89` = 2)
                    code <- as.character(e$meta)
                    if (code %in% names(sizes) && sizes[[code]] != len) parse_failure(status_pos, "bad meta length")
                    d <- e$data
                    bad <- e$meta == 81 && bigendian(d) == 0
                    bad <- bad || (e$meta == 32 && d[1] > 15)
                    bad <- bad || (e$meta == 88 && (d[1] == 0 || d[2] > 6))
                    if (e$meta == 89) {
                        sf <- if (d[1] >= 128) d[1] - 256 else d[1]
                        bad <- bad || sf < -7 || sf > 7 || d[2] > 1
                    }
                    if (bad) parse_failure(status_pos, "bad meta data")
                }
            } else {
                parse_failure(status_pos, "unknown status byte")
            }
            track[[length(track) + 1L]] <- e
        }
        if (!length(track) || !is_meta(track[[length(track)]], 47)) parse_failure(finish, "missing end of track")
        s$tracks[[t]] <- track
        pos <- finish
    }
    if (pos < length(data)) parse_failure(pos, "extra data")
    s
}
parse_text <- function(lines) {
    lineno <- 1L
    fail <- function(reason) parse_failure(lineno, reason)
    require <- function(ok) if (!isTRUE(ok)) fail("bad value")
    h <- strsplit(lines[1], " ", fixed = TRUE)[[1]]
    if (length(h) != 4L || h[1] != "HEADER") fail("bad header")
    f <- as.numeric(h[2])
    count <- as.numeric(h[3])
    division <- as.numeric(h[4])
    if (!(f >= 0 && f <= 2 && count >= 1 && count <= 65535 && division >= 1 && division <= 32767 && (f != 0 || count == 1))) fail("bad header")
    s <- list(format = f, division = division, tracks = rep(list(list()), count))
    current <- 1L
    for (i in seq.int(2L, length(lines) + 1L)) {
        if (i > length(lines)) break
        lineno <- i
        text <- lines[i]
        w <- strsplit(text, " ", fixed = TRUE)[[1]]
        tick <- as.numeric(w[1])
        track <- as.numeric(w[2]) + 1
        name <- w[3]
        rest <- if (length(w) > 3L) substring(text, nchar(paste(w[1:3], collapse = " ")) + 2L) else ""
        fields <- if (nzchar(rest)) strsplit(rest, " ", fixed = TRUE)[[1]] else character()
        index <- match(name, channel_names)
        meta <- match(name, meta_names)
        known <- !is.na(meta)
        if (is.na(index) && !known && !(name %in% c("META", "SYSEX", "SYSEX_ESCAPE"))) fail("unknown event type")
        e <- event(tick, 255)
        value <- function(at, lo, hi) {
            require(at <= length(fields))
            n <- as.numeric(fields[at])
            require(n >= lo && n <= hi)
            n
        }
        if (!is.na(index)) {
            n <- if (index %in% c(5, 6, 7)) 2L else 3L
            require(length(fields) == n)
            e$status <- (index + 7) * 16 + value(1, 1, 16) - 1
            if (index <= 3) {
                pitch <- match(fields[2], vapply(0:127, note_name, character(1))) - 1L
                require(!is.na(pitch))
                e$data <- c(pitch, value(3, 0, 127))
            } else if (index == 7) {
                bend <- value(2, -8192, 8191) + 8192
                e$data <- c(bend %% 128, bend %/% 128)
            } else {
                e$data <- vapply(2:n, function(j) value(j, 0, 127), numeric(1))
            }
        } else if (known && as.numeric(names(meta_names)[meta]) %in% 1:7) {
            require(nchar(rest) >= 2L && startsWith(rest, '"') && endsWith(rest, '"'))
            body <- substring(rest, 2L, nchar(rest) - 1L)
            require(!grepl('"', body, fixed = TRUE))
            e$meta <- as.numeric(names(meta_names)[meta])
            e$data <- as.numeric(charToRaw(body))
        } else if (name %in% c("META", "SYSEX", "SYSEX_ESCAPE", "SEQUENCER_SPECIFIC")) {
            if (name == "SYSEX") {
                e$status <- 240
            } else if (name == "SYSEX_ESCAPE") {
                e$status <- 247
            } else if (name == "META") {
                require(length(fields) >= 2L && grepl("^[0-9A-F]{2}$", fields[1]))
                e$meta <- strtoi(fields[1], base = 16L)
                require(!(as.character(e$meta) %in% names(meta_names)))
                fields <- fields[-1]
            } else {
                e$meta <- 127
            }
            len <- value(1, 0, 1000000)
            if (!len) {
                require(length(fields) == 1L)
            } else {
                require(length(fields) == 2L && nchar(fields[2]) == len * 2)
                require(grepl("^[0-9A-F]+$", fields[2]))
                starts <- seq.int(1L, nchar(fields[2]), by = 2L)
                e$data <- strtoi(substring(fields[2], starts, starts + 1L), base = 16L)
            }
        } else {
            e$meta <- as.numeric(names(meta_names)[meta])
            if (e$meta == 0) {
                require(length(fields) == 1L)
                e$data <- bytes_be(value(1, 0, 65535), 2L)
            } else if (e$meta == 32) {
                require(length(fields) == 1L)
                e$data <- value(1, 1, 16) - 1
            } else if (e$meta == 47) {
                require(!length(fields))
            } else if (e$meta == 81) {
                require(length(fields) == 1L)
                e$data <- bytes_be(value(1, 1, 16777215), 3L)
            } else if (e$meta == 84) {
                require(length(fields) == 5L)
                e$data <- vapply(1:5, function(j) value(j, 0, 255), numeric(1))
            } else if (e$meta == 88) {
                require(length(fields) == 3L)
                fraction <- as.numeric(strsplit(fields[1], "/", fixed = TRUE)[[1]])
                exponent <- match(fraction[2], 2^(0:6)) - 1L
                require(fraction[1] >= 1 && fraction[1] <= 255 && !is.na(exponent))
                e$data <- c(fraction[1], exponent, value(2, 0, 255), value(3, 0, 255))
            } else if (e$meta == 89) {
                require(length(fields) == 2L)
                found <- FALSE
                for (mi in 0:1) {
                    for (sf in -7:7) {
                        if (identical(fields, c(key_names[[mi + 1L]][sf + 8L], if (!mi) "major" else "minor"))) {
                            e$data <- c(sf %% 256, mi)
                            found <- TRUE
                        }
                    }
                }
                require(found)
            }
        }
        if (track > count) fail("bad track")
        row <- s$tracks[[current]]
        ended <- length(row) && is_meta(row[[length(row)]], 47)
        if (track < current) fail("out of order")
        if (track > current && (!ended || track > current + 1L)) fail("missing end of track")
        if (track == current && ended) fail("event after end of track")
        if (track == current + 1L) {
            current <- current + 1L
            row <- s$tracks[[current]]
        }
        if (length(row) && tick < row[[length(row)]]$tick) fail("out of order")
        s$tracks[[current]][[length(row) + 1L]] <- e
    }
    lineno <- length(lines) + 1L
    row <- s$tracks[[current]]
    if (current < count || !length(row) || !is_meta(row[[length(row)]], 47)) fail("missing end of track")
    s
}
vlq <- function(value) {
    data <- value %% 128
    value <- value %/% 128
    while (value > 0) {
        data <- c(value %% 128 + 128, data)
        value <- value %/% 128
    }
    data
}
encode <- function(s, running, zero) {
    data <- c(as.numeric(charToRaw("MThd")), bytes_be(6, 4L), bytes_be(s$format, 2L), bytes_be(length(s$tracks), 2L), bytes_be(s$division, 2L))
    for (track in s$tracks) {
        row <- numeric()
        last <- 0
        status <- 0
        for (e in track) {
            row <- c(row, vlq(e$tick - last))
            last <- e$tick
            st <- e$status
            body <- e$data
            if (zero && st %/% 16 == 8) {
                st <- st + 16
                body <- c(body[1], 0)
            }
            if (st < 240) {
                if (!running || status != st) row <- c(row, st)
                row <- c(row, body)
                status <- st
            } else {
                status <- 0
                row <- c(row, st)
                if (st == 255) row <- c(row, e$meta)
                row <- c(row, vlq(length(body)), body)
            }
        }
        data <- c(data, as.numeric(charToRaw("MTrk")), bytes_be(length(row), 4L), row)
    }
    data
}
pairing <- function(s) {
    queues <- list()
    notes <- list()
    unmatched <- list()
    for (p in ordered(s)) {
        e <- p$event
        if (!is_on(e) && !is_off(e)) next
        key <- paste(channel(e), e$data[1], sep = ":")
        queue <- queues[[key]]
        if (is_on(e)) {
            queue[[length(queue) + 1L]] <- p
            queues[[key]] <- queue
        } else if (!length(queue)) {
            unmatched[[length(unmatched) + 1L]] <- p
        } else {
            on <- queue[[1L]]
            queues[[key]] <- queue[-1L]
            notes[[length(notes) + 1L]] <- list(on = on, off = p, length = e$tick - on$event$tick)
        }
    }
    for (queue in queues) unmatched <- c(unmatched, queue)
    if (length(notes)) {
        notes <- notes[order(vapply(notes, function(n) n$on$event$tick, numeric(1)), vapply(notes, function(n) channel(n$on$event), numeric(1)), vapply(notes, function(n) n$on$event$data[1], numeric(1)), vapply(notes, function(n) n$on$order, numeric(1)))]
    }
    if (length(unmatched)) unmatched <- unmatched[order(vapply(unmatched, function(p) p$order, numeric(1)))]
    list(notes = notes, unmatched = unmatched)
}
time_at <- function(s, tick) {
    total <- 0
    last <- 0
    tempo <- 500000
    for (p in ordered(s)) {
        e <- p$event
        if (e$tick > tick) break
        if (is_meta(e, 81)) {
            total <- total + (e$tick - last) * tempo
            last <- e$tick
            tempo <- bigendian(e$data)
        }
    }
    usec <- (total + (tick - last) * tempo) %/% s$division
    paste0(usec %/% 1000, ".", sprintf("%03d", as.integer(usec %% 1000)))
}
bar_at <- function(s, tick) {
    start <- 0
    bar <- 1
    nn <- 4
    beat <- s$division
    for (p in ordered(s)) {
        e <- p$event
        if (e$tick > tick) break
        if (is_meta(e, 88)) {
            size <- nn * beat
            bar <- bar + (e$tick - start + size - 1) %/% size
            start <- e$tick
            nn <- e$data[1]
            beat <- (s$division * 4) %/% 2^e$data[2]
        }
    }
    x <- tick - start
    paste(bar + x %/% (nn * beat), x %% (nn * beat) %/% beat + 1, x %% beat, sep = ":")
}
store <- new.env(parent = emptyenv())
settings <- new.env(parent = emptyenv())
settings$running <- TRUE
settings$zero <- FALSE
execute <- function(words) {
    cmd <- words[1]
    a <- words[-1]
    commands <- c("DECODE", "ENCODE", "TIMING", "NOTES", "STATS", "ROLL", "TRANSPOSE", "QUANTIZE", "VELOCITY", "TEMPO", "FILTER", "MERGE", "SPLIT", "COPY", "LIST", "RUNNING", "NOTEOFF")
    if (!(cmd %in% commands)) {
        line("error: unknown command")
        return()
    }
    if (cmd == "LIST") {
        names <- sort(ls(store), method = "radix")
        for (name in names) line(name, " ", summary_song(store[[name]]))
        if (!length(names)) line("no songs")
        return()
    }
    if (cmd %in% c("RUNNING", "NOTEOFF")) {
        allowed <- if (cmd == "RUNNING") c("ON", "OFF") else c("ZERO", "KEEP")
        if (!(a[1] %in% allowed)) {
            line("error: bad argument")
        } else {
            if (cmd == "RUNNING") settings$running <- a[1] == "ON" else settings$zero <- a[1] == "ZERO"
            line(tolower(cmd), " ", tolower(a[1]))
        }
        return()
    }
    if (!exists(a[1], envir = store, inherits = FALSE)) {
        line("error: no song ", a[1])
        return()
    }
    s <- store[[a[1]]]
    args <- if (cmd == "COPY") numeric() else as.numeric(a[-1])
    valid <- TRUE
    if (cmd == "TRANSPOSE") valid <- args[1] >= -127 && args[1] <= 127 && (length(args) == 1L || (args[2] >= 1 && args[2] <= 16))
    if (cmd == "QUANTIZE") valid <- args[1] >= 1 && args[1] <= 1000000 && args[2] >= 0 && args[2] <= 100
    if (cmd == "VELOCITY") valid <- args[1] >= 0 && args[1] <= 1000 && args[2] >= -127 && args[2] <= 127
    if (cmd == "TEMPO") valid <- all(args >= 1 & args <= 1000)
    if (cmd == "FILTER") valid <- all(args >= 1 & args <= 16)
    if (cmd == "ROLL") {
        valid <- args[1] >= 0 && args[1] <= 10000000 && args[2] >= 1 && args[2] <= 10000000 && args[3] >= 1 && args[3] <= 10000000 && args[2] > args[1]
        if (valid) valid <- (args[2] - args[1] + args[3] - 1) %/% args[3] <= 64
    }
    if (!valid) {
        line("error: bad argument")
        return()
    }
    if (cmd %in% c("TIMING", "STATS") && s$format == 2) {
        line("error: format 2 not supported")
        return()
    }
    if (cmd == "MERGE" && s$format != 1) {
        line("error: not format 1")
        return()
    }
    if (cmd == "SPLIT" && s$format != 0) {
        line("error: not format 0")
        return()
    }
    if (cmd == "COPY") {
        store[[a[2]]] <- s
        line("copied ", a[1], " to ", a[2])
    } else if (cmd == "DECODE") {
        line("HEADER ", s$format, " ", length(s$tracks), " ", s$division)
        for (t in seq_along(s$tracks)) {
            for (e in s$tracks[[t]]) line(event_line(e, t - 1L))
        }
    } else if (cmd == "ENCODE") {
        data <- encode(s, settings$running, settings$zero)
        for (i in seq.int(1L, length(data), by = 16L)) {
            line(sprintf("%04X: ", i - 1L), paste(sprintf("%02X", as.integer(data[i:min(i + 15L, length(data))])), collapse = " "))
        }
        line(length(data), " bytes")
    } else if (cmd == "TIMING") {
        for (p in ordered(s)) {
            e <- p$event
            line(e$tick, " ", p$track, " ", kind(e), " ", time_at(s, e$tick), " ", bar_at(s, e$tick))
        }
        tick <- song_length(s)
        line("end ", tick, " ", time_at(s, tick), " ", bar_at(s, tick))
    } else if (cmd %in% c("NOTES", "STATS", "ROLL")) {
        pairs <- pairing(s)
        notes <- pairs$notes
        unmatched <- pairs$unmatched
        if (cmd == "ROLL") {
            columns <- (args[2] - args[1] + args[3] - 1) %/% args[3]
            found <- FALSE
            for (pitch in 127:0) {
                row <- rep(".", columns)
                for (i in seq_along(row)) {
                    tick <- args[1] + (i - 1L) * args[3]
                    for (n in notes) {
                        if (n$on$event$data[1] != pitch) next
                        start <- n$on$event$tick
                        if (tick <= start && start < tick + args[3]) {
                            row[i] <- "#"
                            break
                        } else if (start <= tick && tick < start + n$length) {
                            row[i] <- "="
                        }
                    }
                }
                if (any(row != ".")) {
                    line(sprintf("%-4s", note_name(pitch)), " ", paste(row, collapse = ""))
                    found <- TRUE
                }
            }
            if (!found) line("empty")
            return()
        }
        if (cmd == "STATS") line(summary_song(s))
        line("notes ", length(notes), " unmatched ", length(unmatched))
        if (cmd == "NOTES") {
            for (n in notes) {
                e <- n$on$event
                line(e$tick, " ", n$length, " ", channel(e), " ", note_name(e$data[1]), " ", e$data[2])
            }
            for (p in unmatched) {
                e <- p$event
                line("unmatched ", if (is_on(e)) "on" else "off", " ", e$tick, " ", p$track, " ", channel(e), " ", note_name(e$data[1]))
            }
        } else {
            pitches <- numeric()
            for (ch in 1:16) {
                group <- Filter(function(n) channel(n$on$event) == ch, notes)
                if (length(group)) {
                    values <- vapply(group, function(n) n$on$event$data[1], numeric(1))
                    line("channel ", ch, " notes ", length(group), " range ", note_name(min(values)), " ", note_name(max(values)))
                    pitches <- c(pitches, values)
                }
            }
            if (length(pitches)) line("range ", note_name(min(pitches)), " ", note_name(max(pitches))) else line("range none")
            line("length ", song_length(s), " ticks ", time_at(s, song_length(s)), " ms")
            changes <- list()
            for (n in notes) {
                if (n$length > 0) {
                    start <- as.character(n$on$event$tick)
                    finish <- as.character(n$on$event$tick + n$length)
                    changes[[start]] <- if (is.null(changes[[start]])) 1 else changes[[start]] + 1
                    changes[[finish]] <- if (is.null(changes[[finish]])) -1 else changes[[finish]] - 1
                }
            }
            current <- 0
            peak <- 0
            at <- 0
            for (tick in sort(as.numeric(names(changes)))) {
                current <- current + changes[[as.character(tick)]]
                if (current > peak) {
                    peak <- current
                    at <- tick
                }
            }
            if (!peak) line("polyphony 0") else line("polyphony ", peak, " at ", at)
        }
    } else if (cmd == "TRANSPOSE") {
        kept <- 0L
        dropped <- character()
        for (t in seq_along(s$tracks)) {
            row <- list()
            for (e in s$tracks[[t]]) {
                if (e$status < 176 && (length(args) == 1L || channel(e) == args[2])) {
                    pitch <- e$data[1] + args[1]
                    if (pitch < 0 || pitch > 127) {
                        dropped <- c(dropped, paste("dropped", e$tick, t - 1L, kind(e), channel(e), note_name(e$data[1])))
                        next
                    }
                    e$data[1] <- pitch
                    kept <- kept + 1L
                }
                row[[length(row) + 1L]] <- e
            }
            s$tracks[[t]] <- row
        }
        line("transposed ", kept, " dropped ", length(dropped))
        for (text in dropped) line(text)
    } else if (cmd == "QUANTIZE") {
        pairs <- pairing(s)
        targets <- lapply(pairs$notes, function(n) list(on = n$on, off = n$off))
        for (p in pairs$unmatched) {
            if (is_on(p$event)) targets[[length(targets) + 1L]] <- list(on = p, off = NULL)
        }
        moved <- 0L
        for (target in targets) {
            on <- target$on
            tick <- on$event$tick
            lower <- tick %/% args[1] * args[1]
            goal <- if (tick - lower <= lower + args[1] - tick) lower else lower + args[1]
            delta <- (2 * (goal - tick) * args[2] + 100) %/% 200
            moved <- moved + (delta != 0)
            s$tracks[[on$track + 1L]][[on$index]]$tick <- tick + delta
            off <- target$off
            if (!is.null(off)) s$tracks[[off$track + 1L]][[off$index]]$tick <- off$event$tick + delta
        }
        for (t in seq_along(s$tracks)) {
            track <- s$tracks[[t]]
            ending <- track[[length(track)]]
            row <- track[-length(track)]
            if (length(row)) {
                row <- row[order(vapply(row, function(e) e$tick, numeric(1)), seq_along(row))]
                ending$tick <- max(ending$tick, row[[length(row)]]$tick)
            }
            s$tracks[[t]] <- c(row, list(ending))
        }
        line("quantized ", length(targets), " moved ", moved)
    } else if (cmd == "VELOCITY") {
        count <- 0L
        clamped <- 0L
        for (t in seq_along(s$tracks)) {
            for (i in seq_along(s$tracks[[t]])) {
                e <- s$tracks[[t]][[i]]
                if (is_on(e)) {
                    count <- count + 1L
                    v <- (e$data[2] * args[1] + 50) %/% 100 + args[2]
                    clamped <- clamped + (v < 1 || v > 127)
                    s$tracks[[t]][[i]]$data[2] <- max(1, min(127, v))
                }
            }
        }
        line("velocity ", count, " clamped ", clamped)
    } else if (cmd == "TEMPO") {
        count <- 0L
        exists_zero <- FALSE
        good <- TRUE
        scale <- function(v) (2 * v * args[2] + args[1]) %/% (2 * args[1])
        for (t in seq_along(s$tracks)) {
            for (i in seq_along(s$tracks[[t]])) {
                e <- s$tracks[[t]][[i]]
                if (is_meta(e, 81)) {
                    count <- count + 1L
                    exists_zero <- exists_zero || e$tick == 0
                    v <- scale(bigendian(e$data))
                    good <- good && v >= 1 && v <= 16777215
                    s$tracks[[t]][[i]]$data <- bytes_be(v, 3L)
                }
            }
        }
        inserted <- scale(500000)
        if (!exists_zero) {
            good <- good && inserted >= 1 && inserted <= 16777215
            s$tracks[[1]] <- c(list(event(0, 255, bytes_be(inserted, 3L), 81)), s$tracks[[1]])
        }
        if (!good) {
            line("error: tempo out of range")
            return()
        }
        line("scaled ", count)
        if (!exists_zero) line("inserted 0 0 TEMPO ", inserted)
    } else if (cmd == "FILTER") {
        count <- 0L
        for (t in seq_along(s$tracks)) {
            row <- list()
            for (e in s$tracks[[t]]) {
                if (e$status < 240 && !(channel(e) %in% args)) count <- count + 1L else row[[length(row) + 1L]] <- e
            }
            s$tracks[[t]] <- row
        }
        line("removed ", count)
    } else if (cmd == "MERGE") {
        original <- length(s$tracks)
        tick <- song_length(s)
        row <- lapply(Filter(function(p) !is_meta(p$event, 47), ordered(s)), function(p) p$event)
        s$tracks <- list(c(row, list(eot(tick))))
        s$format <- 0
        line("merged ", original, " tracks events ", length(s$tracks[[1]]))
    } else if (cmd == "SPLIT") {
        tick <- song_length(s)
        rows <- list(`0` = list())
        for (e in s$tracks[[1]]) {
            if (is_meta(e, 47)) next
            ch <- if (e$status < 240) channel(e) else 0
            key <- as.character(ch)
            row <- rows[[key]]
            row[[length(row) + 1L]] <- e
            rows[[key]] <- row
        }
        s$tracks <- lapply(sort(as.integer(names(rows))), function(ch) c(rows[[as.character(ch)]], list(eot(tick))))
        s$format <- 1
        line("split tracks ", length(s$tracks), " events ", sum(lengths(s$tracks)))
    }
    if (cmd %in% c("TRANSPOSE", "QUANTIZE", "VELOCITY", "TEMPO", "FILTER", "MERGE", "SPLIT")) store[[a[1]]] <- s
}
input <- file("stdin", "r")
n <- as.integer(readLines(input, n = 1L))
for (i in seq_len(n)) {
    words <- strsplit(readLines(input, n = 1L), " ", fixed = TRUE)[[1]]
    if (words[1] %in% c("HEX", "TEXT")) {
        lines <- readLines(input, n = as.integer(words[3]))
        tryCatch({
            if (words[1] == "HEX") {
                bytes <- unlist(strsplit(paste(lines, collapse = " "), " ", fixed = TRUE), use.names = FALSE)
                s <- parse_hex(strtoi(bytes, base = 16L))
            } else {
                s <- parse_text(lines)
            }
            store[[words[2]]] <- s
            line("loaded ", words[2], " ", summary_song(s))
        }, midi_error = function(e) {
            line("error: ", if (words[1] == "HEX") "byte" else "line", " ", e$position, ": ", e$reason)
        })
    } else {
        execute(words)
    }
}
close(input)
