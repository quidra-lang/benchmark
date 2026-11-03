from collections import Counter, defaultdict, deque
from fractions import Fraction
from itertools import combinations

from alpha_miner import extend_pair, pair_order, plus_relation, triangle_counts
from conformance import PetriNet, ReplayTotals, read_model
from dfg import basic_relation, directly_follows, footprint, table
from eventlog import Event, group_cases, median, read_inputs, timestamp_minutes
from heuristic_miner import dependency, join_measure, loop_measure, split_measure
from report import fraction, names, percentage, write_outputs


class ProcessStudy:
    def __init__(self, rows, parameters, reference):
        self.rows = rows
        self.parameters = {name: Fraction(value) if "/" in value else int(value)
                           for name, value in parameters.items()}
        self.reference = reference
        self.errors = []
        self.events = []
        self.validate_log()
        self.cases = group_cases(self.events)
        self.activities = sorted({event.activity for event in self.events})
        self.resources = sorted({event.resource for event in self.events})
        self.log = [(case.trace, 1) for case in self.cases]
        self.counts = directly_follows(self.log)
        self.variants = []
        self.variant_by_case = {}
        self.filtered_log = []
        self.prefixes = {}

    def validate_log(self):
        adopted = set()
        for line, case_id, activity, timestamp, resource in self.rows:
            time = timestamp_minutes(timestamp)
            if time is None:
                self.errors.append(f"line {line}: bad timestamp {timestamp}")
                continue
            identity = case_id, activity, timestamp
            if identity in adopted:
                self.errors.append(f"line {line}: duplicate event {case_id} {activity} {timestamp}")
                continue
            adopted.add(identity)
            self.events.append(Event(line, case_id, activity, timestamp, resource, time))

    def log_summary(self):
        lines = ["ERROR " + error for error in self.errors]
        earliest = min(self.events, key=lambda event: event.time)
        latest = max(self.events, key=lambda event: event.time)
        lines.append(
            f"LOG rows {len(self.rows)} adopted {len(self.events)} rejected {len(self.errors)} "
            f"cases {len(self.cases)} activities {len(self.activities)} resources {len(self.resources)} "
            f"first {earliest.timestamp} last {latest.timestamp}"
        )
        event_counts = Counter()
        case_counts = Counter()
        starts = Counter()
        ends = Counter()
        rework = Counter()
        waits = defaultdict(list)
        resources = defaultdict(set)
        weekday_events = [0] * 7
        weekday_starts = [0] * 7
        weekday_ends = [0] * 7
        for case in self.cases:
            occurrences = Counter(case.trace)
            case_counts.update(occurrences.keys())
            rework.update(activity for activity, count in occurrences.items() if count >= 2)
            starts[case.trace[0]] += 1
            ends[case.trace[-1]] += 1
            weekday_starts[(case.events[0].time // 1440 + 3) % 7] += 1
            weekday_ends[(case.events[-1].time // 1440 + 3) % 7] += 1
            for index, event in enumerate(case.events):
                event_counts[event.activity] += 1
                resources[event.activity].add(event.resource)
                weekday_events[(event.time // 1440 + 3) % 7] += 1
                if index:
                    waits[event.activity].append(event.time - case.events[index - 1].time)
        for activity in self.activities:
            values = waits[activity]
            waiting = fraction(Fraction(sum(values), len(values))) if values else "-"
            model = "yes" if activity in self.reference.inputs else "no"
            lines.append(
                f"ACTIVITY {activity} events {event_counts[activity]} cases {case_counts[activity]} "
                f"start {starts[activity]} end {ends[activity]} rework {rework[activity]} "
                f"wait {waiting} resources {len(resources[activity])} model {model}"
            )
        lengths = [len(case.events) for case in self.cases]
        durations = [case.duration for case in self.cases]
        for label, values in (("LENGTH", lengths), ("DURATION", durations)):
            lines.append(f"{label} min {min(values)} max {max(values)} "
                         f"mean {fraction(Fraction(sum(values), len(values)))} median {fraction(median(values))}")
        days = Counter(duration // 1440 for duration in durations)
        for day in range(max(days) + 1):
            lines.append(f"DAYS {day} cases {days[day]} share {percentage(days[day], len(self.cases))}")
        limit = self.parameters["sla_minutes"]
        late = sum(duration > limit for duration in durations)
        lines.append(f"SLA limit {limit} late {late} share {percentage(late, len(self.cases))}")
        for index, weekday in enumerate(("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun")):
            lines.append(f"WEEKDAY {weekday} events {weekday_events[index]} "
                         f"starts {weekday_starts[index]} ends {weekday_ends[index]}")
        return lines

    def build_variants(self):
        grouped = defaultdict(list)
        for case in self.cases:
            grouped[case.trace].append(case)
        traces = sorted(grouped, key=lambda trace: (-len(grouped[trace]), trace))
        minimum = self.parameters["filter_min_follows"]
        for number, trace in enumerate(traces, 1):
            cases = grouped[trace]
            keep = all(self.counts[first, second] >= minimum for first, second in zip(trace, trace[1:]))
            self.variants.append({"number": number, "trace": trace, "cases": cases, "keep": keep})
            for case in cases:
                self.variant_by_case[case.identifier] = number
            if keep:
                self.filtered_log.append((trace, len(cases)))
        self.kept_cases = sum(weight for _, weight in self.filtered_log)
        self.kept_events = sum(len(trace) * weight for trace, weight in self.filtered_log)

    def variant_report(self):
        lines = []
        limit = self.parameters["sla_minutes"]
        for variant in self.variants:
            cases = variant["cases"]
            trace = variant["trace"]
            count = len(cases)
            duration = Fraction(sum(case.duration for case in cases), count)
            late = sum(case.duration > limit for case in cases)
            fitness = self.reference_replays[cases[0].identifier].fitness()
            decision = "KEEP" if variant["keep"] else "DROP"
            lines.append(
                f"VARIANT {variant['number']} count {count} share {percentage(count, len(self.cases))} "
                f"length {len(trace)} first {cases[0].identifier} duration {fraction(duration)} "
                f"late {late} fitness {fraction(fitness)} {decision} {names(trace)}"
            )
        lines.append(
            f"FILTER min_follows {self.parameters['filter_min_follows']} variants {len(self.filtered_log)} "
            f"of {len(self.variants)} cases {self.kept_cases} of {len(self.cases)} "
            f"events {self.kept_events} of {len(self.events)}"
        )
        return lines

    def dfg_report(self):
        starts = Counter()
        ends = defaultdict(list)
        waiting = defaultdict(list)
        edge_cases = Counter()
        for case in self.cases:
            starts[case.trace[0]] += 1
            ends[case.trace[-1]].append(case.duration)
            present = set()
            for first, second in zip(case.events, case.events[1:]):
                pair = first.activity, second.activity
                waiting[pair].append(second.time - first.time)
                present.add(pair)
            edge_cases.update(present)
        lines = []
        for activity in sorted(starts, key=lambda activity: (-starts[activity], activity)):
            lines.append(f"START {activity} count {starts[activity]}")
        for activity in sorted(ends, key=lambda activity: (-len(ends[activity]), activity)):
            values = ends[activity]
            lines.append(f"END {activity} count {len(values)} duration {fraction(Fraction(sum(values), len(values)))}")
        for pair in sorted(self.counts, key=lambda pair: (-self.counts[pair], pair)):
            first, second = pair
            values = waiting[pair]
            lines.append(
                f"EDGE {first} {second} count {self.counts[pair]} cases {edge_cases[pair]} "
                f"mean {fraction(Fraction(sum(values), len(values)))} min {min(values)} max {max(values)}"
            )
        lines.extend(footprint(self.activities, lambda first, second: basic_relation(self.counts, first, second)))
        return lines

    def discover(self, log, activities, relation):
        candidates = set()
        pending = deque()
        causal = 0
        for first in activities:
            for second in activities:
                if relation(first, second) != "->":
                    continue
                causal += 1
                if relation(first, first) == "#" and relation(second, second) == "#":
                    pair = frozenset((first,)), frozenset((second,))
                    candidates.add(pair)
                    pending.append(pair)
        while pending:
            pair = pending.popleft()
            for activity in activities:
                for side in (0, 1):
                    extended = extend_pair(pair, activity, side, relation)
                    if extended is not None and extended not in candidates:
                        candidates.add(extended)
                        pending.append(extended)
        maximal = []
        for pair in candidates:
            has_extension = any(extend_pair(pair, activity, side, relation) is not None
                                for activity in activities for side in (0, 1))
            if not has_extension:
                maximal.append(pair)
        maximal.sort(key=pair_order)
        starts = sorted({trace[0] for trace, _ in log})
        ends = sorted({trace[-1] for trace, _ in log})
        places = ["start", *(f"p{number}" for number in range(1, len(maximal) + 1)), "end"]
        arcs = [("start", activity) for activity in starts]
        arcs.extend((activity, "end") for activity in ends)
        for number, (first, second) in enumerate(maximal, 1):
            place = f"p{number}"
            arcs.extend((activity, place) for activity in sorted(first))
            arcs.extend((place, activity) for activity in sorted(second))
        net = PetriNet(places, activities, arcs, "start", "end")
        return {"net": net, "pairs": maximal, "candidates": len(candidates), "causal": causal,
                "starts": starts, "ends": ends, "activities": activities, "relation": relation}

    def pair_line(self, discovery):
        return (f"PAIRS causal {discovery['causal']} candidates {discovery['candidates']} "
                f"maximal {len(discovery['pairs'])}")

    def net_lines(self, discovery):
        net = discovery["net"]
        lines = [f"PLACE start - {names(discovery['starts'])}"]
        for number, (first, second) in enumerate(discovery["pairs"], 1):
            lines.append(f"PLACE p{number} {names(sorted(first))} {names(sorted(second))}")
        lines.append(f"PLACE end {names(discovery['ends'])} -")
        for transition in net.transitions:
            inputs = names(net.places[index] for index in net.inputs[transition])
            outputs = names(net.places[index] for index in net.outputs[transition])
            lines.append(f"TRANSITION {transition} in {inputs} out {outputs}")
        lines.append(f"NET places {len(net.places)} transitions {len(net.transitions)} arcs {len(net.arcs)}")
        return lines

    def mine_workflows(self):
        counts = directly_follows(self.filtered_log)
        activities = sorted({activity for trace, _ in self.filtered_log for activity in trace})
        loops = [activity for activity in activities if counts[activity, activity] >= 1]
        basic = lambda first, second: basic_relation(counts, first, second)
        alpha = self.discover(self.filtered_log, activities, basic)
        lines = [f"LOG variants {len(self.filtered_log)} cases {self.kept_cases} activities {names(activities)}",
                 f"LOOPS {names(loops)}", "MINER alpha"]
        lines.extend(footprint(activities, basic))
        lines.append(self.pair_line(alpha))
        lines.extend(self.net_lines(alpha))
        loop_set = set(loops)
        reduced = [(tuple(activity for activity in trace if activity not in loop_set), weight)
                   for trace, weight in self.filtered_log]
        retained = [activity for activity in activities if activity not in loop_set]
        reduced_counts = directly_follows(reduced)
        triangles = triangle_counts(reduced)
        relation = lambda first, second: plus_relation(reduced_counts, triangles, first, second)
        alpha_plus = self.discover(reduced, retained, relation)
        lines.append("MINER alpha_plus")
        for (first, second), count in sorted(triangles.items()):
            lines.append(f"TRIANGLE {first} {second} count {count}")
        lines.extend(footprint(retained, relation))
        lines.append(self.pair_line(alpha_plus))
        arcs = alpha_plus["net"].arcs.copy()
        for activity in loops:
            before = frozenset(other for other in retained if counts[other, activity] >= 1)
            after = frozenset(other for other in retained if counts[activity, other] >= 1)
            place = "-"
            for number, pair in enumerate(alpha_plus["pairs"], 1):
                if pair == (before, after):
                    place = f"p{number}"
                    arcs.add((place, activity))
                    arcs.add((activity, place))
                    break
            lines.append(f"LOOP {activity} before {names(sorted(before))} "
                         f"after {names(sorted(after))} place {place}")
        alpha_plus["net"] = PetriNet(alpha_plus["net"].places, activities, arcs, "start", "end")
        lines.extend(self.net_lines(alpha_plus))
        self.nets = (("reference", self.reference), ("alpha", alpha["net"]), ("alpha_plus", alpha_plus["net"]))
        return lines

    def heuristic_report(self):
        counts = self.counts
        triangles = triangle_counts(self.log)
        minimum = self.parameters["positive_observations"]
        loops1 = set()
        loops2 = set()
        lines = []
        for activity in self.activities:
            count = counts[activity, activity]
            if count == 0:
                continue
            measure = loop_measure(count)
            accepted = count >= minimum and measure >= self.parameters["loop1_threshold"]
            if accepted:
                loops1.add(activity)
            verdict = "ACCEPT" if accepted else "REJECT"
            lines.append(f"L1 {activity} count {count} measure {fraction(measure)} {verdict}")
        for first, second in combinations(self.activities, 2):
            count = triangles[first, second] + triangles[second, first]
            if first in loops1 or second in loops1 or count == 0:
                continue
            measure = loop_measure(count)
            accepted = count >= minimum and measure >= self.parameters["loop2_threshold"]
            if accepted:
                loops2.add((first, second))
            verdict = "ACCEPT" if accepted else "REJECT"
            lines.append(f"L2 {first} {second} count {count} measure {fraction(measure)} {verdict}")
        measures = {pair: dependency(counts, *pair) for pair in counts if pair[0] != pair[1]}
        best_out = {}
        best_in = {}
        for (first, second), measure in measures.items():
            best_out[first] = measure if first not in best_out else max(best_out[first], measure)
            best_in[second] = measure if second not in best_in else max(best_in[second], measure)
        edges = {(activity, activity) for activity in loops1}
        relative = self.parameters["relative_to_best"]
        for (first, second), measure in sorted(measures.items()):
            if tuple(sorted((first, second))) in loops2:
                verdict = "LOOP2"
            elif counts[first, second] < minimum:
                verdict = "REJECT_COUNT"
            elif measure < self.parameters["dependency_threshold"]:
                verdict = "REJECT_MEASURE"
            elif best_out[first] - measure > relative and best_in[second] - measure > relative:
                verdict = "REJECT_BEST"
            else:
                verdict = "ACCEPT"
            if verdict in ("LOOP2", "ACCEPT"):
                edges.add((first, second))
            lines.append(f"DEP {first} {second} count {counts[first, second]} "
                         f"reverse {counts[second, first]} measure {fraction(measure)} {verdict}")
        inputs = {activity: sorted(first for first, second in edges if second == activity)
                  for activity in self.activities}
        outputs = {activity: sorted(second for first, second in edges if first == activity)
                   for activity in self.activities}
        for activity in self.activities:
            lines.append(f"NODE {activity} in {names(inputs[activity])} out {names(outputs[activity])}")
        for activity in self.activities:
            successors = [other for other in outputs[activity] if other != activity]
            predecessors = [other for other in inputs[activity] if other != activity]
            for first, second in combinations(successors, 2):
                measure = split_measure(counts, activity, first, second)
                verdict = "AND" if measure >= self.parameters["and_threshold"] else "XOR"
                lines.append(f"SPLIT {activity} {first} {second} measure {fraction(measure)} {verdict}")
            for first, second in combinations(predecessors, 2):
                measure = join_measure(counts, activity, first, second)
                verdict = "AND" if measure >= self.parameters["and_threshold"] else "XOR"
                lines.append(f"JOIN {activity} {first} {second} measure {fraction(measure)} {verdict}")
        lines.append(f"GRAPH activities {len(self.activities)} edges {len(edges)} "
                     f"loops1 {len(loops1)} loops2 {len(loops2)}")
        return lines

    def explore(self, net):
        markings = {net.initial_marking}
        pending = deque([net.initial_marking])
        edges = []
        reverse = defaultdict(set)
        enabled_at = {}
        ever_enabled = set()
        unsafe = 0
        deadlocks = 0
        while pending:
            marking = pending.popleft()
            enabled = net.enabled_transitions(marking)
            enabled_at[marking] = enabled
            ever_enabled.update(enabled)
            if not enabled and marking != net.final_marking:
                deadlocks += 1
            for transition in enabled:
                after = net.fire(marking, transition)
                if any(tokens > 1 for tokens in after):
                    unsafe += 1
                    continue
                edges.append((marking, transition, after))
                reverse[after].add(marking)
                if after not in markings:
                    markings.add(after)
                    pending.append(after)
        reachable_final = set()
        if net.final_marking in markings:
            reachable_final.add(net.final_marking)
            pending.append(net.final_marking)
        while pending:
            marking = pending.popleft()
            for before in reverse[marking]:
                if before not in reachable_final:
                    reachable_final.add(before)
                    pending.append(before)
        dead = sorted(set(net.transitions) - ever_enabled)
        stuck = len(markings) - len(reachable_final)
        follows = Counter()
        for _, transition, after in edges:
            for successor in enabled_at[after]:
                follows[transition, successor] = 1
        return {"markings": len(markings), "edges": len(edges), "unsafe": unsafe,
                "deadlocks": deadlocks, "stuck": stuck, "final": net.final_marking in markings,
                "dead": dead, "sound": unsafe == 0 and stuck == 0 and not dead, "follows": follows}

    def reachability_line(self, name, result):
        final = "yes" if result["final"] else "no"
        sound = "yes" if result["sound"] else "no"
        return (f"REACHABILITY {name} markings {result['markings']} edges {result['edges']} "
                f"unsafe {result['unsafe']} deadlocks {result['deadlocks']} stuck {result['stuck']} "
                f"final {final} dead {names(result['dead'])} sound {sound}")

    def footprint_fitness(self, name, net, follows):
        activities = sorted(set(self.activities) | set(net.transitions))
        differences = []
        for first in activities:
            for second in activities:
                observed = basic_relation(self.counts, first, second)
                modeled = basic_relation(follows, first, second)
                if observed != modeled:
                    differences.append((first, second, observed, modeled))
        cells = len(activities) * len(activities)
        fitness = Fraction(cells - len(differences), cells)
        lines = [f"FOOTPRINT {name} activities {len(activities)} cells {cells} "
                 f"differing {len(differences)} fitness {fraction(fitness)}"]
        if name == "reference":
            for first, second, observed, modeled in differences:
                if first <= second:
                    lines.append(f"DIFF {first} {second} log {observed} model {modeled}")
        return lines

    def build_prefixes(self):
        for case in self.cases:
            for length in range(len(case.trace) + 1):
                prefix = case.trace[:length]
                if prefix not in self.prefixes:
                    self.prefixes[prefix] = [0, set()]
                entry = self.prefixes[prefix]
                entry[0] += 1
                if length < len(case.trace):
                    entry[1].add(case.trace[length])

    def precision_report(self, name, net):
        markings = {}
        fitting = 0
        allowed = 0
        escaping = 0
        escape_weights = Counter()
        for prefix in sorted(self.prefixes):
            marking = net.initial_marking
            if prefix:
                marking = markings[prefix[:-1]]
                transition = prefix[-1]
                if marking is not None and transition in net.inputs and net.enabled(marking, transition):
                    marking = net.fire(marking, transition)
                else:
                    marking = None
            markings[prefix] = marking
            if marking is None:
                continue
            fitting += 1
            weight, followers = self.prefixes[prefix]
            enabled = set(net.enabled_transitions(marking))
            escapes = enabled - followers
            allowed += weight * len(enabled)
            escaping += weight * len(escapes)
            for transition in escapes:
                escape_weights[transition] += weight
        precision = Fraction(allowed - escaping, allowed) if allowed else Fraction(1)
        lines = [f"PRECISION {name} prefixes {fitting} allowed {allowed} escaping {escaping} "
                 f"precision {fraction(precision)}"]
        for transition in sorted(escape_weights, key=lambda transition: (-escape_weights[transition], transition)):
            lines.append(f"ESCAPE {name} {transition} weight {escape_weights[transition]}")
        return lines

    def replay_case(self, net, case):
        result = ReplayTotals(len(net.places))
        tokens = [deque() for _ in net.places]
        tokens[net.initial].append(case.events[0].time)
        result.produced = 1
        for event in case.events:
            transition = event.activity
            if transition not in net.inputs:
                result.skipped += 1
                continue
            for place in net.inputs[transition]:
                result.consumed += 1
                if tokens[place]:
                    produced_at = tokens[place].popleft()
                    result.waiting[place].append(event.time - produced_at)
                    result.routes[place][transition] += 1
                else:
                    result.missing += 1
                    result.place_missing[place] += 1
            for place in net.outputs[transition]:
                tokens[place].append(event.time)
                result.produced += 1
        result.consumed += 1
        if tokens[net.final]:
            tokens[net.final].popleft()
        else:
            result.missing += 1
            result.place_missing[net.final] += 1
        for place, queue in enumerate(tokens):
            remaining = len(queue)
            result.place_remaining[place] = remaining
            result.remaining += remaining
            result.deviating[place] = int(result.place_missing[place] > 0 or remaining > 0)
        return result

    def aggregate_replays(self, net):
        total = ReplayTotals(len(net.places))
        results = {}
        fitting = 0
        for case in self.cases:
            result = self.replay_case(net, case)
            results[case.identifier] = result
            fitting += int(result.missing == 0 and result.remaining == 0)
            total.missing += result.missing
            total.remaining += result.remaining
            total.consumed += result.consumed
            total.produced += result.produced
            total.skipped += result.skipped
            for place in range(len(net.places)):
                total.place_missing[place] += result.place_missing[place]
                total.place_remaining[place] += result.place_remaining[place]
                total.deviating[place] += result.deviating[place]
                total.waiting[place].extend(result.waiting[place])
                total.routes[place].update(result.routes[place])
        return total, results, fitting

    def replay_report(self, name, net, total, fitting):
        lines = [f"REPLAY {name} cases {len(self.cases)} fitting {fitting} skipped {total.skipped} "
                 f"missing {total.missing} remaining {total.remaining} consumed {total.consumed} "
                 f"produced {total.produced} fitness {fraction(total.fitness())}"]
        for index, place in enumerate(net.places):
            waiting = total.waiting[index]
            mean = fraction(Fraction(sum(waiting), len(waiting))) if waiting else "-"
            maximum = str(max(waiting)) if waiting else "-"
            lines.append(
                f"PLACE {name} {place} missing {total.place_missing[index]} remaining {total.place_remaining[index]} "
                f"deviating {total.deviating[index]} tokens {len(waiting)} mean {mean} max {maximum}"
            )
        for index, place in enumerate(net.places):
            if len(net.routes[index]) >= 2:
                consumptions = ",".join(f"{transition}={total.routes[index][transition]}"
                                        for transition in net.routes[index])
                lines.append(f"ROUTE {name} {place} {consumptions}")
        return lines

    def conformance_report(self):
        lines = [f"MODEL places {len(self.reference.places)} transitions {len(self.reference.transitions)} "
                 f"arcs {len(self.reference.arcs)}"]
        exploration = {}
        for name, net in self.nets:
            result = self.explore(net)
            exploration[name] = result
            lines.append(self.reachability_line(name, result))
        for name, net in self.nets:
            lines.extend(self.footprint_fitness(name, net, exploration[name]["follows"]))
        self.build_prefixes()
        for name, net in self.nets:
            lines.extend(self.precision_report(name, net))
        for name, net in self.nets:
            total, results, fitting = self.aggregate_replays(net)
            if name == "reference":
                self.reference_replays = results
            lines.extend(self.replay_report(name, net, total, fitting))
        return lines

    def conformance_csv(self):
        lines = ["case_id,variant,events,skipped,missing,remaining,consumed,produced,fitness"]
        for case in self.cases:
            result = self.reference_replays[case.identifier]
            lines.append(
                f"{case.identifier},{self.variant_by_case[case.identifier]},{len(case.events)},{result.skipped},"
                f"{result.missing},{result.remaining},{result.consumed},{result.produced},{fraction(result.fitness())}"
            )
        return lines

    def resource_report(self):
        events = Counter()
        cases = Counter()
        work = defaultdict(Counter)
        handovers = Counter()
        handover_cases = Counter()
        subcontracting = Counter()
        together = Counter()
        for case in self.cases:
            workers = [event.resource for event in case.events]
            present = sorted(set(workers))
            cases.update(present)
            together.update(combinations(present, 2))
            for event in case.events:
                events[event.resource] += 1
                work[event.resource][event.activity] += 1
            pairs = list(zip(workers, workers[1:]))
            handovers.update(pairs)
            handover_cases.update(set(pairs))
            for first, second, third in zip(workers, workers[1:], workers[2:]):
                if first == third and first != second:
                    subcontracting[first, second] += 1
        lines = []
        for number, resource in enumerate(self.resources, 1):
            activities = ",".join(f"{activity}={work[resource][activity]}" for activity in sorted(work[resource]))
            lines.append(f"RESOURCE {number} {resource} events {events[resource]} "
                         f"cases {cases[resource]} work {activities}")
        pairs = sorted(handovers, key=lambda pair: (-handovers[pair], pair))
        for first, second in pairs:
            if first != second:
                lines.append(f"HANDOVER {first} {second} count {handovers[first, second]} "
                             f"cases {handover_cases[first, second]}")
        rows = [[handovers[first, second] for second in self.resources] for first in self.resources]
        lines.extend(table(rows, 5))
        for first, second in sorted(subcontracting, key=lambda pair: (-subcontracting[pair], pair)):
            lines.append(f"SUBCONTRACT {first} {second} count {subcontracting[first, second]}")
        for first, second in sorted(together, key=lambda pair: (-together[pair], pair)):
            lines.append(f"TOGETHER {first} {second} cases {together[first, second]}")
        total = sum(handovers.values())
        own = sum(count for (first, second), count in handovers.items() if first == second)
        lines.append(f"TOTAL handovers {total} self {own} other {total - own}")
        return lines

    def analyze(self):
        self.build_variants()
        workflows = self.mine_workflows()
        conformance = self.conformance_report()
        return {
            "log_summary.txt": self.log_summary(),
            "variants.txt": self.variant_report(),
            "dfg.txt": self.dfg_report(),
            "alpha_net.txt": workflows,
            "heuristic_net.txt": self.heuristic_report(),
            "conformance.csv": self.conformance_csv(),
            "conformance.txt": conformance,
            "resources.txt": self.resource_report(),
        }


def main():
    rows, parameters = read_inputs()
    study = ProcessStudy(rows, parameters, read_model())
    write_outputs(study.analyze())


if __name__ == "__main__":
    main()
