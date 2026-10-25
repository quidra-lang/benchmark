suppressPackageStartupMessages(library(gmp))

COMMANDS <- c("SHOE", "RULE", "RULES", "PLAYER", "LEAVE", "REBUY", "BET", "SIDE", "DEAL", "INSURANCE", "HIT", "STAND", "DOUBLE", "SPLIT", "SURRENDER", "HINT", "AUTO", "STATUS", "COUNT", "STATS")
ACTIONS <- c("HIT", "STAND", "DOUBLE", "SPLIT", "SURRENDER")
IDLE_COMMANDS <- c("SHOE", "RULE", "PLAYER", "LEAVE", "REBUY", "BET", "SIDE", "DEAL")
PLAYER_COMMANDS <- c("LEAVE", "REBUY", "BET", "SIDE", "INSURANCE", ACTIONS, "AUTO")
RULE_NAMES <- c("DEALER", "PEN", "MIN", "MAX", "BJ", "DAS", "DOUBLE", "HANDS", "RSA", "SURRENDER", "CHARLIE", "SIDEMAX")
STAT_NAMES <- c("rounds", "hands", "wins", "losses", "pushes", "blackjacks", "busts", "surrenders", "doubles", "splits")
RANKS <- strsplit("A23456789TJQK", "", fixed = TRUE)[[1L]]
SUITS <- c("C", "D", "H", "S")

number <- function(value) format(value, scientific = FALSE, trim = TRUE)
signed <- function(value) paste0(if (value >= 0L) "+" else "", number(value))
emit <- function(...) {
    fields <- lapply(list(...), function(value) if (is.numeric(value)) number(value) else as.character(value))
    cat(paste(unlist(fields, use.names = FALSE), collapse = " "), "\n", sep = "")
}
fail <- function(message) stop(structure(list(message = message, call = NULL), class = c("command_error", "error", "condition")))
integer_word <- function(word, low, high) {
    if (!grepl("^(0|[1-9][0-9]{0,9})$", word, perl = TRUE)) fail(paste("bad value", word))
    value <- as.integer(word)
    if (value < low || value > high) fail(paste("bad value", word))
    value
}

new_rules <- function() list(DEALER = "S17", PEN = 75L, MIN = 10L, MAX = 500L, BJ = "3:2", DAS = TRUE, DOUBLE = "ANY", HANDS = 4L, RSA = FALSE, SURRENDER = TRUE, CHARLIE = 0L, SIDEMAX = 25L)
new_hand <- function(cards = integer(), bet = 0L, split = FALSE, split_aces = FALSE) {
    list(cards = cards, bet = bet, split = split, split_aces = split_aces, finish = "pending")
}
new_player <- function(name, bankroll) {
    list2env(list(name = name, bankroll = bankroll, bet = 0L, side = 0L, insurance = 0L, net = 0L,
                 hands = list(), stats = setNames(integer(10L), STAT_NAMES)), parent = emptyenv())
}
new_table <- function() {
    list2env(list(rules = new_rules(), players = vector("list", 7L), phase = "idle", round = 0L,
                 participants = integer(), insurance_turn = 1L, current_seat = 0L, current_hand = 0L,
                 dealer = new_hand(), hole_visible = FALSE, dealer_natural = FALSE,
                 dealer_blackjacks = 0L, dealer_busts = 0L, decks = 0L, shoe = integer(),
                 random_state = 1L, drawn = 0L, running = 0L), parent = emptyenv())
}
seated <- function(table) which(!vapply(table$players, is.null, logical(1L)))
find_player <- function(table, name) {
    seats <- seated(table)
    found <- seats[vapply(table$players[seats], function(player) player$name == name, logical(1L))]
    if (length(found)) found[[1L]] else 0L
}
lookup_player <- function(table, name) {
    seat <- find_player(table, name)
    if (seat == 0L) fail(paste("unknown player", name))
    seat
}

