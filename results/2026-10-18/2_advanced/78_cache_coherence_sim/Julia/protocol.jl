const DIRTY_STATES = Set(["M", "O"])

function requester_transition(protocol, old, operation, other_copy)
    if protocol == "VI"
        operation == "R" && return old == "I" ? ("BusRd", "V") : (nothing, "V")
        return "BusWr", old == "I" ? "I" : "V"
    end
    if old == "I"
        operation == "W" && return "BusRdX", "M"
        return "BusRd", protocol == "MSI" || other_copy ? "S" : "E"
    end
    operation == "R" && return nothing, old
    old in ("M", "E") && return nothing, "M"
    return "BusUpgr", "M"
end

function snoop_transition(protocol, old, transaction)
    if protocol == "VI"
        return transaction == "BusRd" ? ("V", false, false) : ("I", false, false)
    end
    if transaction == "BusRd"
        old == "M" && return protocol == "MOESI" ? ("O", true, false) : ("S", true, true)
        old == "O" && return "O", true, false
        return "S", false, false
    end
    return "I", transaction == "BusRdX" && old in DIRTY_STATES, false
end
