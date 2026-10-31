"""Deterministic SAT solver, model enumeration, and combinatorial puzzle reports.

Run as python3 Python/main.py from the task directory. The complete solver
reads input/jobs.txt, input/graphs.txt, and referenced input/*.cnf files;
its only external outputs are the four required files in output/.
"""

from collections import Counter, defaultdict
from pathlib import Path
import re

from cnf_io import model_lines, read_dimacs, valid_number
from dpll import run_round
from encoders import (
    canonical_coloring, coloring, pigeon, positions, queens,
    queens_symmetries,
)
from preprocess import preprocess
from report import (
    frequency, heading, named, number_list, queens_board,
    save_lines, save_paragraphs,
)


COMMANDS = ("SOLVE", "ENUM", "CORE", "QUEENS", "PIGEON", "COLOR", "CHROMATIC")
ARGUMENT_TYPES = {
    "SOLVE": ("file",),
    "ENUM": ("file", "limit"),
    "CORE": ("file",),
    "QUEENS": ("small", "limit"),
    "PIGEON": ("small", "small", "limit"),
    "COLOR": ("graph", "color", "limit"),
    "CHROMATIC": ("graph", "color"),
}
NAME = re.compile(r"[a-z0-9_]{1,20}\Z")


def load_graphs(filename="input/graphs.txt"):
    """Preserve first edge-error per graph with absolute source-line numbers."""
    graphs = {}
    lines = Path(filename).read_text(encoding="ascii").splitlines()
    current = None
    for lineno, line in enumerate(lines, 1):
        if current is None:
            if not line or line.startswith("#"):
                continue
            label, graph_name, count = line.split(" ")
            if label != "GRAPH":
                raise ValueError("malformed graph block")
            current = {
                "name": graph_name, "vertices": int(count),
                "edges": [], "invalid": None,
            }
            continue
        if line == "END":
            current["edges"].sort()
            graphs[current["name"]] = current
            current = None
            continue
        if current["invalid"] is not None:
            continue
        tokens = line.split(" ")
        reason = None
        if len(tokens) != 2 or not all(valid_number(t) for t in tokens):
            reason = "bad edge line"
        else:
            first, second = map(int, tokens)
            if not (1 <= first <= current["vertices"]
                    and 1 <= second <= current["vertices"]):
                reason = "vertex out of range"
            elif first == second:
                reason = "self loop"
            elif (min(first, second), max(first, second)) in current["edges"]:
                reason = "duplicate edge"
            else:
                current["edges"].append(
                    (min(first, second), max(first, second))
                )
        if reason:
            current["invalid"] = f"{reason} at line {lineno}"
    return graphs


def load_jobs(filename="input/jobs.txt"):
    """Discard blank/comment lines while retaining exact original job text."""
    jobs = []
    for raw in Path(filename).read_text(encoding="ascii").splitlines():
        if not raw or raw.startswith("#"):
            continue
        tokens = raw.split(" ")
        jobs.append({
            "number": len(jobs) + 1,
            "text": raw,
            "command": tokens[0],
            "args": tokens[1:],
        })
    return jobs


def validate_job(job, graphs):
    """Validate syntax and arguments in the prescribed left-to-right order."""
    command = job["command"]
    if command not in ARGUMENT_TYPES:
        return f"unknown command {command}"
    types = ARGUMENT_TYPES[command]
    if len(job["args"]) != len(types):
        return "wrong argument count"
    for argument, kind in zip(job["args"], types):
        if kind == "file":
            if not argument.endswith(".cnf") or NAME.fullmatch(argument[:-4]) is None:
                return f"bad file name {argument}"
        elif kind == "graph":
            if argument not in graphs:
                return f"unknown graph {argument}"
            if graphs[argument]["invalid"] is not None:
                return f"invalid graph {argument}: {graphs[argument]['invalid']}"
        else:
            if not valid_number(argument):
                return f"bad number {argument}"
            number = int(argument)
            maximum = {"small": 8, "color": 6, "limit": 200}[kind]
            if not 1 <= number <= maximum:
                return f"out of range {argument}"
    return None


