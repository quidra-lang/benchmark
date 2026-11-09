source("config_io.R")
source("cache.R")
source("protocol.R")
source("bus.R")
source("stats.R")

validate_trace <- function(lines, config) {
    events <- rejected <- list()
    latest <- 0L
    for (line_number in seq_along(lines)) {
        line <- lines[line_number]
        fields <- strsplit(paste0(line, " "), " ", fixed = TRUE)[[1L]]
        reason <- NULL
        if (!length(fields) %in% c(3L, 4L) || any(!nzchar(fields))) {
            reason <- "fields"
        } else if (!decimal_integer(fields[1L], 7L)) {
            reason <- "cycle"
        } else if (!decimal_integer(fields[2L]) || as.integer(fields[2L]) >= config$cores) {
            reason <- "core"
        } else if (!fields[3L] %in% c(
            "R",
            "W",
            "FENCE"
        ) || (fields[3L] == "FENCE" && length(fields) != 3L) || (fields[3L] != "FENCE" && length(fields) != 4L)) {
            reason <- "op"
        } else if (fields[3L] != "FENCE" && (!valid_hex_address(fields[4L]) || strtoi(
            substr(fields[4L], 1L, 1L),
            16L
        ) > 7L || strtoi(fields[4L], 16L) %% 4L != 0L)) {
            reason <- "address"
        } else if (as.integer(fields[1L]) < latest) {
            reason <- "order"
        }
        if (!is.null(reason)) {
            rejected[[length(rejected) + 1L]] <- list(number = line_number, reason = reason)
            next
        }
        event <- new.env(parent = emptyenv())
        event$number <- length(events) + 1L
        event$cycle <- as.integer(fields[1L])
        event$core <- as.integer(fields[2L])
        event$operation <- fields[3L]
        event$address <- if (fields[3L] == "FENCE") 0L else strtoi(fields[4L], 16L)
        event$block <- event$address %/% config$line_size
        event$word <- (event$address %% config$line_size) %/% 4L
        event$distance <- 0L
        latest <- event$cycle
        events[[length(events) + 1L]] <- event
    }
    list(events = events, rejected = rejected)
}

per_core_events <- function(events, core_count) {
    groups <- rep(list(list()), core_count)
    for (event in events) groups[[event$core + 1L]][[length(groups[[event$core + 1L]]) + 1L]] <- event
    groups
}

fenwick_add <- function(tree, index, amount) {
    while (index <= length(tree$values)) {
        tree$values[index] <- tree$values[index] + amount
        index <- index + bitwAnd(index, -index)
    }
}

fenwick_sum <- function(tree, index) {
    total <- 0L
    while (index > 0L) {
        total <- total + tree$values[index]
        index <- index - bitwAnd(index, -index)
    }
    total
}

reuse_analysis <- function(events, config) {
    analyses <- list()
    capacities <- c(config$cap %/% 4L, config$cap %/% 2L, config$cap, 2L * config$cap, 4L * config$cap)
    labels <- c("1", "2-4", "5-16", "17-64", "65-256", "257+")
    by_core <- per_core_events(events, config$cores)
    for (core_index in seq_along(by_core)) {
        accesses <- Filter(function(event) event$operation != "FENCE", by_core[[core_index]])
        last_position <- new_counter()
        tree <- new.env(parent = emptyenv())
        tree$values <- integer(length(accesses))
        distances <- new_counter()
        lru <- new_counter()
        cold <- 0L
        for (index in seq_along(accesses)) {
            event <- accesses[[index]]
            previous <- counter_value(last_position, event$block)
            if (previous == 0L) {
                cold <- cold + 1L
                distance <- 0L
            } else {
                distance <- fenwick_sum(tree, index - 1L) - fenwick_sum(tree, previous - 1L)
                bucket <- if (distance == 1L) 1L else if (distance <= 4L) 2L else if (distance <= 16L) 3L else if (distance <= 64L) 4L else if (distance <= 256L) 5L else 6L
                add_count(distances, labels[bucket])
                fenwick_add(tree, previous, -1L)
            }
            event$distance <- distance
            for (capacity in capacities) if (distance == 0L || distance > capacity) add_count(lru, capacity)
            fenwick_add(tree, index, 1L)
            last_position[[as.character(event$block)]] <- index
        }
        next_use <- rep(length(accesses) + 1L, length(accesses))
        future <- new_counter()
        for (index in rev(seq_along(accesses))) {
            key <- as.character(accesses[[index]]$block)
            next_use[index] <- if (exists(
                key,
                future,
                inherits = FALSE
            )) future[[key]] else length(accesses) + 1L
            future[[key]] <- index
        }
        resident <- new_counter()
        active <- integer()
        opt <- 0L
        for (index in seq_along(accesses)) {
            block <- accesses[[index]]$block
            key <- as.character(block)
            if (!exists(key, resident, inherits = FALSE)) {
                opt <- opt + 1L
                if (length(active) == config$cap) {
                    priorities <- vapply(active, function(line) resident[[as.character(line)]], 0L)
                    victim <- active[order(-priorities, active)[1L]]
                    rm(list = as.character(victim), envir = resident)
                    active <- active[active != victim]
                }
                active <- c(active, block)
            }
            resident[[key]] <- next_use[index]
        }
        analyses[[core_index]] <- list(
            core = core_index - 1L,
            accesses = length(accesses),
            lines = length(ls(last_position)),
            distances = distances,
            cold = cold,
            lru = lru,
            capacities = capacities,
            opt = opt
        )
    }
    analyses
}

