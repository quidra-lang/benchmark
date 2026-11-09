policies <- c("FIFO", "LRU", "LFU", "NRU", "AGING", "CLOCK", "ECLOCK", "WSCLOCK", "RANDOM", "OPT")
clocks <- c("CLOCK", "ECLOCK", "WSCLOCK")
emit <- function(...) cat(paste0(...), "\n", sep = "")
suffix <- function(items) if (length(items)) paste0(" ", paste(items, collapse = " ")) else ""
fail <- function(text) stop(structure(list(message = text), class = c("command_error", "error", "condition")))
address <- function(s) strtoi(substring(s, 3), base = 16)
hex <- function(n) paste0("0x", toupper(as.character(as.hexmode(as.integer(n)))))
ratio <- function(x, y) {
    v <- if (y == 0) 0 else floor(10000 * x / y)
    sprintf("%d.%02d%%", v %/% 100, v %% 100)
}
settings <- function(words) {
    c <- list(page = 256, frames = 4, tlb = 4, sets = 1, policy = "FIFO", scope = "GLOBAL", asid = "OFF", tick = 0, tau = 8, seed = 1)
    limits <- list(frames = c(1, 16), tlb = c(1, 8), sets = c(1, 8), tick = c(0, 1000), tau = c(1, 1000), seed = c(1, 2147483646))
    seen <- character()
    for (word in words) {
        kv <- strsplit(word, "=", fixed = TRUE)[[1]]
        k <- kv[1]
        text <- kv[2]
        if (!(k %in% names(c))) fail(paste("unknown key", k))
        if (k %in% seen) fail(paste("duplicate key", k))
        seen <- c(seen, k)
        if (k %in% c("policy", "scope", "asid")) {
            choices <- switch(k, policy = policies, scope = c("GLOBAL", "LOCAL"), asid = c("ON", "OFF"))
            if (!(text %in% choices)) fail(paste("invalid", k))
            value <- text
        } else {
            value <- as.numeric(text)
            valid <- if (k == "page") value %in% 2^(4:12) else value >= limits[[k]][1] && value <= limits[[k]][2]
            if (!valid) fail(paste("invalid", k))
        }
        c[[k]] <- value
    }
    if (c$tlb %% c$sets != 0) fail("invalid sets")
    c
}
page <- function(pid, number) {
    p <- new.env(parent = emptyenv())
    p$pid <- pid
    p$number <- number
    p$frame <- p$slot <- -1
    p$ro <- p$locked <- p$seen <- FALSE
    p$r <- p$m <- p$load <- p$last <- p$uses <- p$age <- 0
    p
}
label <- function(p) paste0("P", p$pid, ":", p$number)
process_new <- function(pid, count) {
    p <- new.env(parent = emptyenv())
    p$pid <- pid
    p$pages <- lapply(seq_len(count) - 1, function(i) page(pid, i))
    p$faults <- p$writes <- p$seg <- p$prot <- p$resident <- p$peak <- p$hand <- 0
    p$exited <- FALSE
    p$history <- numeric()
    p
}
simulation <- function(c, refs) {
    s <- new.env(parent = emptyenv())
    s$config <- c
    s$processes <- list()
    s$frames <- vector("list", c$frames)
    s$slots <- list()
    s$tlb <- replicate(c$sets, list(), simplify = FALSE)
    s$refs <- refs
    s$position <- s$time <- s$lastpid <- s$hand <- 0
    s$counts <- setNames(rep(0, 6), c("faults", "zero", "swapin", "tlbhits", "writebacks", "switches"))
    s$random <- c$seed
    s$history <- numeric()
    s
}
pids <- function(s) sort(as.numeric(names(s$processes)))
get_process <- function(s, pid) {
    p <- s$processes[[as.character(pid)]]
    if (is.null(p)) fail(paste("unknown process", pid))
    if (p$exited) fail(paste("process", pid, "exited"))
    p
}
quota <- function(s, pid) {
    ids <- pids(s)
    s$config$frames %/% length(ids) + as.numeric(match(pid, ids) <= s$config$frames %% length(ids))
}
remove_tlb <- function(s, p) {
    k <- p$number %% s$config$sets + 1
    s$tlb[[k]] <- Filter(function(x) !identical(x, p), s$tlb[[k]])
}
writeback <- function(s, p) {
    s$counts["writebacks"] <- s$counts["writebacks"] + 1
    proc <- s$processes[[as.character(p$pid)]]
    proc$writes <- proc$writes + 1
    p$m <- 0
    if (p$slot < 0) {
        free <- which(vapply(s$slots, is.null, logical(1)))
        i <- if (length(free)) free[1] else length(s$slots) + 1
        p$slot <- i - 1
        s$slots[i] <- list(p)
    }
}
next_use <- function(s, p) {
    if (s$position < length(s$refs)) {
        for (i in seq.int(s$position + 1, length(s$refs))) {
            if (identical(s$refs[[i]], c(p$pid, p$number))) return(i)
        }
    }
    length(s$refs) + 1
}
choose <- function(s, proc, candidates) {
    c <- s$config
    policy <- c$policy
    if (policy == "RANDOM") {
        s$random <- (48271 * s$random) %% 2147483647
        return(candidates[s$random %% length(candidates) + 1])
    }
    if (policy %in% clocks) {
        hand <- if (c$scope == "LOCAL") proc$hand else s$hand
        order <- candidates[order((candidates - 1 - hand) %% c$frames)]
        chosen <- 0
        if (policy == "CLOCK") {
            while (chosen == 0) {
                for (f in order) {
                    p <- s$frames[[f]]
                    if (p$r == 0) {
                        chosen <- f
                        break
                    }
                    p$r <- 0
                }
            }
        } else if (policy == "ECLOCK") {
            while (chosen == 0) {
                for (f in order) {
                    p <- s$frames[[f]]
                    if (p$r == 0 && p$m == 0) {
                        chosen <- f
                        break
                    }
                }
                if (chosen != 0) break
                for (f in order) {
                    p <- s$frames[[f]]
                    if (p$r == 0 && p$m == 1) {
                        chosen <- f
                        break
                    }
                    p$r <- 0
                }
            }
        } else {
            for (f in order) {
                p <- s$frames[[f]]
                if (p$r == 1) {
                    p$r <- 0
                    p$last <- s$time
                } else if (s$time - p$last > c$tau) {
                    if (p$m == 0) {
                        chosen <- f
                        break
                    }
                    writeback(s, p)
                }
            }
            if (chosen == 0) {
                clean <- Filter(function(f) s$frames[[f]]$m == 0, order)
                chosen <- if (length(clean)) clean[1] else order[1]
            }
        }
        if (c$scope == "LOCAL") proc$hand <- chosen %% c$frames else s$hand <- chosen %% c$frames
        return(chosen)
    }
    ranks <- lapply(candidates, function(f) {
        p <- s$frames[[f]]
        switch(policy, FIFO = c(p$load, f), LRU = c(p$last, f), LFU = c(p$uses, p$load),
               NRU = c(2 * p$r + p$m, f), AGING = c(p$age, p$load), OPT = c(-next_use(s, p), f))
    })
    ranks <- do.call(rbind, ranks)
    candidates[order(ranks[, 1], ranks[, 2])[1]]
}
target <- function(s, p) {
    global <- s$config$scope == "GLOBAL"
    if (global || p$resident < quota(s, p$pid)) {
        free <- which(vapply(s$frames, is.null, logical(1)))
        if (length(free)) return(free[1])
    }
    candidates <- which(vapply(s$frames, function(pg) !is.null(pg) && (global || pg$pid == p$pid), logical(1)))
    unlocked <- Filter(function(f) !s$frames[[f]]$locked, candidates)
    choose(s, p, if (length(unlocked)) unlocked else candidates)
}
access <- function(s, a, position) {
    s$position <- position
    s$time <- s$time + 1
    c <- s$config
    p <- s$processes[[as.character(a$pid)]]
    switched <- s$lastpid != 0 && s$lastpid != a$pid
    if (switched) {
        s$counts["switches"] <- s$counts["switches"] + 1
        if (c$asid == "OFF") s$tlb <- replicate(c$sets, list(), simplify = FALSE)
    }
    s$lastpid <- a$pid
    n <- a$address %/% c$page
    off <- a$address %% c$page
    pg <- p$pages[[n + 1]]
    k <- n %% c$sets + 1
    hit <- any(vapply(s$tlb[[k]], identical, logical(1), pg))
    fault <- 0
    if (hit) {
        s$counts["tlbhits"] <- s$counts["tlbhits"] + 1
        result <- "TLBHIT"
        remove_tlb(s, pg)
    } else if (pg$frame >= 0) {
        result <- "HIT"
    } else {
        fault <- 1
        p$faults <- p$faults + 1
        s$counts["faults"] <- s$counts["faults"] + 1
        source <- if (pg$slot < 0) "zero" else "swapin"
        s$counts[source] <- s$counts[source] + 1
        result <- paste("FAULT", toupper(source))
        f <- target(s, p)
        victim <- s$frames[[f]]
        if (!is.null(victim)) {
            result <- paste0(result, " evict=", label(victim))
            victim$frame <- -1
            owner <- s$processes[[as.character(victim$pid)]]
            owner$resident <- owner$resident - 1
            remove_tlb(s, victim)
            if (victim$m == 1) {
                writeback(s, victim)
                result <- paste0(result, " writeback")
            }
        }
        s$frames[f] <- list(pg)
        pg$frame <- f - 1
        pg$load <- s$time
        pg$uses <- pg$m <- pg$age <- 0
        p$resident <- p$resident + 1
        p$peak <- max(p$peak, p$resident)
    }
    entries <- s$tlb[[k]]
    if (length(entries) == c$tlb / c$sets) entries <- head(entries, -1)
    s$tlb[[k]] <- c(list(pg), entries)
    pg$r <- 1
    if (a$op == "W") pg$m <- 1
    pg$last <- s$time
    pg$uses <- pg$uses + 1
    pg$seen <- TRUE
    p$history <- c(p$history, n)
    s$history <- c(s$history, fault)
    physical <- pg$frame * c$page + off
    line <- paste0("t=", s$time, " P", a$pid, " ", a$op, " ", hex(a$address), " page=", n,
                   " frame=", pg$frame, " phys=", hex(physical), " ", result, if (switched) " switch" else "")
    lines <- line
    if (c$tick > 0 && s$time %% c$tick == 0) {
        for (page in s$frames) {
            if (is.null(page)) next
            page$age <- page$age %/% 2 + 128 * page$r
            page$r <- 0
        }
        lines <- c(lines, paste0("t=", s$time, " tick"))
    }
    lines
}
exit_process <- function(s, pid) {
    freed <- slots <- 0
    for (i in seq_along(s$frames)) {
        pg <- s$frames[[i]]
        if (!is.null(pg) && pg$pid == pid) {
            s$frames[i] <- list(NULL)
            pg$frame <- -1
            remove_tlb(s, pg)
            freed <- freed + 1
        }
    }
    for (i in seq_along(s$slots)) {
        pg <- s$slots[[i]]
        if (!is.null(pg) && pg$pid == pid) {
            s$slots[i] <- list(NULL)
            pg$slot <- -1
            slots <- slots + 1
        }
    }
    p <- s$processes[[as.character(pid)]]
    p$resident <- 0
    p$exited <- TRUE
    c(freed, slots)
}
clean <- function(s) {
    written <- 0
    for (pg in s$frames) {
        if (!is.null(pg) && pg$m == 1) {
            writeback(s, pg)
            written <- written + 1
        }
    }
    written
}
set_lock <- function(s, e) {
    for (pg in s$processes[[as.character(e$pid)]]$pages[seq.int(e$first + 1, e$last + 1)]) pg$locked <- e$locked
}
rerun <- function(s, events, policy, frames) {
    c <- s$config
    c$policy <- policy
    c$frames <- frames
    refs <- lapply(Filter(function(e) e$kind == "ACCESS", events), function(e) c(e$pid, e$address %/% c$page))
    r <- simulation(c, refs)
    for (id in pids(s)) r$processes[[as.character(id)]] <- process_new(id, length(s$processes[[as.character(id)]]$pages))
    pos <- 0
    for (e in events) {
        if (e$kind == "ACCESS") {
            pos <- pos + 1
            access(r, e, pos)
        } else if (e$kind == "EXIT") {
            exit_process(r, e$pid)
        } else if (e$kind == "CLEAN") {
            clean(r)
        } else {
            set_lock(r, e)
        }
    }
    r
}
command <- function(state, words) {
    s <- state$s
    c <- s$config
    cmd <- words[1]
    v <- words[-1]
    n <- function(i) as.numeric(v[i])
    add_event <- function(e) state$events <- c(state$events, list(e))
    if (cmd == "PROCESS") {
        id <- n(1)
        count <- n(2)
        if (state$position > 0) fail("processes are fixed")
        if (!is.null(s$processes[[as.character(id)]])) fail(paste("duplicate process", id))
        if (count < 1 || count > 256) fail("invalid page count")
        if (length(s$processes) >= 8 || (c$scope == "LOCAL" && length(s$processes) >= c$frames)) fail("too many processes")
        s$processes[[as.character(id)]] <- process_new(id, count)
    } else if (cmd == "EXIT") {
        p <- get_process(s, n(1))
        result <- exit_process(s, p$pid)
        add_event(list(kind = "EXIT", pid = p$pid))
        emit("EXIT P", p$pid, " freed=", result[1], " slots=", result[2])
    } else if (cmd %in% c("PROTECT", "LOCK", "UNLOCK")) {
        p <- get_process(s, n(1))
        first <- n(2)
        last <- n(3)
        if (first > last || last >= length(p$pages)) fail("invalid page range")
        if (cmd == "PROTECT") {
            for (pg in p$pages[seq.int(first + 1, last + 1)]) pg$ro <- v[4] == "RO"
        } else {
            e <- list(kind = "LOCK", pid = p$pid, first = first, last = last, locked = cmd == "LOCK")
            set_lock(s, e)
            add_event(e)
        }
    } else if (cmd == "TRACE") {
        state$trace <- v[1] == "ON"
    } else if (cmd == "SUMMARY") {
        k <- s$counts
        emit("SUMMARY policy=", c$policy, " scope=", c$scope, " time=", s$time)
        seg <- sum(vapply(s$processes, function(p) p$seg, numeric(1)))
        prot <- sum(vapply(s$processes, function(p) p$prot, numeric(1)))
        emit("total faults=", k["faults"], " zero=", k["zero"], " swapin=", k["swapin"], " faultrate=", ratio(k["faults"], s$time),
             " tlbhits=", k["tlbhits"], " tlbrate=", ratio(k["tlbhits"], s$time), " writebacks=", k["writebacks"],
             " switches=", k["switches"], " segfaults=", seg, " protfaults=", prot)
        for (id in pids(s)) {
            p <- s$processes[[as.character(id)]]
            tail <- if (c$scope == "LOCAL") paste0(" quota=", quota(s, id)) else ""
            if (p$exited) tail <- paste0(tail, " exited")
            emit("P", id, " accesses=", length(p$history), " faults=", p$faults, " writebacks=", p$writes,
                 " segfaults=", p$seg, " protfaults=", p$prot, " resident=", p$resident, " peak=", p$peak, tail)
        }
    } else if (cmd == "FRAMES") {
        emit("FRAMES used=", sum(!vapply(s$frames, is.null, logical(1))), "/", c$frames)
        for (i in seq_along(s$frames)) {
            p <- s$frames[[i]]
            if (is.null(p)) emit(i - 1, " free") else emit(i - 1, " ", label(p), " R=", p$r, " M=", p$m,
                " load=", p$load, " last=", p$last, " uses=", p$uses, " age=", p$age, if (p$locked) " locked" else "")
        }
        if (c$policy %in% clocks) {
            if (c$scope == "GLOBAL") emit("hand=", s$hand) else emit("hand", paste0(vapply(pids(s), function(id) paste0(" P", id, "=", s$processes[[as.character(id)]]$hand), character(1)), collapse = ""))
        }
    } else if (cmd == "PAGETABLE") {
        p <- get_process(s, n(1))
        emit("PAGETABLE P", p$pid, " pages=", length(p$pages), " resident=", p$resident)
        for (pg in p$pages) {
            if (!pg$seen) next
            text <- if (pg$frame >= 0) paste0("frame=", pg$frame, " R=", pg$r, " M=", pg$m) else if (pg$slot >= 0) paste0("swap=", pg$slot) else "zero"
            emit(pg$number, " ", text, if (pg$ro) " RO" else "", if (pg$locked) " locked" else "")
        }
    } else if (cmd == "TLB") {
        emit("TLB used=", sum(lengths(s$tlb)), "/", c$tlb, " sets=", c$sets)
        for (i in seq_along(s$tlb)) emit("set ", i - 1, ":", paste(vapply(s$tlb[[i]], function(p) paste0(" ", label(p), "->", p$frame), character(1)), collapse = ""))
    } else if (cmd == "SWAP") {
        emit("SWAP used=", sum(!vapply(s$slots, is.null, logical(1))))
        for (i in seq_along(s$slots)) if (!is.null(s$slots[[i]])) emit(i - 1, " ", label(s$slots[[i]]))
    } else if (cmd == "CLEAN") {
        emit("CLEAN written=", clean(s))
        add_event(list(kind = "CLEAN"))
    } else if (cmd == "COMPARE") {
        emit("COMPARE accesses=", s$time, " frames=", c$frames)
        results <- lapply(policies, function(policy) rerun(s, state$events, policy, c$frames))
        for (i in seq_along(policies)) {
            k <- results[[i]]$counts
            emit(policies[i], " faults=", k["faults"], " writebacks=", k["writebacks"], " tlbhits=", k["tlbhits"])
        }
        order <- order(vapply(results, function(r) r$counts["faults"], numeric(1)), vapply(results, function(r) r$counts["writebacks"], numeric(1)), seq_along(policies))
        emit("ranking ", paste(policies[order], collapse = " "))
    } else if (cmd == "CURVE") {
        policy <- v[1]
        lo <- n(2)
        hi <- n(3)
        if (!(policy %in% policies)) fail("unknown policy")
        if (lo < 1 || lo > hi || hi > 16 || (c$scope == "LOCAL" && lo < length(s$processes))) fail("invalid frame range")
        emit("CURVE ", policy, " frames=", lo, "..", hi)
        previous <- -1
        for (f in seq.int(lo, hi)) {
            faults <- rerun(s, state$events, policy, f)$counts["faults"]
            emit("F=", f, " faults=", faults, if (previous >= 0 && faults > previous) " ANOMALY" else "")
            previous <- faults
        }
    } else if (cmd == "EAT") {
        if (s$time == 0) emit("EAT accesses=0") else {
            total <- n(1) * s$time + n(2) * (2 * s$time - s$counts["tlbhits"]) + n(3) * (s$counts["swapin"] + s$counts["writebacks"])
            average <- floor(100 * total / s$time)
            emit("EAT accesses=", s$time, " total=", format(total, scientific = FALSE, trim = TRUE), " average=", sprintf("%d.%02d", average %/% 100, average %% 100))
        }
    } else if (cmd == "TIMELINE") {
        w <- n(1)
        if (w < 1) fail("invalid window")
        counts <- numeric()
        if (length(s$history)) for (i in seq.int(1, length(s$history), by = w)) counts <- c(counts, sum(s$history[i:min(i + w - 1, length(s$history))]))
        emit("TIMELINE window=", w, suffix(counts))
    } else if (cmd %in% c("WSET", "HOT")) {
        p <- get_process(s, n(1))
        k <- n(2)
        if (k < 1) fail(if (cmd == "WSET") "invalid window" else "invalid count")
        if (cmd == "WSET") {
            pages <- sort(unique(tail(p$history, k)))
            emit("WSET P", p$pid, " window=", k, " size=", length(pages), suffix(pages))
        } else {
            pages <- sort(unique(p$history))
            counts <- vapply(pages, function(pg) sum(p$history == pg), numeric(1))
            ix <- head(order(-counts, pages), k)
            emit("HOT P", p$pid, suffix(if (length(ix)) paste0(pages[ix], ":", counts[ix]) else character()))
        }
    }
}
expand <- function(lines) {
    items <- list()
    add <- function(pid, op, addr) items[[length(items) + 1]] <<- list(kind = "ACCESS", pid = as.numeric(pid), op = op, address = as.numeric(addr))
    for (line in lines) {
        w <- strsplit(line, " ", fixed = TRUE)[[1]]
        if (grepl("^[0-9]", w[1])) {
            add(w[1], w[2], address(w[3]))
        } else if (w[1] == "LOOP") {
            for (r in seq_len(as.integer(w[7]))) for (i in seq_len(as.integer(w[6])) - 1) add(w[2], w[3], address(w[4]) + i * as.numeric(w[5]))
        } else if (w[1] == "RAND") {
            x <- as.numeric(w[6])
            lo <- address(w[3])
            hi <- address(w[4])
            for (i in seq_len(as.integer(w[5]))) {
                x <- (48271 * x) %% 2147483647
                addr <- lo + x %% (hi - lo)
                x <- (48271 * x) %% 2147483647
                add(w[2], if (x %% 100 < as.numeric(w[7])) "W" else "R", addr)
            }
        } else {
            items[[length(items) + 1]] <- list(kind = w[1], words = w)
        }
    }
    items
}
main <- function() {
    options(scipen = 999)
    lines <- readLines(file("stdin"), warn = FALSE)
    items <- expand(lines[seq_len(as.integer(lines[1])) + 1])
    state <- new.env(parent = emptyenv())
    state$s <- NULL
    state$trace <- FALSE
    state$position <- 0
    state$events <- list()
    for (index in seq_along(items)) {
        item <- items[[index]]
        tryCatch({
            if (item$kind == "SYSTEM") {
                state$s <- NULL
                c <- settings(item$words[-1])
                refs <- list()
                if (index < length(items)) for (j in seq.int(index + 1, length(items))) {
                    future <- items[[j]]
                    if (future$kind == "SYSTEM") break
                    if (future$kind == "ACCESS") refs[[length(refs) + 1]] <- c(future$pid, future$address %/% c$page)
                }
                state$s <- simulation(c, refs)
                state$trace <- FALSE
                state$position <- 0
                state$events <- list()
                emit("SYSTEM ", paste(paste0(names(c), "=", unlist(c)), collapse = " "))
            } else {
                s <- state$s
                if (is.null(s)) fail("no system")
                if (item$kind == "ACCESS") {
                    state$position <- state$position + 1
                    p <- get_process(s, item$pid)
                    if (item$address >= length(p$pages) * s$config$page) {
                        p$seg <- p$seg + 1
                        emit("SEGFAULT P", item$pid, " ", hex(item$address))
                    } else if (item$op == "W" && p$pages[[item$address %/% s$config$page + 1]]$ro) {
                        p$prot <- p$prot + 1
                        emit("PROTFAULT P", item$pid, " ", hex(item$address))
                    } else {
                        output <- access(s, item, state$position)
                        state$events <- c(state$events, list(item))
                        if (state$trace) for (line in output) emit(line)
                    }
                } else {
                    command(state, item$words)
                }
            }
        }, command_error = function(e) emit("ERROR ", e$message))
    }
}
main()