def greedy_coloring(graph):
    """Degree-descending greedy coloring, ties in vertex-number order."""
    degree = [0] * (graph["vertices"] + 1)
    neighbors = defaultdict(set)
    for a, b in graph["edges"]:
        degree[a] += 1
        degree[b] += 1
        neighbors[a].add(b)
        neighbors[b].add(a)
    order = sorted(range(1, graph["vertices"] + 1),
                   key=lambda vertex: (-degree[vertex], vertex))
    colors = [0] * (graph["vertices"] + 1)
    for vertex in order:
        used = {colors[n] for n in neighbors[vertex] if colors[n]}
        candidate = 1
        while candidate in used:
            candidate += 1
        colors[vertex] = candidate
    return colors[1:]


def solved_statistics():
    return {
        "decisions": 0, "propagations": 0,
        "conflicts": 0, "max_depth": 0,
    }


def accumulate_stats(destination, source):
    """Sums event counters, but keeps the largest encountered search depth."""
    for key in ("decisions", "propagations", "conflicts"):
        destination[key] += source[key]
    destination["max_depth"] = max(
        destination["max_depth"], source["max_depth"]
    )


def solve_formula(variables, original_clauses, limit):
    """Preprocess once, then repeat watched-literal search with blocking."""
    preparation = preprocess(variables, original_clauses, limit == 1)
    models = []
    stats = solved_statistics()
    rounds = 0
    trace = []
    blocking = []
    if preparation["empty_clause"] is not None:
        stop = "preprocess"
    else:
        while len(models) < limit:
            rounds += 1
            model, events, counters = run_round(
                variables, preparation["clauses"] + blocking
            )
            if rounds == 1:
                trace = events
            accumulate_stats(stats, counters)
            if model is None:
                stop = "all"
                break
            for variable, value in preparation["fixed"].items():
                model[variable] = value
            models.append(model)
            blocking.append([
                -variable if model[variable] else variable
                for variable in preparation["active"]
            ])
        else:
            stop = "limit"
    return {
        "variables": variables,
        "clauses": original_clauses,
        "models": models,
        "status": "SAT" if models else "UNSAT",
        "rounds": rounds,
        "stop": stop,
        "trace": trace,
        "stats": stats,
        "preparation": preparation,
        "removed": preparation["counts"]["removed"],
    }


def true_literal(model, literal):
    return model[abs(literal)] if literal > 0 else not model[abs(literal)]


def satisfies(model, clauses):
    return all(
        any(true_literal(model, literal) for literal in clause)
        for clause in clauses
    )


def analyze_models(solution):
    """Original-clause verification, flips, diversity and backbone."""
    models = solution["models"]
    if not models:
        return None
    clauses = solution["clauses"]
    count = solution["variables"]
    failure = None
    for model_number, model in enumerate(models, 1):
        for clause_number, clause in enumerate(clauses, 1):
            if not any(true_literal(model, lit) for lit in clause):
                failure = model_number, clause_number
                break
        if failure:
            break
    first = models[0]
    true_distribution = [
        sum(true_literal(first, lit) for lit in clause)
        for clause in clauses
    ]
    safe = []
    for variable in range(1, count + 1):
        inverted = first.copy()
        inverted[variable] = not inverted[variable]
        if satisfies(inverted, clauses):
            safe.append(variable)
    diversity = []
    for i in range(len(models)):
        for j in range(i + 1, len(models)):
            diversity.append(
                sum(models[i][v] != models[j][v]
                    for v in range(1, count + 1))
            )
    backbone = [
        variable if first[variable] else -variable
        for variable in range(1, count + 1)
        if all(model[variable] == first[variable] for model in models)
    ]
    return {
        "failure": failure,
        "true_distribution": true_distribution,
        "safe": safe,
        "diversity": diversity,
        "backbone": backbone,
    }


