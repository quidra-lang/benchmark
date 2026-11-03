"""Cycle-accurate integer-only multi-core coherence simulator.

The entry point reads configuration and accesses in input/ and produces five
reports under output/. Cache state transitions, bus ordering and statistics
are kept independent for each configured scenario.
"""

from collections import Counter, defaultdict

from bus import Bus
from cache import Cache
from config_io import (
    decimal_integer, hex_address, read_config, read_trace,
    valid_hex_address, write_lines,
)
from protocol import DIRTY, requester, snoop
from stats import (
    MISSES, TRANSACTIONS, core_string, decimal, empty_counters,
    fraction, six_lines, total_counters,
)


def validate_trace(lines, config):
    """Apply the six validation rules in order, retaining accepted-line cycles."""
    accepted = []
    rejected = []
    latest = 0
    for lineno, line in enumerate(lines, 1):
        words = line.split(" ")
        reason = None
        if len(words) not in (3, 4) or "" in words:
            reason = "fields"
        elif not decimal_integer(words[0], 7):
            reason = "cycle"
        elif not decimal_integer(words[1]) or int(words[1]) >= config["cores"]:
            reason = "core"
        elif words[2] not in ("R", "W", "FENCE") or (
                words[2] == "FENCE" and len(words) != 3) or (
                words[2] != "FENCE" and len(words) != 4):
            reason = "op"
        elif words[2] != "FENCE" and (
                not valid_hex_address(words[3]) or
                int(words[3], 16) % 4 != 0 or
                int(words[3], 16) > 0x7fffffff):
            reason = "address"
        elif int(words[0]) < latest:
            reason = "order"
        if reason:
            rejected.append((lineno, reason))
            continue
        cycle, core = int(words[0]), int(words[1])
        latest = cycle
        event = {
            "number": len(accepted) + 1,
            "line": lineno,
            "cycle": cycle,
            "core": core,
            "op": words[2],
        }
        if words[2] != "FENCE":
            address = int(words[3], 16)
            event.update({
                "address": address,
                "block": address // config["line"],
                "word": (address % config["line"]) // 4,
                "distance": None,
            })
        accepted.append(event)
    return accepted, rejected


def per_core_events(events, number_cores):
    """Preserve event-number order separately within each core."""
    result = [[] for _ in range(number_cores)]
    for event in events:
        result[event["core"]].append(event)
    return result


def reuse_analysis(events, config):
    """Compute per-core stack distances, LRU miss curves, and Belady OPT."""
    by_core = per_core_events(events, config["cores"])
    analyses = []
    capacities = [
        config["cap"] // 4, config["cap"] // 2, config["cap"],
        2 * config["cap"], 4 * config["cap"],
    ]
    for ordered in by_core:
        accesses = [event for event in ordered if event["op"] != "FENCE"]
        blocks = [event["block"] for event in accesses]
        stack = []
        cold = 0
        distances = Counter()
        miss_curve = {capacity: 0 for capacity in capacities}
        for event in accesses:
            block = event["block"]
            if block not in stack:
                cold += 1
                distance = None
            else:
                distance = stack.index(block) + 1
                stack.remove(block)
                if distance == 1:
                    distances["1"] += 1
                elif distance <= 4:
                    distances["2-4"] += 1
                elif distance <= 16:
                    distances["5-16"] += 1
                elif distance <= 64:
                    distances["17-64"] += 1
                elif distance <= 256:
                    distances["65-256"] += 1
                else:
                    distances["257+"] += 1
            event["distance"] = distance
            for capacity in capacities:
                if distance is None or distance > capacity:
                    miss_curve[capacity] += 1
            stack.insert(0, block)

        future_positions = defaultdict(list)
        for index, block in enumerate(blocks):
            future_positions[block].append(index)
        remaining = {
            block: list(indices) for block, indices in future_positions.items()
        }
        opt_lines = set()
        opt_misses = 0
        for index, block in enumerate(blocks):
            remaining[block].pop(0)
            if block in opt_lines:
                continue
            opt_misses += 1
            if len(opt_lines) == config["cap"]:
                def future_priority(line):
                    next_position = (
                        remaining[line][0] if remaining[line]
                        else len(blocks) + 1
                    )
                    return next_position, -line
                victim = max(opt_lines, key=future_priority)
                opt_lines.remove(victim)
            opt_lines.add(block)
        analyses.append({
            "core": core,
            "accesses": len(accesses),
            "lines": len(set(blocks)),
            "distances": distances,
            "cold": cold,
            "lru": miss_curve,
            "capacities": capacities,
            "opt": opt_misses,
        })
    return analyses