static_sharing <- function(events) {
    lines <- new.env(parent = emptyenv())
    for (event in events) {
        if (event$operation == "FENCE") next
        key <- as.character(event$block)
        info <- lines[[key]]
        if (is.null(info)) {
            info <- new.env(parent = emptyenv())
            info$cores <- info$writers <- integer()
            info$counts <- new_counter()
            info$words <- new.env(parent = emptyenv())
            lines[[key]] <- info
        }
        info$cores <- union(info$cores, event$core)
        kind <- if (event$operation == "W") "writes" else "reads"
        add_count(info$counts, kind)
        if (event$operation == "W") info$writers <- union(info$writers, event$core)
        word_key <- as.character(event$word)
        word <- info$words[[word_key]]
        if (is.null(word)) word <- list(reads = integer(), writes = integer())
        word[[kind]] <- union(word[[kind]], event$core)
        info$words[[word_key]] <- word
    }
    lines
}

initial_state <- function(config, scenario, events) {
    state <- new.env(parent = emptyenv())
    state$config <- config
    state$scenario <- scenario
    state$l1 <- lapply(
        seq_len(config$cores),
        function(index) new_cache(config$l1_sets, config$l1_ways, scenario$l1)
    )
    state$l2 <- new_cache(config$l2_sets, config$l2_ways, scenario$l2)
    state$bus <- new_bus(config$tb)
    state$cores <- lapply(seq_len(config$cores), function(index) new_core_counters())
    state$event_lists <- per_core_events(events, config$cores)
    state$indices <- rep(1L, config$cores)
    state$ready <- state$write_completion <- integer(config$cores)
    state$seen <- lapply(seq_len(config$cores), function(index) new_counter())
    state$invalidations <- lapply(seq_len(config$cores), function(index) new.env(parent = emptyenv()))
    state$l2_counters <- new_counter()
    state$accesses <- list()
    state$watch_lines <- character()
    state$handoffs <- new_counter()
    state$last_writer <- new_counter()
    state$shared_misses <- new_counter()
    state$word_state <- new.env(parent = emptyenv())
    state$communications <- matrix(0L, config$cores, config$cores)
    state
}

line_states <- function(state, block) c(
    vapply(state$l1, cache_state, "", block = block),
    cache_state(state$l2, block)
)

next_event <- function(state) {
    chosen <- NULL
    for (core in seq_len(state$config$cores) - 1L) {
        index <- state$indices[core + 1L]
        ordered <- state$event_lists[[core + 1L]]
        if (index <= length(ordered)) {
            event <- ordered[[index]]
            issue <- max(event$cycle, state$ready[core + 1L])
            if (is.null(chosen) || issue < chosen$issue || (issue == chosen$issue && core < chosen$core)) chosen <- list(
                issue = issue,
                core = core,
                event = event
            )
        }
    }
    chosen
}

issue_transaction <- function(state, core, kind, block, request_cycle) {
    tx <- bus_assign(state$bus, core, kind, block, request_cycle)
    add_count(state$cores[[core + 1L]]$bus, kind)
    if (kind == "WB") add_count(state$l2_counters, "writebacks")
    tx
}

