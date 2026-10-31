source("tiles.R")
source("decomposition.R")
source("yaku.R")
source("scoring.R")
source("shanten.R")

WAIT_ORDER <- c("ryanmen", "kanchan", "penchan", "shanpon", "tanki", "single", "thirteen")
WIN_ORDER <- c("dealer_ron", "dealer_tsumo", "nondealer_ron", "nondealer_tsumo")
new_counter <- function() new.env(parent = emptyenv())
report_count <- function(counts, key) {
    value <- counts[[as.character(key)]]
    if (is.null(value)) 0L else value
}
add_report <- function(
    counts,
    key,
    amount = 1L
) counts[[as.character(key)]] <- report_count(counts, key) + amount
report_pairs <- function(keys, counts) paste(
    vapply(keys, function(key) paste(key, report_count(counts, key)), ""),
    collapse = " "
)

read_records <- function(filename) {
    lapply(readLines(file.path("input", filename), warn = FALSE), function(line) {
        items <- strsplit(line, " ", fixed = TRUE)[[1L]]
        fields <- list()
        for (item in items[-1L]) {
            parts <- strsplit(item, "=", fixed = TRUE)[[1L]]
            fields[[parts[1L]]] <- parts[2L]
        }
        list(label = items[1L], fields = fields)
    })
}

read_rules <- function() {
    rules <- list()
    for (record in read_records("rules.txt")) {
        rules[[record$label]] <- lapply(names(record$fields), function(key) {
            if (key == "honba") as.integer(record$fields[[key]]) else record$fields[[key]] == "yes"
        })
        names(rules[[record$label]]) <- names(record$fields)
    }
    rules
}

parse_meld <- function(text) {
    kind <- substr(text, 1L, 1L)
    tiles <- parse_tiles(substr(text, 2L, nchar(text)))
    block <- if (is.null(tiles)) integer() else sort(vapply(tiles, function(tile) tile$kind, 0L))
    list(kind = kind, tiles = tiles, block = block)
}

valid_meld <- function(meld) {
    block <- meld$block
    if (meld$kind == "C") return(length(block) == 3L && block[1L] < 27L && block[1L] %% 9L <= 6L && identical(
        block,
        block[1L]:(block[1L] + 2L)
    ))
    if (!meld$kind %in% c("P", "K", "A")) return(FALSE)
    length(block) == (if (meld$kind == "P") 3L else 4L) && length(unique(block)) == 1L
}

parse_situation <- function(label, fields, rules) {
    situation <- new.env(parent = emptyenv())
    situation$label <- label
    situation$rule_name <- fields$rules
    situation$rules <- rules[[fields$rules]]
    situation$hand <- parse_tiles(fields$hand)
    situation$win <- parse_tiles(fields$win)
    situation$melds <- if (fields$melds == "-") list() else lapply(
        strsplit(fields$melds, ",", fixed = TRUE)[[1L]],
        parse_meld
    )
    situation$dora <- parse_tiles(fields$dora)
    situation$ura <- parse_tiles(fields$ura, allow_empty = TRUE)
    situation$discards <- parse_tiles(fields$discards, allow_empty = TRUE)
    situation$by <- fields$by
    situation$seat <- fields$seat
    situation$discarder <- fields$from
    situation$round <- fields$round
    situation$seat_tile <- WIND_TILES[[fields$seat]]
    situation$round_tile <- WIND_TILES[[fields$round]]
    situation$flags <- if (fields$flags == "-") character() else strsplit(
        fields$flags,
        ",",
        fixed = TRUE
    )[[1L]]
    situation$closed <- all(vapply(situation$melds, function(meld) meld$kind == "A", FALSE))
    situation$riichi <- any(c("riichi", "double_riichi") %in% situation$flags)
    situation$kan_count <- sum(vapply(situation$melds, function(meld) meld$kind %in% c("K", "A"), FALSE))
    situation$honba <- as.integer(fields$honba)
    situation$sticks <- as.integer(fields$sticks)
    situation
}

