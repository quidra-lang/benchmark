"""Phylogenetic searches, statistical analyses, and the ten required reports."""

from collections import Counter
from itertools import combinations
from math import exp, log, sqrt
from pathlib import Path

import alignment
import distances
import parsimony
import tree_building
import tree_io
from tree_io import real, symbols


NJ_METHODS = ("NJ_P", "NJ_JC", "NJ_K2P")
METHODS = (*NJ_METHODS, "ME", "MP", "CONSENSUS")


def ordered_sum(values):
    total = 0.0
    for value in values:
        total += value
    return total


def square(value):
    return value * value


def read_parameters():
    parameters = {}
    integers = {"replicates", "seed", "max_missing_percent", "low_sites"}
    with Path("input/params.txt").open(encoding="ascii") as source:
        for line in source:
            key, *values = line.split()
            if key in integers:
                parameters[key] = int(values[0])
            elif key == "saturation_distance":
                parameters[key] = float(values[0])
            elif key == "exhaustive_taxa":
                parameters[key] = values
            else:
                parameters[key] = values[0]
    return parameters


def check_records(records, maximum_missing):
    length = len(records[0][2])
    seen = set()
    accepted = []
    rejected = []
    for line, name, sequence in records:
        reason = None
        if name in seen:
            reason = "duplicate name"
        seen.add(name)
        if reason is None:
            for column, character in enumerate(sequence, 1):
                if character not in alignment.BASE_SETS:
                    reason = f"invalid character {character} at column {column}"
                    break
        if reason is None and len(sequence) != length:
            reason = f"length mismatch {len(sequence)}"
        if reason is None:
            missing = sequence.count("-") + sequence.count("N")
            if 100 * missing > maximum_missing * length:
                reason = f"too many missing {missing}"
        if reason is None:
            accepted.append((name, sequence))
        else:
            rejected.append((line, name, reason))
    return accepted, rejected, length


def summary_lines(records, rejected, names, sequences, patterns):
    length = len(sequences[0])
    lines = [
        f"INPUT records {len(records)} accepted {len(names)} rejected {len(rejected)} columns {length}"
    ]
    for line, name, reason in rejected:
        lines.append(f"REJECT line {line} {name} {reason}")
    columns = [Counter(character for character in column if character in alignment.BASES)
               for column in zip(*sequences)]
    composition = [0] * 4
    for name, sequence in zip(names, sequences):
        counts = Counter(sequence)
        bases = sum(counts[base] for base in alignment.BASES)
        ambiguous = sum(counts[character] for character in alignment.AMBIGUOUS)
        missing = counts["-"] + counts["N"]
        unique = 0
        for character, column in zip(sequence, columns):
            if character in alignment.BASES and column[character] == 1 and sum(column.values()) > 1:
                unique += 1
        gc = (counts["C"] + counts["G"]) / bases
        lines.append(
            f"TAXON {name} bases {bases} ambiguous {ambiguous} missing {missing} "
            f"unique {unique} gc {real(gc, 4)}"
        )
        for index, base in enumerate(alignment.BASES):
            composition[index] += counts[base]
    classes = alignment.classify_columns(sequences)
    lines.append("COLUMNS " + " ".join(f"{kind} {count}" for kind, count in classes.items()))
    lines.append(f"PATTERNS {len(patterns.patterns)}")
    total = sum(composition)
    lines.append("COMPOSITION " + " ".join(
        f"{base} {real(count / total, 4)}" for base, count in zip(alignment.BASES, composition)
    ))
    return lines


def matrix_lines(names, matrix):
    width = max(map(len, names))
    return [f"{name:<{width}} " + " ".join(real(value, 5) for value in row)
            for name, row in zip(names, matrix)]


def parsimony_bounds(patterns):
    minimum_by_pattern = []
    maximum = 0
    for pattern, weight in zip(patterns.encoded, patterns.weights):
        minimum = min(mask.bit_count() for mask in range(1, 16)
                      if all(mask & bases for bases in pattern)) - 1
        minimum_by_pattern.append(minimum)
        greatest = min(sum(not (bases & base) for bases in pattern) for base in (1, 2, 4, 8))
        maximum += greatest * weight
    minimum_by_column = [minimum_by_pattern[index] for index in patterns.columns]
    return sum(minimum_by_column), maximum, minimum_by_column


