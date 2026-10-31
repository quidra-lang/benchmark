import os
from math import sqrt

from features import (
    FEATURE_NAMES, SQRT_FEATURES, correlation, eligible_customers, mean, ordered_sum,
    sample_sd, standardization, standardize,
)
from kmeans import (
    cluster_center, cluster_centers, cluster_sizes, lloyd, mean_point, squared_distance, sse,
)
from profiles import original_scale, read_rules, rule_number
from report import amount, four_decimal, real, reals, write_lines
from transactions import group_orders, orders_by_customer, read_params, read_transactions
import validation


MODULUS = 2147483647
MULTIPLIER = 48271
HARTIGAN_LIMIT = 10
R_SCORES = (5, 4, 3, 2, 1)
FEATURES_HEADER = (
    "customer,recency,frequency,monetary,basket,categories,tenure,"
    "z_recency,z_frequency,z_monetary,z_basket,z_categories,z_tenure"
)
SEGMENTS_HEADER = "customer,segment,name,distance,other,other_distance,silhouette,recommend"


class Minstd:
    def __init__(self, seed):
        self.state = seed

    def draw(self):
        self.state = MULTIPLIER * self.state % MODULUS
        return self.state


def nearest_gaps(points, chosen):
    return [min(squared_distance(point, points[index]) for index in chosen) for point in points]


def forgy(points, k, random):
    chosen = []
    while len(chosen) < k:
        index = random.draw() % len(points)
        if index not in chosen:
            chosen.append(index)
    return chosen


def maximin(points, k, run_number):
    center = mean_point(points)
    spread = [squared_distance(point, center) for point in points]
    order = sorted(range(len(points)), key=lambda index: (spread[index], index))
    chosen = [order[run_number - 1]]
    while len(chosen) < k:
        gaps = nearest_gaps(points, chosen)
        chosen.append(max(range(len(points)), key=lambda index: gaps[index]))
    return chosen


def weighted_index(gaps, threshold):
    total = 0.0
    for index, gap in enumerate(gaps):
        total += gap
        if total > threshold:
            return index
    return max(index for index, gap in enumerate(gaps) if gap > 0)


def kmeanspp(points, k, random):
    chosen = [random.draw() % len(points)]
    while len(chosen) < k:
        gaps = nearest_gaps(points, chosen)
        weight = ordered_sum(gaps)
        threshold = (random.draw() / MODULUS) * weight
        chosen.append(weighted_index(gaps, threshold))
    return chosen


def initial_seeds(method, points, k, run_number, random):
    if method == "forgy":
        return forgy(points, k, random)
    if method == "maximin":
        return maximin(points, k, run_number)
    return kmeanspp(points, k, random)


class Improvement:
    def __init__(self, labels, passes, transfers, refined):
        self.labels = labels
        self.passes = passes
        self.transfers = transfers
        self.sse = refined


def improve(points, labels, k, max_passes):
    labels = list(labels)
    sizes = cluster_sizes(labels, k)
    centers = cluster_centers(points, labels, k)
    passes = 0
    transfers = 0
    moved = True
    while moved and passes < max_passes:
        moved = False
        passes += 1
        for i, point in enumerate(points):
            own = labels[i]
            if sizes[own] == 1:
                continue
            removal = (sizes[own] / (sizes[own] - 1)) * squared_distance(point, centers[own])
            target = None
            target_cost = 0.0
            for q in range(k):
                if q == own:
                    continue
                cost = (sizes[q] / (sizes[q] + 1)) * squared_distance(point, centers[q])
                if target is None or cost < target_cost:
                    target = q
                    target_cost = cost
            if target_cost < removal:
                labels[i] = target
                sizes[own] -= 1
                sizes[target] += 1
                centers[own] = cluster_center(points, labels, own)
                centers[target] = cluster_center(points, labels, target)
                transfers += 1
                moved = True
    refined = sse(points, labels, cluster_centers(points, labels, k))
    return Improvement(labels, passes, transfers, refined)


class Run:
    def __init__(self, method, number, seeds, points, max_iterations):
        self.method = method
        self.number = number
        self.seeds = seeds
        self.lloyd = lloyd(points, [points[index] for index in seeds], max_iterations)
        self.lloyd_sse = sse(points, self.lloyd.labels, self.lloyd.centers)
        self.improved = improve(points, self.lloyd.labels, len(seeds), max_iterations)