prepare_situation <- function(situation) {
    meld_tiles <- unlist(lapply(situation$melds, function(meld) meld$tiles), recursive = FALSE)
    situation$winning_tile <- situation$win[[1L]]$kind
    situation$hand_counts <- tile_counts(situation$hand)
    situation$concealed_counts <- tile_counts(c(situation$hand, situation$win))
    situation$meld_counts <- tile_counts(meld_tiles)
    situation$all_tiles <- c(situation$hand, situation$win, meld_tiles)
    situation$all_counts <- tile_counts(situation$all_tiles)
    situation
}

copy_error <- function(all_tiles, rules) {
    reds <- integer(3L)
    for (tile in all_tiles) if (tile$red) reds[tile$kind %/% 9L + 1L] <- reds[tile$kind %/% 9L + 1L] + 1L
    if (!rules$red_fives && any(reds > 0L)) return("red five not allowed")
    counts <- tile_counts(all_tiles)
    for (kind in 0:33) if (counts[kind + 1L] >= 5L) return(paste("too many copies of", tile_name(kind)))
    for (suit in 1:3) if (reds[suit] >= 2L) return(paste0("too many copies of 0", TILE_SUITS[suit]))
    NULL
}

validate_situation <- function(situation) {
    values <- c(
        list(situation$hand, situation$win, situation$dora, situation$ura, situation$discards),
        lapply(situation$melds, function(meld) meld$tiles)
    )
    if (any(vapply(values, is.null, FALSE)) || length(situation$win) != 1L) return("bad tile notation")
    if (length(situation$melds) >= 5L || any(!vapply(situation$melds, valid_meld, FALSE))) return("bad meld")
    if (length(situation$hand) != 13L - 3L * length(situation$melds)) return("wrong tile count")
    prepare_situation(situation)
    error <- copy_error(
        c(situation$all_tiles, situation$dora, situation$ura, situation$discards),
        situation$rules
    )
    if (!is.null(error)) return(error)
    if ((situation$by == "tsumo" && situation$discarder != "-") || (situation$by == "ron" && situation$discarder %in% c(
        "-",
        situation$seat
    ))) return("invalid discarder")
    flags <- situation$flags
    valid_flags <- c(riichi = situation$closed,
        double_riichi = situation$closed && !"riichi" %in% flags,
        ippatsu = situation$riichi && !"rinshan" %in% flags,
        haitei = situation$by == "tsumo" && !"rinshan" %in% flags,
        houtei = situation$by == "ron" && !"chankan" %in% flags,
        rinshan = situation$by == "tsumo" && situation$kan_count >= 1L,
        chankan = situation$by == "ron",
        tenhou = situation$seat == "E" && situation$by == "tsumo" && !length(situation$melds) && identical(
            flags,
            "tenhou"
        ),
        chiihou = situation$seat != "E" && situation$by == "tsumo" && !length(situation$melds) && identical(
            flags,
            "chiihou"
        ))
    for (flag in SITUATION_FLAGS) if (flag %in% flags && !valid_flags[[flag]]) return(paste(
        "invalid flag",
        flag
    ))
    if (length(situation$dora) != 1L + situation$kan_count) return("invalid dora indicators")
    if ((situation$riichi && length(situation$ura) != length(situation$dora)) || (!situation$riichi && length(situation$ura) > 0L)) return("invalid ura indicators")
    if (situation$riichi && situation$sticks == 0L) return("invalid sticks")
    if (!winning_form(situation$concealed_counts, length(situation$melds))) return("not a winning hand")
    NULL
}

new_candidate <- function(form_type, pair, sets, winning_block, form, wait) {
    candidate <- new.env(parent = emptyenv())
    candidate$form_type <- form_type
    candidate$pair <- pair
    candidate$sets <- sets
    candidate$winning_block <- winning_block
    candidate$form <- form
    candidate$wait <- wait
    candidate$yaku <- candidate$yakuman <- candidate$fu_items <- list()
    candidate$multiplier <- candidate$han <- candidate$fu <- candidate$fu_total <- candidate$base <- 0L
    candidate$dora <- candidate$aka <- candidate$ura <- 0L
    candidate$category <- "none"
    candidate
}