parse_rule <- function(name, word) {
    if (!name %in% RULE_NAMES) fail(paste("unknown rule", name))
    choices <- switch(name, DEALER = c("S17", "H17"), BJ = c("3:2", "6:5"),
                      DOUBLE = c("ANY", "9-11", "10-11"),
                      DAS = c("ON", "OFF"), RSA = c("ON", "OFF"), SURRENDER = c("ON", "OFF"), NULL)
    if (!is.null(choices)) {
        if (!word %in% choices) fail(paste("bad value", word))
        return(if (name %in% c("DAS", "RSA", "SURRENDER")) word == "ON" else word)
    }
    bounds <- switch(name, PEN = c(50L, 90L), MIN = c(1L, 10000L), MAX = c(1L, 10000L),
                     HANDS = c(1L, 4L), CHARLIE = c(0L, 7L), SIDEMAX = c(0L, 1000L))
    value <- integer_word(word, bounds[1L], bounds[2L])
    if (name == "CHARLIE" && !value %in% c(0L, 5L, 6L, 7L)) fail(paste("bad value", word))
    value
}
rule_text <- function(value) {
    if (is.logical(value)) if (value) "ON" else "OFF"
    else if (is.numeric(value)) number(value) else value
}

point <- function(cards) pmin(10L, cards %% 13L + 1L)
card_text <- function(cards) paste0(RANKS[cards %% 13L + 1L], SUITS[cards %/% 13L + 1L])
hand_total <- function(hand) {
    value <- sum(point(hand$cards))
    soft <- any(hand$cards %% 13L == 0L) && value + 10L <= 21L
    list(value = value + if (soft) 10L else 0L, soft = soft)
}
blackjack <- function(hand) !hand$split && length(hand$cards) == 2L && hand_total(hand)$value == 21L
hand_text <- function(hand) {
    score <- hand_total(hand)
    status <- if (blackjack(hand)) "blackjack" else if (score$value > 21L) paste("bust", score$value) else if (score$soft) paste("soft", score$value) else number(score$value)
    paste0(paste(card_text(hand$cards), collapse = " "), " (", status, ")")
}
hand_name <- function(player, index) paste0(player$name, "[", index, "]")
hand_line <- function(table, seat, index, verb = "") {
    player <- table$players[[seat]]
    emit(paste0(hand_name(player, index), verb, ": ", hand_text(player$hands[[index]])))
}
cut <- function(table) (length(table$shoe) * table$rules$PEN) %/% 100L

