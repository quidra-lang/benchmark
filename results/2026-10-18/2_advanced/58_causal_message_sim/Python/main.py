"""Discrete-event logical-clock simulator with snapshots and causal analysis.

Use python3 Python/main.py from the benchmark task directory. This program
reads input/topology.txt, input/programs.txt and input/params.txt and writes
five ASCII result files, without printing to standard output.
"""

from collections import Counter, defaultdict
from heapq import heappop, heappush
from pathlib import Path

from analysis import (
    concurrency_statistics, enumerate_cuts, graph_edges, graph_path,
    races_and_violations, range_notation,
)
from clocks import (
    broadcast_deliverable, missing_indices, nonreceive_event,
    receive_event, relation, vector_text,
)
from network import MINSTD, delay_notation, dispatch, read_topology
from processes import (
    balance_at_cut, held_count, initialize, read_scripts,
    reaction_actions, schedule_actions,
)
from snapshot import (
    accepted_marker, copy_label, cut_details, new_snapshot,
    record_state, recorded_copies, snapshot_cut,
    transit_match, vector_consistent,
)


def load_params(path="input/params.txt"):
    lines = Path(path).read_text(encoding="ascii").splitlines()
    params = {"compare": [], "cuts": [], "predicates": []}
    for line in lines:
        fields = line.split(" ")
        keyword, arguments = fields[0], fields[1:]
        if keyword == "SEED":
            params["seed"] = int(arguments[0])
        elif keyword == "END":
            params["end"] = int(arguments[0])
        elif keyword == "CUTCOUNT":
            params["cutcount"] = int(arguments[0])
        elif keyword == "COMPARE":
            params["compare"].append(tuple(arguments))
        elif keyword == "CUT":
            params["cuts"].append(tuple(map(int, arguments)))
        elif keyword == "PREDICATE":
            params["predicates"].append(int(arguments[0]))
    return params


def yes(value):
    return "yes" if value else "no"


def msg_name(message):
    return f"m{message['id']}"


def process_names(names, chosen):
    return ",".join(name for name in names if name in chosen)


