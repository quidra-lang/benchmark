kinds <- c("I", "O", "T", "S", "Z", "J", "L")
state_names <- c("0", "R", "2", "L")
movements <- c("L", "R", "LL", "RR", "SD", "DD", "CW", "CCW")
operations <- c(movements, "HD", "LOCK", "HOLD")
shape_rows <- list(I = c("....", "####", "....", "...."), O = c("##", "##"),
                   T = c(".#.", "###", "..."), S = c(".##", "##.", "..."),
                   Z = c("##.", ".##", "..."), J = c("#..", "###", "..."),
                   L = c("..#", "###", "..."))
shapes <- lapply(shape_rows, function(rows) {
    cells <- matrix(integer(), ncol = 2)
    for (j in seq_along(rows)) {
        marks <- strsplit(rows[j], "", fixed = TRUE)[[1]]
        for (i in which(marks == "#")) cells <- rbind(cells, c(i - 1L, j - 1L))
    }
    states <- vector("list", 4)
    for (s in 1:4) {
        states[[s]] <- cells
        cells <- cbind(length(rows) - 1L - cells[, 2], cells[, 1])
    }
    states
})
kick_matrix <- function(...) matrix(c(...), ncol = 2, byrow = TRUE)
kicks <- list(
    `01` = kick_matrix(0,0,-1,0,-1,1,0,-2,-1,-2),
    `10` = kick_matrix(0,0,1,0,1,-1,0,2,1,2),
    `12` = kick_matrix(0,0,1,0,1,-1,0,2,1,2),
    `21` = kick_matrix(0,0,-1,0,-1,1,0,-2,-1,-2),
    `23` = kick_matrix(0,0,1,0,1,1,0,-2,1,-2),
    `32` = kick_matrix(0,0,-1,0,-1,-1,0,2,-1,2),
    `30` = kick_matrix(0,0,-1,0,-1,-1,0,2,-1,2),
    `03` = kick_matrix(0,0,1,0,1,1,0,-2,1,-2))
i_kicks <- list(
    `01` = kick_matrix(0,0,-2,0,1,0,-2,-1,1,2),
    `10` = kick_matrix(0,0,2,0,-1,0,2,1,-1,-2),
    `12` = kick_matrix(0,0,-1,0,2,0,-1,2,2,-1),
    `21` = kick_matrix(0,0,1,0,-2,0,1,-2,-2,1),
    `23` = kick_matrix(0,0,2,0,-1,0,2,1,-1,-2),
    `32` = kick_matrix(0,0,-2,0,1,0,-2,-1,1,2),
    `30` = kick_matrix(0,0,1,0,-2,0,1,-2,-2,1),
    `03` = kick_matrix(0,0,-1,0,2,0,-1,2,2,-1))
clear_names <- c("SINGLE", "DOUBLE", "TRIPLE", "TETRIS", "TSPIN_MINI",
                 "TSPIN_MINI_SINGLE", "TSPIN_MINI_DOUBLE", "TSPIN",
                 "TSPIN_SINGLE", "TSPIN_DOUBLE", "TSPIN_TRIPLE")
base_points <- c(100,300,500,800,100,200,400,400,800,1200,1600)
send_lines <- c(0,1,2,4,0,0,1,0,2,4,6)
gravity <- c(60,48,37,28,21,16,11,8,6,4,3,2)
game <- NULL
game_serial <- 0