def bme_length(tree, matrix):
    taxa = tree.taxa()
    total = 0.0
    for index, first in enumerate(taxa):
        steps = tree_building.path_distances(tree, first, unit=True)
        for second in taxa[index + 1:]:
            total += matrix[first][second] / (2 ** (steps[second] - 1))
    return total


def stepwise(taxa, size, patterns, outgroup):
    tree = tree_building.star(size, taxa[:3])
    initial = parsimony.score(tree, patterns, outgroup)
    current = initial
    additions = []
    evaluated = 0
    for taxon in taxa[3:]:
        best = None
        chosen = None
        selected_mask = None
        ties = 0
        for mask, first, second in parsimony.branches(tree, outgroup):
            candidate = parsimony.insert(tree, first, second, taxon)
            value = parsimony.score(candidate, patterns, outgroup)
            evaluated += 1
            if best is None or value < best:
                best = value
                chosen = candidate
                selected_mask = mask
                ties = 1
            elif value == best:
                ties += 1
        tree, current = chosen, best
        additions.append((taxon, selected_mask, current, ties))
    return {"tree": tree, "initial": initial, "score": current,
            "additions": additions, "evaluated": evaluated, "taxa": taxa}


def hill_climb(tree, objective, outgroup, value):
    tree = tree.copy()
    evaluated = 0
    moves = []
    while True:
        for mask, swap, candidate in parsimony.nni_candidates(tree, outgroup):
            candidate_value = objective(candidate)
            evaluated += 1
            if candidate_value < value:
                tree, value = candidate, candidate_value
                moves.append((mask, swap, value))
                break
        else:
            break
    return {"tree": tree, "value": value, "moves": moves, "evaluated": evaluated}


def consensus_tree(size, taxa, outgroup, clades):
    tree = tree_building.Tree(size, taxa)
    root = tree.internal()
    nodes = {mask: tree.internal() for mask in sorted(clades)}
    for mask, node in nodes.items():
        containers = [other for other in nodes if other != mask and other & mask == mask]
        parent = nodes[min(containers, key=int.bit_count)] if containers else root
        tree.connect(parent, node)
    for taxon in taxa:
        containers = [mask for mask in nodes if mask & (1 << taxon)]
        parent = nodes[min(containers, key=int.bit_count)] if containers else root
        tree.connect(parent, taxon)
    return tree


def exhaustive_search(taxa, names, patterns, outgroup, matrix):
    trees = [tree_building.star(len(names), taxa[:3])]
    for taxon in taxa[3:]:
        expanded = []
        for tree in trees:
            for mask, first, second in parsimony.branches(tree, outgroup):
                expanded.append(parsimony.insert(tree, first, second, taxon))
        trees = expanded
    records = []
    histogram = Counter()
    for tree in trees:
        score = parsimony.score(tree, patterns, outgroup)
        histogram[score] += 1
        records.append({
            "tree": tree, "score": score, "bme": bme_length(tree, matrix),
            "newick": tree_io.newick(tree, names, outgroup),
            "splits": tree.rooted(outgroup).splits(),
        })
    best_score = min(histogram)
    optimal = sorted((record for record in records if record["score"] == best_score),
                     key=lambda record: record["newick"])
    common = optimal[0]["splits"].copy()
    for record in optimal[1:]:
        common.intersection_update(record["splits"])
    strict = consensus_tree(len(names), taxa, outgroup, common)
    best_bme = min(records, key=lambda record: (record["bme"], record["newick"]))
    second_bme = min(record["bme"] for record in records if record is not best_bme)
    initial = stepwise(taxa, len(names), patterns, outgroup)
    heuristic = hill_climb(initial["tree"], lambda tree: parsimony.score(tree, patterns, outgroup),
                           outgroup, initial["score"])
    return {"taxa": taxa, "records": records, "histogram": histogram, "best_score": best_score,
            "optimal": optimal, "strict": strict, "best_bme": best_bme, "second_bme": second_bme,
            "heuristic": heuristic["value"]}


