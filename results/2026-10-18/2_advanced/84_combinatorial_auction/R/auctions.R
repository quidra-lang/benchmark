enumerate_candidates <- function(bids, xor) {
    result <- list()
    if (!length(bids)) return(result)
    for (number in seq_len(bit_at(length(bids)+1L)-1L)) {
        if (xor && mask_size(number) != 1L) next
        bundle <- 0L
        value <- 0
        feasible <- TRUE
        for (i in seq_along(bids)) if (has_item(number, i)) {
            bid <- bids[[i]]
            if (bitwAnd(bundle, bid$bundle) != 0L) {
                feasible <- FALSE
                break
            }
            bundle <- bitwOr(bundle, bid$bundle)
            value <- value+bid$amount
        }
        if (feasible) result[[length(result)+1L]] <- list(number=number, bundle=bundle, value=value)
    }
    result
}
value_of <- function(candidates, items) {
    max(c(
        0,
        vapply(Filter(function(c) bitwAnd(c$bundle, items) == c$bundle, candidates), function(c) c$value, 0)
    ))
}
english_auction <- function(participants, reserve, increment) {
    price <- reserve
    steps <- winner <- 0L
    paid <- 0
    remaining <- which(vapply(participants, function(p) p$value >= price, FALSE))
    while (length(remaining) >= 2L) {
        previous <- remaining
        price <- price+increment
        steps <- steps+1L
        remaining <- which(vapply(participants, function(p) p$value >= price, FALSE))
        if (!length(remaining)) {
            winner <- previous[1]
            paid <- price-increment
            break
        }
    }
    if (winner == 0L && length(remaining)) {
        winner <- remaining[1]
        paid <- price
    }
    drops <- vapply(participants, function(p) {
        drop <- if (p$value < reserve) reserve else reserve+((p$value-reserve) %/% increment+1)*increment
        if (drop <= price) integer_text(drop) else "-"
    }, "")
    list(winner=winner, price=paid, steps=steps, drops=drops)
}
dutch_auction <- function(participants, reserve, start, decrement) {
    price <- start
    steps <- 0L
    while (price >= reserve) {
        eligible <- which(vapply(participants, function(p) p$bid >= price, FALSE))
        if (length(eligible)) {
            winner <- eligible[which.max(vapply(participants[eligible], function(p) p$bid, 0))]
            return(list(winner=winner, price=price, steps=steps))
        }
        price <- price-decrement
        steps <- steps+1L
    }
    list(winner=0L, price=0, steps=steps)
}
