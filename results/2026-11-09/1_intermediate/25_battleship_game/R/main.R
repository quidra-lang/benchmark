suppressPackageStartupMessages(library(gmp))

SHIP_NAMES <- c("CARRIER", "BATTLESHIP", "CRUISER", "SUBMARINE", "DESTROYER")
SHIP_LENGTHS <- c(5L, 4L, 3L, 3L, 2L)
SHIP_SYMBOLS <- c("C", "B", "R", "S", "D")
STRATEGIES <- c("HUNT", "PROB", "RANDOM")
SETUP_COMMANDS <- c("PLACE", "REMOVE", "AUTOPLACE", "LAYOUT", "REEF", "SALVO", "CHAIN", "TOUCH")
TURN_COMMANDS <- c("FIRE", "AI", "TORPEDO", "SONAR")
PLAYER_COMMANDS <- c("PLACE", "REMOVE", "AUTOPLACE", "LAYOUT", "FIRE", "AI", "TORPEDO", "SONAR", "RESIGN", "CONTROL", "SEED", "HINT", "DENSITY", "SHOW", "RADAR", "EXPORT", "FLEET")

emit <- function(...) {
    fields <- lapply(list(...), function(value) {
        if (is.numeric(value)) format(value, digits = 22L, scientific = FALSE, trim = TRUE) else as.character(value)
    })
    cat(paste(unlist(fields, use.names = FALSE), collapse = " "), "\n", sep = "")
}
fail <- function(message) {
    stop(structure(list(message = message, call = NULL), class = c("command_error", "error", "condition")))
}
coordinate <- function(cell) paste0(LETTERS[(cell - 1L) %/% 10L + 1L], (cell - 1L) %% 10L + 1L)
parse_cell <- function(text) (match(substr(text, 1L, 1L), LETTERS) - 1L) * 10L + as.integer(substring(text, 2L))
ship_range <- function(cells) paste0(coordinate(cells[1L]), "-", coordinate(cells[length(cells)]))

advance <- function(state) as.integer(as.character((as.bigz(state) * 48271L) %% 2147483647L))

step <- function(cell, dr, dc) {
    row <- (cell - 1L) %/% 10L + dr
    column <- (cell - 1L) %% 10L + dc
    if (row < 0L || row >= 10L || column < 0L || column >= 10L) return(0L)
    row * 10L + column + 1L
}

footprint <- function(start, direction, length) {
    position <- if (direction == "H") (start - 1L) %% 10L else (start - 1L) %/% 10L
    if (position + length > 10L) return(integer())
    start + (seq_len(length) - 1L) * if (direction == "H") 1L else 10L
}

AROUND <- lapply(seq_len(100L), function(cell) {
    cells <- integer()
    for (dr in -1L:1L) for (dc in -1L:1L) {
        if (dr == 0L && dc == 0L) next
        neighbor <- step(cell, dr, dc)
        if (neighbor != 0L) cells <- c(cells, neighbor)
    }
    cells
})
ORTHOGONAL <- lapply(seq_len(100L), function(cell) {
    cells <- c(step(cell, 0L, -1L), step(cell, 1L, 0L), step(cell, 0L, 1L), step(cell, -1L, 0L))
    cells[cells != 0L]
})
PLACEMENTS <- lapply(seq_along(SHIP_LENGTHS), function(ship) {
    positions <- list()
    for (start in seq_len(100L)) for (direction in c("H", "V")) {
        cells <- footprint(start, direction, SHIP_LENGTHS[ship])
        if (length(cells)) positions[[length(positions) + 1L]] <- cells
    }
    positions
})

touching <- function(first, second) any(second %in% unlist(AROUND[first], use.names = FALSE))

