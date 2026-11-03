"""Benchmark multi-agent warehouse pathfinding: PP, CBS, ICBS and WHCA.

The six Python modules live in the same language directory. Run this file
from the task directory so input/ and output/ have their specified locations.
All algorithms use integer arithmetic and deterministic action ordering.
"""

from collections import Counter, defaultdict, deque
from heapq import heappop, heappush
from pathlib import Path

from cbs import (
    conflicts, key as node_key, new_node, ordered_constraints,
    plan_cost, position, split_constraints,
)
from grid_map import (
    destinations, distance_table, grid_statistics, neighbors,
    read_agents, read_grid,
)
from low_level import Budget, BudgetExceeded, Prohibitions, reserve_path, search
from prioritized import try_order
from report import (
    action_string, agent_name, cell_text, conflict_text,
    csv_line, fraction, picture, save_file,
)


def read_parameters(n, path="input/params.txt"):
    """Read exact run order, alternative PP priorities, delays and animation."""
    settings = {"orders": [], "runs": [], "delays": []}
    for line in Path(path).read_text(encoding="ascii").splitlines():
        pieces = line.split(" ")
        kind, args = pieces[0], pieces[1:]
        if kind == "HORIZON":
            settings["horizon"] = int(args[0])
        elif kind == "HL_BUDGET":
            settings["hl_budget"] = int(args[0])
        elif kind == "LL_BUDGET":
            settings["ll_budget"] = int(args[0])
        elif kind == "WINDOW":
            settings["window"], settings["step"] = map(int, args)
        elif kind == "ORDER":
            settings["orders"].append(tuple(map(int, args)))
        elif kind == "RUN":
            solver, cost_function = args
            settings["runs"].append({
                "name": solver + "-" + cost_function,
                "solver": solver,
                "cost_function": cost_function,
            })
        elif kind == "ANIMATE":
            settings["animate"] = args[0]
            settings["frames"] = int(args[1])
        elif kind == "DELAY":
            settings["delays"].append(tuple(map(int, args)))
    settings["orders"].insert(0, tuple(range(n)))
    return settings


def walk_allowed(grid, restrictions, source, destination, time):
    return (
        destination in grid["free"]
        and restrictions.action_allowed(source, destination, time)
    )


def mdd_layers(grid, agent, distances, length, restrictions):
    """Forward and backward reachability for all feasible walks of length c."""
    layers = [{agent["start"]}]
    for time in range(1, length + 1):
        next_layer = set()
        for cell in layers[-1]:
            for destination, _ in destinations(grid, cell):
                if (time + distances.get(destination, length + 1) <= length
                        and walk_allowed(
                            grid, restrictions, cell, destination, time
                        )):
                    next_layer.add(destination)
        layers.append(next_layer)
    valid = [set() for _ in range(length + 1)]
    valid[-1].add(agent["goal"])
    for time in range(length - 1, -1, -1):
        valid[time] = {
            source for source in layers[time]
            if any(
                next_cell in valid[time + 1]
                and walk_allowed(grid, restrictions, source, next_cell, time + 1)
                for next_cell, _ in destinations(grid, source)
            )
        }
    return valid


def mdd_properties(layers):
    return sum(len(layer) for layer in layers), max(map(len, layers))


def conflict_class(conflict, paths, restrictions, grid, agents, distances,
                   cache=None):
    """Count agents forced into the conflicting state(s) by their MDDs."""
    fixed = []
    for number in (conflict["a"], conflict["b"]):
        length = len(paths[number]) - 1
        if cache is not None and number in cache:
            layers = cache[number]
        else:
            layers = mdd_layers(
                grid, agents[number], distances[number], length,
                restrictions[number],
            )
            if cache is not None:
                cache[number] = layers
        time = conflict["time"]
        if time > length:
            forced = True
        elif conflict["kind"] == "vertex":
            forced = len(layers[time]) == 1
        else:
            forced = len(layers[time - 1]) == 1 and len(layers[time]) == 1
        fixed.append(forced)
    return (
        "cardinal" if all(fixed)
        else "semi_cardinal" if any(fixed)
        else "non_cardinal"
    )


def independent_plan(grid, agents, distances, horizon):
    """Generate baseline shortest paths; ignore low-level run budgets."""
    unrestricted = Prohibitions()
    budget = Budget()
    paths = []
    for index, agent in enumerate(agents):
        path, _ = search(
            grid, agent, distances[index], agent["start"], 0,
            unrestricted, horizon, budget,
        )
        paths.append(path)
    return paths