snoop_others <- function(state, tx, word) {
    for (core in seq_len(state$config$cores) - 1L) {
        if (core == tx$core) next
        cache <- state$l1[[core + 1L]]
        old <- cache_state(cache, tx$block)
        if (old == "I") next
        updated <- snoop_transition(state$scenario$protocol, old, tx$kind)
        tx$snoops <- c(tx$snoops, sprintf("c%d:%s>%s", core, old, updated$state))
        tx$snoop_hits <- tx$snoop_hits + 1L
        if (updated$state == "I") {
            cache_remove(cache, tx$block)
            tx$invalidations <- tx$invalidations + 1L
            add_count(state$cores[[tx$core + 1L]]$snoop, "invalidations_sent")
            add_count(state$cores[[core + 1L]]$snoop, "invalidations_received")
            state$invalidations[[core + 1L]][[as.character(tx$block)]] <- word
        } else {
            cache_change(cache, tx$block, updated$state)
        }
        if (updated$supply) {
            tx$supplier <- core
            add_count(state$cores[[core + 1L]]$snoop, "supplied")
        }
        if (updated$flush) tx$flushed <- TRUE
    }
    if (tx$flushed) add_count(state$l2_counters, "flushes")
}

access_l2 <- function(state, tx) {
    cache <- state$l2
    add_count(state$l2_counters, "lookups")
    if (cache_state(cache, tx$block) != "I") {
        tx$l2 <- "hit"
        add_count(state$l2_counters, "hits")
        cache_touch(cache, tx$block)
    } else {
        tx$l2 <- "miss"
        add_count(state$l2_counters, "misses")
        evicted <- cache_fill(cache, tx$block, "C")
        if (!is.null(evicted)) {
            copies <- character()
            dirty <- evicted$state == "D"
            for (core in seq_len(state$config$cores) - 1L) {
                l1 <- state$l1[[core + 1L]]
                old <- cache_state(l1, evicted$block)
                if (old == "I") next
                cache_remove(l1, evicted$block)
                copies <- c(copies, sprintf("c%d:%s", core, old))
                add_count(state$cores[[core + 1L]]$snoop, "back_invalidations")
                if (old %in% DIRTY_STATES) dirty <- TRUE
            }
            tx$eviction <- list(block = evicted$block, copies = copies, dirty = dirty)
            add_count(state$l2_counters, "evictions")
            if (dirty) add_count(state$l2_counters, "dirty_evictions")
        }
    }
    if (tx$flushed || tx$kind == "BusWr") cache_change(cache, tx$block, "D")
}

run_bus_transaction <- function(state, core, kind, block, word, request_cycle) {
    tx <- issue_transaction(state, core, kind, block, request_cycle)
    snoop_others(state, tx, word)
    if (kind != "BusUpgr") access_l2(state, tx)
    completion <- tx$start + state$config$tb
    if (kind == "BusWr") {
        completion <- completion + state$config$t2 + (if (tx$l2 == "miss") state$config$tm else 0L)
    } else if (kind != "BusUpgr") {
        if (tx$supplier >= 0L) {
            tx$source <- paste0("c", tx$supplier)
        } else if (tx$l2 == "hit") {
            completion <- completion + state$config$t2
            tx$source <- "L2"
        } else {
            completion <- completion + state$config$t2 + state$config$tm
            tx$source <- "mem"
        }
    }
    list(completion = completion, transaction = tx)
}

write_back <- function(state, core, old_line) {
    issue_transaction(state, core, "WB", old_line$block, state$bus$free)
    cache_touch(state$l2, old_line$block)
    cache_change(state$l2, old_line$block, "D")
}

classify_miss <- function(state, event) {
    key <- as.character(event$block)
    if (!exists(
        key,
        state$seen[[event$core + 1L]],
        inherits = FALSE
    )) return(list(kind = "compulsory", sharing = NULL))
    record <- state$invalidations[[event$core + 1L]][[key]]
    if (!is.null(record)) return(list(
        kind = "coherence",
        sharing = if (event$word %in% record) "true_sharing" else "false_sharing"
    ))
    if (event$distance > state$config$cap) return(list(kind = "capacity", sharing = NULL))
    list(kind = "conflict", sharing = NULL)
}