emit <- function(...) {
    parts <- lapply(list(...), function(x) {
        if (is.numeric(x)) format(x, scientific = FALSE, trim = TRUE, digits = 22) else x
    })
    cat(paste(unlist(parts, use.names = FALSE), collapse = " "), "\n", sep = "")
}
spawn_position <- function(kind) c(0L, if (kind == "O") 5L else 4L, 22L)
cells_at <- function(kind, position) {
    blocks <- shapes[[kind]][[position[1] + 1L]]
    cbind(position[2] + blocks[, 1], position[3] - blocks[, 2])
}
blocked <- function(board, col, row) {
    col < 1L || col > 10L || row < 1L || row > 22L || board[row, col]
}
fits <- function(board, kind, position) {
    cells <- cells_at(kind, position)
    if (any(cells[, 1] < 1L | cells[, 1] > 10L | cells[, 2] < 1L | cells[, 2] > 22L)) return(FALSE)
    !any(board[cbind(cells[, 2], cells[, 1])])
}
lower <- function(position) position + c(0L, 0L, -1L)
landing <- function(board, kind, position) {
    while (fits(board, kind, lower(position))) position <- lower(position)
    position
}
move_piece <- function(board, kind, position, operation) {
    if (operation %in% c("CW", "CCW")) {
        next_state <- (position[1] + if (operation == "CW") 1L else 3L) %% 4L
        key <- paste0(position[1], next_state)
        offsets <- if (kind == "O") matrix(c(0L, 0L), ncol = 2L) else if (kind == "I") i_kicks[[key]] else kicks[[key]]
        for (i in seq_len(nrow(offsets))) {
            next_position <- c(next_state, position[2:3] + offsets[i, ])
            if (fits(board, kind, next_position)) return(list(position = next_position, test = i))
        }
        return(NULL)
    }
    step <- switch(operation, L = c(0,-1,0), LL = c(0,-1,0),
                   R = c(0,1,0), RR = c(0,1,0), SD = c(0,0,-1), DD = c(0,0,-1))
    next_position <- position + step
    if (!fits(board, kind, next_position)) return(NULL)
    if (operation %in% c("LL", "RR", "DD")) {
        while (fits(board, kind, next_position + step)) next_position <- next_position + step
    }
    list(position = next_position, test = 0L)
}
placed_board <- function(board, kind, position) {
    cells <- cells_at(kind, position)
    board[cbind(cells[, 2], cells[, 1])] <- TRUE
    complete <- rowSums(board) == 10L
    count <- sum(complete)
    list(board = rbind(board[!complete, , drop = FALSE], matrix(FALSE, count, 10L)), lines = count)
}
well_metrics <- function(board, lines = 0) {
    heights <- vapply(seq_len(10), function(col) {
        filled <- which(board[, col])
        if (length(filled)) max(filled) else 0L
    }, integer(1))
    holes <- sum(vapply(seq_len(10), function(col) {
        h <- heights[col]
        if (h) sum(!board[seq_len(h), col]) else 0L
    }, integer(1)))
    bumpiness <- sum(abs(diff(heights)))
    list(heights = heights, holes = holes, bumpiness = bumpiness,
         value = 76 * lines - 51 * sum(heights) - 36 * holes - 18 * bumpiness)
}
random_next <- function(value) (48271 * value) %% 2147483647
bag <- function(value) {
    pieces <- kinds
    for (i in 7:2) {
        value <- random_next(value)
        j <- value %% i + 1
        pieces[c(i, j)] <- pieces[c(j, i)]
    }
    list(pieces = pieces, random = value)
}
add_bag <- function() {
    generated <- bag(game$random)
    game$queue <<- c(game$queue, generated$pieces)
    game$random <<- generated$random
}
take_piece <- function() {
    kind <- game$queue[1]
    game$queue <<- game$queue[-1]
    if (length(game$queue) < 5L) add_bag()
    kind
}
core_state <- function() game[setdiff(names(game), c("history", "start_state", "saves"))]
ratio <- function(a, b) {
    q <- if (b == 0) 0 else (100 * a) %/% b
    sprintf("%.0f.%02.0f", q %/% 100, q %% 100)
}
summary <- function() {
    g <- game
    emit("summary game", g$serial, "score", g$score, "level", g$level, "lines", g$lines, "pieces", g$pieces)
    emit("clears single", g$clears[1], "double", g$clears[2], "triple", g$clears[3], "tetris", g$clears[4], "perfect", g$perfect)
    emit("tspins mini", g$clears[5], "mini_single", g$clears[6], "mini_double", g$clears[7],
         "zero", g$clears[8], "single", g$clears[9], "double", g$clears[10], "triple", g$clears[11])
    parts <- character()
    for (kind in kinds) parts <- c(parts, kind, g$kind_counts[[kind]])
    emit("pieces", paste(parts, collapse = " "))
    emit("best combo", g$max_combo, "chain", g$max_chain, "holds", g$holds, "drops", g$drops, "faults", g$faults)
    emit("garbage sent", g$sent, "cancelled", g$cancelled, "received", g$received)
    emit("rates app", ratio(g$sent, g$pieces), "apl", ratio(g$sent, g$lines), "kpp", ratio(g$operation_total, g$pieces))
}
game_over <- function(reason) {
    game$ended <<- TRUE
    emit("game over", reason)
    summary()
    stop(structure(list(message = "", call = NULL), class = c("game_over", "error", "condition")))
}
spawn <- function(kind) {
    game$kind <<- kind
    game$position <<- spawn_position(kind)
    game$motion <<- "none"
    game$test <<- 0L
    game$keys <<- 0
    game$drop <<- 0
    game$fall_counter <<- 0L
    game$ground_counter <<- 0L
    game$resets <<- 0L
    game$lowest <<- min(cells_at(kind, game$position)[, 2])
    if (!fits(game$board, kind, game$position)) game_over("block out")
}
update_position <- function(position, motion, test = 0L) {
    game$position <<- position
    game$motion <<- motion
    game$test <<- test
    lowest <- min(cells_at(game$kind, position)[, 2])
    if (lowest < game$lowest) {
        game$lowest <<- lowest
        game$resets <<- 0L
    }
}
position_key <- function(position) paste(position, collapse = ",")
reachable <- function(board, kind, start) {
    seen <- new.env(hash = TRUE, parent = emptyenv())
    nodes <- list(list(position = start, previous = 0L, operation = ""))
    assign(position_key(start), TRUE, envir = seen)
    next_index <- 1L
    while (next_index <= length(nodes)) {
        position <- nodes[[next_index]]$position
        for (operation in movements) {
            result <- move_piece(board, kind, position, operation)
            if (is.null(result)) next
            key <- position_key(result$position)
            if (exists(key, envir = seen, inherits = FALSE)) next
            assign(key, TRUE, envir = seen)
            nodes[[length(nodes) + 1L]] <- list(position = result$position, previous = next_index, operation = operation)
        }
        next_index <- next_index + 1L
    }
    nodes
}
shortest <- function(board, kind, target) {
    start <- spawn_position(kind)
    if (!fits(board, kind, start)) return(NULL)
    nodes <- reachable(board, kind, start)
    for (i in seq_along(nodes)) {
        if (!all(landing(board, kind, nodes[[i]]$position) == target)) next
        sequence <- character()
        current <- i
        while (nodes[[current]]$previous != 0L) {
            sequence <- c(nodes[[current]]$operation, sequence)
            current <- nodes[[current]]$previous
        }
        return(sequence)
    }
    NULL
}
spin_check <- function(board, kind, position, motion, test) {
    if (kind != "T" || motion != "rotation") return(0L)
    x <- position[2]; y <- position[3]
    corners <- c(blocked(board,x,y), blocked(board,x+2,y),
                 blocked(board,x+2,y-2), blocked(board,x,y-2))
    if (sum(corners) < 3L) return(0L)
    front <- switch(as.character(position[1]), `0` = c(1L,2L), `1` = c(2L,3L),
                    `2` = c(3L,4L), `3` = c(4L,1L))
    if (all(corners[front]) || test == 5L) 2L else 1L
}
clear_type <- function(spin, lines) {
    if (spin == 0L) { if (lines == 0L) 0L else lines }
    else if (spin == 1L) 5L + lines else 8L + lines
}

