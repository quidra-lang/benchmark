import math
import os

from agglomerative import agglomerate, minimum_spanning_tree
from dataset import read_observations, read_settings, write_lines
from dendrogram import column, dendrogram_rows, leaf_order, ordered_children
from distances import (
    DISTANCE_TYPES, distance_matrix, feature_statistics, sequential_sum, squared_distance,
    standardize,
)
from validation import adjusted_rand_index, contingency_table, correlation, silhouette_values


INPUT_DIRECTORY = "input"
OUTPUT_DIRECTORY = "output"
HISTOGRAM_BINS = 10
HISTOGRAM_BAR = 50
PROFILE_BAR = 10
PROFILE_SCALE = 4
HEIGHT_TOLERANCE = 0.000000001
SHADES = "@%#*+=-:. "
MINSTD_MULTIPLIER = 48271
MINSTD_MODULUS = 2147483647


def real(value):
    if value is None:
        return "-"
    text = f"{value:.4f}"
    return "0.0000" if text == "-0.0000" else text


def reals(values):
    return " ".join(real(value) for value in values)


def integers(values):
    return " ".join(str(value) for value in values)


def four_digit(value):
    return round(value, 4)


def ari_value(ari):
    numerator, denominator = ari
    return numerator / denominator


def ari_text(ari):
    numerator, denominator = ari
    return f"{numerator}/{denominator} {real(numerator / denominator)}"


def ari_greater(first, second):
    return first[0] * second[1] > second[0] * first[1]


def pair_values(matrix):
    count = len(matrix)
    return [matrix[i][j] for i in range(count) for j in range(i + 1, count)]


def histogram_bin(value, maximum):
    return min(HISTOGRAM_BINS - 1, math.floor(HISTOGRAM_BINS * value / maximum))


def centroid(vectors):
    size = len(vectors)
    return [sequential_sum(vector[f] for vector in vectors) / size for f in range(len(vectors[0]))]


def cluster_members(partition, groups):
    members = [[] for _ in range(groups)]
    for i, number in enumerate(partition):
        members[number - 1].append(i)
    return members


def majority_class(row):
    best = 0
    for t in range(1, len(row)):
        if row[t] > row[best]:
            best = t
    return best


def connected_components(count, edges):
    component = list(range(count))
    for edge in edges:
        old = component[edge.child]
        new = component[edge.parent]
        for u in range(count):
            if component[u] == old:
                component[u] = new
    return component


def join_parts(parts):
    lines = []
    for part in parts:
        if lines:
            lines.append("")
        lines.extend(part)
    return lines


class Minstd:
    def __init__(self, seed):
        self.state = seed

    def draw(self):
        self.state = MINSTD_MULTIPLIER * self.state % MINSTD_MODULUS
        return self.state


class Tree:
    def __init__(self, merges, count):
        self.merges = merges
        self.count = count
        self.heights = [merge.height for merge in merges]
        self.children = ordered_children(merges, count)
        self.order = leaf_order(self.children, count)
        self.members = [[u] for u in range(count)]
        self.depths = [0] * count
        self.subtree_heights = []
        for merge in merges:
            self.members.append(self.members[merge.a] + self.members[merge.b])
            self.depths.append(1 + max(self.depths[merge.a], self.depths[merge.b]))
            self.subtree_heights.append(
                max(merge.height, self.subtree_height(merge.a), self.subtree_height(merge.b))
            )

    def root(self):
        return 2 * self.count - 2

    def height_of(self, node):
        return 0.0 if node < self.count else self.heights[node - self.count]

    def subtree_height(self, node):
        return 0.0 if node < self.count else self.subtree_heights[node - self.count]

    def partition(self, selected):
        owner = list(range(self.count))
        for step, chosen in enumerate(selected):
            if chosen:
                node = self.count + step
                for u in self.members[node]:
                    owner[u] = node
        numbers = [0] * (2 * self.count - 1)
        groups = 0
        for u in self.order:
            if numbers[owner[u]] == 0:
                groups += 1
                numbers[owner[u]] = groups
        return [numbers[owner[u]] for u in range(self.count)]

    def cut_at_height(self, height):
        return self.partition([value <= height for value in self.subtree_heights])

    def cut_into(self, k):
        return self.partition([step < self.count - k for step in range(len(self.merges))])

    def cophenetic(self):
        matrix = [[0.0] * self.count for _ in range(self.count)]
        for merge in self.merges:
            for i in self.members[merge.a]:
                for j in self.members[merge.b]:
                    matrix[i][j] = merge.height
                    matrix[j][i] = merge.height
        return matrix

    def joining_heights(self):
        heights = [0.0] * self.count
        for merge in self.merges:
            for child in (merge.a, merge.b):
                if child < self.count:
                    heights[child] = merge.height
        return heights

    def height_sequence(self, step, depth):
        if depth == 0:
            return []
        merge = self.merges[step]
        sequence = [merge.height]
        for child in (merge.a, merge.b):
            if child >= self.count:
                sequence.extend(self.height_sequence(child - self.count, depth - 1))
        return sequence

    def newick(self, node, idents):
        if node < self.count:
            return idents[node]
        upper, lower = self.children[node - self.count]
        height = self.heights[node - self.count]
        branches = [
            self.newick(child, idents) + ":" + real(height - self.height_of(child))
            for child in (upper, lower)
        ]
        return "(" + ",".join(branches) + ")"