make_candidates <- function(situation) {
    result <- list()
    winning <- situation$winning_tile
    counts <- situation$concealed_counts
    for (decomposition in standard_decompositions(counts, length(situation$melds))) {
        pair <- decomposition$pair
        sets <- decomposition$sets
        blocks <- c(list(c(pair, pair)), sets)
        choices <- unique(Filter(function(block) winning %in% block, blocks))
        for (chosen in choices) {
            parts <- "standard"
            marked <- FALSE
            for (block in blocks) {
                notation <- block_notation(block)
                if (identical(block, chosen) && !marked) {
                    notation <- paste0(notation, "*")
                    marked <- TRUE
                }
                parts <- c(parts, notation)
            }
            for (meld in situation$melds) parts <- c(parts, paste0(meld$kind, block_notation(meld$block)))
            result[[length(result) + 1L]] <- new_candidate(
                "standard",
                pair,
                sets,
                chosen,
                paste(parts, collapse = " "),
                wait_shape("standard", chosen, winning, situation$hand_counts)
            )
        }
    }
    if (!length(situation$melds) && seven_pairs(counts)) {
        parts <- "chiitoitsu"
        for (kind in 0:33) if (counts[kind + 1L] > 0L) parts <- c(
            parts,
            paste0(block_notation(c(kind, kind)), if (kind == winning) "*" else "")
        )
        result[[length(result) + 1L]] <- new_candidate(
            "chiitoitsu",
            NULL,
            list(),
            NULL,
            paste(parts, collapse = " "),
            "tanki"
        )
    }
    if (!length(situation$melds) && thirteen_orphans(counts)) {
        parts <- "kokushi"
        for (kind in YAOCHUU) parts <- c(
            parts,
            paste0(block_notation(rep(kind, counts[kind + 1L])), if (kind == winning) "*" else "")
        )
        result[[length(result) + 1L]] <- new_candidate(
            "kokushi",
            NULL,
            list(),
            NULL,
            paste(parts, collapse = " "),
            wait_shape("kokushi", NULL, winning, situation$hand_counts)
        )
    }
    result[order(vapply(result, function(candidate) candidate$form, ""), method = "radix")]
}

block_facts <- function(situation, candidate) {
    triplets <- concealed_sequences <- list()
    sequences <- integer()
    for (block in candidate$sets) {
        if (block[1L] == tail(block, 1L)) {
            triplets[[length(triplets) + 1L]] <- list(
                block = block,
                concealed = situation$by == "tsumo" || !identical(block, candidate$winning_block),
                kan = FALSE
            )
        } else {
            sequences <- c(sequences, block[1L])
            concealed_sequences[[length(concealed_sequences) + 1L]] <- block
        }
    }
    for (meld in situation$melds) {
        if (meld$kind == "C") sequences <- c(
            sequences,
            meld$block[1L]
        ) else triplets[[length(triplets) + 1L]] <- list(
            block = meld$block,
            concealed = meld$kind == "A",
            kan = meld$kind %in% c("K", "A")
        )
    }
    list(triplets = triplets, sequences = sequences, concealed_sequences = concealed_sequences)
}

yakuman_names <- function(situation, candidate, kinds, triplets) {
    names <- intersect(situation$flags, c("tenhou", "chiihou"))
    if (all(vapply(kinds, is_honor, FALSE))) names <- c(names, "tsuuiisou")
    if (all(vapply(kinds, is_terminal, FALSE))) names <- c(names, "chinroutou")
    if (all(kinds %in% GREEN_TILES)) names <- c(names, "ryuuiisou")
    suits <- unique(kinds %/% 9L)
    if (!length(situation$melds) && length(suits) == 1L && !any(vapply(kinds, is_honor, FALSE))) {
        start <- suits[1L] * 9L + 1L
        counts <- situation$all_counts[start:(start + 8L)]
        if (counts[1L] >= 3L && counts[9L] >= 3L && all(counts[2:8] >= 1L)) {
            initial <- situation$hand_counts[start:(start + 8L)]
            names <- c(
                names,
                if (identical(initial, c(3L, 1L, 1L, 1L, 1L, 1L, 1L, 1L, 3L))) "junsei_chuuren" else "chuuren"
            )
        }
    }
    if (candidate$form_type == "kokushi") names <- c(
        names,
        if (candidate$wait == "thirteen") "kokushi_13" else "kokushi"
    )
    if (candidate$form_type == "standard") {
        concealed <- sum(vapply(triplets, function(triplet) triplet$concealed, FALSE))
        triplet_kinds <- unique(vapply(triplets, function(triplet) triplet$block[1L], 0L))
        dragons <- length(intersect(triplet_kinds, 31:33))
        winds <- length(intersect(triplet_kinds, 27:30))
        if (concealed == 4L) names <- c(
            names,
            if (candidate$wait == "tanki") "suuankou_tanki" else "suuankou"
        )
        if (dragons == 3L) names <- c(names, "daisangen")
        if (winds == 4L) names <- c(names, "daisuushii")
        if (winds == 3L && candidate$pair >= 27L && candidate$pair <= 30L) names <- c(names, "shousuushii")
        if (sum(vapply(triplets, function(triplet) triplet$kan, FALSE)) == 4L) names <- c(names, "suukantsu")
    }
    unique(names)
}