def unsat_core(variables, clauses):
    """Deletion-based irreducible core; execute exactly M tests."""
    remaining = set(range(1, len(clauses) + 1))
    decisions = 0
    conflicts = 0
    for removed_number in range(1, len(clauses) + 1):
        candidates = [
            clause for number, clause in enumerate(clauses, 1)
            if number in remaining and number != removed_number
        ]
        test = solve_formula(variables, candidates, 1)
        decisions += test["stats"]["decisions"]
        conflicts += test["stats"]["conflicts"]
        if test["status"] == "UNSAT":
            remaining.discard(removed_number)
    return {
        "clauses": sorted(remaining),
        "decisions": decisions,
        "conflicts": conflicts,
    }


def execute_chromatic(job, graphs):
    """Find the first color count with a model, aggregating all attempts."""
    graph = graphs[job["args"][0]]
    bound = int(job["args"][1])
    attempts = []
    summary = solved_statistics()
    total_rounds = 0
    removed_total = 0
    last = None
    for colors in range(1, bound + 1):
        count, clauses = coloring(graph, colors)
        solution = solve_formula(count, clauses, 1)
        solution["colors"] = colors
        attempts.append(solution)
        accumulate_stats(summary, solution["stats"])
        total_rounds += solution["rounds"]
        removed_total += solution["removed"]
        last = solution
        if solution["status"] == "SAT":
            break
    job["attempts"] = attempts
    job["chromatic"] = last["colors"] if last["models"] else None
    job["solution"] = last
    job["aggregate_stats"] = summary
    job["aggregate_rounds"] = total_rounds
    job["aggregate_removed"] = removed_total
    job["colors"] = last["colors"]
    job["graph"] = graph


def execute_standard(job, graphs):
    """Read or encode the formula, choose its limit, and solve."""
    command = job["command"]
    args = job["args"]
    if command in ("SOLVE", "ENUM", "CORE"):
        variables, clauses = read_dimacs(args[0])
        limit = int(args[1]) if command == "ENUM" else 1
    elif command == "QUEENS":
        variables, clauses = queens(int(args[0]))
        limit = int(args[1])
    elif command == "PIGEON":
        variables, clauses = pigeon(int(args[0]), int(args[1]))
        limit = int(args[2])
    else:
        job["graph"] = graphs[args[0]]
        job["colors"] = int(args[1])
        variables, clauses = coloring(job["graph"], job["colors"])
        limit = int(args[2])
    solution = solve_formula(variables, clauses, limit)
    job["solution"] = solution
    job["aggregate_stats"] = solution["stats"]
    job["aggregate_rounds"] = solution["rounds"]
    job["aggregate_removed"] = solution["removed"]
    if command == "CORE" and solution["status"] == "UNSAT":
        job["core"] = unsat_core(variables, clauses)


def execute_jobs(jobs, graphs):
    for job in jobs:
        error = validate_job(job, graphs)
        if error is not None:
            job["error"] = error
            continue
        try:
            if job["command"] == "CHROMATIC":
                execute_chromatic(job, graphs)
            else:
                execute_standard(job, graphs)
        except ValueError as exception:
            job["error"] = str(exception)
            continue
        job["analysis"] = analyze_models(job["solution"])
    return jobs


def summarize_formula(variables, clauses):
    lengths = [len(clause) for clause in clauses]
    return named(
        variables=variables, clauses=len(clauses),
        literals=sum(lengths), lengths=frequency(lengths),
    )


def graph_summary(graph):
    degree = Counter()
    for a, b in graph["edges"]:
        degree[a] += 1
        degree[b] += 1
    greedy = greedy_coloring(graph)
    return named(
        vertices=graph["vertices"], edges=len(graph["edges"]),
        max_degree=max(degree.values(), default=0),
        greedy=max(greedy),
    )


