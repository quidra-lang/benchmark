"""Single shared snooping bus, transaction assignment and its log."""

from config_io import hex_address


class Bus:
    def __init__(self, latency, cores):
        self.latency = latency
        self.core_count = cores
        self.free = 0
        self.wait = 0
        self.transactions = []

    def assign(self, core, kind, block, requested):
        """Reserve TB cycles, preserving transaction assignment order."""
        start = max(requested, self.free)
        self.wait += start - requested
        self.free = start + self.latency
        transaction = {
            "number": len(self.transactions) + 1,
            "start": start, "core": core, "kind": kind,
            "block": block, "snoop": [], "snoop_hits": 0,
            "invalidations": 0, "supplier": None,
            "flush": False, "l2": None, "eviction": None,
            "source": None,
        }
        self.transactions.append(transaction)
        return transaction

    def line(self, transaction, line_size):
        tx = transaction
        prefix = (
            f"{tx['number']} {tx['start']} c{tx['core']} "
            f"{tx['kind']} {hex_address(tx['block'] * line_size)}"
        )
        if tx["kind"] == "WB":
            return prefix
        snoops = " ".join(tx["snoop"]) if tx["snoop"] else "none"
        output = prefix + " snoop " + snoops
        if tx["kind"] == "BusUpgr":
            return output
        if tx["kind"] in ("BusRd", "BusRdX"):
            output += " data " + tx["source"]
        output += " l2 " + tx["l2"]
        if tx["eviction"] is not None:
            evicted = tx["eviction"]
            copies = " ".join(evicted["copies"]) if evicted["copies"] else "none"
            quality = "dirty" if evicted["dirty"] else "clean"
            output += (
                f" evict {hex_address(evicted['block'] * line_size)} "
                f"{copies} {quality}"
            )
        return output
