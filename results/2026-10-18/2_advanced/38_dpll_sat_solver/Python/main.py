"""Deterministic SAT benchmarking: CNF, DPLL, enumeration and encodings.

Run from the topic directory: python3 Python/main.py
The inputs are under input/, and the four outputs are under output/.
All choices and traversal orders are defined by taskA.txt.
"""

from collections import Counter
from pathlib import Path
import re

from cnf_io import model_lines, read_dimacs, valid_number
from dpll import search
from encoders import (
    canonical_coloring, coloring, decode_positions, pigeon,
    queen_variants, queens,
)
from preprocess import preprocess, removed_count
from report import (
    frequency, heading, number_list, queen_board, record,
    save_lines, save_paragraphs,
)


COMMAND_ARGS = {
    "SOLVE": ("file",),
    "ENUM": ("file", "limit"),
    "CORE": ("file",),
    "QUEENS": ("queens", "limit"),
    "PIGEON": ("pigeons", "holes", "limit"),
    "COLOR": ("graph", "colors", "limit"),
    "CHROMATIC": ("graph", "colors"),
}
COMMAND_ORDER = tuple(COMMAND_ARGS)
NAME = re.compile(r"[a-z0-9_]{1,20}\Z")
FILE = re.compile(r"[a-z0-9_]{1,20}\.cnf\Z")
RANGES = {
    "queens": (1, 8), "pigeons": (1, 8), "holes": (1, 8),
    "colors": (1, 6), "limit": (1, 200),
}
STATISTICS = (
    "decisions", "propagations", "conflicts", "max_depth",
)


def read_jobs():
    """Assign job numbers only to nonempty and noncomment lines."""
    lines = Path("input/jobs.txt").read_text(encoding="ascii").splitlines()
    jobs = []
    for line in lines:
        if line and not line.startswith("#"):
            jobs.append({
                "number": len(jobs) + 1,
                "text": line,
                "words": line.split(" "),
            })
    return jobs


def read_graphs():
    """Preserve each graph's first edge-format error and its file line."""
    lines = Path("input/graphs.txt").read_text(encoding="ascii").splitlines()
    graphs = {}
    current = None
    seen = set()
    for lineno, line in enumerate(lines, 1):
        if current is None:
            if not line or line.startswith("#"):
                continue
            _, name, size = line.split(" ")
            current = {
                "name": name, "vertices": int(size),
                "edges": [], "error": None,
            }
            seen = set()
            continue
        if line == "END":
            current["edges"].sort()
            graphs[current["name"]] = current
            current = None
            continue
        if current["error"] is not None:
            continue
        fields = line.split(" ")
        if len(fields) != 2 or not all(valid_number(word) for word in fields):
            reason = "bad edge line"
        else:
            a, b = map(int, fields)
            if not (1 <= a <= current["vertices"]
                    and 1 <= b <= current["vertices"]):
                reason = "vertex out of range"
            elif a == b:
                reason = "self loop"
            elif tuple(sorted((a, b))) in seen:
                reason = "duplicate edge"
            else:
                reason = None
        if reason is not None:
            current["error"] = f"{reason} at line {lineno}"
            continue
        edge = tuple(sorted((a, b)))
        seen.add(edge)
        current["edges"].append(edge)
    return graphs


def validate_job(job, graphs):
    """Check command, arity and each argument from left to right."""
    words = job["words"]
    command, arguments = words[0], words[1:]
    if command not in COMMAND_ARGS:
        return f"unknown command {command}"
    names = COMMAND_ARGS[command]
    if len(names) != len(arguments):
        return "wrong argument count"
    parsed = {}
    for name, argument in zip(names, arguments):
        if name == "file":
            if FILE.fullmatch(argument) is None:
                return f"bad file name {argument}"
            parsed[name] = argument
        elif name == "graph":
            if argument not in graphs:
                return f"unknown graph {argument}"
            if graphs[argument]["error"] is not None:
                return f"invalid graph {argument}: {graphs[argument]['error']}"
            parsed[name] = argument
        else:
            if not valid_number(argument):
                return f"bad number {argument}"
            number = int(argument)
            low, high = RANGES[name]
            if not low <= number <= high:
                return f"out of range {argument}"
            parsed[name] = number
    job["command"] = command
    job["args"] = parsed
    if command in ("SOLVE", "ENUM", "CORE"):
        try:
            variable_count, clauses = read_dimacs(parsed["file"])
        except ValueError as error:
            return str(error)
        job["formula"] = (variable_count, clauses)
    return None