def static_sharing(events):
    """Build line/word read and write sets and access counts from the trace."""
    lines = {}
    for event in events:
        if event["op"] == "FENCE":
            continue
        block = event["block"]
        core = event["core"]
        info = lines.setdefault(block, {
            "cores": set(), "writers": set(),
            "reads": 0, "writes": 0,
            "words": {},
        })
        info["cores"].add(core)
        if event["op"] == "W":
            info["writers"].add(core)
            info["writes"] += 1
        else:
            info["reads"] += 1
        word = info["words"].setdefault(event["word"], {
            "reads": set(), "writes": set(),
        })
        word["writes" if event["op"] == "W" else "reads"].add(core)
    for info in lines.values():
        info["shared"] = len(info["cores"]) >= 2 and bool(info["writers"])
        info["true"] = any(
            entry["writes"] and len(entry["reads"] | entry["writes"]) >= 2
            for entry in info["words"].values()
        )
    return lines


def initial_state(config, scenario, events):
    """Create independent cache, bus, core and event scheduling state."""
    grouped = per_core_events(events, config["cores"])
    return {
        "config": config, "scenario": scenario,
        "l1": [
            Cache(config["l1_sets"], config["l1_ways"], scenario["l1"])
            for _ in range(config["cores"])
        ],
        "l2": Cache(config["l2_sets"], config["l2_ways"], scenario["l2"]),
        "bus": Bus(config["tb"], config["cores"]),
        "cores": [empty_counters() for _ in range(config["cores"])],
        "event_lists": grouped,
        "indices": [0] * config["cores"],
        "ready": [0] * config["cores"],
        "write_completion": [0] * config["cores"],
        "seen": [set() for _ in range(config["cores"])],
        "invalidations": {},
        "l2_counters": Counter(),
        "processed_accesses": [],
        "watch_lines": [],
        "handoffs": Counter(),
        "last_writer": {},
        "word_state": {},
        "communications": [
            [0] * config["cores"] for _ in range(config["cores"])
        ],
        "shared_misses": Counter(),
    }


def line_states(state, block):
    """The watched tuple contains all L1 states followed by the L2 state."""
    return tuple(cache.state(block) for cache in state["l1"]) + (
        state["l2"].state(block),
    )


def access_issue(event, state):
    """Obtain the issue cycle of one core's next event."""
    return max(event["cycle"], state["ready"][event["core"]])


def next_event(state):
    candidates = []
    for core, ordered in enumerate(state["event_lists"]):
        index = state["indices"][core]
        if index < len(ordered):
            event = ordered[index]
            candidates.append((access_issue(event, state), core, event))
    return min(candidates) if candidates else None


def issue_transaction(state, core, kind, block, request_cycle):
    """Reserve the bus, credit requester traffic, and append its numbered record."""
    transaction = state["bus"].assign(core, kind, block, request_cycle)
    state["cores"][core]["bus"][kind] += 1
    if kind == "WB":
        state["l2_counters"]["writebacks"] += 1
    return transaction


