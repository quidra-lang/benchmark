triplet_fu <- function(kinds, concealed, kan) {
    if (kan) {
        kind <- if (concealed) "closed_kan" else "open_kan"
        value <- if (concealed) 16L else 8L
    } else {
        kind <- if (concealed) "closed_triplet" else "open_triplet"
        value <- if (concealed) 4L else 2L
    }
    list(name = paste(kind, block_notation(kinds)), value = value * (if (is_yaochuu(kinds[1L])) 2L else 1L))
}

fu_breakdown <- function(form, pair, triplets, wait, closed, method, seat, round_wind, pinfu) {
    if (form == "chiitoitsu") return(list(
        items = list(list(name = "chiitoitsu", value = 25L)),
        total = 25L,
        fu = 25L
    ))
    items <- list(list(name = "base", value = 20L))
    if (closed && method == "ron") items <- c(items, list(list(name = "closed_ron", value = 10L)))
    if (method == "tsumo" && !pinfu) items <- c(items, list(list(name = "tsumo", value = 2L)))
    pair_value <- 2L * sum(pair >= 31L, pair == seat, pair == round_wind)
    if (pair_value > 0L) items <- c(
        items,
        list(list(name = paste("pair", block_notation(c(pair, pair))), value = pair_value))
    )
    for (triplet in triplets) items <- c(
        items,
        list(triplet_fu(triplet$block, triplet$concealed, triplet$kan))
    )
    if (wait %in% c("kanchan", "penchan", "tanki")) items <- c(
        items,
        list(list(name = paste("wait", wait), value = 2L))
    )
    total <- sum(vapply(items, function(item) item$value, 0L))
    if (!closed && total == 20L) {
        items <- c(items, list(list(name = "open_pinfu", value = 10L)))
        total <- total + 10L
    }
    list(items = items, total = total, fu = ((total + 9L) %/% 10L) * 10L)
}

score_limit <- function(han, fu, rules) {
    if (han >= 13L && rules$kazoe_yakuman) return(list(category = "kazoe_yakuman", base = 8000L))
    if (han >= 11L) return(list(category = "sanbaiman", base = 6000L))
    if (han >= 8L) return(list(category = "baiman", base = 4000L))
    if (han >= 6L) return(list(category = "haneman", base = 3000L))
    base <- as.integer(fu * 2^(han + 2L))
    if (han == 5L || base >= 2000L || (rules$kiriage && base == 1920L)) return(list(
        category = "mangan",
        base = 2000L
    ))
    list(category = "none", base = base)
}

round_hundred <- function(value) ((value + 99L) %/% 100L) * 100L
payments <- function(base, dealer, method) {
    if (method == "ron") {
        ron <- round_hundred(base * (if (dealer) 6L else 4L))
        return(list(ron = ron, dealer = 0L, nondealer = 0L, points = ron))
    }
    if (dealer) {
        nondealer <- round_hundred(base * 2L)
        return(list(ron = 0L, dealer = 0L, nondealer = nondealer, points = nondealer * 3L))
    }
    dealer_payment <- round_hundred(base * 2L)
    nondealer <- round_hundred(base)
    list(ron = 0L, dealer = dealer_payment, nondealer = nondealer, points = dealer_payment + 2L * nondealer)
}