def empty_search_stats():
    return {
        "decisions": 0,
        "propagations": 0,
        "conflicts": 0,
        "max_depth": 0,
    }


def combine_search_stats(left, right):
    for name in ("decisions", "propagations", "conflicts"):
        left[name] += right[name]
    left["max_depth"] = max(left["max_depth"], right["max_depth"])
    return left


def solve(variable_count, original, limit):
    """Preprocess once and run deterministic DPLL rounds with blocking clauses."""
    simplified = preprocess(variable_count, original, limit == 1)
    statistics = empty_search_stats()
    result = {
        "variables": variable_count,
        "clauses": original,
        "preprocess": simplified,
        "models": [],
        "stats": statistics,
        "rounds": 0,
        "trace": [],
        "stop": None,
    }
    if simplified["empty"] is not None:
        result["stop"] = "preprocess"
        result["status"] = "UNSAT"
        return result
    blocked = []
    active = simplified["active"]
    while len(result["models"]) < limit:
        clauses = simplified["clauses"] + blocked
        model, search_stats = search(variable_count, clauses)
        result["rounds"] += 1
        if result["rounds"] == 1:
            result["trace"] = search_stats["trace"]
        combine_search_stats(statistics, search_stats)
        if model is None:
            result["stop"] = "all"
            break
        complete = [False] * (variable_count + 1)
        for x in range(1, variable_count + 1):
            complete[x] = simplified["fixed"].get(x, model[x])
        result["models"].append(complete)
        blocked.append([-x if complete[x] else x for x in active])
    if result["stop"] is None:
        result["stop"] = "limit"
    result["status"] = "SAT" if result["models"] else "UNSAT"
    return result


def clause_truth_count(clause, assignment):
    return sum(
        assignment[abs(literal)] == (literal > 0) for literal in clause
    )


def model_is_valid(clauses, assignment):
    return all(clause_truth_count(clause, assignment) > 0 for clause in clauses)


def analyze_models(result):
    """Verification, literal frequencies, safe flips, diversity and backbone."""
    original = result["clauses"]
    models = result["models"]
    if not models:
        return None
    bad = None
    for model_number, model in enumerate(models, 1):
        for clause_number, clause in enumerate(original, 1):
            if clause_truth_count(clause, model) == 0:
                bad = (model_number, clause_number)
                break
        if bad is not None:
            break
    first = models[0]
    frequencies = frequency([
        clause_truth_count(clause, first) for clause in original
    ])
    flips = []
    for x in range(1, result["variables"] + 1):
        flipped = first.copy()
        flipped[x] = not flipped[x]
        if model_is_valid(original, flipped):
            flips.append(x)
    distances = []
    for i, left in enumerate(models):
        for right in models[i + 1:]:
            distances.append(
                sum(left[x] != right[x] for x in range(1, len(left)))
            )
    backbone = []
    if result["stop"] == "all":
        for x in range(1, result["variables"] + 1):
            if all(model[x] == first[x] for model in models):
                backbone.append(x if first[x] else -x)
    return {
        "bad": bad,
        "true_frequency": frequencies,
        "safe_flips": flips,
        "distances": distances,
        "backbone": backbone,
    }


def extract_core(variable_count, original):
    """Sequential deletion-based unsatisfiable core using full solver calls."""
    numbers = list(range(1, len(original) + 1))
    decisions = conflicts = 0
    for clause_number in range(1, len(original) + 1):
        trial = [original[i - 1] for i in numbers if i != clause_number]
        attempt = solve(variable_count, trial, 1)
        decisions += attempt["stats"]["decisions"]
        conflicts += attempt["stats"]["conflicts"]
        if attempt["status"] == "UNSAT":
            numbers.remove(clause_number)
    return {
        "clauses": numbers, "decisions": decisions, "conflicts": conflicts,
    }


