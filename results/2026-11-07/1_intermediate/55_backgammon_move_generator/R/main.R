options(scipen = 999)
line <- function(...) cat(..., "\n", sep = "")
color <- function(side) if (side == 1L) "W" else "B"
owner <- function(s) if (!s$owner) "center" else color(s$owner)
initial <- function() {
    pos <- matrix(0, 2L, 26L)
    for (side in 1:2) pos[side, c(25, 14, 9, 7)] <- c(2, 5, 3, 5)
    list(position = pos, side = 1L, cube = 1, owner = 0L, pending = FALSE, over = FALSE, score = c(0, 0))
}
random_source <- function(seed) {
    rng <- new.env(parent = emptyenv())
    rng$value <- seed
    rng
}
random <- function(rng) {
    rng$value <- (rng$value * 48271) %% 2147483647
    rng$value
}
die <- function(rng) random(rng) %% 6 + 1
pips <- function(pos, side) sum((1:25) * pos[side, 2:26])
keith <- function(pos, side) {
    c <- pos[side, ]
    pips(pos, side) + 2 * max(c[2] - 1, 0) + max(c[3] - 1, 0) + max(c[4] - 3, 0) + sum(c[5:7] == 0)
}
contact <- function(pos) {
    white <- if (pos[1, 26] > 0) 25 else 0
    black <- if (pos[2, 26] > 0) 0 else 25
    for (p in 1:24) {
        if (pos[1, p + 1L] > 0) white <- max(white, p)
        if (pos[2, p + 1L] > 0) black <- min(black, 25 - p)
    }
    white > black
}
evaluate <- function(pos, side) {
    other <- 3L - side
    P <- pips(pos, other) - pips(pos, side)
    G <- pos[other, 26] - pos[side, 26]
    S <- H <- R <- A <- run <- 0
    for (p in 1:24) {
        if (pos[side, p + 1L] >= 2) {
            run <- run + 1L
            R <- max(R, run)
            H <- H + (p <= 6)
            A <- A + (p >= 19)
        } else {
            run <- 0L
        }
        if (pos[side, p + 1L] == 1) {
            q <- 0:(p - 1L)
            distances <- p - q[pos[other, 26L - q] > 0]
            for (a in 1:6) {
                for (b in 1:6) {
                    hit <- a %in% distances || b %in% distances || (a + b) %in% distances || (a == b && ((3 * a) %in% distances || (4 * a) %in% distances))
                    S <- S + hit
                }
            }
        }
    }
    list(E = 2 * P - S + 4 * H + 3 * R + 3 * A + 6 * G, P = P, S = S, H = H, R = R, A = A, G = G)
}
cube_decision <- function(s, prohibited = FALSE) {
    if (s$owner == 3L - s$side || s$cube == 64 || prohibited) return("unavailable")
    if (contact(s$position)) {
        E <- evaluate(s$position, s$side)$E
        if (E < 60) return("no double")
        return(if (E <= 100) "double take" else "double drop")
    }
    V <- 8 * keith(s$position, s$side) - 7 * keith(s$position, 3L - s$side)
    L <- if (!s$owner) 28 else 21
    if (V > L) return("no double")
    if (V >= 14) "double take" else "double drop"
}
submoves <- function(pos, side, die) {
    sources <- if (pos[side, 26] > 0) 25L else (24:1)[pos[side, 25:2] > 0]
    home <- pos[side, 26] == 0 && all(pos[side, 8:25] == 0)
    moves <- list()
    for (from in sources) {
        to <- from - die
        if (to >= 1) {
            if (pos[3L - side, 26L - to] < 2) moves[[length(moves) + 1L]] <- c(from, to)
        } else if (home) {
            allowed <- TRUE
            if (to < 0 && from < 6) allowed <- all(pos[side, seq.int(from + 2L, 7L)] == 0)
            if (allowed) moves[[length(moves) + 1L]] <- c(from, 0)
        }
    }
    moves
}
apply_submove <- function(pos, side, move) {
    from <- move[1]
    to <- move[2]
    pos[side, from + 1L] <- pos[side, from + 1L] - 1L
    pos[side, to + 1L] <- pos[side, to + 1L] + 1L
    hit <- to > 0 && pos[3L - side, 26L - to] == 1
    if (hit) {
        pos[3L - side, 26L - to] <- 0
        pos[3L - side, 26] <- pos[3L - side, 26] + 1L
    }
    list(position = pos, hit = hit)
}
sort_pairs <- function(pairs) {
    if (!length(pairs)) return(pairs)
    pairs[order(-vapply(pairs, function(p) p[1], numeric(1)), -vapply(pairs, function(p) p[2], numeric(1)))]
}
canonical <- function(moves, hits) {
    key <- sort_pairs(moves)
    repeat {
        first <- second <- 0L
        for (i in seq_along(key)) {
            to <- key[[i]][2]
            if (!to || to %in% hits) next
            matches <- which(vapply(key, function(b) b[1] == to, logical(1)))
            if (length(matches)) {
                first <- i
                second <- matches[1L]
                break
            }
        }
        if (!first) break
        combined <- c(key[[first]][1], key[[second]][2])
        key <- key[-c(first, second)]
        key[[length(key) + 1L]] <- combined
        key <- sort_pairs(key)
    }
    parts <- character()
    marked <- numeric()
    i <- 1L
    while (i <= length(key)) {
        pair <- key[[i]]
        j <- i + 1L
        while (j <= length(key) && all(key[[j]] == pair)) j <- j + 1L
        from <- if (pair[1] == 25) "bar" else as.character(pair[1])
        to <- if (!pair[2]) "off" else as.character(pair[2])
        part <- paste0(from, "/", to)
        if (pair[2] %in% hits && !(pair[2] %in% marked)) {
            part <- paste0(part, "*")
            marked <- c(marked, pair[2])
        }
        if (j - i >= 2L) part <- paste0(part, "(", j - i, ")")
        parts <- c(parts, part)
        i <- j
    }
    list(key = key, notation = if (length(parts)) paste(parts, collapse = " ") else "none")
}
key_less <- function(a, b) {
    for (i in seq_len(min(length(a), length(b)))) {
        if (a[[i]][1] != b[[i]][1]) return(a[[i]][1] > b[[i]][1])
        if (a[[i]][2] != b[[i]][2]) return(a[[i]][2] > b[[i]][2])
    }
    length(a) > length(b)
}
sort_plays <- function(plays) {
    if (length(plays) < 2L) return(plays)
    merge <- function(a, b) {
        result <- list()
        i <- j <- 1L
        while (i <= length(a) && j <= length(b)) {
            if (key_less(b[[j]]$key, a[[i]]$key)) {
                result[[length(result) + 1L]] <- b[[j]]
                j <- j + 1L
            } else {
                result[[length(result) + 1L]] <- a[[i]]
                i <- i + 1L
            }
        }
        if (i <= length(a)) result <- c(result, a[seq.int(i, length(a))])
        if (j <= length(b)) result <- c(result, b[seq.int(j, length(b))])
        result
    }
    middle <- length(plays) %/% 2L
    merge(sort_plays(plays[seq_len(middle)]), sort_plays(plays[seq.int(middle + 1L, length(plays))]))
}
enumerate_plays <- function(pos, side, d1, d2) {
    dice <- if (d1 == d2) rep(d1, 4L) else c(d1, d2)
    possible <- list()
    maximum <- 0L
    search <- function(current, left, path, hits, first) {
        possible[[length(possible) + 1L]] <<- list(position = current, moves = path, hits = hits, die = first)
        maximum <<- max(maximum, length(path))
        seen <- numeric()
        for (i in seq_along(left)) {
            die <- left[i]
            if (die %in% seen) next
            seen <- c(seen, die)
            rest <- left[-i]
            for (move in submoves(current, side, die)) {
                next_state <- apply_submove(current, side, move)
                next_hits <- if (next_state$hit) union(hits, move[2]) else hits
                search(next_state$position, rest, c(path, list(move)), next_hits, if (length(path)) first else die)
            }
        }
    }
    search(pos, dice, list(), numeric(), 0)
    larger <- maximum == 1L && d1 != d2 && any(vapply(possible, function(p) length(p$moves) == 1L && p$die == max(d1, d2), logical(1)))
    legal <- list()
    positions <- new.env(hash = TRUE, parent = emptyenv())
    for (p in possible) {
        if (length(p$moves) != maximum || (larger && p$die != max(d1, d2))) next
        key <- paste(as.vector(p$position), collapse = ",")
        if (exists(key, envir = positions, inherits = FALSE)) next
        normalized <- canonical(p$moves, p$hits)
        p$key <- normalized$key
        p$notation <- normalized$notation
        legal[[length(legal) + 1L]] <- p
        positions[[key]] <- TRUE
    }
    list(legal = sort_plays(legal), possible = possible, maximum = maximum)
}
best <- function(plays, side) {
    chosen <- plays[[1L]]
    score <- evaluate(chosen$position, side)$E
    for (p in plays[-1L]) {
        value <- evaluate(p$position, side)$E
        if (value > score) {
            chosen <- p
            score <- value
        }
    }
    list(play = chosen, value = score)
}
multiplier <- function(kind) if (kind == "gammon") 2L else if (kind == "backgammon") 3L else 1L
finish <- function(s, winner, kind) {
    s$pending <- FALSE
    s$over <- TRUE
    points <- multiplier(kind) * s$cube
    s$score[winner] <- s$score[winner] + points
    list(state = s, winner = winner, kind = kind, points = points)
}
bear_result <- function(s, winner) {
    other <- 3L - winner
    kind <- "single"
    if (s$position[other, 1] == 0) {
        back <- s$position[other, 26] > 0 || any(s$position[other, 20:25] > 0)
        kind <- if (back) "backgammon" else "gammon"
    }
    finish(s, winner, kind)
}
result_line <- function(r) paste("result", color(r$winner), r$kind, r$points)
engine <- new.env(parent = emptyenv())
engine$state <- initial()
engine$history <- list()
engine$redo <- list()
make_play <- function(play, d1, d2) {
    before <- engine$state
    s <- before
    side <- s$side
    s$position <- play$position
    result <- NULL
    if (s$position[side, 1] == 15) {
        result <- bear_result(s, side)
        s <- result$state
    } else {
        s$side <- 3L - side
    }
    record <- paste(color(side), paste0(d1, "-", d2), play$notation)
    engine$history[[length(engine$history) + 1L]] <- list(record = record, before = before, after = s)
    engine$state <- s
    engine$redo <- list()
    if (!is.null(result)) line(result_line(result))
}
parse_play <- function(words) {
    if (identical(words, "none")) return(list())
    moves <- list()
    pattern <- "^(bar|[1-9]|1[0-9]|2[0-4])(?:/(?:[1-9]|1[0-9]|2[0-4])\\*?)*(?:/off|/(?:[1-9]|1[0-9]|2[0-4])\\*?)(?:\\([234]\\))?$"
    for (word in words) {
        if (!grepl(pattern, word, perl = TRUE)) return(NULL)
        count <- 1L
        if (endsWith(word, ")")) {
            count <- as.integer(substring(word, nchar(word) - 1L, nchar(word) - 1L))
            word <- substring(word, 1L, nchar(word) - 3L)
        }
        parts <- strsplit(word, "/", fixed = TRUE)[[1]]
        points <- vapply(parts, function(part) {
            if (part == "bar") 25 else if (part == "off") 0 else as.numeric(sub("\\*$", "", part))
        }, numeric(1))
        for (i in seq_len(length(points) - 1L)) {
            if (points[i] <= points[i + 1L]) return(NULL)
            for (j in seq_len(count)) moves[[length(moves) + 1L]] <- points[c(i, i + 1L)]
        }
    }
    moves
}
validate_play <- function(pos, side, moves, generated) {
    final <- pos
    destinations <- numeric()
    nonbar <- bear <- FALSE
    for (move in moves) {
        from <- move[1]
        to <- move[2]
        final[side, from + 1L] <- final[side, from + 1L] - 1L
        final[side, to + 1L] <- final[side, to + 1L] + 1L
        destinations <- union(destinations, to)
        nonbar <- nonbar || from != 25
        bear <- bear || to == 0
    }
    for (to in destinations) {
        if (to > 0 && pos[3L - side, 26L - to] == 1) {
            final[3L - side, 26L - to] <- 0
            final[3L - side, 26] <- final[3L - side, 26] + 1L
        }
    }
    reject <- function(reason) list(play = NULL, reason = reason)
    if (any(final[side, 2:26] < 0)) return(reject("no checker"))
    if (final[side, 26] > 0 && nonbar) return(reject("bar"))
    if (any(vapply(destinations, function(to) to > 0 && pos[3L - side, 26L - to] >= 2, logical(1)))) return(reject("blocked"))
    if (bear && (final[side, 26] > 0 || any(final[side, 8:25] > 0))) return(reject("bear-off"))
    for (p in generated$legal) {
        if (all(p$position == final)) return(list(play = p, reason = ""))
    }
    matched <- Filter(function(p) all(p$position == final), generated$possible)
    if (any(vapply(matched, function(p) length(p$moves) < generated$maximum, logical(1)))) return(reject("too few dice"))
    if (length(matched)) return(reject("larger die required"))
    reject("impossible")
}
simulation <- function(s, rng, strategies, opening = FALSE, target = 0, score = c(0, 0), crawford = FALSE, verbose = FALSE) {
    first_dice <- c(0, 0)
    if (opening) {
        while (first_dice[1] == first_dice[2]) first_dice <- c(die(rng), die(rng))
        s$side <- if (first_dice[1] > first_dice[2]) 1L else 2L
    }
    start <- s$side
    turns <- 0L
    t <- 1L
    repeat {
        side <- s$side
        other <- 3L - side
        if (opening && t == 1L) {
            d1 <- first_dice[1]
            d2 <- first_dice[2]
        } else {
            prohibited <- target > 0 && (crawford || score[side] + s$cube >= target)
            decision <- cube_decision(s, prohibited)
            if (decision %in% c("double take", "double drop")) {
                if (verbose) line(t, " ", color(side), " doubles ", s$cube * 2)
                if (decision == "double drop") {
                    if (verbose) line(t, " ", color(other), " drops")
                    r <- finish(s, side, "drop")
                    r$turns <- turns
                    r$start <- start
                    return(r)
                }
                s$cube <- s$cube * 2
                s$owner <- other
                if (verbose) line(t, " ", color(other), " takes")
            }
            d1 <- die(rng)
            d2 <- die(rng)
        }
        plays <- enumerate_plays(s$position, side, d1, d2)$legal
        chosen <- plays[[1L]]
        if (strategies[side] == "BEST") chosen <- best(plays, side)$play
        if (strategies[side] == "RANDOM") chosen <- plays[[random(rng) %% length(plays) + 1L]]
        s$position <- chosen$position
        turns <- turns + 1L
        if (verbose) line(t, " ", color(side), " ", d1, "-", d2, " ", chosen$notation)
        if (s$position[side, 1] == 15) {
            r <- bear_result(s, side)
            r$turns <- turns
            r$start <- start
            return(r)
        }
        s$side <- other
        t <- t + 1L
    }
}
board <- function(s) {
    format_row <- function(values) paste0(paste(sprintf("%3s", values[1:6]), collapse = ""), " |", paste(sprintf("%3s", values[7:12]), collapse = ""))
    for (half in 0:1) {
        points <- if (!half) 13:24 else 12:1
        if (!half) line(format_row(as.character(points)))
        for (row in 1:5) {
            level <- if (!half) row else 6L - row
            fields <- character()
            for (p in points) {
                count <- s$position[1, p + 1L]
                letter <- "W"
                if (!count) {
                    count <- s$position[2, 26L - p]
                    letter <- "B"
                }
                value <- if (count >= level) letter else "."
                if (level == 5L && count > 5) value <- as.character(count)
                fields <- c(fields, value)
            }
            line(format_row(fields))
        }
        if (!half) {
            status <- if (s$over) "game over" else if (s$pending) paste(color(s$side), "doubles") else paste(color(s$side), "to move")
            line("bar W", s$position[1, 26], " B", s$position[2, 26], " | off W", s$position[1, 1], " B", s$position[2, 1], " | cube ", s$cube, " ", owner(s), " | ", status)
        } else {
            line(format_row(as.character(points)))
        }
    }
}
execute <- function(words) {
    cmd <- words[1]
    a <- words[-1]
    noargs <- c("NEW", "SHOW", "BOARD", "PIPS", "RACE", "EVAL", "SHOTS", "CUBE", "DOUBLE", "TAKE", "DROP", "SCORE", "HISTORY")
    others <- c("POS", "MOVES", "PLAY", "AUTO", "HINT", "RESIGN", "UNDO", "REDO", "GAME", "MATCH", "STATS")
    if (!(cmd %in% c(noargs, others))) {
        line("ERROR unknown command")
        return()
    }
    arg <- function(at, lo, hi) at <= length(a) && as.numeric(a[at]) >= lo && as.numeric(a[at]) <= hi
    valid <- !(cmd %in% noargs) || !length(a)
    if (cmd == "POS") valid <- length(a) == 4L
    if (cmd %in% c("MOVES", "AUTO")) valid <- length(a) == 2L && arg(1, 1, 6) && arg(2, 1, 6)
    if (cmd == "PLAY") valid <- length(a) >= 3L && arg(1, 1, 6) && arg(2, 1, 6)
    if (cmd == "HINT") valid <- length(a) == 3L && arg(1, 1, 6) && arg(2, 1, 6) && arg(3, 1, 1000)
    if (cmd == "RESIGN") valid <- length(a) == 1L && a[1] %in% c("single", "gammon", "backgammon")
    if (cmd %in% c("UNDO", "REDO")) valid <- length(a) == 1L && arg(1, 1, 1000)
    if (cmd == "GAME") valid <- length(a) == 3L && arg(1, 1, 2147483646) && all(a[2:3] %in% c("BEST", "FIRST", "RANDOM"))
    if (cmd == "MATCH") valid <- length(a) == 2L && arg(1, 1, 15) && arg(2, 1, 2147483646)
    if (cmd == "STATS") valid <- length(a) == 2L && arg(1, 1, 50) && arg(2, 1, 2147483646)
    if (cmd == "POS" && valid) {
        points <- as.numeric(strsplit(a[1], ",", fixed = TRUE)[[1]])
        valid <- length(points) == 24L && arg(2, 0, 15) && arg(3, 0, 15) && a[4] %in% c("W", "B")
        s <- initial()
        s$position[,] <- 0
        s$score <- engine$state$score
        if (valid) {
            s$position[1, 26] <- as.numeric(a[2])
            s$position[2, 26] <- as.numeric(a[3])
            for (i in seq_along(points)) {
                if (points[i] > 0) s$position[1, i + 1L] <- points[i]
                if (points[i] < 0) s$position[2, 26L - i] <- -points[i]
            }
            for (side in 1:2) {
                s$position[side, 1] <- 15 - sum(s$position[side, 2:26])
                valid <- valid && s$position[side, 1] >= 0 && s$position[side, 1] <= 14
            }
            s$side <- if (a[4] == "W") 1L else 2L
        }
        if (valid) {
            engine$state <- s
            engine$history <- engine$redo <- list()
            line("OK")
            return()
        }
    }
    if (!valid) {
        line(if (cmd == "POS") "ERROR bad position" else "ERROR bad arguments")
        return()
    }
    s <- engine$state
    after <- c("RACE", "MOVES", "PLAY", "AUTO", "HINT", "EVAL", "SHOTS", "CUBE", "DOUBLE", "TAKE", "DROP", "RESIGN", "GAME")
    pending <- c("PLAY", "AUTO", "CUBE", "DOUBLE", "RESIGN", "GAME")
    if (s$over && cmd %in% after) {
        line("ERROR game over")
        return()
    }
    if (s$pending && cmd %in% pending) {
        line("ERROR double pending")
        return()
    }
    if (cmd == "NEW") {
        fresh <- initial()
        fresh$score <- s$score
        engine$state <- fresh
        engine$history <- engine$redo <- list()
        line("OK")
    } else if (cmd == "SHOW") {
        points <- s$position[1, 2:25] - s$position[2, 25:2]
        line("POS ", paste(points, collapse = ","), " ", s$position[1, 26], " ", s$position[2, 26], " ", color(s$side))
    } else if (cmd == "BOARD") {
        board(s)
    } else if (cmd == "PIPS") {
        line("pips W ", pips(s$position, 1L), " B ", pips(s$position, 2L))
    } else if (cmd == "RACE") {
        if (contact(s$position)) line("contact") else line("race W ", keith(s$position, 1L), " B ", keith(s$position, 2L))
    } else if (cmd == "EVAL") {
        v <- evaluate(s$position, s$side)
        line("eval ", v$E, " pips ", v$P, " blots ", v$S, " home ", v$H, " prime ", v$R, " anchors ", v$A, " bar ", v$G)
    } else if (cmd %in% c("MOVES", "PLAY", "AUTO", "HINT")) {
        d1 <- as.numeric(a[1])
        d2 <- as.numeric(a[2])
        if (cmd == "PLAY") {
            moves <- parse_play(a[-c(1L, 2L)])
            if (is.null(moves)) {
                line("ILLEGAL syntax")
                return()
            }
            generated <- enumerate_plays(s$position, s$side, d1, d2)
            result <- validate_play(s$position, s$side, moves, generated)
            if (nzchar(result$reason)) {
                line("ILLEGAL ", result$reason)
            } else {
                line("OK ", result$play$notation)
                make_play(result$play, d1, d2)
            }
            return()
        }
        legal <- enumerate_plays(s$position, s$side, d1, d2)$legal
        if (cmd == "MOVES") {
            for (play in legal) line(play$notation)
            line("total ", length(legal))
        } else if (cmd == "AUTO") {
            chosen <- best(legal, s$side)
            line("OK ", chosen$play$notation, " eval ", chosen$value)
            make_play(chosen$play, d1, d2)
        } else {
            scores <- vapply(legal, function(p) evaluate(p$position, s$side)$E, numeric(1))
            order_ids <- order(-scores, seq_along(legal))
            for (i in head(order_ids, as.integer(a[3]))) line(scores[i], " ", legal[[i]]$notation)
        }
    } else if (cmd == "SHOTS") {
        blots <- (24:1)[s$position[s$side, 25:2] == 1]
        counts <- setNames(numeric(length(blots)), as.character(blots))
        total <- 0L
        rolls <- character()
        for (a in 6:1) {
            for (b in seq(a, 1L)) {
                legal <- enumerate_plays(s$position, 3L - s$side, a, b)$legal
                hit <- blots[vapply(blots, function(p) any(vapply(legal, function(play) (25L - p) %in% play$hits, logical(1))), logical(1))]
                weight <- if (a == b) 1L else 2L
                if (length(hit)) {
                    total <- total + weight
                    rolls <- c(rolls, paste0(a, "-", b))
                }
                for (p in hit) counts[as.character(p)] <- counts[as.character(p)] + weight
            }
        }
        suffix <- if (length(rolls)) paste0(" ", paste(rolls, collapse = " ")) else ""
        line("shots ", total, "/36", suffix)
        for (p in blots) line("blot ", p, " ", counts[as.character(p)], "/36")
    } else if (cmd == "CUBE") {
        line("cube ", cube_decision(s))
    } else if (cmd == "DOUBLE") {
        if (s$owner == 3L - s$side || s$cube == 64) {
            line("ERROR cube unavailable")
        } else {
            engine$state$pending <- TRUE
            engine$redo <- list()
            line("OK double ", s$cube * 2)
        }
    } else if (cmd == "TAKE") {
        if (!s$pending) {
            line("ERROR no double")
        } else {
            s$pending <- FALSE
            s$cube <- s$cube * 2
            s$owner <- 3L - s$side
            engine$state <- s
            engine$redo <- list()
            line("OK take ", s$cube, " ", owner(s))
        }
    } else if (cmd == "DROP") {
        if (!s$pending) {
            line("ERROR no double")
        } else {
            result <- finish(s, s$side, "drop")
            engine$state <- result$state
            engine$redo <- list()
            line("OK drop")
            line(result_line(result))
        }
    } else if (cmd == "RESIGN") {
        result <- finish(s, 3L - s$side, a[1])
        engine$state <- result$state
        engine$redo <- list()
        line("OK resign")
        line(result_line(result))
    } else if (cmd == "SCORE") {
        line("score W ", s$score[1], " B ", s$score[2])
    } else if (cmd == "HISTORY") {
        line("history ", length(engine$history))
        for (i in seq_along(engine$history)) line(i, " ", engine$history[[i]]$record)
    } else if (cmd == "UNDO") {
        n <- as.integer(a[1])
        if (n > length(engine$history)) {
            line("ERROR cannot undo")
        } else {
            index <- length(engine$history) - n + 1L
            engine$state <- engine$history[[index]]$before
            engine$redo <- c(engine$history[seq.int(index, length(engine$history))], engine$redo)
            engine$history <- engine$history[seq_len(index - 1L)]
            line("OK")
        }
    } else if (cmd == "REDO") {
        n <- as.integer(a[1])
        if (n > length(engine$redo)) {
            line("ERROR cannot redo")
        } else {
            engine$state <- engine$redo[[n]]$after
            engine$history <- c(engine$history, engine$redo[seq_len(n)])
            engine$redo <- engine$redo[-seq_len(n)]
            line("OK")
        }
    } else if (cmd == "GAME") {
        result <- simulation(s, random_source(as.numeric(a[1])), a[2:3], verbose = TRUE)
        line(result_line(result))
    } else if (cmd == "MATCH") {
        target <- as.numeric(a[1])
        rng <- random_source(as.numeric(a[2]))
        score <- c(0, 0)
        used <- FALSE
        game <- 0L
        while (max(score) < target) {
            game <- game + 1L
            crawford <- !used && max(score) == target - 1L
            used <- used || crawford
            r <- simulation(initial(), rng, c("BEST", "BEST"), opening = TRUE, target = target, score = score, crawford = crawford)
            score[r$winner] <- score[r$winner] + r$points
            label <- if (crawford) " crawford" else ""
            line("game ", game, label, " start ", color(r$start), " turns ", r$turns, " result ", color(r$winner), " ", r$kind, " ", r$points, " score ", score[1], "-", score[2])
        }
        winner <- if (score[1] >= target) 1L else 2L
        line("match ", color(winner), " ", score[1], "-", score[2])
    } else if (cmd == "STATS") {
        rng <- random_source(as.numeric(a[2]))
        kinds <- c("single", "gammon", "backgammon", "drop")
        counts <- setNames(rep(list(c(0, 0)), 4L), kinds)
        points <- c(0, 0)
        turns <- 0
        for (i in seq_len(as.integer(a[1]))) {
            r <- simulation(initial(), rng, c("BEST", "BEST"), opening = TRUE)
            counts[[r$kind]][r$winner] <- counts[[r$kind]][r$winner] + 1L
            points[r$winner] <- points[r$winner] + r$points
            turns <- turns + r$turns
        }
        for (kind in kinds) line(kind, " W ", counts[[kind]][1], " B ", counts[[kind]][2])
        line("points W ", points[1], " B ", points[2])
        line("turns ", turns)
    }
}
input <- file("stdin", "r")
n <- as.integer(readLines(input, n = 1L))
for (i in seq_len(n)) execute(strsplit(readLines(input, n = 1L), " ", fixed = TRUE)[[1]])
close(input)