new_player <- function(seed, wins) {
    list2env(list(
        fleet = replicate(5L, integer(), simplify = FALSE), attacked = rep(FALSE, 100L),
        candidates = integer(), state = seed, controller = "HUMAN", torpedo = FALSE, sonar = FALSE,
        shots = 0L, hits = 0L, sinks = 0L, turns = 0L, streak = 0L, best_streak = 0L, wins = wins
    ), parent = emptyenv())
}

new_game <- function(wins = c(0L, 0L)) {
    list2env(list(
        phase = "SETUP", current = 1L, winner = 0L, salvo = FALSE, chain = FALSE, touch = FALSE,
        reefs = rep(FALSE, 100L), players = list(new_player(1L, wins[1L]), new_player(2L, wins[2L]))
    ), parent = emptyenv())
}

board_of <- function(player) {
    occupied <- integer(100L)
    for (ship in seq_along(player$fleet)) occupied[player$fleet[[ship]]] <- ship
    occupied
}
is_sunk <- function(player, ship) length(player$fleet[[ship]]) > 0L && all(player$attacked[player$fleet[[ship]]])
placed_count <- function(player) sum(lengths(player$fleet) > 0L)
afloat_count <- function(player) sum(lengths(player$fleet) > 0L & !vapply(seq_len(5L), function(ship) is_sunk(player, ship), logical(1L)))
defeated <- function(player) all(vapply(seq_len(5L), function(ship) is_sunk(player, ship), logical(1L)))
allowance <- function(game, player) if (game$salvo) afloat_count(game$players[[player]]) else 1L

placement_problem <- function(game, player, cells) {
    if (!length(cells)) return("out of bounds")
    if (any(game$reefs[cells])) return("on reef")
    fleet <- game$players[[player]]$fleet
    for (ship in seq_len(5L)) if (any(cells %in% fleet[[ship]])) return(paste("overlaps", SHIP_NAMES[ship]))
    if (!game$touch) {
        for (ship in seq_len(5L)) if (touching(cells, fleet[[ship]])) return(paste("touches", SHIP_NAMES[ship]))
    }
    NULL
}

placement_output <- function(game, player) {
    for (ship in seq_len(5L)) emit("PLACED", player, SHIP_NAMES[ship], ship_range(game$players[[player]]$fleet[[ship]]))
}

auto_place <- function(game, player, seed) {
    owner <- game$players[[player]]
    owner$state <- seed
    owner$fleet <- replicate(5L, integer(), simplify = FALSE)
    attempts <- 0
    for (ship in seq_len(5L)) {
        while (!length(owner$fleet[[ship]])) {
            attempts <- attempts + 1
            owner$state <- advance(owner$state)
            direction <- if (owner$state %% 2L == 0L) "H" else "V"
            owner$state <- advance(owner$state)
            span <- 11L - SHIP_LENGTHS[ship]
            index <- owner$state %% (10L * span)
            start <- if (direction == "H") index %/% span * 10L + index %% span + 1L else index + 1L
            cells <- footprint(start, direction, SHIP_LENGTHS[ship])
            if (is.null(placement_problem(game, player, cells))) owner$fleet[[ship]] <- cells
        }
    }
    attempts
}

layout_fleet <- function(game, text) {
    chars <- strsplit(gsub("/", "", text, fixed = TRUE), "", fixed = TRUE)[[1L]]
    fleet <- vector("list", 5L)
    for (ship in seq_len(5L)) {
        cells <- which(chars == SHIP_SYMBOLS[ship])
        if (length(cells) != SHIP_LENGTHS[ship]) fail(paste(SHIP_NAMES[ship], "has", length(cells), "cells"))
        if (!identical(cells, footprint(cells[1L], "H", SHIP_LENGTHS[ship])) &&
            !identical(cells, footprint(cells[1L], "V", SHIP_LENGTHS[ship]))) fail(paste(SHIP_NAMES[ship], "not straight"))
        if (any(game$reefs[cells])) fail(paste(SHIP_NAMES[ship], "on reef"))
        fleet[[ship]] <- cells
    }
    if (!game$touch) {
        for (first in seq_len(4L)) for (second in seq.int(first + 1L, 5L)) {
            if (touching(fleet[[first]], fleet[[second]])) fail(paste(SHIP_NAMES[first], "touches", SHIP_NAMES[second]))
        }
    }
    fleet
}