def graph_degrees(graph):
    degrees = [0] * (graph["vertices"] + 1)
    for first, second in graph["edges"]:
        degrees[first] += 1
        degrees[second] += 1
    return degrees


def greedy_coloring(graph):
    """Degree-descending graph coloring, breaking ties by original vertex."""
    degrees = graph_degrees(graph)
    order = sorted(range(1, graph["vertices"] + 1),
                   key=lambda x: (-degrees[x], x))
    adjacency = {x: set() for x in range(1, graph["vertices"] + 1)}
    for a, b in graph["edges"]:
        adjacency[a].add(b)
        adjacency[b].add(a)
    colors = [0] * (graph["vertices"] + 1)
    for vertex in order:
        unavailable = {colors[other] for other in adjacency[vertex]}
        choice = 1
        while choice in unavailable:
            choice += 1
        colors[vertex] = choice
    return colors[1:]


def graph_details(graph):
    degrees = graph_degrees(graph)
    assigned = greedy_coloring(graph)
    return {
        "vertices": graph["vertices"],
        "edges": len(graph["edges"]),
        "max_degree": max(degrees[1:]),
        "greedy": max(assigned),
        "greedy_colors": assigned,
    }


def prepare_formula(job, graphs):
    command, args = job["command"], job["args"]
    if "formula" in job:
        return job["formula"]
    if command == "QUEENS":
        return queens(args["queens"])
    if command == "PIGEON":
        return pigeon(args["pigeons"], args["holes"])
    if command == "COLOR":
        return coloring(graphs[args["graph"]], args["colors"])
    raise ValueError("CHROMATIC requires repeated attempts")


def run_job(job, graphs):
    """Execute the solver or repeated chromatic attempts for one valid job."""
    command, args = job["command"], job["args"]
    if command != "CHROMATIC":
        variable_count, original = prepare_formula(job, graphs)
        limit = 1 if command in ("SOLVE", "CORE") else args["limit"]
        result = solve(variable_count, original, limit)
        result["analysis"] = analyze_models(result)
        if command == "CORE" and result["status"] == "UNSAT":
            result["core"] = extract_core(variable_count, original)
        if command == "COLOR":
            result["graph_info"] = graph_details(graphs[args["graph"]])
        result["job"] = job
        return result
    graph = graphs[args["graph"]]
    attempts = []
    stats = empty_search_stats()
    rounds = 0
    removed = 0
    for color_count in range(1, args["colors"] + 1):
        variable_count, original = coloring(graph, color_count)
        attempt = solve(variable_count, original, 1)
        attempts.append(attempt)
        combine_search_stats(stats, attempt["stats"])
        rounds += attempt["rounds"]
        removed += removed_count(attempt["preprocess"])
        if attempt["status"] == "SAT":
            break
    last = attempts[-1]
    result = {
        **last,
        "job": job,
        "analysis": analyze_models(last),
        "attempts": attempts,
        "chromatic": len(attempts) if last["status"] == "SAT" else "-",
        "graph_info": graph_details(graph),
        "stats": stats,
        "rounds": rounds,
        "removed_override": removed,
    }
    return result


def count_removed(result):
    return result.get("removed_override",
                      removed_count(result["preprocess"]))


def statistics_row(result):
    job, stats = result["job"], result["stats"]
    return [
        job["number"], job["command"], result["status"],
        result["variables"], len(result["clauses"]), count_removed(result),
        stats["decisions"], stats["propagations"], stats["conflicts"],
        stats["max_depth"], len(result["models"]), result["rounds"],
    ]


def graph_summary_line(details):
    return "graph " + record(
        vertices=details["vertices"], edges=details["edges"],
        max_degree=details["max_degree"], greedy=details["greedy"],
    )


