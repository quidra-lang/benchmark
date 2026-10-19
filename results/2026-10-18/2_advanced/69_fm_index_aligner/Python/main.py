"""Build and inspect FM indexes, map reads, and assemble five file reports."""

from bisect import bisect_right
from collections import Counter
from itertools import groupby
from pathlib import Path

from fm_index import FMIndex
from sam_writer import header, ratio, record, write_lines
from search import backtrack
from sequence_io import read_inputs, reverse_complement
from suffix_array import BASES, SYMBOLS, adjacent_check, build, direct_sort


class ReferenceText:
    def __init__(self, references):
        self.references = references
        self.offsets = []
        offset = 0
        for reference in references:
            self.offsets.append(offset)
            offset += len(reference.bases) + 1
        self.text = "#".join(reference.bases for reference in references) + "$"
        self.reverse = self.text[:-1][::-1] + "$"

    def position(self, position):
        reference = bisect_right(self.offsets, position) - 1
        offset = position - self.offsets[reference]
        if offset >= len(self.references[reference].bases):
            return None
        return reference, offset

    def label(self, position):
        located = self.position(position)
        if located is None:
            return "*"
        reference, offset = located
        return f"{self.references[reference].name}:{offset + 1}"


def runs(operations):
    return [(operation, sum(1 for _ in values)) for operation, values in groupby(operations)]


def describe(reference, position, strand, operations, core, trimmed, references):
    oriented = core if strand == "+" else reverse_complement(core)
    sequence = references[reference].bases
    cigar_parts, md_parts, pairs = [], [], []
    read_offset, reference_offset, matches, nm = 0, position, 0, 0
    for operation, count in runs(operations):
        cigar_parts.append(f"{count}{operation}")
        if operation == "I":
            read_offset += count
            nm += count
        elif operation == "D":
            deleted = sequence[reference_offset:reference_offset + count]
            md_parts.append(f"{matches}^{deleted}")
            matches = 0
            reference_offset += count
            nm += count
        else:
            for _ in range(count):
                pairs.append((read_offset, reference_offset))
                if oriented[read_offset] == sequence[reference_offset]:
                    matches += 1
                else:
                    md_parts.append(f"{matches}{sequence[reference_offset]}")
                    matches = 0
                    nm += 1
                read_offset += 1
                reference_offset += 1
    md_parts.append(str(matches))
    if trimmed:
        if strand == "+":
            cigar_parts.append(f"{trimmed}S")
        else:
            cigar_parts.insert(0, f"{trimmed}S")
    return {"reference": reference, "position": position, "strand": strand,
            "operations": operations, "oriented": oriented, "pairs": pairs,
            "cigar": "".join(cigar_parts), "nm": nm, "md": "".join(md_parts)}


def maximum_reachable(*values):
    reachable = [value for value in values if value is not None]
    return max(reachable) if reachable else None


def subtract(value, penalty):
    return None if value is None else value - penalty


def banded_alignment(oriented, sequence, center, width, scores):
    match, mismatch, gap_open, gap_extend = scores
    length, reference_length = len(oriented), len(sequence)
    h, e, f = {}, {}, {}
    for column in range(max(0, center - width), min(reference_length, center + width) + 1):
        h[0, column] = 0
    for row in range(1, length + 1):
        first = max(0, row + center - width)
        last = min(reference_length, row + center + width)
        for column in range(first, last + 1):
            cell = row, column
            f[cell] = maximum_reachable(subtract(h.get((row - 1, column)), gap_open + gap_extend),
                                        subtract(f.get((row - 1, column)), gap_extend))
            diagonal = None
            if column >= 1:
                e[cell] = maximum_reachable(subtract(h.get((row, column - 1)), gap_open + gap_extend),
                                            subtract(e.get((row, column - 1)), gap_extend))
                previous = h.get((row - 1, column - 1))
                if previous is not None:
                    diagonal = previous + (match if oriented[row - 1] == sequence[column - 1] else -mismatch)
            h[cell] = maximum_reachable(diagonal, e.get(cell), f[cell])
    endpoints = [(value, column) for (row, column), value in h.items()
                 if row == length and value is not None]
    if not endpoints:
        return None
    score, column = max(endpoints, key=lambda item: (item[0], -item[1]))
    row, state, backward = length, "H", []
    while True:
        cell = row, column
        if state == "H":
            if row == 0:
                break
            previous = h.get((row - 1, column - 1)) if column >= 1 else None
            if previous is not None:
                delta = match if oriented[row - 1] == sequence[column - 1] else -mismatch
                if h[cell] == previous + delta:
                    backward.append("M")
                    row -= 1
                    column -= 1
                    continue
            state = "I" if f.get(cell) is not None and h[cell] == f[cell] else "D"
        elif state == "I":
            backward.append("I")
            previous = f.get((row - 1, column))
            state = "I" if previous is not None and f[cell] == previous - gap_extend else "H"
            row -= 1
        else:
            backward.append("D")
            previous = e.get((row, column - 1))
            state = "D" if previous is not None and e[cell] == previous - gap_extend else "H"
            column -= 1
    return score, column, "".join(reversed(backward))