def snoop_others(state, tx, word):
    """Apply the other cores' protocol transitions in increasing core order."""
    block, requester_core = tx["block"], tx["core"]
    for core, cache in enumerate(state["l1"]):
        if core == requester_core:
            continue
        old = cache.state(block)
        if old == "I":
            continue
        updated, supplies, flushed = snoop(
            state["scenario"]["protocol"], old, tx["kind"]
        )
        tx["snoop"].append(f"c{core}:{old}>{updated}")
        tx["snoop_hits"] += 1
        if updated == "I":
            cache.remove(block)
            tx["invalidations"] += 1
            state["cores"][requester_core]["snoop"]["invalidations_sent"] += 1
            state["cores"][core]["snoop"]["invalidations_received"] += 1
            # All invalidating coherence transactions here are write requests.
            state["invalidations"][(core, block)] = {word}
        else:
            cache.change(block, updated)
        if supplies:
            tx["supplier"] = core
            state["cores"][core]["snoop"]["supplied"] += 1
        if flushed:
            tx["flush"] = True
    if tx["flush"]:
        state["l2_counters"]["flushes"] += 1


def access_l2(state, transaction):
    """Lookup/fill inclusive L2; evicted lines back-invalidate all L1 copies."""
    config = state["config"]
    cache = state["l2"]
    block = transaction["block"]
    state["l2_counters"]["lookups"] += 1
    if cache.state(block) != "I":
        transaction["l2"] = "hit"
        state["l2_counters"]["hits"] += 1
        cache.touch(block)
    else:
        transaction["l2"] = "miss"
        state["l2_counters"]["misses"] += 1
        evicted = cache.fill(block, "C")
        if evicted is not None:
            old_block = evicted["block"]
            copies = []
            dirty = evicted["state"] == "D"
            for core, l1 in enumerate(state["l1"]):
                old_state = l1.state(old_block)
                if old_state == "I":
                    continue
                l1.remove(old_block)
                copies.append(f"c{core}:{old_state}")
                state["cores"][core]["snoop"]["back_invalidations"] += 1
                if old_state in DIRTY:
                    dirty = True
            transaction["eviction"] = {
                "block": old_block, "copies": copies, "dirty": dirty,
            }
            state["l2_counters"]["evictions"] += 1
            if dirty:
                state["l2_counters"]["dirty_evictions"] += 1
    if transaction["flush"] or transaction["kind"] == "BusWr":
        cache.change(block, "D")


def run_bus_transaction(state, core, kind, block, word, request_cycle):
    """Snoop, access L2 where needed, and compute the data-ready cycle."""
    tx = issue_transaction(state, core, kind, block, request_cycle)
    snoop_others(state, tx, word)
    if kind != "BusUpgr":
        access_l2(state, tx)
    start, bus_time = tx["start"], state["config"]["tb"]
    if kind == "BusUpgr":
        completion = start + bus_time
    elif kind == "BusWr":
        completion = start + bus_time + state["config"]["t2"]
        if tx["l2"] == "miss":
            completion += state["config"]["tm"]
    elif tx["supplier"] is not None:
        completion = start + bus_time
        tx["source"] = f"c{tx['supplier']}"
    elif tx["l2"] == "hit":
        completion = start + bus_time + state["config"]["t2"]
        tx["source"] = "L2"
    else:
        completion = (start + bus_time + state["config"]["t2"]
                      + state["config"]["tm"])
        tx["source"] = "mem"
    return completion, tx


def write_back(state, core, old_line):
    """Dirty L1 evictions use a WB immediately after the current bus transaction."""
    bus = state["bus"]
    tx = issue_transaction(
        state, core, "WB", old_line["block"], bus.free
    )
    state["l2"].touch(old_line["block"])
    state["l2"].change(old_line["block"], "D")
    return tx


def classify_miss(state, event):
    core = event["core"]
    block = event["block"]
    record = state["invalidations"].get((core, block))
    if block not in state["seen"][core]:
        return "compulsory", None
    if record is not None:
        share = "true_sharing" if event["word"] in record else "false_sharing"
        return "coherence", share
    if event["distance"] > state["config"]["cap"]:
        return "capacity", None
    return "conflict", None