def model_analysis_lines(result):
    """Common verification and safe-flip lines for SAT jobs."""
    data = result["analysis"]
    if data is None:
        return []
    if data["bad"] is not None:
        first, second = data["bad"]
        lines = [f"verify failed model={first} clause={second}"]
    else:
        lines = [
            "verify " + record(
                ok="", models=len(result["models"]), clauses=len(result["clauses"]),
                true_literals=data["true_frequency"]
            ).replace("ok= ", "ok ", 1)
        ]
    flips = data["safe_flips"]
    lines.append(
        "flips " + record(safe=len(flips), variables=number_list(flips))
    )
    return lines


def search_line(stats):
    return "search " + record(
        decisions=stats["decisions"], propagations=stats["propagations"],
        conflicts=stats["conflicts"], max_depth=stats["max_depth"],
    )


def form_line(variable_count, clauses):
    return "formula " + record(
        variables=variable_count, clauses=len(clauses),
        literals=sum(map(len, clauses)),
        lengths=frequency([len(clause) for clause in clauses]),
    )


def preprocessing_lines(result):
    """All fixed assignments, removed-clause reasons and normalized clauses."""
    prep = result["preprocess"]
    counts = prep["stats"]
    lines = [
        "preprocess " + record(
            pure="on" if prep["pure"] else "off",
            tautologies=counts["tautologies"],
            duplicate_literals=counts["duplicate_literals"],
            unit_fixed=counts["unit_fixed"],
            unit_removed=counts["unit_removed"],
            subsumed=counts["subsumed"],
            pure_fixed=counts["pure_fixed"],
            pure_removed=counts["pure_removed"],
            removed=removed_count(prep),
        ),
        "removed_clauses " + record(
            tautology=number_list(sorted(counts["removed"]["tautology"])),
            unit=number_list(sorted(counts["removed"]["unit"])),
            subsumed=number_list(sorted(counts["removed"]["subsumed"])),
            pure=number_list(sorted(counts["removed"]["pure"])),
        ),
    ]
    if prep["empty"] is not None:
        lines.append(f"simplified empty_clause={prep['empty']}")
    else:
        clauses = prep["clauses"]
        lines.append(
            "simplified " + record(
                clauses=len(clauses),
                literals=sum(map(len, clauses)),
                lengths=frequency([len(clause) for clause in clauses]),
                fixed=len(prep["fixed"]), active=len(prep["active"]),
            )
        )
        lines.append(
            "fixed " + record(literals=number_list(
                x if prep["fixed"][x] else -x for x in sorted(prep["fixed"])
            ))
        )
    return lines


def trace_line(events):
    shown = events[:12]
    text = " ".join(shown) if shown else "-"
    if len(events) > 12:
        text += f" +{len(events) - 12}"
    return "trace " + text


def render_regular_result(result):
    """Full result paragraph for SOLVE, ENUM, CORE and encoded problems."""
    job = result["job"]
    lines = [heading(job)]
    if job["command"] == "COLOR":
        lines.append(graph_summary_line(result["graph_info"]))
    lines.append(form_line(result["variables"], result["clauses"]))
    lines.extend(preprocessing_lines(result))
    lines.append(
        "result " + record(
            status=result["status"], models=len(result["models"]),
            rounds=result["rounds"], stop=result["stop"],
        ).replace("status=", "", 1)
    )
    lines.append(search_line(result["stats"]))
    if result["rounds"]:
        lines.append(trace_line(result["trace"]))
    lines.extend(model_analysis_lines(result))
    analysis = result["analysis"]
    if analysis and len(result["models"]) >= 2:
        distances = analysis["distances"]
        lines.append(
            "diversity " + record(
                pairs=len(distances), min_distance=min(distances),
                max_distance=max(distances),
            )
        )
    if analysis and result["stop"] == "all":
        literals = analysis["backbone"]
        lines.append(
            "backbone " + record(size=len(literals),
                                 literals=number_list(literals))
        )
    if "core" in result:
        core = result["core"]
        lines.append(
            "core " + record(
                size=len(core["clauses"]), decisions=core["decisions"],
                conflicts=core["conflicts"],
                clauses=number_list(core["clauses"]),
            )
        )
    return lines