class Simulation:
    """One reproducible event simulation, with or without ordering guarantees."""

    def __init__(self, names, original_channels, scripts, params, raw=False):
        self.names = list(names)
        self.index = {name: i for i, name in enumerate(names)}
        self.params = params
        self.raw = raw
        self.processes = initialize(names, scripts)
        self.channels = {
            key: {**channel, "previous_vector": [0] * len(names)}
            for key, channel in original_channels.items()
        }
        self.channel_order = sorted(self.channels, key=lambda pair: (
            self.index[pair[0]], self.index[pair[1]]
        ))
        self.random = MINSTD(params["seed"])
        self.queue = []
        self.creation_number = 0
        self.current_time = 0
        self.messages = []
        self.copies = []
        self.events = []
        self.snapshots = []
        self.snapshot_by_name = {}
        self.timeline = []
        schedule_actions(
            names, self.processes, params["end"], self.enqueue,
        )

    def enqueue(self, time, destination, kind, payload):
        self.creation_number += 1
        heappush(self.queue, (
            time, self.index[destination], self.creation_number,
            destination, kind, payload,
        ))

    def record_event(self, process, kind, details, sender=None):
        """Advance logical clocks, then append local and global event numbers."""
        name = process["name"]
        if kind == "RECV":
            receive_event(process, self.index[name], sender)
        else:
            nonreceive_event(process, self.index[name])
        event = {
            "number": len(self.events) + 1,
            "local_number": len(process["events"]) + 1,
            "process": name, "type": kind,
            "details": details, "time": self.current_time,
            "lamport": process["lamport"],
            "vector": list(process["vector"]),
            "balance": process["balance"],
            "process_events": process["events"],
        }
        event["name"] = f"{name}.{event['local_number']}"
        process["events"].append(event)
        process["types"][kind] = process["types"].get(kind, 0) + 1
        process["min_balance"] = min(
            process["min_balance"], process["balance"]
        )
        self.events.append(event)
        self.timeline.append(("event", event))
        return event

    def send_message(self, process, action, sender=None):
        kind = action[0]
        source = process["name"]
        destination = action[1] if kind != "BROADCAST" else None
        if destination == "SENDER":
            destination = sender
        if kind == "TRANSFER":
            amount = action[2]
            if amount > process["balance"]:
                process["refused"] += 1
                self.record_event(
                    process, "NOFUNDS",
                    {"destination": destination, "amount": amount,
                     "balance": process["balance"]},
                )
                return
            process["balance"] -= amount
            process["out"] += amount
            tag = "transfer"
            event_type = "SEND"
            message_kind = "P2P"
        elif kind == "SEND":
            amount = 0
            tag = action[2]
            event_type = "SEND"
            message_kind = "P2P"
        else:
            amount = 0
            tag = action[1]
            event_type = "BCAST"
            message_kind = "BCAST"
            process["broadcast"][self.index[source]] += 1

        message = {
            "id": len(self.messages) + 1,
            "kind": message_kind, "source": source, "tag": tag,
            "amount": amount, "copies": [],
            "stamp": list(process["broadcast"]) if message_kind == "BCAST" else None,
        }
        self.messages.append(message)
        sending = self.record_event(
            process, event_type, {"message": message,
                                  "destination": destination},
        )
        message["send_event"] = sending
        message["send_time"] = self.current_time
        destinations = (
            [name for name in self.names if name != source]
            if message_kind == "BCAST" else [destination]
        )
        for target in destinations:
            copy = {
                "packet_type": "copy", "message": message,
                "kind": message_kind, "tag": tag,
                "amount": amount, "send_event": sending,
                "stamp": message["stamp"],
                "fifo_wait": False, "causal_wait": False,
                "missing": [], "recv_event": None,
            }
            message["copies"].append(copy)
            self.copies.append(copy)
            dispatch(
                self.channels, source, target, copy,
                self.current_time, self.random, self.enqueue,
            )

    def process_action(self, name, action, sender=None):
        process = self.processes[name]
        kind = action[0]
        if kind == "LOCAL":
            self.record_event(process, "LOCAL", {"label": action[1]})
        elif kind == "SNAPSHOT":
            self.initiate_snapshot(name, action[1])
        else:
            self.send_message(process, action, sender)

    def start_snapshot(self, name):
        if name not in self.snapshot_by_name:
            snapshot = new_snapshot(name, self.current_time, self.names)
            self.snapshot_by_name[name] = snapshot
            self.snapshots.append(snapshot)
        return self.snapshot_by_name[name]

    def record_snapshot(self, snapshot, name, reason):
        process = self.processes[name]
        record_state(snapshot, process, self.current_time, reason)
        self.timeline.append(("snapshot", {
            "time": self.current_time, "process": name,
            "name": snapshot["name"],
        }))
        for destination in self.names:
            if destination == name:
                continue
            marker = {
                "packet_type": "marker", "snapshot": snapshot["name"],
            }
            dispatch(
                self.channels, name, destination, marker,
                self.current_time, self.random, self.enqueue,
            )
            snapshot["markers"][(name, destination)] = {
                "sent": self.current_time, "accepted": None,
            }

    def initiate_snapshot(self, name, snapshot_name):
        snapshot = self.start_snapshot(snapshot_name)
        if name in snapshot["records"]:
            snapshot["ignored"].append((name, self.current_time))
            return
        self.record_snapshot(snapshot, name, "initiate")

    def accept_marker(self, destination, packet):
        source = packet["source"]
        snapshot = self.snapshot_by_name[packet["snapshot"]]
        if destination not in snapshot["records"]:
            self.record_snapshot(snapshot, destination, f"marker {source}")
        accepted_marker(
            snapshot, source, destination, self.current_time, self.names
        )

    def deliver(self, destination, copy):
        process = self.processes[destination]
        message = copy["message"]
        if message["kind"] == "BCAST":
            process["broadcast"][self.index[copy["source"]]] += 1
        process["balance"] += copy["amount"]
        process["in"] += copy["amount"]
        event = self.record_event(
            process, "RECV", {"copy": copy},
            sender=copy["send_event"],
        )
        copy["recv_event"] = event
        copy["delivery_time"] = self.current_time
        process["delivered"].append(copy)
        for action in reaction_actions(process, copy["tag"]):
            self.process_action(destination, action, copy["source"])

    def missing_for_copy(self, destination, copy):
        index = self.index[copy["source"]]
        process = self.processes[destination]
        return missing_indices(copy["stamp"], process["broadcast"], index)

    def can_deliver(self, destination, copy):
        process = self.processes[destination]
        return broadcast_deliverable(
            copy["stamp"], process["broadcast"], self.index[copy["source"]],
        )

    def release_causal_waits(self, destination):
        process = self.processes[destination]
        while True:
            index = next(
                (i for i, copy in enumerate(process["holdback"])
                 if self.can_deliver(destination, copy)),
                None,
            )
            if index is None:
                break
            copy = process["holdback"].pop(index)
            self.deliver(destination, copy)

    def accept_packet(self, destination, packet):
        process = self.processes[destination]
        source = packet["source"]
        process["next_sequence"][source] += 1
        if packet["packet_type"] == "marker":
            self.accept_marker(destination, packet)
            return
        for snapshot in self.snapshots:
            if (destination in snapshot["records"]
                    and (source, destination) not in snapshot["accepted"]):
                snapshot["channel_states"][(source, destination)].append(packet)
        if packet["kind"] == "P2P" or self.raw:
            self.deliver(destination, packet)
            return
        if self.can_deliver(destination, packet):
            self.deliver(destination, packet)
            self.release_causal_waits(destination)
        else:
            packet["causal_wait"] = True
            packet["missing"] = self.missing_for_copy(destination, packet)
            process["holdback"].append(packet)

    def receive_packet(self, destination, packet):
        process = self.processes[destination]
        source = packet["source"]
        next_number = process["next_sequence"][source]
        if self.raw:
            self.accept_packet(destination, packet)
        elif packet["sequence"] != next_number:
            packet["fifo_wait"] = True
            process["reorder"][source][packet["sequence"]] = packet
            self.channels[(source, destination)]["buffered"] += 1
        else:
            self.accept_packet(destination, packet)
            buffer = process["reorder"][source]
            while process["next_sequence"][source] in buffer:
                following = buffer.pop(process["next_sequence"][source])
                self.accept_packet(destination, following)
        process["max_held"] = max(
            process["max_held"], held_count(process),
        )

    def run(self):
        end = self.params["end"]
        while self.queue and self.queue[0][0] <= end:
            time, _, _, destination, kind, payload = heappop(self.queue)
            self.current_time = time
            if kind == "action":
                self.process_action(destination, payload)
            else:
                self.receive_packet(destination, payload)
        return self