view_of <- function(game, player) {
    opponent <- game$players[[3L - player]]
    chars <- rep(".", 100L)
    chars[opponent$attacked] <- "o"
    for (ship in seq_len(5L)) {
        cells <- opponent$fleet[[ship]]
        chars[cells[opponent$attacked[cells]]] <- if (is_sunk(opponent, ship)) "#" else "x"
    }
    chars[game$reefs] <- "~"
    chars
}

excluded_cells <- function(game, view) {
    excluded <- rep(FALSE, 100L)
    if (!game$touch) excluded[unlist(AROUND[which(view == "#")], use.names = FALSE)] <- TRUE
    excluded
}

density <- function(game, player, view, excluded) {
    scores <- integer(100L)
    allowed <- view %in% c(".", "x") & !excluded
    for (ship in seq_len(5L)) {
        if (is_sunk(game$players[[3L - player]], ship)) next
        for (cells in PLACEMENTS[[ship]]) {
            if (all(allowed[cells])) scores[cells] <- scores[cells] + 1L + 10L * sum(view[cells] == "x")
        }
    }
    scores
}

choose <- function(game, player, strategy) {
    view <- view_of(game, player)
    excluded <- excluded_cells(game, view)
    candidates <- view == "." & !excluded
    state <- game$players[[player]]$state
    result <- function(cell, info, generator = state) list(cell = cell, info = info, state = generator)
    if (strategy == "PROB") {
        scores <- density(game, player, view, excluded)
        unknown <- which(view == ".")
        cell <- unknown[which.max(scores[unknown])]
        return(result(cell, scores[cell]))
    }
    if (strategy == "RANDOM") {
        cells <- which(candidates)
        generator <- advance(state)
        return(result(cells[generator %% length(cells) + 1L], length(cells), generator))
    }
    valid <- function(cell) cell > 0L && candidates[cell]
    for (cell in which(view == "x")) {
        for (direction in list(c(0L, 1L), c(1L, 0L))) {
            dr <- direction[1L]
            dc <- direction[2L]
            front <- step(cell, dr, dc)
            if (front == 0L || view[front] != "x") next
            while (front != 0L && view[front] == "x") front <- step(front, dr, dc)
            back <- step(cell, -dr, -dc)
            if (valid(front)) return(result(front, "LINE"))
            if (valid(back)) return(result(back, "LINE"))
        }
    }
    for (cell in rev(game$players[[player]]$candidates)) if (candidates[cell]) return(result(cell, "STACK"))
    remaining <- !vapply(seq_len(5L), function(ship) is_sunk(game$players[[3L - player]], ship), logical(1L))
    shortest <- min(SHIP_LENGTHS[remaining])
    cells <- which(candidates)
    parity <- ((cells - 1L) %/% 10L + (cells - 1L) %% 10L) %% shortest == 0L
    result(cells[which(parity)[1L]], "PARITY")
}

shoot <- function(game, player, cell) {
    attacker <- game$players[[player]]
    opponent <- game$players[[3L - player]]
    text <- "ALREADY"
    hit <- FALSE
    sunk <- 0L
    if (!opponent$attacked[cell]) {
        opponent$attacked[cell] <- TRUE
        ship <- board_of(opponent)[cell]
        if (ship == 0L) text <- "MISS"
        else {
            hit <- TRUE
            if (is_sunk(opponent, ship)) {
                text <- paste("SUNK", SHIP_NAMES[ship])
                sunk <- ship
            } else {
                text <- "HIT"
                attacker$candidates <- c(attacker$candidates, ORTHOGONAL[[cell]])
            }
        }
    }
    attacker$shots <- attacker$shots + 1L
    if (hit) {
        attacker$hits <- attacker$hits + 1L
        attacker$streak <- attacker$streak + 1L
        attacker$best_streak <- max(attacker$best_streak, attacker$streak)
    } else attacker$streak <- 0L
    if (sunk > 0L) attacker$sinks <- attacker$sinks + 1L
    list(text = text, hit = hit, sunk = sunk)
}

