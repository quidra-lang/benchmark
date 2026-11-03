"""Integer-only dynamic-trace simulation of an in-order five-stage CPU."""

from collections import Counter, defaultdict

from hazards import dependencies, forwarding_path, id_resolved
from pipeline import CAUSES, STAGES, simulate
from predictors import BTB, RAS, DirectionPredictor
from report import (cycle_heading, decimal, diagram_row, hexadecimal, join_parts,
                    percentage, reduced_fraction, register, write_lines)
from trace_io import parse_hex, parse_register, read_inputs


CLASSES = ("ALU", "MUL", "LOAD", "STORE", "BRANCH", "JUMP", "NOP")
CONTROLS = ("BRANCH", "JUMP")
OPERANDS = {
    "ALU": ("required", "required", "optional"),
    "MUL": ("required", "required", "required"),
    "LOAD": ("required", "required", "none"),
    "STORE": ("none", "required", "required"),
    "BRANCH": ("none", "required", "optional"),
    "JUMP": ("optional", "optional", "none"),
    "NOP": ("none", "none", "none"),
}
MISS_KINDS = ("direction", "btb_miss", "wrong_target")


def check_record(line, static):
    tokens = line.split(" ")
    if len(tokens) != 8 or "" in tokens:
        return None, "fields"
    pc_text, kind, rd_text, rs1_text, rs2_text, outcome, target_text, address_text = tokens
    pc = parse_hex(pc_text)
    if pc is None or pc % 4:
        return None, "pc"
    if kind not in CLASSES:
        return None, "class"
    register_texts = (rd_text, rs1_text, rs2_text)
    registers = tuple(parse_register(text) for text in register_texts)
    if any(text != "-" and value is None for text, value in zip(register_texts, registers)):
        return None, "register"
    for text, usage in zip(register_texts, OPERANDS[kind]):
        if (usage == "required" and text == "-") or (usage == "none" and text != "-"):
            return None, "operands"
    allowed = ("T", "N") if kind == "BRANCH" else ("T",) if kind == "JUMP" else ("-",)
    if outcome not in allowed:
        return None, "taken"
    target = parse_hex(target_text)
    if kind in CONTROLS:
        if target is None or target % 4 or target == pc + 4:
            return None, "target"
    elif target_text != "-":
        return None, "target"
    address = parse_hex(address_text)
    if kind in ("LOAD", "STORE"):
        if address is None or address % 4:
            return None, "address"
    elif address_text != "-":
        return None, "address"
    rd, rs1, rs2 = registers
    instruction = {"pc": pc, "class": kind, "rd": rd, "rs1": rs1, "rs2": rs2,
                   "outcome": outcome, "target": target, "address": address}
    if pc in static:
        previous = static[pc]
        if any(instruction[key] != previous[key] for key in ("class", "rd", "rs1", "rs2")):
            return None, "conflict"
        fixed_target = kind == "BRANCH" or (kind == "JUMP" and rs1 is None)
        if fixed_target and target != previous["target"]:
            return None, "conflict"
    instruction["next_pc"] = target if outcome == "T" else pc + 4
    return instruction, None


def validate_trace(lines):
    instructions = []
    rejected = []
    gaps = []
    static = {}
    for line_number, line in enumerate(lines, 1):
        instruction, error = check_record(line, static)
        if error is not None:
            rejected.append((line_number, error))
            continue
        instruction["line"] = line_number
        instruction["number"] = len(instructions) + 1
        if instructions and instruction["pc"] != instructions[-1]["next_pc"]:
            gaps.append((line_number, instructions[-1]["next_pc"], instruction["pc"]))
        instructions.append(instruction)
        static.setdefault(instruction["pc"], instruction)
    return {"lines": len(lines), "instructions": instructions, "rejected": rejected,
            "gaps": gaps, "static": static}