def likelihood_sites(tree, names, patterns, outgroup):
    rooted = tree.rooted(outgroup)
    children = tree_io.child_order(rooted, names)
    transition = {}
    for node in rooted.order[1:]:
        length = tree.adjacent[node][rooted.parents[node]]
        exponential = exp(-(4 * length) / 3)
        same = 1 / 4 + (3 / 4) * exponential
        different = 1 / 4 - (1 / 4) * exponential
        transition[node] = [[same if first == second else different for second in range(4)]
                            for first in range(4)]
    pattern_values = []
    for pattern in patterns.encoded:
        partial = {}
        upward = {}
        for node in reversed(rooted.order):
            if node < tree.size:
                partial[node] = [1.0 if pattern[node] & (1 << base) else 0.0 for base in range(4)]
            else:
                values = [1.0] * 4
                for child in children[node]:
                    for base in range(4):
                        values[base] *= upward[child][base]
                partial[node] = values
            if node != rooted.root:
                upward[node] = [ordered_sum(transition[node][first][second] * partial[node][second]
                                           for second in range(4)) for first in range(4)]
        probability = ordered_sum((1 / 4) * value for value in partial[rooted.root])
        pattern_values.append(log(probability))
    return [pattern_values[index] for index in patterns.columns]


def likelihood_lines(names, patterns, nj_trees, outgroup, main_method, low_count, site_logs):
    length = len(patterns.columns)
    lines = [f"LIKELIHOOD columns {length} patterns {len(patterns.patterns)}"]
    for method in NJ_METHODS:
        total = ordered_sum(site_logs[method])
        lines.append(f"TREE {method} loglik {real(total, 4)} per_site {real(total / length, 4)}")
    for first, second in combinations(NJ_METHODS, 2):
        deltas = [a - b for a, b in zip(site_logs[first], site_logs[second])]
        difference = ordered_sum(deltas)
        mean = difference / length
        standard_error = sqrt((length / (length - 1)) * ordered_sum(square(delta - mean) for delta in deltas))
        lines.append(
            f"KH {first} {second} difference {real(difference, 4)} se {real(standard_error, 4)} "
            f"z {real(difference / standard_error, 4)}"
        )
    lowest = sorted(range(length), key=lambda column: (float(real(site_logs[main_method][column], 4)), column))
    changes = parsimony.pattern_scores(nj_trees[main_method], patterns, outgroup)
    lines.append(f"LOWEST {main_method} sites {low_count}")
    for column in lowest[:low_count]:
        index = patterns.columns[column]
        lines.append(
            f"SITE {column + 1} loglik {real(site_logs[main_method][column], 4)} "
            f"changes {changes[index]} pattern {patterns.patterns[index]}"
        )
    return lines


def bootstrap(names, sequences, parameters, main_tree, main_matrix, outgroup):
    count, length = len(names), len(sequences[0])
    replicates = parameters["replicates"]
    state = parameters["seed"]
    support = Counter()
    main_splits = main_tree.rooted(outgroup).splits()
    lines = [f"BOOTSTRAP model {parameters['model']} replicates {replicates} seed {state}"]
    identical = 0
    for replicate in range(1, replicates + 1):
        weights = [0] * length
        for draw in range(length):
            state = (48271 * state) % 2147483647
            weights[state % length] += 1
        pairs = distances.all_pairs(sequences, weights)
        matrix, saturated = distances.build_matrix(pairs, count, parameters["model"],
                                                   parameters["saturation_distance"])
        tree = tree_building.neighbor_joining(matrix, range(count))
        splits = tree.rooted(outgroup).splits()
        support.update(splits)
        difference = len(splits ^ main_splits)
        identical += difference == 0
        distinct = sum(weight > 0 for weight in weights)
        lines.append(f"REPLICATE {replicate} distinct {distinct} rf {difference}")
    lines.append(f"IDENTICAL {identical}")
    for mask in sorted(main_splits, key=lambda mask: symbols(mask, count)):
        lines.append(f"SUPPORT {symbols(mask, count)} {support[mask]}")
    for mask in sorted(support, key=lambda mask: (-support[mask], symbols(mask, count))):
        lines.append(f"SPLIT {symbols(mask, count)} {support[mask]}")
    majority = {mask for mask, value in support.items() if 2 * value > replicates}
    consensus = consensus_tree(count, range(count), outgroup, majority)
    lines.append("CONSENSUS " + tree_io.newick(consensus, names, outgroup, support=support))
    for taxon in range(count):
        if taxon == outgroup:
            continue
        taxa = [other for other in range(count) if other != taxon]
        tree = tree_building.neighbor_joining(main_matrix, taxa)
        reduced = {mask & ~(1 << taxon) for mask in main_splits}
        reduced = {mask for mask in reduced if 2 <= mask.bit_count() <= count - 3}
        difference = len(tree.rooted(outgroup).splits() ^ reduced)
        lines.append(f"JACKKNIFE {names[taxon]} rf {difference}")
    return consensus, support, lines