def initial_total(simulation):
    return sum(p["initial"] for p in simulation.processes.values())


def event_line(event):
    """Write a trace event with exact details for its event kind."""
    kind, detail = event["type"], event["details"]
    if kind == "LOCAL":
        info = detail["label"]
    elif kind == "NOFUNDS":
        info = (
            f"to {detail['destination']} amount {detail['amount']} "
            f"balance {detail['balance']}"
        )
    elif kind in ("SEND", "BCAST"):
        message = detail["message"]
        if kind == "SEND":
            info = (
                f"{msg_name(message)} to {detail['destination']} "
                f"tag {message['tag']}"
            )
            if message["amount"]:
                info += (
                    f" amount {message['amount']} balance {event['balance']}"
                )
        else:
            info = f"{msg_name(message)} tag {message['tag']}"
    else:
        copy = detail["copy"]
        info = (
            f"{msg_name(copy['message'])} from {copy['source']} "
            f"tag {copy['tag']}"
        )
        if copy["amount"]:
            info += f" amount {copy['amount']} balance {event['balance']}"
    return (
        f"{event['number']} t={event['time']} {event['name']} "
        f"{kind} {info} L={event['lamport']} "
        f"V={vector_text(event['vector'])}"
    )


def trace_lines(simulation):
    result = [event_line(event) for event in simulation.events]
    delivered = sum(copy["recv_event"] is not None for copy in simulation.copies)
    result.append(
        f"SUMMARY events {len(simulation.events)} "
        f"messages {len(simulation.messages)} "
        f"copies {len(simulation.copies)} delivered {delivered} "
        f"undelivered {len(simulation.copies) - delivered} "
        f"draws {simulation.random.draws}"
    )
    for name in simulation.names:
        process = simulation.processes[name]
        result.append(
            f"FINAL {name} events {len(process['events'])} "
            f"L={process['lamport']} V={vector_text(process['vector'])} "
            f"B={vector_text(process['broadcast'])} "
            f"balance {process['balance']} in {process['in']} "
            f"out {process['out']} refused {process['refused']} "
            f"min {process['min_balance']}"
        )
    for name in simulation.names:
        counts = simulation.processes[name]["types"]
        result.append(
            f"COUNTS {name} local {counts.get('LOCAL', 0)} "
            f"nofunds {counts.get('NOFUNDS', 0)} "
            f"send {counts.get('SEND', 0)} "
            f"bcast {counts.get('BCAST', 0)} "
            f"recv {counts.get('RECV', 0)}"
        )
    return result


