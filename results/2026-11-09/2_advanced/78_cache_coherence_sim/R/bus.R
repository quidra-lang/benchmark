new_bus <- function(latency) {
    bus <- new.env(parent = emptyenv())
    bus$latency <- latency
    bus$free <- bus$wait <- 0L
    bus$transactions <- list()
    bus
}

bus_assign <- function(bus, core, kind, block, requested) {
    start <- max(requested, bus$free)
    bus$wait <- bus$wait + start - requested
    bus$free <- start + bus$latency
    tx <- new.env(parent = emptyenv())
    tx$number <- length(bus$transactions) + 1L
    tx$start <- start
    tx$core <- core
    tx$kind <- kind
    tx$block <- block
    tx$snoops <- character()
    tx$snoop_hits <- tx$invalidations <- 0L
    tx$supplier <- -1L
    tx$flushed <- FALSE
    tx$l2 <- tx$source <- ""
    tx$eviction <- NULL
    bus$transactions[[length(bus$transactions) + 1L]] <- tx
    tx
}

bus_line <- function(tx, line_size) {
    output <- sprintf(
        "%d %d c%d %s %s",
        tx$number,
        tx$start,
        tx$core,
        tx$kind,
        hex_address(tx$block * line_size)
    )
    if (tx$kind == "WB") return(output)
    output <- paste(output, "snoop", if (length(tx$snoops)) paste(tx$snoops, collapse = " ") else "none")
    if (tx$kind == "BusUpgr") return(output)
    if (tx$kind %in% c("BusRd", "BusRdX")) output <- paste(output, "data", tx$source)
    output <- paste(output, "l2", tx$l2)
    if (!is.null(tx$eviction)) {
        evicted <- tx$eviction
        copies <- if (length(evicted$copies)) paste(evicted$copies, collapse = " ") else "none"
        output <- paste(
            output,
            "evict",
            hex_address(evicted$block * line_size),
            copies,
            if (evicted$dirty) "dirty" else "clean"
        )
    }
    output
}