def clock_lines(names, sequences, outgroup, main_method, main_tree):
    ingroup = [taxon for taxon in range(len(names)) if taxon != outgroup]
    pairs = []
    rejected = 0
    for first, second in combinations(ingroup, 2):
        m1 = m2 = 0
        for a, b, o in zip(sequences[first], sequences[second], sequences[outgroup]):
            if a in alignment.BASES and b in alignment.BASES and o in alignment.BASES and a != b:
                m1 += b == o
                m2 += a == o
        reject = 1000 * square(m1 - m2) > 3841 * (m1 + m2)
        rejected += reject
        chi_squared = real(square(m1 - m2) / (m1 + m2), 4) if m1 + m2 else "-"
        pairs.append(f"RRT {names[first]} {names[second]} m1 {m1} m2 {m2} "
                     f"chi2 {chi_squared} {'reject' if reject else 'ok'}")
    lines = [f"RELATIVE_RATE outgroup {names[outgroup]} pairs {len(pairs)} rejected {rejected}", *pairs]
    root = main_tree.rooted(outgroup).root
    paths = tree_building.path_distances(main_tree, root)
    mean = ordered_sum(paths[taxon] for taxon in ingroup) / len(ingroup)
    deviation = sqrt(ordered_sum(square(paths[taxon] - mean) for taxon in ingroup) / (len(ingroup) - 1))
    lines.append(f"ROOT_TO_TIP {main_method} mean {real(mean, 5)} sd {real(deviation, 5)} "
                 f"cv {real(deviation / mean, 4)}")
    lines.extend(f"TIP {names[taxon]} {real(paths[taxon], 5)}" for taxon in ingroup)
    return lines


def quartet_topologies(splits, count):
    topologies = []
    for a, b, c, d in combinations(range(count), 4):
        quartet = (1 << a) | (1 << b) | (1 << c) | (1 << d)
        topology = 0
        for number, other in enumerate((b, c, d), 1):
            side = (1 << a) | (1 << other)
            if any((mask & quartet) in (side, quartet ^ side) for mask in splits):
                topology = number
                break
        topologies.append(topology)
    return topologies


def comparison_lines(names, patterns, trees, matrices, main_matrix, main_method, outgroup,
                     support, replicates, nj_scores, mp_score, mp_changes, site_logs, patristic):
    count = len(names)
    splits = {method: trees[method].rooted(outgroup).splits() for method in METHODS}
    lines = []
    for method in METHODS:
        supported = sum(2 * support[mask] > replicates for mask in splits[method])
        score = bme = length = negative = residual = likelihood = "-"
        tree = trees[method]
        if method != "CONSENSUS":
            if method in NJ_METHODS:
                value = nj_scores[method]
            elif method == "MP":
                value = mp_score
            else:
                value = parsimony.score(tree, patterns, outgroup)
            score = str(value)
            bme = real(bme_length(tree, main_matrix), 5)
        if method in NJ_METHODS:
            length = real(ordered_sum(tree.adjacent[first][second]
                                      for mask, first, second in parsimony.branches(tree, outgroup)), 5)
            negative = str(tree.negative)
            matrix = matrices[method[3:]]
            residual = real(ordered_sum(square(matrix[first][second] - patristic[method][first][second])
                                        for first, second in combinations(range(count), 2)), 6)
            likelihood = real(ordered_sum(site_logs[method]), 4)
        elif method == "MP":
            length = real(mp_score / len(patterns.columns), 5)
        lines.append(
            f"TREE {method} splits {len(splits[method])} supported {supported} parsimony {score} "
            f"bme {bme} length {length} negative {negative} sse {residual} loglik {likelihood}"
        )
    lines.append("RF " + " ".join(METHODS))
    for first in METHODS:
        values = [len(splits[first] ^ splits[second]) for second in METHODS]
        lines.append(first + " " + " ".join(map(str, values)))
    quartets = {method: quartet_topologies(splits[method], count) for method in METHODS}
    lines.append("QUARTET " + " ".join(METHODS))
    for first in METHODS:
        values = [sum(a != b for a, b in zip(quartets[first], quartets[second])) for second in METHODS]
        lines.append(first + " " + " ".join(map(str, values)))
    all_clades = set().union(*splits.values())
    lengths = trees[main_method].rooted(outgroup).branch_lengths()
    changes = {mask: mp_changes[tuple(sorted((first, second)))]
               for mask, first, second in parsimony.branches(trees["MP"], outgroup)}
    for mask in sorted(all_clades, key=lambda mask: symbols(mask, count)):
        marks = "".join("+" if mask in splits[method] else "-" for method in METHODS)
        length = real(lengths[mask], 5) if mask in lengths else "-"
        change = str(changes[mask]) if mask in changes else "-"
        lines.append(f"CLADE {symbols(mask, count)} support {support[mask]} trees {marks} "
                     f"length {length} changes {change}")
    return lines


