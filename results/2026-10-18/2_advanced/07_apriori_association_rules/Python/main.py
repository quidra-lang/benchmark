import os
from fractions import Fraction

from apriori import count_supports, generate_candidates, one_smaller_subsets
from baskets import Product, Transaction, contains, extended_basket, read_records
from fpgrowth import fp_growth
from report import (
    fraction_text, itemset_text, money_text, percent_text, rule_arrow, rules_csv, write_report,
)
from rules import Rule, RuleSet, lift_of, meets_thresholds, rule_order


INPUT_DIR = "input"
SEGMENTS = ("NEW", "LOYAL", "AT_RISK", "REGULAR")
NEW_WINDOW = 28
LOYAL_MIN_BASKETS = 4
LOYAL_WINDOW = 14
AT_RISK_WINDOW = 28
WEEK_LENGTH = 7
LABEL_WIDTH = 17
WEEK_WIDTH = 6
INDEX_WIDTH = 4
CELL_WIDTH = 7
MATRIX_SCALE = 100


def parse_fraction(text):
    numerator, denominator = text.split("/")
    return Fraction(int(numerator), int(denominator))


class Params:
    def __init__(self, values):
        self.min_support = int(values["min_support"])
        self.min_confidence = parse_fraction(values["min_confidence"])
        self.min_lift = parse_fraction(values["min_lift"])
        self.max_size = int(values["max_size"])
        self.category_min_support = int(values["category_min_support"])
        self.sequence_min_support = int(values["sequence_min_support"])
        self.split_day = int(values["split_day"])
        self.train_min_support = int(values["train_min_support"])
        self.test_min_support = int(values["test_min_support"])
        self.recommend_top = int(values["recommend_top"])
        self.matrix_size = int(values["matrix_size"])
        self.group_min_lift = parse_fraction(values["group_min_lift"])
        self.negative_max_lift = parse_fraction(values["negative_max_lift"])
        self.negative_min_expected = int(values["negative_min_expected"])
        self.trend_threshold = parse_fraction(values["trend_threshold"])


def read_params(path):
    values = {}
    with open(path) as handle:
        for line in handle.read().splitlines():
            key, value = line.split(" ")
            values[key] = value
    return Params(values)


def median(values):
    ordered = sorted(values)
    middle = len(ordered) // 2
    if len(ordered) % 2 == 1:
        return Fraction(ordered[middle])
    return Fraction(ordered[middle - 1] + ordered[middle], 2)


def size_order(itemset):
    return len(itemset), itemset


def support_in(supports, total, itemset):
    return supports[itemset] if itemset else total


def split_itemset(itemset, mask):
    chosen = tuple(item for bit, item in enumerate(itemset) if mask >> bit & 1)
    rest = tuple(item for bit, item in enumerate(itemset) if not mask >> bit & 1)
    return chosen, rest


def week_of(day):
    return (day - 1) // WEEK_LENGTH + 1


def purchase_days(baskets):
    found = {}
    for basket in baskets:
        for product in basket.counts:
            found.setdefault(product, set()).add(basket.day)
    return {product: sorted(days) for product, days in found.items()}


def shortest_gap(first_days, second_days):
    gaps = [later - earlier for earlier in first_days for later in second_days if earlier < later]
    return min(gaps)


def recommend(held, candidates, limit):
    selected = []
    for product in candidates:
        if len(selected) == limit:
            break
        if product not in held and product not in selected:
            selected.append(product)
    return selected


def rule_candidates(rules, held):
    return [
        rule.consequent[0] for rule in rules
        if len(rule.consequent) == 1 and contains(held, rule.antecedent)
    ]


def other_item(pair, item):
    return pair[1] if pair[0] == item else pair[0]


def table_row(label, values):
    return f"{label:<{LABEL_WIDTH}}" + "".join(f"{value:>{WEEK_WIDTH}}" for value in values)


def segment_of(summary, last_basket_day):
    if summary.first > last_basket_day - NEW_WINDOW:
        return "NEW"
    if summary.baskets >= LOYAL_MIN_BASKETS and last_basket_day - summary.last <= LOYAL_WINDOW:
        return "LOYAL"
    if last_basket_day - summary.last > AT_RISK_WINDOW:
        return "AT_RISK"
    return "REGULAR"