def predict_trace(instructions, definition, config):
    btb = BTB(config["btb"])
    ras = RAS(config["ras"])
    direction = DirectionPredictor(definition["scheme"], definition["parameters"])
    details = [None] * len(instructions)
    flags = [False] * len(instructions)
    statistics = Counter()
    for index, instruction in enumerate(instructions):
        kind = instruction["class"]
        if kind not in CONTROLS:
            continue
        pc = instruction["pc"]
        target = instruction["target"]
        taken = instruction["outcome"] == "T"
        candidate = btb.lookup(pc)
        statistics["lookups"] += 1
        statistics["hits"] += candidate is not None
        is_return = kind == "JUMP" and instruction["rd"] is None and instruction["rs1"] == 31
        is_call = kind == "JUMP" and instruction["rd"] == 31
        statistics["calls"] += is_call
        statistics["returns"] += is_return
        if is_return:
            address = ras.pop()
            if address is not None:
                candidate = address
                statistics["ras_predictions"] += 1
                statistics["ras_correct"] += address == target
        if is_call:
            ras.push(pc + 4)
        predicted_taken = direction.prediction(pc, target) if kind == "BRANCH" else True
        if definition["scheme"] == "PERFECT":
            predicted_pc = instruction["next_pc"]
        elif kind == "JUMP":
            predicted_pc = candidate if candidate is not None else pc + 4
        else:
            predicted_pc = candidate if predicted_taken and candidate is not None else pc + 4
        missed = predicted_pc != instruction["next_pc"]
        miss_kind = None
        if missed:
            if kind == "BRANCH" and predicted_taken != taken:
                miss_kind = "direction"
            else:
                miss_kind = "btb_miss" if candidate is None else "wrong_target"
            statistics[miss_kind] += 1
        flags[index] = missed
        details[index] = {"predicted": predicted_pc, "kind": miss_kind, "missed": missed}
        statistics["control"] += 1
        statistics["mispredictions"] += missed
        statistics[kind] += 1
        statistics[kind + "_misses"] += missed
        if kind == "BRANCH":
            direction.update(pc, taken)
        if taken:
            btb.insert(pc, target)
    return {"definition": definition, "details": details, "flags": flags,
            "statistics": statistics, "bits": direction.storage_bits()}


def stall_totals(records):
    cycles = Counter()
    events = Counter()
    for record in records:
        cycles[record["cause"]] += record["cycles"]
        events[record["cause"]] += 1
    return cycles, events


def all_combinations(instructions, sources, predictions, config):
    combinations = []
    primary = None
    for variant in config["variants"]:
        for predictor in config["predictors"]:
            result = simulate(instructions, sources, variant, predictions[predictor["name"]]["flags"])
            cycles, counts = stall_totals(result["records"])
            combinations.append({"variant": variant["name"], "predictor": predictor["name"],
                                 "cycles": result["cycles"], "stalls": cycles})
            if (variant["name"], predictor["name"]) == config["primary"]:
                primary = {**result, "variant": variant, "predictor": predictor["name"],
                           "stalls": cycles, "stall_events": counts}
    combinations.sort(key=lambda pair: (pair["cycles"], pair["variant"], pair["predictor"]))
    return combinations, primary


def dataflow_height(instructions, sources, latency):
    finish = []
    for instruction, operands in zip(instructions, sources):
        start = max((finish[source["producer"]] for source in operands
                     if source["producer"] is not None), default=0)
        cost = 2 if instruction["class"] == "LOAD" else latency if instruction["class"] == "MUL" else 1
        finish.append(start + cost)
    return max(finish)


def whatif_runs(instructions, sources, primary, flags):
    variant = primary["variant"]
    changes = [
        ("perfect_prediction", variant, [False] * len(instructions)),
        ("single_cycle_mul", {**variant, "latency": 1}, flags),
        ("forwarding_off" if variant["forwarding"] else "forwarding_on",
         {**variant, "forwarding": not variant["forwarding"]}, flags),
        ("branch_stage_ID" if variant["stage"] == "EX" else "branch_stage_EX",
         {**variant, "stage": "ID" if variant["stage"] == "EX" else "EX"}, flags),
    ]
    result = []
    for name, modified, mispredictions in changes:
        count = simulate(instructions, sources, modified, mispredictions)["cycles"]
        result.append((name, count))
    return result