def wait_mode(copy, names):
    fifo = copy["fifo_wait"]
    causal = copy["causal_wait"]
    if not fifo and not causal:
        return "direct"
    if fifo and not causal:
        return "fifo"
    missing = process_names(names, {
        names[i] for i in copy["missing"]
    })
    if fifo:
        return f"fifo+causal {missing}"
    return f"causal {missing}"


def broadcast_history(process):
    result = []
    for event in process["events"]:
        if event["type"] == "BCAST":
            result.append(msg_name(event["details"]["message"]))
        elif (event["type"] == "RECV"
              and event["details"]["copy"]["kind"] == "BCAST"):
            result.append(msg_name(event["details"]["copy"]["message"]))
    return result


def deliveries_lines(simulation):
    """Group delivered, held and in-transit copies per destination."""
    result = []
    end = simulation.params["end"]
    for name in simulation.names:
        process = simulation.processes[name]
        result.append(f"PROCESS {name}")
        modes = Counter()
        wait_total = 0
        max_wait = 0
        delivered = process["delivered"]
        for number, copy in enumerate(delivered, 1):
            wait = copy["delivery_time"] - copy["arrival_time"]
            wait_total += wait
            max_wait = max(max_wait, wait)
            mode = wait_mode(copy, simulation.names)
            modes[("both" if copy["fifo_wait"] and copy["causal_wait"]
                   else "fifo" if copy["fifo_wait"]
                   else "causal" if copy["causal_wait"]
                   else "direct")] += 1
            result.append(
                f"{number} {msg_name(copy['message'])} "
                f"from {copy['source']} {copy['kind']} tag {copy['tag']} "
                f"sent {copy['message']['send_time']} "
                f"arrived {copy['arrival_time']} "
                f"delivered {copy['delivery_time']} "
                f"wait {wait} {mode}"
            )
        for copy in simulation.copies:
            if (copy["destination"] != name
                    or copy["arrival_time"] > end
                    or copy["recv_event"] is not None):
                continue
            if copy["sequence"] in process["reorder"][copy["source"]]:
                place = "fifo"
            else:
                missing = process_names(simulation.names, {
                    simulation.names[i] for i in copy["missing"]
                })
                place = f"causal {missing}"
            result.append(
                f"HELD {msg_name(copy['message'])} from {copy['source']} "
                f"{copy['kind']} tag {copy['tag']} "
                f"sent {copy['message']['send_time']} "
                f"arrived {copy['arrival_time']} {place}"
            )
        for copy in simulation.copies:
            if copy["destination"] == name and copy["arrival_time"] > end:
                result.append(
                    f"TRANSIT {msg_name(copy['message'])} "
                    f"from {copy['source']} {copy['kind']} tag {copy['tag']} "
                    f"sent {copy['message']['send_time']} "
                    f"arrival {copy['arrival_time']}"
                )
        result.append(
            f"TOTAL delivered {len(delivered)} direct {modes['direct']} "
            f"fifo {modes['fifo']} causal {modes['causal']} "
            f"both {modes['both']} wait {wait_total} "
            f"max_wait {max_wait} max_held {process['max_held']}"
        )
        broadcasts = broadcast_history(process)
        result.append(
            "BCASTS " + (" ".join(broadcasts) if broadcasts else "none")
        )

    for pair in simulation.channel_order:
        channel = simulation.channels[pair]
        result.append(
            f"CHANNEL {pair[0]}->{pair[1]} {channel['kind']} "
            f"{delay_notation(channel)} messages {channel['messages']} "
            f"markers {channel['markers']} buffered {channel['buffered']} "
            f"max_delay {channel['max_delay']} entries {channel['entries']}"
        )
    for tag in sorted({copy["tag"] for copy in simulation.copies}):
        tagged = [copy for copy in simulation.copies if copy["tag"] == tag]
        completed = [copy for copy in tagged if copy["recv_event"] is not None]
        latencies = [
            copy["delivery_time"] - copy["message"]["send_time"]
            for copy in completed
        ]
        result.append(
            f"TAG {tag} copies {len(tagged)} delivered {len(completed)} "
            f"latency {sum(latencies)} max {max(latencies, default=0)}"
        )

    broadcasts = [
        message for message in simulation.messages if message["kind"] == "BCAST"
    ]
    for message in broadcasts:
        copies = message["copies"]
        times = [copy["delivery_time"] for copy in copies
                 if copy["recv_event"] is not None]
        stable = max(times) if len(times) == len(copies) else "none"
        result.append(
            f"STABLE {msg_name(message)} {message['source']} "
            f"tag {message['tag']} sent {message['send_time']} "
            f"stable {stable}"
        )
    disagreements = 0
    for i, first in enumerate(broadcasts):
        for second in broadcasts[i + 1:]:
            earlier, later = [], []
            first_name, second_name = msg_name(first), msg_name(second)
            for name in simulation.names:
                history = broadcast_history(simulation.processes[name])
                if first_name in history and second_name in history:
                    if history.index(first_name) < history.index(second_name):
                        earlier.append(name)
                    else:
                        later.append(name)
            if earlier and later:
                disagreements += 1
                result.append(
                    f"DISAGREE {first_name} {second_name} "
                    f"{','.join(earlier)} {','.join(later)}"
                )
    result.append(f"DISAGREEMENTS {disagreements}")
    return result