def preprocessing_report(preparation):
    """Render all ordered preprocessing statistics and removed-clause IDs."""
    counts = preparation["counts"]
    records = preparation["records"]
    lines = [
        "preprocess " + named(
            pure="on" if preparation["pure"] else "off",
            tautologies=counts["tautologies"],
            duplicate_literals=counts["duplicate_literals"],
            unit_fixed=counts["unit_fixed"], unit_removed=counts["unit_removed"],
            subsumed=counts["subsumed"], pure_fixed=counts["pure_fixed"],
            pure_removed=counts["pure_removed"], removed=counts["removed"],
        ),
        "removed_clauses " + named(
            tautology=number_list(records["tautology"]),
            unit=number_list(records["unit"]),
            subsumed=number_list(records["subsumed"]),
            pure=number_list(records["pure"]),
        ),
    ]
    if preparation["empty_clause"] is not None:
        lines.append(
            f"simplified empty_clause={preparation['empty_clause']}"
        )
    else:
        lengths = [len(clause) for clause in preparation["clauses"]]
        lines.append("simplified " + named(
            clauses=len(lengths), literals=sum(lengths),
            lengths=frequency(lengths), fixed=len(preparation["fixed"]),
            active=len(preparation["active"]),
        ))
        fixed_literals = [
            variable if preparation["fixed"][variable] else -variable
            for variable in sorted(preparation["fixed"])
        ]
        lines.append("fixed " + named(literals=number_list(fixed_literals)))
    return lines


def search_report(stats):
    return "search " + named(
        decisions=stats["decisions"], propagations=stats["propagations"],
        conflicts=stats["conflicts"], max_depth=stats["max_depth"],
    )


def verification_report(solution, analysis):
    if analysis is None:
        return []
    failure = analysis["failure"]
    if failure is not None:
        return [f"verify failed model={failure[0]} clause={failure[1]}"]
    return ["verify ok " + named(
        models=len(solution["models"]), clauses=len(solution["clauses"]),
        true_literals=frequency(analysis["true_distribution"]),
    )]


def analysis_report(solution, analysis):
    """Only emit model-dependent sections when they are meaningful."""
    if analysis is None:
        return []
    safe = analysis["safe"]
    lines = [
        "flips " + named(safe=len(safe), variables=number_list(safe)),
    ]
    distances = analysis["diversity"]
    if distances:
        lines.append("diversity " + named(
            pairs=len(distances), min_distance=min(distances),
            max_distance=max(distances),
        ))
    if solution["stop"] == "all":
        backbone = analysis["backbone"]
        lines.append("backbone " + named(
            size=len(backbone), literals=number_list(backbone),
        ))
    return lines


def trace_report(events):
    if not events:
        return "trace -"
    initial = events[:12]
    remaining = len(events) - len(initial)
    text = " ".join(initial)
    return "trace " + text + (f" +{remaining}" if remaining else "")


def standard_result(job):
    solution = job["solution"]
    preprocessing = solution["preparation"]
    result = [heading(job)]
    if job["command"] == "COLOR":
        result.append("graph " + graph_summary(job["graph"]))
    result.append("formula " + summarize_formula(
        solution["variables"], solution["clauses"]
    ))
    result.extend(preprocessing_report(preprocessing))
    result.append("result " + named(
        S=solution["status"], models=len(solution["models"]),
        rounds=solution["rounds"], stop=solution["stop"],
    ).replace("S=", "", 1))
    result.append(search_report(solution["stats"]))
    if solution["rounds"]:
        result.append(trace_report(solution["trace"]))
    result.extend(verification_report(solution, job["analysis"]))
    result.extend(analysis_report(solution, job["analysis"]))
    if "core" in job:
        core = job["core"]
        result.append("core " + named(
            size=len(core["clauses"]), decisions=core["decisions"],
            conflicts=core["conflicts"], clauses=number_list(core["clauses"]),
        ))
    return result