def communicate(state, event):
    """Track handoffs of writes and distinct read-after-write communications."""
    block, word, core = event["block"], event["word"], event["core"]
    key = (block, word)
    previous, readers = state["word_state"].get(key, (None, set()))
    if event["op"] == "W":
        former_writer = state["last_writer"].get(block)
        if former_writer is not None and former_writer != core:
            state["handoffs"][block] += 1
        state["last_writer"][block] = core
        state["word_state"][key] = (core, set())
    elif previous is not None and previous != core and core not in readers:
        state["communications"][previous][core] += 1
        readers.add(core)
        state["word_state"][key] = (previous, readers)


def render_watch(state, event, issue, before):
    config = state["config"]
    for block in config["watch"]:
        after = line_states(state, block)
        if block != event["block"] and before[block] == after:
            continue
        state_columns = " ".join(
            f"c{core}:{after[core]}" for core in range(config["cores"])
        )
        state["watch_lines"].append(
            f"{event['number']} {issue} c{event['core']} "
            f"{event['op']} {hex_address(event['address'])} "
            f"line {hex_address(block * config['line'])} "
            f"{state_columns} L2:{after[-1]}"
        )


def handle_access(state, event, issue, primary):
    """Perform the seven access steps in order, including deferred write timing."""
    config = state["config"]
    core = event["core"]
    block, word, op = event["block"], event["word"], event["op"]
    counters = state["cores"][core]
    cache = state["l1"][core]
    before = (
        {block: line_states(state, block) for block in config["watch"]}
        if primary else None
    )
    old = cache.state(block)
    hit = old != "I"
    counters["simple"]["accesses"] += 1
    counters["simple"]["reads" if op == "R" else "writes"] += 1
    counters["simple"]["hits" if hit else "misses"] += 1

    other_copy = any(
        other.state(block) != "I" for k, other in enumerate(state["l1"])
        if k != core
    )
    transaction_kind, new = requester(
        state["scenario"]["protocol"], old, op, other_copy
    )
    if hit:
        cache.touch(block)
        miss_kind = None
        sharing = None
    else:
        miss_kind, sharing = classify_miss(state, event)
        counters["misses"][miss_kind] += 1
        if sharing:
            counters["misses"][sharing] += 1
            state["shared_misses"][(block, sharing)] += 1

    state["seen"][core].add(block)
    if op == "W":
        for (other, other_block), words in state["invalidations"].items():
            if other != core and other_block == block:
                words.add(word)
    if primary:
        communicate(state, event)

    if transaction_kind is None:
        completion = issue + config["t1"]
        transaction = None
        service = "l1"
    else:
        completion, transaction = run_bus_transaction(
            state, core, transaction_kind, block, word, issue + config["t1"]
        )
        if transaction_kind == "BusUpgr":
            service = "upgrade"
        elif transaction_kind == "BusWr":
            service = "through"
        elif transaction["supplier"] is not None:
            service = "cache"
        elif transaction["l2"] == "hit":
            service = "l2"
        else:
            service = "memory"

    if old != "I":
        cache.change(block, new)
    elif new != "I":
        evicted = cache.fill(block, new)
        state["invalidations"].pop((core, block), None)
        if evicted is not None and evicted["state"] in DIRTY:
            write_back(state, core, evicted)

    latency = completion - issue
    counters["service"][service] += 1
    counters["simple"]["latency"] += latency
    if op == "R":
        counters["simple"]["read_latency"] += latency
        state["ready"][core] = completion
    else:
        counters["simple"]["write_latency"] += latency
        state["ready"][core] = issue + config["t1"]
        state["write_completion"][core] = max(
            state["write_completion"][core], completion
        )
    counters["finish"] = max(counters["finish"], completion)

    state["processed_accesses"].append({
        "number": event["number"], "issue": issue,
        "core": core, "op": op, "address": event["address"],
        "block": block, "word": word,
        "latency": latency, "service": service,
        "miss_kind": miss_kind, "hit": hit,
    })
    if primary:
        render_watch(state, event, issue, before)