def stall_aggregates(instructions, records):
    classes = Counter()
    by_pc = defaultdict(Counter)
    pairs = {}
    for record in records:
        instruction = instructions[record["responsible"]]
        cause, cycles = record["cause"], record["cycles"]
        classes[instruction["class"]] += cycles
        by_pc[instruction["pc"]][cause] += cycles
        if cause in ("load_use", "raw"):
            producer = instructions[record["producer"]]
            waiting = instructions[record["waiting"]]
            key = producer["pc"], waiting["pc"], cause
            group = pairs.setdefault(key, {"cycles": 0, "events": 0})
            group["cycles"] += cycles
            group["events"] += 1
    return classes, by_pc, pairs


def forwarding_counts(instructions, sources, primary):
    counts = Counter()
    timings = primary["timings"]
    for index, instruction in enumerate(instructions):
        for source in sources[index]:
            producer = source["producer"]
            producer_time = None if producer is None else timings[producer]
            path = forwarding_path(instruction, producer_time, timings[index], primary["variant"])
            counts[path] += 1
    return counts


def correct_row(instruction, timing, annotation):
    f, d, x, m, w = (timing[key] for key in ("F", "D", "X", "M", "W"))
    return {"number": instruction["number"], "pc": instruction["pc"],
            "class": instruction["class"], "annotation": annotation,
            "characters": [(f, f, "F"), (f + 1, d - 1, "*"), (d, d, "D"),
                           (d + 1, x - 1, "*"), (x, m - 1, "X"), (m, m, "M"), (w, w, "W")],
            "stages": [("IF", f, d - 1), ("ID", d, x - 1), ("EX", x, m - 1),
                       ("MEM", m, m), ("WB", w, w)]}


def wrong_rows(prediction, timing, resolved):
    d, x = timing["D"], timing["X"]
    cancel = x if resolved else x + 1
    first = {"number": None, "pc": prediction["predicted"], "class": "FLUSH", "annotation": "",
             "characters": [(d, d, "F"), (d + 1, x - 1, "*"), (cancel, cancel, "x")],
             "stages": [("IF", d, x - 1)]}
    if resolved:
        return [first]
    first["characters"].append((x, x, "D"))
    first["stages"].append(("ID", x, x))
    second = {"number": None, "pc": prediction["predicted"] + 4, "class": "FLUSH", "annotation": "",
              "characters": [(x, x, "F"), (x + 1, x + 1, "x")], "stages": [("IF", x, x)]}
    return [first, second]


def build_rows(instructions, primary, prediction):
    annotations = defaultdict(list)
    for record in primary["records"]:
        if record["waiting"] is not None:
            annotations[record["waiting"]].append(f" {record['cause']} {record['cycles']}")
    rows = []
    for index, (instruction, timing) in enumerate(zip(instructions, primary["timings"])):
        annotation = "".join(annotations[index])
        detail = prediction["details"][index]
        if prediction["flags"][index]:
            annotation += " mispredict " + detail["kind"]
        rows.append(correct_row(instruction, timing, annotation))
        if prediction["flags"][index]:
            rows.extend(wrong_rows(detail, timing, id_resolved(instruction, primary["variant"])))
    return rows


def occupancy(rows):
    counts = {stage: Counter() for stage in STAGES}
    for row in rows:
        kind = "wrong" if row["number"] is None else "correct"
        for stage, first, last in row["stages"]:
            counts[stage][kind] += last - first + 1
    return counts


def pipeline_lines(rows, primary, config):
    first, last = config["window"]
    width = last - first + 1
    lines = [f"pipeline variant={primary['variant']['name']} predictor={primary['predictor']} cycles {first}-{last}",
             cycle_heading(first, last)]
    contents = [["."] * len(STAGES) for _ in range(width)]
    visible = 0
    stalled = 0
    flushed = 0
    for row in rows:
        characters = ["."] * width
        for begin, end, symbol in row["characters"]:
            for cycle in range(max(first, begin), min(last, end) + 1):
                characters[cycle - first] = symbol
        if any(symbol != "." for symbol in characters):
            visible += 1
            stalled += characters.count("*")
            flushed += characters.count("x")
            lines.append(diagram_row(row["number"], row["pc"], row["class"],
                                     "".join(characters), row["annotation"]))
        for stage, begin, end in row["stages"]:
            for cycle in range(max(first, begin), min(last, end) + 1):
                contents[cycle - first][STAGES.index(stage)] = "w" if row["number"] is None else str(row["number"])
    completed = sum(first <= time["W"] <= last for time in primary["timings"])
    lines.extend([f"rows {visible} completed {completed} stall_cells {stalled} flushed {flushed}",
                  "", "stages", "cycle IF ID EX MEM WB"])
    lines.extend(f"{cycle} " + " ".join(content) for cycle, content in enumerate(contents, first))
    return lines