next_random <- function(state) as.integer(as.character((as.bigz(state) * 48271L) %% 2147483647L))
shuffle <- function(table) {
    table$shoe <- (seq_len(52L * table$decks) - 1L) %% 52L
    for (index in seq.int(length(table$shoe), 2L)) {
        table$random_state <- next_random(table$random_state)
        other <- table$random_state %% index + 1L
        table$shoe[c(index, other)] <- table$shoe[c(other, index)]
    }
    table$drawn <- table$running <- 0L
}
hilo <- function(card) {
    value <- point(card)
    if (value >= 2L && value <= 6L) 1L else if (value >= 7L && value <= 9L) 0L else -1L
}
draw <- function(table, visible) {
    table$drawn <- table$drawn + 1L
    card <- table$shoe[table$drawn]
    if (visible) table$running <- table$running + hilo(card)
    card
}
reveal_dealer <- function(table) {
    if (!table$hole_visible) {
        table$running <- table$running + hilo(table$dealer$cards[2L])
        table$hole_visible <- TRUE
    }
    emit(paste0("dealer: ", hand_text(table$dealer)))
}
finish_hand <- function(hand, rules, hand_count) {
    value <- hand_total(hand)$value
    if (value > 21L) hand$finish <- "bust"
    else if (rules$CHARLIE != 0L && length(hand$cards) == rules$CHARLIE) hand$finish <- "charlie"
    else if (value == 21L) hand$finish <- "ordinary"
    else if (hand$split_aces && length(hand$cards) == 2L) {
        again <- all(hand$cards %% 13L == 0L) && rules$RSA && hand_count < rules$HANDS
        hand$finish <- if (again) "pending" else "ordinary"
    }
    hand
}
hand_result <- function(table, hand) {
    if (table$dealer_natural) return(if (blackjack(hand)) "push" else "lose")
    if (blackjack(hand)) return("blackjack")
    if (hand$finish %in% c("bust", "surrender", "charlie")) return(hand$finish)
    player_total <- hand_total(hand)$value
    dealer_total <- hand_total(table$dealer)$value
    if (dealer_total > 21L || player_total > dealer_total) "win" else if (player_total == dealer_total) "push" else "lose"
}
hand_profit <- function(rules, bet, result) {
    if (result == "blackjack") return(if (rules$BJ == "3:2") (bet * 3L) %/% 2L else (bet * 6L) %/% 5L)
    if (result %in% c("win", "charlie")) return(bet)
    if (result == "push") return(0L)
    if (result == "surrender") return(bet %/% 2L - bet)
    -bet
}
settle <- function(table) {
    for (seat in table$participants) {
        player <- table$players[[seat]]
        for (index in seq_along(player$hands)) {
            hand <- player$hands[[index]]
            result <- hand_result(table, hand)
            profit <- hand_profit(table$rules, hand$bet, result)
            player$bankroll <- player$bankroll + hand$bet + profit
            player$net <- player$net + profit
            player$stats["hands"] <- player$stats["hands"] + 1L
            field <- if (result %in% c("blackjack", "win", "charlie")) "wins" else if (result == "push") "pushes" else "losses"
            player$stats[field] <- player$stats[field] + 1L
            if (result %in% c("blackjack", "bust", "surrender")) {
                field <- switch(result, blackjack = "blackjacks", bust = "busts", surrender = "surrenders")
                player$stats[field] <- player$stats[field] + 1L
            }
            emit(hand_name(player, index), result, signed(profit))
        }
        emit(player$name, "bankroll", player$bankroll)
    }
    for (seat in seated(table)) {
        table$players[[seat]]$bet <- 0L
        table$players[[seat]]$side <- 0L
    }
    table$phase <- "idle"
}
dealer_turn <- function(table) {
    reveal_dealer(table)
    hands <- unlist(lapply(table$players[table$participants], function(player) player$hands), recursive = FALSE)
    required <- any(vapply(hands, function(hand) hand$finish == "ordinary" && !blackjack(hand), logical(1L)))
    drew <- FALSE
    if (required) repeat {
        score <- hand_total(table$dealer)
        if (!(score$value < 17L || (score$value == 17L && score$soft && table$rules$DEALER == "H17"))) break
        table$dealer$cards <- c(table$dealer$cards, draw(table, TRUE))
        emit(paste0("dealer hits: ", hand_text(table$dealer)))
        drew <- TRUE
    }
    if (drew && hand_total(table$dealer)$value > 21L) table$dealer_busts <- table$dealer_busts + 1L
    settle(table)
}
advance_hands <- function(table) {
    repeat {
        next_seat <- next_hand <- 0L
        for (seat in table$participants) {
            unfinished <- which(vapply(table$players[[seat]]$hands, function(hand) hand$finish == "pending", logical(1L)))
            if (length(unfinished)) {
                next_seat <- seat
                next_hand <- unfinished[[1L]]
                break
            }
        }
        if (next_seat == 0L) {
            dealer_turn(table)
            return(invisible(NULL))
        }
        table$current_seat <- next_seat
        table$current_hand <- next_hand
        player <- table$players[[next_seat]]
        hand <- player$hands[[next_hand]]
        if (length(hand$cards) != 1L) return(invisible(NULL))
        hand$cards <- c(hand$cards, draw(table, TRUE))
        emit(paste0(hand_name(player, next_hand), ": ", hand_text(hand)))
        hand <- finish_hand(hand, table$rules, length(player$hands))
        player$hands[[next_hand]] <- hand
        if (hand$finish == "pending") return(invisible(NULL))
    }
}
peek <- function(table) {
    table$dealer_natural <- blackjack(table$dealer)
    emit("dealer peeks:", if (table$dealer_natural) "blackjack" else "no blackjack")
    for (seat in table$participants) {
        player <- table$players[[seat]]
        if (player$insurance == 0L) next
        profit <- if (table$dealer_natural) player$insurance * 2L else -player$insurance
        player$bankroll <- player$bankroll + player$insurance + profit
        player$net <- player$net + profit
        emit(player$name, "insurance", signed(profit))
    }
    if (table$dealer_natural) {
        table$dealer_blackjacks <- table$dealer_blackjacks + 1L
        reveal_dealer(table)
        settle(table)
    } else {
        table$phase <- "play"
        advance_hands(table)
    }
}
deal <- function(table) {
    if (table$drawn >= cut(table)) {
        shuffle(table)
        emit("shuffle")
    }
    table$round <- table$round + 1L
    emit("round", table$round)
    seats <- seated(table)
    table$participants <- seats[vapply(table$players[seats], function(player) player$bet != 0L, logical(1L))]
    for (seat in table$participants) {
        player <- table$players[[seat]]
        player$bankroll <- player$bankroll - player$bet - player$side
        player$insurance <- 0L
        player$stats["rounds"] <- player$stats["rounds"] + 1L
        player$hands <- list(new_hand(bet = player$bet))
    }
    for (seat in table$participants) table$players[[seat]]$hands[[1L]]$cards <- draw(table, TRUE)
    table$dealer <- new_hand(draw(table, TRUE))
    for (seat in table$participants) {
        player <- table$players[[seat]]
        player$hands[[1L]]$cards <- c(player$hands[[1L]]$cards, draw(table, TRUE))
        if (blackjack(player$hands[[1L]])) player$hands[[1L]]$finish <- "ordinary"
    }
    table$dealer$cards <- c(table$dealer$cards, draw(table, FALSE))
    table$hole_visible <- table$dealer_natural <- FALSE
    for (seat in table$participants) hand_line(table, seat, 1L)
    emit("dealer:", card_text(table$dealer$cards[1L]), "??")
    for (seat in table$participants) {
        player <- table$players[[seat]]
        if (player$side == 0L) next
        cards <- player$hands[[1L]]$cards
        colors <- cards %/% 13L %in% c(0L, 3L)
        multiplier <- if (cards[1L] %% 13L != cards[2L] %% 13L) -1L else if (cards[1L] == cards[2L]) 25L else if (colors[1L] == colors[2L]) 12L else 6L
        result <- if (multiplier == 25L) "perfect" else if (multiplier == 12L) "colored" else if (multiplier == 6L) "mixed" else "lose"
        profit <- player$side * multiplier
        player$bankroll <- player$bankroll + player$side + profit
        player$net <- player$net + profit
        emit(player$name, "side", result, signed(profit))
    }
    upcard <- point(table$dealer$cards[1L])
    if (upcard == 1L) {
        table$phase <- "insurance"
        table$insurance_turn <- 1L
        emit("insurance offered")
    } else if (upcard == 10L) peek(table)
    else {
        table$phase <- "play"
        advance_hands(table)
    }
}