class Dataset:
    def __init__(self):
        self.errors = []
        self.products = {}
        self.item_rows = 0
        self.transaction_lines = 0
        self.adopted = 0
        self.rejected = 0
        self.duplicates = 0
        self.transactions = []

    def record_error(self, file_name, line_number, message):
        self.errors.append(f"{file_name} line {line_number}: {message}")

    def load_items(self, path):
        records = read_records(path)
        self.item_rows = len(records)
        for line_number, (name, category, price_text) in enumerate(records, 2):
            price = int(price_text)
            if name in self.products:
                self.record_error("items.csv", line_number, f"duplicate item {name}")
            elif price == 0:
                self.record_error("items.csv", line_number, f"bad price {price}")
            else:
                self.products[name] = Product(name, category, price)

    def line_problem(self, tid, customer, day, item):
        current = self.transactions[-1]
        if customer != current.customer:
            return f"tid {tid} customer {customer} differs from {current.customer}"
        if day != current.day:
            return f"tid {tid} day {day} differs from {current.day}"
        if item not in self.products:
            return f"unknown item {item}"
        return None

    def load_transactions(self, path):
        records = read_records(path)
        self.transaction_lines = len(records)
        known = set()
        for line_number, (tid, customer, day_text, item) in enumerate(records, 2):
            day = int(day_text)
            if tid in known and tid != self.transactions[-1].tid:
                problem = f"tid {tid} not contiguous"
            else:
                if tid not in known:
                    known.add(tid)
                    self.transactions.append(Transaction(tid, customer, day))
                problem = self.line_problem(tid, customer, day, item)
            if problem is not None:
                self.record_error("transactions.csv", line_number, problem)
                self.rejected += 1
                continue
            self.adopted += 1
            if self.transactions[-1].add(item):
                self.duplicates += 1

    def baskets(self):
        return [transaction for transaction in self.transactions if not transaction.is_empty()]


class Level:
    def __init__(self, number, candidates, excluded, pruned, counted, itemsets):
        self.number = number
        self.candidates = candidates
        self.excluded = excluded
        self.pruned = pruned
        self.counted = counted
        self.itemsets = itemsets


class AprioriResult:
    def __init__(self):
        self.levels = []
        self.supports = {}
        self.single_counts = {}

    def add_level(self, number, candidates, excluded, pruned, counted, counts, minimum):
        frequent = sorted(itemset for itemset in counted if counts[itemset] >= minimum)
        self.levels.append(Level(number, candidates, excluded, pruned, len(counted), frequent))
        for itemset in frequent:
            self.supports[itemset] = counts[itemset]
        return frequent


def run_apriori(item_sets, universe, minimum, max_size, taxonomy=None):
    result = AprioriResult()
    singles = [(item,) for item in sorted(universe)]
    counts = count_supports(item_sets, singles)
    result.single_counts = {single[0]: counts[single] for single in singles}
    frequent = result.add_level(1, len(singles), 0, 0, singles, counts, minimum)
    size = 2
    while size <= max_size and frequent:
        generation = generate_candidates(frequent, size, taxonomy)
        counts = count_supports(item_sets, generation.itemsets)
        frequent = result.add_level(
            size, generation.joined, generation.excluded, generation.pruned,
            generation.itemsets, counts, minimum,
        )
        size += 1
    return result


def reference_confidence(supports, total, antecedent, consequent):
    confidences = []
    for mask in range((1 << len(antecedent)) - 1):
        subset, _ = split_itemset(antecedent, mask)
        joined = tuple(sorted(subset + consequent))
        together = support_in(supports, total, joined)
        confidences.append(Fraction(together, support_in(supports, total, subset)))
    return max(confidences)


def make_rules(supports, total, params, required=None):
    generated = 0
    kept = []
    for itemset, count in supports.items():
        if len(itemset) < 2:
            continue
        if required is not None and not any(item in required for item in itemset):
            continue
        for mask in range(1, (1 << len(itemset)) - 1):
            antecedent, consequent = split_itemset(itemset, mask)
            generated += 1
            rule = Rule(
                itemset, antecedent, consequent, count, total,
                supports[antecedent], supports[consequent],
            )
            if meets_thresholds(rule.confidence, rule.lift, params):
                reference = reference_confidence(supports, total, antecedent, consequent)
                rule.improvement = rule.confidence - reference
                kept.append(rule)
    kept.sort(key=rule_order)
    for rank, rule in enumerate(kept, 1):
        rule.rank = rank
    return RuleSet(generated, kept)


class Sequence:
    def __init__(self, first, second, gaps, buyers, customer_total):
        self.first = first
        self.second = second
        self.customers = len(gaps)
        self.base = buyers[first]
        self.confidence = Fraction(self.customers, self.base)
        self.lift = lift_of(customer_total, self.customers, self.base, buyers[second])
        self.gap = median(gaps)