insert_garbage <- function(count, hole) {
    if (any(game$board[seq.int(23L - count, 22L), , drop = FALSE])) game_over("top out")
    rows <- matrix(TRUE, count, 10L)
    rows[, hole] <- FALSE
    game$board <<- rbind(rows, game$board[seq_len(22L - count), , drop = FALSE])
}
lock_piece <- function() {
    kind <- game$kind
    position <- game$position
    cells <- cells_at(kind, position)
    sequence <- shortest(game$board, kind, position)
    spin <- spin_check(game$board, kind, position, game$motion, game$test)
    placed <- placed_board(game$board, kind, position)
    game$board <<- placed$board
    lines <- placed$lines
    game$history[[length(game$history) + 1L]] <<- game$start_state
    game$pieces <<- game$pieces + 1
    game$kind_counts[[kind]] <<- game$kind_counts[[kind]] + 1
    game$operation_total <<- game$operation_total + game$keys
    type <- clear_type(spin, lines)
    level <- game$level
    points <- if (type == 0L) 0 else base_points[type] * level
    sent <- if (type == 0L) 0 else send_lines[type]
    b2b <- FALSE
    if (lines > 0L) {
        game$streak <<- game$streak + 1L
        if (lines == 4L || spin != 0L) {
            game$chain <<- game$chain + 1L
            b2b <- game$chain >= 2L
        } else game$chain <<- 0L
    } else game$streak <<- 0L
    if (b2b) {
        points <- (points * 3) %/% 2
        sent <- sent + 1
    }
    combo <- game$streak - 1L
    combo_points <- if (combo >= 1L) 50 * combo * level else 0
    if (combo >= 0L) sent <- sent + c(0,1,1,2,2,3,3,4,4,4,5)[min(combo, 10L) + 1L]
    perfect <- lines > 0L && !any(game$board)
    perfect_points <- 0
    if (perfect) {
        perfect_points <- (if (lines == 4L && b2b) 3200 else c(800,1200,1800,2000)[lines]) * level
        sent <- sent + 10
        game$perfect <<- game$perfect + 1
    }
    gained <- points + combo_points + perfect_points
    game$score <<- game$score + gained
    game$lines <<- game$lines + lines
    game$sent <<- game$sent + sent
    game$max_combo <<- max(game$max_combo, combo)
    game$max_chain <<- max(game$max_chain, game$chain)
    emit("lock", game$pieces, kind, state_names[position[1] + 1L], position[2], position[3],
         "keys", game$keys, if (is.null(sequence)) "-" else length(sequence),
         "drop", game$drop, "lines", lines, "sent", sent,
         paste0("+", format(gained, scientific = FALSE, trim = TRUE)), "total", game$score)
    if (!is.null(sequence) && game$keys > length(sequence)) {
        game$faults <<- game$faults + 1
        emit("finesse", if (length(sequence)) paste(sequence, collapse = " ") else "none")
    }
    if (type != 0L) {
        game$clears[type] <<- game$clears[type] + 1
        suffix <- character()
        if (b2b) suffix <- c(suffix, "b2b")
        if (combo >= 1L) suffix <- c(suffix, "combo", sprintf("%.0f", combo), sprintf("%.0f", combo_points))
        if (perfect) suffix <- c(suffix, "perfect", sprintf("%.0f", perfect_points))
        emit("clear", clear_names[type], points, suffix)
    }
    next_level <- game$starting_level + game$lines %/% 10
    if (next_level > level) {
        game$level <<- next_level
        emit("level", next_level)
    }
    if (all(cells[, 2] >= 21L)) game_over("lock out")
    cancelled <- min(sent, sum(game$pending))
    if (cancelled > 0) {
        remaining <- cancelled
        while (remaining > 0) {
            used <- min(remaining, game$pending[1])
            game$pending[1] <<- game$pending[1] - used
            remaining <- remaining - used
            if (game$pending[1] == 0) game$pending <<- game$pending[-1]
        }
        game$cancelled <<- game$cancelled + cancelled
        emit("cancel", cancelled, "pending", sum(game$pending))
    }
    if (lines == 0L) {
        risen <- 0L
        while (length(game$pending) && risen < 8L) {
            count <- min(game$pending[1], 8L - risen)
            game$random <<- random_next(game$random)
            hole <- game$random %% 10 + 1L
            insert_garbage(count, hole)
            game$received <<- game$received + count
            risen <- risen + count
            game$pending[1] <<- game$pending[1] - count
            if (game$pending[1] == 0) game$pending <<- game$pending[-1]
            emit("rise", count, "hole", hole, "pending", sum(game$pending))
        }
    }
    game$hold_used <<- FALSE
    spawn(take_piece())
    game$start_state <<- core_state()
}
add_drop <- function(points) {
    game$score <<- game$score + points
    game$drop <<- game$drop + points
    game$drops <<- game$drops + points
}
operate <- function(operation) {
    kind <- game$kind
    position <- game$position
    if (operation %in% movements) {
        game$keys <<- game$keys + 1
        result <- move_piece(game$board, kind, position, operation)
        if (is.null(result)) { emit("fail", operation); return(invisible(NULL)) }
        if (operation %in% c("SD", "DD")) {
            add_drop(position[3] - result$position[3])
            update_position(result$position, "move")
            game$fall_counter <<- 0L
            game$ground_counter <<- 0L
        } else {
            update_position(result$position, if (operation %in% c("CW", "CCW")) "rotation" else "move", result$test)
            if (game$ground_counter > 0L && game$resets < 15L) {
                game$ground_counter <<- 0L
                game$resets <<- game$resets + 1L
            }
        }
    } else if (operation == "HD") {
        target <- landing(game$board, kind, position)
        distance <- position[3] - target[3]
        add_drop(2 * distance)
        if (distance > 0) update_position(target, "move")
        lock_piece()
    } else if (operation == "LOCK") {
        if (fits(game$board, kind, lower(position))) emit("fail LOCK") else lock_piece()
    } else {
        if (game$hold_used) { emit("fail HOLD"); return(invisible(NULL)) }
        game$hold_used <<- TRUE
        game$holds <<- game$holds + 1
        held <- game$hold
        game$hold <<- kind
        spawn(if (held == "") take_piece() else held)
    }
    invisible(NULL)
}
tick <- function() {
    if (fits(game$board, game$kind, lower(game$position))) {
        game$ground_counter <<- 0L
        game$fall_counter <<- game$fall_counter + 1L
        interval <- if (game$level <= 12L) gravity[game$level] else 1L
        if (game$fall_counter >= interval) {
            update_position(lower(game$position), "move")
            game$fall_counter <<- 0L
        }
    } else {
        game$ground_counter <<- game$ground_counter + 1L
        if (game$ground_counter >= 30L) lock_piece()
    }
}