finish_turn <- function(game, player, hit, mode) {
    owner <- game$players[[player]]
    owner$turns <- owner$turns + 1L
    if (defeated(game$players[[3L - player]])) {
        game$phase <- "OVER"
        game$winner <- player
        owner$wins <- owner$wins + 1L
        if (mode == "normal") emit("WINNER", player)
    } else game$current <- if (game$chain && hit) player else 3L - player
}

shooting_turn <- function(game, player, strategy, cells = integer(), mode = "normal") {
    game$phase <- "BATTLE"
    count <- allowance(game, player)
    hit <- FALSE
    for (index in seq_len(count)) {
        if (is.null(strategy)) cell <- cells[index]
        else {
            choice <- choose(game, player, strategy)
            cell <- choice$cell
            game$players[[player]]$state <- choice$state
        }
        shot <- shoot(game, player, cell)
        hit <- hit || shot$hit
        if (mode == "normal") emit("SHOT", player, coordinate(cell), shot$text)
        if (mode == "match" && shot$sunk > 0L) emit("SINK", player, SHIP_NAMES[shot$sunk], game$players[[player]]$shots)
        if (defeated(game$players[[3L - player]])) break
    }
    finish_turn(game, player, hit, mode)
}

automatic <- function(game) {
    while (game$phase == "BATTLE") {
        player <- game$current
        controller <- game$players[[player]]$controller
        if (controller == "HUMAN") break
        shooting_turn(game, player, controller)
    }
}

torpedo_turn <- function(game, player, row, side) {
    game$phase <- "BATTLE"
    owner <- game$players[[player]]
    opponent <- game$players[[3L - player]]
    owner$torpedo <- TRUE
    occupied <- board_of(opponent)
    columns <- if (side == "W") seq_len(10L) else 10L:1L
    result <- "MISS"
    hit <- FALSE
    stopped_ship <- FALSE
    for (column in columns) {
        cell <- (row - 1L) * 10L + column
        if (game$reefs[cell]) {
            result <- paste("REEF", coordinate(cell))
            break
        }
        if (occupied[cell] > 0L) {
            shot <- shoot(game, player, cell)
            result <- paste(shot$text, coordinate(cell))
            hit <- shot$hit
            stopped_ship <- TRUE
            break
        }
        opponent$attacked[cell] <- TRUE
    }
    if (!stopped_ship) {
        owner$shots <- owner$shots + 1L
        owner$streak <- 0L
    }
    emit("TORPEDO", player, LETTERS[row], side, result)
    finish_turn(game, player, hit, "normal")
}

sonar_turn <- function(game, player, cell) {
    game$phase <- "BATTLE"
    game$players[[player]]$sonar <- TRUE
    opponent <- game$players[[3L - player]]
    region <- c(cell, AROUND[[cell]])
    count <- sum(board_of(opponent)[region] > 0L & !opponent$attacked[region])
    emit("SONAR", player, coordinate(cell), count)
    finish_turn(game, player, FALSE, "normal")
}

board_output <- function(game, player, radar) {
    chars <- view_of(game, player)
    if (!radar) {
        owner <- game$players[[player]]
        chars <- rep(".", 100L)
        chars[owner$attacked] <- "o"
        for (ship in seq_len(5L)) {
            cells <- owner$fleet[[ship]]
            chars[cells] <- SHIP_SYMBOLS[ship]
            chars[cells[owner$attacked[cells]]] <- tolower(SHIP_SYMBOLS[ship])
        }
        chars[game$reefs] <- "~"
    }
    emit(if (radar) "RADAR" else "BOARD", player)
    emit("  1 2 3 4 5 6 7 8 9 10")
    for (row in seq_len(10L)) emit(LETTERS[row], chars[(row - 1L) * 10L + seq_len(10L)])
}

