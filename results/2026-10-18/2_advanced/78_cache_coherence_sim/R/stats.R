TRANSACTION_TYPES <- c("BusRd", "BusRdX", "BusUpgr", "BusWr", "WB")
SERVICE_TYPES <- c("l1", "upgrade", "through", "cache", "l2", "memory")
MISS_TYPES <- c("compulsory", "capacity", "conflict", "coherence")
SNOOP_COUNTERS <- c("invalidations_sent", "invalidations_received", "supplied", "back_invalidations")

new_counter <- function() new.env(parent = emptyenv())
counter_value <- function(counters, key) {
    value <- counters[[as.character(key)]]
    if (is.null(value)) 0L else value
}
add_count <- function(
    counters,
    key,
    amount = 1L
) counters[[as.character(key)]] <- counter_value(counters, key) + amount

reduced_fraction <- function(p, q) {
    a <- p
    b <- q
    while (b != 0L) {
        remainder <- a %% b
        a <- b
        b <- remainder
    }
    paste0(p %/% a, "/", q %/% a)
}

decimal_notation <- function(p, q) {
    value <- (2L * p * 100L + q) %/% (2L * q)
    sprintf("%d.%02d", value %/% 100L, value %% 100L)
}

core_string <- function(cores) if (length(cores)) paste0(sort(unique(cores)), collapse = "") else "-"
range_counts <- function(keys, counts) paste(
    vapply(keys, function(key) paste0(key, ":", counter_value(counts, key)), ""),
    collapse = " "
)
count_pairs <- function(keys, counts) paste(
    vapply(keys, function(key) paste(key, counter_value(counts, key)), ""),
    collapse = " "
)

new_core_counters <- function() {
    entry <- new.env(parent = emptyenv())
    for (key in c("simple", "misses", "service", "bus", "snoop")) entry[[key]] <- new_counter()
    entry$finish <- 0L
    entry
}

total_counters <- function(per_core) {
    total <- new_core_counters()
    for (item in per_core) {
        for (section in c("simple", "misses", "service", "bus", "snoop")) {
            for (key in ls(item[[section]], all.names = TRUE)) add_count(
                total[[section]],
                key,
                item[[section]][[key]]
            )
        }
        total$finish <- max(total$finish, item$finish)
    }
    total
}

six_lines <- function(label, entry) {
    latency <- counter_value(entry$simple, "latency")
    accesses <- counter_value(entry$simple, "accesses")
    c(paste(label, count_pairs(c("accesses", "reads", "writes", "hits", "misses", "fences"), entry$simple)),
      paste(label, "misses", count_pairs(c(MISS_TYPES, "true_sharing", "false_sharing"), entry$misses)),
      paste(label, "service", count_pairs(SERVICE_TYPES, entry$service)),
      paste(label, "bus", count_pairs(TRANSACTION_TYPES, entry$bus)),
      paste(label, "snoop", count_pairs(SNOOP_COUNTERS, entry$snoop)),
      sprintf(
          "%s time latency %d amat %s %s fence_stall %d finish %d",
          label,
          latency,
          reduced_fraction(latency, accesses),
          decimal_notation(latency, accesses),
          counter_value(entry$simple, "fence_stall"),
          entry$finish
      ))
}
