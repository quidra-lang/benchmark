source("bids_io.R")
source("wdp_solver.R")
source("payments.R")
source("auctions.R")
source("report.R")
line <- function(...) {
    parts <- lapply(list(...), function(part) if (is.numeric(part)) integer_text(part) else as.character(part))
    paste(unlist(parts), collapse=" ")
}
MECHANISMS <- c("vcg", "pay_as_bid", "greedy", "critical", "saa")
OUTCOMES <- c("vcg", "greedy", "critical", "saa")
FORMATS <- c("first_price", "second_price", "english", "dutch", "all_pay")
allocation <- function(bids, items, reserves) {
    winning <- bids[order(vapply(bids, function(b) b$number, 0))]
    owners <- integer(length(items))
    for (bid in winning) for (i in seq_along(items)) if (has_item(bid$bundle, i)) owners[i] <- bid$bidder
    unsold <- items[owners == 0L]
    accepted <- sum(vapply(winning, function(b) b$amount, 0))
    retained <- sum(reserves[unsold])
    list(
        winning=winning,
        owners=owners,
        unsold=unsold,
        accepted=accepted,
        retained=retained,
        welfare=accepted+retained
    )
}
validate_bids <- function(raw, reserves, parameters) {
    bidders <- valid <- eligible <- below <- rejected <- list()
    seen <- character()
    bid_count <- 0L
    for (entry in raw$lines) {
        error <- if (entry$name %in% seen) "duplicate bidder" else if (!entry$language %in% c("XOR", "OR")) paste(
            "bad language",
            entry$language
        ) else ""
        seen <- c(seen, entry$name)
        bidder <- NULL
        if (!nzchar(error)) {
            bidder <- list(name=entry$name, language=entry$language, valid=list(), eligible=list())
            bidders[[length(bidders)+1L]] <- bidder
        }
        for (text in entry$texts) {
            bid_count <- bid_count+1L
            reason <- error
            mask <- 0L
            amount <- 0
            if (!nzchar(reason)) {
                if (!grepl("^[a-z]+(\\+[a-z]+)*:(0|[1-9][0-9]{0,4})$", text)) {
                    reason <- "malformed bid"
                } else {
                    parts <- strsplit(text, ":", fixed=TRUE)[[1]]
                    item_names <- strsplit(parts[1], "+", fixed=TRUE)[[1]]
                    for (name in item_names) {
                        if (!name %in% names(reserves)) {
                            reason <- paste("unknown item", name)
                        } else if (!name %in% raw$items) {
                            reason <- paste("item not offered", name)
                        } else {
                            index <- match(name, raw$items)
                            if (has_item(mask, index)) reason <- paste(
                                "duplicate item",
                                name
                            ) else mask <- bitwOr(mask, bit_at(index))
                        }
                        if (nzchar(reason)) break
                    }
                    if (!nzchar(reason)) {
                        amount <- as.numeric(parts[2])
                        duplicates <- which(vapply(bidder$valid, function(b) b$bundle == mask, FALSE))
                        if (length(item_names) > parameters$max_bundle_size) {
                            reason <- "bundle too large"
                        } else if (amount == 0) {
                            reason <- "zero value"
                        } else if (length(duplicates)) {
                            reason <- paste("duplicate bundle", bidder$valid[[duplicates[1]]]$number)
                        } else if (length(bidder$valid) >= parameters$max_bids_per_bidder) {
                            reason <- "too many bids"
                        }
                    }
                }
            }
            if (nzchar(reason)) {
                rejected[[length(rejected)+1L]] <- list(number=bid_count, name=entry$name, reason=reason)
                next
            }
            bid <- new_bid(bid_count, length(bidders), mask, amount, entry$language == "XOR")
            valid[[length(valid)+1L]] <- bid
            bidder$valid[[length(bidder$valid)+1L]] <- bid
            reserve <- sum(reserves[raw$items[vapply(
                seq_along(raw$items),
                function(i) has_item(mask, i),
                FALSE
            )]])
            if (amount >= reserve) {
                eligible[[length(eligible)+1L]] <- bid
                bidder$eligible[[length(bidder$eligible)+1L]] <- bid
            } else {
                below[[length(below)+1L]] <- list(bid=bid, reserve=reserve)
            }
        }
        if (!nzchar(error)) bidders[[length(bidders)]] <- bidder
    }
    list(bidders=bidders, valid=valid, eligible=eligible, below=below, rejected=rejected, bid_count=bid_count)
}
ascending_auction <- function(a, reserves, parameters) {
    items <- a$items
    bidder_names <- a$names
    n <- length(bidder_names)
    choices <- lapply(a$bidders, function(b) enumerate_candidates(b$valid, b$language == "XOR"))
    eligibility <- vapply(
        choices,
        function(options) max(c(0, vapply(options, function(c) mask_size(c$bundle), 0))),
        0
    )
    prices <- unname(reserves[items])
    holders <- bid_counts <- bid_rounds <- last_rounds <- integer(length(items))
    state <- parameters$seed
    increment <- parameters$saa_increment
    lines <- line("AUCTION", a$name, "increment", increment)
    final_round <- 0L
    reason <- "cap"
    for (r in seq_len(parameters$round_cap)) {
        final_round <- r
        activities <- new_by_bidder <- integer(n)
        new_by_item <- rep(list(integer()), length(items))
        for (k in seq_len(n)) {
            held <- sum(vapply(which(holders == k), bit_at, 0L))
            chosen <- 0L
            best_surplus <- 0
            for (candidate in choices[[k]]) {
                if (mask_size(bitwOr(candidate$bundle, held)) > eligibility[k]) next
                indices <- which(vapply(seq_along(items), function(i) has_item(candidate$bundle, i), FALSE))
                asking <- sum(prices[indices]+ifelse(
                    holders[indices] != 0L & holders[indices] != k,
                    increment,
                    0
                ))
                surplus <- candidate$value-asking
                if (surplus > best_surplus) {
                    chosen <- candidate$bundle
                    best_surplus <- surplus
                }
            }
            activities[k] <- mask_size(bitwOr(chosen, held))
            new_by_bidder[k] <- bitwAnd(chosen, bitwNot(held))
            for (i in seq_along(items)) if (has_item(new_by_bidder[k], i)) new_by_item[[i]] <- c(
                new_by_item[[i]],
                k
            )
        }
        demand <- sum(vapply(new_by_bidder, mask_size, 0))
        if (demand > 0) {
            active <- which(new_by_bidder != 0L)
            suffix <- vapply(
                active,
                function(k) paste0(bidder_names[k], ":", bundle_text(new_by_bidder[k], items)),
                ""
            )
            lines <- c(lines, line("ROUND", r, "demand", demand, suffix))
            for (i in seq_along(items)) {
                new_bidders <- new_by_item[[i]]
                if (!length(new_bidders)) next
                winner <- new_bidders[1]
                if (length(new_bidders) >= 2L) {
                    state <- (48271*state) %% 2147483647
                    winner <- new_bidders[state %% length(new_bidders)+1L]
                }
                if (holders[i] != 0L) prices[i] <- prices[i]+increment
                holders[i] <- winner
                bid_counts[i] <- bid_counts[i]+length(new_bidders)
                bid_rounds[i] <- bid_rounds[i]+1L
                last_rounds[i] <- r
            }
            standing <- vapply(
                seq_along(items),
                function(i) paste0(
                    items[i],
                    "=",
                    integer_text(prices[i]),
                    "@",
                    if (holders[i] == 0L) "-" else bidder_names[holders[i]]
                ),
                ""
            )
            lines <- c(lines, line("STANDING", standing))
        } else {
            lines <- c(lines, line("ROUND", r, "none"))
        }
        changed <- character()
        for (k in seq_len(n)) if (activities[k] < eligibility[k]) {
            eligibility[k] <- activities[k]
            changed <- c(changed, paste0(bidder_names[k], "=", eligibility[k]))
        }
        if (length(changed)) lines <- c(lines, line("ELIGIBILITY", changed))
        if (demand == 0) {
            reason <- "quiet"
            break
        }
    }
    lines <- c(lines, line("END rounds", final_round, reason))
    for (i in seq_along(items)) {
        if (holders[i] == 0L) {
            lines <- c(lines, line("ITEM", items[i], "unsold reserve", reserves[[items[i]]]))
        } else {
            lines <- c(
                lines,
                line(
                    "ITEM",
                    items[i],
                    "price",
                    prices[i],
                    "holder",
                    bidder_names[holders[i]],
                    "bids",
                    bid_counts[i],
                    "rounds",
                    bid_rounds[i],
                    "last",
                    last_rounds[i]
                )
            )
        }
    }
    payments <- utilities <- numeric(n)
    values_total <- exposure <- exposed <- 0
    for (k in seq_len(n)) {
        won <- sum(vapply(which(holders == k), bit_at, 0L))
        payments[k] <- sum(prices[holders == k])
        value <- value_of(choices[[k]], won)
        utilities[k] <- value-payments[k]
        values_total <- values_total+value
        if (utilities[k] < 0) {
            exposure <- exposure-utilities[k]
            exposed <- exposed+1L
        }
        text <- line(
            "BIDDER",
            bidder_names[k],
            "won",
            bundle_text(won, items),
            "paid",
            payments[k],
            "value",
            value,
            "utility",
            utilities[k],
            "eligibility",
            eligibility[k]
        )
        lines <- c(lines, paste0(text, if (utilities[k] < 0) " exposed" else ""))
    }
    revenue <- sum(payments)
    retained <- sum(reserves[items[holders == 0L]])
    welfare <- values_total+retained
    lines <- c(
        lines,
        line(
            "TOTAL revenue",
            revenue,
            "welfare",
            welfare,
            "efficiency",
            fraction(rat(welfare, a$exact$welfare)),
            "exposure",
            exposure,
            "exposed",
            exposed
        )
    )
    list(
        lines=lines,
        payments=payments,
        utilities=utilities,
        revenue=revenue,
        retained=retained,
        welfare=welfare,
        rounds=final_round,
        reason=reason,
        exposure=exposure,
        exposed=exposed
    )
}
prepare_auction <- function(raw, reserves, parameters) {
    a <- validate_bids(raw, reserves, parameters)
    a$name <- raw$name
    a$items <- raw$items
    a$names <- vapply(a$bidders, function(b) b$name, "")
    n <- length(a$names)
    a$optimal <- solve_wdp(a$items, reserves, a$eligible)
    a$exact <- allocation(a$optimal$winning, a$items, reserves)
    a$order <- greedy_order(a$eligible)
    a$greedy <- allocation(greedy_select(a$order), a$items, reserves)
    a$critical <- critical_payments(a$order, a$greedy$winning, a$items, reserves)
    a$details <- vcg_payments(a$items, reserves, a$eligible, a$optimal, n)
    a$values <- vapply(
        seq_len(n),
        function(k) sum(vapply(Filter(function(b) b$bidder == k, a$exact$winning), function(b) b$amount, 0)),
        0
    )
    a$greedy_values <- vapply(
        seq_len(n),
        function(k) sum(vapply(Filter(function(b) b$bidder == k, a$greedy$winning), function(b) b$amount, 0)),
        0
    )
    a$paid <- vapply(a$details, function(d) if (is.null(d)) 0 else d$paid, 0)
    a$critical_paid <- vapply(
        seq_len(n),
        function(k) sum(vapply(
            Filter(function(b) b$bidder == k, a$greedy$winning),
            function(b) a$critical[[as.character(b$number)]]$paid,
            0
        )),
        0
    )
    a$utilities <- a$values-a$paid
    a$critical_utilities <- a$greedy_values-a$critical_paid
    a$revenue <- sum(a$paid)
    a$critical_revenue <- sum(a$critical_paid)
    a$saa <- ascending_auction(a, reserves, parameters)
    a
}
wdp_lines <- function(a, reserves) {
    lines <- line(
        "AUCTION",
        a$name,
        "items",
        length(a$items),
        "bidders",
        length(a$names),
        "bids",
        a$bid_count,
        "valid",
        length(a$valid),
        "eligible",
        length(a$eligible)
    )
    for (bidder in a$bidders) lines <- c(
        lines,
        line(
            "BIDDER",
            bidder$name,
            bidder$language,
            "valid",
            length(bidder$valid),
            "eligible",
            length(bidder$eligible)
        )
    )
    for (r in a$rejected) lines <- c(lines, line("REJECT", r$number, r$name, r$reason))
    for (r in a$below) lines <- c(
        lines,
        line(
            "BELOW_RESERVE",
            r$bid$number,
            a$names[r$bid$bidder],
            "value",
            r$bid$amount,
            "reserve",
            r$reserve
        )
    )
    for (s in a$optimal$shares) lines <- c(
        lines,
        line("SHARE", s$item, fraction(s$share), if (s$source == 0L) "reserve" else line("bid", s$source))
    )
    lines <- c(lines, line("ROOT_BOUND", fraction(a$optimal$bound)))
    for (r in a$optimal$improvements) lines <- c(
        lines,
        line("IMPROVE", r$nodes, "welfare", r$welfare, "bids", number_text(r$numbers))
    )
    e <- a$exact
    g <- a$greedy
    lines <- c(
        lines,
        line(
            "OPTIMAL welfare",
            e$welfare,
            "accepted",
            e$accepted,
            "retained",
            e$retained,
            "winners",
            length(e$winning)
        )
    )
    for (b in e$winning) lines <- c(
        lines,
        line("WIN", b$number, a$names[b$bidder], bundle_text(b$bundle, a$items), b$amount)
    )
    lines <- c(lines, line("UNSOLD", if (length(e$unsold)) paste(e$unsold, collapse=" ") else "-"))
    lines <- c(
        lines,
        line(
            "SEARCH nodes",
            a$optimal$nodes,
            "pruned",
            a$optimal$pruned,
            "leaves",
            a$optimal$leaves,
            "improvements",
            length(a$optimal$improvements)
        )
    )
    lines <- c(
        lines,
        line(
            "GREEDY_ORDER",
            if (length(a$order)) paste(vapply(a$order, function(b) b$number, 0), collapse=" ") else "-"
        )
    )
    lines <- c(
        lines,
        line(
            "GREEDY welfare",
            g$welfare,
            "accepted",
            g$accepted,
            "retained",
            g$retained,
            "winners",
            length(g$winning),
            "efficiency",
            fraction(rat(g$welfare, e$welfare))
        )
    )
    for (b in g$winning) {
        critical <- a$critical[[as.character(b$number)]]
        lines <- c(
            lines,
            line(
                "GWIN",
                b$number,
                a$names[b$bidder],
                bundle_text(b$bundle, a$items),
                b$amount,
                "critical",
                critical$paid,
                "against",
                if (is.null(critical$rival)) "-" else as.character(critical$rival$number)
            )
        )
    }
    lines <- c(lines, line("GUNSOLD", if (length(g$unsold)) paste(g$unsold, collapse=" ") else "-"))
    for (i in seq_along(a$items)) {
        lines <- c(lines, line("ITEM", a$items[i], "reserve", reserves[[a$items[i]]], "demand", sum(vapply(a$eligible, function(b) has_item(b$bundle, i), FALSE)),
                              "optimal", if (e$owners[i] == 0L) "-" else a$names[e$owners[i]], "greedy", if (g$owners[i] == 0L) "-" else a$names[g$owners[i]]))
    }
    lines
}
vcg_lines <- function(a) {
    lines <- line("AUCTION", a$name, "welfare", a$exact$welfare)
    for (k in seq_along(a$names)) {
        if (is.null(a$details[[k]])) {
            lines <- c(lines, line("BIDDER", a$names[k], "lost"))
        } else {
            alternate <- a$details[[k]]$alternative
            won <- vapply(Filter(function(b) b$bidder == k, a$exact$winning), function(b) b$number, 0)
            lines <- c(lines, line("BIDDER", a$names[k], "won", number_text(won), "value", a$values[k], "without", alternate$welfare,
                                  "alternative", number_text(alternate$numbers), "payment", a$paid[k], "utility", a$utilities[k]))
        }
    }
    lines <- c(
        lines,
        line(
            "TOTAL revenue",
            a$revenue,
            "pay_as_bid",
            a$exact$accepted,
            "retained",
            a$exact$retained,
            "seller",
            a$revenue+a$exact$retained,
            "bidders",
            sum(a$utilities)
        )
    )
    for (k in seq_along(a$names)) lines <- c(
        lines,
        line(
            "PAYMENTS",
            a$names[k],
            "vcg",
            a$paid[k],
            "pay_as_bid",
            a$values[k],
            "greedy",
            a$greedy_values[k],
            "critical",
            a$critical_paid[k],
            "saa",
            a$saa$payments[k]
        )
    )
    for (k in seq_along(a$names)) lines <- c(
        lines,
        line(
            "UTILITIES",
            a$names[k],
            "vcg",
            a$utilities[k],
            "critical",
            a$critical_utilities[k],
            "saa",
            a$saa$utilities[k]
        )
    )
    lines
}
core_lines <- function(a, reserves, parameters) {
    lines <- line("AUCTION", a$name, "bidders", length(a$names))
    counts <- setNames(numeric(6L), c("checked", "skipped", OUTCOMES))
    if (length(a$names) > parameters$core_max_bidders) {
        counts["skipped"] <- 1
        return(list(lines=c(lines, "SKIPPED"), counts=counts))
    }
    counts["checked"] <- 1
    coalitions <- coalition_welfares(a$items, reserves, a$eligible, length(a$names))
    lines <- c(lines, line("COALITIONS", length(coalitions)))
    outcomes <- list(list(seller=a$revenue+a$exact$retained, utilities=a$utilities), list(seller=a$greedy$welfare, utilities=numeric(length(a$names))),
                     list(
                         seller=a$critical_revenue+a$greedy$retained,
                         utilities=a$critical_utilities
                     ), list(seller=a$saa$revenue+a$saa$retained, utilities=a$saa$utilities))
    member_text <- function(coalition) if (length(coalition$members)) paste(
        a$names[coalition$members],
        collapse="+"
    ) else "-"
    for (i in seq_along(OUTCOMES)) {
        name <- OUTCOMES[i]
        outcome <- outcomes[[i]]
        lines <- c(lines, line("OUTCOME", name, "seller", outcome$seller, "utilities", outcome$utilities))
        result <- blocking_coalitions(coalitions, outcome$seller, outcome$utilities)
        for (r in result$minimal) {
            coalition <- r$coalition
            lines <- c(
                lines,
                line(
                    "BLOCK",
                    member_text(coalition),
                    "welfare",
                    coalition$welfare,
                    "payoff",
                    r$payoff,
                    "deficit",
                    r$deficit,
                    "bids",
                    number_text(coalition$numbers)
                )
            )
        }
        if (!length(result$blocking)) {
            lines <- c(lines, "RESULT core")
            counts[name] <- counts[name]+1
        } else {
            worst <- result$blocking[[which.max(vapply(result$blocking, function(r) r$deficit, 0))]]
            lines <- c(
                lines,
                line(
                    "RESULT blocked",
                    length(result$blocking),
                    "minimal",
                    length(result$minimal),
                    "max_deficit",
                    worst$deficit,
                    "by",
                    member_text(worst$coalition)
                )
            )
        }
    }
    list(lines=lines, counts=counts)
}
duplicate_name <- function(participants) {
    seen <- character()
    for (p in participants) {
        if (p$name %in% seen) return(p$name)
        seen <- c(seen, p$name)
    }
    ""
}
lot_lines <- function(group, parameters) {
    p <- group$participants
    reserve <- as.numeric(group$arguments[1])
    eligible <- which(vapply(p, function(b) b$bid >= reserve, FALSE))
    first_winner <- if (length(eligible)) eligible[which.max(vapply(
        p[eligible],
        function(b) b$bid,
        0
    ))] else 0L
    efficient <- which.max(vapply(p, function(b) b$value, 0))
    optimum <- max(reserve, p[[efficient]]$value)
    if (p[[efficient]]$value < reserve) efficient <- 0L
    lines <- line(
        "LOT",
        group$name,
        "reserve",
        reserve,
        "bidders",
        length(p),
        "efficient",
        if (efficient == 0L) "-" else p[[efficient]]$name,
        "optimum",
        optimum
    )
    first_price <- if (first_winner == 0L) 0 else p[[first_winner]]$bid
    others <- which(vapply(seq_along(p), function(i) i != efficient && p[[i]]$value >= reserve, FALSE))
    second_price <- if (efficient == 0L) 0 else max(c(reserve, vapply(p[others], function(b) b$value, 0)))
    english <- english_auction(p, reserve, parameters$english_increment)
    dutch <- dutch_auction(p, reserve, parameters$dutch_start, parameters$dutch_decrement)
    mechanisms <- list(c(first_winner, first_price), c(efficient, second_price), c(english$winner, english$price, english$steps),
                       c(dutch$winner, dutch$price, dutch$steps), c(first_winner, first_price))
    results <- list()
    summary <- character()
    for (i in seq_along(FORMATS)) {
        name <- FORMATS[i]
        winner <- mechanisms[[i]][1]
        price <- mechanisms[[i]][2]
        utilities <- numeric(length(p))
        revenue <- price
        if (name == "all_pay") {
            revenue <- sum(vapply(p[eligible], function(b) b$bid, 0))
            for (index in eligible) utilities[index] <- -p[[index]]$bid
        }
        welfare <- if (winner == 0L) reserve else p[[winner]]$value
        if (winner == 0L) {
            text <- paste(toupper(name), "unsold")
        } else {
            utilities[winner] <- p[[winner]]$value-price
            text <- line(
                toupper(name),
                "winner",
                p[[winner]]$name,
                "price",
                price,
                "utility",
                utilities[winner]
            )
        }
        if (length(mechanisms[[i]]) == 3L) text <- paste(text, "steps", mechanisms[[i]][3])
        efficiency <- rat(welfare, optimum)
        lines <- c(
            lines,
            line(text, "revenue", revenue, "welfare", welfare, "efficiency", fraction(efficiency))
        )
        if (name == "english") lines <- c(
            lines,
            line(
                "ENGLISH_DROPS",
                vapply(seq_along(p), function(j) paste0(p[[j]]$name, "=", english$drops[j]), "")
            )
        )
        results[[i]] <- list(name=name, utilities=utilities, revenue=revenue)
        summary <- c(
            summary,
            paste0(
                group$name,
                "/",
                name,
                ",",
                integer_text(revenue),
                ",",
                integer_text(welfare),
                ",",
                fraction(efficiency)
            )
        )
    }
    for (i in seq_along(p)) lines <- c(
        lines,
        line("UTILITY", p[[i]]$name, vapply(results, function(r) r$utilities[i], 0))
    )
    ranking <- order(-vapply(results, function(r) r$revenue, 0), seq_along(results))
    lines <- c(lines, line("RANKING", vapply(results[ranking], function(r) r$name, "")))
    list(lines=lines, summary=summary)
}
slots_lines <- function(group, rates) {
    p <- group$participants
    by_bid <- p[order(-vapply(p, function(p) p$bid, 0), seq_along(p))]
    by_value <- p[order(-vapply(p, function(p) p$value, 0), seq_along(p))]
    n <- length(p)
    k <- length(rates)
    lines <- line("SLOTS", group$name, "slots", k, "advertisers", n)
    gsp_revenue <- gsp_welfare <- vcg_revenue <- optimum <- rat(0)
    for (s in seq_len(min(n,k))) {
        bidder <- by_bid[[s]]
        rate <- rates[[s]]
        price <- gsp_price(by_bid, s)
        payment <- rmul(rate, rat(price))
        utility <- rmul(rate, rat(bidder$value-price))
        gsp_revenue <- radd(gsp_revenue, payment)
        gsp_welfare <- radd(gsp_welfare, rmul(rate, rat(bidder$value)))
        optimum <- radd(optimum, rmul(rate, rat(by_value[[s]]$value)))
        lines <- c(
            lines,
            line(
                "GSP",
                s,
                bidder$name,
                "ctr",
                fraction(rate),
                "bid",
                bidder$bid,
                "price",
                price,
                "payment",
                fraction(payment),
                "utility",
                fraction(utility)
            )
        )
    }
    efficiency <- rdiv(gsp_welfare, optimum)
    lines <- c(
        lines,
        line(
            "GSP_TOTAL revenue",
            fraction(gsp_revenue),
            "welfare",
            fraction(gsp_welfare),
            "efficiency",
            fraction(efficiency)
        )
    )
    for (s in seq_len(min(n,k))) {
        bidder <- by_value[[s]]
        rate <- rates[[s]]
        payment <- slot_vcg_payment(by_value, rates, s)
        vcg_revenue <- radd(vcg_revenue, payment)
        utility <- rsub(rmul(rate, rat(bidder$value)), payment)
        lines <- c(
            lines,
            line(
                "VCG",
                s,
                bidder$name,
                "ctr",
                fraction(rate),
                "value",
                bidder$value,
                "payment",
                fraction(payment),
                "price",
                fraction(rdiv(payment,rate)),
                "utility",
                fraction(utility)
            )
        )
    }
    lines <- c(
        lines,
        line("VCG_TOTAL revenue", fraction(vcg_revenue), "welfare", fraction(optimum), "efficiency 1")
    )
    violations <- deviations <- 0L
    if (min(n,k+1L) >= 2L) for (s in seq.int(2L,min(n,k+1L))) {
        bidder <- by_bid[[s]]
        rate <- if (s <= k) rates[[s]] else rat(0)
        stay <- rmul(rate, rat(bidder$value-gsp_price(by_bid,s)))
        swap <- rmul(rates[[s-1L]], rat(bidder$value-bidder$bid))
        violated <- rcmp(stay,swap) < 0
        violations <- violations+violated
        lines <- c(
            lines,
            line(
                "ENVY",
                s,
                bidder$name,
                "stay",
                fraction(stay),
                "swap",
                fraction(swap),
                if (violated) "violated" else "ok"
            )
        )
    }
    lines <- c(lines, if (violations == 0L) "ENVY_FREE yes" else line("ENVY_FREE no violations", violations))
    for (s in seq_len(n)) {
        bidder <- by_bid[[s]]
        rate <- if (s <= k) rates[[s]] else rat(0)
        current <- rmul(rate, rat(bidder$value-gsp_price(by_bid,s)))
        for (t in seq_len(k)) {
            if (t == s) next
            price <- if (t < s) { if (t <= n) by_bid[[t]]$bid else 0 } else gsp_price(by_bid,t)
            payoff <- rmul(rates[[t]], rat(bidder$value-price))
            if (rcmp(payoff,current) > 0) {
                deviations <- deviations+1L
                lines <- c(
                    lines,
                    line("DEVIATE", bidder$name, "from", s, "to", t, "gain", fraction(rsub(payoff,current)))
                )
            }
        }
    }
    lines <- c(lines, if (deviations == 0L) "NASH yes" else line("NASH no deviations", deviations))
    equilibrium <- violations == 0L && deviations == 0L
    lines <- c(lines, line("EQUILIBRIUM", if (equilibrium) "yes" else "no"))
    summary <- c(paste0(group$name, "/gsp,", fraction(gsp_revenue), ",", fraction(gsp_welfare), ",", fraction(efficiency)),
                 paste0(group$name, "/vcg,", fraction(vcg_revenue), ",", fraction(optimum), ",1"))
    list(
        lines=lines,
        summary=summary,
        envy_free=as.integer(violations == 0L),
        nash=as.integer(deviations == 0L),
        equilibria=as.integer(equilibrium)
    )
}
process_groups <- function(groups, parameters) {
    lines <- summary <- character()
    totals <- setNames(numeric(6L), c("lots", "slot_groups", "errors", "envy_free", "nash", "equilibria"))
    for (group in groups) {
        key <- if (group$kind == "lot") "lots" else "slot_groups"
        totals[key] <- totals[key]+1
        error <- ""
        rates <- list()
        if (group$kind == "slots") for (text in group$arguments) {
            if (!grepl("^[1-9][0-9]*/[1-9][0-9]*$", text)) {
                error <- paste("bad ctr", text)
                break
            }
            pair <- as.numeric(strsplit(text, "/", fixed=TRUE)[[1]])
            rate <- rat(pair[1], pair[2])
            if (rcmp(rate,rat(1)) > 0 || (length(rates) && rcmp(rate,rates[[length(rates)]]) >= 0)) {
                error <- paste("bad ctr", text)
                break
            }
            rates[[length(rates)+1L]] <- rate
        }
        if (!nzchar(error)) {
            if (!length(group$participants)) {
                error <- if (group$kind == "lot") "no bidders" else "no advertisers"
            } else {
                duplicate <- duplicate_name(group$participants)
                if (nzchar(duplicate)) {
                    error <- paste(
                        if (group$kind == "lot") "duplicate bidder" else "duplicate advertiser",
                        duplicate
                    )
                } else if (group$kind == "lot") {
                    indices <- which(vapply(group$participants, function(p) p$bid > p$value, FALSE))
                    if (length(indices)) error <- paste(
                        "bid above value",
                        group$participants[[indices[1]]]$name
                    )
                }
            }
        }
        if (nzchar(error)) {
            lines <- c(lines, line(toupper(group$kind), group$name, "ERROR", error))
            totals["errors"] <- totals["errors"]+1
        } else {
            result <- if (group$kind == "lot") lot_lines(group, parameters) else slots_lines(group, rates)
            lines <- c(lines, result$lines)
            summary <- c(summary, result$summary)
            if (group$kind == "slots") for (key in c(
                "envy_free",
                "nash",
                "equilibria"
            )) totals[key] <- totals[key]+result[[key]]
        }
    }
    lines <- c(
        lines,
        line(
            "SUMMARY lots",
            totals["lots"],
            "slot_groups",
            totals["slot_groups"],
            "errors",
            totals["errors"],
            "envy_free",
            totals["envy_free"],
            "nash",
            totals["nash"],
            "equilibria",
            totals["equilibria"]
        )
    )
    list(lines=lines, summary=summary)
}
main <- function() {
    inputs <- read_inputs()
    reserves <- inputs$reserves
    parameters <- inputs$parameters
    wdp <- vcg <- core <- ascending <- character()
    summary <- "mechanism,revenue,welfare,efficiency"
    keys <- c(
        "auctions",
        "bids",
        "valid",
        "eligible",
        "nodes",
        "greedy_optimal",
        "rounds",
        "capped",
        "exposed",
        "exposure"
    )
    totals <- setNames(numeric(length(keys)), keys)
    revenues <- setNames(numeric(length(MECHANISMS)), MECHANISMS)
    core_totals <- setNames(numeric(6L), c("checked", "skipped", OUTCOMES))
    for (name in parameters$run) {
        a <- prepare_auction(inputs$raw[[name]], reserves, parameters)
        wdp <- c(wdp, wdp_lines(a, reserves))
        vcg <- c(vcg, vcg_lines(a))
        check <- core_lines(a, reserves, parameters)
        core <- c(core, check$lines)
        core_totals <- core_totals+check$counts
        ascending <- c(ascending, a$saa$lines)
        totals <- totals+c(1, a$bid_count, length(a$valid), length(a$eligible), a$optimal$nodes,
                           as.integer(a$greedy$welfare == a$exact$welfare), a$saa$rounds, as.integer(a$saa$reason == "cap"), a$saa$exposed, a$saa$exposure)
        income <- c(a$revenue, a$exact$accepted, a$greedy$accepted, a$critical_revenue, a$saa$revenue)
        welfare <- c(a$exact$welfare, a$exact$welfare, a$greedy$welfare, a$greedy$welfare, a$saa$welfare)
        revenues <- revenues+income
        for (i in seq_along(MECHANISMS)) summary <- c(
            summary,
            paste0(
                name,
                "/",
                MECHANISMS[i],
                ",",
                integer_text(income[i]),
                ",",
                integer_text(welfare[i]),
                ",",
                fraction(rat(welfare[i],a$exact$welfare))
            )
        )
    }
    wdp <- c(
        wdp,
        line(
            "TOTAL auctions",
            totals["auctions"],
            "bids",
            totals["bids"],
            "valid",
            totals["valid"],
            "eligible",
            totals["eligible"],
            "nodes",
            totals["nodes"],
            "greedy_optimal",
            totals["greedy_optimal"]
        )
    )
    vcg <- c(
        vcg,
        paste0(
            "OVERALL",
            paste(vapply(MECHANISMS, function(name) paste("", name, revenues[name]), ""), collapse="")
        )
    )
    core <- c(
        core,
        paste0(
            line("SUMMARY checked", core_totals["checked"], "skipped", core_totals["skipped"]),
            paste(vapply(OUTCOMES, function(name) paste("", name, core_totals[name]), ""), collapse="")
        )
    )
    ascending <- c(
        ascending,
        line(
            "SUMMARY auctions",
            totals["auctions"],
            "rounds",
            totals["rounds"],
            "capped",
            totals["capped"],
            "exposed",
            totals["exposed"],
            "exposure",
            totals["exposure"]
        )
    )
    single <- process_groups(inputs$groups, parameters)
    summary <- c(summary, single$summary)
    write_reports(list(
        wdp.txt=wdp,
        vcg.txt=vcg,
        core_check.txt=core,
        ascending_log.txt=ascending,
        single_item.txt=single$lines,
        summary.csv=summary
    ))
}
main()