def input_part(trace):
    instructions = trace["instructions"]
    lines = [f"input lines {trace['lines']} accepted {len(instructions)} rejected {len(trace['rejected'])} gaps {len(trace['gaps'])}"]
    lines.extend(f"reject line {line} {reason}" for line, reason in trace["rejected"])
    lines.extend(f"gap line {line} expected {hexadecimal(expected)} found {hexadecimal(found)}"
                 for line, expected, found in trace["gaps"])
    return lines


def trace_part(trace, sources):
    instructions = trace["instructions"]
    static = trace["static"]
    classes = Counter(instruction["class"] for instruction in instructions)
    branches = [instruction for instruction in instructions if instruction["class"] == "BRANCH"]
    jumps = [instruction for instruction in instructions if instruction["class"] == "JUMP"]
    addresses = {instruction["address"] for instruction in instructions if instruction["class"] in ("LOAD", "STORE")}
    distances = Counter()
    source_count = 0
    for index, operands in enumerate(sources):
        source_count += len(operands)
        for source in operands:
            if source["producer"] is not None:
                distances[min(5, index - source["producer"])] += 1
    return ["trace", f"instructions {len(instructions)}", f"static_instructions {len(static)}",
            "mix " + " ".join(f"{kind} {classes[kind]}" for kind in CLASSES),
            f"branches {len(branches)} taken {sum(i['outcome'] == 'T' for i in branches)} "
            f"backward {sum(i['target'] < i['pc'] for i in branches)}",
            f"jumps {len(jumps)} indirect {sum(i['rs1'] is not None for i in jumps)} "
            f"link {sum(i['rd'] is not None for i in jumps)}",
            f"static_control branches {sum(i['class'] == 'BRANCH' for i in static.values())} "
            f"jumps {sum(i['class'] == 'JUMP' for i in static.values())}",
            f"memory loads {classes['LOAD']} stores {classes['STORE']} distinct_addresses {len(addresses)}",
            f"operands {source_count} with_producer {sum(distances.values())} distance "
            + " ".join(f"{label} {distances[i]}" for i, label in enumerate(("1", "2", "3", "4", "5+"), 1))]


def prediction_accuracy(prediction, kind="control"):
    stats = prediction["statistics"]
    total = stats[kind]
    misses = stats["mispredictions"] if kind == "control" else stats[kind + "_misses"]
    return percentage(total - misses, total)


def prediction_part(predictions, config):
    lines = ["prediction"]
    for definition in config["predictors"]:
        prediction = predictions[definition["name"]]
        stats = prediction["statistics"]
        lines.append(f"{definition['name']} {definition['scheme']} bits {prediction['bits']} "
                     f"control {stats['control']} mispredicted {stats['mispredictions']} "
                     f"accuracy {prediction_accuracy(prediction)} branches {prediction_accuracy(prediction, 'BRANCH')} "
                     f"jumps {prediction_accuracy(prediction, 'JUMP')} "
                     + " ".join(f"{kind} {stats[kind]}" for kind in MISS_KINDS))
    stats = predictions[config["predictors"][0]["name"]]["statistics"]
    lines.extend([f"btb entries {config['btb']} lookups {stats['lookups']} hits {stats['hits']} misses {stats['lookups'] - stats['hits']}",
                  f"ras depth {config['ras']} calls {stats['calls']} returns {stats['returns']} "
                  f"predicted {stats['ras_predictions']} correct {stats['ras_correct']}"])
    return lines


def cause_values(values):
    return " ".join(f"{cause} {values[cause]}" for cause in CAUSES)


