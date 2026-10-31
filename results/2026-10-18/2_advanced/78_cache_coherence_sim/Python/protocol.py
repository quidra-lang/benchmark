"""Requester and snooping transitions for VI, MSI, MESI and MOESI."""

DIRTY = {"M", "O"}


def requester(protocol, old, op, other_has_line):
    """Return (transaction or None, new state) before bus processing."""
    if protocol == "VI":
        if op == "R":
            return ("BusRd", "V") if old == "I" else (None, "V")
        return ("BusWr", "I" if old == "I" else "V")

    if old == "I":
        if op == "W":
            return "BusRdX", "M"
        if protocol in ("MESI", "MOESI"):
            return "BusRd", "S" if other_has_line else "E"
        return "BusRd", "S"
    if op == "R":
        return None, old
    if old in ("M", "E"):
        return None, "M"
    if old in ("S", "O"):
        return "BusUpgr", "M"
    raise ValueError((protocol, old, op))


def snoop(protocol, old, transaction):
    """Return (new state, supply data, flush data into L2)."""
    if protocol == "VI":
        if transaction == "BusRd":
            return "V", False, False
        if transaction == "BusWr":
            return "I", False, False
    if transaction == "BusRd":
        if old == "M":
            if protocol == "MOESI":
                return "O", True, False
            return "S", True, True
        if old == "O":
            return "O", True, False
        if old == "E":
            return "S", False, False
        return "S", False, False
    if transaction == "BusRdX":
        return "I", old in DIRTY, False
    if transaction == "BusUpgr":
        return "I", False, False
    if transaction == "BusWr":
        return "I", False, False
    raise ValueError((protocol, old, transaction))