ordinary_names <- function(situation, candidate, kinds, facts) {
    names <- intersect(situation$flags, SITUATION_FLAGS[1:7])
    triplets <- facts$triplets
    sequences <- facts$sequences
    concealed_sequences <- facts$concealed_sequences
    if (situation$closed && situation$by == "tsumo") names <- c(names, "menzen_tsumo")
    if (all(!vapply(
        kinds,
        is_yaochuu,
        FALSE
    )) && (situation$closed || situation$rules$open_tanyao)) names <- c(names, "tanyao")
    if (all(vapply(kinds, is_yaochuu, FALSE))) names <- c(names, "honroutou")
    number_suits <- unique(kinds[kinds < 27L] %/% 9L)
    honors <- any(vapply(kinds, is_honor, FALSE))
    if (length(number_suits) == 1L) names <- c(names, if (honors) "honitsu" else "chinitsu")
    if (candidate$form_type == "chiitoitsu") names <- c(names, "chiitoitsu")
    if (candidate$form_type != "standard") return(unique(names))
    pair <- candidate$pair
    yakuhai_pair <- pair >= 31L || pair %in% c(situation$seat_tile, situation$round_tile)
    if (situation$closed && !length(situation$melds) && length(concealed_sequences) == 4L && !yakuhai_pair && candidate$wait == "ryanmen") names <- c(
        names,
        "pinfu"
    )
    repeated <- table(vapply(concealed_sequences, function(block) paste(block, collapse = ","), ""))
    ryanpeikou <- situation$closed && length(concealed_sequences) == 4L && sum(repeated %/% 2L) == 2L
    if (ryanpeikou) names <- c(
        names,
        "ryanpeikou"
    ) else if (situation$closed && any(repeated >= 2L)) names <- c(names, "iipeikou")
    triplet_kinds <- unique(vapply(triplets, function(triplet) triplet$block[1L], 0L))
    for (entry in list(
        list(kind = 31L, name = "haku"),
        list(kind = 32L, name = "hatsu"),
        list(kind = 33L, name = "chun"),
        list(kind = situation$seat_tile, name = "jikaze"),
        list(kind = situation$round_tile, name = "bakaze")
    )) {
        if (entry$kind %in% triplet_kinds) names <- c(names, entry$name)
    }
    if (length(triplets) == 4L) names <- c(names, "toitoi")
    if (sum(vapply(triplets, function(triplet) triplet$concealed, FALSE)) == 3L) names <- c(names, "sanankou")
    if (any(vapply(
        0:6,
        function(start) all((start + (0:2) * 9L) %in% sequences),
        FALSE
    ))) names <- c(names, "sanshoku_doujun")
    if (any(vapply(
        0:8,
        function(number) all((number + (0:2) * 9L) %in% triplet_kinds),
        FALSE
    ))) names <- c(names, "sanshoku_doukou")
    if (any(vapply(
        0:2,
        function(suit) all((suit * 9L + c(0L, 3L, 6L)) %in% sequences),
        FALSE
    ))) names <- c(names, "ittsu")
    blocks <- c(list(c(pair, pair)), candidate$sets, lapply(situation$melds, function(meld) meld$block))
    if (length(sequences) && all(vapply(
        blocks,
        function(block) any(vapply(block, is_yaochuu, FALSE)),
        FALSE
    ))) names <- c(names, if (honors) "chanta" else "junchan")
    if (sum(vapply(triplets, function(triplet) triplet$kan, FALSE)) == 3L) names <- c(names, "sankantsu")
    if (length(intersect(triplet_kinds, 31:33)) == 2L && pair >= 31L) names <- c(names, "shousangen")
    unique(names)
}