communicate <- function(state, event) {
    key <- paste(event$block, event$word)
    previous <- state$word_state[[key]]
    if (is.null(previous)) previous <- list(writer = -1L, readers = integer())
    if (event$operation == "W") {
        former <- state$last_writer[[as.character(event$block)]]
        if (!is.null(former) && former != event$core) add_count(state$handoffs, event$block)
        state$last_writer[[as.character(event$block)]] <- event$core
        state$word_state[[key]] <- list(writer = event$core, readers = integer())
    } else if (previous$writer >= 0L && previous$writer != event$core && !event$core %in% previous$readers) {
        state$communications[previous$writer + 1L, event$core + 1L] <- state$communications[
            previous$writer + 1L,
            event$core + 1L
        ] + 1L
        previous$readers <- union(previous$readers, event$core)
        state$word_state[[key]] <- previous
    }
}

render_watch <- function(state, event, issue, before) {
    for (block in state$config$watch) {
        after <- line_states(state, block)
        if (block != event$block && identical(before[[as.character(block)]], after)) next
        columns <- paste(
            sprintf("c%d:%s", seq_len(state$config$cores) - 1L, head(after, -1L)),
            collapse = " "
        )
        state$watch_lines <- c(
            state$watch_lines,
            sprintf(
                "%d %d c%d %s %s line %s %s L2:%s",
                event$number,
                issue,
                event$core,
                event$operation,
                hex_address(event$address),
                hex_address(block * state$config$line_size),
                columns,
                tail(after, 1L)
            )
        )
    }
}

handle_access <- function(state, event, issue, primary) {
    config <- state$config
    core <- event$core
    block <- event$block
    word <- event$word
    operation <- event$operation
    counters <- state$cores[[core + 1L]]
    cache <- state$l1[[core + 1L]]
    before <- list()
    if (primary) for (watched in config$watch) before[[as.character(watched)]] <- line_states(state, watched)
    old <- cache_state(cache, block)
    hit <- old != "I"
    add_count(counters$simple, "accesses")
    add_count(counters$simple, if (operation == "R") "reads" else "writes")
    add_count(counters$simple, if (hit) "hits" else "misses")
    other_copy <- any(vapply(
        seq_len(config$cores) - 1L,
        function(k) k != core && cache_state(state$l1[[k + 1L]], block) != "I",
        FALSE
    ))
    transition <- requester_transition(state$scenario$protocol, old, operation, other_copy)
    kind <- transition$kind
    miss_kind <- NULL
    if (hit) {
        cache_touch(cache, block)
    } else {
        classification <- classify_miss(state, event)
        miss_kind <- classification$kind
        add_count(counters$misses, miss_kind)
        if (!is.null(classification$sharing)) {
            add_count(counters$misses, classification$sharing)
            add_count(state$shared_misses, paste(block, classification$sharing))
        }
    }
    key <- as.character(block)
    state$seen[[core + 1L]][[key]] <- 1L
    if (operation == "W") {
        for (other in seq_len(config$cores) - 1L) {
            records <- state$invalidations[[other + 1L]]
            if (other != core && exists(
                key,
                records,
                inherits = FALSE
            )) records[[key]] <- union(records[[key]], word)
        }
    }
    if (primary) communicate(state, event)
    if (is.null(kind)) {
        completion <- issue + config$t1
        service <- "l1"
    } else {
        result <- run_bus_transaction(state, core, kind, block, word, issue + config$t1)
        completion <- result$completion
        tx <- result$transaction
        service <- if (kind == "BusUpgr") "upgrade" else if (kind == "BusWr") "through" else if (tx$supplier >= 0L) "cache" else if (tx$l2 == "hit") "l2" else "memory"
    }
    if (old != "I") {
        cache_change(cache, block, transition$state)
    } else if (transition$state != "I") {
        evicted <- cache_fill(cache, block, transition$state)
        records <- state$invalidations[[core + 1L]]
        if (exists(key, records, inherits = FALSE)) rm(list = key, envir = records)
        if (!is.null(evicted) && evicted$state %in% DIRTY_STATES) write_back(state, core, evicted)
    }
    latency <- completion - issue
    add_count(counters$service, service)
    add_count(counters$simple, "latency", latency)
    add_count(counters$simple, if (operation == "R") "read_latency" else "write_latency", latency)
    if (operation == "R") {
        state$ready[core + 1L] <- completion
    } else {
        state$ready[core + 1L] <- issue + config$t1
        state$write_completion[core + 1L] <- max(state$write_completion[core + 1L], completion)
    }
    counters$finish <- max(counters$finish, completion)
    state$accesses[[length(state$accesses) + 1L]] <- list(
        number = event$number,
        issue = issue,
        core = core,
        operation = operation,
        address = event$address,
        block = block,
        word = word,
        latency = latency,
        service = service,
        miss_kind = miss_kind,
        hit = hit
    )
    if (primary) render_watch(state, event, issue, before)
}

