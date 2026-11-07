seats <- c("N", "E", "S", "W")
suits <- c("C", "D", "S", "H")
ranks <- strsplit("23456789TJQKA", "", fixed = TRUE)[[1]]
QS <- 36L
KS <- 37L
AS <- 38L
JD <- 22L
directions <- c(L = "LEFT", R = "RIGHT", A = "ACROSS", H = "HOLD")
rule_names <- c("TARGET", "LIMIT", "MOON", "JACK", "QSBREAK", "BLOOD", "PASS")
fail <- function(reason) {
    stop(structure(list(message = reason, call = NULL), class = c("command_error", "error", "condition")))
}
seat_value <- function(word) {
    value <- match(word, seats)
    if (is.na(value)) fail(paste("bad seat", word))
    value
}
card_value <- function(word) {
    r <- match(substr(word, 1, 1), ranks)
    s <- match(substr(word, 2, 2), suits)
    if (nchar(word) != 2 || is.na(r) || is.na(s)) fail(paste("bad card", word))
    13L * (s - 1L) + r - 1L
}
card_text <- function(cards) paste0(ranks[(cards %% 13L) + 1L], suits[(cards %/% 13L) + 1L])
cards_text <- function(cards) if (length(cards)) paste(card_text(sort(cards)), collapse = " ") else "-"
bounded <- function(word, low, high) {
    value <- suppressWarnings(as.numeric(word))
    if (is.na(value) || value < low || value > high) fail(paste("bad value", word))
    value
}
penalty <- function(cards) cards == QS | (cards %/% 13L) == 3L
ordered <- function(cards, high = FALSE) cards[order(if (high) -(cards %% 13L) else cards %% 13L, cards %/% 13L)]
lowest <- function(cards) ordered(cards)[1]
highest <- function(cards) ordered(cards, TRUE)[1]
next_seat <- function(seat, offset) ((seat - 1L + offset) %% 4L) + 1L
pairs <- function(label, values) paste(label, paste(seats, values, collapse = " "))
new_generator <- function(seed) {
    rng <- new.env(parent = emptyenv())
    rng$state <- seed
    rng
}
draw <- function(rng) {
    rng$state <- (48271 * rng$state) %% 2147483647
    rng$state
}
new_game <- function(rules, bots, rng) {
    g <- new.env(parent = emptyenv())
    g$rules <- rules
    g$bots <- bots
    g$rng <- rng
    g$state <- "between"
    g$number <- 0L
    g$scores <- numeric(4)
    g$stats <- matrix(0, 4, 4)
    g$stacked <- vector("list", 4)
    g$history <- list()
    g$log <- list()
    g$record <- character()
    g
}
point <- function(g, cards) {
    ifelse(cards == QS, 13, ifelse((cards %/% 13L) == 3L, 1,
           ifelse(cards == JD & g$rules[["JACK"]] == "ON", -10, 0)))
}
points <- function(g, cards) sum(point(g, cards))
record_line <- function(g, level, line) {
    g$log[[length(g$log) + 1L]] <- list(level = level, text = line)
    if (level > 0L) g$record <- c(g$record, line)
}
begin_play <- function(g) {
    g$state <- "playing"
    g$leader <- which(vapply(g$hands, function(hand) 0L %in% hand, logical(1)))[1]
    record_line(g, 2L, paste("lead", seats[g$leader]))
}
deal <- function(g) {
    g$number <- g$number + 1L
    cycle <- g$rules[["PASS"]]
    position <- ((g$number - 1L) %% nchar(cycle)) + 1L
    g$direction <- substr(cycle, position, position)
    g$hands <- lapply(g$stacked, function(cards) if (is.null(cards)) integer() else cards)
    deck <- setdiff(0:51, unlist(g$hands, use.names = FALSE))
    if (length(deck) > 1L) {
        for (i in seq.int(length(deck), 2L)) {
            j <- (draw(g$rng) %% i) + 1L
            tmp <- deck[i]
            deck[i] <- deck[j]
            deck[j] <- tmp
        }
    }
    free <- which(vapply(g$stacked, is.null, logical(1)))
    for (i in seq_along(deck)) {
        seat <- free[((i - 1L) %% length(free)) + 1L]
        g$hands[[seat]] <- c(g$hands[[seat]], deck[i])
    }
    g$stacked <- vector("list", 4)
    g$passed <- rep(FALSE, 4)
    g$passes <- vector("list", 4)
    g$taken <- replicate(4, integer(), simplify = FALSE)
    g$tricks <- list()
    g$counts <- integer(4)
    g$current <- list()
    g$broken <- FALSE
    g$undo <- list()
    g$record <- character()
    record_line(g, 1L, paste("hand", g$number, "pass", directions[[g$direction]]))
    for (seat in 1:4) record_line(g, 2L, paste0(seats[seat], ": ", cards_text(g$hands[[seat]])))
    if (g$direction == "H") begin_play(g) else g$state <- "passing"
}
pass_cards <- function(g, seat, cards) {
    g$hands[[seat]] <- setdiff(g$hands[[seat]], cards)
    g$passed[seat] <- TRUE
    g$passes[[seat]] <- cards
    record_line(g, 2L, paste(seats[seat], "passes", cards_text(cards)))
    if (all(g$passed)) {
        offset <- c(L = 1L, R = 3L, A = 2L)[[g$direction]]
        for (source in 1:4) {
            target <- next_seat(source, offset)
            g$hands[[target]] <- c(g$hands[[target]], g$passes[[source]])
        }
        begin_play(g)
    }
}
actor <- function(g) next_seat(g$leader, length(g$current))
legal <- function(g) {
    hand <- g$hands[[actor(g)]]
    if (!length(g$current)) {
        if (!length(g$tricks)) return(0L)
        safe <- hand[(hand %/% 13L) != 3L]
        return(if (!g$broken && length(safe)) safe else hand)
    }
    led <- g$current[[1]]$card %/% 13L
    followers <- hand[(hand %/% 13L) == led]
    if (length(followers)) return(followers)
    if (!length(g$tricks) && g$rules[["BLOOD"]] == "OFF") {
        safe <- hand[!penalty(hand)]
        if (length(safe)) return(safe)
    }
    hand
}
choose_pass <- function(g, seat) {
    hand <- g$hands[[seat]]
    strategy <- g$bots$values[seat]
    low <- ordered(hand)
    high <- ordered(hand, TRUE)
    hearts <- high[(high %/% 13L) == 3L]
    special <- c(QS, KS, AS)
    special <- special[special %in% hand]
    if (strategy == "LOW") {
        priority <- high
    } else if (strategy == "HIGH") {
        priority <- low
    } else if (strategy == "MOON") {
        priority <- c(low[(low %/% 13L) != 3L], low[(low %/% 13L) == 3L])
    } else if (strategy == "SMART") {
        protected <- QS %in% hand && sum((hand %/% 13L) == 2L) >= 5L
        priority <- if (protected) integer() else special
        counts <- vapply(0:1, function(suit) sum((hand %/% 13L) == suit), integer(1))
        available <- which(counts > 0L)
        if (length(available)) {
            suit <- available[order(counts[available], available)][1] - 1L
            priority <- c(priority, high[(high %/% 13L) == suit])
        }
        priority <- c(priority, hearts, high)
    } else {
        priority <- c(special, hearts, high)
    }
    unique(priority)[1:3]
}
queen_played <- function(g) {
    any(vapply(g$taken, function(cards) QS %in% cards, logical(1))) ||
        any(vapply(g$current, function(play) play$card == QS, logical(1)))
}
choose_play <- function(g) {
    seat <- actor(g)
    hand <- g$hands[[seat]]
    playable <- legal(g)
    strategy <- g$bots$values[seat]
    if (strategy == "LOW") return(lowest(playable))
    if (strategy == "HIGH") return(highest(playable))
    if (strategy == "MOON" && any(vapply(setdiff(1:4, seat), function(other) any(penalty(g$taken[[other]])), logical(1)))) {
        strategy <- "BASIC"
    }
    if (!length(g$current)) {
        if (strategy == "SMART" && !queen_played(g) && !(QS %in% hand)) {
            small <- playable[(playable %/% 13L) == 2L & (playable %% 13L) < 10L]
            if (length(small)) return(lowest(small))
        }
        available <- sort(unique(playable %/% 13L))
        counts <- vapply(available, function(suit) sum((playable %/% 13L) == suit), integer(1))
        suit <- available[order(if (strategy == "MOON") -counts else counts, available)][1]
        subset <- playable[(playable %/% 13L) == suit]
        return(if (strategy == "MOON") highest(subset) else lowest(subset))
    }
    led <- g$current[[1]]$card %/% 13L
    if (any((hand %/% 13L) == led)) {
        played <- vapply(g$current, function(play) play$card, integer(1))
        winning <- max((played[played %/% 13L == led]) %% 13L)
        lower <- playable[(playable %% 13L) < winning]
        if (strategy == "MOON") {
            high <- highest(playable)
            return(if ((high %% 13L) > winning) high else lowest(playable))
        }
        if (length(lower)) return(highest(lower))
        if (strategy == "SMART" && length(g$current) == 3L) {
            safe <- playable[playable != QS]
            return(if (length(safe)) highest(safe) else QS)
        }
        return(lowest(playable))
    }
    if (strategy == "MOON") {
        safe <- playable[!penalty(playable)]
        return(lowest(if (length(safe)) safe else playable))
    }
    if (QS %in% playable) return(QS)
    if (strategy == "SMART" && !queen_played(g)) {
        if (AS %in% playable) return(AS)
        if (KS %in% playable) return(KS)
    }
    hearts <- playable[(playable %/% 13L) == 3L]
    highest(if (length(hearts)) hearts else playable)
}
winner <- function(plays) {
    led <- plays[[1]]$card %/% 13L
    candidates <- Filter(function(play) (play$card %/% 13L) == led, plays)
    candidates[[which.max(vapply(candidates, function(play) play$card %% 13L, integer(1)))]]$seat
}
plays_text <- function(plays) paste(vapply(plays, function(play) paste(seats[play$seat], card_text(play$card)), character(1)), collapse = " ")
trick_line <- function(g, plays, number) {
    value <- sum(vapply(plays, function(play) point(g, play$card), numeric(1)))
    paste0("trick ", number, ": ", plays_text(plays), " -> ", seats[winner(plays)], " ", value)
}
play_card <- function(g, card) {
    seat <- actor(g)
    fields <- c("hands", "taken", "tricks", "counts", "current", "leader", "broken", "record")
    snapshot <- lapply(fields, function(name) g[[name]])
    names(snapshot) <- fields
    snapshot$log_size <- length(g$log)
    snapshot$seat <- seat
    snapshot$card <- card
    g$undo[[length(g$undo) + 1L]] <- snapshot
    g$hands[[seat]] <- setdiff(g$hands[[seat]], card)
    g$current[[length(g$current) + 1L]] <- list(seat = seat, card = card)
    if ((card %/% 13L) == 3L || card == QS && g$rules[["QSBREAK"]] == "ON") g$broken <- TRUE
    if (length(g$current) == 4L) {
        who <- winner(g$current)
        g$taken[[who]] <- c(g$taken[[who]], vapply(g$current, function(play) play$card, integer(1)))
        g$counts[who] <- g$counts[who] + 1L
        g$tricks[[length(g$tricks) + 1L]] <- g$current
        record_line(g, 2L, trick_line(g, g$current, length(g$tricks)))
        g$current <- list()
        g$leader <- who
        if (length(g$tricks) == 13L) finish_hand(g)
    }
}
undo_card <- function(g) {
    index <- length(g$undo)
    snapshot <- g$undo[[index]]
    g$undo <- g$undo[seq_len(index - 1L)]
    for (name in c("hands", "taken", "tricks", "counts", "current", "leader", "broken", "record")) {
        g[[name]] <- snapshot[[name]]
    }
    g$log <- g$log[seq_len(snapshot$log_size)]
    c(snapshot$seat, snapshot$card)
}
ranking <- function(g) order(g$scores, 1:4)
ended <- function(g, scores) g$number >= as.numeric(g$rules[["LIMIT"]]) || max(scores) >= as.numeric(g$rules[["TARGET"]])
stats_lines <- function(g) {
    vapply(1:4, function(seat) paste("stats", seats[seat], "tricks", g$stats[seat, 1], "hearts", g$stats[seat, 2], "queens", g$stats[seat, 3], "moons", g$stats[seat, 4]), character(1))
}
finish_hand <- function(g) {
    values <- vapply(g$taken, function(cards) points(g, cards), numeric(1))
    shooters <- which(vapply(g$taken, function(cards) sum(penalty(cards)) == 14L, logical(1)))
    shooter <- if (length(shooters)) shooters[1] else 0L
    if (shooter != 0L) {
        values[shooter] <- values[shooter] - 26L
        method <- g$rules[["MOON"]]
        if (method == "AUTO") {
            addition <- g$scores + values + ifelse(1:4 == shooter, 0L, 26L)
            method <- if (ended(g, addition) && order(addition, 1:4)[1] != shooter) "SUB" else "ADD"
        }
        if (method == "SUB") values[shooter] <- values[shooter] - 26L else values[-shooter] <- values[-shooter] + 26L
        record_line(g, 1L, paste("moon", seats[shooter], method))
    }
    for (seat in 1:4) {
        g$scores[seat] <- g$scores[seat] + values[seat]
        g$stats[seat, ] <- g$stats[seat, ] + c(g$counts[seat], sum((g$taken[[seat]] %/% 13L) == 3L), QS %in% g$taken[[seat]], shooter == seat)
    }
    record_line(g, 1L, pairs("points", values))
    record_line(g, 1L, pairs("scores", g$scores))
    g$history[[length(g$history) + 1L]] <- list(number = g$number, direction = directions[[g$direction]], points = values, shooter = shooter, record = g$record)
    g$state <- if (ended(g, g$scores)) "none" else "between"
    if (g$state == "none") {
        record_line(g, 0L, paste("game over hands", g$number))
        order_seats <- ranking(g)
        for (place in 1:4) record_line(g, 0L, paste("rank", place, seats[order_seats[place]], g$scores[order_seats[place]]))
        for (line in stats_lines(g)) record_line(g, 0L, line)
    }
}
auto_pass <- function(g) {
    for (seat in 1:4) if (!g$passed[seat]) pass_cards(g, seat, choose_pass(g, seat))
}
auto_hand <- function(g) {
    if (g$state == "passing") auto_pass(g)
    while (g$state == "playing") play_card(g, choose_play(g))
}
auto_game <- function(g) {
    if (g$state %in% c("passing", "playing")) auto_hand(g)
    while (g$state != "none") {
        deal(g)
        auto_hand(g)
    }
}
duplicate <- function(cards) {
    seen <- integer()
    for (card in cards) {
        if (card %in% seen) fail(paste("duplicate card", card_text(card)))
        seen <- c(seen, card)
    }
}
active <- function(table) !is.null(table$game) && table$game$state != "none"
require_state <- function(table, state) {
    if (state == "game") {
        if (!active(table)) fail("no game")
    } else if (state == "between") {
        require_state(table, "game")
        if (table$game$state != "between") fail("hand in progress")
    } else if (state == "hand") {
        if (!active(table) || !(table$game$state %in% c("passing", "playing"))) fail("no hand")
    } else if (!active(table) || table$game$state != state) {
        fail(paste("not", state))
    }
}
simulate <- function(table, command, seed, repetitions) {
    rng <- new_generator(seed)
    if (command == "GAME") {
        g <- new_game(table$rules, table$bots, rng)
        auto_game(g)
        selected <- Filter(function(entry) entry$level <= repetitions, g$log)
        return(c(paste("game seed", seed), vapply(selected, function(entry) entry$text, character(1))))
    }
    rounds <- if (command == "ROTATE") 4L else 1L
    places <- matrix(0, 4, 4)
    totals <- numeric(4)
    statistics <- matrix(0, 4, 4)
    hands <- 0L
    for (rotation in seq_len(rounds) - 1L) {
        bots <- new.env(parent = emptyenv())
        bots$values <- character(4)
        for (seat in 1:4) bots$values[next_seat(seat, rotation)] <- table$bots$values[seat]
        for (i in seq_len(repetitions)) {
            g <- new_game(table$rules, bots, rng)
            auto_game(g)
            hands <- hands + g$number
            order_seats <- ranking(g)
            for (seat in 1:4) {
                actual <- next_seat(seat, rotation)
                place <- match(actual, order_seats)
                places[seat, place] <- places[seat, place] + 1L
                totals[seat] <- totals[seat] + g$scores[actual]
                statistics[seat, ] <- statistics[seat, ] + g$stats[actual, ]
            }
        }
    }
    games <- rounds * repetitions
    output <- paste(tolower(command), "seed", seed, "games", games, "hands", hands)
    for (seat in 1:4) {
        cents <- floor(100 * totals[seat] / games)
        magnitude <- abs(cents)
        average <- paste0(if (cents < 0) "-" else "", magnitude %/% 100, ".", sprintf("%02d", as.integer(magnitude %% 100)))
        name <- if (command == "ROTATE") paste(seats[seat], table$bots$values[seat]) else seats[seat]
        output <- c(output, paste(name, "places", paste(places[seat, ], collapse = " "), "total", totals[seat], "average", average,
                                  "tricks", statistics[seat, 1], "hearts", statistics[seat, 2], "queens", statistics[seat, 3], "moons", statistics[seat, 4]))
    }
    output
}
command <- function(table, words) {
    cmd <- words[1]
    args <- words[-1]
    known <- strsplit("RULE BOT SETTINGS GAME MATCH ROTATE NEW ABANDON STACK DEAL SHOW PASS PLAY AUTO UNDO CLAIM LEGAL PREVIEW SCORE TAKEN TRICKS VOIDS UNSEEN STATS HISTORY REPLAY", " ", fixed = TRUE)[[1]]
    if (!(cmd %in% known)) fail(paste("unknown command", cmd))
    if (cmd == "RULE") {
        name <- args[1]
        value <- args[2]
        if (!(name %in% rule_names)) fail(paste("unknown rule", name))
        if (name %in% c("TARGET", "LIMIT")) {
            bounded(value, 1, if (name == "TARGET") 1000 else 100)
        } else {
            good <- if (name == "PASS") nchar(value) <= 8L && grepl("^[LRAH]+$", value) else if (name == "MOON") value %in% c("ADD", "SUB", "AUTO") else value %in% c("ON", "OFF")
            if (!good) fail(paste("bad value", value))
        }
        if (active(table)) fail("game in progress")
        table$rules[[name]] <- value
        return(paste("rule", name, value))
    }
    if (cmd == "BOT") {
        seat <- seat_value(args[1])
        if (!(args[2] %in% c("BASIC", "LOW", "HIGH", "SMART", "MOON"))) fail(paste("bad value", args[2]))
        table$bots$values[seat] <- args[2]
        return(paste("bot", seats[seat], args[2]))
    }
    if (cmd == "SETTINGS") return(c(paste("rules", paste(rule_names, unlist(table$rules[rule_names]), collapse = " ")), pairs("bots", table$bots$values)))
    if (cmd %in% c("GAME", "MATCH", "ROTATE")) {
        seed <- bounded(args[1], 1, 2147483646)
        repetitions <- bounded(args[2], if (cmd == "GAME") 0 else 1, if (cmd == "GAME") 2 else if (cmd == "MATCH") 50 else 10)
        return(simulate(table, cmd, seed, repetitions))
    }
    if (cmd == "NEW") {
        seed <- bounded(args[1], 1, 2147483646)
        if (active(table)) fail("game in progress")
        table$game <- new_game(table$rules, table$bots, new_generator(seed))
        return(paste("new game seed", seed))
    }
    if (cmd == "ABANDON") {
        require_state(table, "game")
        table$game <- NULL
        return("game abandoned")
    }
    seat <- if (cmd %in% c("STACK", "PASS", "PLAY", "CLAIM")) seat_value(args[1]) else 0L
    cards <- if (cmd %in% c("STACK", "PASS", "PLAY")) vapply(args[-1], card_value, integer(1)) else integer()
    if (cmd == "STACK" && length(cards) != 13L) fail("need 13 cards")
    if (cmd == "AUTO" && !(args[1] %in% c("PASS", "CARD", "TRICK", "HAND", "GAME"))) fail(paste("bad value", args[1]))
    if (cmd %in% c("STACK", "DEAL")) {
        require_state(table, "between")
    } else if (cmd == "SHOW") {
        require_state(table, "hand")
    } else if (cmd == "PASS") {
        require_state(table, "passing")
    } else if (cmd %in% c("PLAY", "UNDO", "CLAIM", "LEGAL", "PREVIEW", "TAKEN", "TRICKS", "VOIDS", "UNSEEN")) {
        require_state(table, "playing")
    } else if (cmd %in% c("SCORE", "STATS", "HISTORY", "REPLAY")) {
        require_state(table, "game")
    } else if (cmd == "AUTO") {
        mode <- args[1]
        require_state(table, if (mode == "PASS") "passing" else if (mode %in% c("CARD", "TRICK")) "playing" else if (mode == "HAND") "hand" else "game")
    }
    g <- table$game
    before <- length(g$log)
    output <- character()
    if (cmd == "STACK") {
        duplicate(cards)
        for (card in cards) for (other in setdiff(1:4, seat)) {
            if (card %in% g$stacked[[other]]) fail(paste(card_text(card), "stacked for", seats[other]))
        }
        g$stacked[[seat]] <- cards
        return(paste("stacked", seats[seat]))
    } else if (cmd == "DEAL") {
        deal(g)
    } else if (cmd == "SHOW") {
        return(vapply(1:4, function(seat) paste0(seats[seat], ": ", cards_text(g$hands[[seat]])), character(1)))
    } else if (cmd == "PASS") {
        if (g$passed[seat]) fail(paste(seats[seat], "already passed"))
        duplicate(cards)
        for (card in cards) if (!(card %in% g$hands[[seat]])) fail(paste(seats[seat], "does not hold", card_text(card)))
        pass_cards(g, seat, cards)
    } else if (cmd == "PLAY") {
        card <- cards[1]
        if (seat != actor(g)) fail(paste("waiting for", seats[actor(g)]))
        if (!(card %in% g$hands[[seat]])) fail(paste(seats[seat], "does not hold", card_text(card)))
        if (!(card %in% legal(g))) {
            if (!length(g$current)) fail(if (!length(g$tricks)) "must lead 2C" else "hearts not broken")
            led <- g$current[[1]]$card %/% 13L
            if (any((g$hands[[seat]] %/% 13L) == led)) fail(paste("must follow", suits[led + 1L]))
            fail("no points on first trick")
        }
        output <- paste(seats[seat], "plays", card_text(card))
        play_card(g, card)
    } else if (cmd == "AUTO") {
        mode <- args[1]
        if (mode == "PASS") {
            auto_pass(g)
        } else if (mode == "CARD") {
            seat <- actor(g)
            card <- choose_play(g)
            output <- paste(seats[seat], "plays", card_text(card))
            play_card(g, card)
        } else if (mode == "TRICK") {
            completed <- length(g$tricks)
            while (g$state == "playing" && length(g$tricks) == completed) play_card(g, choose_play(g))
        } else if (mode == "HAND") {
            auto_hand(g)
        } else {
            auto_game(g)
        }
    } else if (cmd == "UNDO") {
        if (!length(g$undo)) fail("nothing to undo")
        result <- undo_card(g)
        return(paste("undo", seats[result[1]], card_text(result[2])))
    } else if (cmd == "CLAIM") {
        if (seat != actor(g)) fail(paste("waiting for", seats[actor(g)]))
        if (length(g$current)) fail("trick in progress")
        for (card in g$hands[[seat]]) for (other in setdiff(1:4, seat)) {
            hand <- g$hands[[other]]
            if (any((hand %/% 13L) == (card %/% 13L) & (hand %% 13L) > (card %% 13L))) fail("claim rejected")
        }
        remaining <- unlist(g$hands, use.names = FALSE)
        count <- 13L - length(g$tricks)
        g$taken[[seat]] <- c(g$taken[[seat]], remaining)
        g$counts[seat] <- g$counts[seat] + count
        g$hands <- replicate(4, integer(), simplify = FALSE)
        record_line(g, 2L, paste("claim", seats[seat], "tricks", count, "points", points(g, remaining)))
        finish_hand(g)
    } else if (cmd == "LEGAL") {
        return(paste0("legal ", seats[actor(g)], ": ", cards_text(legal(g)), " bot ", card_text(choose_play(g))))
    } else if (cmd == "PREVIEW") {
        for (card in sort(legal(g))) {
            trial <- list2env(as.list(g), parent = emptyenv())
            completed <- length(trial$tricks)
            play_card(trial, card)
            while (trial$state == "playing" && length(trial$tricks) == completed) play_card(trial, choose_play(trial))
            trick <- trial$tricks[[length(trial$tricks)]]
            value <- sum(vapply(trick, function(play) point(g, play$card), numeric(1)))
            output <- c(output, paste("preview", card_text(card), "->", seats[winner(trick)], value))
        }
        return(output)
    } else if (cmd == "SCORE") {
        output <- pairs("scores", g$scores)
        if (g$state == "playing") output <- c(output, pairs("taken", vapply(g$taken, function(cards) points(g, cards), numeric(1))))
        return(output)
    } else if (cmd == "TAKEN") {
        return(vapply(1:4, function(seat) {
            cards <- g$taken[[seat]]
            paste0(seats[seat], ": ", cards_text(cards[point(g, cards) != 0L]))
        }, character(1)))
    } else if (cmd == "TRICKS") {
        output <- vapply(seq_along(g$tricks), function(number) trick_line(g, g$tricks[[number]], number), character(1))
        if (length(g$current)) output <- c(output, paste("current:", plays_text(g$current)))
        return(if (length(output)) output else "no tricks")
    } else if (cmd == "VOIDS") {
        missing <- replicate(4, integer(), simplify = FALSE)
        for (trick in c(g$tricks, list(g$current))) {
            if (!length(trick)) next
            led <- trick[[1]]$card %/% 13L
            for (play in trick) if ((play$card %/% 13L) != led) missing[[play$seat]] <- union(missing[[play$seat]], led)
        }
        values <- vapply(missing, function(item) if (length(item)) paste(suits[sort(item) + 1L], collapse = "") else "-", character(1))
        return(pairs("voids", values))
    } else if (cmd == "UNSEEN") {
        who <- actor(g)
        played <- c(unlist(g$taken, use.names = FALSE), vapply(g$current, function(play) play$card, integer(1)))
        return(paste0("unseen ", seats[who], ": ", cards_text(setdiff(0:51, c(g$hands[[who]], played)))))
    } else if (cmd == "STATS") {
        return(stats_lines(g))
    } else if (cmd == "HISTORY") {
        for (hand in g$history) {
            line <- paste("hand", hand$number, "pass", hand$direction, pairs("points", hand$points))
            if (hand$shooter != 0L) line <- paste(line, "moon", seats[hand$shooter])
            output <- c(output, line)
        }
        return(if (length(output)) output else "no hands")
    } else if (cmd == "REPLAY") {
        hand <- bounded(args[1], 1, length(g$history))
        return(g$history[[hand]]$record)
    }
    entries <- if (length(g$log) > before) g$log[seq.int(before + 1L, length(g$log))] else list()
    c(output, vapply(entries, function(entry) entry$text, character(1)))
}
main <- function() {
    lines <- readLines(file("stdin"), warn = FALSE)
    table <- new.env(parent = emptyenv())
    table$rules <- as.list(setNames(c("100", "100", "ADD", "OFF", "OFF", "OFF", "LRAH"), rule_names))
    table$bots <- new.env(parent = emptyenv())
    table$bots$values <- rep("BASIC", 4)
    table$game <- NULL
    output <- character()
    for (line in lines[seq_len(as.integer(lines[1])) + 1L]) {
        result <- tryCatch(command(table, strsplit(line, " ", fixed = TRUE)[[1]]), command_error = function(error) paste0("error: ", error$message))
        output <- c(output, result)
    }
    if (length(output)) cat(paste(output, collapse = "\n"), "\n", sep = "")
}
main()