def conflict_groups(conflict_list, count):
    adjacent = {i: set() for i in range(count)}
    for conflict in conflict_list:
        a, b = conflict["a"], conflict["b"]
        adjacent[a].add(b)
        adjacent[b].add(a)
    seen = set()
    result = []
    for start in range(count):
        if start in seen or not adjacent[start]:
            continue
        component = []
        queue = deque([start])
        seen.add(start)
        while queue:
            current = queue.popleft()
            component.append(current)
            for other in sorted(adjacent[current]):
                if other not in seen:
                    seen.add(other)
                    queue.append(other)
        if len(component) > 1:
            result.append("".join(agent_name(i) for i in sorted(component)))
    return result


def instance_overview(grid, agents, distances, independent):
    """Shared overview computed before any solver run."""
    degree_counts = grid_statistics(grid)
    restrictions = [Prohibitions() for _ in agents]
    agent_info = []
    for index, agent in enumerate(agents):
        shortest = distances[index][agent["start"]]
        layers = mdd_layers(grid, agent, distances[index], shortest,
                            restrictions[index])
        state_count, width = mdd_properties(layers)
        agent_info.append({
            "shortest": shortest, "mdd_states": state_count,
            "mdd_width": width,
        })
    conflict_list = conflicts(independent)
    cache = {}
    for conflict in conflict_list:
        conflict["class"] = conflict_class(
            conflict, independent, restrictions, grid, agents, distances,
            cache=cache,
        )
    class_counts = Counter(conflict["class"] for conflict in conflict_list)
    kind_counts = Counter(conflict["kind"] for conflict in conflict_list)
    return {
        "degrees": degree_counts, "agents": agent_info,
        "soc_lower": sum(info["shortest"] for info in agent_info),
        "makespan_lower": max(info["shortest"] for info in agent_info),
        "independent_conflicts": conflict_list,
        "independent_class_counts": class_counts,
        "independent_kind_counts": kind_counts,
        "groups": conflict_groups(conflict_list, len(agents)),
    }


def start_run(definition, settings):
    """Create a fresh expansion/search budget for each solver/cost combination."""
    return {
        **definition, "status": "FAIL", "reason": None,
        "paths": None, "high_level": 0, "generated": None,
        "budget": Budget(settings["ll_budget"]),
        "specific": [], "trace": [], "end": "",
    }


def solve_pp(run, grid, agents, distances, settings):
    """Try number order then each supplied ORDER until complete or budget abort."""
    budget = run["budget"]
    for order_number, order in enumerate(settings["orders"], 1):
        run["high_level"] += 1
        before = budget.expansions
        paths, attempts, failure = try_order(
            grid, agents, distances, settings["horizon"], order, budget,
        )
        names = "".join(agent_name(i) for i in order)
        for item in attempts:
            prefix = f"order {order_number} agent {agent_name(item['agent'])}"
            if item["path"] is None:
                run["trace"].append(
                    f"{prefix} failed expansions {item['expansions']}"
                )
            else:
                run["trace"].append(
                    f"{prefix} cost {len(item['path']) - 1} "
                    f"expansions {item['expansions']}"
                )
        if failure == "ll_budget":
            run["reason"] = "ll_budget"
            break
        expansion_count = budget.expansions - before
        summary = (f"order {order_number} {names} planned "
                   f"{len(attempts) if failure is None else len(attempts) - 1} "
                   f"expansions {expansion_count}")
        if failure is None:
            run["specific"].append(summary + " ok")
            run["paths"] = paths
            run["status"] = "OK"
            run["answer_order"] = order_number
            break
        run["specific"].append(summary + f" failed {agent_name(failure)}")
    if run["status"] == "OK":
        run["end"] = f"end OK order {run['answer_order']}"
    else:
        run["reason"] = run["reason"] or "orders"
        run["end"] = f"end FAIL {run['reason']}"


def apply_constraint(base, addition):
    """Clone restrictions per agent, then add exactly the new branch constraint."""
    agent, kind, value, time = addition
    copied = list(base)
    changed = copied[agent].copy()
    if kind == "vertex":
        changed.states.add((value, time))
    else:
        u, v = value
        changed.moves.add((u, v, time))
    copied[agent] = changed
    return copied