export_fleet <- function(player) {
    chars <- rep(".", 100L)
    for (ship in seq_len(5L)) chars[player$fleet[[ship]]] <- SHIP_SYMBOLS[ship]
    rows <- vapply(seq_len(10L), function(row) paste0(chars[(row - 1L) * 10L + seq_len(10L)], collapse = ""), character(1L))
    paste(rows, collapse = "/")
}

fleet_output <- function(game, player) {
    owner <- game$players[[player]]
    emit("FLEET", player, "afloat", afloat_count(owner))
    for (ship in seq_len(5L)) {
        cells <- owner$fleet[[ship]]
        if (!length(cells)) emit(SHIP_NAMES[ship], "unplaced")
        else emit(SHIP_NAMES[ship], ship_range(cells), paste0(sum(owner$attacked[cells]), "/", SHIP_LENGTHS[ship]), if (is_sunk(owner, ship)) "SUNK" else "AFLOAT")
    }
}

density_output <- function(game, player) {
    view <- view_of(game, player)
    scores <- density(game, player, view, excluded_cells(game, view))
    values <- ifelse(view == ".", as.character(scores), ifelse(view == "~", "~", "-"))
    emit("DENSITY", player)
    emit(paste0(" ", paste(sprintf("%5d", seq_len(10L)), collapse = "")))
    for (row in seq_len(10L)) {
        cells <- (row - 1L) * 10L + seq_len(10L)
        emit(paste0(LETTERS[row], paste(sprintf("%5s", values[cells]), collapse = "")))
    }
    unknown <- which(view == ".")
    best <- unknown[which.max(scores[unknown])]
    emit("BEST", coordinate(best), scores[best])
}

status_output <- function(game) {
    rule <- function(value) if (value) "ON" else "OFF"
    prefix <- c("STATUS", game$phase, "salvo", rule(game$salvo), "chain", rule(game$chain), "touch", rule(game$touch), "reefs", sum(game$reefs))
    if (game$phase == "SETUP") {
        emit(prefix, "placed", placed_count(game$players[[1L]]), placed_count(game$players[[2L]]))
    } else {
        turn <- if (game$phase == "BATTLE") c("turn", game$current, "shots", allowance(game, game$current)) else c("winner", game$winner)
        emit(prefix, turn, "afloat", afloat_count(game$players[[1L]]), afloat_count(game$players[[2L]]))
    }
}

statistics <- function(game) {
    for (side in seq_len(2L)) {
        player <- game$players[[side]]
        accuracy <- if (player$shots == 0L) "-" else paste0((player$hits * 100L) %/% player$shots, "%")
        emit("STATS", side, "shots", player$shots, "hits", player$hits, "sunk", player$sinks, "turns", player$turns,
             "streak", player$best_streak, "accuracy", accuracy, "wins", player$wins)
    }
}

play_match <- function(current, first_seed, second_seed, first_strategy, second_strategy, mode = "quiet") {
    game <- new_game()
    game$salvo <- current$salvo
    game$chain <- current$chain
    game$touch <- current$touch
    game$reefs <- current$reefs
    auto_place(game, 1L, first_seed)
    auto_place(game, 2L, second_seed)
    game$phase <- "BATTLE"
    strategies <- c(first_strategy, second_strategy)
    while (game$phase == "BATTLE") {
        player <- game$current
        shooting_turn(game, player, strategies[player], mode = mode)
    }
    game
}