def hypothesis_lines(names, trees, outgroup, support, exhaustive):
    numbers = {name: taxon for taxon, name in enumerate(names)}
    ingroup = ((1 << len(names)) - 1) ^ (1 << outgroup)
    exhaustive_ingroup = sum(1 << taxon for taxon in exhaustive["taxa"] if taxon != outgroup)
    splits = {method: trees[method].rooted(outgroup).splits() for method in METHODS}
    lines = []
    with Path("input/clades.txt").open(encoding="ascii") as source:
        for line in source:
            hypothesis, *members = line.split()
            unknown = next((name for name in members if name not in numbers), None)
            if unknown is not None:
                lines.append(f"INVALID {hypothesis} unknown taxon {unknown}")
                continue
            if names[outgroup] in members:
                lines.append(f"INVALID {hypothesis} contains outgroup")
                continue
            mask = sum(1 << numbers[name] for name in members)
            lines.append(f"CLADE {hypothesis} taxa {mask.bit_count()} support {support[mask]}")
            for method in METHODS:
                containers = [clade for clade in splits[method] | {ingroup} if clade & mask == mask]
                common = min(containers, key=int.bit_count)
                intruders = [name for taxon, name in enumerate(names)
                             if common & ~mask & (1 << taxon)]
                joined = ",".join(intruders) if intruders else "-"
                verdict = "yes" if common == mask else "no"
                lines.append(f"TEST {hypothesis} {method} monophyletic {verdict} "
                             f"mrca {common.bit_count()} intruders {joined}")
            subset = mask & exhaustive_ingroup
            if not 2 <= subset.bit_count() < exhaustive_ingroup.bit_count():
                lines.append(f"SUBSET {hypothesis} untestable")
                continue
            included = [record for record in exhaustive["records"] if subset in record["splits"]]
            excluded = [record for record in exhaustive["records"] if subset not in record["splits"]]
            with_score = min(record["score"] for record in included)
            without_score = min(record["score"] for record in excluded)
            with_bme = min(record["bme"] for record in included)
            without_bme = min(record["bme"] for record in excluded)
            lines.append(f"SUBSET {hypothesis} taxa {subset.bit_count()} with {with_score} "
                         f"without {without_score} bme_with {real(with_bme, 5)} "
                         f"bme_without {real(without_bme, 5)}")
    return lines