def choose_split(node, run, grid, agents, distances):
    if run["solver"] == "CBS":
        return node["conflicts"][0], None
    labels = ("cardinal", "semi_cardinal", "non_cardinal")
    classified = []
    cache = {}
    for conflict in node["conflicts"]:
        category = conflict_class(
            conflict, node["paths"], node["constraints"],
            grid, agents, distances, cache,
        )
        classified.append(category)
    best_index = min(
        range(len(classified)), key=lambda i: (labels.index(classified[i]), i)
    )
    return node["conflicts"][best_index], classified[best_index]


def solve_cbs(run, grid, agents, distances, settings):
    """Best-first constraint tree with cardinal-first optional conflict splitting."""
    budget = run["budget"]
    count = len(agents)
    empty = [Prohibitions() for _ in agents]
    paths = []
    try:
        for i, agent in enumerate(agents):
            path, _ = search(
                grid, agent, distances[i], agent["start"], 0,
                empty[i], settings["horizon"], budget,
            )
            paths.append(path)
    except BudgetExceeded:
        run["reason"] = "ll_budget"
        run["generated"] = 0
        run["specific"] = [
            "search expanded 0 generated 0 pruned 0 open 0"
        ]
        if run["solver"] == "ICBS":
            run["specific"].append(
                "classes cardinal 0 semi_cardinal 0 non_cardinal 0"
            )
        run["end"] = "end FAIL ll_budget"
        return
    root = new_node(paths, empty, 0, 0, None, run["cost_function"])
    nodes = {0: root}
    open_heap = [(node_key(root), root["number"])]
    generated = 1
    expanded = 0
    pruned = 0
    classifications = Counter()
    reason = "exhausted"
    answer = None
    while open_heap:
        _, number = heappop(open_heap)
        node = nodes[number]
        if not node["conflicts"]:
            answer = node
            reason = None
            break
        if expanded == settings["hl_budget"]:
            reason = "hl_budget"
            break
        expanded += 1
        conflict, category = choose_split(
            node, run, grid, agents, distances
        )
        if category:
            classifications[category] += 1
        created = []
        aborted = False
        for branch in split_constraints(conflict):
            affected = branch[0]
            restrictions = apply_constraint(node["constraints"], branch)
            try:
                child_path, _ = search(
                    grid, agents[affected], distances[affected],
                    agents[affected]["start"], 0,
                    restrictions[affected], settings["horizon"], budget,
                )
            except BudgetExceeded:
                aborted = True
                break
            if child_path is None:
                pruned += 1
                created.append("-")
                continue
            new_paths = list(node["paths"])
            new_paths[affected] = child_path
            child = new_node(
                new_paths, restrictions, generated, node["depth"] + 1,
                node["number"], run["cost_function"],
            )
            nodes[generated] = child
            heappush(open_heap, (node_key(child), generated))
            created.append(str(generated))
            generated += 1
        if aborted:
            reason = "ll_budget"
            break
        parent = "-" if node["parent"] is None else node["parent"]
        text = (
            f"expand {expanded} node {node['number']} parent {parent} "
            f"depth {node['depth']} cost {node['cost']} "
            f"conflicts {len(node['conflicts'])} split "
            f"{conflict_text(conflict)}"
        )
        if category:
            text += f" class {category}"
        run["trace"].append(
            text + f" children {created[0]} {created[1]}"
        )
    run["high_level"] = expanded
    run["generated"] = generated
    run["specific"].append(
        f"search expanded {expanded} generated {generated} "
        f"pruned {pruned} open {len(open_heap)}"
    )
    if run["solver"] == "ICBS":
        run["specific"].append(
            f"classes cardinal {classifications['cardinal']} "
            f"semi_cardinal {classifications['semi_cardinal']} "
            f"non_cardinal {classifications['non_cardinal']}"
        )
    if answer is None:
        run["reason"] = reason
        run["end"] = f"end FAIL {reason}"
        return
    run["status"] = "OK"
    run["paths"] = answer["paths"]
    run["answer_node"] = answer["number"]
    run["specific"].append(
        f"solution node {answer['number']} depth {answer['depth']}"
    )
    for agent, time, _, u, v, kind in ordered_constraints(answer):
        if kind == "vertex":
            run["specific"].append(
                f"constraint {agent_name(agent)} vertex {cell_text(u)} t {time}"
            )
        else:
            run["specific"].append(
                f"constraint {agent_name(agent)} edge "
                f"{cell_text(u)} {cell_text(v)} t {time}"
            )
    run["end"] = f"end OK node {answer['number']} cost {answer['cost']}"