def chromatic_result(job):
    result = [heading(job), "graph " + graph_summary(job["graph"])]
    for attempt in job["attempts"]:
        result.append("attempt " + named(
            k=attempt["colors"], clauses=len(attempt["clauses"]),
            removed=attempt["removed"], result=attempt["status"],
            stop=attempt["stop"],
            decisions=attempt["stats"]["decisions"],
            propagations=attempt["stats"]["propagations"],
            conflicts=attempt["stats"]["conflicts"],
            max_depth=attempt["stats"]["max_depth"],
        ))
    result.append(
        f"result {job['solution']['status']} "
        f"chromatic={job['chromatic'] if job['chromatic'] else '-'} "
        f"attempts={len(job['attempts'])}"
    )
    result.append(search_report(job["aggregate_stats"]))
    if job["solution"]["status"] == "SAT":
        result.extend(verification_report(job["solution"], job["analysis"]))
        safe = job["analysis"]["safe"]
        result.append("flips " + named(
            safe=len(safe), variables=number_list(safe),
        ))
    return result


def valid_jobs(jobs):
    return [job for job in jobs if "error" not in job]


def results_summary(jobs):
    valid = valid_jobs(jobs)
    sat = sum(job["solution"]["status"] == "SAT" for job in valid)
    result = [
        "SUMMARY " + named(
            jobs=len(jobs), sat=sat, unsat=len(valid) - sat,
            error=len(jobs) - len(valid),
        ),
        "totals " + named(
            models=sum(len(job["solution"]["models"]) for job in valid),
            rounds=sum(job["aggregate_rounds"] for job in valid),
            decisions=sum(job["aggregate_stats"]["decisions"] for job in valid),
            propagations=sum(job["aggregate_stats"]["propagations"] for job in valid),
            conflicts=sum(job["aggregate_stats"]["conflicts"] for job in valid),
            removed_clauses=sum(job["aggregate_removed"] for job in valid),
        ),
    ]
    for command in COMMANDS:
        members = [job for job in valid if job["command"] == command]
        if not members:
            continue
        result.append(
            f"command {command} " + named(
                jobs=len(members),
                sat=sum(job["solution"]["status"] == "SAT" for job in members),
                unsat=sum(job["solution"]["status"] == "UNSAT" for job in members),
                decisions=sum(job["aggregate_stats"]["decisions"] for job in members),
                propagations=sum(job["aggregate_stats"]["propagations"]
                                 for job in members),
                conflicts=sum(job["aggregate_stats"]["conflicts"] for job in members),
            )
        )
    for label, key in (("hardest", "conflicts"),
                       ("deepest", "max_depth"),
                       ("busiest", "propagations")):
        if not valid:
            break
        job = max(
            valid, key=lambda item: (item["aggregate_stats"][key], -item["number"])
        )
        result.append(
            f"{label} job={job['number']} {key}={job['aggregate_stats'][key]}"
        )
    return result


def result_paragraphs(jobs):
    paragraphs = []
    for job in jobs:
        if "error" in job:
            paragraphs.append([heading(job), "error " + job["error"]])
        elif job["command"] == "CHROMATIC":
            paragraphs.append(chromatic_result(job))
        else:
            paragraphs.append(standard_result(job))
    paragraphs.append(results_summary(jobs))
    return paragraphs


def model_paragraphs(jobs):
    paragraphs = []
    for job in valid_jobs(jobs):
        models = job["solution"]["models"]
        if not models:
            continue
        lines = [heading(job)]
        for number, model in enumerate(models, 1):
            lines.append(f"model {number}")
            lines.extend(model_lines(model))
        paragraphs.append(lines)
    return paragraphs


def classes_for_models(columns, canonicalize):
    classes = {}
    assignments = []
    for index, value in enumerate(columns, 1):
        canonical, orbit = canonicalize(value)
        if canonical not in classes:
            classes[canonical] = {
                "number": len(classes) + 1,
                "first": index, "found": 0,
                "canonical": canonical, "orbit": orbit,
            }
        group = classes[canonical]
        group["found"] += 1
        assignments.append((value, group["number"], index == group["first"]))
    return assignments, list(classes.values())


