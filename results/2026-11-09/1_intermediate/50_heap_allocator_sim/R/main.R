block <- function(start, size) {
    b <- new.env(parent = emptyenv())
    b$start <- start
    b$size <- size
    b$owner <- ""
    b$requested <- 0
    b$data <- numeric()
    b$stamp <- 0
    b
}
used <- function(b) nzchar(b$owner)
area <- function(b) paste0(b$start, "+", b$size)
power2 <- function(x) x > 0 && x == 2^floor(log2(x))
heap <- function(size, mode) {
    h <- new.env(parent = emptyenv())
    h$size <- size
    h$mode <- mode
    h$rover <- 0
    h$age <- 0
    h$blocks <- list(register(h, block(0, size)))
    h
}
register <- function(h, b) {
    h$age <- h$age + 1
    b$stamp <- h$age
    b
}
required <- function(h, n) {
    s <- ceiling(n / 8) * 8 + 8
    if (h$mode == "BUDDY") s <- max(32, 2^ceiling(log2(s)))
    s
}
used_total <- function(h) sum(vapply(h$blocks, function(b) if (used(b)) b$size else 0, numeric(1)))
fragmentation <- function(h) {
    sizes <- vapply(Filter(function(b) !used(b), h$blocks), function(b) b$size, numeric(1))
    if (!length(sizes)) return(0)
    floor((sum(sizes) - max(sizes)) * 100 / sum(sizes))
}
insert_block <- function(h, i, b) h$blocks <- append(h$blocks, list(b), after = i - 1)
remove_block <- function(h, i) h$blocks <- h$blocks[-i]
halve <- function(h, i, s) {
    b <- h$blocks[[i]]
    while (b$size > s) {
        b$size <- b$size / 2
        insert_block(h, i + 1, register(h, block(b$start + b$size, b$size)))
    }
}
allocate <- function(h, s, al) {
    ri <- which(vapply(h$blocks, function(b) b$start <= h$rover && h$rover < b$start + b$size, logical(1)))[1]
    candidates <- list()
    for (i in seq_along(h$blocks)) {
        b <- h$blocks[[i]]
        if (used(b)) next
        p <- ceiling((b$start + 8) / al) * al - 8
        if (p > b$start && p - b$start < 16) p <- p + al
        if (p + s > b$start + b$size) next
        rank <- switch(h$mode,
            NEXT = c((i - ri) %% length(h$blocks), 0),
            BEST = c(b$size, b$start), BUDDY = c(b$size, b$start),
            WORST = c(-b$size, b$start),
            SEGFIT = c(floor(log2(b$size)), -b$stamp),
            c(b$start, 0))
        candidates[[length(candidates) + 1]] <- c(rank, i, p)
    }
    if (!length(candidates)) return(NULL)
    ranks <- do.call(rbind, candidates)
    choice <- ranks[order(ranks[, 1], ranks[, 2])[1], ]
    i <- choice[3]
    p <- choice[4]
    if (h$mode == "BUDDY") {
        halve(h, i, s)
        b <- h$blocks[[i]]
    } else {
        old <- h$blocks[[i]]
        parts <- list()
        if (p > old$start) parts <- list(register(h, block(old$start, p - old$start)))
        b <- block(p, old$start + old$size - p)
        parts <- c(parts, list(b))
        if (b$size - s >= 16) {
            parts <- c(parts, list(register(h, block(p + s, b$size - s))))
            b$size <- s
        }
        remove_block(h, i)
        h$blocks <- append(h$blocks, parts, after = i - 1)
    }
    b$owner <- "@"
    if (h$mode == "NEXT") h$rover <- (b$start + b$size) %% h$size
    b
}
coalesce <- function(h, i) {
    merges <- 0
    if (h$mode == "BUDDY") {
        while (h$blocks[[i]]$size < h$size) {
            b <- h$blocks[[i]]
            a <- if (b$start %% (2 * b$size) == 0) b$start + b$size else b$start - b$size
            js <- which(vapply(h$blocks, function(x) !used(x) && x$start == a && x$size == b$size, logical(1)))
            if (!length(js)) break
            i <- min(i, js[1])
            h$blocks[[i]]$size <- h$blocks[[i]]$size + h$blocks[[i + 1]]$size
            remove_block(h, i + 1)
            merges <- merges + 1
        }
    } else {
        if (i < length(h$blocks) && !used(h$blocks[[i + 1]])) {
            h$blocks[[i]]$size <- h$blocks[[i]]$size + h$blocks[[i + 1]]$size
            remove_block(h, i + 1)
            merges <- merges + 1
        }
        if (i > 1 && !used(h$blocks[[i - 1]])) {
            i <- i - 1
            h$blocks[[i]]$size <- h$blocks[[i]]$size + h$blocks[[i + 1]]$size
            remove_block(h, i + 1)
            merges <- merges + 1
        }
    }
    list(block = register(h, h$blocks[[i]]), merges = merges)
}
release <- function(h, b) {
    b$owner <- ""
    b$requested <- 0
    b$data <- numeric()
    i <- which(vapply(h$blocks, identical, logical(1), b))[1]
    coalesce(h, i)
}
resize <- function(h, b, s) {
    i <- which(vapply(h$blocks, identical, logical(1), b))[1]
    if (s <= b$size) {
        if (h$mode == "BUDDY") {
            if (s == b$size) return("kept")
            halve(h, i, s)
        } else {
            if (b$size - s < 16) return("kept")
            insert_block(h, i + 1, block(b$start + s, b$size - s))
            b$size <- s
            coalesce(h, i + 1)
        }
        return("shrunk")
    }
    if (h$mode == "BUDDY") {
        z <- b$size
        j <- i
        while (z < s) {
            j <- j + 1
            if (b$start %% (2 * z) != 0 || j > length(h$blocks)) return(NULL)
            p <- h$blocks[[j]]
            if (used(p) || p$size != z) return(NULL)
            z <- 2 * z
        }
        h$blocks <- h$blocks[-seq.int(i + 1, j)]
        b$size <- s
        return("grown")
    }
    if (i < length(h$blocks) && !used(h$blocks[[i + 1]])) {
        z <- b$size + h$blocks[[i + 1]]$size
        if (z >= s) {
            remove_block(h, i + 1)
            b$size <- z
            if (z - s >= 16) {
                b$size <- s
                insert_block(h, i + 1, register(h, block(b$start + s, z - s)))
            }
            return("grown")
        }
    }
    NULL
}
allocator <- function(h = NULL) {
    a <- new.env(parent = emptyenv())
    a$heap <- h
    a$live <- list()
    a$freed <- a$roots <- character()
    a$refs <- a$histories <- list()
    a$counts <- setNames(rep(0, 6), c("allocs", "frees", "reallocs", "moves", "failures", "collected"))
    a$peak <- 0
    a
}
emit <- function(...) cat(paste0(...), "\n", sep = "")
fail <- function(text) stop(structure(list(message = text), class = c("command_error", "error", "condition")))
record <- function(a, id, line) {
    emit(line)
    a$histories[[id]] <- c(a$histories[[id]], line)
}
live <- function(a, id) {
    if (!is.null(a$live[[id]])) return(a$live[[id]])
    fail(paste(if (id %in% a$freed) "USE AFTER FREE" else "UNKNOWN ID", id))
}
bounds <- function(a, id, off, len) {
    b <- live(a, id)
    if (off + len > b$requested) fail(paste("OUT OF BOUNDS", id))
    b
}
reachable <- function(a) {
    seen <- todo <- a$roots
    while (length(todo)) {
        id <- todo[1]
        todo <- todo[-1]
        fresh <- setdiff(a$refs[[id]], seen)
        seen <- c(seen, fresh)
        todo <- c(todo, fresh)
    }
    seen
}
malloc_id <- function(a, word, id, n, al = 8, value = -1) {
    if (n == 0) fail("BAD SIZE")
    if (!is.null(a$live[[id]])) fail(paste("DUPLICATE ID", id))
    b <- allocate(a$heap, required(a$heap, n), al)
    if (is.null(b)) {
        a$counts["failures"] <- a$counts["failures"] + 1
        fail(paste("OUT OF MEMORY", id))
    }
    b$owner <- id
    b$requested <- n
    b$data <- rep(value, n)
    a$live[[id]] <- b
    a$freed <- setdiff(a$freed, id)
    a$counts["allocs"] <- a$counts["allocs"] + 1
    record(a, id, paste0(word, " ", id, " addr=", b$start + 8, " block=", b$size))
}
release_id <- function(a, id) {
    b <- a$live[[id]]
    size <- b$size
    a$live[[id]] <- NULL
    a$freed <- union(a$freed, id)
    a$roots <- setdiff(a$roots, id)
    a$refs[[id]] <- NULL
    a$refs <- lapply(a$refs, setdiff, id)
    result <- release(a$heap, b)
    paste0("block=", size, " merges=", result$merges, " free=", area(result$block))
}
free_id <- function(a, id) {
    if (id %in% a$freed) fail(paste("DOUBLE FREE", id))
    if (is.null(a$live[[id]])) fail(paste("UNKNOWN ID", id))
    details <- release_id(a, id)
    a$counts["frees"] <- a$counts["frees"] + 1
    record(a, id, paste("FREE", id, details))
}
tree <- function(h, start, size, depth = 0) {
    label <- paste0(strrep(" ", 2 * depth), start, "+", size)
    leaves <- Filter(function(b) b$start == start && b$size == size, h$blocks)
    if (length(leaves)) {
        b <- leaves[[1]]
        emit(label, if (used(b)) paste0(" USED ", b$owner) else " FREE")
    } else {
        emit(label, " split")
        tree(h, start, size / 2, depth + 1)
        tree(h, start + size / 2, size / 2, depth + 1)
    }
}
experiment <- function(mode, size, seed, ops, maxreq) {
    h <- heap(size, mode)
    x <- seed
    active <- list()
    ok <- bad <- peak <- 0
    for (step in seq_len(ops)) {
        x <- (48271 * x) %% 2147483647
        alloc <- !length(active) || x %% 3 != 0
        x <- (48271 * x) %% 2147483647
        if (alloc) {
            b <- allocate(h, required(h, 1 + x %% maxreq), 8)
            if (is.null(b)) {
                bad <- bad + 1
            } else {
                ok <- ok + 1
                active <- c(active, list(b))
            }
        } else {
            i <- x %% length(active) + 1
            release(h, active[[i]])
            active <- active[-i]
        }
        peak <- max(peak, used_total(h))
    }
    emit("BENCH ", mode, " ok=", ok, " fail=", bad, " peak=", peak, " used=", used_total(h),
         " frag=", fragmentation(h), " blocks=", length(h$blocks))
}
execute <- function(a, words) {
    cmd <- words[1]
    v <- words[-1]
    num <- function(i) as.numeric(v[i])
    h <- a$heap
    if (cmd == "HEAP") {
        s <- num(1)
        m <- v[2]
        if (s %% 8 != 0 || s < 32 || s > 65536 || (m == "BUDDY" && !power2(s))) fail("BAD HEAP SIZE")
        fresh <- allocator(heap(s, m))
        for (name in ls(fresh)) a[[name]] <- fresh[[name]]
        emit("HEAP size=", s, " mode=", m)
    } else if (cmd == "BENCH") {
        s <- num(1)
        if (!power2(s) || s < 32 || s > 65536) fail("BAD HEAP SIZE")
        emit("BENCH heap=", s, " seed=", num(2), " ops=", num(3), " maxreq=", num(4))
        for (m in c("FIRST", "NEXT", "BEST", "WORST", "SEGFIT", "BUDDY")) experiment(m, s, num(2), num(3), num(4))
    } else if (is.null(h)) {
        fail("NO HEAP")
    } else if (cmd %in% c("MALLOC", "CALLOC", "MEMALIGN")) {
        al <- 8
        n <- num(2)
        value <- -1
        if (cmd == "CALLOC") {
            n <- num(2) * num(3)
            value <- 0
        } else if (cmd == "MEMALIGN") {
            if (h$mode == "BUDDY") fail("UNSUPPORTED IN BUDDY MODE")
            al <- num(2)
            n <- num(3)
            if (!power2(al) || al < 8 || al > 4096) fail("BAD ALIGNMENT")
        }
        malloc_id(a, cmd, v[1], n, al, value)
    } else if (cmd == "FREE") {
        free_id(a, v[1])
    } else if (cmd == "REALLOC") {
        id <- v[1]
        n <- num(2)
        if (n == 0) {
            free_id(a, id)
        } else if (id %in% a$freed) {
            fail(paste("USE AFTER FREE", id))
        } else if (is.null(a$live[[id]])) {
            malloc_id(a, "MALLOC", id, n)
        } else {
            b <- a$live[[id]]
            data <- rep(-1, n)
            k <- min(n, b$requested)
            if (k > 0) data[seq_len(k)] <- b$data[seq_len(k)]
            origin <- b$start + 8
            kind <- resize(h, b, required(h, n))
            if (is.null(kind)) {
                moved <- allocate(h, required(h, n), 8)
                if (is.null(moved)) {
                    a$counts["failures"] <- a$counts["failures"] + 1
                    fail(paste("OUT OF MEMORY", id))
                }
                moved$owner <- id
                a$live[[id]] <- moved
                release(h, b)
                b <- moved
                a$counts["moves"] <- a$counts["moves"] + 1
                kind <- paste0("moved from=", origin)
            }
            b$requested <- n
            b$data <- data
            a$counts["reallocs"] <- a$counts["reallocs"] + 1
            record(a, id, paste0("REALLOC ", id, " addr=", b$start + 8, " block=", b$size, " ", kind))
        }
    } else if (cmd %in% c("FILL", "READ")) {
        id <- v[1]
        off <- num(2)
        len <- num(3)
        b <- bounds(a, id, off, len)
        ix <- seq.int(off + 1, off + len)
        if (cmd == "FILL") {
            b$data[ix] <- num(4)
            emit("FILL ", id, " ", off, "+", len, " = ", num(4))
        } else {
            text <- paste(ifelse(b$data[ix] == -1, "?", b$data[ix]), collapse = " ")
            emit("READ ", id, " ", off, "+", len, " = ", text)
        }
    } else if (cmd == "COPY") {
        d <- bounds(a, v[1], num(2), num(5))
        s <- bounds(a, v[3], num(4), num(5))
        values <- s$data[seq.int(num(4) + 1, num(4) + num(5))]
        d$data[seq.int(num(2) + 1, num(2) + num(5))] <- values
        emit("COPY ", v[1], " ", num(2), "+", num(5), " from ", v[3], " ", num(4))
    } else if (cmd %in% c("ROOT", "UNROOT")) {
        id <- v[1]
        live(a, id)
        if (cmd == "ROOT") {
            a$roots <- union(a$roots, id)
        } else {
            if (!(id %in% a$roots)) fail(paste("NOT ROOT", id))
            a$roots <- setdiff(a$roots, id)
        }
        emit(cmd, " ", id)
    } else if (cmd %in% c("LINK", "UNLINK")) {
        live(a, v[1])
        live(a, v[2])
        if (cmd == "LINK") {
            a$refs[[v[1]]] <- union(a$refs[[v[1]]], v[2])
        } else {
            if (!(v[2] %in% a$refs[[v[1]]])) fail(paste("NO LINK", v[1], v[2]))
            a$refs[[v[1]]] <- setdiff(a$refs[[v[1]]], v[2])
        }
        emit(cmd, " ", v[1], " ", v[2])
    } else if (cmd == "GC") {
        seen <- reachable(a)
        garbage <- Filter(function(b) !(b$owner %in% seen), h$blocks)
        garbage <- Filter(used, garbage)
        bytes <- sum(vapply(garbage, function(b) b$size, numeric(1)))
        emit("GC collected=", length(garbage), " bytes=", bytes)
        for (b in garbage) {
            id <- b$owner
            record(a, id, paste("COLLECT", id, release_id(a, id)))
        }
        a$counts["collected"] <- a$counts["collected"] + length(garbage)
    } else if (cmd == "SBRK") {
        k <- num(1)
        valid <- if (h$mode == "BUDDY") k == h$size && 2 * h$size <= 65536 else k %% 8 == 0 && k >= 16 && h$size + k <= 65536
        if (!valid) fail("BAD SBRK SIZE")
        h$blocks <- c(h$blocks, list(block(h$size, k)))
        h$size <- h$size + k
        result <- coalesce(h, length(h$blocks))
        emit("SBRK heap=", h$size, " free=", area(result$block))
    } else if (cmd == "TRIM") {
        old <- h$size
        if (h$mode == "BUDDY") {
            repeat {
                b <- h$blocks[[length(h$blocks)]]
                if (used(b) || 2 * b$size != h$size) break
                h$size <- h$size - b$size
                remove_block(h, length(h$blocks))
            }
        } else if (length(h$blocks) >= 2 && !used(h$blocks[[length(h$blocks)]])) {
            h$size <- h$blocks[[length(h$blocks)]]$start
            remove_block(h, length(h$blocks))
        }
        if (h$rover >= h$size) h$rover <- 0
        emit("TRIM heap=", h$size, " released=", old - h$size)
    } else if (cmd == "COMPACT") {
        if (h$mode == "BUDDY") fail("UNSUPPORTED IN BUDDY MODE")
        packed <- Filter(used, h$blocks)
        moves <- list()
        pos <- 0
        for (b in packed) {
            if (b$start != pos) {
                moves <- c(moves, list(list(b = b, origin = b$start + 8)))
                b$start <- pos
            }
            pos <- pos + b$size
        }
        free <- if (pos == h$size) "none" else paste0(pos, "+", h$size - pos)
        if (pos < h$size) packed <- c(packed, list(register(h, block(pos, h$size - pos))))
        h$blocks <- packed
        h$rover <- 0
        a$counts["moves"] <- a$counts["moves"] + length(moves)
        emit("COMPACT moved=", length(moves), " free=", free)
        for (m in moves) record(a, m$b$owner, paste0("MOVE ", m$b$owner, " ", m$origin, " -> ", m$b$start + 8))
    } else if (cmd == "WHO") {
        p <- num(1)
        if (p >= h$size) {
            emit("WHO ", p, " outside")
        } else {
            b <- Filter(function(b) b$start <= p && p < b$start + b$size, h$blocks)[[1]]
            if (!used(b)) {
                emit("WHO ", p, " free ", area(b))
            } else if (p < b$start + 8) {
                emit("WHO ", p, " header ", b$owner)
            } else {
                d <- p - b$start - 8
                emit("WHO ", p, if (d < b$requested) " data " else " slack ", b$owner, "+", d)
            }
        }
    } else if (cmd == "DUMP") {
        tail <- if (h$mode == "NEXT") paste0(" rover=", h$rover) else ""
        emit("DUMP mode=", h$mode, " heap=", h$size, " blocks=", length(h$blocks), tail)
        for (b in h$blocks) emit(b$start, " ", b$size, if (used(b)) paste0(" USED ", b$owner, " req=", b$requested) else " FREE")
    } else if (cmd == "MAP") {
        emit("MAP heap=", h$size)
        chars <- character()
        for (b in h$blocks) {
            rest <- b$size / 8 - 1
            tail <- if (used(b)) ifelse(8 * (seq_len(rest) - 1) < b$requested, "#", "-") else rep(".", rest)
            chars <- c(chars, if (used(b)) "H" else "F", tail)
        }
        for (first in seq.int(1, length(chars), by = 64)) emit(sprintf("%05d", (first - 1) * 8), " ", paste(chars[first:min(first + 63, length(chars))], collapse = ""))
    } else if (cmd == "FREELIST") {
        free <- Filter(function(b) !used(b), h$blocks)
        if (h$mode == "SEGFIT" && length(free)) free <- free[order(vapply(free, function(b) -b$stamp, numeric(1)))]
        emit("FREELIST count=", length(free))
        classes <- sort(unique(vapply(free, function(b) floor(log2(b$size)), numeric(1))))
        for (k in classes) {
            members <- Filter(function(b) floor(log2(b$size)) == k, free)
            emit(2^k, "-", 2^(k + 1) - 1, ": ", paste(vapply(members, area, character(1)), collapse = " "))
        }
    } else if (cmd == "TREE") {
        if (h$mode != "BUDDY") fail("REQUIRES BUDDY MODE")
        emit("TREE heap=", h$size)
        tree(h, 0, h$size)
    } else if (cmd == "STATS") {
        u <- Filter(used, h$blocks)
        f <- Filter(function(b) !used(b), h$blocks)
        sizes <- vapply(f, function(b) b$size, numeric(1))
        req <- sum(vapply(u, function(b) b$requested, numeric(1)))
        emit("STATS used=", used_total(h), " used_blocks=", length(u), " free=", sum(sizes), " free_blocks=", length(f),
             " largest=", max(c(0, sizes)), " frag=", fragmentation(h), " requested=", req, " peak=", a$peak)
        emit("OPS ", paste(paste0(names(a$counts), "=", a$counts), collapse = " "))
    } else if (cmd == "LEAKS") {
        seen <- reachable(a)
        ids <- sort(names(a$live), method = "radix")
        req <- sum(vapply(a$live, function(b) b$requested, numeric(1)))
        emit("LEAKS count=", length(ids), " requested=", req, " lost=", sum(!(ids %in% seen)))
        for (id in ids) {
            b <- a$live[[id]]
            emit("LEAK ", id, " addr=", b$start + 8, " block=", b$size, " req=", b$requested, if (id %in% seen) " reachable" else " lost")
        }
    } else if (cmd == "HISTORY") {
        events <- a$histories[[v[1]]]
        emit("HISTORY ", v[1], " events=", length(events))
        for (line in events) emit(line)
    }
}
main <- function() {
    options(scipen = 999)
    input <- readLines(file("stdin"), warn = FALSE)
    a <- allocator()
    for (i in seq_len(as.integer(input[1]))) {
        words <- strsplit(input[i + 1], " ", fixed = TRUE)[[1]]
        tryCatch(execute(a, words), command_error = function(e) emit("ERROR ", e$message))
        if (!is.null(a$heap)) a$peak <- max(a$peak, used_total(a$heap))
    }
}
main()