def trim_goal_tail(path, goal):
    while len(path) > 1 and path[-1] == goal and path[-2] == goal:
        path.pop()
    return path


def solve_whca(run, grid, agents, distances, settings):
    """Replan every window, execute s actions, and retain full time history."""
    horizon, window, step = (
        settings["horizon"], settings["window"], settings["step"]
    )
    current = [agent["start"] for agent in agents]
    executed = [[agent["start"]] for agent in agents]
    time = 0
    rounds = 0
    reason = None
    while not all(
        current[i] == agent["goal"] for i, agent in enumerate(agents)
    ):
        if time >= horizon:
            reason = "timeout"
            break
        rounds += 1
        restrictions = Prohibitions()
        order = (
            [i for i, agent in enumerate(agents)
             if current[i] != agent["goal"]]
            + [i for i, agent in enumerate(agents)
               if current[i] == agent["goal"]]
        )
        plans = {}
        failed = False
        for i in order:
            try:
                path, expansions = search(
                    grid, agents[i], distances[i], current[i], time,
                    restrictions, time + window, run["budget"], window=True,
                )
            except BudgetExceeded:
                reason = "ll_budget"
                failed = True
                break
            prefix = (
                f"round {rounds} time {time} agent {agent_name(i)}"
            )
            if path is None:
                run["trace"].append(
                    f"{prefix} blocked expansions {expansions}"
                )
                reason = "blocked"
                failed = True
                break
            extended = path + [path[-1]] * (window + 1 - len(path))
            plans[i] = extended
            run["trace"].append(
                f"{prefix} moves {action_string(extended)} "
                f"expansions {expansions}"
            )
            reserve_path(restrictions, extended, start_time=time)
        if failed:
            break
        for i in range(len(agents)):
            executed[i].extend(plans[i][1:step + 1])
            current[i] = plans[i][step]
        time += step
    run["high_level"] = rounds
    run["specific"].append(
        f"window {window} step {step} rounds {rounds}"
    )
    if reason:
        run["reason"] = reason
        run["end"] = f"end FAIL {reason}"
    else:
        run["status"] = "OK"
        run["paths"] = [
            trim_goal_tail(path, agent["goal"])
            for path, agent in zip(executed, agents)
        ]
        run["end"] = f"end OK rounds {rounds}"


def run_solvers(grid, agents, distances, settings):
    results = []
    for definition in settings["runs"]:
        run = start_run(definition, settings)
        if run["solver"] == "PP":
            solve_pp(run, grid, agents, distances, settings)
        elif run["solver"] in ("CBS", "ICBS"):
            solve_cbs(run, grid, agents, distances, settings)
        else:
            solve_whca(run, grid, agents, distances, settings)
        results.append(run)
    return results


def validate_plan(paths, agents, grid):
    """Check path endpoints, legal individual actions, conflicts and follows."""
    start = sum(
        path[0] != agent["start"] for path, agent in zip(paths, agents)
    )
    goal = sum(
        path[-1] != agent["goal"] for path, agent in zip(paths, agents)
    )
    illegal_moves = sum(
        destination not in (p for p, _ in destinations(grid, source))
        for path in paths for source, destination in zip(path, path[1:])
    )
    collisions = conflicts(paths)
    vertex_count = sum(c["kind"] == "vertex" for c in collisions)
    edge_count = len(collisions) - vertex_count
    horizon = max(len(path) - 1 for path in paths)
    follows = 0
    for time in range(1, horizon + 1):
        for first in range(len(paths)):
            past_a = position(paths[first], time - 1)
            next_a = position(paths[first], time)
            if next_a == past_a:
                continue
            for second in range(len(paths)):
                if first == second:
                    continue
                past_b = position(paths[second], time - 1)
                next_b = position(paths[second], time)
                if next_a == past_b and next_b != past_a:
                    follows += 1
    valid = not any((start, goal, illegal_moves, vertex_count, edge_count))
    return {
        "verdict": "VALID" if valid else "INVALID",
        "start": start, "goal": goal, "moves": illegal_moves,
        "vertex": vertex_count, "edge": edge_count,
        "follows": follows, "conflicts": collisions,
    }