evaluate_candidate <- function(situation, candidate) {
    kinds <- which(situation$all_counts > 0L) - 1L
    facts <- block_facts(situation, candidate)
    names <- yakuman_names(situation, candidate, kinds, facts$triplets)
    candidate$yakuman <- ordered_yakuman(names, situation$rules$double_yakuman)
    if (length(candidate$yakuman)) {
        candidate$multiplier <- sum(vapply(candidate$yakuman, function(item) item$value, 0L))
        candidate$base <- 8000L * candidate$multiplier
        candidate$category <- "yakuman"
        return(candidate)
    }
    names <- ordinary_names(situation, candidate, kinds, facts)
    candidate$yaku <- ordered_yaku(names, situation$closed)
    candidate$dora <- sum(vapply(
        situation$dora,
        function(tile) situation$all_counts[next_dora(tile$kind) + 1L],
        0L
    ))
    candidate$ura <- sum(vapply(
        situation$ura,
        function(tile) situation$all_counts[next_dora(tile$kind) + 1L],
        0L
    ))
    candidate$aka <- sum(vapply(situation$all_tiles, function(tile) tile$red, FALSE))
    fu <- fu_breakdown(
        candidate$form_type,
        candidate$pair,
        facts$triplets,
        candidate$wait,
        situation$closed,
        situation$by,
        situation$seat_tile,
        situation$round_tile,
        "pinfu" %in% names
    )
    candidate$fu_items <- fu$items
    candidate$fu_total <- fu$total
    candidate$fu <- fu$fu
    if (length(candidate$yaku)) {
        candidate$han <- sum(vapply(
            candidate$yaku,
            function(item) item$value,
            0L
        )) + candidate$dora + candidate$aka + candidate$ura
        limit <- score_limit(candidate$han, candidate$fu, situation$rules)
        candidate$category <- limit$category
        candidate$base <- limit$base
    }
    candidate
}

evaluate_candidates <- function(situation) lapply(
    make_candidates(situation),
    function(candidate) evaluate_candidate(situation, candidate)
)

best_candidate <- function(candidates) {
    eligible <- Filter(function(candidate) candidate$base >= 1L, candidates)
    if (!length(eligible)) return(NULL)
    index <- order(
        -vapply(eligible, function(candidate) candidate$base, 0L),
        -vapply(eligible, function(candidate) as.integer(length(candidate$yakuman) > 0L), 0L),
        -vapply(eligible, function(candidate) if (length(candidate$yakuman)) 0L else candidate$han, 0L),
        -vapply(eligible, function(candidate) if (length(candidate$yakuman)) 0L else candidate$fu, 0L),
        vapply(eligible, function(candidate) candidate$form, ""),
        method = "radix"
    )[1L]
    eligible[[index]]
}

yaku_names_text <- function(items, separator = ",") paste(
    vapply(items, function(item) item$name, ""),
    collapse = separator
)

candidate_line <- function(candidate) {
    if (length(candidate$yakuman)) {
        evaluation <- sprintf(
            "yakuman %d base %d yaku %s",
            candidate$multiplier,
            candidate$base,
            yaku_names_text(candidate$yakuman)
        )
    } else if (!length(candidate$yaku)) {
        evaluation <- "no_yaku"
    } else {
        evaluation <- sprintf(
            "han %d fu %d base %d yaku %s",
            candidate$han,
            candidate$fu,
            candidate$base,
            yaku_names_text(candidate$yaku)
        )
    }
    sprintf("CANDIDATE %s = %s %s", candidate$form, candidate$wait, evaluation)
}