simulate <- function(config, scenario, events, primary) {
    state <- initial_state(config, scenario, events)
    repeat {
        chosen <- next_event(state)
        if (is.null(chosen)) break
        issue <- chosen$issue
        core <- chosen$core
        event <- chosen$event
        state$indices[core + 1L] <- state$indices[core + 1L] + 1L
        if (event$operation == "FENCE") {
            counters <- state$cores[[core + 1L]]
            completion <- max(issue, state$write_completion[core + 1L])
            add_count(counters$simple, "fences")
            add_count(counters$simple, "fence_stall", completion - issue)
            counters$finish <- max(counters$finish, completion)
            state$ready[core + 1L] <- completion
        } else {
            handle_access(state, event, issue, primary)
        }
    }
    state$total <- total_counters(state$cores)
    state$finish <- state$total$finish
    state
}

trace_config_lines <- function(config, trace, events, rejected) {
    lines <- sprintf(
        "trace lines %d accepted %d rejected %d",
        length(trace),
        length(events),
        length(rejected)
    )
    for (item in rejected) lines <- c(lines, sprintf("reject line %d %s", item$number, item$reason))
    c(
        lines,
        sprintf(
            "geometry cores %d line %d l1 %d %d sets %d l2 %d %d sets %d",
            config$cores,
            config$line_size,
            config$l1_size,
            config$l1_ways,
            config$l1_sets,
            config$l2_size,
            config$l2_ways,
            config$l2_sets
        ),
        sprintf("latency l1 %d l2 %d memory %d bus %d", config$t1, config$t2, config$tm, config$tb)
    )
}

reuse_lines <- function(analyses, config) {
    lines <- character()
    labels <- c("1", "2-4", "5-16", "17-64", "65-256", "257+")
    for (record in analyses) {
        lines <- c(
            lines,
            sprintf(
                "reuse c%d accesses %d lines %d distance %s cold %d",
                record$core,
                record$accesses,
                record$lines,
                range_counts(labels, record$distances),
                record$cold
            ),
            sprintf(
                "mrc c%d lru %s opt %d:%d",
                record$core,
                range_counts(record$capacities, record$lru),
                config$cap,
                record$opt
            )
        )
    }
    lines
}

length_histogram <- function(accesses) {
    counts <- new_counter()
    labels <- c("1", "2-9", "10-29", "30-99", "100-299", "300+")
    for (event in accesses) {
        latency <- event$latency
        bucket <- if (latency == 1L) 1L else if (latency <= 9L) 2L else if (latency <= 29L) 3L else if (latency <= 99L) 4L else if (latency <= 299L) 5L else 6L
        add_count(counts, labels[bucket])
    }
    range_counts(labels, counts)
}