def path_statistics(path, goal, lower):
    moves = []
    waits = 0
    turns = 0
    for first, second in zip(path, path[1:]):
        delta = (second[0] - first[0], second[1] - first[1])
        if delta == (0, 0):
            waits += 1
        else:
            moves.append(delta)
    for first, second in zip(moves, moves[1:]):
        if first != second:
            turns += 1
    arrive = next(i for i, cell in enumerate(path) if cell == goal)
    leaves = sum(
        earlier == goal and later != goal
        for earlier, later in zip(path, path[1:])
    )
    return {
        "cost": len(path) - 1,
        "extra": len(path) - 1 - lower,
        "waits": waits, "turns": turns,
        "arrive": arrive, "leave": leaves,
        "actions": action_string(path),
    }


def plan_statistics(paths, agents, overview, cost_function):
    """SOC, MAKESPAN, ratios, per-agent actions, and busy grid cells."""
    lengths = [len(path) - 1 for path in paths]
    soc = sum(lengths)
    makespan = max(lengths)
    selected = soc if cost_function == "SOC" else makespan
    lower = (overview["soc_lower"] if cost_function == "SOC"
             else overview["makespan_lower"])
    per_agent = [
        path_statistics(paths[i], agent["goal"],
                        overview["agents"][i]["shortest"])
        for i, agent in enumerate(agents)
    ]
    arrivals = [
        sum(length <= time for length in lengths)
        for time in range(makespan + 1)
    ]
    traffic = Counter()
    cell_waits = Counter()
    for path in paths:
        for cell in set(path):
            traffic[cell] += 1
        for a, b in zip(path, path[1:]):
            if a == b:
                cell_waits[a] += 1
    hotspots = sorted(
        traffic, key=lambda cell: (-traffic[cell], cell[1], cell[0])
    )[:5]
    return {
        "soc": soc, "makespan": makespan, "cost": selected,
        "ratio": fraction(selected, lower), "agents": per_agent,
        "sum_extra": sum(record["extra"] for record in per_agent),
        "max_extra": max(record["extra"] for record in per_agent),
        "waits": sum(record["waits"] for record in per_agent),
        "turns": sum(record["turns"] for record in per_agent),
        "arrivals": arrivals, "traffic": traffic,
        "cell_waits": cell_waits, "hotspots": hotspots,
    }


def delayed_execution(paths, settings):
    """Progress steps only after all earlier occupants have already left."""
    steps = []
    for path in paths:
        entries = [(0, path[0])]
        for time in range(1, len(path)):
            if path[time] != path[time - 1]:
                entries.append((time, path[time]))
        steps.append(entries)
    prerequisites = []
    for i, entries in enumerate(steps):
        requests = {}
        for index in range(1, len(entries)):
            scheduled, cell = entries[index]
            requests[index] = [
                (j, k)
                for j, other_entries in enumerate(steps) if i != j
                for k, (time, other_cell) in enumerate(other_entries)
                if other_cell == cell and time < scheduled
            ]
        prerequisites.append(requests)

    progress = [0] * len(paths)
    finish = [None] * len(paths)
    holds = 0
    time = 0
    while any(progress[i] < len(steps[i]) - 1 for i in range(len(paths))):
        advance = []
        stopped_count = 0
        for i in range(len(paths)):
            if progress[i] == len(steps[i]) - 1:
                continue
            if any(
                agent == i and start <= time < start + duration
                for agent, start, duration in settings["delays"]
            ):
                stopped_count += 1
                continue
            target_step = progress[i] + 1
            if all(progress[other] > index
                   for other, index in prerequisites[i][target_step]):
                advance.append(i)
            else:
                holds += 1
        if not advance and stopped_count == 0:
            return {"deadlock": time, "blocked": holds}
        for i in advance:
            progress[i] += 1
            if progress[i] == len(steps[i]) - 1:
                finish[i] = time + 1
        time += 1
    return {
        "deadlock": None, "blocked": holds, "finish": finish,
        "soc": sum(finish), "makespan": max(finish),
    }


def complete_runs(results, agents, grid, overview, settings):
    for run in results:
        if run["status"] == "FAIL":
            continue
        run["metrics"] = plan_statistics(
            run["paths"], agents, overview, run["cost_function"]
        )
        run["validation"] = validate_plan(run["paths"], agents, grid)
        run["execution"] = delayed_execution(run["paths"], settings)


