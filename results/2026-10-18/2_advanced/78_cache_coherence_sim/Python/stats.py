"""Per-core performance counters and integer-only report notation."""

from collections import Counter
from math import gcd


TRANSACTIONS = ("BusRd", "BusRdX", "BusUpgr", "BusWr", "WB")
SERVICES = ("l1", "upgrade", "through", "cache", "l2", "memory")
MISSES = ("compulsory", "capacity", "conflict", "coherence")
SNOOP_COUNTERS = (
    "invalidations_sent", "invalidations_received", "supplied",
    "back_invalidations",
)
SIMPLE = ("accesses", "reads", "writes", "hits", "misses", "fences",
          "latency", "fence_stall", "read_latency", "write_latency")


def fraction(p, q):
    factor = gcd(p, q)
    return f"{p // factor}/{q // factor}"


def decimal(p, q):
    value = (2 * p * 100 + q) // (2 * q)
    return f"{value // 100}.{value % 100:02d}"


def core_string(cores):
    ordered = sorted(cores)
    return "".join(str(core) for core in ordered) if ordered else "-"


def empty_counters():
    return {
        "simple": Counter(),
        "misses": Counter(),
        "service": Counter(),
        "bus": Counter(),
        "snoop": Counter(),
        "finish": 0,
    }


def total_counters(per_core):
    total = empty_counters()
    for item in per_core:
        for section in ("simple", "misses", "service", "bus", "snoop"):
            total[section].update(item[section])
        total["finish"] = max(total["finish"], item["finish"])
    return total


def six_lines(label, entry):
    s = entry["simple"]
    misses, services = entry["misses"], entry["service"]
    bus, snoop = entry["bus"], entry["snoop"]
    length, accesses = s["latency"], s["accesses"]
    return [
        f"{label} accesses {s['accesses']} reads {s['reads']} "
        f"writes {s['writes']} hits {s['hits']} misses {s['misses']} "
        f"fences {s['fences']}",
        f"{label} misses compulsory {misses['compulsory']} "
        f"capacity {misses['capacity']} conflict {misses['conflict']} "
        f"coherence {misses['coherence']} "
        f"true_sharing {misses['true_sharing']} "
        f"false_sharing {misses['false_sharing']}",
        f"{label} service " + " ".join(
            f"{kind} {services[kind]}" for kind in SERVICES
        ),
        f"{label} bus " + " ".join(
            f"{kind} {bus[kind]}" for kind in TRANSACTIONS
        ),
        f"{label} snoop " + " ".join(
            f"{kind} {snoop[kind]}" for kind in SNOOP_COUNTERS
        ),
        f"{label} time latency {length} "
        f"amat {fraction(length, accesses)} {decimal(length, accesses)} "
        f"fence_stall {s['fence_stall']} finish {entry['finish']}",
    ]