action_problem <- function(table, action) {
    player <- table$players[[table$current_seat]]
    hand <- player$hands[[table$current_hand]]
    if (action == "HIT") return(if (hand$split_aces) "split aces" else NULL)
    if (action == "DOUBLE") {
        if (hand$split_aces) return("split aces")
        if (length(hand$cards) != 2L) return("two cards only")
        score <- hand_total(hand)
        limited <- table$rules$DOUBLE != "ANY" && (score$soft || score$value > 11L || score$value < if (table$rules$DOUBLE == "9-11") 9L else 10L)
        if (limited || (!table$rules$DAS && hand$split)) return("double not allowed")
        if (player$bankroll < hand$bet) return("insufficient funds")
    } else if (action == "SPLIT") {
        if (length(hand$cards) != 2L) return("two cards only")
        if (point(hand$cards[1L]) != point(hand$cards[2L])) return("not a pair")
        if (length(player$hands) >= table$rules$HANDS) return("hand limit")
        if (player$bankroll < hand$bet) return("insufficient funds")
    } else if (action == "SURRENDER") {
        if (!table$rules$SURRENDER || hand$split) return("surrender not allowed")
        if (length(hand$cards) != 2L) return("two cards only")
    }
    NULL
}
recommendation <- function(table) {
    hand <- table$players[[table$current_seat]]$hands[[table$current_hand]]
    can_split <- is.null(action_problem(table, "SPLIT"))
    if (hand$split_aces) return(if (can_split) "SPLIT" else "STAND")
    up <- point(table$dealer$cards[1L])
    if (up == 1L) up <- 11L
    if (can_split) {
        value <- point(hand$cards[1L])
        wanted <- value %in% c(1L, 8L) || (value == 9L && !up %in% c(7L, 10L, 11L)) || (value %in% c(2L, 3L, 7L) && up <= 7L) || (value == 6L && up <= 6L) || (value == 4L && up %in% c(5L, 6L))
        if (wanted) return("SPLIT")
    }
    score <- hand_total(hand)
    value <- score$value
    can_double <- is.null(action_problem(table, "DOUBLE"))
    if (score$soft) {
        if (value >= 19L) return("STAND")
        if (value == 18L) {
            if (up >= 3L && up <= 6L) return(if (can_double) "DOUBLE" else "STAND")
            return(if (up %in% c(2L, 7L, 8L)) "STAND" else "HIT")
        }
        wanted <- (value == 17L && up >= 3L && up <= 6L) || (value %in% c(15L, 16L) && up >= 4L && up <= 6L) || (value %in% c(13L, 14L) && up %in% c(5L, 6L))
        return(if (wanted && can_double) "DOUBLE" else "HIT")
    }
    if (value >= 17L) return("STAND")
    if (value >= 13L) {
        if (up <= 6L) return("STAND")
        if (((value == 16L && up >= 9L) || (value == 15L && up == 10L)) && is.null(action_problem(table, "SURRENDER"))) return("SURRENDER")
        return("HIT")
    }
    if (value == 12L) return(if (up >= 4L && up <= 6L) "STAND" else "HIT")
    wanted <- (value == 11L && up <= 10L) || (value == 10L && up <= 9L) || (value == 9L && up >= 3L && up <= 6L)
    if (wanted && can_double) "DOUBLE" else "HIT"
}
perform_action <- function(table, action) {
    player <- table$players[[table$current_seat]]
    index <- table$current_hand
    hand <- player$hands[[index]]
    name <- hand_name(player, index)
    if (action == "SPLIT") {
        player$bankroll <- player$bankroll - hand$bet
        player$stats["splits"] <- player$stats["splits"] + 1L
        emit(name, "splits", card_text(hand$cards))
        aces <- hand$split_aces || point(hand$cards[1L]) == 1L
        first <- new_hand(hand$cards[1L], hand$bet, TRUE, aces)
        second <- new_hand(hand$cards[2L], hand$bet, TRUE, aces)
        player$hands <- append(player$hands[-index], list(first, second), after = index - 1L)
        hand <- player$hands[[index]]
        hand$cards <- c(hand$cards, draw(table, TRUE))
        emit(paste0(name, ": ", hand_text(hand)))
        player$hands[[index]] <- finish_hand(hand, table$rules, length(player$hands))
    } else if (action %in% c("STAND", "SURRENDER")) {
        hand$finish <- if (action == "STAND") "ordinary" else "surrender"
        verb <- if (action == "STAND") "stands" else "surrenders"
        emit(paste0(name, " ", verb, ": ", hand_text(hand)))
        player$hands[[index]] <- hand
    } else {
        if (action == "DOUBLE") {
            player$bankroll <- player$bankroll - hand$bet
            hand$bet <- hand$bet * 2L
            player$stats["doubles"] <- player$stats["doubles"] + 1L
        }
        hand$cards <- c(hand$cards, draw(table, TRUE))
        verb <- if (action == "DOUBLE") "doubles" else "hits"
        emit(paste0(name, " ", verb, ": ", hand_text(hand)))
        hand <- finish_hand(hand, table$rules, length(player$hands))
        if (action == "DOUBLE" && hand$finish == "pending") hand$finish <- "ordinary"
        player$hands[[index]] <- hand
    }
    advance_hands(table)
}

