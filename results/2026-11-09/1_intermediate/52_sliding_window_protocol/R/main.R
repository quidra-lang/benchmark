keys <- c("PROTOCOL", "FRAMES", "WINDOW", "SEQBITS", "TIMEOUT", "DELAY", "INTERVAL", "MAXTICKS", "DUPACK", "NAK", "BACKOFF", "CONGESTION", "UNSAFE", "TRACE", "RANDOM", "LOSEDATA", "LOSECTRL", "CORRUPTDATA", "CORRUPTCTRL", "DELAYDATA", "DELAYCTRL", "SNAPSHOT")
listkeys <- keys[16:22]
emit <- function(...) cat(paste0(...), "\n", sep = "")
bad <- function(text) stop(structure(list(message = text), class = c("settings_error", "error", "condition")))
configure <- function(lines) {
    raw <- list()
    for (words in lines) {
        key <- words[1]
        values <- words[-1]
        if (!(key %in% keys)) bad(paste("unknown key", key))
        if (key %in% names(raw)) bad(paste("duplicate key", key))
        count <- if (key == "RANDOM") length(values) == 3 else if (key %in% listkeys) length(values) >= 1 else length(values) == 1
        if (!count) bad(paste("wrong number of values for", key))
        raw[[key]] <- values
    }
    for (key in keys[1:6]) if (!(key %in% names(raw))) bad(paste("missing key", key))
    ranges <- list(FRAMES = c(1, 60), WINDOW = c(1, 32), SEQBITS = c(1, 6), TIMEOUT = c(1, 50), DELAY = c(1, 10), INTERVAL = c(0, 10), MAXTICKS = c(1, 2000), DUPACK = c(1, 10))
    values <- list()
    for (key in keys) {
        if (!(key %in% names(raw))) next
        v <- raw[[key]]
        valid <- TRUE
        if (key %in% names(ranges)) {
            n <- as.numeric(v[1])
            valid <- n >= ranges[[key]][1] && n <= ranges[[key]][2]
            values[[key]] <- n
        } else if (key == "PROTOCOL") {
            valid <- v[1] %in% c("SW", "GBN", "SR")
            values[[key]] <- v[1]
        } else if (key == "TRACE") {
            valid <- v[1] %in% c("ALL", "SENDER", "RECEIVER", "NONE")
            values[[key]] <- v[1]
        } else if (key %in% c("NAK", "BACKOFF", "CONGESTION", "UNSAFE")) {
            valid <- v[1] %in% c("ON", "OFF")
            values[[key]] <- v[1]
        } else if (key == "RANDOM") {
            ns <- as.numeric(v)
            valid <- ns[1] >= 1 && ns[1] <= 2147483646 && ns[2] >= 0 && ns[3] >= 0 && ns[2] + ns[3] <= 100
            values[[key]] <- ns
        } else if (key %in% c("DELAYDATA", "DELAYCTRL")) {
            pairs <- lapply(strsplit(v, ":", fixed = TRUE), as.numeric)
            ids <- vapply(pairs, function(pair) pair[1], numeric(1))
            delays <- vapply(pairs, function(pair) pair[2], numeric(1))
            valid <- all(ids >= 1 & ids <= 9999 & delays >= 1 & delays <= 50) && !anyDuplicated(ids)
            values[[key]] <- setNames(delays, as.character(ids))
        } else {
            ns <- as.numeric(v)
            lo <- if (key == "SNAPSHOT") 0 else 1
            hi <- if (key == "SNAPSHOT") 2000 else 9999
            valid <- all(ns >= lo & ns <= hi) && !anyDuplicated(ns)
            values[[key]] <- ns
        }
        if (!valid) bad(paste("bad value for", key))
    }
    p <- values$PROTOCOL
    w <- values$WINDOW
    k <- values$SEQBITS
    if (p == "SR" && "DUPACK" %in% names(raw)) bad("DUPACK not supported for SR")
    limit <- if (p == "SW") 1 else if (p == "GBN") 2^k - 1 else 2^(k - 1)
    unsafe <- identical(values$UNSAFE, "ON") && p != "SW"
    if (w > limit && !unsafe) bad(paste("window", w, "exceeds limit", limit, "for", p))
    for (kind in c("data", "control")) {
        lost <- if (kind == "data") "LOSEDATA" else "LOSECTRL"
        corrupt <- if (kind == "data") "CORRUPTDATA" else "CORRUPTCTRL"
        common <- intersect(values[[lost]], values[[corrupt]])
        if (length(common)) bad(paste0(kind, " #", min(common), " both lost and corrupted"))
    }
    defaults <- list(INTERVAL = 0, MAXTICKS = 1000, NAK = "OFF", BACKOFF = "OFF", CONGESTION = "OFF", UNSAFE = "OFF", TRACE = "ALL")
    for (key in names(defaults)) if (!(key %in% names(values))) values[[key]] <- defaults[[key]]
    for (key in listkeys) if (!(key %in% names(values))) values[[key]] <- numeric()
    values
}
decimal <- function(x, y, digits) {
    scale <- 10^digits
    value <- floor(scale * x / y)
    paste0(format(value %/% scale, scientific = FALSE, trim = TRUE), ".", sprintf(paste0("%0", digits, "d"), as.integer(value %% scale)))
}
simulate <- function(name, c) {
    p <- c$PROTOCOL
    n <- c$FRAMES
    w <- c$WINDOW
    k <- c$SEQBITS
    T <- c$TIMEOUT
    d <- c$DELAY
    g <- c$INTERVAL
    L <- c$MAXTICKS
    M <- 2^k
    sr <- p == "SR"
    congestion <- c$CONGESTION == "ON"
    emit("config: ", p, " n=", n, " w=", w, " k=", k, " T=", T, " d=", d)
    randomtext <- if (is.null(c$RANDOM)) "off" else paste(c$RANDOM, collapse = "/")
    duptext <- if (is.null(c$DUPACK)) "off" else as.character(c$DUPACK)
    emit("options: interval=", g, " limit=", L, " dupack=", duptext, " nak=", tolower(c$NAK), " backoff=", tolower(c$BACKOFF),
         " congestion=", tolower(c$CONGESTION), " unsafe=", tolower(c$UNSAFE), " trace=", tolower(c$TRACE), " random=", randomtext)
    s <- new.env(parent = emptyenv())
    s$base <- s$H <- s$nextframe <- s$D <- s$r <- s$A <- 0
    s$C <- T
    s$timer <- -1
    s$cwnd <- 1
    s$threshold <- w
    s$nakmark <- FALSE
    s$marks <- rep(FALSE, n)
    s$timers <- rep(-1, n)
    s$queue <- numeric()
    s$buffer <- list()
    s$tx <- rep(0, n)
    s$first <- s$delivered <- s$acked <- rep(-1, n)
    s$dataevents <- s$controlevents <- vector("list", L + 61)
    s$stats <- setNames(rep(0, 14), c("data", "resent", "control", "nak", "timeouts", "fastretx", "lost_data", "lost_ctrl", "corrupt_data", "corrupt_ctrl", "delivered", "errors", "discarded", "max_buffer"))
    s$x <- if (is.null(c$RANDOM)) 1 else c$RANDOM[1]
    s$latency <- 0
    s$tick <- 0
    completion <- -1
    tend <- L
    line <- function(side, text) {
        if (side == "ALWAYS" || c$TRACE == "ALL" || c$TRACE == side) emit(s$tick, " ", text)
    }
    outcome <- function(kind, number) {
        result <- "normal"
        if (!is.null(c$RANDOM)) {
            s$x <- (48271 * s$x) %% 2147483647
            v <- s$x %% 100
            loss <- c$RANDOM[2]
            corrupt <- c$RANDOM[3]
            result <- if (v < loss) "LOST" else if (v < loss + corrupt) "CORRUPT" else "normal"
        }
        key <- if (kind == "data") "DATA" else "CTRL"
        if (number %in% c[[paste0("LOSE", key)]]) result <- "LOST"
        if (number %in% c[[paste0("CORRUPT", key)]]) result <- "CORRUPT"
        result
    }
    extra_delay <- function(key, number) {
        value <- c[[key]][as.character(number)]
        if (!length(value) || is.na(value)) 0 else unname(value)
    }
    control <- function(kind, value) {
        s$stats["control"] <- s$stats["control"] + 1
        j <- unname(s$stats["control"])
        if (kind == "NAK") s$stats["nak"] <- s$stats["nak"] + 1
        line("RECEIVER", paste0(kind, " a=", value, " #", j))
        arrival <- s$tick + d + extra_delay("DELAYCTRL", j)
        event <- list(number = j, value = value, kind = kind, outcome = outcome(kind, j))
        s$controlevents[[arrival + 1]] <- c(s$controlevents[[arrival + 1]], list(event))
    }
    deliver <- function(payload) {
        if (payload == s$r) {
            line("RECEIVER", paste0("DELIVER f=", s$r))
            s$stats["delivered"] <- s$stats["delivered"] + 1
            s$delivered[s$r + 1] <- s$tick
            s$latency <- s$latency + s$tick - s$first[payload + 1]
        } else {
            line("RECEIVER", paste0("DELIVER f=", s$r, " wrong=", payload))
            s$stats["errors"] <- s$stats["errors"] + 1
        }
        s$r <- s$r + 1
        s$nakmark <- FALSE
    }
    discard <- function(seq) {
        s$stats["discarded"] <- s$stats["discarded"] + 1
        line("RECEIVER", paste0("DISCARD seq=", seq))
    }
    goback <- function() {
        s$nextframe <- s$base
        s$timer <- -1
        s$D <- 0
    }
    increase <- function(count) {
        if (!congestion) return(invisible(NULL))
        for (i in seq_len(count)) {
            if (s$cwnd >= w) next
            if (s$cwnd < s$threshold) {
                s$cwnd <- s$cwnd + 1
            } else {
                s$A <- s$A + 1
                if (s$A == s$cwnd) {
                    s$cwnd <- s$cwnd + 1
                    s$A <- 0
                }
            }
        }
    }
    decrease <- function(timeout) {
        if (!congestion) return(invisible(NULL))
        s$threshold <- max(floor(s$cwnd / 2), 1)
        s$cwnd <- if (timeout) 1 else s$threshold
        s$A <- 0
    }
    cwndline <- function(old) {
        if (congestion && !identical(old, c(s$cwnd, s$threshold))) line("SENDER", paste0("CWND ", s$cwnd, " ssthresh=", s$threshold))
    }
    for (t in 0:L) {
        s$tick <- t
        data <- s$dataevents[[t + 1]]
        if (length(data)) data <- data[order(vapply(data, function(e) e$number, numeric(1)))]
        for (e in data) {
            if (e$outcome != "normal") {
                key <- if (e$outcome == "LOST") "lost_data" else "corrupt_data"
                s$stats[key] <- s$stats[key] + 1
                line("RECEIVER", paste0(e$outcome, " data #", e$number))
                next
            }
            seq <- e$value %% M
            line("RECEIVER", paste0("RECV seq=", seq, " #", e$number))
            if (!sr) {
                if (seq == s$r %% M) {
                    deliver(e$value)
                    control("ACK", seq)
                } else {
                    discard(seq)
                    if (c$NAK == "ON" && !s$nakmark) {
                        control("NAK", s$r %% M)
                        s$nakmark <- TRUE
                    } else if (s$r > 0) {
                        control("ACK", (s$r - 1) %% M)
                    }
                }
            } else {
                o <- (seq - s$r) %% M
                if (o < w) {
                    pos <- s$r + o
                    key <- as.character(pos)
                    if (!is.null(s$buffer[[key]])) {
                        discard(seq)
                        control("ACK", seq)
                    } else if (o == 0) {
                        deliver(e$value)
                        while (!is.null(s$buffer[[as.character(s$r)]])) {
                            key <- as.character(s$r)
                            payload <- s$buffer[[key]]
                            s$buffer[[key]] <- NULL
                            deliver(payload)
                        }
                        control("ACK", seq)
                    } else {
                        s$buffer[[key]] <- e$value
                        s$stats["max_buffer"] <- max(s$stats["max_buffer"], length(s$buffer))
                        line("RECEIVER", paste0("BUFFER f=", pos))
                        control("ACK", seq)
                        if (c$NAK == "ON" && !s$nakmark) {
                            control("NAK", s$r %% M)
                            s$nakmark <- TRUE
                        }
                    }
                } else {
                    discard(seq)
                    if ((s$r - seq) %% M <= w) control("ACK", seq)
                }
            }
        }
        controls <- s$controlevents[[t + 1]]
        if (length(controls)) controls <- controls[order(vapply(controls, function(e) e$number, numeric(1)))]
        for (e in controls) {
            kind <- e$kind
            value <- e$value
            j <- e$number
            if (e$outcome != "normal") {
                key <- if (e$outcome == "LOST") "lost_ctrl" else "corrupt_ctrl"
                s$stats[key] <- s$stats[key] + 1
                line("SENDER", paste0(e$outcome, " ", tolower(kind), " #", j))
                next
            }
            old <- c(s$cwnd, s$threshold)
            oldbase <- s$base
            f <- s$base + (value - s$base) %% M
            accepted <- FALSE
            if (kind == "ACK") {
                if (!sr && f < s$H) {
                    accepted <- TRUE
                    s$base <- f + 1
                    s$nextframe <- max(s$nextframe, s$base)
                } else if (sr && f < s$H && !s$marks[f + 1]) {
                    accepted <- TRUE
                    s$marks[f + 1] <- TRUE
                    if (s$acked[f + 1] < 0) s$acked[f + 1] <- t
                    s$timers[f + 1] <- -1
                    s$queue <- s$queue[s$queue != f]
                    while (s$base < s$H && s$marks[s$base + 1]) s$base <- s$base + 1
                }
            } else if (!sr && f <= s$H) {
                accepted <- TRUE
                s$base <- f
                goback()
            } else if (sr && f < s$H && !s$marks[f + 1]) {
                accepted <- TRUE
                s$timers[f + 1] <- -1
                if (!(f %in% s$queue)) s$queue <- c(s$queue, f)
            }
            if (s$base > oldbase) {
                s$C <- T
                if (!sr) {
                    s$D <- 0
                    for (a in seq.int(oldbase, s$base - 1)) if (s$acked[a + 1] < 0) s$acked[a + 1] <- t
                }
            }
            if (accepted) {
                newly <- if (sr) as.numeric(kind == "ACK") else s$base - oldbase
                increase(newly)
                if (!sr && kind == "ACK") s$timer <- if (s$base == s$nextframe) -1 else t + s$C
                if (kind == "NAK") decrease(FALSE)
                line("SENDER", paste0("GOT", kind, " a=", value, " #", j, " base=", s$base))
            } else {
                line("SENDER", paste0("OLD", kind, " a=", value, " #", j))
                if (!sr && kind == "ACK" && !is.null(c$DUPACK) && s$base >= 1 && value == (s$base - 1) %% M) {
                    s$D <- s$D + 1
                    if (s$D == c$DUPACK) {
                        s$stats["fastretx"] <- s$stats["fastretx"] + 1
                        line("SENDER", paste0("FASTRETX f=", s$base))
                        goback()
                        decrease(FALSE)
                    }
                }
            }
            cwndline(old)
        }
        done <- s$base == n
        if (!done) {
            expired <- numeric()
            if (sr && s$base < s$H) {
                frames <- seq.int(s$base, s$H - 1)
                expired <- frames[s$timers[frames + 1] == t]
            } else if (!sr && s$timer == t) expired <- s$base
            for (f in expired) {
                old <- c(s$cwnd, s$threshold)
                s$stats["timeouts"] <- s$stats["timeouts"] + 1
                line("SENDER", paste0("TIMEOUT f=", f))
                if (sr) {
                    s$timers[f + 1] <- -1
                    s$queue <- c(s$queue, f)
                } else {
                    goback()
                }
                if (c$BACKOFF == "ON") s$C <- min(2 * s$C, 8 * T)
                decrease(TRUE)
                cwndline(old)
            }
            E <- if (congestion) min(w, s$cwnd) else w
            send <- -1
            if (sr) {
                if (length(s$queue)) {
                    send <- s$queue[1]
                    s$queue <- s$queue[-1]
                } else if (s$H < n && s$H < s$base + E && s$H * g <= t) {
                    send <- s$H
                    s$H <- s$H + 1
                }
            } else if (s$nextframe < n && s$nextframe < s$base + E && (s$nextframe < s$H || s$nextframe * g <= t)) {
                send <- s$nextframe
                s$H <- max(s$H, s$nextframe + 1)
                s$nextframe <- s$nextframe + 1
            }
            if (send >= 0) {
                s$stats["data"] <- s$stats["data"] + 1
                i <- unname(s$stats["data"])
                word <- if (s$tx[send + 1] == 0) "SEND" else "RESEND"
                if (word == "SEND") s$first[send + 1] <- t else s$stats["resent"] <- s$stats["resent"] + 1
                s$tx[send + 1] <- s$tx[send + 1] + 1
                line("SENDER", paste0(word, " f=", send, " seq=", send %% M, " #", i))
                arrival <- t + d + extra_delay("DELAYDATA", i)
                event <- list(number = i, value = send, kind = "data", outcome = outcome("data", i))
                s$dataevents[[arrival + 1]] <- c(s$dataevents[[arrival + 1]], list(event))
                if (sr) s$timers[send + 1] <- t + s$C else if (s$timer < 0) s$timer <- t + s$C
            }
        }
        if (t %in% c$SNAPSHOT) {
            E <- if (congestion) min(w, s$cwnd) else w
            sx <- rx <- character(n)
            for (f in 0:(n - 1)) {
                acknowledged <- if (sr) s$marks[f + 1] else f < s$base
                waiting <- if (sr) f %in% s$queue else s$nextframe <= f && f < s$H
                sent <- if (sr) f < s$H else f < s$nextframe
                sx[f + 1] <- if (acknowledged) "A" else if (waiting) "R" else if (sent) "O" else if (f < s$base + E) "W" else "."
                rx[f + 1] <- if (f < s$r) "D" else if (sr && !is.null(s$buffer[[as.character(f)]])) "B" else if (if (sr) f < s$r + w else f == s$r) "W" else "."
            }
            line("ALWAYS", paste0("SNAPSHOT sender=", paste(sx, collapse = ""), " receiver=", paste(rx, collapse = "")))
        }
        if (done || t == L) {
            line("ALWAYS", if (done) "DONE" else "ABORT")
            completion <- if (done) t else -1
            tend <- t
            break
        }
    }
    text <- function(v) if (v < 0) "-" else as.character(v)
    for (f in 0:(n - 1)) emit("frame ", f, ": seq=", f %% M, " tx=", s$tx[f + 1], " first=", text(s$first[f + 1]), " delivered=", text(s$delivered[f + 1]), " acked=", text(s$acked[f + 1]))
    groups <- list(totals = c("data", "resent", "control", "nak", "timeouts", "fastretx"), channel = c("lost_data", "lost_ctrl", "corrupt_data", "corrupt_ctrl"), receiver = c("delivered", "errors", "discarded", "max_buffer"))
    for (prefix in names(groups)) {
        ks <- groups[[prefix]]
        emit(prefix, ": ", paste(paste0(ks, "=", s$stats[ks]), collapse = " "))
    }
    D <- unname(s$stats["delivered"])
    X <- unname(s$stats["data"])
    goodput <- if (completion < 0) "-" else decimal(D, completion, 2)
    lag <- if (D == 0) "-" else decimal(s$latency, D, 2)
    emit("result: completion=", text(completion), " goodput=", goodput, " efficiency=", decimal(100 * D, X, 1), "% utilization=", decimal(100 * X, tend + 1, 1), "% latency=", lag)
    list(name = name, protocol = p, status = if (completion < 0) "aborted" else "done", delivered = D, completion = completion, data = X)
}
main <- function() {
    options(scipen = 999)
    input <- readLines(file("stdin"), warn = FALSE)
    q <- as.integer(input[1])
    position <- 2
    results <- list()
    for (scenario in seq_len(q)) {
        name <- strsplit(input[position], " ", fixed = TRUE)[[1]][2]
        position <- position + 1
        lines <- list()
        while (input[position] != "END") {
            lines[[length(lines) + 1]] <- strsplit(input[position], " ", fixed = TRUE)[[1]]
            position <- position + 1
        }
        position <- position + 1
        emit("== ", name, " ==")
        result <- tryCatch(simulate(name, configure(lines)), settings_error = function(e) {
            emit("error: ", e$message)
            list(name = name, protocol = "", status = "invalid", delivered = 0, completion = -1, data = 0)
        })
        results[[length(results) + 1]] <- result
    }
    emit("== ranking ==")
    completed <- Filter(function(r) r$status == "done", results)
    better <- function(a, b) {
        left <- a$delivered * b$completion
        right <- b$delivered * a$completion
        if (left != right) return(left > right)
        a$delivered * b$data > b$delivered * a$data
    }
    sorted <- list()
    for (r in completed) {
        i <- 1
        while (i <= length(sorted) && !better(r, sorted[[i]])) i <- i + 1
        sorted <- append(sorted, list(r), after = i - 1)
    }
    for (i in seq_along(sorted)) {
        r <- sorted[[i]]
        emit(i, ". ", r$name, " ", r$protocol, " goodput=", decimal(r$delivered, r$completion, 2), " efficiency=", decimal(100 * r$delivered, r$data, 1), "%")
    }
    for (r in results) if (r$status != "done") emit("- ", r$name, " ", r$status)
    emit("== protocols ==")
    for (p in c("SW", "GBN", "SR")) {
        runs <- Filter(function(r) r$protocol == p, completed)
        if (!length(runs)) next
        D <- sum(vapply(runs, function(r) r$delivered, numeric(1)))
        T <- sum(vapply(runs, function(r) r$completion, numeric(1)))
        X <- sum(vapply(runs, function(r) r$data, numeric(1)))
        emit(p, ": runs=", length(runs), " goodput=", decimal(D, T, 2), " efficiency=", decimal(100 * D, X, 1), "%")
    }
}
main()