scenario_report <- function(state) {
    config <- state$config
    scenario <- state$scenario
    total <- state$total
    bus <- state$bus
    lines <- sprintf("scenario %s %s %s %s", scenario$name, scenario$protocol, scenario$l1, scenario$l2)
    for (index in seq_along(state$cores)) lines <- c(
        lines,
        six_lines(paste0("c", index - 1L), state$cores[[index]])
    )
    lines <- c(
        lines,
        six_lines("total", total),
        paste(
            "l2",
            count_pairs(
                c("lookups", "hits", "misses", "flushes", "writebacks", "evictions", "dirty_evictions"),
                state$l2_counters
            )
        )
    )
    transactions <- length(bus$transactions)
    busy <- config$tb * transactions
    lines <- c(
        lines,
        sprintf(
            "bus transactions %d busy %d wait %d utilization %s",
            transactions,
            busy,
            bus$wait,
            decimal_notation(100L * busy, state$finish)
        )
    )
    data_bytes <- config$line_size * sum(vapply(
        c("BusRd", "BusRdX", "WB"),
        function(kind) counter_value(total$bus, kind),
        0L
    )) + 4L * counter_value(total$bus, "BusWr")
    memory_bytes <- config$line_size * (counter_value(state$l2_counters, "misses") + counter_value(
        state$l2_counters,
        "dirty_evictions"
    ))
    lines <- c(
        lines,
        sprintf(
            "traffic command_bytes %d data_bytes %d memory_bytes %d",
            8L * transactions,
            data_bytes,
            memory_bytes
        )
    )
    snoops <- Filter(function(tx) tx$kind != "WB", bus$transactions)
    fanout <- new_counter()
    for (tx in snoops) if (tx$kind %in% c("BusRdX", "BusUpgr", "BusWr")) add_count(fanout, tx$invalidations)
    hits <- sum(vapply(snoops, function(tx) tx$snoop_hits, 0L))
    lines <- c(
        lines,
        sprintf(
            "snoops probes %d hits %d fanout %s",
            (config$cores - 1L) * length(snoops),
            hits,
            range_counts(seq_len(config$cores) - 1L, fanout)
        )
    )
    c(
        lines,
        sprintf(
            "latencies reads %d writes %d histogram %s",
            counter_value(total$simple, "read_latency"),
            counter_value(total$simple, "write_latency"),
            length_histogram(state$accesses)
        )
    )
}

ranking_lines <- function(states) {
    order_indices <- order(
        vapply(states, function(state) state$finish, 0L),
        vapply(states, function(state) length(state$bus$transactions), 0L),
        seq_along(states)
    )
    lines <- "ranking"
    for (rank in seq_along(order_indices)) {
        state <- states[[order_indices[rank]]]
        latency <- counter_value(state$total$simple, "latency")
        accesses <- counter_value(state$total$simple, "accesses")
        lines <- c(
            lines,
            sprintf(
                "%d %s finish %d transactions %d amat %s %s",
                rank,
                state$scenario$name,
                state$finish,
                length(state$bus$transactions),
                reduced_fraction(latency, accesses),
                decimal_notation(latency, accesses)
            )
        )
    }
    lines
}

hot_lines <- function(state) {
    counts <- new.env(parent = emptyenv())
    cores <- new.env(parent = emptyenv())
    for (tx in state$bus$transactions) {
        key <- as.character(tx$block)
        if (!exists(key, counts, inherits = FALSE)) counts[[key]] <- new_counter()
        add_count(counts[[key]], tx$kind)
        add_count(counts[[key]], "invalidations", tx$invalidations)
        cores[[key]] <- union(cores[[key]], tx$core)
    }
    for (event in state$accesses) {
        key <- as.character(event$block)
        if (!is.null(event$miss_kind) && exists(key, counts, inherits = FALSE)) {
            add_count(counts[[key]], "misses")
            if (event$miss_kind == "coherence") add_count(counts[[key]], "coherence")
        }
    }
    blocks <- as.integer(ls(counts))
    tx_total <- function(block) sum(vapply(
        TRANSACTION_TYPES,
        function(kind) counter_value(counts[[as.character(block)]], kind),
        0L
    ))
    totals <- vapply(blocks, tx_total, 0L)
    blocks <- head(blocks[order(-totals, blocks)], state$config$top)
    lines <- paste("hot", state$scenario$name)
    for (rank in seq_along(blocks)) {
        block <- blocks[rank]
        key <- as.character(block)
        numbers <- counts[[key]]
        lines <- c(
            lines,
            sprintf(
                "%d %s transactions %d %s misses %d coherence %d invalidations %d cores %s",
                rank,
                hex_address(block * state$config$line_size),
                tx_total(block),
                count_pairs(TRANSACTION_TYPES, numbers),
                counter_value(numbers, "misses"),
                counter_value(numbers, "coherence"),
                counter_value(numbers, "invalidations"),
                core_string(cores[[key]])
            )
        )
    }
    lines
}