winning_lines <- function(situation, candidate) {
    lines <- c(paste("FORM", candidate$form), paste("WAIT", candidate$wait))
    if (length(candidate$yakuman)) {
        for (item in candidate$yakuman) lines <- c(lines, paste("YAKUMAN", item$name, item$value))
        lines <- c(lines, sprintf("SCORE yakuman %d base %d", candidate$multiplier, candidate$base))
    } else {
        for (item in candidate$yaku) lines <- c(lines, paste("YAKU", item$name, item$value))
        lines <- c(lines, sprintf("DORA dora %d aka %d ura %d", candidate$dora, candidate$aka, candidate$ura))
        for (item in candidate$fu_items) lines <- c(lines, paste("FU", item$name, item$value))
        lines <- c(
            lines,
            sprintf("FU total %d %d", candidate$fu_total, candidate$fu),
            sprintf(
                "SCORE han %d fu %d limit %s base %d",
                candidate$han,
                candidate$fu,
                candidate$category,
                candidate$base
            )
        )
    }
    payment <- payments(candidate$base, situation$seat == "E", situation$by)
    if (situation$by == "ron") lines <- c(lines, paste("PAY ron", payment$ron)) else if (situation$seat == "E") lines <- c(
        lines,
        paste("PAY tsumo all", payment$nondealer)
    ) else lines <- c(
        lines,
        sprintf("PAY tsumo dealer %d nondealer %d", payment$dealer, payment$nondealer)
    )
    honba <- situation$honba * situation$rules$honba
    sticks <- situation$sticks * 1000L
    gain <- payment$points + honba + sticks
    lines <- c(
        lines,
        sprintf("BONUS honba %d sticks %d", honba, sticks),
        sprintf("TOTAL points %d gain %d", payment$points, gain)
    )
    delta <- setNames(integer(4L), WINDS)
    if (situation$by == "ron") {
        delta[situation$discarder] <- -payment$ron - honba
    } else {
        for (wind in WINDS) {
            if (wind == situation$seat) next
            amount <- if (wind == "E") payment$dealer else payment$nondealer
            delta[wind] <- -amount - honba %/% 3L
        }
    }
    delta[situation$seat] <- gain
    changes <- paste(
        vapply(
            WINDS,
            function(wind) paste(
                wind,
                if (delta[[wind]] > 0L) sprintf("+%d", delta[[wind]]) else as.character(delta[[wind]])
            ),
            ""
        ),
        collapse = " "
    )
    list(lines = c(lines, paste("DELTA", changes)), points = payment$points)
}