def instance_lines(grid, agents, overview):
    stats = overview["degrees"]
    result = [
        f"instance width {grid['width']} height {grid['height']} "
        f"free {len(grid['free'])} agents {len(agents)}",
        f"map isolated {stats['isolated']} dead_ends {stats['dead_ends']} "
        f"corridors {stats['corridors']} junctions {stats['junctions']} "
        f"components {stats['components']}",
    ]
    for i, agent in enumerate(agents):
        record = overview["agents"][i]
        result.append(
            f"agent {agent['name']} start {cell_text(agent['start'])} "
            f"goal {cell_text(agent['goal'])} distance {record['shortest']} "
            f"mdd {record['mdd_states']} width {record['mdd_width']}"
        )
    result.append(
        f"lower_bound soc {overview['soc_lower']} "
        f"makespan {overview['makespan_lower']}"
    )
    classes = overview["independent_class_counts"]
    kinds = overview["independent_kind_counts"]
    result.append(
        f"independent conflicts {len(overview['independent_conflicts'])} "
        f"vertex {kinds['vertex']} edge {kinds['edge']} "
        f"cardinal {classes['cardinal']} "
        f"semi_cardinal {classes['semi_cardinal']} "
        f"non_cardinal {classes['non_cardinal']}"
    )
    result.append(
        "groups " + (" ".join(overview["groups"]) if overview["groups"] else "-")
    )
    return result


def successful_run_lines(run, agents):
    metrics = run["metrics"]
    execution = run["execution"]
    result = [
        f"run {run['name']} solver {run['solver']} "
        f"cost_function {run['cost_function']} result OK "
        f"cost {metrics['cost']} soc {metrics['soc']} "
        f"makespan {metrics['makespan']} ratio {metrics['ratio']}"
    ]
    result.extend(run["specific"])
    for agent, record in zip(agents, metrics["agents"]):
        result.append(
            f"agent {agent['name']} cost {record['cost']} "
            f"extra {record['extra']} waits {record['waits']} "
            f"turns {record['turns']} arrive {record['arrive']} "
            f"leave {record['leave']} moves {record['actions']}"
        )
    result.append("arrivals " + " ".join(map(str, metrics["arrivals"])))
    result.append(
        "hotspots " + " ".join(
            f"{cell_text(cell)}:{metrics['traffic'][cell]}"
            for cell in metrics["hotspots"]
        )
    )
    if execution["deadlock"] is not None:
        result.append(
            f"execution deadlock time {execution['deadlock']}"
        )
    else:
        result.append(
            f"execution soc {execution['soc']} "
            f"makespan {execution['makespan']} blocked {execution['blocked']} "
            f"finish {' '.join(map(str, execution['finish']))}"
        )
    return result


def solution_lines(grid, agents, overview, results):
    result = instance_lines(grid, agents, overview)
    for run in results:
        result.append("")
        if run["status"] == "OK":
            result.extend(successful_run_lines(run, agents))
        else:
            result.append(
                f"run {run['name']} solver {run['solver']} "
                f"cost_function {run['cost_function']} result FAIL "
                f"reason {run['reason']}"
            )
            result.extend(run["specific"])
    result.append("")
    succeeded = [run for run in results if run["status"] == "OK"]
    result.append(
        f"summary ok {len(succeeded)} failed {len(results) - len(succeeded)}"
    )
    if succeeded:
        best_soc = min(run["metrics"]["soc"] for run in succeeded)
        best_span = min(run["metrics"]["makespan"] for run in succeeded)
        result.append(
            f"best_soc {best_soc} " +
            " ".join(run["name"] for run in succeeded
                     if run["metrics"]["soc"] == best_soc)
        )
        result.append(
            f"best_makespan {best_span} " +
            " ".join(run["name"] for run in succeeded
                     if run["metrics"]["makespan"] == best_span)
        )
        ranked = sorted(succeeded, key=lambda run: (
            run["metrics"]["soc"], run["metrics"]["makespan"],
            results.index(run),
        ))
        result.append("ranking " + " ".join(run["name"] for run in ranked))
    return result