class Repeat:
    def __init__(self, product, customers, intervals):
        self.product = product
        self.customers = customers
        self.count = len(intervals)
        self.minimum = min(intervals)
        self.maximum = max(intervals)
        self.mean = Fraction(sum(intervals), len(intervals))
        self.median = median(intervals)


class RuleCheck:
    def __init__(self, rule, counts, total, params):
        self.rule = rule
        self.together = counts[rule.itemset]
        self.antecedent_count = counts[rule.antecedent]
        consequent_count = counts[rule.consequent]
        self.confidence = None
        self.lift = None
        if self.antecedent_count == 0 or consequent_count == 0:
            self.verdict = "UNSEEN"
            return
        self.confidence = Fraction(self.together, self.antecedent_count)
        self.lift = lift_of(total, self.together, self.antecedent_count, consequent_count)
        if meets_thresholds(self.confidence, self.lift, params):
            self.verdict = "HOLD"
        else:
            self.verdict = "FAIL"


class Tally:
    def __init__(self):
        self.cases = 0
        self.covered = 0
        self.top_hits = 0
        self.hits = 0
        self.baseline_hits = 0

    def add(self, held_out, suggestion, baseline):
        self.cases += 1
        if suggestion:
            self.covered += 1
            if suggestion[0] == held_out:
                self.top_hits += 1
        if held_out in suggestion:
            self.hits += 1
        if held_out in baseline:
            self.baseline_hits += 1

    def describe(self):
        hit_rate = fraction_text(Fraction(self.hits, self.cases))
        baseline_rate = fraction_text(Fraction(self.baseline_hits, self.cases))
        return (
            f"cases {self.cases} covered {self.covered} hit1 {self.top_hits} hit {self.hits} "
            f"rate {hit_rate} baseline {self.baseline_hits} rate {baseline_rate}"
        )


class CategorySummary:
    def __init__(self, name, members, units, revenue, baskets):
        self.name = name
        self.products = len(members)
        self.units = sum(units[member] for member in members)
        self.revenue = sum(revenue[member] for member in members)
        self.baskets = baskets


class Group:
    def __init__(self, members, edges, core, revenue):
        self.members = members
        self.edges = edges
        self.core = core
        self.revenue = revenue


class Substitute:
    def __init__(self, first, second, together, counts, total):
        self.first = first
        self.second = second
        self.together = together
        self.expected = Fraction(counts[first] * counts[second], total)
        self.lift = lift_of(total, together, counts[first], counts[second])


class Trend:
    def __init__(self, name, series, threshold):
        weeks = len(series)
        week_sum = sum(range(1, weeks + 1))
        square_sum = sum(week * week for week in range(1, weeks + 1))
        weighted_sum = sum(week * value for week, value in enumerate(series, 1))
        self.name = name
        self.units = sum(series)
        self.slope = Fraction(
            weeks * weighted_sum - week_sum * self.units, weeks * square_sum - week_sum * week_sum
        )
        self.relative = None
        self.verdict = "NONE"
        if self.units > 0:
            self.relative = self.slope * weeks / self.units
            if self.relative >= threshold:
                self.verdict = "RISING"
            elif self.relative <= -threshold:
                self.verdict = "FALLING"
            else:
                self.verdict = "FLAT"


class CustomerSummary:
    def __init__(self, customer, baskets, history, products):
        days = sorted({basket.day for basket in baskets})
        self.customer = customer
        self.baskets = len(baskets)
        self.days = len(days)
        self.first = days[0]
        self.last = days[-1]
        self.products = len(history)
        self.units = 0
        self.revenue = 0
        category_units = {}
        for basket in baskets:
            for name, count in basket.counts.items():
                product = products[name]
                self.units += count
                self.revenue += count * product.price
                category_units[product.category] = category_units.get(product.category, 0) + count
        self.average = self.revenue // self.baskets
        self.favorite = min(category_units, key=lambda name: (-category_units[name], name))
        self.segment = None
        self.offer = []