def timing_part(primary, instruction_count, height, refetch_count):
    variant = primary["variant"]
    cycles = primary["cycles"]
    stalls = primary["stalls"]
    total_stalls = sum(stalls.values())
    lengths = Counter(min(5, value) for value in primary["delays"] if value > 0)
    cpi_causes = " ".join(f"{cause} {decimal(stalls[cause], instruction_count)}" for cause in CAUSES)
    return [f"timing variant={variant['name']} predictor={primary['predictor']}",
            f"forwarding {'on' if variant['forwarding'] else 'off'} branch_stage {variant['stage']} mul_latency {variant['latency']}",
            f"cycles {cycles}", f"cpi {reduced_fraction(cycles, instruction_count)} {decimal(cycles, instruction_count)}",
            f"ipc {decimal(instruction_count, cycles)}", f"stall_cycles total {total_stalls} {cause_values(stalls)}",
            "stall_events " + cause_values(primary["stall_events"]), f"flushed {refetch_count}",
            f"cycle_check {instruction_count} + 4 + {total_stalls} = {instruction_count + 4 + total_stalls}",
            f"cpi_stack base 1.0000 fill {decimal(4, instruction_count)} {cpi_causes}",
            "stall_lengths " + " ".join(f"{label} {lengths[i]}" for i, label in enumerate(("1", "2", "3", "4", "5+"), 1)),
            f"dataflow height {height} ilp {decimal(instruction_count, height)}"]


def whatif_part(runs, total_cycles):
    return ["whatif"] + [f"{name} cycles {cycles} saved {total_cycles - cycles} speedup {decimal(total_cycles, cycles)}"
                         for name, cycles in runs]


def classes_part(instructions, cycles):
    counts = Counter(instruction["class"] for instruction in instructions)
    lines = ["classes"]
    for kind in CLASSES:
        per_instruction = decimal(cycles[kind], counts[kind]) if counts[kind] else "-"
        lines.append(f"{kind} count {counts[kind]} stall_cycles {cycles[kind]} per_instruction {per_instruction}")
    return lines


def occupancy_part(counts, cycles):
    lines = [f"occupancy cycles {cycles}"]
    for stage in STAGES:
        correct, wrong = counts[stage]["correct"], counts[stage]["wrong"]
        lines.append(f"{stage} correct {correct} wrong {wrong} idle {cycles - correct - wrong} "
                     f"busy {percentage(correct + wrong, cycles)}")
    return lines


def hotspots_part(by_pc, static, limit):
    pcs = sorted(by_pc, key=lambda pc: (-sum(by_pc[pc].values()), pc))[:limit]
    lines = ["hotspots"]
    for rank, pc in enumerate(pcs, 1):
        causes = by_pc[pc]
        lines.append(f"{rank} {hexadecimal(pc)} {static[pc]['class']} stall_cycles {sum(causes.values())} "
                     + cause_values(causes))
    return lines


def dependencies_part(pairs, static, limit):
    ordered = sorted(pairs, key=lambda key: (-pairs[key]["cycles"], key[0], key[1], CAUSES.index(key[2])))
    lines = [f"dependencies total {len(pairs)}"]
    for rank, (producer, waiting, cause) in enumerate(ordered[:limit], 1):
        data = pairs[(producer, waiting, cause)]
        lines.append(f"{rank} {hexadecimal(producer)} {static[producer]['class']} -> "
                     f"{hexadecimal(waiting)} {static[waiting]['class']} {cause} "
                     f"stall_cycles {data['cycles']} events {data['events']}")
    return lines


def intervals_part(timings, size):
    lines = [f"intervals size {size}"]
    for first in range(0, len(timings), size):
        last = min(len(timings), first + size) - 1
        previous = timings[first - 1]["W"] if first else 0
        cycles = timings[last]["W"] - previous
        lines.append(f"{first + 1}-{last + 1} cycles {cycles} cpi {decimal(cycles, last - first + 1)}")
    return lines


def cycles_table_part(combinations, config):
    table = {(pair["variant"], pair["predictor"]): pair["cycles"] for pair in combinations}
    predictor_names = [definition["name"] for definition in config["predictors"]]
    lines = ["cycles_table " + " ".join(predictor_names)]
    for variant in config["variants"]:
        lines.append(variant["name"] + " " + " ".join(str(table[(variant["name"], name)]) for name in predictor_names))
    return lines