class Mapper:
    def __init__(self, reference_text, forward_index, reverse_index, params):
        self.reference_text = reference_text
        self.references = reference_text.references
        self.forward = forward_index
        self.reverse = reverse_index
        self.params = params
        self.search_counts = Counter()
        self.seed_counts = Counter()

    def value(self, name):
        return self.params[name][0]

    def locate(self, row):
        position, _ = self.forward.locate(row)
        return self.reference_text.position(position)

    def alignment(self, reference, position, strand, operations, result):
        return describe(reference, position, strand, operations, result["core"],
                        result["trimmed"], self.references)

    def map_read(self, read):
        qualities = [ord(character) - 33 for character in read.quality]
        length = len(read.bases)
        while length and qualities[length - 1] < self.value("TRIM_QUALITY"):
            length -= 1
        core = read.bases[:length]
        result = {"read": read, "core": core, "qualities": qualities,
                  "length": length, "trimmed": len(read.bases) - length,
                  "mapped": False, "reason": "SHORT"}
        if length < self.value("MIN_READ_LENGTH"):
            return result
        oriented = (core, reverse_complement(core))
        exact = [self.forward.backward_search(sequence) for sequence in oriented]
        maximum = 1 if any(lower < upper for lower, upper in exact) else self.value("MAX_MISMATCHES")
        hits = []
        for strand, sequence in enumerate(oriented):
            nodes, leaves, positions = backtrack(sequence, maximum, self.forward, self.reverse)
            self.search_counts["calls"] += 1
            self.search_counts["nodes"] += nodes
            self.search_counts["leaves"] += len(leaves)
            self.search_counts["positions"] += positions
            for lower, upper, mismatches in leaves:
                for row in range(lower, upper):
                    reference, offset = self.locate(row)
                    hits.append((mismatches, reference, offset, strand))
        if hits:
            self.finish_search(result, sorted(hits))
        else:
            self.seed_and_extend(result, oriented)
        return result

    def finish_search(self, result, hits):
        best = hits[0][0]
        best_count = sum(hit[0] == best for hit in hits)
        second_count = sum(hit[0] == best + 1 for hit in hits)
        alignments = []
        for mismatches, reference, offset, strand in hits:
            if mismatches > best + 1:
                break
            alignments.append(self.alignment(reference, offset, "+-"[strand], "M" * result["length"], result))
        if best_count >= 2:
            mapq = 0
        elif second_count == 0:
            mapq = 60 - 12 * best
        else:
            mapq = max(30 - 12 * best - 3 * second_count, 1)
        match, mismatch, _, _ = self.params["SCORES"]
        score = (result["length"] - best) * match - best * mismatch
        targets = sorted({reference for mm, reference, _, _ in hits if mm == best})
        result.update(mapped=True, primary=alignments[0], others=alignments[1:],
                      method="EXACT" if best == 0 else "MISMATCH", score=score,
                      mapq=mapq, x0=best_count, x1=second_count, targets=targets)

    def make_candidates(self, oriented):
        candidates = set()
        seed_length = self.value("SEED_LENGTH")
        for strand, sequence in enumerate(oriented):
            for offset in range(0, len(sequence) - seed_length + 1, self.value("SEED_STEP")):
                self.seed_counts["seeds"] += 1
                seed = sequence[offset:offset + seed_length]
                if "N" in seed:
                    self.seed_counts["with_n"] += 1
                    continue
                lower, upper = self.forward.backward_search(seed)
                if upper - lower > self.value("MAX_SEED_HITS"):
                    self.seed_counts["repetitive"] += 1
                elif lower >= upper:
                    self.seed_counts["without_hit"] += 1
                else:
                    for row in range(lower, upper):
                        reference, position = self.locate(row)
                        candidates.add((strand, reference, position - offset))
        self.seed_counts["candidates"] += len(candidates)
        return sorted(candidates)

    def seed_and_extend(self, result, oriented):
        result["reason"] = "NOHIT"
        if result["length"] < self.value("SEED_LENGTH"):
            return
        self.seed_counts["reads"] += 1
        accepted = {}
        scores = self.params["SCORES"]
        threshold = self.value("MIN_SCORE_PERCENT") * scores[0] * result["length"]
        for strand, reference, center in self.make_candidates(oriented):
            alignment = banded_alignment(oriented[strand], self.references[reference].bases,
                                         center, self.value("BAND_WIDTH"), scores)
            if alignment is None or 100 * alignment[0] < threshold:
                continue
            score, position, operations = alignment
            key = reference, position, strand
            if key not in accepted or score > accepted[key][0]:
                accepted[key] = score, operations
        self.seed_counts["passing"] += len(accepted)
        if not accepted:
            return
        ordered = sorted(((score, reference, position, strand, operations)
                          for (reference, position, strand), (score, operations) in accepted.items()),
                         key=lambda item: (-item[0], item[1], item[2], item[3]))
        best = ordered[0][0]
        best_count = sum(item[0] == best for item in ordered)
        second = max((item[0] for item in ordered if item[0] < best), default=0)
        alignments = [self.alignment(reference, position, "+-"[strand], operations, result)
                      for _, reference, position, strand, operations in ordered]
        targets = sorted({reference for score, reference, _, _, _ in ordered if score == best})
        result.update(mapped=True, primary=alignments[0], others=alignments[1:], method="SEED",
                      score=best, mapq=0 if best_count >= 2 else 60 * (best - second) // best,
                      x0=best_count, x1=len(ordered) - best_count, targets=targets)