series <- function(current, count, seed, first_strategy, second_strategy) {
    wins <- shots <- c(0L, 0L)
    fastest <- rep(NA_integer_, 2L)
    generator <- seed
    for (index in seq_len(count)) {
        first_seed <- advance(generator)
        generator <- advance(first_seed)
        game <- play_match(current, first_seed, generator, first_strategy, second_strategy)
        winner <- game$winner
        wins[winner] <- wins[winner] + 1L
        shots <- shots + vapply(game$players, function(player) player$shots, integer(1L))
        won_shots <- game$players[[winner]]$shots
        fastest[winner] <- if (is.na(fastest[winner])) won_shots else min(fastest[winner], won_shots)
    }
    minimums <- ifelse(is.na(fastest), "-", as.character(fastest))
    emit("SERIES", count, "wins", wins, "shots", shots, "fastest", minimums)
}

tourney <- function(current, count, seed) {
    wins <- shots <- integer(3L)
    generator <- seed
    for (first in seq_len(3L)) for (second in seq_len(3L)) {
        if (first == second) next
        for (index in seq_len(count)) {
            first_seed <- advance(generator)
            generator <- advance(first_seed)
            game <- play_match(current, first_seed, generator, STRATEGIES[first], STRATEGIES[second])
            winner <- if (game$winner == 1L) first else second
            wins[winner] <- wins[winner] + 1L
            shots[c(first, second)] <- shots[c(first, second)] + vapply(game$players, function(player) player$shots, integer(1L))
        }
    }
    ranking <- order(-wins, shots, STRATEGIES, method = "radix")
    emit("TOURNEY", count)
    for (rank in seq_along(ranking)) {
        strategy <- ranking[rank]
        emit(rank, STRATEGIES[strategy], "wins", wins[strategy], "shots", shots[strategy])
    }
}