def best_run(runs):
    return min(runs, key=lambda run: four_decimal(run.improved.sse))


class Solution:
    def __init__(self, points, labels, k):
        groups = [[i for i, label in enumerate(labels) if label == j] for j in range(k)]
        groups.sort(key=lambda group: (-len(group), group[0]))
        self.k = k
        self.members = groups
        self.sizes = [len(group) for group in groups]
        self.labels = [0] * len(labels)
        for number, group in enumerate(groups):
            for index in group:
                self.labels[index] = number
        self.centers = cluster_centers(points, self.labels, k)
        self.sse = sse(points, self.labels, self.centers)


class Candidate:
    def __init__(self, k, runs, method_bests, best, solution):
        self.k = k
        self.runs = runs
        self.method_bests = method_bests
        self.best = best
        self.solution = solution
        self.silhouettes = []
        self.silhouette = 0.0
        self.calinski_harabasz = 0.0
        self.davies_bouldin = 0.0
        self.elbow = 0.0
        self.hartigan = None
        self.rule_numbers = []
        self.names = []


def segment_names(rules, centers):
    numbers = [rule_number(rules, center) for center in centers]
    names = []
    for position, number in enumerate(numbers):
        repeats = numbers[:position].count(number)
        name = rules[number - 1].name
        names.append(name if repeats == 0 else f"{name}_{repeats + 1}")
    return numbers, names