class MarketAnalysis:
    def __init__(self, params, data):
        self.params = params
        self.data = data
        self.products = data.products
        self.product_names = sorted(data.products)
        self.taxonomy = {name: product.category for name, product in data.products.items()}
        self.categories = sorted(set(self.taxonomy.values()))
        self.baskets = data.baskets()
        self.item_sets = [basket.products() for basket in self.baskets]
        self.total = len(self.baskets)
        self.customer_baskets = {}
        for basket in self.baskets:
            self.customer_baskets.setdefault(basket.customer, []).append(basket)
        self.customers = sorted(self.customer_baskets)
        self.histories = {
            customer: purchase_days(self.customer_baskets[customer]) for customer in self.customers
        }
        self.first_day = min(basket.day for basket in self.baskets)
        self.last_day = max(basket.day for basket in self.baskets)

    def run(self):
        self.analyze_frequent()
        self.analyze_categories()
        self.analyze_sequences()
        self.analyze_validation()
        self.analyze_products()
        self.analyze_groups()
        self.analyze_substitutes()
        self.analyze_trends()
        self.analyze_customers()

    def analyze_frequent(self):
        params = self.params
        self.main = run_apriori(
            self.item_sets, self.product_names, params.min_support, params.max_size
        )
        self.frequent = self.main.supports
        self.counts = self.main.single_counts
        pattern_base = [(sorted(items), 1) for items in self.item_sets]
        self.growth = fp_growth(pattern_base, params.min_support, params.max_size)
        self.classify_itemsets()
        self.main_rules = make_rules(self.frequent, self.total, params)
        self.pairs = sorted(itemset for itemset in self.frequent if len(itemset) == 2)

    def classify_itemsets(self):
        closed = set(self.frequent)
        maximal = set(self.frequent)
        generators = []
        for itemset, count in self.frequent.items():
            subsets = one_smaller_subsets(itemset)
            if all(support_in(self.frequent, self.total, subset) > count for subset in subsets):
                generators.append(itemset)
            for subset in subsets:
                if subset:
                    maximal.discard(subset)
                    if self.frequent[subset] == count:
                        closed.discard(subset)
        self.closed = sorted(closed, key=size_order)
        self.maximal = sorted(maximal, key=size_order)
        self.generators = sorted(generators, key=size_order)

    def analyze_categories(self):
        params = self.params
        self.extended_sets = [extended_basket(items, self.taxonomy) for items in self.item_sets]
        self.category_run = run_apriori(
            self.extended_sets, self.product_names + self.categories,
            params.category_min_support, params.max_size, self.taxonomy,
        )
        self.category_rules = make_rules(
            self.category_run.supports, self.total, params, set(self.categories)
        )

    def analyze_sequences(self):
        self.buyers = dict.fromkeys(self.product_names, 0)
        gaps = {}
        for customer in self.customers:
            history = self.histories[customer]
            for first in sorted(history):
                self.buyers[first] += 1
                for second in sorted(history):
                    if history[first][0] < history[second][-1]:
                        gap = shortest_gap(history[first], history[second])
                        gaps.setdefault((first, second), []).append(gap)
        self.sequence_pairs = len(gaps)
        self.sequences = [
            Sequence(first, second, found, self.buyers, len(self.customers))
            for (first, second), found in gaps.items()
            if len(found) >= self.params.sequence_min_support
        ]
        self.sequences.sort(
            key=lambda sequence: (
                -sequence.customers, -sequence.confidence, sequence.first, sequence.second
            )
        )
        self.analyze_repeats()

    def analyze_repeats(self):
        intervals = {}
        repeaters = {}
        for customer in self.customers:
            for product, days in self.histories[customer].items():
                if len(days) < 2:
                    continue
                repeaters[product] = repeaters.get(product, 0) + 1
                found = intervals.setdefault(product, [])
                for index in range(1, len(days)):
                    found.append(days[index] - days[index - 1])
        self.repeats = [
            Repeat(product, repeaters[product], intervals[product]) for product in intervals
        ]
        self.repeats.sort(key=lambda repeat: (repeat.mean, repeat.product))

    def analyze_validation(self):
        params = self.params
        split_day = params.split_day
        train_sets = [basket.products() for basket in self.baskets if basket.day <= split_day]
        test_sets = [basket.products() for basket in self.baskets if basket.day > split_day]
        self.train_total = len(train_sets)
        self.test_total = len(test_sets)
        self.train_run = run_apriori(
            train_sets, self.product_names, params.train_min_support, params.max_size
        )
        self.train_rules = make_rules(self.train_run.supports, self.train_total, params).rules
        needed = []
        for rule in self.train_rules:
            needed.extend((rule.antecedent, rule.consequent, rule.itemset))
        test_counts = count_supports(test_sets, needed)
        self.checks = [
            RuleCheck(rule, test_counts, self.test_total, params) for rule in self.train_rules
        ]
        test_run = run_apriori(
            test_sets, self.product_names, params.test_min_support, params.max_size
        )
        test_rules = make_rules(test_run.supports, self.test_total, params).rules
        known = {(rule.antecedent, rule.consequent) for rule in self.train_rules}
        self.emerging = [
            rule for rule in test_rules if (rule.antecedent, rule.consequent) not in known
        ]
        self.evaluate(test_sets)

    def evaluate(self, test_sets):
        limit = self.params.recommend_top
        train_counts = self.train_run.single_counts
        popularity = sorted(self.product_names, key=lambda name: (-train_counts[name], name))
        self.tallies = {}
        self.overall = Tally()
        self.held_out = dict.fromkeys(self.product_names, 0)
        self.held_hits = dict.fromkeys(self.product_names, 0)
        for items in test_sets:
            if len(items) < 2:
                continue
            tally = self.tallies.setdefault(len(items), Tally())
            for product in sorted(items):
                held = items - {product}
                suggestion = recommend(held, rule_candidates(self.train_rules, held), limit)
                baseline = recommend(held, popularity, limit)
                tally.add(product, suggestion, baseline)
                self.overall.add(product, suggestion, baseline)
                self.held_out[product] += 1
                if product in suggestion:
                    self.held_hits[product] += 1

    def pair_lift(self, pair):
        first, second = pair
        return lift_of(self.total, self.frequent[pair], self.counts[first], self.counts[second])

    def partner_text(self, name):
        pairs = [pair for pair in self.pairs if name in pair]
        if not pairs:
            return "none"
        partner = min(
            pairs,
            key=lambda pair: (-self.pair_lift(pair), -self.frequent[pair], other_item(pair, name)),
        )
        return f"{other_item(partner, name)} {fraction_text(self.pair_lift(partner))}"

    def strongest_text(self, name):
        for rule in self.main_rules.rules:
            if name in rule.antecedent or name in rule.consequent:
                return f"{rule.rank} {rule_arrow(rule)}"
        return "none"

    def analyze_products(self):
        self.units = dict.fromkeys(self.product_names, 0)
        for basket in self.baskets:
            for product, count in basket.counts.items():
                self.units[product] += count
        self.revenue = {
            name: self.units[name] * self.products[name].price for name in self.product_names
        }
        self.total_revenue = sum(self.revenue.values())
        self.category_summaries = []
        for category in self.categories:
            members = [name for name in self.product_names if self.taxonomy[name] == category]
            basket_count = self.category_run.single_counts[category]
            summary = CategorySummary(category, members, self.units, self.revenue, basket_count)
            self.category_summaries.append(summary)
        self.category_summaries.sort(key=lambda summary: (-summary.revenue, summary.name))

    def analyze_groups(self):
        neighbors = {name: [] for name in self.product_names}
        edges = []
        for pair in self.pairs:
            if self.pair_lift(pair) >= self.params.group_min_lift:
                first, second = pair
                edges.append(pair)
                neighbors[first].append(second)
                neighbors[second].append(first)
        visited = set()
        self.groups = []
        for name in self.product_names:
            if name in visited or not neighbors[name]:
                continue
            members = []
            stack = [name]
            visited.add(name)
            while stack:
                current = stack.pop()
                members.append(current)
                for neighbor in neighbors[current]:
                    if neighbor not in visited:
                        visited.add(neighbor)
                        stack.append(neighbor)
            members.sort()
            edge_count = sum(1 for first, second in edges if first in members)
            core = min(
                members, key=lambda member: (-len(neighbors[member]), -self.counts[member], member)
            )
            revenue = sum(self.revenue[member] for member in members)
            self.groups.append(Group(members, edge_count, core, revenue))
        self.groups.sort(key=lambda group: (-len(group.members), group.members[0]))

    def analyze_substitutes(self):
        params = self.params
        singles = [itemset[0] for itemset in self.main.levels[0].itemsets]
        pairs = []
        for index, first in enumerate(singles):
            for second in singles[index + 1:]:
                expected = self.counts[first] * self.counts[second]
                if expected >= params.negative_min_expected * self.total:
                    pairs.append((first, second))
        together = count_supports(self.item_sets, pairs)
        self.substitutes = []
        for pair in pairs:
            first, second = pair
            substitute = Substitute(first, second, together[pair], self.counts, self.total)
            if substitute.lift <= params.negative_max_lift:
                self.substitutes.append(substitute)
        self.substitutes.sort(
            key=lambda substitute: (
                substitute.lift, -substitute.expected, substitute.first, substitute.second
            )
        )

    def analyze_trends(self):
        self.week_count = week_of(self.last_day)
        self.week_baskets = [0] * self.week_count
        self.week_units = [0] * self.week_count
        week_customers = [set() for _ in range(self.week_count)]
        self.category_series = {category: [0] * self.week_count for category in self.categories}
        self.product_series = {name: [0] * self.week_count for name in self.product_names}
        for basket in self.baskets:
            week = week_of(basket.day) - 1
            self.week_baskets[week] += 1
            self.week_units[week] += basket.units()
            week_customers[week].add(basket.customer)
            for product, count in basket.counts.items():
                self.product_series[product][week] += count
                self.category_series[self.taxonomy[product]][week] += count
        self.week_customers = [len(customers) for customers in week_customers]
        threshold = self.params.trend_threshold
        trends = [Trend(name, series, threshold) for name, series in self.category_series.items()]
        for name, series in self.product_series.items():
            trends.append(Trend(name, series, threshold))
        rated = [trend for trend in trends if trend.relative is not None]
        rated.sort(key=lambda trend: (-trend.relative, trend.name))
        unrated = [trend for trend in trends if trend.relative is None]
        unrated.sort(key=lambda trend: trend.name)
        self.trends = rated + unrated

    def analyze_customers(self):
        self.customer_summaries = []
        for customer in self.customers:
            history = self.histories[customer]
            baskets = self.customer_baskets[customer]
            summary = CustomerSummary(customer, baskets, history, self.products)
            summary.segment = segment_of(summary, self.last_day)
            held = set(history)
            candidates = rule_candidates(self.main_rules.rules, held)
            summary.offer = recommend(held, candidates, self.params.recommend_top)
            self.customer_summaries.append(summary)

    def summary_lines(self):
        data = self.data
        sizes = [len(items) for items in self.item_sets]
        largest = max(sizes)
        average = fraction_text(Fraction(sum(sizes), self.total))
        multi_day = sum(1 for summary in self.customer_summaries if summary.days >= 2)
        lines = [f"ERROR {error}" for error in data.errors]
        lines.append(
            f"ITEMS rows {data.item_rows} adopted {len(self.products)} "
            f"categories {len(self.categories)}"
        )
        lines.append(
            f"TRANSACTIONS lines {data.transaction_lines} adopted {data.adopted} "
            f"rejected {data.rejected} duplicates {data.duplicates} "
            f"transactions {len(data.transactions)} empty {len(data.transactions) - self.total}"
        )
        lines.append(
            f"BASKETS count {self.total} customers {len(self.customers)} "
            f"first_day {self.first_day} last_day {self.last_day} "
            f"average_size {average} largest {largest}"
        )
        for size in range(1, largest + 1):
            count = sizes.count(size)
            lines.append(f"SIZE {size} baskets {count} share {percent_text(count, self.total)}")
        lines.append(
            f"FREQUENT itemsets {len(self.frequent)} closed {len(self.closed)} "
            f"maximal {len(self.maximal)} generators {len(self.generators)} "
            f"levels {len(self.main.levels)}"
        )
        lines.extend(self.growth_lines())
        rules = self.main_rules
        lines.append(
            f"RULES generated {rules.generated} passed {len(rules.rules)} "
            f"productive {rules.productive}"
        )
        for level in self.category_run.levels:
            lines.append(
                f"CATEGORY_LEVEL {level.number} candidates {level.candidates} "
                f"taxonomy {level.excluded} pruned {level.pruned} counted {level.counted} "
                f"frequent {len(level.itemsets)}"
            )
        rules = self.category_rules
        lines.append(
            f"CATEGORY_RULES itemsets {len(self.category_run.supports)} "
            f"generated {rules.generated} passed {len(rules.rules)} productive {rules.productive}"
        )
        lines.append(
            f"SEQUENCES customers {len(self.customers)} multi_day {multi_day} "
            f"pairs {self.sequence_pairs} frequent {len(self.sequences)}"
        )
        return lines

    def growth_lines(self):
        growth = self.growth
        found = set(growth.itemsets)
        expected = set(self.frequent.items())
        status = "MATCH" if found == expected else "MISMATCH"
        lines = [
            f"FPGROWTH header {growth.header_count} nodes {growth.node_count} "
            f"conditional_trees {growth.conditional_trees} "
            f"conditional_nodes {growth.conditional_nodes} "
            f"itemsets {len(growth.itemsets)} {status}"
        ]
        if status == "MISMATCH":
            for itemset, count in sorted(expected - found, key=lambda pair: size_order(pair[0])):
                lines.append(f"ONLY_APRIORI {itemset_text(itemset)} {count}")
            for itemset, count in sorted(found - expected, key=lambda pair: size_order(pair[0])):
                lines.append(f"ONLY_FPGROWTH {itemset_text(itemset)} {count}")
        return lines

    def itemset_lines(self):
        lines = []
        for level in self.main.levels:
            lines.append(
                f"LEVEL {level.number} candidates {level.candidates} pruned {level.pruned} "
                f"counted {level.counted} frequent {len(level.itemsets)}"
            )
            for itemset in level.itemsets:
                lines.append(f"{itemset_text(itemset)} {self.frequent[itemset]}")
        return lines

    def closed_maximal_lines(self):
        lines = []
        sections = (
            ("CLOSED", self.closed), ("MAXIMAL", self.maximal), ("GENERATOR", self.generators)
        )
        for label, itemsets in sections:
            for itemset in itemsets:
                lines.append(f"{label} {itemset_text(itemset)} {self.frequent[itemset]}")
        return lines

    def sequence_lines(self):
        lines = []
        for rank, sequence in enumerate(self.sequences, 1):
            lines.append(
                f"SEQ {rank} {sequence.first} -> {sequence.second} "
                f"customers {sequence.customers} base {sequence.base} "
                f"confidence {fraction_text(sequence.confidence)} "
                f"lift {fraction_text(sequence.lift)} gap {fraction_text(sequence.gap)}"
            )
        for repeat in self.repeats:
            lines.append(
                f"REPEAT {repeat.product} customers {repeat.customers} intervals {repeat.count} "
                f"min {repeat.minimum} max {repeat.maximum} mean {fraction_text(repeat.mean)} "
                f"median {fraction_text(repeat.median)}"
            )
        return lines

    def validation_lines(self):
        lines = []
        for check in self.checks:
            rule = check.rule
            measured = "confidence - lift -"
            if check.verdict != "UNSEEN":
                confidence = fraction_text(check.confidence)
                measured = f"confidence {confidence} lift {fraction_text(check.lift)}"
            lines.append(
                f"RULE {rule.rank} {rule_arrow(rule)} train {rule.count} "
                f"confidence {fraction_text(rule.confidence)} lift {fraction_text(rule.lift)} "
                f"test {check.together} of {check.antecedent_count} {measured} {check.verdict}"
            )
        for rule in self.emerging:
            lines.append(
                f"EMERGING {rule.rank} {rule_arrow(rule)} test {rule.count} "
                f"confidence {fraction_text(rule.confidence)} lift {fraction_text(rule.lift)}"
            )
        verdicts = [check.verdict for check in self.checks]
        lines.append(
            f"VALIDATION train {self.train_total} test {self.test_total} "
            f"itemsets {len(self.train_run.supports)} rules {len(self.train_rules)} "
            f"hold {verdicts.count('HOLD')} fail {verdicts.count('FAIL')} "
            f"unseen {verdicts.count('UNSEEN')} emerging {len(self.emerging)}"
        )
        for size in sorted(self.tallies):
            lines.append(f"RECOMMEND size {size} {self.tallies[size].describe()}")
        lines.append(f"RECOMMEND total {self.overall.describe()}")
        return lines

    def item_lines(self):
        lines = []
        ranked = sorted(self.product_names, key=lambda name: (-self.revenue[name], name))
        for rank, name in enumerate(ranked, 1):
            product = self.products[name]
            revenue = self.revenue[name]
            baskets = self.counts[name]
            containing = sum(1 for itemset in self.frequent if name in itemset)
            lines.append(
                f"ITEM {rank} {name} {product.category} price {money_text(product.price)} "
                f"units {self.units[name]} revenue {money_text(revenue)} "
                f"share {percent_text(revenue, self.total_revenue)} baskets {baskets} "
                f"support {fraction_text(Fraction(baskets, self.total))} "
                f"customers {self.buyers[name]} itemsets {containing} "
                f"heldout {self.held_out[name]} hits {self.held_hits[name]} "
                f"partner {self.partner_text(name)} best {self.strongest_text(name)}"
            )
        for summary in self.category_summaries:
            lines.append(
                f"CATEGORY {summary.name} items {summary.products} units {summary.units} "
                f"revenue {money_text(summary.revenue)} "
                f"share {percent_text(summary.revenue, self.total_revenue)} "
                f"baskets {summary.baskets} "
                f"support {fraction_text(Fraction(summary.baskets, self.total))}"
            )
        lines.append(
            f"TOTAL items {len(self.products)} units {sum(self.units.values())} "
            f"revenue {money_text(self.total_revenue)} baskets {self.total} "
            f"customers {len(self.customers)}"
        )
        lines.extend(self.group_lines())
        by_support = sorted(self.product_names, key=lambda name: (-self.counts[name], name))
        top_products = by_support[:self.params.matrix_size]
        lines.extend(self.matrix_lines("MATRIX", top_products, self.counts, self.item_sets))
        category_counts = self.category_run.single_counts
        top_categories = sorted(self.categories, key=lambda name: (-category_counts[name], name))
        lines.extend(self.matrix_lines(
            "CATEGORY_MATRIX", top_categories, category_counts, self.extended_sets
        ))
        return lines

    def group_lines(self):
        lines = []
        for number, group in enumerate(self.groups, 1):
            lines.append(
                f"GROUP {number} items {len(group.members)} edges {group.edges} "
                f"core {group.core} revenue {money_text(group.revenue)} "
                f"share {percent_text(group.revenue, self.total_revenue)} "
                f"members {itemset_text(group.members)}"
            )
        for substitute in self.substitutes:
            lines.append(
                f"SUBSTITUTE {substitute.first} {substitute.second} "
                f"count {substitute.together} expected {fraction_text(substitute.expected)} "
                f"lift {fraction_text(substitute.lift)}"
            )
        return lines

    def matrix_lines(self, label, items, counts, item_sets):
        pairs = []
        for index, first in enumerate(items):
            for second in items[index + 1:]:
                pairs.append(tuple(sorted((first, second))))
        together = count_supports(item_sets, pairs)
        lines = [
            f"{label} {index} {item} baskets {counts[item]}" for index, item in enumerate(items, 1)
        ]
        indices = range(1, len(items) + 1)
        lines.append(" " * INDEX_WIDTH + "".join(f"{index:>{CELL_WIDTH}}" for index in indices))
        for row, first in enumerate(items, 1):
            cells = []
            for column, second in enumerate(items, 1):
                if row == column:
                    cells.append("-")
                    continue
                pair = tuple(sorted((first, second)))
                value = MATRIX_SCALE * len(item_sets) * together[pair]
                cells.append(str(value // (counts[first] * counts[second])))
            row_text = "".join(f"{cell:>{CELL_WIDTH}}" for cell in cells)
            lines.append(f"{row:>{INDEX_WIDTH}}{row_text}")
        return lines

    def trend_lines(self):
        lines = [
            table_row("WEEK", range(1, self.week_count + 1)),
            table_row("BASKETS", self.week_baskets),
            table_row("UNITS", self.week_units),
            table_row("CUSTOMERS", self.week_customers),
        ]
        for category in self.categories:
            lines.append(table_row(category, self.category_series[category]))
        for name in self.product_names:
            lines.append(table_row(name, self.product_series[name]))
        for trend in self.trends:
            relative = "-" if trend.relative is None else fraction_text(trend.relative)
            lines.append(
                f"TREND {trend.name} units {trend.units} slope {fraction_text(trend.slope)} "
                f"relative {relative} {trend.verdict}"
            )
        return lines

    def customer_lines(self):
        lines = []
        for summary in self.customer_summaries:
            offer = itemset_text(summary.offer) if summary.offer else "none"
            lines.append(
                f"CUSTOMER {summary.customer} baskets {summary.baskets} days {summary.days} "
                f"first {summary.first} last {summary.last} items {summary.products} "
                f"units {summary.units} revenue {money_text(summary.revenue)} "
                f"average {money_text(summary.average)} favorite {summary.favorite} "
                f"segment {summary.segment} offer {offer}"
            )
        for segment in SEGMENTS:
            members = [
                summary for summary in self.customer_summaries if summary.segment == segment
            ]
            revenue = sum(summary.revenue for summary in members)
            lines.append(
                f"SEGMENT {segment} customers {len(members)} revenue {money_text(revenue)} "
                f"share {percent_text(revenue, self.total_revenue)}"
            )
        return lines

    def write(self):
        write_report("summary.txt", self.summary_lines())
        write_report("itemsets.txt", self.itemset_lines())
        write_report("closed_maximal.txt", self.closed_maximal_lines())
        write_report("rules.csv", rules_csv(self.main_rules.rules))
        write_report("category_rules.csv", rules_csv(self.category_rules.rules))
        write_report("sequences.txt", self.sequence_lines())
        write_report("validation.txt", self.validation_lines())
        write_report("items_report.txt", self.item_lines())
        write_report("trends.txt", self.trend_lines())
        write_report("customers.txt", self.customer_lines())


def main():
    params = read_params(os.path.join(INPUT_DIR, "params.txt"))
    data = Dataset()
    data.load_items(os.path.join(INPUT_DIR, "items.csv"))
    data.load_transactions(os.path.join(INPUT_DIR, "transactions.csv"))
    analysis = MarketAnalysis(params, data)
    analysis.run()
    analysis.write()


if __name__ == "__main__":
    main()