def statistics_lines(trace, sources, predictions, combinations, primary, rows, config):
    instructions = trace["instructions"]
    height = dataflow_height(instructions, sources, primary["variant"]["latency"])
    flags = predictions[primary["predictor"]]["flags"]
    whatif = whatif_runs(instructions, sources, primary, flags)
    class_stalls, by_pc, pairs = stall_aggregates(instructions, primary["records"])
    forwarding = forwarding_counts(instructions, sources, primary)
    forward_line = "forwarding " + " ".join(f"{path} {forwarding[path]}" for path in ("regfile", "ex_mem", "mem_wb"))
    return join_parts([
        input_part(trace), trace_part(trace, sources), prediction_part(predictions, config),
        timing_part(primary, len(instructions), height, sum(row["number"] is None for row in rows)),
        whatif_part(whatif, primary["cycles"]), classes_part(instructions, class_stalls),
        [forward_line], occupancy_part(occupancy(rows), primary["cycles"]),
        hotspots_part(by_pc, trace["static"], config["top"]), dependencies_part(pairs, trace["static"], config["top"]),
        intervals_part(primary["timings"], config["interval"]), cycles_table_part(combinations, config),
    ])


def group_executions(instructions):
    groups = defaultdict(list)
    for index, instruction in enumerate(instructions):
        groups[instruction["pc"]].append(index)
    return dict(sorted(groups.items()))


def branch_lines(instructions, groups, predictions, config):
    lines = ["predictor,pc,class,executions,taken,mispredictions,accuracy"]
    for definition in config["predictors"]:
        name = definition["name"]
        flags = predictions[name]["flags"]
        for pc, indices in groups.items():
            kind = instructions[indices[0]]["class"]
            if kind not in CONTROLS:
                continue
            taken = sum(instructions[i]["outcome"] == "T" for i in indices)
            missed = sum(flags[i] for i in indices)
            lines.append(f"{name},{hexadecimal(pc)},{kind},{len(indices)},{taken},{missed},{percentage(len(indices) - missed, len(indices))}")
    return lines


def comparison_lines(combinations, primary, predictions, count):
    lines = ["rank,variant,predictor,cycles,cpi,speedup,accuracy,mispredictions,control,structural,load_use,raw"]
    for rank, pair in enumerate(combinations, 1):
        prediction = predictions[pair["predictor"]]
        values = [str(rank), pair["variant"], pair["predictor"], str(pair["cycles"]),
                  decimal(pair["cycles"], count), decimal(primary["cycles"], pair["cycles"]),
                  prediction_accuracy(prediction), str(prediction["statistics"]["mispredictions"])]
        values.extend(str(pair["stalls"][cause]) for cause in CAUSES)
        lines.append(",".join(values))
    return lines


def longest_runs(outcomes):
    longest = {"T": 0, "N": 0}
    previous = None
    length = 0
    for outcome in outcomes:
        length = length + 1 if outcome == previous else 1
        longest[outcome] = max(longest[outcome], length)
        previous = outcome
    return longest


def branch_profile(instructions, groups, predictions, config):
    lines = ["branches"]
    choices = [definition["name"] for definition in config["predictors"] if definition["scheme"] != "PERFECT"]
    for pc, indices in groups.items():
        instruction = instructions[indices[0]]
        if instruction["class"] != "BRANCH":
            continue
        outcomes = [instructions[i]["outcome"] for i in indices]
        transitions = sum(a != b for a, b in zip(outcomes, outcomes[1:]))
        longest = longest_runs(outcomes)
        misses = {name: sum(predictions[name]["flags"][i] for i in indices) for name in choices}
        best = min(choices, key=lambda name: (misses[name], choices.index(name)))
        direction = "backward" if instruction["target"] < pc else "forward"
        lines.append(f"{hexadecimal(pc)} {direction} executions {len(indices)} taken {outcomes.count('T')} "
                     f"transitions {transitions} longest_taken {longest['T']} longest_not_taken {longest['N']} best {best} {misses[best]}")
    return lines