def rfm_scores(customers):
    count = len(customers)
    scores = []
    for customer in customers:
        older = sum(1 for other in customers if other.recency > customer.recency)
        fewer = sum(1 for other in customers if other.frequency < customer.frequency)
        smaller = sum(1 for other in customers if other.spend < customer.spend)
        scores.append([1 + 5 * rank // count for rank in (older, fewer, smaller)])
    return scores


def gini(spends):
    ordered = sorted(spends)
    count = len(ordered)
    total = sum(ordered)
    weighted = sum(position * spend for position, spend in enumerate(ordered, 1))
    return (2 * weighted - (count + 1) * total) / (count * total)


def lower_median(values):
    return sorted(values)[(len(values) - 1) // 2]


def traits(center):
    order = sorted(range(len(center)), key=lambda feature: (-abs(center[feature]), feature))
    return [
        ("high_" if center[feature] > 0 else "low_") + FEATURE_NAMES[feature]
        for feature in order[:2]
    ]


def category_totals(customers):
    totals = {}
    for customer in customers:
        for category, spend in customer.category_spend.items():
            totals[category] = totals.get(category, 0) + spend
    return totals


def category_ranking(totals):
    positive = [category for category in totals if totals[category] > 0]
    return sorted(positive, key=lambda category: (-totals[category], category))


def yes_no(flag):
    return "yes" if flag else "no"


def join_blocks(blocks):
    lines = []
    for block in blocks:
        if lines:
            lines.append("")
        lines.extend(block)
    return lines


class Analysis:
    def __init__(self, params, data, rules):
        self.params = params
        self.data = data
        self.rules = rules
        self.random = Minstd(params.seed)
        self.reference_orders = group_orders(data.valid_rows, 1, params.reference_day)
        self.customer_orders = orders_by_customer(self.reference_orders)
        self.customers = eligible_customers(self.reference_orders, params.reference_day)
        self.n = len(self.customers)
        self.numbers = {customer.id: number for number, customer in enumerate(self.customers)}
        transformed = [customer.transformed() for customer in self.customers]
        self.means, self.sds = standardization(transformed)
        self.points = [standardize(values, self.means, self.sds) for values in transformed]
        self.candidates = []
        self.votes = []
        self.final = None
        self.final_votes = 0
        self.jaccards = []

    def ids(self, numbers):
        return " ".join(self.customers[number].id for number in numbers)

    def candidate(self, k):
        return self.candidates[k - self.params.k_min]

    def analyze(self):
        for k in range(self.params.k_min, self.params.k_max + 1):
            self.candidates.append(self.search(k))
        self.evaluate()
        self.choose_k()
        self.describe_final()
        self.jaccards = self.subsample_jaccards()

    def search(self, k):
        runs = []
        method_bests = []
        for method in self.params.methods:
            method_runs = []
            for number in range(1, self.params.restarts + 1):
                seeds = initial_seeds(method, self.points, k, number, self.random)
                run = Run(method, number, seeds, self.points, self.params.max_iterations)
                method_runs.append(run)
            runs.extend(method_runs)
            method_bests.append(best_run(method_runs))
        best = best_run(method_bests)
        solution = Solution(self.points, best.improved.labels, k)
        return Candidate(k, runs, method_bests, best, solution)

    def evaluate(self):
        table = validation.distance_table(self.points)
        first = self.candidates[0].solution.sse
        last = self.candidates[-1].solution.sse
        for position, candidate in enumerate(self.candidates):
            solution = candidate.solution
            candidate.silhouettes = validation.silhouettes(table, solution.labels, solution.sizes)
            candidate.silhouette = ordered_sum(candidate.silhouettes) / self.n
            candidate.calinski_harabasz = validation.calinski_harabasz(
                self.points, solution.centers, solution.sizes, solution.sse
            )
            candidate.davies_bouldin = validation.davies_bouldin(
                self.points, solution.labels, solution.centers, solution.sizes
            )
            candidate.elbow = validation.elbow(
                candidate.k, self.params.k_min, self.params.k_max, solution.sse, first, last
            )
            if candidate.k < self.params.k_max:
                following = self.candidates[position + 1].solution.sse
                candidate.hartigan = validation.hartigan(
                    solution.sse, following, self.n, candidate.k
                )
            candidate.rule_numbers, candidate.names = segment_names(self.rules, solution.centers)

    def choose_k(self):
        candidates = self.candidates
        elbow = max(candidates[1:-1], key=lambda candidate: four_decimal(candidate.elbow))
        silhouette = max(candidates, key=lambda candidate: four_decimal(candidate.silhouette))
        harabasz = max(candidates, key=lambda candidate: four_decimal(candidate.calinski_harabasz))
        bouldin = min(candidates, key=lambda candidate: four_decimal(candidate.davies_bouldin))
        hartigan = next(
            (
                candidate.k for candidate in candidates
                if candidate.hartigan is not None and candidate.hartigan <= HARTIGAN_LIMIT
            ),
            self.params.k_max,
        )
        self.votes = [
            ("elbow", elbow.k),
            ("silhouette", silhouette.k),
            ("calinski_harabasz", harabasz.k),
            ("davies_bouldin", bouldin.k),
            ("hartigan", hartigan),
        ]
        counts = {candidate.k: 0 for candidate in candidates}
        for _, k in self.votes:
            counts[k] += 1
        self.final = max(
            candidates,
            key=lambda candidate: (counts[candidate.k], four_decimal(candidate.silhouette)),
        )
        self.final_votes = counts[self.final.k]

    def describe_final(self):
        solution = self.final.solution
        self.k = solution.k
        self.labels = solution.labels
        self.centers = solution.centers
        self.names = self.final.names
        self.silhouettes = self.final.silhouettes
        self.distances = []
        self.others = []
        for point, label in zip(self.points, self.labels):
            squared = [squared_distance(point, center) for center in self.centers]
            other = min((j for j in range(self.k) if j != label), key=lambda j: squared[j])
            self.distances.append(sqrt(squared[label]))
            self.others.append((other, sqrt(squared[other])))
        self.scores = rfm_scores(self.customers)
        self.codes = ["".join(str(score) for score in scores) for scores in self.scores]
        self.total_spend = sum(customer.spend for customer in self.customers)
        self.overall_categories = category_totals(self.customers)
        self.category_names = sorted(self.overall_categories)
        self.segment_customers = [
            [self.customers[number] for number in members] for members in solution.members
        ]
        self.segment_spends = [
            sum(customer.spend for customer in members) for members in self.segment_customers
        ]
        self.segment_categories = [category_totals(members) for members in self.segment_customers]
        self.rankings = [category_ranking(totals) for totals in self.segment_categories]
        self.segment_sse = []
        for segment, members in enumerate(solution.members):
            total = 0.0
            for number in members:
                total += squared_distance(self.points[number], self.centers[segment])
            self.segment_sse.append(total)

    def recommendation(self, number):
        customer = self.customers[number]
        for category in self.rankings[self.labels[number]]:
            if customer.category_spend.get(category, 0) <= 0:
                return category
        return "-"

    def subsample_jaccards(self):
        size = self.n * self.params.subsample_percent // 100
        jaccards = [[] for _ in range(self.k)]
        for _ in range(self.params.subsamples):
            order = list(range(self.n))
            for t in range(size):
                j = t + self.random.draw() % (self.n - t)
                order[t], order[j] = order[j], order[t]
            sample = sorted(order[:size])
            points = [self.points[number] for number in sample]
            result = lloyd(points, self.centers, self.params.max_iterations)
            for segment in range(self.k):
                jaccards[segment].append(self.jaccard(sample, result.labels, segment))
        return jaccards

    def jaccard(self, sample, labels, segment):
        in_segment = [self.labels[number] == segment for number in sample]
        best = 0.0
        for j in range(self.k):
            both = sum(1 for member, label in zip(in_segment, labels) if member and label == j)
            either = sum(1 for member, label in zip(in_segment, labels) if member or label == j)
            if either > 0 and both / either > best:
                best = both / either
        return best

    def features_lines(self):
        lines = [FEATURES_HEADER]
        for customer, point in zip(self.customers, self.points):
            fields = [
                customer.id, str(customer.recency), str(customer.frequency),
                amount(customer.spend), real(customer.basket),
                str(customer.categories), str(customer.tenure),
            ]
            fields.extend(real(value) for value in point)
            lines.append(",".join(fields))
        return lines

    def run_line(self, run):
        return (
            f"run {run.method} {run.number} seeds {self.ids(run.seeds)}"
            f" iterations {run.lloyd.iterations} converged {yes_no(run.lloyd.converged)}"
            f" reseeds {run.lloyd.reseeds} sse {real(run.lloyd_sse)}"
            f" passes {run.improved.passes} transfers {run.improved.transfers}"
            f" refined {real(run.improved.sse)}"
        )

    def run_summary(self, run):
        return f"{run.method} restart {run.number} sse {real(run.improved.sse)}"

    def runs_lines(self):
        blocks = []
        for candidate in self.candidates:
            block = [f"k {candidate.k}"]
            block.extend(self.run_line(run) for run in candidate.runs)
            for run in candidate.method_bests:
                block.append(f"best {self.run_summary(run)}")
            block.append(f"chosen {self.run_summary(candidate.best)}")
            block.append("sizes " + " ".join(str(size) for size in candidate.solution.sizes))
            blocks.append(block)
        return join_blocks(blocks)

    def stability_line(self, position, candidate):
        parts = [f"k={candidate.k}"]
        bests = candidate.method_bests
        for i, first in enumerate(bests):
            for second in bests[i + 1:]:
                index = validation.adjusted_rand_index(
                    first.improved.labels, second.improved.labels
                )
                parts.append(f"{first.method}:{second.method} {real(index)}")
        parts.append("final")
        for run in bests:
            index = validation.adjusted_rand_index(run.improved.labels, candidate.solution.labels)
            parts.append(f"{run.method} {real(index)}")
        if position + 1 < len(self.candidates):
            following = self.candidates[position + 1].solution
            index = validation.adjusted_rand_index(candidate.solution.labels, following.labels)
            parts.append(f"next {real(index)}")
        else:
            parts.append("next -")
        return " ".join(parts)

    def selection_lines(self):
        indices = ["indices"]
        for candidate in self.candidates:
            hartigan = "-" if candidate.hartigan is None else real(candidate.hartigan)
            indices.append(
                f"k={candidate.k} sse {real(candidate.solution.sse)} elbow {real(candidate.elbow)}"
                f" silhouette {real(candidate.silhouette)}"
                f" calinski_harabasz {real(candidate.calinski_harabasz)}"
                f" davies_bouldin {real(candidate.davies_bouldin)} hartigan {hartigan}"
            )
        votes = ["votes"]
        votes.extend(f"{criterion} k={k}" for criterion, k in self.votes)
        votes.append(f"chosen k={self.final.k} votes {self.final_votes}")
        names = ["segments"]
        for candidate in self.candidates:
            parts = [
                f"{name}:{size}" for name, size in zip(candidate.names, candidate.solution.sizes)
            ]
            names.append(f"k={candidate.k} " + " ".join(parts))
        stability = ["stability"]
        for position, candidate in enumerate(self.candidates):
            stability.append(self.stability_line(position, candidate))
        return join_blocks([indices, votes, names, stability])

    def segments_lines(self):
        lines = [SEGMENTS_HEADER]
        for number, customer in enumerate(self.customers):
            label = self.labels[number]
            other, other_distance = self.others[number]
            fields = [
                customer.id, str(label + 1), self.names[label], real(self.distances[number]),
                str(other + 1), real(other_distance), real(self.silhouettes[number]),
                self.recommendation(number),
            ]
            lines.append(",".join(fields))
        return lines

    def median_line(self, customers):
        recency = lower_median([customer.recency for customer in customers])
        frequency = lower_median([customer.frequency for customer in customers])
        spend = lower_median([customer.spend for customer in customers])
        basket = lower_median([customer.basket for customer in customers])
        categories = lower_median([customer.categories for customer in customers])
        tenure = lower_median([customer.tenure for customer in customers])
        return (
            f"  median recency {recency} frequency {frequency} monetary {amount(spend)}"
            f" basket {real(basket)} categories {categories} tenure {tenure}"
        )

    def related(self, members, k):
        if k < self.params.k_min or k > self.params.k_max:
            return f"k={k} -"
        labels = self.candidate(k).solution.labels
        counts = [0] * k
        for number in members:
            counts[labels[number]] += 1
        best = counts.index(max(counts))
        return f"k={k} segment {best + 1} shared {counts[best]}"

    def cadence_line(self, customers):
        gaps = []
        overdue = 0
        for customer in customers:
            if customer.frequency < 2:
                continue
            active_days = customer.tenure - customer.recency
            intervals = customer.frequency - 1
            gaps.append(active_days / intervals)
            if customer.recency * intervals > self.params.overdue_factor * active_days:
                overdue += 1
        mean_gap = real(mean(gaps)) if gaps else "-"
        return f"  cadence customers {len(gaps)} mean_gap {mean_gap} overdue {overdue}"

    def order_sizes_line(self, customers):
        bins = [0] * (len(self.params.order_bins) + 1)
        for customer in customers:
            for order in customer.orders:
                bins[sum(1 for bound in self.params.order_bins if order.net >= bound * 100)] += 1
        return "  order_sizes " + " ".join(str(count) for count in bins)

    def returns_line(self, customers):
        gross = 0
        returned = 0
        cancelled = 0
        for customer in customers:
            for order in self.customer_orders[customer.id]:
                if not order.is_valid():
                    cancelled += 1
                for row in order.rows:
                    if row.amount > 0:
                        gross += row.amount
                    elif row.amount < 0:
                        returned -= row.amount
        return (
            f"  returns rate {real(returned / gross)} returned {amount(returned)}"
            f" cancelled {cancelled}"
        )

    def rfm_line(self, members):
        size = len(members)
        means = [sum(self.scores[number][part] for number in members) / size for part in range(3)]
        counts = {}
        for number in members:
            counts[self.codes[number]] = counts.get(self.codes[number], 0) + 1
        mode = min(counts, key=lambda code: (-counts[code], code))
        return (
            f"  rfm r {real(means[0])} f {real(means[1])} m {real(means[2])}"
            f" mode {mode} {counts[mode]}"
        )

    def categories_line(self, segment):
        totals = self.segment_categories[segment]
        spend = self.segment_spends[segment]
        parts = ["  categories"]
        for category in self.rankings[segment][:self.params.top_categories]:
            share = totals[category] / spend
            lift = share / (self.overall_categories[category] / self.total_spend)
            parts.extend((category, real(share), real(lift)))
        return " ".join(parts)

    def outliers_line(self, members):
        outliers = []
        if len(members) >= 2:
            distances = [self.distances[number] for number in members]
            limit = mean(distances) + self.params.outlier_sd * sample_sd(distances)
            outliers = [
                self.customers[number].id for number in members if self.distances[number] > limit
            ]
        return " ".join(["  outliers", str(len(outliers))] + outliers)

    def segment_profile(self, segment):
        members = self.final.solution.members[segment]
        customers = self.segment_customers[segment]
        size = len(members)
        center = self.centers[segment]
        spend = self.segment_spends[segment]
        lines = [
            f"segment {segment + 1} {self.names[segment]} rule {self.final.rule_numbers[segment]}"
            f" size {size} share {real(size / self.n)} revenue {amount(spend)}"
            f" revenue_share {real(spend / self.total_spend)}"
        ]
        lines.append("  center " + reals(center))
        values = original_scale(center, self.means, self.sds)
        named_values = [f"{name} {real(value)}" for name, value in zip(FEATURE_NAMES, values)]
        lines.append("  value " + " ".join(named_values))
        lines.append("  traits " + " ".join(traits(center)))
        lines.append(self.median_line(customers))
        lines.append(
            "  related " + " ".join(self.related(members, k) for k in (self.k - 1, self.k + 1))
        )
        top = sorted(members, key=lambda number: (-self.customers[number].spend, number))
        parts = ["  top_customers"]
        for number in top[:self.params.top_customers]:
            parts.extend((self.customers[number].id, amount(self.customers[number].spend)))
        lines.append(" ".join(parts))
        lines.append(self.cadence_line(customers))
        lines.append(self.order_sizes_line(customers))
        segment_sse = self.segment_sse[segment]
        sse_share = segment_sse / self.final.solution.sse
        lines.append(f"  sse {real(segment_sse)} share {real(sse_share)}")
        lines.append(f"  gini {real(gini([customer.spend for customer in customers]))}")
        lines.append(self.returns_line(customers))
        silhouettes = [self.silhouettes[number] for number in members]
        negative = sum(1 for value in silhouettes if value < 0)
        lines.append(f"  silhouette {real(mean(silhouettes))} negative {negative}")
        lines.append(self.rfm_line(members))
        lines.append(self.categories_line(segment))
        lines.append(self.outliers_line(members))
        return lines

    def segment_numbers(self):
        return " ".join(str(segment + 1) for segment in range(self.k))

    def category_mix_lines(self):
        lines = ["category_mix " + self.segment_numbers()]
        for category in self.category_names:
            shares = [
                totals.get(category, 0) / spend
                for totals, spend in zip(self.segment_categories, self.segment_spends)
            ]
            lines.append(category + " " + reals(shares))
        return lines

    def recency_table_lines(self):
        lines = ["rfm_recency " + self.segment_numbers()]
        for score in R_SCORES:
            counts = [0] * self.k
            for number, scores in enumerate(self.scores):
                if scores[0] == score:
                    counts[self.labels[number]] += 1
            lines.append(f"r={score} " + " ".join(str(count) for count in counts))
        index = validation.adjusted_rand_index(self.codes, self.labels)
        lines.append(f"ari rfm_codes {real(index)}")
        return lines

    def center_distance_lines(self):
        lines = ["center_distances"]
        for segment, center in enumerate(self.centers):
            distances = [sqrt(squared_distance(center, other)) for other in self.centers]
            lines.append(f"{segment + 1} " + reals(distances))
        return lines

    def profiles_lines(self):
        all_spends = [customer.spend for customer in self.customers]
        blocks = [[
            f"segments k={self.k} customers {self.n} revenue {amount(self.total_spend)}"
            f" gini {real(gini(all_spends))}"
        ]]
        for segment in range(self.k):
            blocks.append(self.segment_profile(segment))
        blocks.append(self.category_mix_lines())
        blocks.append(self.recency_table_lines())
        blocks.append(self.center_distance_lines())
        return join_blocks(blocks)

    def subsample_lines(self):
        size = self.n * self.params.subsample_percent // 100
        lines = [f"subsamples {self.params.subsamples} size {size}"]
        for segment, values in enumerate(self.jaccards):
            lines.append(
                f"segment {segment + 1} {self.names[segment]} mean_jaccard {real(mean(values))}"
                f" min_jaccard {real(min(values))}"
            )
        return lines

    def ablation_lines(self):
        lines = ["ablation"]
        for feature, name in enumerate(FEATURE_NAMES):
            points = [point[:feature] + point[feature + 1:] for point in self.points]
            seeds = maximin(points, self.k, 1)
            run = Run("maximin", 1, seeds, points, self.params.max_iterations)
            index = validation.adjusted_rand_index(run.improved.labels, self.labels)
            lines.append(
                f"without {name} seeds {self.ids(seeds)} iterations {run.lloyd.iterations}"
                f" converged {yes_no(run.lloyd.converged)} transfers {run.improved.transfers}"
                f" sse {real(run.improved.sse)} ari {real(index)}"
            )
        return lines

    def drilldown_lines(self):
        members = self.final.solution.members[0]
        points = [self.points[number] for number in members]
        seeds = maximin(points, 2, 1)
        run = Run("maximin", 1, seeds, points, self.params.max_iterations)
        parts = Solution(points, run.improved.labels, 2)
        before = self.segment_sse[0]
        after = run.improved.sse
        lines = [
            f"drilldown segment 1 {self.names[0]} size {len(members)}"
            f" seeds {self.ids(members[seed] for seed in seeds)} iterations {run.lloyd.iterations}"
            f" converged {yes_no(run.lloyd.converged)} transfers {run.improved.transfers}",
            f"sse before {real(before)} after {real(after)} gain {real(before - after)}",
        ]
        for part, (size, center) in enumerate(zip(parts.sizes, parts.centers), 1):
            lines.append(f"part {part} size {size} center {reals(center)}")
        return lines

    def robustness_lines(self):
        return join_blocks([self.subsample_lines(), self.ablation_lines(), self.drilldown_lines()])

    def period_lines(self):
        reference_day = self.params.reference_day
        days = self.params.period_days
        lines = [f"periods {self.params.periods} days {days}"]
        for q in range(1, self.params.periods + 1):
            first = reference_day - q * days + 1
            last = reference_day - (q - 1) * days
            revenue = [0] * self.k
            active = [0] * self.k
            acquired = [0] * self.k
            for customer, label in zip(self.customers, self.labels):
                nets = [order.net for order in customer.orders if first <= order.day <= last]
                if nets:
                    revenue[label] += sum(nets)
                    active[label] += 1
                if first <= reference_day - customer.tenure <= last:
                    acquired[label] += 1
            parts = [f"period {q} days {first} {last} revenue"]
            parts.extend(amount(value) for value in revenue)
            parts.append("active")
            parts.extend(str(count) for count in active)
            parts.append("acquired")
            parts.extend(str(count) for count in acquired)
            lines.append(" ".join(parts))
        return lines

    def migration_lines(self):
        snapshot_day = self.params.snapshot_day
        orders = group_orders(self.data.valid_rows, 1, snapshot_day)
        snapshot_segments = {}
        for customer in eligible_customers(orders, snapshot_day):
            point = standardize(customer.transformed(), self.means, self.sds)
            squared = [squared_distance(point, center) for center in self.centers]
            snapshot_segments[customer.id] = squared.index(min(squared))
        table = [[0] * self.k for _ in range(self.k + 1)]
        moved_lines = []
        stayed = 0
        new = 0
        for customer, label in zip(self.customers, self.labels):
            if customer.id not in snapshot_segments:
                table[self.k][label] += 1
                new += 1
                continue
            origin = snapshot_segments[customer.id]
            table[origin][label] += 1
            if origin == label:
                stayed += 1
            else:
                moved_lines.append(f"{customer.id} {origin + 1} {label + 1}")
        lost = sum(1 for customer_id in snapshot_segments if customer_id not in self.numbers)
        lines = [
            f"migration day {snapshot_day} customers {len(snapshot_segments)}",
            "from\\to " + self.segment_numbers(),
        ]
        for origin, counts in enumerate(table):
            label = "none" if origin == self.k else str(origin + 1)
            lines.append(label + " " + " ".join(str(count) for count in counts))
        lines.append("moved_customers")
        lines.extend(moved_lines)
        lines.append(f"stayed {stayed} moved {len(moved_lines)} new {new} lost {lost}")
        return lines

    def outcome_lines(self):
        first = self.params.reference_day + 1
        last = self.params.reference_day + self.params.outcome_days
        orders = group_orders(self.data.valid_rows, first, last)
        purchases = orders_by_customer([order for order in orders if order.is_valid()])
        lines = [f"outcome days {first} {last}"]
        for segment, customers in enumerate(self.segment_customers):
            size = len(customers)
            buyers = 0
            spend = 0
            for customer in customers:
                if customer.id in purchases:
                    buyers += 1
                    spend += sum(order.net for order in purchases[customer.id])
            lines.append(
                f"segment {segment + 1} {self.names[segment]} size {size} buyers {buyers}"
                f" rate {real(buyers / size)} revenue {amount(spend)}"
                f" per_customer {real((spend / 100) / size)}"
            )
        outsiders = [customer_id for customer_id in purchases if customer_id not in self.numbers]
        outsider_spend = sum(
            order.net for customer_id in outsiders for order in purchases[customer_id]
        )
        lines.append(f"unsegmented buyers {len(outsiders)} revenue {amount(outsider_spend)}")
        return lines

    def tracking_lines(self):
        return join_blocks([self.period_lines(), self.migration_lines(), self.outcome_lines()])

    def data_lines(self):
        reference_day = self.params.reference_day
        used = [row for row in self.data.valid_rows if row.day <= reference_day]
        returns = sum(1 for row in used if row.amount < 0)
        later = sum(1 for row in self.data.valid_rows if row.day > reference_day)
        valid = sum(1 for order in self.reference_orders if order.is_valid())
        excluded = sorted(
            customer_id for customer_id in self.data.customers if customer_id not in self.numbers
        )
        return [
            f"rows {self.data.row_count} duplicates {self.data.duplicates} zero {self.data.free}"
            f" used {len(used)} returns {returns} later {later}",
            f"orders {len(self.reference_orders)} valid {valid}"
            f" cancelled {len(self.reference_orders) - valid}",
            f"customers {len(self.data.customers)} clustered {self.n} excluded {len(excluded)}",
            "excluded_ids " + (" ".join(excluded) if excluded else "-"),
        ]

    def category_lines(self):
        lines = []
        for category in self.category_names:
            total = self.overall_categories[category]
            buyers = sum(
                1 for customer in self.customers if customer.category_spend.get(category, 0) > 0
            )
            lines.append(
                f"category {category} revenue {amount(total)}"
                f" share {real(total / self.total_spend)} customers {buyers}"
            )
        return lines

    def feature_summary_lines(self):
        lines = []
        raw_values = [customer.values() for customer in self.customers]
        for feature, name in enumerate(FEATURE_NAMES):
            column = [values[feature] for values in raw_values]
            transform = "sqrt" if SQRT_FEATURES[feature] else "none"
            lines.append(
                f"feature {name} transform {transform} raw_mean {real(mean(column))}"
                f" raw_sd {real(sample_sd(column))} mean {real(self.means[feature])}"
                f" sd {real(self.sds[feature])}"
            )
        return lines

    def correlation_lines(self):
        lines = ["correlation " + " ".join(FEATURE_NAMES)]
        for first, name in enumerate(FEATURE_NAMES):
            values = [
                correlation(self.points, first, second) for second in range(len(FEATURE_NAMES))
            ]
            lines.append(name + " " + reals(values))
        return lines

    def summary_lines(self):
        return join_blocks([
            self.data_lines(), self.category_lines(),
            self.feature_summary_lines(), self.correlation_lines(),
        ])


def main():
    params = read_params("input/params.txt")
    data = read_transactions("input/transactions.csv")
    rules = read_rules("input/segment_rules.txt")
    analysis = Analysis(params, data, rules)
    analysis.analyze()
    os.makedirs("output", exist_ok=True)
    write_lines("output/features.csv", analysis.features_lines())
    write_lines("output/runs.txt", analysis.runs_lines())
    write_lines("output/selection.txt", analysis.selection_lines())
    write_lines("output/segments.csv", analysis.segments_lines())
    write_lines("output/profiles.txt", analysis.profiles_lines())
    write_lines("output/robustness.txt", analysis.robustness_lines())
    write_lines("output/tracking.txt", analysis.tracking_lines())
    write_lines("output/summary.txt", analysis.summary_lines())


if __name__ == "__main__":
    main()