def render_chromatic_result(result):
    """CHROMATIC omits the ordinary formula and preprocessing paragraphs."""
    lines = [heading(result["job"]), graph_summary_line(result["graph_info"])]
    for k, attempt in enumerate(result["attempts"], 1):
        stats = attempt["stats"]
        lines.append(
            "attempt " + record(
                k=k, clauses=len(attempt["clauses"]),
                removed=removed_count(attempt["preprocess"]),
                result=attempt["status"], stop=attempt["stop"],
                decisions=stats["decisions"], propagations=stats["propagations"],
                conflicts=stats["conflicts"], max_depth=stats["max_depth"],
            )
        )
    lines.append(
        "result " + result["status"] + " " + record(
            chromatic=result["chromatic"], attempts=len(result["attempts"])
        )
    )
    lines.append(search_line(result["stats"]))
    if result["status"] == "SAT":
        lines.extend(model_analysis_lines(result))
    return lines


def render_results(results, error_jobs, all_jobs):
    """Produce the ordered job paragraphs and the final aggregate summary."""
    successes = {result["job"]["number"]: result for result in results}
    errors = {job["number"]: job for job in error_jobs}
    paragraphs = []
    for job in all_jobs:
        number = job["number"]
        if number in errors:
            paragraphs.append([heading(job), "error " + job["error"]])
        else:
            result = successes[number]
            if job["command"] == "CHROMATIC":
                paragraphs.append(render_chromatic_result(result))
            else:
                paragraphs.append(render_regular_result(result))
    stats = [result["stats"] for result in results]
    sat = sum(result["status"] == "SAT" for result in results)
    unsat = sum(result["status"] == "UNSAT" for result in results)
    summary = [
        f"SUMMARY jobs={len(all_jobs)} sat={sat} unsat={unsat} "
        f"error={len(error_jobs)}",
        "totals " + record(
            models=sum(len(r["models"]) for r in results),
            rounds=sum(r["rounds"] for r in results),
            decisions=sum(s["decisions"] for s in stats),
            propagations=sum(s["propagations"] for s in stats),
            conflicts=sum(s["conflicts"] for s in stats),
            removed_clauses=sum(count_removed(r) for r in results),
        ),
    ]
    for command in COMMAND_ORDER:
        members = [r for r in results if r["job"]["command"] == command]
        if not members:
            continue
        summary.append(
            "command " + command + " " + record(
                jobs=len(members),
                sat=sum(r["status"] == "SAT" for r in members),
                unsat=sum(r["status"] == "UNSAT" for r in members),
                decisions=sum(r["stats"]["decisions"] for r in members),
                propagations=sum(r["stats"]["propagations"] for r in members),
                conflicts=sum(r["stats"]["conflicts"] for r in members),
            )
        )
    if results:
        for name, label, metric in (
                ("hardest", "conflicts", "conflicts"),
                ("deepest", "max_depth", "max_depth"),
                ("busiest", "propagations", "propagations")):
            winner = min(
                results, key=lambda r: (-r["stats"][metric], r["job"]["number"])
            )
            summary.append(
                f"{name} job={winner['job']['number']} "
                f"{label}={winner['stats'][metric]}"
            )
    paragraphs.append(summary)
    return paragraphs


def render_models(result):
    """One paragraph per solved job with signed literals in groups of ten."""
    lines = [heading(result["job"])]
    for index, model in enumerate(result["models"], 1):
        lines.append(f"model {index}")
        lines.extend(model_lines(model))
    return lines


def board_queens(result):
    """Canonical dihedral classes, their orbits and first-class boards."""
    job = result["job"]
    n = job["args"]["queens"]
    lines = [f"QUEENS job={job['number']} n={n}"]
    classes = {}
    for number, model in enumerate(result["models"], 1):
        columns = decode_positions(model, n, n)
        forms = queen_variants(columns)
        key = min(forms)
        if key not in classes:
            classes[key] = {
                "number": len(classes) + 1,
                "first": number,
                "found": 0,
                "orbit": len(set(forms)),
            }
        group = classes[key]
        group["found"] += 1
        lines.append(
            f"solution {number} columns={number_list(columns)} "
            f"class={group['number']}"
        )
        if group["first"] == number:
            lines.extend(queen_board(columns))
    for key, value in classes.items():
        lines.append(
            f"class {value['number']} orbit={value['orbit']} "
            f"found={value['found']} first={value['first']} "
            f"canonical={number_list(key)}"
        )
    lines.append(
        f"summary solutions={len(result['models'])} stop={result['stop']} "
        f"classes={len(classes)}"
    )
    return lines