def loops_profile(instructions, groups):
    lines = ["loops"]
    for pc, indices in groups.items():
        instruction = instructions[indices[0]]
        if instruction["class"] != "BRANCH" or instruction["target"] >= pc:
            continue
        trips = []
        length = 0
        for index in indices:
            length += 1
            if instructions[index]["outcome"] == "N":
                trips.append(length)
                length = 0
        if length:
            trips.append(length)
        target = instruction["target"]
        lines.append(f"{hexadecimal(target)}-{hexadecimal(pc)} body {(pc - target) // 4 + 1} "
                     f"entries {len(trips)} iterations {len(indices)} avg_trip {decimal(len(indices), len(trips))} max_trip {max(trips)}")
    return lines


def segments_profile(instructions, timings, limit):
    groups = {}
    first = 0
    for last, instruction in enumerate(instructions):
        if instruction["class"] in CONTROLS or last == len(instructions) - 1:
            pc = instructions[first]["pc"]
            group = groups.setdefault(pc, {"instances": 0, "instructions": 0, "cycles": 0})
            group["instances"] += 1
            group["instructions"] += last - first + 1
            group["cycles"] += timings[last]["W"] - (timings[first - 1]["W"] if first else 0)
            first = last + 1
    ranked = sorted(groups, key=lambda pc: (-groups[pc]["cycles"], pc))
    lines = [f"segments total {len(groups)}"]
    for rank, pc in enumerate(ranked[:limit], 1):
        group = groups[pc]
        lines.append(f"{rank} {hexadecimal(pc)} instances {group['instances']} instructions {group['instructions']} "
                     f"cycles {group['cycles']} cpi {decimal(group['cycles'], group['instructions'])}")
    return lines


def indirect_profile(instructions, groups):
    lines = ["indirect"]
    for pc, indices in groups.items():
        instruction = instructions[indices[0]]
        if instruction["class"] != "JUMP" or instruction["rs1"] is None:
            continue
        targets = Counter(instructions[i]["target"] for i in indices)
        ordered = sorted(targets, key=lambda target: (-targets[target], target))
        values = " ".join(f"{hexadecimal(target)}:{targets[target]}" for target in ordered)
        lines.append(f"{hexadecimal(pc)} executions {len(indices)} distinct {len(targets)} targets {values}")
    return lines


def static_profile(instructions, groups, records):
    stalls = Counter()
    for record in records:
        stalls[instructions[record["responsible"]]["pc"]] += record["cycles"]
    lines = ["instructions"]
    for pc, indices in groups.items():
        instruction = instructions[indices[0]]
        operands = " ".join(register(instruction[key]) for key in ("rd", "rs1", "rs2"))
        lines.append(f"{hexadecimal(pc)} {instruction['class']} {operands} executions {len(indices)} stall_cycles {stalls[pc]}")
    return lines


def profile_lines(instructions, groups, predictions, primary, config):
    return join_parts([
        branch_profile(instructions, groups, predictions, config),
        loops_profile(instructions, groups), segments_profile(instructions, primary["timings"], config["top"]),
        indirect_profile(instructions, groups), static_profile(instructions, groups, primary["records"]),
    ])


def main():
    lines, config = read_inputs()
    trace = validate_trace(lines)
    instructions = trace["instructions"]
    sources = dependencies(instructions)
    predictions = {definition["name"]: predict_trace(instructions, definition, config)
                   for definition in config["predictors"]}
    combinations, primary = all_combinations(instructions, sources, predictions, config)
    rows = build_rows(instructions, primary, predictions[primary["predictor"]])
    groups = group_executions(instructions)
    write_lines("pipeline.txt", pipeline_lines(rows, primary, config))
    write_lines("stats.txt", statistics_lines(trace, sources, predictions, combinations, primary, rows, config))
    write_lines("branches.csv", branch_lines(instructions, groups, predictions, config))
    write_lines("comparison.csv", comparison_lines(combinations, primary, predictions, len(instructions)))
    write_lines("profile.txt", profile_lines(instructions, groups, predictions, primary, config))


if __name__ == "__main__":
    main()
