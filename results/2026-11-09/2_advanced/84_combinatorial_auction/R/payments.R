vcg_payments <- function(items, reserves, bids, optimal, bidder_count) {
    details <- vector("list", bidder_count)
    for (k in seq_len(bidder_count)) {
        winning <- Filter(function(b) b$bidder == k, optimal$winning)
        if (!length(winning)) next
        alternative <- solve_wdp(items, reserves, Filter(function(b) b$bidder != k, bids))
        value <- sum(vapply(winning, function(b) b$amount, 0))
        details[[k]] <- list(paid=alternative$welfare-(optimal$welfare-value), alternative=alternative)
    }
    details
}
critical_payments <- function(order, winning, items, reserves) {
    result <- list()
    for (bid in winning) {
        selected <- greedy_select(Filter(function(b) b$number != bid$number, order))
        rivals <- Filter(
            function(b) bitwAnd(b$bundle, bid$bundle) != 0L || (bid$xor && b$bidder == bid$bidder),
            selected
        )
        rival <- if (length(rivals)) rivals[[1]] else NULL
        payment <- sum(reserves[items[vapply(seq_along(items), function(i) has_item(bid$bundle, i), FALSE)]])
        if (!is.null(rival)) {
            threshold <- rival$amount*rival$amount*mask_size(bid$bundle)
            earlier <- function(t) {
                value <- t*t*mask_size(rival$bundle)
                value > threshold || (value == threshold && bid$number < rival$number)
            }
            low <- high <- 1
            while (!earlier(high)) high <- high*2
            while (low < high) {
                middle <- (low+high) %/% 2
                if (earlier(middle)) high <- middle else low <- middle+1
            }
            payment <- max(payment, low)
        }
        result[[as.character(bid$number)]] <- list(paid=payment, rival=rival)
    }
    result
}
coalition_welfares <- function(items, reserves, bids, bidder_count) {
    masks <- 0:(bit_at(bidder_count+1L)-1L)
    positions <- lapply(
        masks,
        function(mask) which(vapply(seq_len(bidder_count), function(i) has_item(mask, i), FALSE))
    )
    keys <- vapply(positions, function(p) paste(sprintf("%02d", p), collapse=""), "")
    masks <- masks[order(lengths(positions), keys, method="radix")]
    result <- list()
    for (mask in masks) {
        search <- solve_wdp(items, reserves, Filter(function(b) has_item(mask, b$bidder), bids))
        result[[length(result)+1L]] <- list(
            mask=mask,
            members=which(vapply(seq_len(bidder_count), function(i) has_item(mask, i), FALSE)),
            welfare=search$welfare,
            numbers=search$numbers
        )
    }
    result
}
blocking_coalitions <- function(coalitions, seller, utilities) {
    blocking <- minimal <- list()
    for (coalition in coalitions) {
        payoff <- seller+sum(utilities[coalition$members])
        if (coalition$welfare > payoff) {
            record <- list(coalition=coalition, payoff=payoff, deficit=coalition$welfare-payoff)
            if (!any(vapply(
                blocking,
                function(previous) bitwAnd(
                    previous$coalition$mask,
                    coalition$mask
                ) == previous$coalition$mask,
                FALSE
            ))) minimal[[length(minimal)+1L]] <- record
            blocking[[length(blocking)+1L]] <- record
        }
    }
    list(blocking=blocking, minimal=minimal)
}
gsp_price <- function(ranking, rank) if (rank < length(ranking)) ranking[[rank+1L]]$bid else 0
slot_vcg_payment <- function(ranking, rates, rank) {
    payment <- rat(0)
    end <- min(length(ranking), length(rates)+1L)
    if (rank < end) for (following in seq.int(rank+1L, end)) {
        next_rate <- if (following <= length(rates)) rates[[following]] else rat(0)
        payment <- radd(
            payment,
            rmul(rat(ranking[[following]]$value), rsub(rates[[following-1L]], next_rate))
        )
    }
    payment
}