def board_pigeon(result):
    """Assignments, empty holes and the falling-factorial expected count."""
    job = result["job"]
    p, h = job["args"]["pigeons"], job["args"]["holes"]
    lines = [f"PIGEON job={job['number']} pigeons={p} holes={h}"]
    for number, model in enumerate(result["models"], 1):
        choices = decode_positions(model, p, h)
        vacant = [hole for hole in range(1, h + 1) if hole not in choices]
        lines.append(
            f"assignment {number} holes={number_list(choices)} "
            f"empty={number_list(vacant)}"
        )
    expected = 0 if p > h else 1
    if p <= h:
        for i in range(p):
            expected *= h - i
    lines.append(
        f"summary assignments={len(result['models'])} "
        f"stop={result['stop']} expected={expected}"
    )
    return lines


def board_coloring(result, graphs):
    """Color-renaming equivalence classes and deterministic greedy baseline."""
    job = result["job"]
    graph = graphs[job["args"]["graph"]]
    color_count = (len(result["attempts"]) if "attempts" in result else
                   job["args"]["colors"])
    kind = job["command"]
    info = result["graph_info"]
    lines = [
        f"{kind} job={job['number']} graph={graph['name']} "
        f"vertices={graph['vertices']} edges={len(graph['edges'])} "
        f"colors={color_count}",
        f"greedy used={info['greedy']} "
        f"colors={number_list(info['greedy_colors'])}",
    ]
    classes = {}
    for number, model in enumerate(result["models"], 1):
        assigned = decode_positions(model, graph["vertices"], color_count)
        key = canonical_coloring(assigned)
        if key not in classes:
            classes[key] = {
                "number": len(classes) + 1,
                "first": number, "found": 0,
            }
        group = classes[key]
        group["found"] += 1
        sizes = [assigned.count(color) for color in range(1, color_count + 1)]
        lines.append(
            f"coloring {number} colors={number_list(assigned)} "
            f"used={len(set(assigned))} sizes={number_list(sizes)} "
            f"class={group['number']}"
        )
    for key, value in classes.items():
        lines.append(
            f"class {value['number']} found={value['found']} "
            f"first={value['first']} canonical={number_list(key)}"
        )
    stop = result["attempts"][-1]["stop"] if "attempts" in result else result["stop"]
    lines.append(
        f"summary colorings={len(result['models'])} "
        f"stop={stop} classes={len(classes)}"
    )
    return lines


def render_boards(result, graphs):
    command = result["job"]["command"]
    if command == "QUEENS":
        return board_queens(result)
    if command == "PIGEON":
        return board_pigeon(result)
    return board_coloring(result, graphs)


def write_outputs(results, error_jobs, jobs, graphs):
    """Create the four requested files and no additional output artifacts."""
    save_paragraphs(
        "results.txt", render_results(results, error_jobs, jobs)
    )
    save_paragraphs(
        "models.txt", [
            render_models(result) for result in results if result["models"]
        ],
    )
    save_paragraphs(
        "boards.txt", [
            render_boards(result, graphs) for result in results
            if result["job"]["command"] in (
                "QUEENS", "PIGEON", "COLOR", "CHROMATIC"
            )
        ],
    )
    rows = [
        "job,command,status,variables,clauses,removed_clauses,"
        "decisions,propagations,conflicts,max_depth,models,rounds"
    ]
    rows.extend(",".join(map(str, statistics_row(result))) for result in results)
    save_lines("stats.csv", rows)


def main():
    graphs = read_graphs()
    jobs = read_jobs()
    valid_results = []
    errors = []
    for job in jobs:
        error = validate_job(job, graphs)
        if error is not None:
            job["error"] = error
            errors.append(job)
            continue
        valid_results.append(run_job(job, graphs))
    write_outputs(valid_results, errors, jobs, graphs)


if __name__ == "__main__":
    main()