def index_statistics(reference_text, suffixes, classes, forward, reverse_suffixes, reverse_classes, reverse, params):
    text, reverse_text = reference_text.text, reference_text.reverse
    references, size = reference_text.references, len(text)
    lines = [f"text length {size} sequences {len(references)}"]
    for number, reference in enumerate(references):
        length = len(reference.bases)
        gc = reference.bases.count("G") + reference.bases.count("C")
        lines.append(f"sequence {reference.name} length {length} offset {reference_text.offsets[number]} "
                     f"gc {ratio(gc, length)} masked {reference.masked}")
    frequencies = Counter(text)
    lines.append("symbols " + " ".join(f"{symbol} {frequencies[symbol]}" for symbol in SYMBOLS))
    lines.extend(["", "forward_index", f"suffix_array rounds {len(classes) - 1}"])
    for round_number, count in enumerate(classes):
        lines.append(f"round {round_number} prefix_length {1 << round_number} classes {count}")
    ordered, lcp_sum, maximum, row = adjacent_check(text, suffixes)
    lines.append(f"sa_check pairs {size - 1} ordered {ordered} lcp_sum {lcp_sum} "
                 f"mean_lcp {ratio(lcp_sum, size - 1)} max_lcp {maximum}")
    lines.append(f"longest_repeat {maximum} {reference_text.label(suffixes[row - 1])} "
                 f"{reference_text.label(suffixes[row])}")
    length = params["SEED_LENGTH"][0]
    kmers = Counter(reference.bases[position:position + length]
                    for reference in references for position in range(len(reference.bases) - length + 1))
    occurrences, unique = sum(kmers.values()), sum(count == 1 for count in kmers.values())
    lines.append(f"kmers length {length} occurrences {occurrences} distinct {len(kmers)} unique {unique} "
                 f"max_occurrence {max(kmers.values())} unique_fraction {ratio(unique, occurrences)}")
    lines.append(f"bwt runs {len(runs(forward.bwt))} head {forward.bwt[:60]}")
    lines.append("c_array " + " ".join(f"{symbol} {forward.C[symbol]}" for symbol in SYMBOLS))
    lines.append(f"occ interval {forward.interval} checkpoints {len(forward.checkpoints)}")
    lines.append(f"sa_sample interval {params['SA_SAMPLE_INTERVAL'][0]} samples {len(forward.samples)}")
    correct, total_steps, max_steps = 0, 0, 0
    for row, position in enumerate(suffixes):
        located, steps = forward.locate(row)
        correct += located == position
        total_steps += steps
        max_steps = max(max_steps, steps)
    lines.append(f"locate rows {size} correct {correct} total_steps {total_steps} max_steps {max_steps} "
                 f"mean_steps {ratio(total_steps, size)}")
    lines.append("inverse_bwt identical " + ("yes" if forward.inverse() == text else "no"))
    reverse_ordered, _, _, _ = adjacent_check(reverse_text, reverse_suffixes)
    lines.extend(["", "reverse_index", f"suffix_array rounds {len(reverse_classes) - 1}",
                  f"sa_check pairs {size - 1} ordered {reverse_ordered}",
                  f"bwt runs {len(runs(reverse.bwt))} head {reverse.bwt[:60]}",
                  "inverse_bwt identical " + ("yes" if reverse.inverse() == reverse_text else "no"),
                  "", "direct_sort"])
    cross_checks = 0
    for reference in references:
        if len(reference.bases) <= params["DIRECT_SORT_LIMIT"][0]:
            sequence = reference.bases + "$"
            doubled, counts = build(sequence)
            identical = "yes" if doubled == direct_sort(sequence) else "no"
            lines.append(f"{reference.name} length {len(sequence)} rounds {len(counts) - 1} identical {identical}")
            cross_checks += 1
    if not cross_checks:
        lines.append("none")
    occurrence_bytes = 24 * len(forward.checkpoints)
    sample_bytes = 4 * len(forward.samples)
    bitmap_bytes = (size + 7) // 8
    total_bytes = size + occurrence_bytes + sample_bytes + bitmap_bytes
    lines.extend(["", f"index_size bwt_bytes {size} occ_bytes {occurrence_bytes} sample_bytes {sample_bytes} "
                  f"bitmap_bytes {bitmap_bytes} total_bytes {total_bytes} full_bytes {5 * size} "
                  f"ratio {ratio(total_bytes, 5 * size)}"])
    return lines


