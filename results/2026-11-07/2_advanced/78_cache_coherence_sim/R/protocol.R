DIRTY_STATES <- c("M", "O")

requester_transition <- function(protocol, old, operation, other_copy) {
    if (protocol == "VI") {
        if (operation == "R") return(list(kind = if (old == "I") "BusRd" else NULL, state = "V"))
        return(list(kind = "BusWr", state = if (old == "I") "I" else "V"))
    }
    if (old == "I") {
        if (operation == "W") return(list(kind = "BusRdX", state = "M"))
        return(list(kind = "BusRd", state = if (protocol == "MSI" || other_copy) "S" else "E"))
    }
    if (operation == "R") return(list(kind = NULL, state = old))
    if (old %in% c("M", "E")) return(list(kind = NULL, state = "M"))
    list(kind = "BusUpgr", state = "M")
}

snoop_transition <- function(protocol, old, transaction) {
    if (protocol == "VI") return(list(
        state = if (transaction == "BusRd") "V" else "I",
        supply = FALSE,
        flush = FALSE
    ))
    if (transaction == "BusRd") {
        if (old == "M") return(list(
            state = if (protocol == "MOESI") "O" else "S",
            supply = TRUE,
            flush = protocol != "MOESI"
        ))
        if (old == "O") return(list(state = "O", supply = TRUE, flush = FALSE))
        return(list(state = "S", supply = FALSE, flush = FALSE))
    }
    list(state = "I", supply = transaction == "BusRdX" && old %in% DIRTY_STATES, flush = FALSE)
}
