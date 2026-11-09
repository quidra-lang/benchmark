for (file in c("hashing", "wallets", "transactions", "blocks", "chain")) source(paste0(file, ".R"))

setting <- function(node, key, index = 1L) as.integer(node$params[[key]][index])
height <- function(record) record$block$height
next_height <- function(node) height(node$tip) + 1L
reward <- function(node, h) block_reward(h, setting(node, "REWARD"), setting(node, "REWARD", 2L))
difficulty <- function(node, parent = node$tip) required_difficulty(
    parent,
    setting(node, "DIFFICULTY"),
    setting(node, "RETARGET"),
    setting(node, "RETARGET", 2L)
)
mature <- function(node, coin) is_mature(coin, next_height(node), setting(node, "MATURITY"))
node_balance <- function(node, address) sum(vapply(
    node$tip$utxo,
    function(coin) if (coin$address == address) coin$amount else 0L,
    0L
))
locked_references <- function(node) unique(unlist(
    lapply(node$mempool, function(entry) entry$transaction$inputs),
    use.names = FALSE
))
priority_order <- function(node) {
    entries <- node$mempool
    before <- function(first, second) {
        left <- first$fee * second$transaction$size
        right <- second$fee * first$transaction$size
        if (left != right) left > right else first$transaction$txid < second$transaction$txid
    }
    ranks <- vapply(entries, function(entry) sum(vapply(entries, before, FALSE, second = entry)), 0L)
    entries[order(ranks)]
}
find_entry <- function(node, txid) {
    for (entry in node$mempool) if (entry$transaction$txid == txid) return(entry)
    NULL
}
line_text <- function(...) paste(c(...), collapse = " ")
log_event <- function(node, ...) node$log <- c(node$log, line_text(node$now, ...))
signed <- function(value) paste0(if (value >= 0L) "+" else "", value)
tally <- function(node, category, reason) {
    key <- paste(category, reason)
    count <- node$rejections[[key]]
    node$rejections[[key]] <- if (is.null(count)) 1L else count + 1L
}
refresh_chain <- function(node) {
    node$main_chain <- chain_to(node$tip)
    node$confirmed <- list()
    for (record in node$main_chain) for (tx in record$block$transactions) node$confirmed[[tx$txid]] <- height(record)
}
new_node <- function(params, wallets) {
    node <- new.env(parent = emptyenv())
    node$params <- params
    node$wallets <- wallets
    node$owners <- setNames(wallets, vapply(wallets, function(w) w$address, ""))
    node$named <- setNames(wallets, vapply(wallets, function(w) w$name, ""))
    genesis <- params$GENESIS
    outputs <- lapply(
        seq.int(1L, length(genesis), 2L),
        function(i) list(address = node$named[[genesis[i]]]$address, amount = as.integer(genesis[i + 1L]))
    )
    tx <- create_coinbase(0L, outputs)
    b <- block(0L, paste(rep("0", 32L), collapse = ""), tx$txid, 0L, 0L, 0L, list(tx))
    record <- block_record(b, NULL, apply_transaction(list(), tx, 0L), integer(), "genesis")
    node$now <- 0L
    node$records <- setNames(list(record), b$hash)
    node$mempool <- list()
    node$orphans <- list()
    node$rejected <- character()
    node$drops <- list()
    node$peers <- list()
    node$rejections <- list()
    node$reorganizations <- list()
    node$log <- character()
    node$tip <- record
    refresh_chain(node)
    node
}
new_peer <- function(name) {
    peer <- new.env(parent = emptyenv())
    peer$name <- name
    for (field in c(
        "blocks",
        "rejected_blocks",
        "orphans",
        "txs",
        "rejected_txs",
        "ignored",
        "score"
    )) peer[[field]] <- 0L
    peer
}
acceptance <- function(node, tx) {
    failure <- function(reason) list(reason = reason, fee = 0L, conflicts = list())
    if (is_coinbase(tx)) return(failure("coinbase"))
    if (!is.null(node$confirmed[[tx$txid]]) || !is.null(find_entry(
        node,
        tx$txid
    ))) return(failure("duplicate"))
    result <- check_transaction(
        tx,
        node$tip$utxo,
        character(),
        next_height(node),
        node$owners,
        setting(node, "MATURITY")
    )
    if (!is.null(result$reason)) return(failure(result$reason))
    fee <- result$fee
    if (fee * 1000L < setting(node, "MINFEERATE") * tx$size) return(failure("low-fee"))
    conflicts <- Filter(function(entry) any(entry$transaction$inputs %in% tx$inputs), node$mempool)
    if (length(conflicts) && !(fee > sum(vapply(conflicts, function(entry) entry$fee, 0L)) && all(vapply(
        conflicts,
        function(entry) fee * entry$transaction$size > entry$fee * tx$size,
        FALSE
    )))) return(failure("conflict"))
    list(reason = NULL, fee = fee, conflicts = conflicts)
}
record_drop <- function(node, txid, reason) {
    node$drops[[txid]] <- reason
    log_event(node, "DROP", short_hash(txid), reason)
}
drop_entry <- function(node, entry, reason) {
    node$mempool <- Filter(function(other) other$transaction$txid != entry$transaction$txid, node$mempool)
    record_drop(node, entry$transaction$txid, reason)
}
register <- function(node, tx, result, arrival) {
    for (entry in result$conflicts) drop_entry(node, entry, "replaced")
    node$mempool <- c(node$mempool, list(list(transaction = tx, fee = result$fee, arrival = arrival)))
    if (length(node$mempool) > setting(node, "MEMPOOL")) drop_entry(
        node,
        tail(priority_order(node), 1L)[[1L]],
        "mempool-full"
    )
}
rebuild_mempool <- function(node, returned) {
    previous <- node$mempool
    node$mempool <- list()
    candidates <- c(
        lapply(returned, function(tx) list(transaction = tx, arrival = node$now, returned = TRUE)),
        lapply(previous, function(entry) c(entry, list(returned = FALSE)))
    )
    for (candidate in candidates) {
        tx <- candidate$transaction
        if (!is.null(node$confirmed[[tx$txid]])) next
        result <- acceptance(node, tx)
        if (!is.null(result$reason)) record_drop(node, tx$txid, result$reason) else {
            if (candidate$returned) log_event(node, "RETURN", short_hash(tx$txid))
            register(node, tx, result, candidate$arrival)
        }
    }
}
switch_tip <- function(node, target) {
    old <- node$tip
    fork <- fork_point(old, target)
    disconnected <- height(old) - height(fork)
    connected <- height(target) - height(fork)
    if (disconnected > setting(node, "MAXREORG")) {
        log_event(
            node,
            "REFUSE",
            height(target),
            short_hash(target$block$hash),
            "work",
            target$cumulative_work,
            "fork",
            height(fork),
            "depth",
            disconnected
        )
        return(invisible(NULL))
    }
    returned <- list()
    for (record in node$main_chain) if (height(record) > height(fork)) returned <- c(
        returned,
        record$block$transactions[-1L]
    )
    node$tip <- target
    refresh_chain(node)
    if (disconnected == 0L) log_event(
        node,
        "TIP",
        height(target),
        short_hash(target$block$hash),
        "work",
        target$cumulative_work
    ) else {
        log_event(
            node,
            "REORG",
            height(target),
            short_hash(target$block$hash),
            "work",
            target$cumulative_work,
            "fork",
            height(fork),
            "disconnected",
            disconnected,
            "connected",
            connected
        )
        node$reorganizations <- c(
            node$reorganizations,
            list(list(
                time = node$now,
                fork = height(fork),
                disconnected = disconnected,
                connected = connected,
                old = old$block$hash,
                new = target$block$hash
            ))
        )
    }
    rebuild_mempool(node, returned)
}
penalize <- function(node, peer, points) {
    before <- peer$score
    peer$score <- peer$score + points
    if (before < setting(node, "BAN") && peer$score >= setting(node, "BAN")) log_event(
        node,
        "BAN",
        peer$name,
        "score",
        peer$score
    )
}
pay <- function(node, fields) {
    sender <- node$named[[fields[3L]]]
    fee <- as.integer(fields[4L])
    outputs <- lapply(
        seq.int(5L, length(fields), 2L),
        function(i) list(address = node$named[[fields[i]]]$address, amount = as.integer(fields[i + 1L]))
    )
    total <- sum(vapply(outputs, function(output) output$amount, 0L))
    need <- total + fee
    locked <- locked_references(node)
    refs <- names(node$tip$utxo)
    refs <- refs[vapply(refs, function(ref) {
        coin <- node$tip$utxo[[ref]]
        coin$address == sender$address && !(ref %in% locked) && mature(node, coin)
    }, FALSE)]
    amounts <- vapply(refs, function(ref) node$tip$utxo[[ref]]$amount, 0L)
    refs <- refs[order(-amounts, substr(refs, 1L, 32L), as.integer(substring(refs, 34L)), method = "radix")]
    inputs <- character()
    gathered <- 0L
    for (ref in refs) {
        if (gathered >= need) break
        inputs <- c(inputs, ref)
        gathered <- gathered + node$tip$utxo[[ref]]$amount
    }
    prefix <- c("PAY", sender$name, "fee", fee, "total", total)
    if (gathered < need) {
        log_event(node, prefix, "rejected", "insufficient-funds")
        tally(node, "pay", "insufficient-funds")
        return(invisible(NULL))
    }
    if (gathered > need) outputs <- c(outputs, list(list(address = sender$address, amount = gathered - need)))
    tx <- create_transaction(inputs, outputs, sender$secret)
    result <- acceptance(node, tx)
    if (!is.null(result$reason)) {
        log_event(node, prefix, "tx", short_hash(tx$txid), "rejected", result$reason)
        tally(node, "pay", result$reason)
    } else {
        log_event(
            node,
            prefix,
            "tx",
            short_hash(tx$txid),
            "accepted",
            "inputs",
            length(inputs),
            "outputs",
            length(outputs),
            "size",
            tx$size
        )
        register(node, tx, result, node$now)
    }
}
bump <- function(node, txid, fee) {
    prefix <- c("BUMP", short_hash(txid), "fee", fee)
    entry <- find_entry(node, txid)
    if (is.null(entry)) {
        log_event(node, prefix, "rejected", "unknown")
        tally(node, "bump", "unknown")
        return(invisible(NULL))
    }
    original <- entry$transaction
    addresses <- unique(vapply(original$inputs, function(ref) node$tip$utxo[[ref]]$address, ""))
    last <- tail(original$outputs, 1L)[[1L]]
    change <- last$amount - (fee - entry$fee)
    if (length(addresses) != 1L || addresses[1L] != last$address || change < 1L) {
        log_event(node, prefix, "rejected", "no-change")
        tally(node, "bump", "no-change")
        return(invisible(NULL))
    }
    outputs <- original$outputs
    outputs[[length(outputs)]]$amount <- change
    tx <- create_transaction(original$inputs, outputs, node$owners[[last$address]]$secret)
    result <- acceptance(node, tx)
    if (!is.null(result$reason)) {
        log_event(node, prefix, "tx", short_hash(tx$txid), "rejected", result$reason)
        tally(node, "bump", result$reason)
    } else {
        log_event(node, prefix, "tx", short_hash(tx$txid), "accepted", "size", tx$size)
        register(node, tx, result, node$now)
    }
}
receive_transaction <- function(node, peer, tx) {
    result <- acceptance(node, tx)
    if (!is.null(result$reason)) {
        peer$rejected_txs <- peer$rejected_txs + 1L
        tally(node, "tx", result$reason)
        log_event(node, "TX", peer$name, short_hash(tx$txid), "rejected", result$reason)
        if (result$reason %in% c(
            "coinbase",
            "bad-output",
            "bad-sig",
            "overspend"
        )) penalize(node, peer, setting(node, "BAN", 3L))
    } else {
        peer$txs <- peer$txs + 1L
        log_event(node, "TX", peer$name, short_hash(tx$txid), "accepted", "fee", result$fee, "size", tx$size)
        register(node, tx, result, node$now)
    }
}
mine <- function(node, wallet) {
    h <- next_height(node)
    selected <- list()
    size <- 0L
    for (entry in priority_order(node)) if (size + entry$transaction$size <= setting(node, "MAXBLOCK")) {
        selected <- c(selected, list(entry))
        size <- size + entry$transaction$size
    }
    fees <- vapply(selected, function(entry) entry$fee, 0L)
    coinbase <- create_coinbase(h, list(list(address = wallet$address, amount = reward(node, h) + sum(fees))))
    transactions <- c(list(coinbase), lapply(selected, function(entry) entry$transaction))
    b <- mine_block(
        h,
        node$tip$block$hash,
        transactions,
        max(node$now, median_time(node$tip) + 1L),
        difficulty(node)
    )
    utxo <- node$tip$utxo
    for (tx in transactions) utxo <- apply_transaction(utxo, tx, h)
    record <- block_record(b, node$tip, utxo, fees, "local")
    node$records[[b$hash]] <- record
    log_event(
        node,
        "MINE",
        wallet$name,
        h,
        short_hash(b$hash),
        "bits",
        b$difficulty,
        "nonce",
        b$nonce,
        "txs",
        length(transactions),
        "size",
        size,
        "fees",
        record$fees,
        "work",
        record$cumulative_work
    )
    switch_tip(node, record)
}
reject_block <- function(node, kind, block, peer, reason) {
    node$rejected <- union(node$rejected, block$hash)
    peer$rejected_blocks <- peer$rejected_blocks + 1L
    tally(node, "block", strsplit(reason, " ", fixed = TRUE)[[1L]][1L])
    log_event(node, kind, peer$name, block$height, short_hash(block$hash), "rejected", reason)
    if (reason != "time-too-new") penalize(node, peer, setting(node, "BAN", 2L))
}
validate_block <- function(node, block, parent) {
    failure <- function(reason) list(reason = reason)
    if (block$height != height(parent) + 1L) return(failure("bad-height"))
    if (block$difficulty != difficulty(node, parent)) return(failure("bad-difficulty"))
    if (block$timestamp <= median_time(parent)) return(failure("time-too-old"))
    if (block$timestamp > node$now + setting(node, "DRIFT")) return(failure("time-too-new"))
    utxo <- parent$utxo
    spent <- character()
    fees <- integer()
    for (position in seq_along(block$transactions)[-1L]) {
        tx <- block$transactions[[position]]
        result <- check_transaction(tx, utxo, spent, block$height, node$owners, setting(node, "MATURITY"))
        if (!is.null(result$reason)) return(failure(paste(result$reason, "tx", position)))
        spent <- union(spent, tx$inputs)
        utxo <- apply_transaction(utxo, tx, block$height)
        fees <- c(fees, result$fee)
    }
    coinbase <- block$transactions[[1L]]
    for (output in coinbase$outputs) if (is.null(node$owners[[output$address]]) || output$amount == 0L) return(failure("bad-output tx 1"))
    if (output_total(coinbase) > reward(node, block$height) + sum(fees)) return(failure("bad-coinbase"))
    list(reason = NULL, utxo = apply_transaction(utxo, coinbase, block$height), fees = fees)
}
connect_block <- function(node, kind, block, peer) {
    parent <- node$records[[block$previous]]
    result <- validate_block(node, block, parent)
    if (!is.null(result$reason)) {
        reject_block(node, kind, block, peer, result$reason)
        return(invisible(NULL))
    }
    record <- block_record(block, parent, result$utxo, result$fees, peer$name)
    node$records[[block$hash]] <- record
    peer$blocks <- peer$blocks + 1L
    log_event(
        node,
        kind,
        peer$name,
        block$height,
        short_hash(block$hash),
        "accepted",
        "work",
        record$cumulative_work
    )
    if (record$cumulative_work > node$tip$cumulative_work) switch_tip(node, record)
}
resolve_orphans <- function(node, start) {
    queue <- start
    while (length(queue)) {
        parent <- queue[1L]
        queue <- queue[-1L]
        children <- Filter(function(orphan) orphan$block$previous == parent, node$orphans)
        for (orphan in children) {
            node$orphans <- Filter(function(other) other$block$hash != orphan$block$hash, node$orphans)
            if (parent %in% node$rejected) reject_block(
                node,
                "UNORPHAN",
                orphan$block,
                orphan$peer,
                "bad-parent"
            ) else connect_block(node, "UNORPHAN", orphan$block, orphan$peer)
            queue <- c(queue, orphan$block$hash)
        }
    }
}
receive_block <- function(node, peer, block) {
    if (!is.null(node$records[[block$hash]]) || any(vapply(
        node$orphans,
        function(orphan) orphan$block$hash == block$hash,
        FALSE
    )) || block$hash %in% node$rejected) {
        log_event(node, "BLOCK", peer$name, block$height, short_hash(block$hash), "rejected", "duplicate")
        peer$rejected_blocks <- peer$rejected_blocks + 1L
        tally(node, "block", "duplicate")
        return(invisible(NULL))
    }
    reason <- context_free_error(block, setting(node, "MAXBLOCK"))
    if (is.null(reason) && block$previous %in% node$rejected) reason <- "bad-parent"
    if (!is.null(reason)) {
        reject_block(node, "BLOCK", block, peer, reason)
        resolve_orphans(node, block$hash)
    } else if (is.null(node$records[[block$previous]])) {
        node$orphans <- c(node$orphans, list(list(block = block, peer = peer)))
        peer$orphans <- peer$orphans + 1L
        log_event(
            node,
            "BLOCK",
            peer$name,
            block$height,
            short_hash(block$hash),
            "orphan",
            "parent",
            short_hash(block$previous)
        )
        if (length(node$orphans) > setting(node, "ORPHANS")) {
            evicted <- node$orphans[[1L]]
            node$orphans <- node$orphans[-1L]
            log_event(node, "EVICT", short_hash(evicted$block$hash), "orphan-limit")
        }
    } else {
        connect_block(node, "BLOCK", block, peer)
        resolve_orphans(node, block$hash)
    }
}
status <- function(node, txid) {
    prefix <- c("STATUS", short_hash(txid))
    h <- node$confirmed[[txid]]
    if (!is.null(h)) {
        log_event(node, prefix, "confirmed", h, "confirmations", next_height(node) - h)
        return(invisible(NULL))
    }
    ranked <- priority_order(node)
    ranks <- which(vapply(ranked, function(entry) entry$transaction$txid == txid, FALSE))
    if (length(ranks)) log_event(
        node,
        prefix,
        "mempool",
        "rank",
        ranks[1L],
        "of",
        length(ranked)
    ) else if (!is.null(node$drops[[txid]])) log_event(node, prefix, "dropped", node$drops[[txid]]) else {
        stale <- any(vapply(
            node$records,
            function(record) any(vapply(record$block$transactions, function(tx) tx$txid == txid, FALSE)),
            FALSE
        ))
        log_event(node, prefix, if (stale) "stale" else "unknown")
    }
}
print_state <- function(node) {
    ranked <- priority_order(node)
    log_event(
        node,
        "PRINT",
        "height",
        height(node$tip),
        "tip",
        short_hash(node$tip$block$hash),
        "work",
        node$tip$cumulative_work,
        "bits",
        difficulty(node),
        "reward",
        reward(node, next_height(node)),
        "mempool",
        length(ranked),
        "size",
        sum(vapply(ranked, function(entry) entry$transaction$size, 0L)),
        "orphans",
        length(node$orphans)
    )
    for (rank in seq_along(ranked)) {
        entry <- ranked[[rank]]
        log_event(
            node,
            "MEMPOOL",
            rank,
            short_hash(entry$transaction$txid),
            "fee",
            entry$fee,
            "size",
            entry$transaction$size
        )
    }
    for (wallet in node$wallets) log_event(node, "BALANCE", wallet$name, node_balance(node, wallet$address))
}
process <- function(node, fields, texts) {
    node$now <- as.integer(fields[1L])
    for (entry in node$mempool) if (node$now - entry$arrival >= setting(node, "EXPIRY")) drop_entry(
        node,
        entry,
        "expired"
    )
    kind <- fields[2L]
    if (kind == "PAY") pay(node, fields) else if (kind == "BUMP") bump(
        node,
        fields[3L],
        as.integer(fields[4L])
    ) else if (kind == "MINE") mine(node, node$named[[fields[3L]]]) else if (kind == "STATUS") status(node, fields[3L]) else if (kind == "PRINT") print_state(node) else {
        name <- fields[3L]
        if (is.null(node$peers[[name]])) node$peers[[name]] <- new_peer(name)
        peer <- node$peers[[name]]
        if (peer$score >= setting(node, "BAN")) {
            peer$ignored <- peer$ignored + 1L
            log_event(node, "IGNORE", name, kind)
        } else if (kind == "TX") receive_transaction(node, peer, parse_transaction(fields[4L])) else receive_block(
            node,
            peer,
            parse_block_event(fields, texts)
        )
    }
}
miner_address <- function(record) record$block$transactions[[1L]]$outputs[[1L]]$address
chain_lines <- function(node) {
    tip <- node$tip
    lines <- line_text(
        "TIP",
        height(tip),
        tip$block$hash,
        "work",
        tip$cumulative_work,
        "stored",
        length(node$records),
        "orphans",
        length(node$orphans)
    )
    add <- function(...) lines <<- c(lines, line_text(...))
    for (record in node$main_chain) {
        b <- record$block
        miner <- if (b$height == 0L) "-" else node$owners[[miner_address(record)]]$name
        add(
            "BLOCK",
            b$height,
            b$hash,
            "prev",
            short_hash(b$previous),
            "time",
            b$timestamp,
            "bits",
            b$difficulty,
            "nonce",
            b$nonce,
            "txs",
            length(b$transactions),
            "size",
            block_size(b),
            "fees",
            record$fees,
            "miner",
            miner,
            "source",
            record$source,
            "work",
            record$cumulative_work
        )
        for (k in seq_along(b$transactions)) {
            tx <- b$transactions[[k]]
            if (is_coinbase(tx)) add("TX", k, tx$txid, if (b$height == 0L) "genesis" else "coinbase", "out", length(tx$outputs), "amount", output_total(tx)) else add(
                "TX",
                k,
                tx$txid,
                "payment",
                "in",
                length(tx$inputs),
                "out",
                length(tx$outputs),
                "size",
                tx$size,
                "fee",
                record$transaction_fees[k - 1L]
            )
        }
    }
    main_hashes <- vapply(node$main_chain, function(record) record$block$hash, "")
    stale <- Filter(function(record) !(record$block$hash %in% main_hashes), node$records)
    stale <- stale[order(
        vapply(stale, height, 0L),
        vapply(stale, function(record) record$block$hash, ""),
        method = "radix"
    )]
    for (record in stale) add(
        "STALE",
        height(record),
        record$block$hash,
        "prev",
        short_hash(record$block$previous),
        "source",
        record$source,
        "work",
        record$cumulative_work
    )
    for (orphan in node$orphans) add(
        "ORPHAN",
        orphan$block$height,
        orphan$block$hash,
        "prev",
        short_hash(orphan$block$previous),
        "source",
        orphan$peer$name
    )
    for (entry in node$reorganizations) add(
        "REORG",
        entry$time,
        "fork",
        entry$fork,
        "disconnected",
        entry$disconnected,
        "connected",
        entry$connected,
        "old",
        short_hash(entry$old),
        "new",
        short_hash(entry$new)
    )
    mined <- node$main_chain[-1L]
    for (wallet in node$wallets) {
        own <- Filter(function(record) miner_address(record) == wallet$address, mined)
        if (length(own)) add(
            "MINER",
            wallet$name,
            "blocks",
            length(own),
            "coinbase",
            sum(vapply(own, function(record) output_total(record$block$transactions[[1L]]), 0L)),
            "fees",
            sum(vapply(own, function(record) record$fees, 0L))
        )
    }
    i <- 1L
    while (i <= length(mined)) {
        j <- i
        while (j < length(mined) && mined[[j + 1L]]$block$difficulty == mined[[i]]$block$difficulty) j <- j + 1L
        add(
            "BITS",
            mined[[i]]$block$difficulty,
            "heights",
            paste(height(mined[[i]]), height(mined[[j]]), sep = "-"),
            "blocks",
            j - i + 1L
        )
        i <- j + 1L
    }
    for (name in sort(names(node$peers), method = "radix")) {
        peer <- node$peers[[name]]
        add(
            "PEER",
            name,
            "blocks",
            peer$blocks,
            "rejected",
            peer$rejected_blocks,
            "orphans",
            peer$orphans,
            "txs",
            peer$txs,
            "rejected",
            peer$rejected_txs,
            "ignored",
            peer$ignored,
            "score",
            peer$score,
            if (peer$score >= setting(node, "BAN")) "banned" else "ok"
        )
    }
    ranked <- priority_order(node)
    for (rank in seq_along(ranked)) {
        entry <- ranked[[rank]]
        add(
            "MEMPOOL",
            rank,
            entry$transaction$txid,
            "fee",
            entry$fee,
            "size",
            entry$transaction$size,
            "time",
            entry$arrival
        )
    }
    for (key in sort(names(node$rejections), method = "radix")) add("REJECT", key, node$rejections[[key]])
    genesis <- output_total(node$main_chain[[1L]]$block$transactions[[1L]])
    rewards <- sum(vapply(mined, function(record) reward(node, height(record)), 0L))
    fees <- sum(vapply(mined, function(record) record$fees, 0L))
    minted <- sum(vapply(mined, function(record) output_total(record$block$transactions[[1L]]), 0L))
    add(
        "SUPPLY",
        "genesis",
        genesis,
        "rewards",
        rewards,
        "fees",
        fees,
        "burned",
        rewards + fees - minted,
        "utxo",
        sum(vapply(tip$utxo, function(coin) coin$amount, 0L))
    )
    lines
}
balance_lines <- function(node) {
    locked <- locked_references(node)
    lines <- "wallet,address,balance,immature,locked,incoming,utxos"
    for (wallet in node$wallets) {
        refs <- names(node$tip$utxo)[vapply(
            node$tip$utxo,
            function(coin) coin$address == wallet$address,
            FALSE
        )]
        amount <- function(ref) node$tip$utxo[[ref]]$amount
        balance <- sum(vapply(refs, amount, 0L))
        immature <- sum(vapply(
            refs,
            function(ref) if (!mature(node, node$tip$utxo[[ref]])) amount(ref) else 0L,
            0L
        ))
        amount_locked <- sum(vapply(refs[refs %in% locked], amount, 0L))
        incoming <- sum(vapply(
            node$mempool,
            function(entry) sum(vapply(
                entry$transaction$outputs,
                function(output) if (output$address == wallet$address) output$amount else 0L,
                0L
            )),
            0L
        ))
        lines <- c(
            lines,
            paste(
                wallet$name,
                wallet$address,
                balance,
                immature,
                amount_locked,
                incoming,
                length(refs),
                sep = ","
            )
        )
    }
    lines
}
coin_category <- function(coin) if (coin$height == 0L) "genesis" else if (coin$coinbase) "coinbase" else "payment"
utxo_lines <- function(node) {
    locked <- locked_references(node)
    utxo <- node$tip$utxo
    refs <- names(utxo)
    refs <- refs[order(substr(refs, 1L, 32L), as.integer(substring(refs, 34L)), method = "radix")]
    lines <- vapply(refs, function(ref) {
        coin <- utxo[[ref]]
        state <- if (!mature(node, coin)) "immature" else if (ref %in% locked) "locked" else "free"
        line_text(
            ref,
            node$owners[[coin$address]]$name,
            coin$amount,
            "height",
            coin$height,
            coin_category(coin),
            state
        )
    }, "")
    root <- merkle_root(vapply(lines, digest, ""))
    c(
        lines,
        line_text("TOTAL", length(utxo), sum(vapply(utxo, function(coin) coin$amount, 0L))),
        line_text("ROOT", root)
    )
}
history_lines <- function(node) {
    confirmed <- list()
    for (record in node$main_chain) for (tx in record$block$transactions) confirmed[[tx$txid]] <- tx
    lines <- character()
    add <- function(...) lines <<- c(lines, line_text(...))
    for (wallet in node$wallets) {
        add("WALLET", wallet$name, wallet$address)
        count <- spent_total <- received_total <- balance <- pending <- 0L
        for (record in node$main_chain) for (tx in record$block$transactions) {
            inputs <- lapply(tx$inputs, function(ref) {
                id <- substr(ref, 1L, 32L)
                index <- as.integer(substring(ref, 34L)) + 1L
                confirmed[[id]]$outputs[[index]]
            })
            involved <- any(vapply(
                c(inputs, tx$outputs),
                function(output) output$address == wallet$address,
                FALSE
            ))
            if (!involved) next
            own_amount <- function(output) if (output$address == wallet$address) output$amount else 0L
            spent <- sum(vapply(inputs, own_amount, 0L))
            received <- sum(vapply(tx$outputs, own_amount, 0L))
            count <- count + 1L
            spent_total <- spent_total + spent
            received_total <- received_total + received
            balance <- balance + received - spent
            category <- if (!is_coinbase(tx)) "payment" else if (height(record) == 0L) "genesis" else "coinbase"
            add(
                height(record),
                short_hash(tx$txid),
                category,
                "spent",
                spent,
                "received",
                received,
                "net",
                signed(received - spent),
                "balance",
                balance
            )
        }
        for (entry in priority_order(node)) {
            tx <- entry$transaction
            spent <- sum(vapply(tx$inputs, function(ref) {
                coin <- node$tip$utxo[[ref]]
                if (coin$address == wallet$address) coin$amount else 0L
            }, 0L))
            received <- sum(vapply(
                tx$outputs,
                function(output) if (output$address == wallet$address) output$amount else 0L,
                0L
            ))
            if (spent != 0L || received != 0L) {
                pending <- pending + 1L
                add(
                    "pending",
                    short_hash(tx$txid),
                    "spent",
                    spent,
                    "received",
                    received,
                    "net",
                    signed(received - spent)
                )
            }
        }
        add(
            "END",
            wallet$name,
            "txs",
            count,
            "spent",
            spent_total,
            "received",
            received_total,
            "balance",
            balance,
            "pending",
            pending
        )
    }
    lines
}
main <- function() {
    options(scipen = 999)
    params <- list()
    for (fields in strsplit(
        readLines("input/params.txt"),
        " ",
        fixed = TRUE
    )) params[[fields[1L]]] <- fields[-1L]
    node <- new_node(params, read_wallets("input/wallets.txt"))
    lines <- readLines("input/events.txt")
    position <- 1L
    while (position <= length(lines)) {
        fields <- strsplit(lines[position], " ", fixed = TRUE)[[1L]]
        count <- if (fields[2L] == "BLOCK") as.integer(fields[10L]) else 0L
        texts <- if (count) lines[seq.int(position + 1L, position + count)] else character()
        process(node, fields, texts)
        position <- position + count + 1L
    }
    dir.create("output", showWarnings = FALSE)
    outputs <- list(
        "log.txt" = node$log,
        "chain.txt" = chain_lines(node),
        "balances.csv" = balance_lines(node),
        "utxo.txt" = utxo_lines(node),
        "history.txt" = history_lines(node)
    )
    for (name in names(outputs)) writeLines(outputs[[name]], file.path("output", name), useBytes = TRUE)
}
main()
