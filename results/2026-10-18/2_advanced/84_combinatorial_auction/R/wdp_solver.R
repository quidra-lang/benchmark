bit_at <- function(index) bitwShiftL(1L, index-1L)
has_item <- function(mask, index) bitwAnd(mask, bit_at(index)) != 0L
mask_size <- function(mask) sum(as.integer(intToBits(as.integer(mask)))[seq_len(20L)])
lex_less <- function(a, b) {
    for (i in seq_len(min(length(a), length(b)))) if (a[i] != b[i]) return(a[i] < b[i])
    length(a) < length(b)
}
bid_shares <- function(items, reserves, bids, decided=0L) {
    result <- list()
    for (i in seq_along(items)) {
        if (has_item(decided, i)) next
        share <- rat(reserves[[items[i]]])
        source <- 0L
        for (bid in bids) if (has_item(bid$bundle, i)) {
            candidate <- rat(bid$amount, mask_size(bid$bundle))
            if (rcmp(candidate, share) > 0) {
                share <- candidate
                source <- bid$number
            }
        }
        result[[length(result)+1L]] <- list(item=items[i], share=share, source=source)
    }
    result
}
solve_wdp <- function(items, reserves, bids) {
    ordered <- bids[order(vapply(bids, function(b) b$number, 0))]
    shares <- bid_shares(items, reserves, ordered)
    root_bound <- rat(0)
    for (entry in shares) root_bound <- radd(root_bound, entry$share)
    nodes <- pruned <- leaves <- 0L
    best_welfare <- NULL
    best_numbers <- integer()
    improvements <- list()
    complete <- bit_at(length(items)+1L)-1L
    visit <- function(decided, used, welfare, chosen) {
        nodes <<- nodes+1L
        if (decided == complete) {
            leaves <<- leaves+1L
            numbers <- sort(vapply(chosen, function(b) b$number, 0))
            if (is.null(best_welfare) || welfare > best_welfare || (welfare == best_welfare && lex_less(
                numbers,
                best_numbers
            ))) {
                best_welfare <<- welfare
                best_numbers <<- numbers
                improvements[[length(improvements)+1L]] <<- list(
                    nodes=nodes,
                    welfare=welfare,
                    numbers=numbers
                )
            }
            return(invisible(NULL))
        }
        usable <- Filter(
            function(b) bitwAnd(b$bundle, decided) == 0L && !(b$xor && has_item(used, b$bidder)),
            ordered
        )
        bound <- rat(welfare)
        for (entry in bid_shares(items, reserves, usable, decided)) bound <- radd(bound, entry$share)
        if (!is.null(best_welfare) && rcmp(bound, rat(best_welfare)) < 0) {
            pruned <<- pruned+1L
            return(invisible(NULL))
        }
        first_item <- which(!vapply(seq_along(items), function(i) has_item(decided, i), FALSE))[1]
        for (bid in usable) if (has_item(bid$bundle, first_item)) {
            next_used <- if (bid$xor) bitwOr(used, bit_at(bid$bidder)) else used
            visit(bitwOr(decided, bid$bundle), next_used, welfare+bid$amount, c(chosen, list(bid)))
        }
        visit(bitwOr(decided, bit_at(first_item)), used, welfare+reserves[[items[first_item]]], chosen)
    }
    visit(0L, 0L, 0, list())
    list(welfare=best_welfare, numbers=best_numbers, winning=Filter(function(b) b$number %in% best_numbers, ordered),
         nodes=nodes, pruned=pruned, leaves=leaves, improvements=improvements, shares=shares, bound=root_bound)
}
greedy_order <- function(bids) {
    result <- list()
    earlier <- function(a, b) {
        left <- a$amount*a$amount*mask_size(b$bundle)
        right <- b$amount*b$amount*mask_size(a$bundle)
        if (left == right) a$number < b$number else left > right
    }
    for (bid in bids) {
        position <- 1L
        while (position <= length(result) && !earlier(bid, result[[position]])) position <- position+1L
        result <- append(result, list(bid), after=position-1L)
    }
    result
}
greedy_select <- function(bids) {
    occupied <- used <- 0L
    chosen <- list()
    for (bid in bids) {
        if (bitwAnd(bid$bundle, occupied) != 0L || (bid$xor && has_item(used, bid$bidder))) next
        chosen[[length(chosen)+1L]] <- bid
        occupied <- bitwOr(occupied, bid$bundle)
        if (bid$xor) used <- bitwOr(used, bit_at(bid$bidder))
    }
    chosen
}
