"""Deterministic BGP route propagation, convergence records, and final audits."""

from collections import Counter

import decision
import policy
import report
import simulator
import topology


CONVERGENCE_HEADER = (
    "event,time,kind,status,convergence_time,updates,withdrawals,drops,"
    "best_changes,routes_changed,max_exploration"
)


def collapse_runs(path):
    result = []
    for owner in path:
        if not result or result[-1] != owner:
            result.append(owner)
    return tuple(result)


def valley_position(pattern):
    position = 0
    while position < len(pattern) and pattern[position] == "U":
        position += 1
    if position < len(pattern) and pattern[position] == "P":
        position += 1
    while position < len(pattern) and pattern[position] == "D":
        position += 1
    return position


def message_text(message):
    return (f"#{message.serial} {message.sender}->{message.receiver} {message.link.name} "
            f"{topology.prefix_text(message.prefix)}")


class Session:
    def __init__(self, owner, link):
        self.owner = owner
        self.link = link
        self.incoming = {}
        self.outgoing = {}
        self.pending = set()
        self.timer = None
        self.sent = 0
        self.received = 0


class Router:
    def __init__(self, owner, links):
        self.owner = owner
        self.origination = {}
        self.rib = {}
        self.sessions = [Session(owner, link) for link in links]
        self.changes = 0


class Period:
    def __init__(self, number, event, routers):
        self.number = number
        self.event = event
        self.before = {owner: router.rib.copy() for owner, router in routers.items()}
        self.counters = Counter()
        self.exploration = Counter()
        self.best_lines = []
        self.convergence_time = 0
        self.delivery_times = 0
        self.states = {}
        self.divergence = None
        self.status = None
        self.routes_changed = 0

    def finish(self, routers):
        for owner, router in routers.items():
            before = self.before[owner]
            for prefix in before.keys() | router.rib.keys():
                if before.get(prefix) != router.rib.get(prefix):
                    self.routes_changed += 1

    def csv_line(self):
        values = [self.number, self.event.time, self.event.kind, self.status,
                  self.convergence_time, self.counters["updates"], self.counters["withdrawals"],
                  self.counters["drops"], self.counters["best_changes"], self.routes_changed,
                  max(self.exploration.values(), default=0)]
        return ",".join(map(str, values))


class Forwarding:
    def __init__(self, result, visits, hops):
        self.result = result
        self.visits = tuple(visits)
        self.hops = tuple(hops)
        self.count = sum(link is not None for owner, prefix, link in hops)
        self.arrival = hops[-1][0] if result == "DELIVERED" else None