def handle_fence(state, event, issue):
    core = event["core"]
    counters = state["cores"][core]
    completion = max(issue, state["write_completion"][core])
    counters["simple"]["fences"] += 1
    counters["simple"]["fence_stall"] += completion - issue
    counters["finish"] = max(counters["finish"], completion)
    state["ready"][core] = completion


def simulate(config, scenario, events, primary):
    """Select the ready core and process exactly one of its queued events."""
    state = initial_state(config, scenario, events)
    while True:
        chosen = next_event(state)
        if chosen is None:
            break
        issue, core, event = chosen
        state["indices"][core] += 1
        if event["op"] == "FENCE":
            handle_fence(state, event, issue)
        else:
            handle_access(state, event, issue, primary)
    state["total"] = total_counters(state["cores"])
    state["finish"] = state["total"]["finish"]
    return state


def format_trace_config(config, lines, events, rejected):
    result = [
        f"trace lines {len(lines)} accepted {len(events)} rejected {len(rejected)}"
    ]
    for number, reason in rejected:
        result.append(f"reject line {number} {reason}")
    result.extend([
        f"geometry cores {config['cores']} line {config['line']} "
        f"l1 {config['l1_size']} {config['l1_ways']} sets {config['l1_sets']} "
        f"l2 {config['l2_size']} {config['l2_ways']} sets {config['l2_sets']}",
        f"latency l1 {config['t1']} l2 {config['t2']} "
        f"memory {config['tm']} bus {config['tb']}",
    ])
    return result


def format_reuse(analyses, config):
    """One reuse histogram and miss-ratio curve for every core."""
    result = []
    for record in analyses:
        histogram = record["distances"]
        core = record["core"]
        result.append(
            f"reuse c{core} accesses {record['accesses']} "
            f"lines {record['lines']} distance "
            + " ".join(
                f"{bucket}:{histogram[bucket]}" for bucket in (
                    "1", "2-4", "5-16", "17-64", "65-256", "257+"
                )
            ) + f" cold {record['cold']}"
        )
        result.append(
            f"mrc c{core} lru " + " ".join(
                f"{capacity}:{record['lru'][capacity]}"
                for capacity in record["capacities"]
            ) + f" opt {config['cap']}:{record['opt']}"
        )
    return result


def length_histogram(accesses):
    values = Counter()
    for event in accesses:
        latency = event["latency"]
        key = (
            "1" if latency == 1 else "2-9" if latency <= 9
            else "10-29" if latency <= 29
            else "30-99" if latency <= 99
            else "100-299" if latency <= 299
            else "300+"
        )
        values[key] += 1
    return " ".join(
        f"{key}:{values[key]}"
        for key in ("1", "2-9", "10-29", "30-99", "100-299", "300+")
    )


