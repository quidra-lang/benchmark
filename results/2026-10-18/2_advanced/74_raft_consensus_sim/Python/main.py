"""Execute the five Raft phases and assemble the simulation reports."""

from collections import Counter, defaultdict
from pathlib import Path

from checker import Checker
from cluster import read_script, read_settings
from minstd import Minstd
from network import FIELDS, REASONS, TYPES, Network
from raft_node import Entry, Node, apply_command


def node_set(nodes):
    return ",".join(f"n{number}" for number in sorted(nodes)) or "-"


def command_text(command):
    return " ".join(map(str, command))


class Simulator:
    def __init__(self, settings, controls, requests, network):
        self.settings = settings
        self.nodes = [Node(number) for number in range(1, settings.nodes + 1)]
        self.network = network
        self.random = Minstd(settings.seed)
        self.checker = Checker()
        self.controls = defaultdict(list)
        for event in controls:
            self.controls[event.time].append(event)
        self.requests = requests
        self.attempt_queue = defaultdict(list)
        for request in requests:
            self.attempt_queue[request.scheduled].append(request)
        self.time = 0
        self.trace = []
        self.elections = []
        self.leaders = {}
        self.timelines = []
        self.leader_ticks = 0
        self.multi_ticks = 0
        self.gaps = []
        self.gap_start = None

    def node(self, number):
        return self.nodes[number - 1]

    def majority(self, count):
        return 2 * count > self.settings.nodes

    def write_trace(self, content):
        self.trace.append(f"{self.time} {content}")

    def set_election_timer(self, node):
        duration = self.random.between(self.settings.election_min, self.settings.election_max)
        node.election_deadline = self.time + duration

    def send(self, node, destination, kind, data):
        self.network.send(self.time, node.number, destination, node.term, kind, data)

    def send_append(self, node, destination):
        previous = node.next[destination] - 1
        entries = tuple(node.log[previous:previous + self.settings.batch])
        self.send(node, destination, "AE", {
            "previous": previous, "previous_term": node.term_at(previous),
            "entries": entries, "commit": node.commit,
        })

    def broadcast_append(self, node):
        for other in self.nodes:
            if other is not node:
                self.send_append(node, other.number)

    def end_leadership(self, node, reason):
        record = self.leaders[node.term]
        record["ended"] = self.time
        record["reason"] = reason
        record["commit"] = node.commit
        node.cancel_transfer()

    def control(self, event):
        kind, arguments = event.kind, event.arguments
        if kind == "CRASH":
            node = self.node(arguments[0])
            self.write_trace(f"CRASH n{node.number} {node.role} term {node.term}")
            if node.role == "LEADER":
                self.end_leadership(node, "CRASH")
            node.crash()
        elif kind == "RESTART":
            node = self.node(arguments[0])
            node.up = True
            self.set_election_timer(node)
            self.write_trace(f"RESTART n{node.number} term {node.term} length {node.last_index} "
                             f"deadline {node.election_deadline}")
        elif kind == "PARTITION":
            self.network.partition(arguments)
            self.write_trace("PARTITION " + " ".join(node_set(group) for group in arguments))
        elif kind == "HEAL":
            self.network.heal()
            self.write_trace("HEAL")
        else:
            self.start_transfer(self.node(arguments[0]), arguments[1])

    def attempt(self, request):
        request.attempts += 1
        destination = request.destination
        redirected = 0
        while True:
            node = self.node(destination)
            if not node.up:
                reason = "down"
                break
            if node.role == "LEADER":
                if node.transfer_target is not None:
                    reason = "transfer"
                    break
                node.log.append(Entry(node.term, request.command, request.number))
                self.leaders[node.term]["appended"] += 1
                request.accepted = node.last_index, node.term
                request.scheduled = None
                self.write_trace(f"ACCEPT r{request.number} n{node.number} "
                                 f"index {node.last_index} term {node.term}")
                return
            if node.known_leader is None or redirected >= self.settings.nodes - 1:
                reason = "noleader"
                break
            destination = node.known_leader
            self.write_trace(f"REDIRECT r{request.number} n{node.number} n{destination}")
            redirected += 1
            request.redirects += 1
        prefix = f"REJECT r{request.number} n{node.number} {reason}"
        if request.attempts < self.settings.attempts:
            request.destination = node.number % self.settings.nodes + 1
            request.scheduled = self.time + self.settings.retry
            self.attempt_queue[request.scheduled].append(request)
            self.write_trace(f"{prefix} retry n{request.destination} at {request.scheduled}")
        else:
            request.abandoned = True
            request.scheduled = None
            self.write_trace(prefix + " giveup")

    def start_election(self, node, trigger):
        node.term += 1
        node.role = "CANDIDATE"
        node.voted_for = node.number
        node.votes = {node.number}
        node.known_leader = None
        self.set_election_timer(node)
        node.stats["elections"] += 1
        record = {"time": self.time, "node": node.number, "term": node.term,
                  "trigger": trigger, "votes": node.votes, "won": None}
        node.election_record = record
        self.elections.append(record)
        self.write_trace(f"ELECTION n{node.number} term {node.term} "
                         f"last {node.last_index}/{node.last_term} deadline {node.election_deadline}")
        for other in self.nodes:
            if other is not node:
                self.send(node, other.number, "RV", {
                    "last_index": node.last_index, "last_term": node.last_term,
                })

    def vote_request(self, node, message):
        reason = None
        if message.term < node.term:
            reason = "term"
        elif node.voted_for is not None and node.voted_for != message.source:
            reason = "voted"
        elif not node.accepts_log(message.data["last_index"], message.data["last_term"]):
            reason = "log"
        if reason is None:
            node.voted_for = message.source
            node.stats["votes_granted"] += 1
            self.set_election_timer(node)
            self.write_trace(f"VOTE n{node.number} n{message.source} term {node.term} "
                             f"deadline {node.election_deadline}")
        else:
            self.write_trace(f"DENY n{node.number} n{message.source} term {node.term} {reason}")
        self.send(node, message.source, "RVR", {"granted": reason is None})

    def vote_response(self, node, message):
        if node.role != "CANDIDATE" or message.term != node.term or not message.data["granted"]:
            return
        node.votes.add(message.source)
        if self.majority(len(node.votes)):
            self.become_leader(node)

    def become_leader(self, node):
        node.role = "LEADER"
        node.known_leader = node.number
        node.next = {other.number: node.last_index + 1 for other in self.nodes if other is not node}
        node.match = {other.number: 0 for other in self.nodes if other is not node}
        node.log.append(Entry(node.term, ("NOOP",), 0))
        node.stats["leader_terms"] += 1
        node.election_record["won"] = self.time
        self.checker.leader(node)
        self.leaders[node.term] = {
            "node": node.number, "elected": self.time, "votes": node.votes.copy(),
            "appended": 1, "ended": None, "reason": None, "commit": None,
        }
        self.write_trace(f"LEADER n{node.number} term {node.term} votes {node_set(node.votes)} "
                         f"noop {node.last_index}")
        self.broadcast_append(node)
        node.heartbeat_deadline = self.time + self.settings.heartbeat
        node.quorum_deadline = self.time + self.settings.quorum
        node.heard = set()

    def truncate(self, node, first):
        removed = node.log[first - 1:]
        del node.log[first - 1:]
        node.stats["truncated"] += len(removed)
        self.checker.truncate(first, removed)
        self.write_trace(f"TRUNCATE n{node.number} from {first} removed {len(removed)}")

    def append_request(self, node, message):
        if message.term < node.term:
            self.send(node, message.source, "AER", {"success": False, "match": 0})
            return
        if node.role == "CANDIDATE":
            node.role = "FOLLOWER"
            self.write_trace(f"YIELD n{node.number} term {node.term} n{message.source}")
        node.known_leader = message.source
        self.set_election_timer(node)
        previous = message.data["previous"]
        if previous > node.last_index or node.term_at(previous) != message.data["previous_term"]:
            node.stats["ae_fail"] += 1
            hint = node.last_index if previous > node.last_index else previous - 1
            self.send(node, message.source, "AER", {"success": False, "match": hint})
            return
        node.stats["ae_ok"] += 1
        for index, entry in enumerate(message.data["entries"], previous + 1):
            if index <= node.last_index and node.term_at(index) != entry.term:
                self.truncate(node, index)
            if index > node.last_index:
                node.log.append(entry)
                node.stats["appended"] += 1
        confirmed = previous + len(message.data["entries"])
        commit = min(message.data["commit"], confirmed)
        if commit > node.commit:
            self.advance_commit(node, commit)
        self.send(node, message.source, "AER", {"success": True, "match": confirmed})

    def append_response(self, node, message):
        if node.role != "LEADER" or message.term != node.term:
            return
        source = message.source
        node.heard.add(source)
        confirmed = message.data["match"]
        if message.data["success"]:
            node.match[source] = max(node.match[source], confirmed)
            node.next[source] = max(node.next[source], confirmed + 1)
            self.check_commit(node)
            if (source == node.transfer_target and not node.transfer_sent
                    and node.match[source] == node.last_index):
                self.send_timeout_now(node)
            elif node.next[source] <= node.last_index:
                self.send_append(node, source)
        else:
            node.next[source] = max(node.match[source] + 1, min(node.next[source] - 1, confirmed + 1))
            self.write_trace(f"BACKTRACK n{node.number} n{source} next {node.next[source]}")
            self.send_append(node, source)

    def check_commit(self, node):
        for index in range(node.last_index, node.commit, -1):
            if node.term_at(index) != node.term:
                return
            count = 1 + sum(confirmed >= index for confirmed in node.match.values())
            if self.majority(count):
                self.write_trace(f"COMMIT n{node.number} {node.commit + 1}-{index} term {node.term}")
                self.advance_commit(node, index)
                return

    def advance_commit(self, node, index):
        for position in range(node.commit + 1, index + 1):
            self.checker.commit(position, node.term_at(position), self.time)
        node.commit = index
        first = node.applied + 1
        for position in range(first, index + 1):
            entry = node.log[position - 1]
            result = apply_command(node.store, entry.command)
            node.stats["applies"] += 1
            self.checker.apply(position, entry, result)
        node.applied = index
        self.write_trace(f"APPLY n{node.number} {first}-{index}")

    def receive(self, message):
        node = self.node(message.destination)
        if message.term > node.term:
            role = node.role
            self.write_trace(f"TERM n{node.number} {node.term}->{message.term} "
                             f"{message.kind} n{message.source} {role}")
            if role == "LEADER":
                self.end_leadership(node, "STEPDOWN")
            node.term = message.term
            node.voted_for = None
            node.known_leader = None
            node.role = "FOLLOWER"
            if role == "LEADER":
                self.set_election_timer(node)
        if message.kind == "RV":
            self.vote_request(node, message)
        elif message.kind == "RVR":
            self.vote_response(node, message)
        elif message.kind == "AE":
            self.append_request(node, message)
        elif message.kind == "AER":
            self.append_response(node, message)
        elif message.term != node.term or node.role != "FOLLOWER":
            self.write_trace(f"IGNORE n{node.number} TN n{message.source} term {message.term}")
        else:
            self.start_election(node, "transfer")

    def start_transfer(self, node, destination):
        prefix = f"TRANSFER n{node.number} n{destination}"
        if (not node.up or node.role != "LEADER" or node.transfer_target is not None
                or node.number == destination):
            self.write_trace(prefix + " ignored")
            return
        self.write_trace(f"{prefix} start match {node.match[destination]}/{node.last_index}")
        node.transfer_target = destination
        node.transfer_sent = False
        node.transfer_deadline = self.time + self.settings.election_min
        if node.match[destination] == node.last_index:
            self.send_timeout_now(node)
        else:
            self.send_append(node, destination)

    def send_timeout_now(self, node):
        self.write_trace(f"TIMEOUTNOW n{node.number} n{node.transfer_target} "
                         f"term {node.term} index {node.last_index}")
        node.transfer_sent = True
        self.send(node, node.transfer_target, "TN", {})

    def timers(self, node):
        if node.role == "LEADER":
            if node.quorum_deadline == self.time:
                if not self.majority(1 + len(node.heard)):
                    self.write_trace(f"STEPDOWN n{node.number} term {node.term} heard {node_set(node.heard)}")
                    self.end_leadership(node, "QUORUM")
                    node.role = "FOLLOWER"
                    node.known_leader = None
                    self.set_election_timer(node)
                    return
                node.heard = set()
                node.quorum_deadline = self.time + self.settings.quorum
            if node.transfer_target is not None and node.transfer_deadline == self.time:
                self.write_trace(f"TRANSFER n{node.number} n{node.transfer_target} abort")
                node.cancel_transfer()
            if node.heartbeat_deadline == self.time:
                self.broadcast_append(node)
                node.heartbeat_deadline = self.time + self.settings.heartbeat
        elif node.election_deadline == self.time:
            self.start_election(node, "timeout")

    def end_of_tick(self):
        self.checker.check_logs(self.nodes)
        leaders = [node for node in self.nodes if node.up and node.role == "LEADER"]
        for node in leaders:
            node.stats["leader_ticks"] += 1
        if leaders:
            self.leader_ticks += 1
            self.multi_ticks += len(leaders) >= 2
            if self.gap_start is not None:
                self.gaps.append((self.gap_start, self.time - 1))
                self.gap_start = None
        elif self.gap_start is None:
            self.gap_start = self.time
        if self.time % self.settings.sample == 0:
            fields = [(node.role[0] if node.up else "D") + str(node.term) for node in self.nodes]
            self.timelines.append(f"TIMELINE {self.time} " + " ".join(fields))

    def run(self):
        for node in self.nodes:
            self.set_election_timer(node)
            self.write_trace(f"START n{node.number} deadline {node.election_deadline}")
        for self.time in range(self.settings.end + 1):
            for event in self.controls.get(self.time, ()):
                self.control(event)
            attempts = self.attempt_queue.pop(self.time, ())
            for request in sorted(attempts, key=lambda request: request.number):
                self.attempt(request)
            for message in self.network.arrivals(self.time):
                if self.network.deliver(message, self.node(message.destination).up):
                    self.receive(message)
            for node in self.nodes:
                if node.up:
                    self.timers(node)
            self.end_of_tick()
        if self.gap_start is not None:
            self.gaps.append((self.gap_start, self.settings.end))
        self.finish_statistics()

    def finish_statistics(self):
        self.maximum_term = max(node.term for node in self.nodes)
        self.committed_count = len(self.checker.committed)
        needed = {node.applied for node in self.nodes}
        self.reference_states = {0: {}}
        self.reference_state = {}
        for index in range(1, self.committed_count + 1):
            entry, result = self.checker.applied[index]
            apply_command(self.reference_state, entry.command)
            if index in needed:
                self.reference_states[index] = self.reference_state.copy()
        self.status_counts = Counter()
        self.latencies = []
        self.key_requests = Counter()
        self.key_committed = Counter()
        for request in self.requests:
            key = request.command[1]
            self.key_requests[key] += 1
            if request.accepted is not None:
                index, term = request.accepted
                committed = self.checker.committed.get(index)
                if committed is not None and committed[0] == term:
                    request.status = "COMMITTED"
                    request.latency = committed[1] - request.time
                    request.result = self.checker.applied[index][1]
                    self.latencies.append(request.latency)
                    self.key_committed[key] += 1
                elif any(node.last_index >= index and node.term_at(index) == term for node in self.nodes):
                    request.status = "UNCOMMITTED"
                else:
                    request.status = "LOST"
            elif request.abandoned:
                request.status = "FAILED"
            else:
                request.status = "WAITING"
            self.status_counts[request.status] += 1

    def leader_lines(self):
        lines = []
        for record in self.elections:
            outcome = f"WON {record['won']}" if record["won"] is not None else "LOST"
            lines.append(f"ELECTION {record['time']} n{record['node']} term {record['term']} "
                         f"trigger {record['trigger']} votes {len(record['votes'])} {outcome}")
        elections_by_term = defaultdict(list)
        for record in self.elections:
            elections_by_term[record["term"]].append(record)
        for term in range(1, self.maximum_term + 1):
            elections = elections_by_term[term]
            candidates = node_set({record["node"] for record in elections})
            if term not in self.leaders:
                lines.append(f"TERM {term} NONE candidates {candidates}")
                continue
            record = self.leaders[term]
            if record["ended"] is None:
                end = "-"
                reason = "ACTIVE"
                commit = self.node(record["node"]).commit
            else:
                end = record["ended"]
                reason = record["reason"]
                commit = record["commit"]
            start = elections[0]["time"]
            wait = record["elected"] - start
            lines.append(f"TERM {term} LEADER n{record['node']} elected {record['elected']} "
                         f"votes {node_set(record['votes'])} ended {end} {reason} "
                         f"appended {record['appended']} commit {commit} candidates {candidates} "
                         f"started {start} wait {wait}")
        for node in self.nodes:
            stats = node.stats
            lines.append(f"NODE n{node.number} elections {stats['elections']} leader_terms {stats['leader_terms']} "
                         f"leader_ticks {stats['leader_ticks']} votes_granted {stats['votes_granted']}")
        lines.extend(self.timelines)
        for first, last in self.gaps:
            lines.append(f"GAP {first}-{last} length {last - first + 1}")
        longest = max((last - first + 1 for first, last in self.gaps), default=0)
        lines.append(f"SUMMARY terms {self.maximum_term} leaders {len(self.leaders)} elections {len(self.elections)} "
                     f"leader_ticks {self.leader_ticks} multi_ticks {self.multi_ticks} ticks {self.settings.end + 1} "
                     f"gaps {len(self.gaps)} longest {longest}")
        return lines

    def log_lines(self):
        lines = []
        for node in self.nodes:
            status = node.role if node.up else "DOWN"
            voted = f"n{node.voted_for}" if node.voted_for is not None else "-"
            lines.append(f"NODE n{node.number} {status} term {node.term} voted {voted} "
                         f"commit {node.commit} applied {node.applied} length {node.last_index}")
            for index, entry in enumerate(node.log, 1):
                text = f"{index} {entry.term} {command_text(entry.command)}"
                if entry.request:
                    text += f" r{entry.request}"
                lines.append(text)
        prefix = 0
        for index in range(min(node.last_index for node in self.nodes)):
            if not all(node.log[index] == self.nodes[0].log[index] for node in self.nodes[1:]):
                break
            prefix += 1
        lines.append(f"AGREE prefix {prefix} committed {self.committed_count}")
        for node in self.nodes:
            common = 0
            for index in range(1, min(node.last_index, self.committed_count) + 1):
                if node.term_at(index) != self.checker.committed[index][0]:
                    break
                common = index
            stats = node.stats
            lines.append(f"DIFF n{node.number} common {common} behind {self.committed_count - common} "
                         f"extra {node.last_index - common} ae_ok {stats['ae_ok']} ae_fail {stats['ae_fail']} "
                         f"appended {stats['appended']} truncated {stats['truncated']} applies {stats['applies']}")
        return lines

    def request_line(self, request):
        line = (f"REQUEST r{request.number} at {request.time} n{request.initial_destination} "
                f"{command_text(request.command)} attempts {request.attempts} redirects {request.redirects} ")
        if request.accepted is not None:
            index, term = request.accepted
            line += f"{request.status} index {index} term {term}"
            if request.status == "COMMITTED":
                line += f" latency {request.latency} result {request.result}"
        elif request.status == "FAILED":
            line += "FAILED"
        else:
            line += f"WAITING next {request.scheduled}"
        return line

    def state_lines(self):
        lines = []
        for node in self.nodes:
            status = "UP" if node.up else "DOWN"
            replay = "match" if node.store == self.reference_states[node.applied] else "mismatch"
            lines.append(f"NODE n{node.number} {status} applied {node.applied} keys {len(node.store)} replay {replay}")
            lines.extend(f"{key} {node.store[key]}" for key in sorted(node.store))
        lines.extend(self.request_line(request) for request in self.requests)
        for key in sorted(self.key_requests):
            value = self.reference_state.get(key, "missing")
            lines.append(f"KEY {key} requests {self.key_requests[key]} committed {self.key_committed[key]} final {value}")
        statuses = " ".join(f"{name.lower()} {self.status_counts[name]}"
                            for name in ("COMMITTED", "UNCOMMITTED", "LOST", "FAILED", "WAITING"))
        lines.append(f"REQUESTS total {len(self.requests)} {statuses}")
        lines.append(f"LATENCY count {len(self.latencies)} total {sum(self.latencies)} "
                     f"min {min(self.latencies, default=0)} max {max(self.latencies, default=0)}")
        return lines

    def safety_lines(self):
        lines = self.checker.lines(self.maximum_term)
        lines.append("MESSAGES " + " ".join(f"{field} {self.network.total[field]}" for field in FIELDS))
        for kind in TYPES:
            values = self.network.by_type[kind]
            lines.append(f"TYPE {kind} " + " ".join(f"{field} {values[field]}" for field in FIELDS))
        for (source, destination), link in self.network.links.items():
            dropped = sum(link.stats[reason] for reason in REASONS)
            lines.append(f"LINK n{source}->n{destination} delay {link.delay} loss {link.loss} "
                         f"sent {link.stats['sent']} delivered {link.stats['delivered']} dropped {dropped}")
        lines.append(f"DRAWS {self.random.draws}")
        lines.append("RESULT UNSAFE" if any(self.checker.violations.values()) else "RESULT SAFE")
        return lines

    def write_outputs(self):
        outputs = {
            "trace.txt": self.trace,
            "leaders.txt": self.leader_lines(),
            "logs.txt": self.log_lines(),
            "state.txt": self.state_lines(),
            "safety.txt": self.safety_lines(),
        }
        directory = Path("output")
        directory.mkdir(exist_ok=True)
        for filename, lines in outputs.items():
            with (directory / filename).open("w", encoding="ascii", newline="\n") as destination:
                destination.write("\n".join(lines) + "\n")


def main():
    settings = read_settings()
    controls, requests = read_script()
    simulation = Simulator(settings, controls, requests, Network(settings.nodes))
    simulation.run()
    simulation.write_outputs()


if __name__ == "__main__":
    main()