def coverage_and_variants(results, references, params):
    depths = [[0] * len(reference.bases) for reference in references]
    starts = [[0] * len(reference.bases) for reference in references]
    pileups = [[[[0, 0] for _ in BASES] for _ in reference.bases] for reference in references]
    min_depth, min_quality, min_alt, hom_percent = params["VARIANTS"]
    minimum_mapq = params["COVERAGE_MIN_MAPQ"][0]
    for result in results:
        if not result["mapped"]:
            continue
        alignment = result["primary"]
        reference, position = alignment["reference"], alignment["position"]
        strand = 0 if alignment["strand"] == "+" else 1
        if result["mapq"] == 0:
            starts[reference][position] += 1
        if result["mapq"] < minimum_mapq:
            continue
        for read_offset, offset in alignment["pairs"]:
            depths[reference][offset] += 1
            base = alignment["oriented"][read_offset]
            cycle = read_offset + 1 if strand == 0 else result["length"] - read_offset
            if base != "N" and result["qualities"][cycle - 1] >= min_quality:
                pileups[reference][offset][BASES.index(base)][strand] += 1
    window = params["COVERAGE_WINDOW"][0]
    coverage = [f"window {window} min_mapq {minimum_mapq}"]
    variants = [f"min_depth {min_depth} min_base_quality {min_quality} "
                f"min_alt_percent {min_alt} hom_percent {hom_percent}"]
    callable_count, variant_count, heterozygous, homozygous = 0, 0, 0, 0
    for number, reference in enumerate(references):
        length = len(reference.bases)
        depth = depths[number]
        covered = sum(value >= 1 for value in depth)
        histogram = Counter(depth)
        coverage.append(f"reference {reference.name} length {length} covered {covered} "
                        f"breadth {ratio(covered, length)} mean_depth {ratio(sum(depth), length)} "
                        f"max_depth {max(depth)}")
        coverage.append("depth_histogram " + " ".join(f"{value}:{histogram[value]}" for value in range(max(depth) + 1)))
        for first in range(0, length, window):
            last = min(first + window, length)
            size = last - first
            values = depth[first:last]
            sequence = reference.bases[first:last]
            gc = sequence.count("G") + sequence.count("C")
            total = sum(values)
            zero = values.count(0)
            mapq_zero = sum(starts[number][first:last])
            bar = "#" * (10 * total // size)
            coverage.append(f"{reference.name} {first + 1} {last} gc {ratio(gc, size)} sum {total} "
                            f"mean {ratio(total, size)} max {max(values)} zero {zero} mapq0 {mapq_zero} |{bar}")
        for offset, strand_counts in enumerate(pileups[number]):
            counts = [sum(pair) for pair in strand_counts]
            call_depth = sum(counts)
            if call_depth < min_depth:
                continue
            callable_count += 1
            reference_base = reference.bases[offset]
            alternative = max((base for base in range(4) if BASES[base] != reference_base),
                              key=lambda base: (counts[base], -base))
            alternative_count = counts[alternative]
            if alternative_count < 2 or 100 * alternative_count < min_alt * call_depth:
                continue
            is_homozygous = 100 * alternative_count >= hom_percent * call_depth
            genotype = "1/1" if is_homozygous else "0/1"
            homozygous += is_homozygous
            heterozygous += not is_homozygous
            variant_count += 1
            plus, minus = strand_counts[alternative]
            counts_text = " ".join(map(str, counts))
            variants.append(f"{reference.name} {offset + 1} {reference_base}>{BASES[alternative]} "
                            f"depth {call_depth} alt {alternative_count} fraction {ratio(alternative_count, call_depth)} "
                            f"genotype {genotype} strands {plus} {minus} counts {counts_text}")
    variants.append(f"callable {callable_count} variants {variant_count} "
                    f"heterozygous {heterozygous} homozygous {homozygous}")
    return coverage, variants


def error_statistics(results, references):
    maximum_cycle = max(len(result["read"].bases) for result in results)
    cycles = [[0, 0] for _ in range(maximum_cycle + 1)]
    substitutions = [[0] * 5 for _ in BASES]
    quality_counts, quality_sums = [0, 0], [0, 0]
    quality_bins = [[0, 0] for _ in range(5)]
    operation_counts, events, indel_bases = Counter(), Counter(), Counter()
    for result in results:
        if not result["mapped"]:
            continue
        alignment = result["primary"]
        operation_counts.update(alignment["operations"])
        operation_counts["S"] += result["trimmed"]
        if result["x0"] != 1:
            continue
        sequence = references[alignment["reference"]].bases
        for read_offset, offset in alignment["pairs"]:
            observed = alignment["oriented"][read_offset]
            reference = sequence[offset]
            mismatch = int(observed != reference)
            cycle = read_offset + 1 if alignment["strand"] == "+" else result["length"] - read_offset
            quality = result["qualities"][cycle - 1]
            cycles[cycle][0] += 1
            cycles[cycle][1] += mismatch
            substitutions[BASES.index(reference)]["ACGTN".index(observed)] += 1
            quality_counts[mismatch] += 1
            quality_sums[mismatch] += quality
            quality_bin = min(quality // 10, 4)
            quality_bins[quality_bin][0] += 1
            quality_bins[quality_bin][1] += mismatch
        for operation, count in runs(alignment["operations"]):
            if operation in "ID":
                events[operation] += 1
                indel_bases[operation] += count
    aligned = sum(quality_counts)
    mismatches = quality_counts[1]
    lines = [f"error_profile aligned_bases {aligned} mismatches {mismatches} rate {ratio(mismatches, aligned)}",
             "substitutions", "ref A C G T N"]
    for reference, counts in zip(BASES, substitutions):
        lines.append(reference + " " + " ".join(map(str, counts)))
    lines.append("mismatch_by_cycle")
    for cycle in range(1, maximum_cycle + 1):
        count, errors = cycles[cycle]
        lines.append(f"cycle {cycle} aligned {count} mismatches {errors} rate {ratio(errors, count)}")
    lines.append(f"quality matched {quality_counts[0]} mean {ratio(quality_sums[0], quality_counts[0])} "
                 f"mismatched {quality_counts[1]} mean {ratio(quality_sums[1], quality_counts[1])}")
    lines.append("quality_bins")
    for name, (count, errors) in zip(("0-9", "10-19", "20-29", "30-39", "40-"), quality_bins):
        lines.append(f"{name} aligned {count} mismatches {errors} rate {ratio(errors, count)}")
    lines.append("cigar " + " ".join(f"{operation} {operation_counts[operation]}" for operation in "MIDS"))
    lines.append(f"indels insertions {events['I']} {indel_bases['I']} deletions {events['D']} {indel_bases['D']}")
    return lines


def mapping_statistics(results, references, search_counts, seed_counts):
    total = len(results)
    mapped = [result for result in results if result["mapped"]]
    unique = sum(result["x0"] == 1 for result in mapped)
    reasons = Counter(result["reason"] for result in results if not result["mapped"])
    methods = Counter(result["method"] for result in mapped)
    strands = Counter(result["primary"]["strand"] for result in mapped)
    trimmed = sum(result["trimmed"] > 0 for result in results)
    trimmed_bases = sum(result["trimmed"] for result in results)
    lines = [f"reads total {total} trimmed {trimmed} trimmed_bases {trimmed_bases} short {reasons['SHORT']}",
             f"mapped {len(mapped)} rate {ratio(len(mapped), total)} unique {unique} "
             f"multi {len(mapped) - unique} unmapped {total - len(mapped)}",
             f"unmapped short {reasons['SHORT']} nohit {reasons['NOHIT']}",
             f"method exact {methods['EXACT']} mismatch {methods['MISMATCH']} seed {methods['SEED']}",
             f"strand forward {strands['+']} reverse {strands['-']}"]
    for number, reference in enumerate(references):
        on_reference = [result for result in mapped if result["primary"]["reference"] == number]
        unique_count = sum(result["x0"] == 1 for result in on_reference)
        forward = sum(result["primary"]["strand"] == "+" for result in on_reference)
        lines.append(f"reference {reference.name} mapped {len(on_reference)} unique {unique_count} "
                     f"forward {forward} reverse {len(on_reference) - forward}")
    lines.append("length_bins")
    minimum = min(result["length"] for result in results) // 10 * 10
    maximum = max(result["length"] for result in results) // 10 * 10
    for lower in range(minimum, maximum + 1, 10):
        in_bin = [result for result in results if lower <= result["length"] <= lower + 9]
        mapped_bin = [result for result in in_bin if result["mapped"]]
        unique_bin = sum(result["x0"] == 1 for result in mapped_bin)
        lines.append(f"{lower}-{lower + 9} reads {len(in_bin)} mapped {len(mapped_bin)} unique {unique_bin}")
    with_n = [result for result in results if "N" in result["read"].bases]
    n_bases = sum(result["read"].bases.count("N") for result in with_n)
    n_mapped = sum(result["mapped"] for result in with_n)
    lines.append(f"n_reads {len(with_n)} n_bases {n_bases} mapped {n_mapped}")
    target_counts = Counter()
    for result in mapped:
        if result["x0"] >= 2:
            names = "+".join(references[reference].name for reference in result["targets"])
            target_counts[names] += 1
    lines.append("multi_targets")
    if target_counts:
        lines.extend(f"{names} {target_counts[names]}" for names in sorted(target_counts))
    else:
        lines.append("none")
    mapq_counts = Counter(result["mapq"] for result in mapped)
    nm_counts = Counter(result["primary"]["nm"] for result in mapped)
    lines.append("mapq_histogram")
    lines.extend(f"{value} {mapq_counts[value]}" for value in sorted(mapq_counts, reverse=True))
    lines.append("nm_histogram")
    lines.extend(f"{value} {nm_counts[value]}" for value in sorted(nm_counts))
    lines.extend(error_statistics(results, references))
    lines.append(f"search dfs_calls {search_counts['calls']} dfs_nodes {search_counts['nodes']} "
                 f"dfs_leaves {search_counts['leaves']} dfs_positions {search_counts['positions']}")
    lines.append("seeds " + " ".join(f"{name} {seed_counts[name]}" for name in
                 ("reads", "seeds", "with_n", "repetitive", "without_hit", "candidates", "passing")))
    return lines


def main():
    references, reads, params = read_inputs()
    reference_text = ReferenceText(references)
    suffixes, classes = build(reference_text.text)
    reverse_suffixes, reverse_classes = build(reference_text.reverse)
    interval = params["OCC_INTERVAL"][0]
    forward = FMIndex(reference_text.text, suffixes, interval, params["SA_SAMPLE_INTERVAL"][0])
    reverse = FMIndex(reference_text.reverse, reverse_suffixes, interval)
    index_lines = index_statistics(reference_text, suffixes, classes, forward,
                                   reverse_suffixes, reverse_classes, reverse, params)
    mapper = Mapper(reference_text, forward, reverse, params)
    results = [mapper.map_read(read) for read in reads]
    sam_lines = header(references)
    sam_lines.extend(record(result, references, params["MAX_ALT_HITS"][0]) for result in results)
    coverage_lines, variant_lines = coverage_and_variants(results, references, params)
    summary_lines = mapping_statistics(results, references, mapper.search_counts, mapper.seed_counts)
    output = Path("output")
    output.mkdir(exist_ok=True)
    write_lines(output / "alignments.sam", sam_lines)
    write_lines(output / "coverage.txt", coverage_lines)
    write_lines(output / "variants.txt", variant_lines)
    write_lines(output / "index_stats.txt", index_lines)
    write_lines(output / "summary.txt", summary_lines)


if __name__ == "__main__":
    main()