command <- function(program, tokens) {
    op <- tokens[1L]
    if (op == "NEW") {
        wins <- vapply(program$game$players, function(player) player$wins, integer(1L))
        program$game <- new_game(wins)
        emit("NEW")
        return(invisible(NULL))
    }
    game <- program$game
    player <- if (op %in% PLAYER_COMMANDS) as.integer(tokens[2L]) else 0L
    if (op %in% SETUP_COMMANDS && game$phase != "SETUP") fail("setup closed")
    if (op %in% TURN_COMMANDS) {
        if (game$phase == "OVER") fail("game over")
        if (game$phase == "SETUP" && any(vapply(game$players, placed_count, integer(1L)) < 5L)) fail("fleets not ready")
        if (player != game$current) fail("not your turn")
        if (op == "FIRE") {
            count <- allowance(game, player)
            if (length(tokens) - 2L != count) fail(paste("expected", count, "shots"))
            cells <- vapply(tokens[-c(1L, 2L)], parse_cell, integer(1L), USE.NAMES = FALSE)
            for (cell in cells) if (game$reefs[cell]) fail(paste("reef at", coordinate(cell)))
            shooting_turn(game, player, NULL, cells)
        } else if (op == "AI") shooting_turn(game, player, tokens[3L])
        else if (op == "TORPEDO") {
            if (game$players[[player]]$torpedo) fail("torpedo used")
            torpedo_turn(game, player, match(tokens[3L], LETTERS), tokens[4L])
        } else {
            if (game$players[[player]]$sonar) fail("sonar used")
            sonar_turn(game, player, parse_cell(tokens[3L]))
        }
        automatic(game)
        return(invisible(NULL))
    }
    switch(op,
        PLACE =, REMOVE = {
            ship <- match(tokens[3L], SHIP_NAMES)
            owner <- game$players[[player]]
            if (op == "PLACE") {
                if (length(owner$fleet[[ship]])) fail(paste(SHIP_NAMES[ship], "already placed"))
                cells <- footprint(parse_cell(tokens[4L]), tokens[5L], SHIP_LENGTHS[ship])
                problem <- placement_problem(game, player, cells)
                if (!is.null(problem)) fail(problem)
                owner$fleet[[ship]] <- cells
                emit("PLACED", player, SHIP_NAMES[ship], ship_range(cells))
            } else {
                if (!length(owner$fleet[[ship]])) fail(paste(SHIP_NAMES[ship], "not placed"))
                owner$fleet[[ship]] <- integer()
                emit("REMOVED", player, SHIP_NAMES[ship])
            }
        },
        AUTOPLACE = {
            attempts <- auto_place(game, player, as.integer(tokens[3L]))
            emit("AUTOPLACE", player, "attempts", attempts)
            placement_output(game, player)
        },
        LAYOUT = {
            fleet <- layout_fleet(game, tokens[3L])
            game$players[[player]]$fleet <- fleet
            emit("LAYOUT", player)
            placement_output(game, player)
        },
        REEF = {
            cell <- parse_cell(tokens[2L])
            if (game$reefs[cell]) fail(paste("reef exists at", coordinate(cell)))
            for (owner in seq_len(2L)) {
                ship <- board_of(game$players[[owner]])[cell]
                if (ship > 0L) fail(paste(coordinate(cell), "occupied by", owner, SHIP_NAMES[ship]))
            }
            game$reefs[cell] <- TRUE
            emit("REEF", coordinate(cell))
        },
        SALVO =, CHAIN =, TOUCH = {
            game[[tolower(op)]] <- tokens[2L] == "ON"
            emit(op, tokens[2L])
        },
        CONTROL = {
            game$players[[player]]$controller <- tokens[3L]
            emit("CONTROL", player, tokens[3L])
        },
        SEED = {
            game$players[[player]]$state <- as.integer(tokens[3L])
            emit("SEED", player, game$players[[player]]$state)
        },
        RESIGN = {
            if (game$phase != "BATTLE") fail("not in battle")
            game$phase <- "OVER"
            game$winner <- 3L - player
            game$players[[game$winner]]$wins <- game$players[[game$winner]]$wins + 1L
            emit("RESIGN", player)
            emit("WINNER", game$winner)
        },
        HINT = {
            if (game$phase == "OVER") fail("game over")
            choice <- choose(game, player, tokens[3L])
            emit("HINT", player, tokens[3L], coordinate(choice$cell), choice$info)
        },
        DENSITY = {
            if (game$phase == "OVER") fail("game over")
            density_output(game, player)
        },
        SHOW = board_output(game, player, FALSE),
        RADAR = board_output(game, player, TRUE),
        EXPORT = emit("EXPORT", player, export_fleet(game$players[[player]])),
        FLEET = fleet_output(game, player),
        STATUS = status_output(game),
        STATS = statistics(game),
        MATCH = {
            emit("MATCH", 1L, tokens[4L], 2L, tokens[5L])
            trial <- play_match(game, as.integer(tokens[2L]), as.integer(tokens[3L]), tokens[4L], tokens[5L], "match")
            emit("RESULT winner", trial$winner, "shots", trial$players[[1L]]$shots, trial$players[[2L]]$shots,
                 "hits", trial$players[[1L]]$hits, trial$players[[2L]]$hits)
        },
        SERIES = series(game, as.integer(tokens[2L]), as.integer(tokens[3L]), tokens[4L], tokens[5L]),
        TOURNEY = tourney(game, as.integer(tokens[2L]), as.integer(tokens[3L]))
    )
    invisible(NULL)
}

program <- list2env(list(game = new_game()), parent = emptyenv())
input <- file("stdin", open = "r")
command_count <- as.integer(readLines(input, n = 1L, warn = FALSE))
for (command_number in seq_len(command_count)) {
    tokens <- strsplit(readLines(input, n = 1L, warn = FALSE), " ", fixed = TRUE)[[1L]]
    tryCatch(command(program, tokens), command_error = function(problem) emit("ERROR", conditionMessage(problem)))
}
close(input)