class Evaluation:
    def __init__(self, partition, sizes, silhouette, dunn, wss, ch, ari):
        self.partition = partition
        self.sizes = sizes
        self.silhouette = silhouette
        self.dunn = dunn
        self.wss = wss
        self.ch = ch
        self.ari = ari

    def text(self):
        return (
            f"sizes {integers(self.sizes)} silhouette {real(self.silhouette)} "
            f"dunn {real(self.dunn)} wss {real(self.wss)} ch {real(self.ch)} "
            f"ari {ari_text(self.ari)}"
        )


class LinkageResult:
    def __init__(
        self, method, tree, cophenetic, correlation, height_cuts, count_cuts, label_partition
    ):
        self.method = method
        self.tree = tree
        self.cophenetic = cophenetic
        self.correlation = correlation
        self.height_cuts = height_cuts
        self.count_cuts = count_cuts
        self.label_partition = label_partition


class Study:
    def __init__(self, feature_names, observations, settings):
        self.feature_names = feature_names
        self.settings = settings
        self.count = len(observations)
        self.idents = [observation.ident for observation in observations]
        self.labels = [observation.label for observation in observations]
        self.classes = sorted(set(self.labels))
        self.targets = [self.classes.index(label) for label in self.labels]
        self.raw = [observation.values for observation in observations]
        self.means, self.deviations = feature_statistics(self.raw)
        if settings.standardize == "yes":
            self.vectors = standardize(self.raw, self.means, self.deviations)
        else:
            self.vectors = self.raw
        self.distances = distance_matrix(self.vectors, settings.distance)
        self.distance_pairs = pair_values(self.distances)
        self.distance_max = max(self.distance_pairs)
        self.neighbors = [self.nearest_neighbor(i) for i in range(self.count)]
        self.results = [self.analyse_linkage(method) for method in settings.linkages]
        self.chosen, position = self.select()
        self.kappa = settings.cut_counts[position]
        self.selected_cut = self.chosen.count_cuts[position]
        self.selected = self.selected_cut.partition
        self.members = cluster_members(self.selected, self.kappa)
        self.silhouettes = silhouette_values(self.selected, self.kappa, self.distances)
        self.table = self.class_table(self.selected)
        self.majority = [majority_class(row) for row in self.table]

    def nearest_neighbor(self, i):
        best = -1
        for j in range(self.count):
            if j != i and (best < 0 or self.distances[i][j] < self.distances[i][best]):
                best = j
        return best

    def class_table(self, partition):
        return contingency_table(
            [number - 1 for number in partition], self.targets, max(partition), len(self.classes)
        )

    def label_ari(self, partition):
        return adjusted_rand_index(self.class_table(partition))

    def match_count(self, partition):
        return sum(max(row) for row in self.class_table(partition))

    def mean_silhouette(self, partition, delta):
        groups = max(partition)
        if groups < 2:
            return None
        return sequential_sum(silhouette_values(partition, groups, delta)) / len(partition)

    def centroids(self, partition):
        members = cluster_members(partition, max(partition))
        return [centroid([self.vectors[i] for i in group]) for group in members]

    def within_sum(self, partition):
        centers = self.centroids(partition)
        return sequential_sum(
            squared_distance(self.vectors[i], centers[number - 1])
            for i, number in enumerate(partition)
        )

    def dunn_index(self, partition, groups):
        diameter = 0.0
        separation = None
        for i in range(self.count):
            for j in range(i + 1, self.count):
                value = self.distances[i][j]
                if partition[i] == partition[j]:
                    diameter = max(diameter, value)
                elif separation is None or value < separation:
                    separation = value
        if groups >= 2 and diameter > 0:
            return separation / diameter
        return None

    def evaluate(self, partition):
        groups = max(partition)
        members = cluster_members(partition, groups)
        sizes = [len(group) for group in members]
        wss = self.within_sum(partition)
        ch = None
        if 2 <= groups < self.count:
            overall = centroid(self.vectors)
            centers = self.centroids(partition)
            bss = sequential_sum(
                size * squared_distance(center, overall) for size, center in zip(sizes, centers)
            )
            ch = (bss / (groups - 1)) / (wss / (self.count - groups))
        return Evaluation(
            partition, sizes, self.mean_silhouette(partition, self.distances),
            self.dunn_index(partition, groups), wss, ch, self.label_ari(partition),
        )

    def analyse_linkage(self, method):
        tree = Tree(agglomerate(self.distances, method), self.count)
        cophenetic = pair_values(tree.cophenetic())
        height_cuts = [
            self.evaluate(tree.cut_at_height(height)) for height in self.settings.cut_heights
        ]
        count_cuts = [self.evaluate(tree.cut_into(k)) for k in self.settings.cut_counts]
        return LinkageResult(
            method, tree, cophenetic, correlation(self.distance_pairs, cophenetic),
            height_cuts, count_cuts, tree.cut_into(len(self.classes)),
        )

    def select(self):
        chosen = self.results[0]
        position = 0
        for result in self.results:
            for index in range(len(self.settings.cut_counts)):
                if ari_greater(result.count_cuts[index].ari, chosen.count_cuts[position].ari):
                    chosen = result
                    position = index
        return chosen, position

    def linkage_table(self):
        lines = ["method,step,a,b,height,size"]
        for result in self.results:
            for step, merge in enumerate(result.tree.merges, 1):
                lines.append(
                    f"{result.method},{step},{merge.a},{merge.b},{real(merge.height)},{merge.size}"
                )
        return lines

    def clusters_table(self):
        header = ["id", "label"]
        for result in self.results:
            for j in range(1, len(self.settings.cut_heights) + 1):
                header.append(f"{result.method}_h{j}")
            for k in self.settings.cut_counts:
                header.append(f"{result.method}_k{k}")
        lines = [",".join(header)]
        for i in range(self.count):
            fields = [self.idents[i], self.labels[i]]
            for result in self.results:
                for cut in result.height_cuts + result.count_cuts:
                    fields.append(str(cut.partition[i]))
            lines.append(",".join(fields))
        return lines

    def dendrogram_report(self):
        width = self.settings.width
        blocks = []
        for result in self.results:
            tree = result.tree
            height_max = max(tree.heights)
            cut_columns = [column(height, height_max, width) for height in self.settings.cut_heights]
            lines = [f"dendrogram {result.method} height_max {real(height_max)} width {width}"]
            lines.extend(dendrogram_rows(
                tree.merges, tree.children, tree.order, self.idents, self.labels,
                height_max, cut_columns, width,
            ))
            for height, x in zip(self.settings.cut_heights, cut_columns):
                lines.append(f"cut {real(height)} column {x if x <= width else '-'}")
            blocks.append(lines)
        return join_parts(blocks)

    def trees_report(self):
        return [
            f"{result.method} {result.tree.newick(result.tree.root(), self.idents)};"
            for result in self.results
        ]

    def pair_text(self, pair):
        i, j = pair
        return f"{real(self.distances[i][j])} {self.idents[i]} {self.idents[j]}"

    def data_part(self):
        settings = self.settings
        n = self.count
        lines = [
            f"data n {n} features {len(self.feature_names)} classes {len(self.classes)} "
            f"distance {settings.distance} standardize {settings.standardize}"
        ]
        for name, mean, deviation in zip(self.feature_names, self.means, self.deviations):
            lines.append(f"feature {name} mean {real(mean)} sd {real(deviation)}")
        smallest = (0, 1)
        largest = (0, 1)
        for i in range(n):
            for j in range(i + 1, n):
                if self.distances[i][j] < self.distances[smallest[0]][smallest[1]]:
                    smallest = (i, j)
                if self.distances[i][j] > self.distances[largest[0]][largest[1]]:
                    largest = (i, j)
        pairs = len(self.distance_pairs)
        lines.append(
            f"distances pairs {pairs} min {self.pair_text(smallest)} "
            f"max {self.pair_text(largest)} mean {real(sequential_sum(self.distance_pairs) / pairs)}"
        )
        nearest_mean = sequential_sum(self.distances[i][self.neighbors[i]] for i in range(n)) / n
        reciprocal = 0
        for i in range(n):
            if i < self.neighbors[i] and self.neighbors[self.neighbors[i]] == i:
                reciprocal += 1
        lines.append(f"nearest_neighbors mean {real(nearest_mean)} reciprocal_pairs {reciprocal}")
        label_partition = [target + 1 for target in self.targets]
        lines.append("labels " + self.evaluate(label_partition).text())
        return lines

    def correlation_part(self):
        columns = [[row[f] for row in self.raw] for f in range(len(self.feature_names))]
        lines = ["correlation " + " ".join(self.feature_names)]
        for name, first in zip(self.feature_names, columns):
            lines.append(name + " " + reals(correlation(first, second) for second in columns))
        return lines

    def histogram_part(self):
        counts = [0] * HISTOGRAM_BINS
        for value in self.distance_pairs:
            counts[histogram_bin(value, self.distance_max)] += 1
        highest = max(counts)
        lines = ["histogram"]
        for b, count in enumerate(counts):
            lower = b * self.distance_max / HISTOGRAM_BINS
            upper = (b + 1) * self.distance_max / HISTOGRAM_BINS
            line = f"{real(lower)} {real(upper)} {count}"
            length = count * HISTOGRAM_BAR // highest
            if length > 0:
                line += " " + "#" * length
            lines.append(line)
        return lines

    def gaps(self, tree):
        ordered = sorted(tree.subtree_heights)
        n = self.count
        return [ordered[n - k] - ordered[n - k - 1] for k in range(2, self.settings.gap_max_k + 1)]

    def inconsistency_line(self, tree, step):
        sequence = tree.height_sequence(step, self.settings.inconsistency_depth)
        size = len(sequence)
        mean = sequential_sum(sequence) / size
        deviation = 0.0
        coefficient = 0.0
        if size >= 2:
            deviation = math.sqrt(
                sequential_sum((value - mean) * (value - mean) for value in sequence) / (size - 1)
            )
            coefficient = (tree.heights[step] - mean) / deviation
        return (
            f"step {step + 1} height {real(tree.heights[step])} mean {real(mean)} "
            f"sd {real(deviation)} count {size} coefficient {real(coefficient)}"
        )

    def linkage_part(self, result):
        settings = self.settings
        tree = result.tree
        heights = tree.heights
        n = self.count
        leaf_path = sequential_sum(
            self.distances[tree.order[r]][tree.order[r + 1]] for r in range(n - 1)
        )
        inversions = [step for step in range(1, n - 1) if heights[step] < heights[step - 1]]
        lines = [
            f"linkage {result.method}",
            f"cophenetic {real(result.correlation)} leaf_path {real(leaf_path)}",
            f"heights min {real(min(heights))} max {real(max(heights))} inversions {len(inversions)}",
        ]
        for step in inversions:
            lines.append(
                f"inversion step {step + 1} height {real(heights[step])} "
                f"previous {real(heights[step - 1])}"
            )
        gaps = self.gaps(tree)
        suggested = 2
        for k in range(3, settings.gap_max_k + 1):
            if four_digit(gaps[k - 2]) > four_digit(gaps[suggested - 2]):
                suggested = k
        lines.append("gaps " + reals(gaps))
        lines.append(f"suggested_k {suggested}")
        joining = tree.joining_heights()
        late = sorted(range(n), key=lambda i: (-joining[i], i))[:settings.list_size]
        lines.append("late_joiners " + " ".join(f"{self.idents[i]}:{real(joining[i])}" for i in late))
        kinds = [0, 0, 0]
        for merge in tree.merges:
            leaves = 0
            for child in (merge.a, merge.b):
                if child < n:
                    leaves += 1
            kinds[2 - leaves] += 1
        lines.append(
            f"merges leaf_leaf {kinds[0]} leaf_cluster {kinds[1]} cluster_cluster {kinds[2]} "
            f"depth {tree.depths[tree.root()]}"
        )
        matches = self.match_count(result.label_partition)
        lines.append(f"label_cut k {len(self.classes)} purity {matches}/{n} {real(matches / n)}")
        lines.append(f"inconsistency depth {settings.inconsistency_depth}")
        for step in range(n - settings.inconsistency_count - 1, n - 1):
            lines.append(self.inconsistency_line(tree, step))
        for height, cut in zip(settings.cut_heights, result.height_cuts):
            lines.append(f"cut height {real(height)} clusters {len(cut.sizes)} {cut.text()}")
        for k, cut in zip(settings.cut_counts, result.count_cuts):
            lines.append(f"cut k {k} {cut.text()}")
        return lines

    def result_of(self, method):
        for result in self.results:
            if result.method == method:
                return result
        return None

    def mst_part(self):
        single = self.result_of("single")
        n = self.count
        edges = minimum_spanning_tree(self.distances)
        total = sequential_sum(edge.weight for edge in edges)
        weights = sorted(edge.weight for edge in edges)
        heights_match = all(
            abs(weight - height) <= HEIGHT_TOLERANCE
            for weight, height in zip(weights, single.tree.heights)
        )
        linked = [[False] * n for _ in range(n)]
        for edge in edges:
            linked[edge.parent][edge.child] = True
            linked[edge.child][edge.parent] = True
        nn_edges = 0
        for i in range(n):
            if linked[i][self.neighbors[i]]:
                nn_edges += 1
        lines = [
            f"mst total {real(total)} heights {'match' if heights_match else 'mismatch'} "
            f"nn_edges {nn_edges}/{n}"
        ]
        numbers = sorted(range(len(edges)), key=lambda number: (edges[number].weight, number))
        ordered = [edges[number] for number in numbers]
        for k, cut in zip(self.settings.cut_counts, single.count_cuts):
            component = connected_components(n, ordered[:n - k])
            agrees = True
            for i in range(n):
                for j in range(i + 1, n):
                    same_component = component[i] == component[j]
                    same_cluster = cut.partition[i] == cut.partition[j]
                    if same_component != same_cluster:
                        agrees = False
            lines.append(f"mst partition k {k} {'match' if agrees else 'mismatch'}")
        return lines

    def compare_part(self):
        method = self.settings.compare_linkage
        label_count = len(self.classes)
        lines = [f"compare linkage {method} k {label_count}"]
        for kind in DISTANCE_TYPES:
            delta = distance_matrix(self.vectors, kind)
            tree = Tree(agglomerate(delta, method), self.count)
            cophenetic = correlation(pair_values(delta), pair_values(tree.cophenetic()))
            partition = tree.cut_into(label_count)
            lines.append(
                f"metric {kind} cophenetic {real(cophenetic)} "
                f"silhouette {real(self.mean_silhouette(partition, delta))} "
                f"ari {ari_text(self.label_ari(partition))}"
            )
        return lines

    def cophenetic_part(self):
        lines = ["cophenetic_matrix", "linkage " + " ".join(r.method for r in self.results)]
        for first in self.results:
            values = [correlation(first.cophenetic, second.cophenetic) for second in self.results]
            lines.append(first.method + " " + reals(values))
        return lines

    def agreement_part(self):
        lines = [
            f"agreement k {len(self.classes)}",
            "linkage " + " ".join(r.method for r in self.results),
        ]
        for first in self.results:
            values = [
                ari_value(self.partition_ari(first.label_partition, second.label_partition))
                for second in self.results
            ]
            lines.append(first.method + " " + reals(values))
        return lines

    def partition_ari(self, first, second):
        table = contingency_table(
            [number - 1 for number in first], [number - 1 for number in second],
            max(first), max(second),
        )
        return adjusted_rand_index(table)

    def summary_part(self):
        settings = self.settings
        ranking = sorted(
            range(len(self.results)),
            key=lambda index: (-four_digit(self.results[index].correlation), index),
        )
        lines = [
            "summary",
            "cophenetic_ranking " + " ".join(self.results[index].method for index in ranking),
        ]
        for position, k in enumerate(settings.cut_counts):
            best = self.results[0]
            for result in self.results[1:]:
                if ari_greater(result.count_cuts[position].ari, best.count_cuts[position].ari):
                    best = result
            lines.append(f"best_ari k {k} {best.method} {ari_text(best.count_cuts[position].ari)}")
        for result in self.results:
            best = 0
            for position in range(1, len(settings.cut_counts)):
                candidate = four_digit(result.count_cuts[position].silhouette)
                if candidate > four_digit(result.count_cuts[best].silhouette):
                    best = position
            lines.append(
                f"best_silhouette {result.method} k {settings.cut_counts[best]} "
                f"{real(result.count_cuts[best].silhouette)}"
            )
        lines.append(f"selected {self.chosen.method} k {self.kappa}")
        return lines

    def validation_report(self):
        parts = [self.data_part(), self.correlation_part(), self.histogram_part()]
        for result in self.results:
            parts.append(self.linkage_part(result))
        if self.result_of("single") is not None:
            parts.append(self.mst_part())
        parts.append(self.compare_part())
        parts.append(self.cophenetic_part())
        parts.append(self.agreement_part())
        parts.append(self.summary_part())
        return join_parts(parts)

    def separation(self, first, second):
        best = None
        for i in first:
            for j in second:
                if best is None or self.distances[i][j] < best:
                    best = self.distances[i][j]
        return best

    def cluster_lines(self, g):
        group = self.members[g]
        size = len(group)
        silhouette = sequential_sum(self.silhouettes[i] for i in group) / size
        majority = self.majority[g]
        majority_count = self.table[g][majority]
        means = [
            sequential_sum(self.raw[i][f] for i in group) / size
            for f in range(len(self.feature_names))
        ]
        medoid = -1
        medoid_sum = 0.0
        for i in group:
            total = sequential_sum(self.distances[i][j] for j in group)
            if medoid < 0 or total < medoid_sum:
                medoid = i
                medoid_sum = total
        diameter = "0.0000 - -"
        widest = None
        for position, i in enumerate(group):
            for j in group[position + 1:]:
                if widest is None or self.distances[i][j] > self.distances[widest[0]][widest[1]]:
                    widest = (i, j)
        if widest is not None:
            diameter = self.pair_text(widest)
        nearest = -1
        nearest_separation = 0.0
        for h in range(self.kappa):
            if h != g:
                separation = self.separation(group, self.members[h])
                if nearest < 0 or separation < nearest_separation:
                    nearest = h
                    nearest_separation = separation
        return [
            f"cluster {g + 1} size {size} silhouette {real(silhouette)} "
            f"majority {self.classes[majority]} purity {majority_count}/{size} "
            f"{real(majority_count / size)}",
            "  mean " + reals(means),
            f"  medoid {self.idents[medoid]} diameter {diameter} nearest {nearest + 1} "
            f"separation {real(nearest_separation)}",
        ]

    def selection_part(self):
        lines = [
            f"selected linkage {self.chosen.method} k {self.kappa} "
            f"ari {ari_text(self.selected_cut.ari)} silhouette {real(self.selected_cut.silhouette)}"
        ]
        for g in range(self.kappa):
            lines.extend(self.cluster_lines(g))
        return lines

    def centroid_part(self):
        centers = self.centroids(self.selected)
        lines = ["centroid_distances"]
        for g, first in enumerate(centers):
            values = [math.sqrt(squared_distance(first, second)) for second in centers]
            lines.append(f"{g + 1} " + reals(values))
        return lines

    def profile_part(self):
        name_width = max(len(name) for name in self.feature_names)
        lines = ["profile_bars"]
        for g, group in enumerate(self.members):
            lines.append(f"cluster {g + 1}")
            for f, name in enumerate(self.feature_names):
                zeta = sequential_sum(
                    (self.raw[i][f] - self.means[f]) / self.deviations[f] for i in group
                ) / len(group)
                bar = "#" * min(PROFILE_BAR, math.floor(abs(zeta) * PROFILE_SCALE))
                if zeta < 0:
                    left = bar.rjust(PROFILE_BAR)
                    right = " " * PROFILE_BAR
                else:
                    left = " " * PROFILE_BAR
                    right = bar.ljust(PROFILE_BAR)
                lines.append(f"{name:<{name_width}} {left}|{right} {real(zeta)}")
        return lines

    def contingency_part(self):
        n = self.count
        lines = ["contingency", "cluster " + " ".join(self.classes) + " total"]
        for g, row in enumerate(self.table):
            lines.append(f"{g + 1} {integers(row)} {sum(row)}")
        totals = [sum(row[t] for row in self.table) for t in range(len(self.classes))]
        lines.append(f"total {integers(totals)} {n}")
        matches = self.match_count(self.selected)
        lines.append(f"purity {matches}/{n} {real(matches / n)}")
        return lines

    def misplaced_part(self):
        lines = ["misplaced"]
        count = 0
        for i, number in enumerate(self.selected):
            majority = self.majority[number - 1]
            if self.targets[i] != majority:
                count += 1
                lines.append(
                    f"{self.idents[i]} label {self.labels[i]} cluster {number} "
                    f"majority {self.classes[majority]}"
                )
        lines.append(f"count {count}")
        return lines

    def weakest_part(self):
        ordered = sorted(range(self.count), key=lambda i: (self.silhouettes[i], i))
        lines = ["weakest"]
        for i in ordered[:self.settings.list_size]:
            lines.append(
                f"{self.idents[i]} label {self.labels[i]} cluster {self.selected[i]} "
                f"silhouette {real(self.silhouettes[i])}"
            )
        return lines

    def feature_part(self):
        n = self.count
        kappa = self.kappa
        ratios = []
        for f in range(len(self.feature_names)):
            values = [vector[f] for vector in self.vectors]
            overall = sequential_sum(values) / n
            cluster_means = [
                sequential_sum(values[i] for i in group) / len(group) for group in self.members
            ]
            between = sequential_sum(
                len(group) * (mean - overall) * (mean - overall)
                for group, mean in zip(self.members, cluster_means)
            )
            within = sequential_sum(
                (values[i] - cluster_means[number - 1]) * (values[i] - cluster_means[number - 1])
                for i, number in enumerate(self.selected)
            )
            ratios.append((between / (kappa - 1)) / (within / (n - kappa)))
        ranking = sorted(range(len(ratios)), key=lambda f: (-four_digit(ratios[f]), f))
        lines = ["features"]
        for rank, f in enumerate(ranking, 1):
            lines.append(f"{rank} {self.feature_names[f]} f_ratio {real(ratios[f])}")
        return lines

    def class_counts(self, tree, node):
        counts = [0] * len(self.classes)
        for i in tree.members[node]:
            counts[self.targets[i]] += 1
        return "/".join(str(count) for count in counts)

    def top_merges_part(self):
        tree = self.chosen.tree
        n = self.count
        lines = ["top_merges"]
        for step in range(n - self.settings.inconsistency_count - 1, n - 1):
            merge = tree.merges[step]
            lines.append(
                f"step {step + 1} height {real(merge.height)} "
                f"a {merge.a} {len(tree.members[merge.a])} {self.class_counts(tree, merge.a)} "
                f"b {merge.b} {len(tree.members[merge.b])} {self.class_counts(tree, merge.b)}"
            )
        return lines

    def drop_feature_part(self):
        lines = ["drop_feature"]
        for f, name in enumerate(self.feature_names):
            reduced = [vector[:f] + vector[f + 1:] for vector in self.vectors]
            delta = distance_matrix(reduced, self.settings.distance)
            partition = Tree(agglomerate(delta, self.chosen.method), self.count).cut_into(self.kappa)
            lines.append(
                f"{name} ari_selected {ari_text(self.partition_ari(partition, self.selected))} "
                f"ari_labels {ari_text(self.label_ari(partition))}"
            )
        return lines

    def nearest_center(self, vector, centers):
        best = 0
        best_value = squared_distance(vector, centers[0])
        for g in range(1, len(centers)):
            value = squared_distance(vector, centers[g])
            if value < best_value:
                best = g
                best_value = value
        return best + 1

    def refinement_part(self):
        limit = self.settings.refine_iterations
        centers = self.centroids(self.selected)
        previous = self.selected
        iterations = limit
        for t in range(1, limit + 1):
            assignment = [self.nearest_center(vector, centers) for vector in self.vectors]
            if assignment == previous:
                iterations = t
                break
            for g, group in enumerate(cluster_members(assignment, self.kappa)):
                if group:
                    centers[g] = centroid([self.vectors[i] for i in group])
            previous = assignment
        refined = previous
        changed = 0
        for before, after in zip(self.selected, refined):
            if before != after:
                changed += 1
        sizes = [len(group) for group in cluster_members(refined, self.kappa)]
        silhouette = self.mean_silhouette(refined, self.distances)
        return [
            f"refinement max_iterations {limit}",
            f"iterations {iterations} changed {changed} "
            f"wss {real(self.within_sum(self.selected))} -> {real(self.within_sum(refined))}",
            f"sizes {integers(sizes)} silhouette {real(silhouette)}",
            f"ari_selected {ari_text(self.partition_ari(refined, self.selected))} "
            f"ari_labels {ari_text(self.label_ari(refined))}",
        ]

    def jaccard(self, sample_partition, restricted):
        table = contingency_table(
            [number - 1 for number in restricted], [number - 1 for number in sample_partition],
            self.kappa, max(sample_partition),
        )
        column_sizes = [sum(row[h] for row in table) for h in range(len(table[0]))]
        values = []
        for row in table:
            size = sum(row)
            best = 0.0
            if size > 0:
                for h, common in enumerate(row):
                    best = max(best, common / (size + column_sizes[h] - common))
            values.append(best)
        return values

    def stability_part(self):
        settings = self.settings
        n = self.count
        generator = Minstd(settings.seed)
        size = n * settings.percent // 100
        aris = []
        jaccards = []
        lines = [
            f"stability replicates {settings.replicates} percent {settings.percent} "
            f"seed {settings.seed}"
        ]
        for b in range(1, settings.replicates + 1):
            array = list(range(n))
            for t in range(size):
                j = t + generator.draw() % (n - t)
                array[t], array[j] = array[j], array[t]
            sample = sorted(array[:size])
            delta = [[self.distances[u][w] for w in sample] for u in sample]
            partition = Tree(agglomerate(delta, self.chosen.method), size).cut_into(self.kappa)
            restricted = [self.selected[u] for u in sample]
            ari = self.partition_ari(partition, restricted)
            jaccard = self.jaccard(partition, restricted)
            aris.append(ari_value(ari))
            jaccards.append(jaccard)
            lines.append(f"replicate {b} size {size} ari {ari_text(ari)} jaccard {reals(jaccard)}")
        mean_jaccards = [
            sequential_sum(jaccard[g] for jaccard in jaccards) / settings.replicates
            for g in range(self.kappa)
        ]
        lines.append(f"mean_ari {real(sequential_sum(aris) / settings.replicates)}")
        lines.append("mean_jaccard " + reals(mean_jaccards))
        return lines

    def distance_map_part(self):
        order = self.chosen.tree.order
        frame = "+" + "-" * self.count + "+"
        lines = [f"distance_map {self.chosen.method}", frame]
        for u in order:
            shades = "".join(
                SHADES[histogram_bin(self.distances[u][w], self.distance_max)] for w in order
            )
            lines.append("|" + shades + "|")
        lines.append(frame)
        return lines

    def profiles_report(self):
        return join_parts([
            self.selection_part(),
            self.centroid_part(),
            self.profile_part(),
            self.contingency_part(),
            self.misplaced_part(),
            self.weakest_part(),
            self.feature_part(),
            self.top_merges_part(),
            self.drop_feature_part(),
            self.refinement_part(),
            self.stability_part(),
            self.distance_map_part(),
        ])


def main():
    feature_names, observations = read_observations(os.path.join(INPUT_DIRECTORY, "data.csv"))
    settings = read_settings(os.path.join(INPUT_DIRECTORY, "params.txt"))
    study = Study(feature_names, observations, settings)
    os.makedirs(OUTPUT_DIRECTORY, exist_ok=True)
    outputs = (
        ("linkage.csv", study.linkage_table()),
        ("clusters.csv", study.clusters_table()),
        ("dendrogram.txt", study.dendrogram_report()),
        ("trees.txt", study.trees_report()),
        ("validation.txt", study.validation_report()),
        ("profiles.txt", study.profiles_report()),
    )
    for name, lines in outputs:
        write_lines(os.path.join(OUTPUT_DIRECTORY, name), lines)


if __name__ == "__main__":
    main()