score_hands <- function(rules, records) {
    lines <- character()
    summary <- "hand,han,fu,points,yaku"
    stats <- new_counter()
    win_counts <- new_counter()
    wait_counts <- new_counter()
    han_counts <- new_counter()
    fu_counts <- new_counter()
    limit_counts <- new_counter()
    yaku_counts <- new_counter()
    rule_counts <- setNames(lapply(rules, function(rule) new_counter()), names(rules))
    maximum <- 0L
    maximum_hand <- "-"
    for (record in records) {
        label <- record$label
        situation <- parse_situation(label, record$fields, rules)
        add_report(rule_counts[[situation$rule_name]], "hands")
        lines <- c(lines, paste("HAND", label))
        error <- validate_situation(situation)
        if (!is.null(error)) {
            add_report(stats, "errors")
            lines <- c(lines, paste("ERROR", error))
            summary <- c(summary, paste0(label, ",-,-,0,ERROR"))
            next
        }
        waiting <- waiting_tiles(situation$hand_counts, situation$meld_counts, length(situation$melds))
        lines <- c(lines, paste("WAITS", paste(vapply(waiting, tile_name, ""), collapse = " ")))
        evaluated <- evaluate_candidates(situation)
        lines <- c(lines, vapply(evaluated, candidate_line, ""))
        if (situation$by == "ron" && any(vapply(
            situation$discards,
            function(tile) tile$kind %in% waiting,
            FALSE
        ))) {
            add_report(stats, "furiten")
            lines <- c(lines, "RESULT furiten")
            summary <- c(summary, paste0(label, ",-,-,0,FURITEN"))
            next
        }
        best <- best_candidate(evaluated)
        if (is.null(best)) {
            add_report(stats, "no_yaku")
            lines <- c(lines, "RESULT no_yaku")
            summary <- c(summary, paste0(label, ",-,-,0,NO_YAKU"))
            next
        }
        report <- winning_lines(situation, best)
        points <- report$points
        lines <- c(lines, report$lines)
        add_report(stats, "wins")
        add_report(stats, "points", points)
        add_report(rule_counts[[situation$rule_name]], "wins")
        add_report(rule_counts[[situation$rule_name]], "points", points)
        group <- paste0(if (situation$seat == "E") "dealer_" else "nondealer_", situation$by)
        add_report(win_counts, group)
        add_report(wait_counts, best$wait)
        add_report(limit_counts, best$category)
        items <- if (length(best$yakuman)) best$yakuman else best$yaku
        for (item in items) add_report(yaku_counts, item$name)
        if (length(best$yakuman)) {
            han <- paste0("Y", best$multiplier)
            fu <- "-"
        } else {
            han <- as.character(best$han)
            fu <- as.character(best$fu)
            add_report(han_counts, best$han)
            add_report(fu_counts, best$fu)
        }
        summary <- c(summary, sprintf("%s,%s,%s,%d,%s", label, han, fu, points, yaku_names_text(items, ";")))
        if (points > maximum) {
            maximum <- points
            maximum_hand <- label
        }
    }
    lines <- c(
        lines,
        sprintf(
            "STATS hands %d wins %d furiten %d no_yaku %d errors %d",
            length(records),
            report_count(stats, "wins"),
            report_count(stats, "furiten"),
            report_count(stats, "no_yaku"),
            report_count(stats, "errors")
        ),
        paste("WINS", report_pairs(WIN_ORDER, win_counts)),
        paste("WAIT_COUNT", report_pairs(WAIT_ORDER, wait_counts))
    )
    for (han in sort(as.integer(ls(han_counts)))) lines <- c(
        lines,
        paste("HAN_COUNT", han, report_count(han_counts, han))
    )
    for (fu in sort(as.integer(ls(fu_counts)))) lines <- c(
        lines,
        paste("FU_COUNT", fu, report_count(fu_counts, fu))
    )
    for (category in SCORE_CATEGORIES) lines <- c(
        lines,
        paste("LIMIT", category, report_count(limit_counts, category))
    )
    for (name in c(
        vapply(YAKU_TABLE, function(row) row$name, ""),
        vapply(YAKUMAN_TABLE, function(row) row$name, "")
    )) {
        if (report_count(yaku_counts, name) > 0L) lines <- c(
            lines,
            paste("YAKU_COUNT", name, report_count(yaku_counts, name))
        )
    }
    lines <- c(
        lines,
        sprintf("POINTS total %d max %d hand %s", report_count(stats, "points"), maximum, maximum_hand)
    )
    for (name in names(rules)) lines <- c(
        lines,
        paste("RULE", name, report_pairs(c("hands", "wins", "points"), rule_counts[[name]]))
    )
    list(lines = lines, summary = summary)
}

hypothetical <- function(label, fields, winning, method, rules) {
    values <- fields
    values$melds <- "-"
    values$win <- tile_name(winning)
    values$by <- method
    values$from <- if (method == "tsumo") "-" else if (fields$seat == "E") "S" else "E"
    values$flags <- if (fields$riichi == "yes") "riichi" else "-"
    values$ura <- "-"
    values$honba <- values$sticks <- "0"
    prepare_situation(parse_situation(label, values, rules))
}

tenpai_lines <- function(label, fields, waiting, furiten, rules) {
    lines <- character()
    best <- list(ron = NULL, tsumo = NULL)
    for (entry in waiting) {
        kind <- entry[1L]
        remaining <- entry[2L]
        results <- list()
        for (method in c("ron", "tsumo")) {
            if (method == "ron" && furiten) {
                results[[method]] <- "furiten"
                next
            }
            situation <- hypothetical(label, fields, kind, method, rules)
            candidate <- best_candidate(evaluate_candidates(situation))
            if (is.null(candidate)) {
                results[[method]] <- "no_yaku"
                next
            }
            points <- payments(candidate$base, situation$seat == "E", method)$points
            results[[method]] <- as.character(points)
            if (is.null(best[[method]]) || points > best[[method]][2L]) best[[method]] <- c(kind, points)
        }
        lines <- c(
            lines,
            sprintf("WAIT %s left %d ron %s tsumo %s", tile_name(kind), remaining, results$ron, results$tsumo)
        )
    }
    choices <- lapply(
        best,
        function(value) if (is.null(value)) "none" else paste(tile_name(value[1L]), value[2L])
    )
    c(lines, paste("BEST ron", choices$ron, "tsumo", choices$tsumo))
}