status_output <- function(table) {
    heading <- paste("table", table$phase, "round", table$round)
    if (table$phase == "insurance") heading <- paste(heading, "next", table$players[[table$participants[table$insurance_turn]]]$name)
    else if (table$phase == "play") heading <- paste(heading, "turn", hand_name(table$players[[table$current_seat]], table$current_hand))
    emit(heading)
    if (table$phase != "idle") emit("dealer:", card_text(table$dealer$cards[1L]), "??")
    for (seat in seated(table)) {
        player <- table$players[[seat]]
        emit("seat", seat, player$name, "bankroll", player$bankroll, "bet", player$bet, "side", player$side)
        if (table$phase != "idle" && seat %in% table$participants) {
            for (index in seq_along(player$hands)) emit(paste0(hand_name(player, index), ": ", hand_text(player$hands[[index]])), "bet", player$hands[[index]]$bet)
        }
    }
}
statistics_output <- function(table) {
    for (seat in seated(table)) {
        player <- table$players[[seat]]
        fields <- paste(STAT_NAMES, number(player$stats), collapse = " ")
        emit("stats", player$name, fields, "net", signed(player$net))
    }
    emit("stats dealer rounds", table$round, "blackjacks", table$dealer_blackjacks, "busts", table$dealer_busts)
}