candidate_list <- function(kind, start, prefix) {
    result <- list()
    seen <- new.env(hash = TRUE, parent = emptyenv())
    rotations <- list(character(), "CW", c("CW", "CW"), "CCW")
    for (rotation in rotations) {
        position <- start
        valid <- TRUE
        for (operation in rotation) {
            moved <- move_piece(game$board, kind, position, operation)
            if (is.null(moved)) { valid <- FALSE; break }
            position <- moved$position
        }
        if (!valid) next
        starts <- list(list(position = position, sequence = character()))
        for (direction in c("L", "R")) {
            moved_position <- position
            sequence <- character()
            repeat {
                moved <- move_piece(game$board, kind, moved_position, direction)
                if (is.null(moved)) break
                moved_position <- moved$position
                sequence <- c(sequence, direction)
                starts[[length(starts) + 1L]] <- list(position = moved_position, sequence = sequence)
            }
        }
        for (entry in starts) {
            target <- landing(game$board, kind, entry$position)
            cells <- cells_at(kind, target)
            key <- paste(sort((cells[, 2] - 1L) * 10L + cells[, 1]), collapse = ",")
            if (exists(key, envir = seen, inherits = FALSE)) next
            assign(key, TRUE, envir = seen)
            placed <- placed_board(game$board, kind, target)
            result[[length(result) + 1L]] <- list(
                kind = kind, value = well_metrics(placed$board, placed$lines)$value,
                sequence = c(prefix, rotation, entry$sequence, "HD"))
        }
    }
    result
}
ranked_candidates <- function() {
    result <- candidate_list(game$kind, game$position, character())
    if (!game$hold_used) {
        held <- if (game$hold == "") game$queue[1] else game$hold
        start <- spawn_position(held)
        if (fits(game$board, held, start)) result <- c(result, candidate_list(held, start, "HOLD"))
    }
    scores <- vapply(result, function(entry) entry$value, numeric(1))
    result[order(-scores, seq_along(result))]
}
show_spins <- function() {
    if (game$kind != "T") { emit("spins 0"); return(invisible(NULL)) }
    nodes <- reachable(game$board, "T", game$position)
    entries <- list()
    indices <- new.env(hash = TRUE, parent = emptyenv())
    for (node in nodes) for (rotation in c("CW", "CCW")) {
        moved <- move_piece(game$board, "T", node$position, rotation)
        if (is.null(moved) || fits(game$board, "T", lower(moved$position))) next
        spin <- spin_check(game$board, "T", moved$position, "rotation", moved$test)
        if (spin == 0L) next
        key <- position_key(moved$position)
        if (exists(key, envir = indices, inherits = FALSE)) {
            i <- get(key, envir = indices, inherits = FALSE)
            entries[[i]]$spin <- max(entries[[i]]$spin, spin)
        } else {
            i <- length(entries) + 1L
            assign(key, i, envir = indices)
            entries[[i]] <- list(position = moved$position, spin = spin)
        }
    }
    if (length(entries)) {
        positions <- do.call(rbind, lapply(entries, function(entry) entry$position))
        order <- order(positions[, 3], positions[, 2], positions[, 1])
        for (i in order) {
            entry <- entries[[i]]
            cleared <- placed_board(game$board, "T", entry$position)$lines
            emit("spin", state_names[entry$position[1] + 1L], entry$position[2], entry$position[3],
                 clear_names[clear_type(entry$spin, cleared)])
        }
    }
    emit("spins", length(entries))
}
new_game <- function(seed, level) {
    if (!is.null(game) && !game$ended) { emit("game stopped"); summary() }
    game_serial <<- game_serial + 1
    emit("game", game_serial, "seed", seed, "level", level)
    game <<- list(serial = game_serial, board = matrix(FALSE,22L,10L), random = seed,
                  queue = character(), hold = "", hold_used = FALSE, starting_level = level,
                  level = level, score = 0, lines = 0, pieces = 0, streak = 0L, chain = 0L,
                  pending = numeric(), drops = 0, holds = 0, operation_total = 0, faults = 0,
                  perfect = 0, sent = 0, cancelled = 0, received = 0, max_combo = 0,
                  max_chain = 0, kind_counts = setNames(numeric(7),kinds), clears = numeric(11),
                  ended = FALSE, history = list(), start_state = NULL, saves = list())
    add_bag()
    spawn(take_piece())
    game$start_state <<- core_state()
}
restore_core <- function(saved, history) {
    saves <- game$saves
    game <<- c(saved, list(history = history, start_state = saved, saves = saves))
}
print_board <- function() {
    image <- matrix(".", 22L, 10L)
    if (!game$ended) {
        ghost <- cells_at(game$kind, landing(game$board, game$kind, game$position))
        image[cbind(ghost[, 2], ghost[, 1])] <- "+"
        current <- cells_at(game$kind, game$position)
        image[cbind(current[, 2], current[, 1])] <- "@"
    }
    image[game$board] <- "#"
    for (r in 22:1) cat(sprintf("%2d %s\n", r, paste(image[r, ], collapse = "")))
}
valid_integer <- function(word, minimum, maximum) {
    grepl("^(0|[1-9][0-9]*)$", word) && as.numeric(word) >= minimum && as.numeric(word) <= maximum
}
commands <- c("NEW", "PRINT", "NEXT", "PREVIEW", "STATUS", "ANALYZE", "ROW", "GARBAGE",
              "ATTACK", "TICK", "UNDO", "SAVE", "LOAD", "SPINS", "HINT", "AUTO")