analyze_waits <- function(rules, records) {
    lines <- character()
    stats <- new_counter()
    counts <- new_counter()
    for (record in records) {
        label <- record$label
        fields <- record$fields
        lines <- c(lines, paste("HAND", label))
        hand <- parse_tiles(fields$hand)
        dora <- parse_tiles(fields$dora)
        discards <- parse_tiles(fields$discards, allow_empty = TRUE)
        visible <- parse_tiles(fields$visible, allow_empty = TRUE)
        error <- NULL
        if (any(vapply(
            list(hand, dora, discards, visible),
            is.null,
            FALSE
        ))) error <- "bad tile notation" else if (length(hand) != 13L) error <- "wrong tile count" else error <- copy_error(
            c(hand, dora, discards, visible),
            rules[[fields$rules]]
        )
        if (!is.null(error)) {
            add_report(stats, "errors")
            lines <- c(lines, paste("ERROR", error))
            next
        }
        hand_counts <- tile_counts(hand)
        known_counts <- tile_counts(c(hand, dora, discards, visible))
        numbers <- shanten_numbers(hand_counts)
        current <- min(numbers)
        add_report(counts, current)
        lines <- c(
            lines,
            sprintf("SHANTEN standard %d chiitoitsu %d kokushi %d", numbers[1L], numbers[2L], numbers[3L])
        )
        accepted <- list()
        for (kind in 0:33) {
            if (hand_counts[kind + 1L] >= 4L) next
            hand_counts[kind + 1L] <- hand_counts[kind + 1L] + 1L
            advancing <- min(shanten_numbers(hand_counts)) < current
            hand_counts[kind + 1L] <- hand_counts[kind + 1L] - 1L
            if (advancing) accepted[[length(accepted) + 1L]] <- c(kind, 4L - known_counts[kind + 1L])
        }
        total <- sum(vapply(accepted, function(entry) entry[2L], 0L))
        if (current != 0L) {
            suffix <- paste0(
                vapply(accepted, function(entry) paste0(" ", tile_name(entry[1L]), ":", entry[2L]), ""),
                collapse = ""
            )
            lines <- c(lines, sprintf("ACCEPT kinds %d tiles %d%s", length(accepted), total, suffix))
            next
        }
        add_report(stats, "tenpai")
        discarded <- vapply(discards, function(tile) tile$kind, 0L)
        furiten <- any(vapply(accepted, function(entry) entry[1L] %in% discarded, FALSE))
        add_report(stats, "furiten", as.integer(furiten))
        lines <- c(
            lines,
            sprintf(
                "TENPAI kinds %d tiles %d furiten %s",
                length(accepted),
                total,
                if (furiten) "yes" else "no"
            ),
            tenpai_lines(label, fields, accepted, furiten, rules)
        )
    }
    lines <- c(
        lines,
        sprintf(
            "STATS hands %d errors %d tenpai %d furiten %d",
            length(records),
            report_count(stats, "errors"),
            report_count(stats, "tenpai"),
            report_count(stats, "furiten")
        )
    )
    for (number in 0:6) lines <- c(lines, paste("SHANTEN_COUNT", number, report_count(counts, number)))
    lines
}

main <- function() {
    rules <- read_rules()
    scores <- score_hands(rules, read_records("hands.txt"))
    waits <- analyze_waits(rules, read_records("waits.txt"))
    dir.create("output", showWarnings = FALSE)
    writeLines(scores$lines, "output/scores.txt", useBytes = TRUE)
    writeLines(waits, "output/waits.txt", useBytes = TRUE)
    writeLines(scores$summary, "output/summary.csv", useBytes = TRUE)
}

main()