def distance_lines(names, pairs, matrices, saturated, main_method, patristic, me_start, me, exhaustive, outgroup):
    totals = [0, 0, 0]
    pair_block = []
    for first, second, sites, transitions, transversions in pairs:
        pair_block.append(f"PAIR {names[first]} {names[second]} sites {sites} "
                          f"transitions {transitions} transversions {transversions}")
        for index, value in enumerate((sites, transitions, transversions)):
            totals[index] += value
    pair_block.append(f"TOTAL sites {totals[0]} transitions {totals[1]} transversions {totals[2]}")
    blocks = [pair_block]
    for model in distances.MODELS:
        block = [f"MODEL {model}", *matrix_lines(names, matrices[model])]
        block.extend(f"SATURATED {names[first]} {names[second]} sites {sites}"
                     for first, second, sites in saturated[model])
        blocks.append(block)
    blocks.append([f"PATRISTIC {main_method}", *matrix_lines(names, patristic[main_method])])
    evolution = [f"ME start {main_method} length {real(me_start, 5)}"]
    for mask, swap, value in me["moves"]:
        evolution.append(f"NNI edge {symbols(mask, len(names))} swap {swap} length {real(value, 5)}")
    evolution.append(f"ME moves {len(me['moves'])} evaluated {me['evaluated']} length {real(me['value'], 5)}")
    best = exhaustive["best_bme"]
    evolution.append(f"EXHAUSTIVE taxa {len(exhaustive['taxa'])} trees {len(exhaustive['records'])} "
                     f"best {real(best['bme'], 5)} second {real(exhaustive['second_bme'], 5)}")
    evolution.append(f"BEST {best['newick']} parsimony {best['score']}")
    blocks.append(evolution)
    lines = []
    for block in blocks:
        if lines:
            lines.append("")
        lines.extend(block)
    return lines


def score_line(method, score, minimum, maximum):
    return (f"TREE {method} score {score} ci {real(minimum / score, 4)} "
            f"ri {real((maximum - score) / (maximum - minimum), 4)}")


def parsimony_lines(names, outgroup, minimum, maximum, minima, nj_scores, initial, search,
                    ancestors, changes, exhaustive):
    lines = [f"BOUNDS minimum {minimum} maximum {maximum}"]
    for method in NJ_METHODS:
        lines.append(score_line(method, nj_scores[method], minimum, maximum))
    start_names = " ".join(names[taxon] for taxon in initial["taxa"][:3])
    lines.append(f"START {start_names} score {initial['initial']}")
    for taxon, mask, value, ties in initial["additions"]:
        lines.append(f"ADD {names[taxon]} edge {symbols(mask, len(names))} score {value} ties {ties}")
    lines.append(f"STEPWISE score {initial['score']} evaluated {initial['evaluated']}")
    for mask, swap, value in search["moves"]:
        lines.append(f"NNI edge {symbols(mask, len(names))} swap {swap} score {value}")
    lines.append(f"SEARCH moves {len(search['moves'])} evaluated {search['evaluated']} score {search['value']}")
    lines.append(score_line("MP", search["value"], minimum, maximum))
    lines.append("MP " + tree_io.newick(search["tree"], names, outgroup, lengths=True))
    histogram = Counter(changes)
    for value in range(max(changes) + 1):
        lines.append(f"CHANGES {value} columns {histogram[value]}")
    homoplasy = sum(value > lower for value, lower in zip(changes, minima))
    lines.append(f"HOMOPLASY columns {homoplasy} extra {search['value'] - minimum}")
    rooted = search["tree"].rooted(outgroup)
    ancestral_records = []
    for node, sequence in ancestors.items():
        mask = rooted.ingroup if node == rooted.root else rooted.masks[node]
        ancestral_records.append((symbols(mask, len(names)), sequence))
    lines.extend(f"ANCESTOR {symbol} {sequence}" for symbol, sequence in sorted(ancestral_records))
    lines.append("")
    lines.append(f"EXHAUSTIVE taxa {len(exhaustive['taxa'])} trees {len(exhaustive['records'])} "
                 f"best {exhaustive['best_score']} optimal {len(exhaustive['optimal'])}")
    for value, count in sorted(exhaustive["histogram"].items()):
        lines.append(f"SCORE {value} trees {count}")
    for record in exhaustive["optimal"]:
        lines.append(f"OPTIMAL {record['newick']} bme {real(record['bme'], 5)}")
    lines.append("STRICT " + tree_io.newick(exhaustive["strict"], names, outgroup))
    verdict = "yes" if exhaustive["heuristic"] == exhaustive["best_score"] else "no"
    lines.append(f"HEURISTIC score {exhaustive['heuristic']} optimal {verdict}")
    return lines