def consistent_verdict(details):
    if details["consistent"]:
        return "yes"
    return "no " + " ".join(map(copy_label, details["orphans"]))


def snapshots_lines(main_sim, raw_sim):
    """Render complete snapshots, channel states, cuts and RAW comparisons."""
    result = []
    for simulation, raw in ((main_sim, False), (raw_sim, True)):
        for snap in simulation.snapshots:
            indices = simulation.index
            cut = snapshot_cut(snap, simulation.names, indices)
            details = cut_details(
                cut, simulation.names, simulation.processes, simulation.copies
            )
            entries, pending = recorded_copies(
                snap, simulation.channel_order
            )
            channels_total = sum(copy["amount"] for copy in entries)
            snapshot_money = sum(
                record["balance"] for record in snap["records"].values()
            ) + channels_total
            if raw:
                result.append(
                    f"RAW {snap['name']} completed {snap['complete']} "
                    f"cut {vector_text(cut)} "
                    f"consistent {consistent_verdict(details)} "
                    f"money {snapshot_money} "
                    f"conserved {yes(snapshot_money == initial_total(simulation))}"
                )
                continue
            result.append(
                f"SNAPSHOT {snap['name']} started {snap['start']} "
                f"completed {snap['complete']}"
            )
            for name in simulation.names:
                record = snap["records"][name]
                pend_text = " ".join(
                    msg_name(copy["message"]) for copy in record["pending"]
                ) or "none"
                result.append(
                    f"RECORD {name} t={record['time']} {record['reason']} "
                    f"balance {record['balance']} L={record['lamport']} "
                    f"V={vector_text(record['vector'])} pending {pend_text}"
                )
            for source, destination in simulation.channel_order:
                state = snap["channel_states"][(source, destination)]
                values = " ".join(
                    msg_name(copy["message"]) +
                    (f":{copy['amount']}" if copy["amount"] else "")
                    for copy in state
                ) or "empty"
                marker = snap["markers"][(source, destination)]
                result.append(
                    f"CHANNEL {source}->{destination} "
                    f"marker {marker['sent']} {marker['accepted']} "
                    f"state {values}"
                )
            for name, time in snap["ignored"]:
                result.append(f"IGNORED {name} t={time}")
            result.append(
                f"CUT {vector_text(cut)} "
                f"consistent {consistent_verdict(details)} "
                f"vector {yes(vector_consistent(snap, simulation.names, indices, cut))}"
            )
            result.append(
                f"TRANSIT channels {len(entries)} pending {len(pending)} "
                f"cut {len(details['transit'])} "
                f"match {yes(transit_match(entries, pending, details['transit']))}"
            )
            balance_total = sum(
                record["balance"] for record in snap["records"].values()
            )
            result.append(
                f"MONEY balances {balance_total} channels {channels_total} "
                f"total {snapshot_money} initial {initial_total(simulation)} "
                f"conserved {yes(snapshot_money == initial_total(simulation))}"
            )
    return result