class Simulation:
    def __init__(self, network, policies, defaults, stepcap, traces):
        self.network = network
        self.policies = policies
        self.defaults = defaults
        self.stepcap = stepcap
        self.traces = traces
        self.routers = {owner: Router(owner, network.at_as[owner]) for owner in network.ases}
        self.sessions = [session for router in self.routers.values() for session in router.sessions]
        self.by_session = {(session.owner, session.link.number): session for session in self.sessions}
        self.messages = simulator.MessageQueue()
        self.time = 0
        self.logs = []
        self.periods = []
        self.changed_prefixes = set()
        self.trace_records = []
        self.ongoing_traces = {}
        self.ring_records = []
        self.ongoing_rings = {}

    def log(self, content):
        self.logs.append(f"{self.time} {content}")

    def import_route(self, session, prefix, attribute):
        rule = self.policies.applied("IMPORT", session.owner, session.link, prefix,
                                     attribute.path, attribute.communities)
        local_pref = self.defaults[session.link.role(session.owner)]
        if rule is not None and rule.has("DENY"):
            return None, rule
        med, communities = attribute.med, attribute.communities
        if rule is not None:
            local_pref = rule.value("LOCALPREF", local_pref)
            med = rule.value("MED", med)
            communities = policy.edit_communities(communities, rule)
        route = decision.Route(attribute.path, attribute.origin, med, communities, local_pref, session.link)
        return route, rule

    def candidates(self, owner, prefix):
        routes = []
        for session in self.routers[owner].sessions:
            if prefix in session.incoming:
                route, _ = self.import_route(session, prefix, session.incoming[prefix])
                if route is not None:
                    routes.append(route)
        return routes

    def advertised(self, session, prefix):
        owner, link = session.owner, session.link
        route = self.routers[owner].rib.get(prefix)
        if route is None:
            return None, None
        if not route.local and route.neighbor == link.other(owner):
            return None, None
        if policy.NO_EXPORT in route.communities:
            return None, None
        rule = self.policies.applied("EXPORT", owner, link, prefix, route.path, route.communities)
        if rule is not None and rule.has("DENY"):
            return None, rule
        allowed = rule is not None and rule.has("ALLOW")
        if not allowed and not route.local:
            if route.link.role(owner) in ("peer", "provider") and link.role(owner) in ("peer", "provider"):
                return None, rule
        prepend = 0 if rule is None else rule.value("PREPEND", 0)
        med = 0 if rule is None else rule.value("MED", 0)
        communities = route.communities if rule is None else policy.edit_communities(route.communities, rule)
        attribute = decision.Attribute((owner,) * (1 + prepend) + route.path, route.origin, med, communities)
        return attribute, rule

    def redecide(self, owner, prefix):
        router = self.routers[owner]
        if prefix in router.origination:
            route = router.origination[prefix]
        else:
            candidates = self.candidates(owner, prefix)
            route = decision.best_route(candidates, self.network.router_ids)[0] if candidates else None
        if router.rib.get(prefix) == route:
            return
        if route is None:
            router.rib.pop(prefix, None)
        else:
            router.rib[prefix] = route
        self.log(f"BEST {owner} {topology.prefix_text(prefix)} {report.route_text(route)}")
        router.changes += 1
        self.period.counters["best_changes"] += 1
        self.period.exploration[owner, prefix] += 1
        self.period.best_lines.append((self.time, owner, prefix, route))
        self.changed_prefixes.add(prefix)
        for session in router.sessions:
            if session.link.up:
                session.pending.add(prefix)
                if session.timer is None:
                    self.process_pending(session)

    def process_pending(self, session):
        sent = 0
        for prefix in sorted(session.pending):
            content, rule = self.advertised(session, prefix)
            if session.outgoing.get(prefix) == content:
                continue
            if content is None:
                session.outgoing.pop(prefix, None)
            else:
                session.outgoing[prefix] = content
            message = self.messages.send(self.time, session.owner, session.link.other(session.owner),
                                         session.link, prefix, content)
            suffix = "WITHDRAW" if content is None else "ANNOUNCE " + report.attribute_text(content)
            self.log(f"SEND {message_text(message)} {suffix}")
            session.sent += 1
            sent += 1
            self.period.counters["updates"] += 1
            if content is None:
                self.period.counters["withdrawals"] += 1
            if rule is not None:
                rule.hits += 1
        session.pending.clear()
        session.timer = self.time + session.link.mrai if sent and session.link.mrai >= 1 else None

    def receive(self, message):
        session = self.by_session[message.receiver, message.link.number]
        prefix, content = message.prefix, message.content
        session.received += 1
        self.period.convergence_time = self.time - self.period.event.time
        if content is None:
            session.incoming.pop(prefix, None)
            result = "WITHDRAW"
        elif message.receiver in content.path:
            session.incoming.pop(prefix, None)
            result = "ANNOUNCE loop"
        else:
            session.incoming[prefix] = content
            route, rule = self.import_route(session, prefix, content)
            if rule is not None:
                rule.hits += 1
            if route is None:
                result = f"ANNOUNCE deny {rule.name}"
            elif rule is not None:
                result = f"ANNOUNCE accept {rule.name}"
            else:
                result = "ANNOUNCE accept"
        self.log(f"RECV {message_text(message)} {result}")
        self.redecide(message.receiver, prefix)

    def originate(self, owner, prefix, origin, communities):
        self.routers[owner].origination[prefix] = decision.Route.originated(
            origin, policy.parse_communities(communities))
        self.redecide(owner, prefix)

    def link_down(self, link):
        link.up = False
        link.down_count += 1
        for message in self.messages.remove_link(link):
            self.log("DROP " + message_text(message))
            self.period.counters["drops"] += 1
        remembered = {}
        endpoints = sorted((link.first, link.second))
        for owner in endpoints:
            session = self.by_session[owner, link.number]
            remembered[owner] = sorted(session.incoming)
            session.incoming.clear()
            session.outgoing.clear()
            session.pending.clear()
            session.timer = None
        for owner in endpoints:
            for prefix in remembered[owner]:
                self.redecide(owner, prefix)

    def link_up(self, link):
        link.up = True
        for owner in sorted((link.first, link.second)):
            session = self.by_session[owner, link.number]
            session.pending = set(self.routers[owner].rib)
            self.process_pending(session)

    def change_policy(self, rule, active):
        rule.active = active
        router = self.routers[rule.owner]
        if rule.direction == "IMPORT":
            prefixes = set()
            for session in router.sessions:
                prefixes.update(session.incoming)
            for prefix in sorted(prefixes):
                self.redecide(rule.owner, prefix)
        else:
            for session in router.sessions:
                if session.link.up:
                    session.pending.update(router.rib)
                    session.pending.update(session.outgoing)
                    if session.timer is None:
                        self.process_pending(session)

    def execute_event(self, event):
        self.log(f"EVENT {self.period.number} {event.text}")
        fields = event.fields
        if event.kind == "INITIAL":
            for owner, prefix, origin, communities in self.network.initial:
                self.originate(owner, prefix, origin, communities)
        elif event.kind == "ANNOUNCE":
            self.originate(int(fields[1]), topology.parse_prefix(fields[2]), fields[3], fields[4:])
        elif event.kind == "WITHDRAW":
            owner, prefix = int(fields[1]), topology.parse_prefix(fields[2])
            self.routers[owner].origination.pop(prefix)
            self.redecide(owner, prefix)
        elif event.kind == "LINK_DOWN":
            self.link_down(self.network.by_name[fields[2]])
        elif event.kind == "LINK_UP":
            self.link_up(self.network.by_name[fields[2]])
        else:
            self.change_policy(self.policies.by_name[fields[2]], event.kind == "POLICY_ON")

    def global_state(self):
        sessions = []
        for session in self.sessions:
            incoming = tuple(sorted(session.incoming.items()))
            outgoing = tuple(sorted(session.outgoing.items()))
            pending = tuple(sorted(session.pending))
            remaining = None if session.timer is None else session.timer - self.time
            sessions.append((incoming, outgoing, pending, remaining))
        return tuple(sessions), self.messages.state(self.time)

    def detect_divergence(self):
        period = self.period
        if period.divergence is not None or period.delivery_times > self.stepcap:
            return
        state = self.global_state()
        if state in period.states:
            first = period.states[state]
            cycle = [entry for entry in period.best_lines if first < entry[0] <= self.time]
            period.divergence = first, self.time, cycle
        else:
            period.states[state] = self.time

    def quiet(self):
        return self.messages.next_time() is None and all(not session.pending for session in self.sessions)

    def next_moment(self, boundary):
        candidates = []
        delivery = self.messages.next_time()
        if delivery is not None:
            candidates.append(delivery)
        candidates.extend(session.timer for session in self.sessions if session.timer is not None)
        if boundary is not None:
            candidates.append(boundary)
        return min(candidates)

    def run_period(self, number, event, boundary):
        self.period = Period(number, event, self.routers)
        self.periods.append(self.period)
        self.time = event.time
        self.changed_prefixes = set()
        self.execute_event(event)
        while True:
            delivered = False
            while self.messages.next_time() == self.time:
                self.receive(self.messages.take())
                delivered = True
            for session in self.sessions:
                if session.timer == self.time:
                    session.timer = None
                    if session.pending:
                        self.process_pending(session)
            if self.changed_prefixes:
                self.forwarding_checks()
            if delivered:
                self.period.delivery_times += 1
                self.detect_divergence()
            quiet = self.quiet()
            if boundary is None:
                if quiet or self.period.divergence is not None or self.period.delivery_times >= self.stepcap:
                    break
            elif self.time == boundary:
                break
            self.time = self.next_moment(boundary)
            self.changed_prefixes = set()
        if self.period.divergence is not None:
            self.period.status = "DIVERGENT"
        elif quiet:
            self.period.status = "CONVERGED"
        else:
            self.period.status = "CAPPED" if boundary is None else "UNSETTLED"
        self.period.finish(self.routers)
        self.period.states.clear()

    def run(self, events):
        for number, event in enumerate(events):
            boundary = events[number + 1].time - 1 if number + 1 < len(events) else None
            self.run_period(number, event, boundary)

    def trace(self, source, address):
        visits = [source]
        visited = {source}
        hops = []
        owner = source
        while True:
            matches = [prefix for prefix in self.routers[owner].rib if topology.contains(prefix, address)]
            if not matches:
                return Forwarding("UNREACHABLE" if not hops else "BLACKHOLE", visits, hops)
            prefix = max(matches, key=lambda item: item[1])
            route = self.routers[owner].rib[prefix]
            if route.local:
                hops.append((owner, prefix, None))
                return Forwarding("DELIVERED", visits, hops)
            hops.append((owner, prefix, route.link))
            owner = route.link.other(owner)
            visits.append(owner)
            if owner in visited:
                return Forwarding("LOOP", visits, hops)
            visited.add(owner)

    def prefix_loops(self, prefix):
        arrows = {}
        for owner, router in self.routers.items():
            route = router.rib.get(prefix)
            if route is not None and not route.local:
                arrows[owner] = route.link.other(owner)
        finished = set()
        loops = set()
        for start in self.network.ases:
            if start in finished:
                continue
            path, positions = [], {}
            current = start
            while current in arrows and current not in finished and current not in positions:
                positions[current] = len(path)
                path.append(current)
                current = arrows[current]
            if current in positions:
                cycle = path[positions[current]:]
                first = cycle.index(min(cycle))
                loops.add(tuple(cycle[first:] + cycle[:first]))
            finished.update(path)
        return loops

    def forwarding_checks(self):
        for prefix in sorted(self.changed_prefixes):
            loops = self.prefix_loops(prefix)
            for key, record in list(self.ongoing_rings.items()):
                if key[0] == prefix and key[1] not in loops:
                    record["end"] = self.time
                    del self.ongoing_rings[key]
            for loop in sorted(loops):
                key = prefix, loop
                if key not in self.ongoing_rings:
                    record = {"prefix": prefix, "path": loop, "start": self.time, "end": None}
                    self.ring_records.append(record)
                    self.ongoing_rings[key] = record
        for index, (source, address, value) in enumerate(self.traces):
            path = self.trace(source, value)
            status = (path.result, path.visits) if path.result in ("LOOP", "BLACKHOLE") else None
            record = self.ongoing_traces.get(index)
            if record is not None and record["status"] != status:
                record["end"] = self.time
                del self.ongoing_traces[index]
            if status is not None and index not in self.ongoing_traces:
                record = {"index": index, "status": status, "start": self.time, "end": None}
                self.trace_records.append(record)
                self.ongoing_traces[index] = record

    def rib_lines(self):
        lines = []
        for owner, router in self.routers.items():
            local = sum(route.local for route in router.rib.values())
            sent = sum(session.sent for session in router.sessions)
            received = sum(session.received for session in router.sessions)
            lines.append(f"AS {owner} routes {len(router.rib)} local {local} sent {sent} "
                         f"received {received} changes {router.changes}")
            for session in router.sessions:
                accepted = sum(self.import_route(session, prefix, attribute)[0] is not None
                               for prefix, attribute in session.incoming.items())
                link = session.link
                state = "UP" if link.up else "DOWN"
                lines.append(f"SESSION {link.name} {link.other(owner)} {link.role(owner)} {state} "
                             f"in {len(session.incoming)} accepted {accepted} out {len(session.outgoing)} "
                             f"sent {session.sent} received {session.received} flaps {link.down_count}")
            for prefix, route in sorted(router.rib.items()):
                candidates = self.candidates(owner, prefix)
                line = f"{topology.prefix_text(prefix)} {report.route_text(route)} candidates {len(candidates)}"
                if not route.local:
                    _, reason = decision.best_route(candidates, self.network.router_ids)
                    line += " reason " + reason
                lines.append(line)
                remaining = [candidate for candidate in candidates if candidate != route]
                while remaining:
                    alternate, _ = decision.best_route(remaining, self.network.router_ids)
                    lines.append("ALT " + report.route_text(alternate))
                    remaining.remove(alternate)
        return lines

    def trace_lines(self, source, address, value):
        path = self.trace(source, value)
        lines = [f"TRACE {source} {address} {path.result} hops {path.count}"]
        for owner, prefix, link in path.hops:
            beginning = f"HOP {owner} {topology.prefix_text(prefix)}"
            if link is None:
                lines.append(beginning + " LOCAL")
            else:
                lines.append(beginning + f" next {link.other(owner)} link {link.name}")
        if path.result == "LOOP":
            lines.append(f"HOP {path.visits[-1]} REVISIT")
        elif path.result in ("BLACKHOLE", "UNREACHABLE"):
            lines.append(f"HOP {path.visits[-1]} NOROUTE")
        if not path.hops:
            lines.append("CONTROL NONE")
        else:
            first_prefix = path.hops[0][1]
            route = self.routers[source].rib[first_prefix]
            notation = "LOCAL" if route.local else report.path_text(route.path)
            match = path.result == "DELIVERED" and collapse_runs(route.path) == path.visits[1:]
            lines.append(f"CONTROL {notation} " + ("MATCH" if match else "MISMATCH"))
        if path.count:
            pattern = "".join(link.direction(owner) for owner, prefix, link in path.hops if link is not None)
            judgment = "VALLEYFREE" if valley_position(pattern) == len(pattern) else "VALLEY"
            lines.append(f"PATTERN {pattern} {judgment}")
        return lines

    def path_lines(self):
        lines = []
        for source, address, value in self.traces:
            lines.extend(self.trace_lines(source, address, value))
        originated = set()
        for router in self.routers.values():
            originated.update(router.origination)
        prefixes = sorted(originated)
        names = ",".join(topology.prefix_text(prefix) for prefix in prefixes)
        lines.append("PREFIXES" + (" " + names if names else ""))
        for source in self.network.ases:
            symbols = []
            for prefix in prefixes:
                path = self.trace(source, prefix[0])
                if path.result == "DELIVERED":
                    if path.count == 0:
                        symbols.append("*")
                    elif prefix in self.routers[path.arrival].origination:
                        symbols.append("+")
                    else:
                        symbols.append("X")
                else:
                    symbols.append({"LOOP": "L", "BLACKHOLE": "B", "UNREACHABLE": "U"}[path.result])
            joined = "".join(symbols)
            lines.append(f"REACH {source}" + (" " + joined if joined else ""))
        return lines

    def audit_lines(self):
        lines = []
        trace_totals = Counter()
        records = sorted(self.trace_records, key=lambda record: (record["start"], record["index"]))
        for record in records:
            source, address, _ = self.traces[record["index"]]
            result, visits = record["status"]
            trace_totals[result] += 1
            end = "END" if record["end"] is None else str(record["end"])
            line = f"{result} {source} {address} from {record['start']} to {end}"
            if result == "BLACKHOLE":
                line += f" at {visits[-1]}"
            lines.append(line + " path " + report.path_text(visits))
        rings = sorted(self.ring_records,
                       key=lambda record: (record["start"], record["prefix"], record["path"][0]))
        for record in rings:
            end = "END" if record["end"] is None else str(record["end"])
            lines.append(f"RING {topology.prefix_text(record['prefix'])} from {record['start']} to {end} "
                         f"path {report.path_text(record['path'])}")
        routes, valleys = 0, 0
        for owner, router in self.routers.items():
            for prefix, route in sorted(router.rib.items()):
                if route.local:
                    continue
                routes += 1
                path = collapse_runs((owner,) + route.path)
                pattern = "".join(self.network.connecting(first, second)[0].direction(first)
                                  for first, second in zip(path, path[1:]))
                violation = valley_position(pattern)
                if violation != len(pattern):
                    valleys += 1
                    lines.append(f"VALLEY {owner} {topology.prefix_text(prefix)} path {report.path_text(route.path)} "
                                 f"pattern {pattern} leaker {path[violation]}")
        for rule in self.policies.rules:
            state = "ON" if rule.active else "OFF"
            lines.append(f"RULE {rule.name} {rule.direction} {state} hits {rule.hits}")
        divergent = 0
        for period in self.periods:
            if period.divergence is None:
                continue
            divergent += 1
            first, repeat, cycle = period.divergence
            lines.append(f"DIVERGENT event {period.number} first {first} repeat {repeat} period {repeat - first}")
            oscillations = Counter()
            for time, owner, prefix, route in cycle:
                lines.append(f"CYCLE {time} {owner} {topology.prefix_text(prefix)} {report.route_text(route)}")
                oscillations[owner, prefix] += 1
            for (owner, prefix), count in sorted(oscillations.items()):
                lines.append(f"OSCILLATE {owner} {topology.prefix_text(prefix)} changes {count}")
        lines.append(f"SUMMARY loops {trace_totals['LOOP']} blackholes {trace_totals['BLACKHOLE']} "
                     f"rings {len(rings)} routes {routes} valleys {valleys} divergent {divergent} end {self.time}")
        return lines

    def write_outputs(self):
        report.write_reports({
            "updates.txt": self.logs,
            "convergence.csv": [CONVERGENCE_HEADER] + [period.csv_line() for period in self.periods],
            "ribs.txt": self.rib_lines(),
            "paths.txt": self.path_lines(),
            "audit.txt": self.audit_lines(),
        })


def main():
    network = topology.read_topology()
    policies = policy.read_policies()
    events = simulator.read_events()
    defaults, stepcap, traces = simulator.read_params()
    simulation = Simulation(network, policies, defaults, stepcap, traces)
    simulation.run(events)
    simulation.write_outputs()


if __name__ == "__main__":
    main()