def scenario_report(state):
    """Summarize all cores, traffic, snoops, latency and transaction rates."""
    config, scenario = state["config"], state["scenario"]
    bus = state["bus"]
    total = state["total"]
    lines = [
        f"scenario {scenario['name']} {scenario['protocol']} "
        f"{scenario['l1']} {scenario['l2']}"
    ]
    for core, counters in enumerate(state["cores"]):
        lines.extend(six_lines(f"c{core}", counters))
    lines.extend(six_lines("total", total))

    l2 = state["l2_counters"]
    lines.append(
        f"l2 lookups {l2['lookups']} hits {l2['hits']} "
        f"misses {l2['misses']} flushes {l2['flushes']} "
        f"writebacks {l2['writebacks']} evictions {l2['evictions']} "
        f"dirty_evictions {l2['dirty_evictions']}"
    )
    transactions = len(bus.transactions)
    busy = config["tb"] * transactions
    lines.append(
        f"bus transactions {transactions} busy {busy} wait {bus.wait} "
        f"utilization {decimal(100 * busy, state['finish'])}"
    )
    kinds = total["bus"]
    data_bytes = (
        config["line"] * (kinds["BusRd"] + kinds["BusRdX"] + kinds["WB"])
        + 4 * kinds["BusWr"]
    )
    memory_bytes = config["line"] * (
        l2["misses"] + l2["dirty_evictions"]
    )
    lines.append(
        f"traffic command_bytes {8 * transactions} "
        f"data_bytes {data_bytes} memory_bytes {memory_bytes}"
    )
    snoop_transactions = [
        tx for tx in bus.transactions if tx["kind"] != "WB"
    ]
    fanout = Counter(
        tx["invalidations"] for tx in snoop_transactions
        if tx["kind"] in ("BusRdX", "BusUpgr", "BusWr")
    )
    lines.append(
        f"snoops probes {(config['cores'] - 1) * len(snoop_transactions)} "
        f"hits {sum(tx['snoop_hits'] for tx in snoop_transactions)} "
        f"fanout " + " ".join(
            f"{amount}:{fanout[amount]}" for amount in range(config["cores"])
        )
    )
    lines.append(
        f"latencies reads {total['simple']['read_latency']} "
        f"writes {total['simple']['write_latency']} "
        f"histogram {length_histogram(state['processed_accesses'])}"
    )
    return lines


def rank_scenarios(states):
    ordered = sorted(
        states, key=lambda state: (
            state["finish"], len(state["bus"].transactions),
            state["scenario"]["order"],
        )
    )
    rows = ["ranking"]
    for rank, state in enumerate(ordered, 1):
        total = state["total"]["simple"]
        bus_count = len(state["bus"].transactions)
        rows.append(
            f"{rank} {state['scenario']['name']} finish {state['finish']} "
            f"transactions {bus_count} "
            f"amat {fraction(total['latency'], total['accesses'])} "
            f"{decimal(total['latency'], total['accesses'])}"
        )
    return rows


def hot_lines(state):
    """Rank lines by number of transactions with primary-scenario miss counts."""
    kinds = defaultdict(Counter)
    cores = defaultdict(set)
    for tx in state["bus"].transactions:
        block = tx["block"]
        kinds[block][tx["kind"]] += 1
        kinds[block]["invalidations"] += tx["invalidations"]
        cores[block].add(tx["core"])
    for item in state["processed_accesses"]:
        if item["miss_kind"] is not None:
            kinds[item["block"]]["misses"] += 1
            if item["miss_kind"] == "coherence":
                kinds[item["block"]]["coherence"] += 1
    sorted_blocks = sorted(kinds, key=lambda block: (
        -sum(kinds[block][tx] for tx in TRANSACTIONS), block
    ))
    rows = [f"hot {state['scenario']['name']}"]
    for rank, block in enumerate(sorted_blocks[:state["config"]["top"]], 1):
        numbers = kinds[block]
        rows.append(
            f"{rank} {hex_address(block * state['config']['line'])} "
            f"transactions {sum(numbers[tx] for tx in TRANSACTIONS)} "
            + " ".join(f"{tx} {numbers[tx]}" for tx in TRANSACTIONS)
            + f" misses {numbers['misses']} "
            f"coherence {numbers['coherence']} "
            f"invalidations {numbers['invalidations']} "
            f"cores {core_string(cores[block])}"
        )
    return rows