def stats_lines(results):
    lines = [
        "run,solver,cost_function,result,reason,cost,soc,makespan,"
        "sum_extra,max_extra,waits,turns,exec_soc,exec_makespan,"
        "high_level,generated,searches,expansions"
    ]
    for run in results:
        fields = [
            run["name"], run["solver"], run["cost_function"],
            run["status"], run["reason"] if run["reason"] else "-",
        ]
        if run["status"] == "OK":
            metrics = run["metrics"]
            execution = run["execution"]
            fields.extend([
                metrics["cost"], metrics["soc"], metrics["makespan"],
                metrics["sum_extra"], metrics["max_extra"],
                metrics["waits"], metrics["turns"],
            ])
            if execution["deadlock"] is None:
                fields.extend([execution["soc"], execution["makespan"]])
            else:
                fields.extend(["-", "-"])
        else:
            fields.extend(["-"] * 9)
        fields.extend([
            run["high_level"],
            run["generated"] if run["generated"] is not None else "-",
            run["budget"].searches,
            run["budget"].expansions,
        ])
        lines.append(csv_line(fields))
    return lines


def validation_lines(results, independent, agents, grid, overview):
    baseline = validate_plan(independent, agents, grid)
    baseline["conflicts"] = overview["independent_conflicts"]
    result = []
    for name, validation in [("INDEPENDENT", baseline)] + [
        (run["name"], run.get("validation"))
        for run in results
    ]:
        if validation is None:
            result.append(f"plan {name} verdict NONE")
            continue
        result.append(
            f"plan {name} verdict {validation['verdict']} "
            f"start {validation['start']} goal {validation['goal']} "
            f"moves {validation['moves']} vertex {validation['vertex']} "
            f"edge {validation['edge']} follows {validation['follows']}"
        )
        for conflict in validation["conflicts"]:
            text = "  " + conflict_text(conflict)
            if name == "INDEPENDENT":
                text += " " + conflict["class"]
            result.append(text)
    return result


def trace_lines(results):
    lines = []
    for index, run in enumerate(results):
        if index:
            lines.append("")
        lines.append(f"run {run['name']}")
        lines.extend(run["trace"])
        lines.append(run["end"])
    return lines


def occupancy_picture(grid, paths, time, agents):
    """Render goal cells in lowercase, then overlay current agent locations."""
    glyphs = {
        agent["goal"]: agent["name"].lower() for agent in agents
    }
    for agent, path in zip(agents, paths):
        glyphs[position(path, time)] = agent["name"]
    return picture(grid, glyphs)


def count_picture(grid, counts):
    characters = {
        cell: str(value) if value <= 9 else "+"
        for cell, value in counts.items() if value > 0
    }
    return picture(grid, characters)


def animation_lines(results, grid, agents, settings):
    selected = next(run for run in results if run["name"] == settings["animate"])
    if selected["status"] != "OK":
        return [f"run {selected['name']} FAIL"]
    frames = settings["frames"]
    paths = selected["paths"]
    metrics = selected["metrics"]
    lines = [f"run {selected['name']} frames {frames}"]
    for time in range(frames):
        done = sum(time >= len(path) - 1 for path in paths)
        moving = sum(
            time >= 1
            and position(path, time) != position(path, time - 1)
            for path in paths
        )
        waiting = len(paths) - done - moving
        lines.append("")
        lines.append(
            f"frame {time} done {done} moving {moving} waiting {waiting}"
        )
        lines.extend(occupancy_picture(grid, paths, time, agents))
    lines.append("")
    lines.append("traffic")
    lines.extend(count_picture(grid, metrics["traffic"]))
    lines.append("")
    lines.append("waits")
    lines.extend(count_picture(grid, metrics["cell_waits"]))
    return lines


def main():
    grid = read_grid()
    agents = read_agents()
    settings = read_parameters(len(agents))
    distances = [
        distance_table(grid, agent["goal"]) for agent in agents
    ]
    baseline = independent_plan(
        grid, agents, distances, settings["horizon"]
    )
    overview = instance_overview(grid, agents, distances, baseline)
    results = run_solvers(grid, agents, distances, settings)
    complete_runs(results, agents, grid, overview, settings)
    save_file(
        "solutions.txt", solution_lines(grid, agents, overview, results)
    )
    save_file("stats.csv", stats_lines(results))
    save_file(
        "validation.txt",
        validation_lines(results, baseline, agents, grid, overview),
    )
    save_file("trace.txt", trace_lines(results))
    save_file(
        "frames.txt", animation_lines(results, grid, agents, settings)
    )


if __name__ == "__main__":
    main()