def causal_longest_chain(events, sim):
    """Recover a maximum-length Lamport chain using the prescribed predecessor."""
    current = max(events, key=lambda item: (
        item["lamport"], -item["number"]
    ))
    reversed_chain = [current]
    while current["lamport"] > 1:
        previous = None
        if current["type"] == "RECV":
            candidate = current["details"]["copy"]["send_event"]
            if candidate["lamport"] == current["lamport"] - 1:
                previous = candidate
        if previous is None:
            local = sim.processes[current["process"]]["events"]
            previous = local[current["local_number"] - 2]
        reversed_chain.append(previous)
        current = previous
    return list(reversed(reversed_chain))


def compare_events_lines(sim):
    edges = graph_edges(sim.events, sim.copies)
    indexed = {event["name"]: event for event in sim.events}
    by_number = {event["number"]: event for event in sim.events}
    lines = []
    for first_name, second_name in sim.params["compare"]:
        first, second = indexed[first_name], indexed[second_name]
        vector_relation = relation(first["vector"], second["vector"])
        forward = graph_path(first, second, edges)
        reverse = None if forward else graph_path(second, first, edges)
        graph_relation = "->" if forward else "<-" if reverse else "||"
        lines.append(
            f"COMPARE {first_name} {vector_relation} {second_name} "
            f"L={first['lamport']},{second['lamport']} "
            f"graph {graph_relation} agree {yes(vector_relation == graph_relation)}"
        )
        path = forward or reverse
        if path is not None:
            events = [by_number[number] for number in path]
            message_count = sum(
                a["process"] != b["process"]
                for a, b in zip(events, events[1:])
            )
            lines.append(
                f"PATH length {len(path)} messages {message_count} "
                f"{range_notation(events)}"
            )
        for event in (first, second):
            past = event["vector"]
            sender = sim.index[event["process"]]
            k = event["local_number"]
            future = [
                sum(item["vector"][sender] < k
                    for item in sim.processes[name]["events"])
                for name in sim.names
            ]
            lines.append(
                f"WINDOW {event['name']} past {vector_text(past)} "
                f"future {vector_text(future)}"
            )
    return lines


def analysis_lines(sim, raw):
    lines = compare_events_lines(sim)
    summary = concurrency_statistics(sim.events, sim.names)
    lines.append(
        f"CONCURRENCY events {len(sim.events)} pairs {summary['pairs']} "
        f"ordered {summary['ordered']} concurrent {summary['concurrent']} "
        f"same_lamport {summary['same_lamport']} "
        f"inversions {summary['inversions']}"
    )
    for i, first in enumerate(sim.names):
        for second in sim.names[i + 1:]:
            lines.append(
                f"PAIR {first} {second} "
                f"{summary['by_pair'][(first, second)]}"
            )
    chain = causal_longest_chain(sim.events, sim)
    lines.append(
        f"CHAIN length {len(chain)} {range_notation(chain)}"
    )
    races, violations = races_and_violations(sim.processes, sim.names)
    for destination, a, b in races:
        lines.append(
            f"RACE {destination} {msg_name(a['message'])} {a['source']} "
            f"{msg_name(b['message'])} {b['source']}"
        )
    lines.append(f"RACES {len(races)}")
    for destination, a, b in violations:
        lines.append(
            f"VIOLATION {destination} {msg_name(a['message'])} "
            f"{a['source']} overtook {msg_name(b['message'])} {b['source']}"
        )
    lines.append(
        f"VIOLATIONS causal {len(violations)} "
        f"fifo {sum(a['source'] == b['source'] for _, a, b in violations)}"
    )
    _, raw_violations = races_and_violations(raw.processes, raw.names)
    lines.append(
        f"RAW events {len(raw.events)} "
        f"delivered {sum(c['recv_event'] is not None for c in raw.copies)} "
        f"causal {len(raw_violations)} "
        f"fifo {sum(a['source'] == b['source'] for _, a, b in raw_violations)}"
    )
    for cut in sim.params["cuts"]:
        details = cut_details(cut, sim.names, sim.processes, sim.copies)
        if details["consistent"]:
            lines.append(
                f"CUT {vector_text(cut)} consistent "
                f"transit {len(details['transit'])} "
                f"money {details['money']} initial {initial_total(sim)}"
            )
        else:
            lines.append(
                f"CUT {vector_text(cut)} inconsistent orphans "
                f"{' '.join(map(copy_label, details['orphans']))} "
                f"transit {len(details['transit'])} "
                f"money {details['money']} initial {initial_total(sim)}"
            )
    enumeration = enumerate_cuts(
        sim.names, sim.processes, sim.params["cutcount"],
        sim.params["predicates"],
    )
    lines.append(
        f"CUTCOUNT t={sim.params['cutcount']} "
        f"events {vector_text(enumeration['limits'])} "
        f"product {enumeration['product']} consistent {enumeration['consistent']}"
    )
    lines.append(
        "LEVELS " + " ".join(
            str(enumeration["levels"][level])
            for level in range(sum(enumeration["limits"]) + 1)
        )
    )
    for threshold in sim.params["predicates"]:
        record = enumeration["predicates"][threshold]
        lines.append(
            f"PREDICATE transit>={threshold} cuts {record['cuts']} "
            f"possibly {yes(record['possibly'])} "
            f"definitely {yes(record['definitely'])}"
        )
    return lines