command <- function(table, tokens) {
    op <- tokens[1L]
    if (!op %in% COMMANDS) fail(paste("unknown command", op))
    seat <- 0L
    amount <- seed <- 0L
    rule_value <- NULL
    if (op == "SHOE") {
        amount <- integer_word(tokens[2L], 1L, 8L)
        seed <- integer_word(tokens[3L], 1L, 2147483646L)
    } else if (op == "RULE") rule_value <- parse_rule(tokens[2L], tokens[3L])
    else if (op == "PLAYER") {
        if (!grepl("^[A-Z]{1,8}$", tokens[2L], perl = TRUE)) fail(paste("bad name", tokens[2L]))
        amount <- integer_word(tokens[3L], 1L, 1000000L)
    } else if (op %in% PLAYER_COMMANDS) {
        seat <- lookup_player(table, tokens[2L])
        if (op %in% c("REBUY", "BET", "SIDE", "INSURANCE")) amount <- integer_word(tokens[3L], if (op == "REBUY") 1L else 0L, 1000000L)
    }
    if (op %in% IDLE_COMMANDS && table$phase != "idle") fail("round in progress")
    if (op == "INSURANCE" && table$phase != "insurance") fail("no insurance")
    action_command <- op %in% c(ACTIONS, "AUTO")
    if (action_command || op == "HINT") {
        if (table$phase == "idle") fail("no round")
        if (table$phase == "insurance") fail("insurance pending")
        if (action_command && seat != table$current_seat) fail(paste("waiting for", hand_name(table$players[[table$current_seat]], table$current_hand)))
    }
    if (action_command) {
        if (op == "AUTO") {
            while (table$phase == "play" && table$current_seat == seat) perform_action(table, recommendation(table))
        } else {
            problem <- action_problem(table, op)
            if (!is.null(problem)) fail(problem)
            perform_action(table, op)
        }
        return(invisible(NULL))
    }
    if (op == "SHOE") {
        table$decks <- amount
        table$random_state <- seed
        shuffle(table)
        emit("shoe", amount, "decks", length(table$shoe), "cards cut", cut(table))
    } else if (op == "RULE") {
        changed <- table$rules
        changed[[tokens[2L]]] <- rule_value
        if (changed$MIN > changed$MAX) fail("min above max")
        table$rules <- changed
        emit("rule", tokens[2L], rule_text(rule_value))
    } else if (op == "RULES") {
        fields <- paste(RULE_NAMES, vapply(table$rules[RULE_NAMES], rule_text, character(1L)), collapse = " ")
        emit("rules", fields)
    } else if (op == "PLAYER") {
        if (find_player(table, tokens[2L]) != 0L) fail("player exists")
        empty <- which(vapply(table$players, is.null, logical(1L)))
        if (!length(empty)) fail("table full")
        seat <- empty[[1L]]
        table$players[[seat]] <- new_player(tokens[2L], amount)
        emit(tokens[2L], "sits at seat", seat, "with", amount)
    } else if (op == "LEAVE") {
        player <- table$players[[seat]]
        emit(player$name, "leaves with", player$bankroll, "net", signed(player$net))
        table$players[seat] <- list(NULL)
    } else if (op == "REBUY") {
        player <- table$players[[seat]]
        player$bankroll <- player$bankroll + amount
        emit(player$name, "rebuys", amount, "bankroll", player$bankroll)
    } else if (op == "BET") {
        player <- table$players[[seat]]
        if (amount != 0L) {
            if (amount < table$rules$MIN || amount > table$rules$MAX) fail("bet out of limits")
            if (amount + player$side > player$bankroll) fail("insufficient funds")
        }
        player$bet <- amount
        if (amount == 0L) {
            player$side <- 0L
            emit(player$name, "bet cleared")
        } else emit(player$name, "bets", amount)
    } else if (op == "SIDE") {
        player <- table$players[[seat]]
        if (amount != 0L) {
            if (player$bet == 0L) fail("no bet")
            if (amount > table$rules$SIDEMAX) fail("side out of limits")
            if (player$bet + amount > player$bankroll) fail("insufficient funds")
        }
        player$side <- amount
        if (amount == 0L) emit(player$name, "side cleared") else emit(player$name, "side", amount)
    } else if (op == "DEAL") {
        if (table$decks == 0L) fail("no shoe")
        if (!any(vapply(table$players[seated(table)], function(player) player$bet != 0L, logical(1L)))) fail("no bets")
        deal(table)
    } else if (op == "INSURANCE") {
        waiting <- table$participants[table$insurance_turn]
        if (seat != waiting) fail(paste("waiting for", table$players[[waiting]]$name))
        player <- table$players[[seat]]
        if (amount > player$bet %/% 2L) fail("insurance out of limits")
        if (amount > player$bankroll) fail("insufficient funds")
        player$bankroll <- player$bankroll - amount
        player$insurance <- amount
        if (amount == 0L) emit(player$name, "declines insurance") else emit(player$name, "insures", amount)
        table$insurance_turn <- table$insurance_turn + 1L
        if (table$insurance_turn > length(table$participants)) peek(table)
    } else if (op == "HINT") emit(paste0("hint ", hand_name(table$players[[table$current_seat]], table$current_hand), ": ", tolower(recommendation(table))))
    else if (op == "STATUS") status_output(table)
    else if (op == "COUNT") {
        if (table$decks == 0L) fail("no shoe")
        remaining <- length(table$shoe) - table$drawn
        value <- (abs(table$running) * 5200L) %/% remaining
        text <- paste0(if (table$running < 0L) "-" else "", value %/% 100L, ".", sprintf("%02d", value %% 100L))
        emit("count running", table$running, "true", text, "remaining", remaining)
    } else if (op == "STATS") {
        if (!length(seated(table))) fail("no players")
        statistics_output(table)
    }
    invisible(NULL)
}

input <- readLines(file("stdin"), warn = FALSE)
command_count <- as.integer(input[1L])
table <- new_table()
for (line in input[seq_len(command_count) + 1L]) {
    tokens <- strsplit(line, " ", fixed = TRUE)[[1L]]
    tryCatch(command(table, tokens), command_error = function(problem) emit("error:", conditionMessage(problem)))
}