interval_lines <- function(state) {
    config <- state$config
    width <- config$interval
    count <- state$finish %/% width + 1L
    accesses <- matrix(0L, count, config$cores)
    misses <- transactions <- busy <- integer(count)
    for (event in state$accesses) {
        bucket <- event$issue %/% width + 1L
        accesses[bucket, event$core + 1L] <- accesses[bucket, event$core + 1L] + 1L
        if (!is.null(event$miss_kind)) misses[bucket] <- misses[bucket] + 1L
    }
    for (tx in state$bus$transactions) {
        start <- tx$start
        stop <- tx$start + config$tb
        if (start %/% width < count) transactions[start %/% width + 1L] <- transactions[start %/% width + 1L] + 1L
        for (bucket in (start %/% width):((stop - 1L) %/% width)) {
            if (bucket < count) busy[bucket + 1L] <- busy[bucket + 1L] + max(
                0L,
                min(stop, (bucket + 1L) * width) - max(start, bucket * width)
            )
        }
    }
    lines <- sprintf("intervals %s %d", state$scenario$name, width)
    for (bucket in seq_len(count) - 1L) {
        start <- bucket * width
        lines <- c(
            lines,
            sprintf(
                "%d %d-%d accesses %s misses %d transactions %d busy %d utilization %s",
                bucket,
                start,
                start + width - 1L,
                paste(accesses[bucket + 1L, ], collapse = " "),
                misses[bucket + 1L],
                transactions[bucket + 1L],
                busy[bucket + 1L],
                decimal_notation(100L * busy[bucket + 1L], width)
            )
        )
    }
    lines
}

slowest_lines <- function(state) {
    accesses <- state$accesses
    indices <- head(
        order(
            -vapply(accesses, function(event) event$latency, 0L),
            vapply(accesses, function(event) event$number, 0L)
        ),
        state$config$top
    )
    lines <- paste("slowest", state$scenario$name)
    for (rank in seq_along(indices)) {
        event <- accesses[[indices[rank]]]
        lines <- c(
            lines,
            sprintf(
                "%d event %d cycle %d c%d %s %s latency %d service %s",
                rank,
                event$number,
                event$issue,
                event$core,
                event$operation,
                hex_address(event$address),
                event$latency,
                event$service
            )
        )
    }
    lines
}

region_for <- function(address, config) {
    for (region in config$regions) if (address >= region$low && address <= region$high) return(region$name)
    "other"
}

region_lines <- function(state) {
    config <- state$config
    names <- c(vapply(config$regions, function(region) region$name, ""), "other")
    counts <- setNames(lapply(names, function(name) new_counter()), names)
    for (event in state$accesses) {
        numbers <- counts[[region_for(event$address, config)]]
        add_count(numbers, "accesses")
        add_count(numbers, if (event$operation == "R") "reads" else "writes")
        add_count(numbers, "latency", event$latency)
        add_count(numbers, if (event$hit) "hits" else event$miss_kind)
    }
    for (tx in state$bus$transactions) add_count(
        counts[[region_for(tx$block * config$line_size, config)]],
        "transactions"
    )
    lines <- paste("regions", state$scenario$name)
    for (name in names) {
        numbers <- counts[[name]]
        accesses <- counter_value(numbers, "accesses")
        latency <- counter_value(numbers, "latency")
        amat <- if (accesses == 0L) "-" else paste(
            reduced_fraction(latency, accesses),
            decimal_notation(latency, accesses)
        )
        lines <- c(
            lines,
            paste(
                name,
                count_pairs(
                    c("accesses", "reads", "writes", "hits", MISS_TYPES, "transactions", "latency"),
                    numbers
                ),
                "amat",
                amat
            )
        )
    }
    lines
}