def diagram_header(letter, names):
    """Fixed process columns at positions 6, 14, 22, ..."""
    line = list("    " + letter + " ")
    last = 8 * len(names) - 2
    line += [" "] * (last + 1 - len(line))
    for i, name in enumerate(names):
        col = 8 * (i + 1) - 2
        for offset, letter in enumerate(name):
            if col + offset >= len(line):
                line.extend([" "] * (col + offset + 1 - len(line)))
            line[col + offset] = letter
    return "".join(line).rstrip()


def diagram_entry(value, name, kind, detail, sim):
    """Draw an event or snapshot recording, with inter-process arrows."""
    last = 8 * len(sim.names) - 2
    line = list(f"{value:>5} " + " " * (last - 5))
    columns = {name: 8 * (i + 1) - 2
               for i, name in enumerate(sim.names)}
    for column in columns.values():
        line[column] = "|"
    own = columns[name]
    symbol = {
        "LOCAL": "*", "NOFUNDS": "x", "SEND": "S",
        "BCAST": "B", "RECV": "R", "snapshot": "#",
    }[kind]
    line[own] = symbol

    def write(at, text):
        for offset, char in enumerate(text):
            index = at + offset
            if index >= len(line):
                line.extend([" "] * (index + 1 - len(line)))
            line[index] = char

    if kind == "snapshot":
        write(own + 1, detail["name"])
    elif kind in ("SEND", "BCAST"):
        write(own + 1, msg_name(detail["message"]))
    elif kind == "RECV":
        copy = detail["copy"]
        other = columns[copy["source"]]
        low, high = min(own, other), max(own, other)
        for index in range(low + 1, high):
            line[index] = "+" if index in columns.values() else "-"
        if other < own:
            line[high - 1] = ">"
        else:
            line[low + 1] = "<"
        write(low + 2, msg_name(copy["message"]))
        line[own] = "R"
    return "".join(line).rstrip()


def diagram_lines(sim):
    lines = [diagram_header("t", sim.names)]
    for kind, obj in sim.timeline:
        if kind == "snapshot":
            lines.append(
                diagram_entry(obj["time"], obj["process"], "snapshot", obj, sim)
            )
        else:
            lines.append(
                diagram_entry(
                    obj["time"], obj["process"], obj["type"],
                    obj["details"], sim,
                )
            )
    lines.append(diagram_header("L", sim.names))
    for event in sorted(
        sim.events, key=lambda obj: (
            obj["lamport"], sim.index[obj["process"]]
        )
    ):
        lines.append(
            diagram_entry(
                event["lamport"], event["process"], event["type"],
                event["details"], sim,
            )
        )
    return lines


def save_output(name, lines):
    output = Path("output") / name
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text("\n".join(lines) + "\n", encoding="ascii")


def main():
    names, channels, _ = read_topology()
    scripts = read_scripts()
    params = load_params()
    normal = Simulation(names, channels, scripts, params).run()
    comparison = Simulation(names, channels, scripts, params, raw=True).run()
    save_output("trace.txt", trace_lines(normal))
    save_output("deliveries.txt", deliveries_lines(normal))
    save_output("snapshots.txt", snapshots_lines(normal, comparison))
    save_output("analysis.txt", analysis_lines(normal, comparison))
    save_output("diagram.txt", diagram_lines(normal))


if __name__ == "__main__":
    main()