def tree_outputs(names, trees, outgroup, support):
    newicks = []
    diagrams = []
    for method in METHODS:
        tree = trees[method]
        lengths = method in NJ_METHODS or method == "MP"
        counts = support if method == "CONSENSUS" else None
        newicks.append(method + " " + tree_io.newick(tree, names, outgroup, lengths, counts))
        if diagrams:
            diagrams.append("")
        diagrams.append(f"TREE {method}")
        diagrams.extend(tree_io.cladogram(tree, names, outgroup, support))
    return newicks, diagrams


def main():
    parameters = read_parameters()
    records = alignment.read_fasta()
    accepted, rejected, length = check_records(records, parameters["max_missing_percent"])
    names = [name for name, sequence in accepted]
    sequences = [sequence for name, sequence in accepted]
    count = len(names)
    outgroup = names.index(parameters["outgroup"])
    patterns = alignment.Patterns(sequences)
    pairs = distances.all_pairs(sequences, [1] * length)
    matrices, saturated, nj_trees = {}, {}, {}
    for model, method in zip(distances.MODELS, NJ_METHODS):
        matrices[model], saturated[model] = distances.build_matrix(
            pairs, count, model, parameters["saturation_distance"]
        )
        nj_trees[method] = tree_building.neighbor_joining(matrices[model], range(count))
    main_method = "NJ_" + parameters["model"]
    main_tree = nj_trees[main_method]
    main_matrix = matrices[parameters["model"]]
    me_start = bme_length(main_tree, main_matrix)
    me = hill_climb(main_tree, lambda tree: bme_length(tree, main_matrix), outgroup, me_start)
    addition_order = [outgroup, *(taxon for taxon in range(count) if taxon != outgroup)]
    initial = stepwise(addition_order, count, patterns, outgroup)
    mp = hill_climb(initial["tree"], lambda tree: parsimony.score(tree, patterns, outgroup),
                    outgroup, initial["score"])
    ancestors, branch_changes, column_changes = parsimony.reconstruct(mp["tree"], patterns, outgroup)
    for (first, second), changes in branch_changes.items():
        mp["tree"].connect(first, second, changes / length)
    minimum, maximum, minima = parsimony_bounds(patterns)
    nj_scores = {method: parsimony.score(tree, patterns, outgroup) for method, tree in nj_trees.items()}
    exhaustive_names = set(parameters["exhaustive_taxa"])
    exhaustive_taxa = [outgroup, *(taxon for taxon, name in enumerate(names)
                                  if taxon != outgroup and name in exhaustive_names)]
    exhaustive = exhaustive_search(exhaustive_taxa, names, patterns, outgroup, main_matrix)
    site_logs = {method: likelihood_sites(tree, names, patterns, outgroup)
                 for method, tree in nj_trees.items()}
    consensus, support, bootstrap_report = bootstrap(names, sequences, parameters, main_tree,
                                                     main_matrix, outgroup)
    trees = {**nj_trees, "ME": me["tree"], "MP": mp["tree"], "CONSENSUS": consensus}
    patristic = {method: tree_building.patristic_matrix(tree) for method, tree in nj_trees.items()}
    newicks, cladograms = tree_outputs(names, trees, outgroup, support)
    outputs = {
        "summary.txt": summary_lines(records, rejected, names, sequences, patterns),
        "distances.txt": distance_lines(names, pairs, matrices, saturated, main_method, patristic,
                                         me_start, me, exhaustive, outgroup),
        "trees.nwk": newicks,
        "cladograms.txt": cladograms,
        "parsimony.txt": parsimony_lines(names, outgroup, minimum, maximum, minima, nj_scores,
                                           initial, mp, ancestors, column_changes, exhaustive),
        "likelihood.txt": likelihood_lines(names, patterns, nj_trees, outgroup, main_method,
                                             parameters["low_sites"], site_logs),
        "bootstrap.txt": bootstrap_report,
        "clock.txt": clock_lines(names, sequences, outgroup, main_method, main_tree),
        "comparison.txt": comparison_lines(names, patterns, trees, matrices, main_matrix, main_method,
                                             outgroup, support, parameters["replicates"], nj_scores,
                                             mp["value"], branch_changes, site_logs, patristic),
        "hypotheses.txt": hypothesis_lines(names, trees, outgroup, support, exhaustive),
    }
    for filename, lines in outputs.items():
        tree_io.write_lines(filename, lines)


if __name__ == "__main__":
    main()