sharing_lines <- function(static, state) {
    blocks <- sort(as.integer(ls(static)))
    blocks <- blocks[vapply(blocks, function(block) {
        info <- static[[as.character(block)]]
        length(info$cores) >= 2L && length(info$writers) > 0L
    }, FALSE)]
    lines <- character()
    totals <- new_counter()
    for (block in blocks) {
        info <- static[[as.character(block)]]
        word_numbers <- sort(as.integer(ls(info$words)))
        true_line <- any(vapply(word_numbers, function(number) {
            word <- info$words[[as.character(number)]]
            length(word$writes) > 0L && length(union(word$reads, word$writes)) >= 2L
        }, FALSE))
        true_miss <- counter_value(state$shared_misses, paste(block, "true_sharing"))
        false_miss <- counter_value(state$shared_misses, paste(block, "false_sharing"))
        add_count(totals, "coherence", true_miss + false_miss)
        add_count(totals, "true", true_miss)
        add_count(totals, "false", false_miss)
        add_count(totals, if (true_line) "true_lines" else "false_lines")
        words <- paste(vapply(word_numbers, function(number) {
            word <- info$words[[as.character(number)]]
            sprintf("w%d=%s/%s", number, core_string(word$reads), core_string(word$writes))
        }, ""), collapse = " ")
        lines <- c(
            lines,
            sprintf(
                "%s %s cores %s writers %s reads %d writes %d handoffs %d coherence %d true %d false %d words %s",
                hex_address(block * state$config$line_size),
                if (true_line) "true" else "false",
                core_string(info$cores),
                core_string(info$writers),
                counter_value(info$counts, "reads"),
                counter_value(info$counts, "writes"),
                counter_value(state$handoffs, block),
                true_miss + false_miss,
                true_miss,
                false_miss,
                words
            )
        )
    }
    lines <- c(
        lines,
        sprintf(
            "lines %d %s",
            length(blocks),
            count_pairs(c("true_lines", "false_lines", "coherence", "true", "false"), totals)
        ),
        "communication"
    )
    for (core in seq_len(state$config$cores) - 1L) lines <- c(
        lines,
        paste0("c", core, " ", paste(state$communications[core + 1L, ], collapse = " "))
    )
    lines
}

final_state_lines <- function(state) {
    config <- state$config
    lines <- character()
    caches <- c(state$l1, list(state$l2))
    for (index in seq_along(caches)) {
        cache <- caches[[index]]
        label <- if (index <= config$cores) paste0("c", index - 1L) else "L2"
        for (row in seq_len(cache$number_sets)) {
            ways <- vapply(seq_len(cache$ways), function(way) {
                if (cache$blocks[row, way] == -1L) "-" else paste0(
                    hex_address(cache$blocks[row, way] * config$line_size),
                    ":",
                    cache$states[row, way]
                )
            }, "")
            lines <- c(
                lines,
                sprintf(
                    "%s %d %s %s %s fills %d evictions %d",
                    label,
                    row - 1L,
                    paste(ways, collapse = " "),
                    tolower(cache$replacement),
                    cache_order(cache, row),
                    cache$fills[row],
                    cache$evictions[row]
                )
            )
        }
        entries <- cache_lines(cache)
        counts <- new_counter()
        for (item in entries) add_count(counts, item$state)
        if (index <= config$cores) {
            lines <- c(
                lines,
                sprintf(
                    "%s lines %d %s",
                    label,
                    length(entries),
                    count_pairs(c("M", "O", "E", "S", "V"), counts)
                )
            )
        } else {
            resident <- unique(unlist(
                lapply(state$l1, function(l1) vapply(cache_lines(l1), function(item) item$block, 0L)),
                use.names = FALSE
            ))
            lines <- c(
                lines,
                sprintf(
                    "L2 lines %d dirty %d clean %d in_l1 %d",
                    length(entries),
                    counter_value(counts, "D"),
                    counter_value(counts, "C"),
                    length(resident)
                )
            )
        }
    }
    lines
}

main <- function() {
    config <- read_config()
    trace <- read_trace()
    validated <- validate_trace(trace, config)
    events <- validated$events
    rejected <- validated$rejected
    reuse <- reuse_analysis(events, config)
    static <- static_sharing(events)
    states <- lapply(
        config$scenarios,
        function(scenario) simulate(config, scenario, events, scenario$name == config$primary)
    )
    primary <- Filter(function(state) state$scenario$name == config$primary, states)[[1L]]
    sections <- c(
        list(trace_config_lines(config, trace, events, rejected), reuse_lines(reuse, config)),
        lapply(states, scenario_report),
        list(
            ranking_lines(states),
            hot_lines(primary),
            interval_lines(primary),
            slowest_lines(primary),
            region_lines(primary)
        )
    )
    lines <- character()
    for (index in seq_along(sections)) {
        if (index > 1L) lines <- c(lines, "")
        lines <- c(lines, sections[[index]])
    }
    write_lines("stats.txt", lines)
    write_lines("bus_log.txt", vapply(primary$bus$transactions, bus_line, "", line_size = config$line_size))
    write_lines("watch.txt", primary$watch_lines)
    write_lines("sharing.txt", sharing_lines(static, primary))
    write_lines("final_state.txt", final_state_lines(primary))
}

main()
