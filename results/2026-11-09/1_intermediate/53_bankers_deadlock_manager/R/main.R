options(scipen = 999)
line <- function(...) cat(..., "\n", sep = "")
vf <- function(v) paste0("(", paste(v, collapse = ","), ")")
pn <- function(id) paste0("P", id, recycle0 = TRUE)
pf <- function(ids) paste(pn(ids), collapse = " ")
empty_state <- function(total = numeric()) {
    list(total = total, available = total, processes = list(), queue = list(), history = list())
}
m <- new.env(parent = emptyenv())
m$s <- empty_state()
m$mode <- "AVOID"
m$policy <- "ALLOC"
m$trace <- FALSE
m$automatic <- FALSE
m$time <- 0
m$snapshots <- list()
ids <- function(s) sort(as.integer(substring(names(s$processes), 2L)))
need <- function(p) p$maximum - p$allocation
blocked <- function(s, id) any(vapply(s$queue, function(q) q$id == id, logical(1)))
request <- function(s, id) {
    for (q in s$queue) {
        if (q$id == id) return(q$value)
    }
    numeric(length(s$total))
}
check <- function(s, detect = FALSE, trace = FALSE) {
    work <- s$available
    remaining <- ids(s)
    idle <- integer()
    sequence <- integer()
    if (detect) {
        idle <- remaining[vapply(remaining, function(id) all(s$processes[[pn(id)]]$allocation == 0), logical(1))]
        remaining <- setdiff(remaining, idle)
    }
    tag <- if (detect) "[detect]" else "[safety]"
    if (trace) {
        suffix <- if (length(idle)) paste0(" idle ", pf(idle)) else ""
        line(tag, " start work=", vf(work), suffix)
    }
    repeat {
        chosen <- NA_integer_
        for (id in remaining) {
            p <- s$processes[[pn(id)]]
            v <- if (detect) request(s, id) else need(p)
            if (all(v <= work)) {
                chosen <- id
                break
            }
        }
        if (is.na(chosen)) break
        work <- work + s$processes[[pn(chosen)]]$allocation
        remaining <- remaining[remaining != chosen]
        sequence <- c(sequence, chosen)
        if (trace) line(tag, " ", pn(chosen), " can finish, work=", vf(work))
    }
    if (trace && length(remaining)) line(tag, " stuck work=", vf(work), " remaining ", pf(remaining))
    list(ok = !length(remaining), sequence = sequence, remaining = remaining)
}
decision <- function(id, v, reject = TRUE, trace = m$trace) {
    s <- m$s
    p <- s$processes[[pn(id)]]
    result <- function(status, reason = "", sequence = integer()) list(status = status, reason = reason, sequence = sequence)
    if (reject) {
        if (blocked(s, id)) return(result("rejected", paste0("process ", pn(id), " is blocked")))
        if (all(v == 0)) return(result("rejected", "zero vector"))
        if (any(v > need(p))) return(result("rejected", "request exceeds need"))
        held <- which(p$allocation > 0)
        if (m$mode == "ORDER" && length(held) && any(v[seq_len(max(held))] > 0)) {
            return(result("rejected", "resource order violation"))
        }
    }
    if (any(v > s$available)) return(result("blocked", "insufficient resources"))
    if (m$mode == "AVOID") {
        s$available <- s$available - v
        s$processes[[pn(id)]]$allocation <- p$allocation + v
        tested <- check(s, FALSE, trace)
        if (!tested$ok) return(result("blocked", "unsafe state"))
        return(result("granted", sequence = tested$sequence))
    }
    result("granted")
}
record <- function(kind, id, v, wait = 0) {
    m$s$history[[length(m$s$history) + 1L]] <- list(time = m$time, kind = kind, id = id, value = v, wait = wait)
}
remove_wait <- function(id) {
    m$s$queue <- Filter(function(q) q$id != id, m$s$queue)
}
grant <- function(id, v) {
    m$s$available <- m$s$available - v
    m$s$processes[[pn(id)]]$allocation <- m$s$processes[[pn(id)]]$allocation + v
}
retry <- function() {
    queue <- m$s$queue
    for (q in queue) {
        if (decision(q$id, q$value, FALSE)$status == "granted") {
            grant(q$id, q$value)
            remove_wait(q$id)
            line("unblocked ", pn(q$id), " ", vf(q$value))
            record("unblocked", q$id, q$value, m$time - q$since)
        }
    }
}
terminate <- function(id, kind, retry_after = TRUE) {
    v <- m$s$processes[[pn(id)]]$allocation
    m$s$available <- m$s$available + v
    m$s$processes[[pn(id)]] <- NULL
    remove_wait(id)
    line(kind, " ", pn(id), " released ", vf(v))
    record(kind, id, v)
    if (retry_after) retry()
}
lex_less <- function(a, b) {
    for (i in seq_len(min(length(a), length(b)))) {
        if (a[i] != b[i]) return(a[i] < b[i])
    }
    length(a) < length(b)
}
lex_sort <- function(items) {
    if (length(items) < 2L) return(items)
    for (i in 2:length(items)) {
        j <- i
        while (j > 1L && lex_less(items[[j]], items[[j - 1L]])) {
            tmp <- items[[j]]
            items[[j]] <- items[[j - 1L]]
            items[[j - 1L]] <- tmp
            j <- j - 1L
        }
    }
    items
}
victims <- function(s) {
    dead <- check(s, TRUE)$remaining
    if (!length(dead)) return(integer())
    for (size in seq_along(dead)) {
        choices <- combn(dead, size, simplify = FALSE)
        choices <- lex_sort(choices)
        costs <- vapply(choices, function(choice) sum(vapply(choice, function(id) sum(s$processes[[pn(id)]]$allocation), numeric(1))), numeric(1))
        choices <- choices[order(costs, seq_along(choices))]
        for (choice in choices) {
            trial <- s
            for (id in choice) {
                trial$available <- trial$available + trial$processes[[pn(id)]]$allocation
                trial$processes[[pn(id)]] <- NULL
            }
            if (check(trial, TRUE)$ok) return(choice)
        }
    }
    integer()
}
graph <- function(resource) {
    s <- m$s
    order_ids <- ids(s)
    edges <- setNames(lapply(order_ids, function(id) list()), pn(order_ids))
    if (resource) {
        if (any(s$total != 1)) {
            line("error: not single-instance")
            return()
        }
        for (j in seq_along(s$total)) {
            for (id in order_ids) {
                if (s$processes[[pn(id)]]$allocation[j] > 0) line("assign ", LETTERS[j], " -> ", pn(id))
            }
        }
        for (id in order_ids) {
            r <- request(s, id)
            for (j in which(r > 0)) {
                line("request ", pn(id), " -> ", LETTERS[j])
                for (to in order_ids) {
                    if (s$processes[[pn(to)]]$allocation[j] > 0) {
                        edges[[pn(id)]][[length(edges[[pn(id)]]) + 1L]] <- c(to, j)
                    }
                }
            }
        }
        for (id in order_ids) {
            for (j in which(need(s$processes[[pn(id)]]) > 0 & request(s, id) == 0)) {
                line("claim ", pn(id), " -> ", LETTERS[j])
            }
        }
    } else {
        count <- 0L
        for (id in order_ids) {
            for (to in order_ids) {
                if (id == to) next
                labels <- which(request(s, id) > s$available & s$processes[[pn(to)]]$allocation > 0)
                if (length(labels)) {
                    line(pn(id), " -> ", pn(to), " on ", paste(LETTERS[labels], collapse = ","))
                    edges[[pn(id)]][[length(edges[[pn(id)]]) + 1L]] <- c(to, 0)
                    count <- count + 1L
                }
            }
        }
        if (!count) line("no wait edges")
    }
    cycles <- list()
    for (start in order_ids) {
        visit <- function(at, path, seen) {
            for (edge in edges[[pn(at)]]) {
                to <- edge[1]
                next_path <- if (resource) c(path, edge[2], to) else c(path, to)
                if (to == start) {
                    if (resource || length(seen) >= 2L) cycles[[length(cycles) + 1L]] <<- next_path
                } else if (to > start && !(to %in% seen)) {
                    visit(to, next_path, c(seen, to))
                }
            }
        }
        visit(start, start, start)
    }
    for (cycle in lex_sort(cycles)) {
        parts <- vapply(seq_along(cycle), function(i) {
            if (resource && i %% 2 == 0) LETTERS[cycle[i]] else pn(cycle[i])
        }, character(1))
        line("cycle: ", paste(parts, collapse = " -> "))
    }
    if (!length(cycles)) line("no cycles")
}
table <- function(s) {
    widths <- nchar(s$total)
    names_row <- paste(mapply(function(x, w) sprintf("%*s", w, x), LETTERS[seq_along(widths)], widths), collapse = " ")
    cw <- pmax(c(10, 3, 4, 7), nchar(names_row))
    form <- function(v) paste(mapply(function(x, w) sprintf("%*d", w, x), v, widths), collapse = " ")
    row <- function(heading, cols) {
        cols <- c(cols, rep("", 4L - length(cols)))
        result <- sprintf("%-9s", heading)
        for (i in 1:4) result <- paste0(result, "  ", sprintf("%-*s", cw[i], cols[i]))
        line(sub(" +$", "", result))
    }
    row("Process", c("Allocation", "Max", "Need", "Request"))
    row("", rep(names_row, 4))
    for (id in ids(s)) {
        p <- s$processes[[pn(id)]]
        row(pn(id), vapply(list(p$allocation, p$maximum, need(p), request(s, id)), form, character(1)))
    }
    row("Available", form(s$available))
    row("Total", form(s$total))
    if (!length(s$queue)) {
        line("blocked queue: empty")
    } else {
        items <- vapply(s$queue, function(q) paste0(pn(q$id), " ", vf(q$value), " since t=", q$since), character(1))
        line("blocked queue: ", paste(items, collapse = ", "))
    }
}
execute <- function(words) {
    cmd <- words[1]
    args <- words[-1]
    has_id <- cmd %in% c("PROCESS", "CLAIM", "REQUEST", "WHATIF", "RELEASE", "FINISH", "ABORT", "CANCEL", "MAXGRANT")
    has_vector <- cmd %in% c("PROCESS", "CLAIM", "REQUEST", "WHATIF", "RELEASE", "ADD", "REMOVE")
    id <- if (has_id) as.integer(args[1]) else 0L
    v <- if (has_vector) as.numeric(if (has_id) args[-1] else args) else numeric()
    err <- ""
    if (has_vector && length(v) != length(m$s$total)) {
        err <- "wrong vector length"
    } else if (has_id && cmd == "PROCESS" && !is.null(m$s$processes[[pn(id)]])) {
        err <- paste0("duplicate process ", pn(id))
    } else if (has_id && cmd != "PROCESS" && is.null(m$s$processes[[pn(id)]])) {
        err <- paste0("unknown process ", pn(id))
    }
    if (nzchar(err)) {
        line("error: ", err)
        return()
    }
    if (cmd == "RESOURCES") {
        m$s <- empty_state(as.numeric(args))
        line("resources ", vf(m$s$total))
    } else if (cmd %in% c("MODE", "POLICY", "TRACE", "AUTODETECT")) {
        if (cmd == "MODE") m$mode <- args[1]
        if (cmd == "POLICY") m$policy <- args[1]
        if (cmd == "TRACE") m$trace <- args[1] == "ON"
        if (cmd == "AUTODETECT") m$automatic <- args[1] == "ON"
        line(tolower(cmd), " ", args[1])
    } else if (cmd == "PROCESS") {
        if (any(v > m$s$total)) {
            err <- "max exceeds total"
        } else {
            m$s$processes[[pn(id)]] <- list(maximum = v, allocation = numeric(length(v)), created = m$time)
            line("process ", pn(id), " max ", vf(v))
        }
    } else if (cmd == "CLAIM") {
        p <- m$s$processes[[pn(id)]]
        if (blocked(m$s, id)) {
            err <- paste0("process ", pn(id), " is blocked")
        } else if (any(p$allocation > v)) {
            err <- "claim below allocation"
        } else if (any(v > m$s$total)) {
            err <- "max exceeds total"
        } else {
            trial <- m$s
            trial$processes[[pn(id)]]$maximum <- v
            if (m$mode == "AVOID" && !check(trial, FALSE, m$trace)$ok) {
                err <- "claim makes state unsafe"
            } else {
                m$s <- trial
                line("claim ", pn(id), " max ", vf(v))
                retry()
            }
        }
    } else if (cmd %in% c("ADD", "REMOVE")) {
        if (all(v == 0)) {
            err <- "zero vector"
        } else if (cmd == "ADD") {
            m$s$total <- m$s$total + v
            m$s$available <- m$s$available + v
            line("added ", vf(v), " total ", vf(m$s$total))
            retry()
        } else if (any(v > m$s$available)) {
            err <- "remove exceeds available"
        } else if (any(m$s$total - v == 0)) {
            err <- "total must stay positive"
        } else if (any(vapply(m$s$processes, function(p) any(p$maximum > m$s$total - v), logical(1)))) {
            err <- "max exceeds total"
        } else {
            trial <- m$s
            trial$available <- trial$available - v
            if (m$mode == "AVOID" && !check(trial, FALSE, m$trace)$ok) {
                err <- "removal makes state unsafe"
            } else {
                trial$total <- trial$total - v
                m$s <- trial
                line("removed ", vf(v), " total ", vf(m$s$total))
            }
        }
    } else if (cmd %in% c("REQUEST", "WHATIF")) {
        d <- decision(id, v)
        if (cmd == "WHATIF") {
            suffix <- if (d$status != "granted") paste0(" (", d$reason, ")") else if (m$mode == "AVOID") paste0(", safe sequence ", pf(d$sequence)) else ""
            line("whatif ", pn(id), " ", vf(v), ": ", d$status, suffix)
        } else if (d$status == "rejected") {
            err <- d$reason
        } else {
            if (d$status == "granted") {
                grant(id, v)
                line("granted ", pn(id), " ", vf(v))
            } else {
                m$s$queue[[length(m$s$queue) + 1L]] <- list(id = id, value = v, since = m$time)
                line("blocked ", pn(id), " ", vf(v), ": ", d$reason)
            }
            record(d$status, id, v)
            if (d$status == "blocked" && m$automatic) {
                dead <- check(m$s, TRUE, m$trace)$remaining
                if (length(dead)) line("deadlock detected: ", pf(dead))
            }
        }
    } else if (cmd == "RELEASE") {
        p <- m$s$processes[[pn(id)]]
        if (blocked(m$s, id)) {
            err <- paste0("process ", pn(id), " is blocked")
        } else if (all(v == 0)) {
            err <- "zero vector"
        } else if (any(v > p$allocation)) {
            err <- "release exceeds allocation"
        } else {
            m$s$processes[[pn(id)]]$allocation <- p$allocation - v
            m$s$available <- m$s$available + v
            line("released ", pn(id), " ", vf(v))
            record("released", id, v)
            retry()
        }
    } else if (cmd %in% c("FINISH", "ABORT")) {
        if (cmd == "FINISH" && blocked(m$s, id)) {
            err <- paste0("process ", pn(id), " is blocked")
        } else {
            terminate(id, if (cmd == "FINISH") "finished" else "aborted")
        }
    } else if (cmd == "CANCEL") {
        if (!blocked(m$s, id)) {
            err <- paste0("process ", pn(id), " is not blocked")
        } else {
            v <- request(m$s, id)
            remove_wait(id)
            line("cancelled ", pn(id), " ", vf(v))
            record("cancelled", id, v)
        }
    } else if (cmd == "MAXGRANT") {
        if (blocked(m$s, id)) {
            err <- paste0("process ", pn(id), " is blocked")
        } else {
            result <- numeric(length(m$s$total))
            for (j in seq_along(result)) {
                limit <- need(m$s$processes[[pn(id)]])[j]
                if (!limit) next
                for (x in seq(limit, 1)) {
                    value <- numeric(length(result))
                    value[j] <- x
                    if (decision(id, value, trace = FALSE)$status == "granted") {
                        result[j] <- x
                        break
                    }
                }
            }
            line("maxgrant ", pn(id), ": ", vf(result))
        }
    } else if (cmd == "SAFE") {
        if (!length(m$s$processes)) {
            line("safe: no processes")
        } else {
            result <- check(m$s, FALSE, m$trace)
            line(if (result$ok) paste0("safe: ", pf(result$sequence)) else paste0("unsafe: ", pf(result$remaining), " cannot finish"))
        }
    } else if (cmd == "SEQUENCES") {
        if (!length(m$s$processes)) {
            line("safe sequences: no processes")
        } else {
            total <- 0L
            samples <- character()
            search <- function(work, path) {
                if (length(path) == length(m$s$processes)) {
                    total <<- total + 1L
                    if (length(samples) < as.integer(args[1])) samples <<- c(samples, pf(path))
                    return()
                }
                for (id in setdiff(ids(m$s), path)) {
                    p <- m$s$processes[[pn(id)]]
                    if (all(need(p) <= work)) search(work + p$allocation, c(path, id))
                }
            }
            search(m$s$available, integer())
            line("safe sequences: ", total)
            for (sample in samples) line(sample)
        }
    } else if (cmd == "DEFICIT") {
        result <- character(length(m$s$total))
        for (j in seq_along(result)) {
            limit <- sum(vapply(m$s$processes, function(p) need(p)[j], numeric(1)))
            result[j] <- "-"
            for (x in 0:limit) {
                trial <- m$s
                trial$available[j] <- trial$available[j] + x
                if (check(trial)$ok) {
                    result[j] <- as.character(x)
                    break
                }
            }
        }
        line("deficit: ", vf(result))
    } else if (cmd == "STATE") {
        table(m$s)
    } else if (cmd == "STATS") {
        for (j in seq_along(m$s$total)) {
            total <- m$s$total[j]
            used <- total - m$s$available[j]
            requested <- sum(vapply(m$s$queue, function(q) q$value[j], numeric(1)))
            pct <- (used * 1000) %/% total
            line(LETTERS[j], ": allocated ", used, "/", total, " (", pct %/% 10, ".", pct %% 10, "%), requested ", requested)
        }
        kinds <- c("granted", "blocked", "unblocked", "released", "finished", "aborted", "cancelled")
        counts <- vapply(kinds, function(kind) sum(vapply(m$s$history, function(e) e$kind == kind, logical(1))), numeric(1))
        line("events: ", paste(paste(kinds, counts), collapse = ", "))
        n <- counts["unblocked"]
        if (!n) {
            line("waits: none")
        } else {
            total <- sum(vapply(m$s$history, function(e) if (e$kind == "unblocked") e$wait else 0, numeric(1)))
            avg <- (total * 100) %/% n
            line("waits: ", n, " unblocked, total ", total, ", average ", avg %/% 100, ".", sprintf("%02d", as.integer(avg %% 100)))
        }
    } else if (cmd == "DETECT") {
        dead <- check(m$s, TRUE, m$trace)$remaining
        line(if (length(dead)) paste0("deadlocked: ", pf(dead)) else "no deadlock")
    } else if (cmd == "VICTIMS") {
        choice <- victims(m$s)
        line(if (length(choice)) paste0("victims: ", pf(choice)) else "no deadlock")
    } else if (cmd == "RECOVER") {
        count <- 0L
        repeat {
            dead <- check(m$s, TRUE, m$trace)$remaining
            if (!length(dead)) break
            if (length(args)) {
                for (id in dead) terminate(id, "aborted", FALSE)
                count <- count + length(dead)
                retry()
                break
            }
            priority <- vapply(dead, function(id) {
                p <- m$s$processes[[pn(id)]]
                if (m$policy == "ALLOC") sum(p$allocation) else if (m$policy == "NEED") -sum(need(p)) else -p$created
            }, numeric(1))
            chosen <- dead[order(priority, -dead)[1]]
            terminate(chosen, "aborted")
            count <- count + 1L
        }
        line(if (count) paste0("recovered: ", count, " aborted") else "no deadlock")
    } else if (cmd %in% c("WAITGRAPH", "GRAPH")) {
        graph(cmd == "GRAPH")
    } else if (cmd == "HISTORY") {
        found <- FALSE
        for (e in m$s$history) {
            if (length(args) && args[1] != e$kind && args[1] != as.character(e$id)) next
            suffix <- if (e$kind == "unblocked") paste0(" waited ", e$wait) else ""
            line("t=", e$time, " ", e$kind, " ", pn(e$id), " ", vf(e$value), suffix)
            found <- TRUE
        }
        if (!found) line("no events")
    } else if (cmd == "SNAPSHOT") {
        m$snapshots[[args[1]]] <- m$s
        line("saved ", args[1])
    } else if (cmd == "RESTORE") {
        if (is.null(m$snapshots[[args[1]]])) {
            err <- paste0("unknown snapshot ", args[1])
        } else {
            m$s <- m$snapshots[[args[1]]]
            line("restored ", args[1])
        }
    }
    if (nzchar(err)) line("error: ", err)
}
input <- file("stdin", "r")
n <- as.integer(readLines(input, n = 1L))
for (t in seq_len(n)) {
    m$time <- t
    execute(strsplit(readLines(input, n = 1L), " ", fixed = TRUE)[[1]])
}
close(input)