allowed_after_end <- c("PRINT", "NEXT", "PREVIEW", "STATUS", "ANALYZE", "LOAD")
validate_arguments <- function(command, args) {
    n <- length(args)
    if (command == "NEW") return(n == 2L && valid_integer(args[1],1,2147483646) && valid_integer(args[2],1,15))
    if (command %in% c("PRINT", "NEXT", "STATUS", "ANALYZE", "UNDO", "SPINS")) return(n == 0L)
    if (command %in% c("SAVE", "LOAD")) return(n == 1L && grepl("^[a-z]{1,8}$", args[1]))
    if (command == "ROW") return(n == 2L && valid_integer(args[1],1,22) && grepl("^[#.]{10}$", args[2]) && grepl(".",args[2],fixed=TRUE))
    if (command == "GARBAGE") return(n == 2L && valid_integer(args[1],1,10) && valid_integer(args[2],1,10))
    maximum <- switch(command, PREVIEW=14, ATTACK=20, TICK=1000, HINT=10, AUTO=50)
    n == 1L && valid_integer(args[1],1,maximum)
}

process_line <- function(text) {
    words <- strsplit(text, " ", fixed = TRUE)[[1]]
    command <- words[1]
    args <- words[-1]
    if (!command %in% commands) {
        unknown <- words[!words %in% operations]
        if (length(unknown)) { emit("ERROR unknown", unknown[1]); return(invisible(NULL)) }
        if (is.null(game)) { emit("ERROR no game"); return(invisible(NULL)) }
        if (game$ended) { emit("ERROR game over"); return(invisible(NULL)) }
        for (operation in words) operate(operation)
        return(invisible(NULL))
    }
    if (!validate_arguments(command, args)) { emit("ERROR bad arguments"); return(invisible(NULL)) }
    if (command == "NEW") { new_game(as.numeric(args[1]), as.numeric(args[2])); return(invisible(NULL)) }
    if (is.null(game)) { emit("ERROR no game"); return(invisible(NULL)) }
    if (game$ended && !command %in% allowed_after_end) { emit("ERROR game over"); return(invisible(NULL)) }
    if (command == "PRINT") print_board()
    else if (command == "NEXT") emit("hold", if (game$hold == "") "-" else game$hold,
                                     "next", paste(game$queue[1:5], collapse = ""))
    else if (command == "PREVIEW") {
        count <- as.numeric(args[1])
        queue <- game$queue
        random <- game$random
        while (length(queue) < count) {
            generated <- bag(random)
            random <- generated$random
            queue <- c(queue, generated$pieces)
        }
        emit("preview", paste(queue[seq_len(count)], collapse = ""))
    } else if (command == "STATUS") {
        emit("score", game$score, "level", game$level, "lines", game$lines, "pieces", game$pieces)
        piece <- if (game$ended) "-" else paste(game$kind, state_names[game$position[1] + 1L],
                                                game$position[2], game$position[3])
        emit("piece", piece, "streak", game$streak, "chain", game$chain, "pending", sum(game$pending))
    } else if (command == "ANALYZE") {
        metrics <- well_metrics(game$board)
        emit("heights", metrics$heights)
        emit("holes", metrics$holes, "bumpiness", metrics$bumpiness, "value", metrics$value)
    } else if (command == "ROW") {
        row <- as.numeric(args[1])
        marks <- strsplit(args[2], "", fixed = TRUE)[[1]] == "#"
        cells <- cells_at(game$kind, game$position)
        occupied <- cells[cells[, 2] == row, 1]
        if (any(marks[occupied])) emit("ERROR overlap")
        else {
            game$board[row, ] <<- marks
            emit("OK")
        }
    } else if (command == "GARBAGE") {
        count <- as.numeric(args[1])
        insert_garbage(count, as.numeric(args[2]))
        original <- game$position
        found <- FALSE
        for (j in 0:count) {
            position <- original + c(0,0,j)
            if (fits(game$board, game$kind, position)) {
                game$position <<- position
                found <- TRUE
                break
            }
        }
        if (!found) game_over("top out")
        emit("OK")
    } else if (command == "ATTACK") {
        game$pending <<- c(game$pending, as.numeric(args[1]))
        emit("pending", sum(game$pending))
    } else if (command == "TICK") {
        for (i in seq_len(as.numeric(args[1]))) tick()
    } else if (command == "UNDO") {
        if (!length(game$history)) emit("ERROR nothing to undo")
        else {
            last <- length(game$history)
            saved <- game$history[[last]]
            previous <- game$history[-last]
            restore_core(saved, previous)
            emit("undo", game$pieces, game$kind)
        }
    } else if (command == "SAVE") {
        saved <- game[setdiff(names(game), "saves")]
        game$saves[[args[1]]] <<- saved
        emit("OK")
    } else if (command == "LOAD") {
        saved <- game$saves[[args[1]]]
        if (is.null(saved)) emit("ERROR unknown save")
        else {
            saves <- game$saves
            game <<- c(saved, list(saves = saves))
            emit("load", game$pieces, game$kind)
        }
    } else if (command == "SPINS") show_spins()
    else if (command == "HINT") {
        candidates <- ranked_candidates()
        count <- min(as.numeric(args[1]), length(candidates))
        for (i in seq_len(count)) {
            candidate <- candidates[[i]]
            emit("hint", i, candidate$kind, paste(candidate$sequence, collapse = " "), "value", candidate$value)
        }
    } else if (command == "AUTO") {
        for (i in seq_len(as.numeric(args[1]))) {
            candidate <- ranked_candidates()[[1]]
            emit("auto", candidate$kind, paste(candidate$sequence, collapse = " "))
            for (operation in candidate$sequence) operate(operation)
        }
    }
    invisible(NULL)
}

input <- file("stdin", open = "r")
header <- readLines(input, n = 1L, warn = FALSE)
if (length(header)) {
    lines <- readLines(input, n = as.integer(header), warn = FALSE)
    for (line in lines) tryCatch(process_line(line), game_over = function(condition) invisible(NULL))
    if (!is.null(game) && !game$ended) { emit("game stopped"); summary() }
}
close(input)