def interval_rows(state):
    """Bucket issue cycles, misses and exact bus occupancy, including crossings."""
    config = state["config"]
    width = config["interval"]
    interval_count = state["finish"] // width + 1
    accesses = [[0] * config["cores"] for _ in range(interval_count)]
    misses = [0] * interval_count
    tx_count = [0] * interval_count
    busy = [0] * interval_count
    for item in state["processed_accesses"]:
        bucket = item["issue"] // width
        accesses[bucket][item["core"]] += 1
        if item["miss_kind"] is not None:
            misses[bucket] += 1
    for tx in state["bus"].transactions:
        first, last = tx["start"], tx["start"] + config["tb"]
        tx_count[first // width] += 1
        for bucket in range(first // width, (last - 1) // width + 1):
            left = max(first, bucket * width)
            right = min(last, (bucket + 1) * width)
            if bucket < interval_count:
                busy[bucket] += max(0, right - left)
    rows = [f"intervals {state['scenario']['name']} {width}"]
    for bucket in range(interval_count):
        start = bucket * width
        end = start + width - 1
        rows.append(
            f"{bucket} {start}-{end} accesses "
            + " ".join(map(str, accesses[bucket]))
            + f" misses {misses[bucket]} "
            f"transactions {tx_count[bucket]} "
            f"busy {busy[bucket]} "
            f"utilization {decimal(100 * busy[bucket], width)}"
        )
    return rows


def slowest_rows(state):
    ordered = sorted(
        state["processed_accesses"],
        key=lambda event: (-event["latency"], event["number"]),
    )
    rows = [f"slowest {state['scenario']['name']}"]
    for rank, event in enumerate(ordered[:state["config"]["top"]], 1):
        rows.append(
            f"{rank} event {event['number']} cycle {event['issue']} "
            f"c{event['core']} {event['op']} {hex_address(event['address'])} "
            f"latency {event['latency']} service {event['service']}"
        )
    return rows


def region_for(address, config):
    return next(
        (region["name"] for region in config["regions"]
         if region["start"] <= address <= region["end"]),
        "other",
    )


def region_rows(state):
    """Assign accesses by address and transactions by their line addresses."""
    config = state["config"]
    counters = {
        region["name"]: Counter() for region in config["regions"]
    }
    counters["other"] = Counter()
    for event in state["processed_accesses"]:
        region = region_for(event["address"], config)
        count = counters[region]
        count["accesses"] += 1
        count["reads" if event["op"] == "R" else "writes"] += 1
        count["latency"] += event["latency"]
        if event["hit"]:
            count["hits"] += 1
        else:
            count[event["miss_kind"]] += 1
    for tx in state["bus"].transactions:
        name = region_for(tx["block"] * config["line"], config)
        counters[name]["transactions"] += 1
    rows = [f"regions {state['scenario']['name']}"]
    for name in [region["name"] for region in config["regions"]] + ["other"]:
        stats = counters[name]
        if stats["accesses"]:
            amat = (
                fraction(stats["latency"], stats["accesses"])
                + " " + decimal(stats["latency"], stats["accesses"])
            )
        else:
            amat = "-"
        rows.append(
            f"{name} accesses {stats['accesses']} reads {stats['reads']} "
            f"writes {stats['writes']} hits {stats['hits']} "
            + " ".join(f"{key} {stats[key]}" for key in MISSES)
            + f" transactions {stats['transactions']} "
            f"latency {stats['latency']} amat {amat}"
        )
    return rows


def stats_output(config, trace, events, rejected, reuse, states, primary):
    """Eight sections separated by exactly one blank line."""
    sections = [
        format_trace_config(config, trace, events, rejected),
        format_reuse(reuse, config),
    ]
    sections.extend(scenario_report(state) for state in states)
    sections.extend([
        rank_scenarios(states),
        hot_lines(primary),
        interval_rows(primary),
        slowest_rows(primary),
        region_rows(primary),
    ])
    rows = []
    for index, section in enumerate(sections):
        if index:
            rows.append("")
        rows.extend(section)
    return rows


def sharing_output(static, state):
    """Combine static word sharing with primary dynamic false/true misses."""
    rows = []
    shared_lines = [
        (block, entry) for block, entry in sorted(static.items())
        if entry["shared"]
    ]
    totals = Counter()
    for block, entry in shared_lines:
        true_miss = state["shared_misses"][(block, "true_sharing")]
        false_miss = state["shared_misses"][(block, "false_sharing")]
        total_miss = true_miss + false_miss
        totals["coherence"] += total_miss
        totals["true"] += true_miss
        totals["false"] += false_miss
        totals["true_lines" if entry["true"] else "false_lines"] += 1
        words = " ".join(
            f"w{number}={core_string(item['reads'])}/{core_string(item['writes'])}"
            for number, item in sorted(entry["words"].items())
        )
        rows.append(
            f"{hex_address(block * state['config']['line'])} "
            f"{'true' if entry['true'] else 'false'} "
            f"cores {core_string(entry['cores'])} "
            f"writers {core_string(entry['writers'])} "
            f"reads {entry['reads']} writes {entry['writes']} "
            f"handoffs {state['handoffs'][block]} "
            f"coherence {total_miss} true {true_miss} false {false_miss} "
            f"words {words}"
        )
    rows.append(
        f"lines {len(shared_lines)} true_lines {totals['true_lines']} "
        f"false_lines {totals['false_lines']} coherence {totals['coherence']} "
        f"true {totals['true']} false {totals['false']}"
    )
    rows.append("communication")
    for core, vector in enumerate(state["communications"]):
        rows.append(f"c{core} " + " ".join(map(str, vector)))
    return rows


def cache_way(entry, line_size):
    if entry is None:
        return "-"
    return hex_address(entry["block"] * line_size) + ":" + entry["state"]


def final_state_output(state):
    """Dump replacement order, per-set fill counts and cache residency."""
    config = state["config"]
    rows = []
    for core, cache in enumerate(state["l1"]):
        for set_index, ways in enumerate(cache.entries):
            values = " ".join(
                cache_way(item, config["line"]) for item in ways
            )
            rows.append(
                f"c{core} {set_index} {values} "
                f"{cache.replacement.lower()} {cache.order(set_index)} "
                f"fills {cache.fills[set_index]} "
                f"evictions {cache.evictions[set_index]}"
            )
        counts = Counter(item["state"] for item in cache.lines())
        rows.append(
            f"c{core} lines {cache.total_lines()} "
            + " ".join(f"{name} {counts[name]}" for name in ("M", "O", "E", "S", "V"))
        )
    l2 = state["l2"]
    for set_index, ways in enumerate(l2.entries):
        values = " ".join(cache_way(item, config["line"]) for item in ways)
        rows.append(
            f"L2 {set_index} {values} "
            f"{l2.replacement.lower()} {l2.order(set_index)} "
            f"fills {l2.fills[set_index]} evictions {l2.evictions[set_index]}"
        )
    counts = Counter(item["state"] for item in l2.lines())
    in_l1 = len({
        item["block"] for cache in state["l1"] for item in cache.lines()
    })
    rows.append(
        f"L2 lines {l2.total_lines()} dirty {counts['D']} "
        f"clean {counts['C']} in_l1 {in_l1}"
    )
    return rows


def main():
    """Execute each scenario independently and write the five required reports."""
    config = read_config()
    trace = read_trace()
    events, rejected = validate_trace(trace, config)
    reuse = reuse_analysis(events, config)
    shared = static_sharing(events)
    states = []
    for scenario in config["scenarios"]:
        states.append(simulate(
            config, scenario, events, scenario["name"] == config["primary"]
        ))
    primary = next(
        state for state in states
        if state["scenario"]["name"] == config["primary"]
    )
    write_lines(
        "stats.txt",
        stats_output(config, trace, events, rejected, reuse, states, primary),
    )
    write_lines(
        "bus_log.txt",
        [primary["bus"].line(tx, config["line"])
         for tx in primary["bus"].transactions],
    )
    write_lines("watch.txt", primary["watch_lines"])
    write_lines("sharing.txt", sharing_output(shared, primary))
    write_lines("final_state.txt", final_state_output(primary))


if __name__ == "__main__":
    main()