def queens_boards(job):
    n = int(job["args"][0])
    models = job["solution"]["models"]
    columns = [positions(model, n, n) for model in models]

    def canonical(cols):
        variants = queens_symmetries(cols)
        return min(variants), len(set(variants))

    assignments, classes = classes_for_models(columns, canonical)
    lines = [f"QUEENS job={job['number']} n={n}"]
    for index, (value, group, is_first) in enumerate(assignments, 1):
        lines.append(
            f"solution {index} columns={number_list(value)} class={group}"
        )
        if is_first:
            lines.extend(queens_board(value))
    for group in classes:
        lines.append(
            "class " + named(
                C=group["number"], orbit=group["orbit"],
                found=group["found"], first=group["first"],
                canonical=number_list(group["canonical"]),
            ).replace("C=", "", 1)
        )
    lines.append("summary " + named(
        solutions=len(models), stop=job["solution"]["stop"],
        classes=len(classes),
    ))
    return lines


def pigeon_boards(job):
    p, h = map(int, job["args"][:2])
    models = job["solution"]["models"]
    lines = [f"PIGEON job={job['number']} pigeons={p} holes={h}"]
    for index, model in enumerate(models, 1):
        places = positions(model, p, h)
        empty = [hole for hole in range(1, h + 1) if hole not in places]
        lines.append(
            f"assignment {index} holes={number_list(places)} "
            f"empty={number_list(empty)}"
        )
    expected = 1
    if p > h:
        expected = 0
    else:
        for value in range(h, h - p, -1):
            expected *= value
    lines.append("summary " + named(
        assignments=len(models), stop=job["solution"]["stop"],
        expected=expected,
    ))
    return lines


def coloring_boards(job):
    graph = job["graph"]
    count = graph["vertices"]
    colors = job["colors"]
    models = job["solution"]["models"]
    decoded = [positions(model, count, colors) for model in models]

    def canonical(value):
        return canonical_coloring(value), None

    assignments, classes = classes_for_models(decoded, canonical)
    command = job["command"]
    lines = [
        f"{command} job={job['number']} graph={graph['name']} "
        f"vertices={count} edges={len(graph['edges'])} colors={colors}"
    ]
    greedy = greedy_coloring(graph)
    lines.append(
        f"greedy used={max(greedy)} colors={number_list(greedy)}"
    )
    for index, (value, group, _) in enumerate(assignments, 1):
        size = [value.count(color) for color in range(1, colors + 1)]
        lines.append(
            f"coloring {index} colors={number_list(value)} "
            f"used={len(set(value))} sizes={number_list(size)} class={group}"
        )
    for group in classes:
        lines.append(
            f"class {group['number']} found={group['found']} "
            f"first={group['first']} "
            f"canonical={number_list(group['canonical'])}"
        )
    lines.append("summary " + named(
        colorings=len(models), stop=job["solution"]["stop"],
        classes=len(classes),
    ))
    return lines


def boards_paragraphs(jobs):
    result = []
    for job in valid_jobs(jobs):
        command = job["command"]
        if command == "QUEENS":
            result.append(queens_boards(job))
        elif command == "PIGEON":
            result.append(pigeon_boards(job))
        elif command in ("COLOR", "CHROMATIC"):
            result.append(coloring_boards(job))
    return result


def stats_lines(jobs):
    result = [
        "job,command,status,variables,clauses,removed_clauses,"
        "decisions,propagations,conflicts,max_depth,models,rounds"
    ]
    for job in valid_jobs(jobs):
        solution = job["solution"]
        stats = job["aggregate_stats"]
        record = [
            job["number"], job["command"], solution["status"],
            solution["variables"], len(solution["clauses"]),
            job["aggregate_removed"], stats["decisions"],
            stats["propagations"], stats["conflicts"],
            stats["max_depth"], len(solution["models"]),
            job["aggregate_rounds"],
        ]
        result.append(",".join(map(str, record)))
    return result


def main():
    graphs = load_graphs()
    jobs = execute_jobs(load_jobs(), graphs)
    save_paragraphs("results.txt", result_paragraphs(jobs))
    save_paragraphs("models.txt", model_paragraphs(jobs))
    save_paragraphs("boards.txt", boards_paragraphs(jobs))
    save_lines("stats.csv", stats_lines(jobs))


if __name__ == "__main__":
    main()
