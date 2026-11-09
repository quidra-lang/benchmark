from functools import cmp_to_key
import os

from dataset import Row, load_dataset
from evaluation import (
    DEFAULT, PRIMARY, SURROGATE, PrunedTree, average, classification_lines,
    fraction_text, ratio_text, real_text,
)
from impurity import class_counts, impurity_decrease, is_greater, majority, square_sum
from pruning import cost_complexity_sequence, reduced_error_pruning
from tree_builder import TreeBuilder, half_text


INPUT_DIRECTORY = "input"
OUTPUT_DIRECTORY = "output"
MINSTD_MULTIPLIER = 48271
MINSTD_MODULUS = 2147483647
MCNEMAR_SCALE = 1000
MCNEMAR_CRITICAL = 3841
COMPARED_MODELS = ("grown", "depth", "cost_complexity", "bagging")
AUC_MODELS = ("grown", "pruned", "bagging")
METHOD_MARKS = {PRIMARY: "", SURROGATE: " [surrogate]", DEFAULT: " [default]"}


class Minstd:
    def __init__(self, seed):
        self.state = seed

    def draw(self):
        self.state = MINSTD_MULTIPLIER * self.state % MINSTD_MODULUS
        return self.state


class Condition:
    def __init__(self, attribute):
        self.attribute = attribute
        self.lower = None
        self.upper = None
        self.equal = None
        self.excluded = set()

    def add(self, split, left):
        if self.attribute.integer:
            if left:
                self.upper = split.point if self.upper is None else min(self.upper, split.point)
            else:
                self.lower = split.point if self.lower is None else max(self.lower, split.point)
        elif left:
            self.equal = split.point
        else:
            self.excluded.add(split.point)

    def text(self):
        name = self.attribute.name
        if self.attribute.integer:
            if self.lower is not None and self.upper is not None:
                return f"{half_text(self.lower)} < {name} <= {half_text(self.upper)}"
            if self.lower is not None:
                return f"{name} > {half_text(self.lower)}"
            return f"{name} <= {half_text(self.upper)}"
        if self.equal is not None:
            return f"{name} = {self.attribute.values[self.equal]}"
        names = [self.attribute.values[value] for value in sorted(self.excluded)]
        if len(names) == 1:
            return f"{name} != {names[0]}"
        return f"{name} not in {{{','.join(names)}}}"

    def holds(self, row):
        value = row.value(self.attribute)
        if value is None:
            return False
        if self.attribute.integer:
            above = self.lower is None or 2 * value > self.lower
            below = self.upper is None or 2 * value <= self.upper
            return above and below
        if self.equal is not None:
            return value == self.equal
        return value not in self.excluded


class Rule:
    def __init__(self, number, leaf, conditions):
        self.number = number
        self.leaf = leaf
        self.label = leaf.prediction
        self.conditions = conditions
        self.general = conditions
        self.removed = []


class DepthResult:
    def __init__(self, depth, tree, cv_correct):
        self.depth = depth
        self.tree = tree
        self.cv_correct = cv_correct


class Bag:
    def __init__(self, tree, distinct, out_of_bag, correct):
        self.tree = tree
        self.distinct = distinct
        self.out_of_bag = out_of_bag
        self.correct = correct


class Permutation:
    def __init__(self, attribute, counts, drop):
        self.attribute = attribute
        self.counts = counts
        self.drop = drop


def counts_text(counts):
    return " ".join(str(count) for count in counts)


def join_sections(sections):
    lines = []
    for section in sections:
        if lines:
            lines.append("")
        lines.extend(section)
    return lines


def simplify(steps, attributes):
    conditions = []
    for attribute in attributes:
        related = [(split, left) for split, left in steps if split.attribute is attribute]
        if related:
            condition = Condition(attribute)
            for split, left in related:
                condition.add(split, left)
            conditions.append(condition)
    return conditions


def conditions_text(conditions):
    if not conditions:
        return "true"
    return " and ".join(condition.text() for condition in conditions)


def coverage(conditions, rows, label):
    covered = [row for row in rows if all(condition.holds(row) for condition in conditions)]
    hits = sum(row.label == label for row in covered)
    return hits, len(covered)


def laplace(conditions, rows, label, class_count):
    hits, covered = coverage(conditions, rows, label)
    return hits + 1, covered + class_count


def generalize(conditions, rows, label, class_count):
    current = list(conditions)
    removed = []
    while current:
        estimate = laplace(current, rows, label, class_count)
        best_index = None
        best = None
        for index in range(len(current)):
            trial = laplace(current[:index] + current[index + 1:], rows, label, class_count)
            if best is None or is_greater(trial, best):
                best_index = index
                best = trial
        if is_greater(estimate, best):
            break
        removed.append(current[best_index].attribute.name)
        del current[best_index]
    return current, removed


def with_value(row, attribute, value):
    values = list(row.values)
    values[attribute.index] = value
    return Row(row.ident, values, row.label)


def compare_candidates(first, second):
    if is_greater(first.value(), second.value()):
        return -1
    if is_greater(second.value(), first.value()):
        return 1
    return 0


def auc_counts(scores, labels, positive):
    positives = [score[positive] for score, label in zip(scores, labels) if label == positive]
    negatives = [score[positive] for score, label in zip(scores, labels) if label != positive]
    wins = 0
    for first in positives:
        for second in negatives:
            if is_greater(first, second):
                wins += 2
            elif not is_greater(second, first):
                wins += 1
    return wins, 2 * len(positives) * len(negatives)


class Analysis:
    def __init__(self, data):
        self.data = data
        self.attributes = data.attributes
        self.classes = data.classes
        self.settings = data.settings
        self.train = data.train
        self.validation = data.validation
        self.test = data.test
        self.builder = TreeBuilder(data.attributes, len(data.classes), data.settings)
        self.grown = PrunedTree(self.builder.grow(self.train))
        self.pruned, self.decisions = reduced_error_pruning(self.grown.root, self.validation)
        self.rules = self.build_rules()
        self.bounds = self.fold_bounds()
        self.fold_trees = [
            PrunedTree(self.builder.grow(self.fold_training(fold)))
            for fold in range(1, self.settings.folds + 1)
        ]
        self.depth_results = self.depth_selection()
        self.selected_depth = self.select_depth()
        self.sequence = cost_complexity_sequence(self.grown.root)
        self.selected_index = self.select_subtree()
        self.bags, self.oob_votes = self.bagging()
        self.test_votes = self.bagging_votes()
        self.predictions = self.model_predictions()

    def class_name(self, label):
        return self.classes[label]

    def accuracy(self, tree, rows):
        return ratio_text(tree.correct_count(rows), len(rows))

    def build_rules(self):
        rules = []
        self.collect_rules(self.pruned.root, [], rules)
        for rule in rules:
            rule.general, rule.removed = generalize(
                rule.conditions, self.validation, rule.label, len(self.classes)
            )
        return rules

    def collect_rules(self, node, steps, rules):
        if self.pruned.is_leaf(node):
            rules.append(Rule(len(rules) + 1, node, simplify(steps, self.attributes)))
            return
        self.collect_rules(node.left, steps + [(node.split, True)], rules)
        self.collect_rules(node.right, steps + [(node.split, False)], rules)

    def fold_bounds(self):
        size = len(self.train)
        folds = self.settings.folds
        return [fold * size // folds for fold in range(folds + 1)]

    def fold_rows(self, fold):
        return self.train[self.bounds[fold - 1]:self.bounds[fold]]

    def fold_training(self, fold):
        return self.train[:self.bounds[fold - 1]] + self.train[self.bounds[fold]:]

    def limited(self, tree, depth):
        cut = {node.number for node in tree.internal_nodes() if node.depth == depth}
        return PrunedTree(tree.root, cut)

    def depth_selection(self):
        results = []
        for depth in range(self.settings.max_depth + 1):
            cv_correct = 0
            for fold, tree in enumerate(self.fold_trees, 1):
                cv_correct += self.limited(tree, depth).correct_count(self.fold_rows(fold))
            results.append(DepthResult(depth, self.limited(self.grown, depth), cv_correct))
        return results

    def select_depth(self):
        selected = self.depth_results[0]
        for result in self.depth_results[1:]:
            if result.cv_correct > selected.cv_correct:
                selected = result
        return selected

    def validation_errors(self, tree):
        return len(self.validation) - tree.correct_count(self.validation)

    def select_subtree(self):
        errors = [self.validation_errors(step.tree) for step in self.sequence]
        selected = 0
        for index, count in enumerate(errors):
            if count <= errors[selected]:
                selected = index
        return selected

    def bagging(self):
        generator = Minstd(self.settings.bag_seed)
        size = len(self.train)
        bags = []
        votes = [[0] * len(self.classes) for _ in self.train]
        for _ in range(self.settings.bag_trees):
            indices = [generator.draw() % size for _ in range(size)]
            tree = PrunedTree(self.builder.grow([self.train[index] for index in indices]))
            sampled = set(indices)
            out_of_bag = [index for index in range(size) if index not in sampled]
            correct = 0
            for index in out_of_bag:
                row = self.train[index]
                prediction = tree.predict(row)
                votes[index][prediction] += 1
                if prediction == row.label:
                    correct += 1
            bags.append(Bag(tree, len(sampled), len(out_of_bag), correct))
        return bags, votes

    def bagging_votes(self):
        votes = [[0] * len(self.classes) for _ in self.test]
        for bag in self.bags:
            for row, row_votes in zip(self.test, votes):
                row_votes[bag.tree.predict(row)] += 1
        return votes

    def model_predictions(self):
        models = {
            "grown": self.grown,
            "pruned": self.pruned,
            "depth": self.selected_depth.tree,
            "cost_complexity": self.sequence[self.selected_index].tree,
        }
        predictions = {
            name: [tree.predict(row) for row in self.test] for name, tree in models.items()
        }
        predictions["bagging"] = [majority(votes) for votes in self.test_votes]
        return predictions

    def scores(self, model):
        if model == "bagging":
            trees = self.settings.bag_trees
            return [[(count, trees) for count in votes] for votes in self.test_votes]
        tree = self.grown if model == "grown" else self.pruned
        scores = []
        for row in self.test:
            leaf = tree.leaf_of(row)
            scores.append([(count, leaf.size) for count in leaf.counts])
        return scores

    def node_lines(self, tree, node, condition, lines):
        line = (
            f"{'  ' * node.depth}{node.number} {condition}"
            f" n {node.size} counts {counts_text(node.counts)}"
        )
        if tree.is_leaf(node):
            lines.append(f"{line} leaf {self.class_name(node.prediction)}")
            return
        lines.append(line)
        self.node_lines(tree, node.left, node.split.left_condition(), lines)
        self.node_lines(tree, node.right, node.split.right_condition(), lines)

    def tree_lines(self, tree):
        lines = []
        self.node_lines(tree, tree.root, "root", lines)
        lines.append("")
        nodes = tree.preorder()
        leaves = tree.leaves()
        depth = tree.depth()
        errors = ratio_text(tree.training_errors(), len(self.train))
        lines.append(f"nodes {len(nodes)} leaves {len(leaves)} depth {depth} errors {errors}")
        for level in range(depth + 1):
            level_nodes = [node for node in nodes if node.depth == level]
            level_leaves = [node for node in leaves if node.depth == level]
            rows = sum(node.size for node in level_leaves)
            level_errors = sum(node.errors for node in level_leaves)
            lines.append(
                f"level {level} nodes {len(level_nodes)} leaves {len(level_leaves)}"
                f" rows {rows} errors {level_errors}"
            )
        return lines

    def root_candidate_lines(self):
        size = len(self.train)
        counts = self.grown.root.counts
        total_square = square_sum(counts)
        found = []
        for attribute in self.attributes:
            candidate = self.builder.best_split(self.train, [attribute])
            if candidate is not None:
                found.append(candidate)
        found.sort(key=cmp_to_key(compare_candidates))
        lines = [f"root candidates n {size} counts {counts_text(counts)}"]
        for rank, candidate in enumerate(found, 1):
            numerator, denominator = candidate.value()
            gain = numerator / denominator / size - total_square / (size * size)
            lines.append(
                f"{rank} {candidate.split.left_condition()} left {candidate.left_size}"
                f" right {candidate.right_size} gain {real_text(gain, 6)}"
            )
        return lines

    def surrogate_lines(self):
        lines = ["surrogates"]
        for node in self.grown.internal_nodes():
            listed = " ; ".join(
                f"{surrogate.split.left_condition()} {surrogate.direction}"
                f" {surrogate.score}/{node.size}"
                for surrogate in node.surrogates
            )
            lines.append(
                f"node {node.number} split {node.split.left_condition()}"
                f" default {node.default} surrogates {listed or 'none'}"
            )
        return lines

    def tree_file(self):
        return join_sections([
            self.root_candidate_lines(),
            self.tree_lines(self.grown),
            self.surrogate_lines(),
        ])

    def pruned_tree_file(self):
        lines = [f"reduced_error_pruning validation {len(self.validation)}"]
        for decision in self.decisions:
            verdict = "pruned" if decision.pruned else "kept"
            lines.append(
                f"node {decision.node.number} depth {decision.node.depth} rows {decision.rows}"
                f" leaf {decision.leaf_error} subtree {decision.subtree_error} {verdict}"
            )
        pruned = sum(decision.pruned for decision in self.decisions)
        examined = len(self.decisions)
        lines.append(f"examined {examined} pruned {pruned} kept {examined - pruned}")
        lines.append("")
        lines.extend(self.tree_lines(self.pruned))
        return lines

    def predictions_file(self):
        lines = ["id,predicted,actual,grown,leaf,path,missing"]
        for row in self.test:
            path, methods = self.pruned.route(row)
            leaf = path[-1]
            fields = [
                row.ident,
                self.class_name(leaf.prediction),
                self.class_name(row.label),
                self.class_name(self.grown.predict(row)),
                str(leaf.number),
                "-".join(str(node.number) for node in path),
                str(sum(method != PRIMARY for method in methods)),
            ]
            lines.append(",".join(fields))
        return lines

    def rule_lines(self):
        reached = {rule.leaf.number: [] for rule in self.rules}
        for row in self.test:
            reached[self.pruned.leaf_of(row).number].append(row)
        lines = [f"rules {len(self.rules)}"]
        for rule in self.rules:
            rows = reached[rule.leaf.number]
            hits = sum(row.label == rule.label for row in rows)
            train = ratio_text(max(rule.leaf.counts), rule.leaf.size)
            lines.append(
                f"rule {rule.number} node {rule.leaf.number} if {conditions_text(rule.conditions)}"
                f" then {self.class_name(rule.label)} train {train}"
                f" test {ratio_text(hits, len(rows))}"
            )
        return lines

    def generalized_lines(self):
        lines = [f"generalized {len(self.rules)}"]
        for rule in self.rules:
            hits, covered = coverage(rule.general, self.validation, rule.label)
            test_hits, test_covered = coverage(rule.general, self.test, rule.label)
            removed = ",".join(rule.removed) if rule.removed else "none"
            estimate = fraction_text(hits + 1, covered + len(self.classes))
            lines.append(
                f"general {rule.number} if {conditions_text(rule.general)}"
                f" then {self.class_name(rule.label)} removed {removed} laplace {estimate}"
                f" validation {hits}/{covered} test {test_hits}/{test_covered}"
            )
        return lines

    def explanation(self, row):
        path, methods = self.pruned.route(row)
        parts = []
        for node, child, method in zip(path, path[1:], methods):
            parts.append(node.split.condition(child is node.left) + METHOD_MARKS[method])
        return "; ".join(parts) if parts else "root"

    def misclassified_lines(self):
        rule_numbers = {rule.leaf.number: rule.number for rule in self.rules}
        wrong = []
        for row in self.test:
            leaf = self.pruned.leaf_of(row)
            if leaf.prediction != row.label:
                wrong.append((row, leaf))
        lines = [f"misclassified {len(wrong)}"]
        for row, leaf in wrong:
            lines.append(
                f"{row.ident} actual {self.class_name(row.label)}"
                f" predicted {self.class_name(leaf.prediction)}"
                f" rule {rule_numbers[leaf.number]} path {self.explanation(row)}"
            )
        return lines

    def rules_file(self):
        return join_sections([
            self.rule_lines(),
            self.generalized_lines(),
            self.misclassified_lines(),
        ])

    def data_lines(self):
        class_count = len(self.classes)
        lines = [
            f"data train {len(self.train)} validation {len(self.validation)}"
            f" test {len(self.test)} attributes {len(self.attributes)}"
            f" classes {class_count} target {self.data.target}"
        ]
        train_counts = class_counts(self.train, class_count)
        validation_counts = class_counts(self.validation, class_count)
        test_counts = class_counts(self.test, class_count)
        for label, name in enumerate(self.classes):
            lines.append(
                f"class {name} train {train_counts[label]}"
                f" validation {validation_counts[label]} test {test_counts[label]}"
            )
        validation_missing = sum(row.missing_count() for row in self.validation)
        test_missing = sum(row.missing_count() for row in self.test)
        lines.append(f"missing validation {validation_missing} test {test_missing}")
        for attribute in self.attributes:
            validation_missing = sum(row.value(attribute) is None for row in self.validation)
            test_missing = sum(row.value(attribute) is None for row in self.test)
            lines.append(
                f"missing {attribute.name} validation {validation_missing} test {test_missing}"
            )
        return lines

    def summary_line(self, name, tree):
        return (
            f"{name} nodes {len(tree.preorder())} leaves {len(tree.leaves())}"
            f" depth {tree.depth()} train {self.accuracy(tree, self.train)}"
            f" validation {self.accuracy(tree, self.validation)}"
            f" test {self.accuracy(tree, self.test)}"
        )

    def model_evaluation(self, model):
        labels = [row.label for row in self.test]
        return classification_lines(
            f"{model} test", self.classes, labels, self.predictions[model]
        )

    def routing_lines(self):
        internal = self.pruned.internal_nodes()
        tallies = {node.number: {PRIMARY: 0, SURROGATE: 0, DEFAULT: 0} for node in internal}
        for row in self.test:
            path, methods = self.pruned.route(row)
            for node, method in zip(path, methods):
                tallies[node.number][method] += 1
        lines = ["routing pruned test"]
        for node in internal:
            tally = tallies[node.number]
            rows = tally[PRIMARY] + tally[SURROGATE] + tally[DEFAULT]
            lines.append(
                f"node {node.number} rows {rows} primary {tally[PRIMARY]}"
                f" surrogate {tally[SURROGATE]} default {tally[DEFAULT]}"
            )
        complete = [row for row in self.test if row.missing_count() == 0]
        incomplete = [row for row in self.test if row.missing_count() > 0]
        lines.append(
            f"complete rows {len(complete)} correct {self.accuracy(self.pruned, complete)}"
        )
        lines.append(
            f"incomplete rows {len(incomplete)} correct {self.accuracy(self.pruned, incomplete)}"
        )
        return lines

    def cross_validation_lines(self):
        lines = [f"cross_validation folds {self.settings.folds}"]
        total = 0
        for fold, tree in enumerate(self.fold_trees, 1):
            rows = self.fold_rows(fold)
            correct = tree.correct_count(rows)
            total += correct
            lines.append(
                f"fold {fold} rows {self.bounds[fold - 1] + 1}-{self.bounds[fold]}"
                f" leaves {len(tree.leaves())} correct {ratio_text(correct, len(rows))}"
            )
        lines.append(f"cv accuracy {ratio_text(total, len(self.train))}")
        return lines

    def depth_lines(self):
        lines = ["depth_selection"]
        for result in self.depth_results:
            tree = result.tree
            lines.append(
                f"depth {result.depth} leaves {len(tree.leaves())}"
                f" cv {ratio_text(result.cv_correct, len(self.train))}"
                f" train {self.accuracy(tree, self.train)}"
                f" validation {self.accuracy(tree, self.validation)}"
                f" test {self.accuracy(tree, self.test)}"
            )
        selected = self.selected_depth
        lines.append(
            f"selected depth {selected.depth} leaves {len(selected.tree.leaves())}"
            f" test {self.accuracy(selected.tree, self.test)}"
        )
        return lines

    def cost_complexity_lines(self):
        lines = ["cost_complexity"]
        size = len(self.train)
        for index, step in enumerate(self.sequence):
            numerator, denominator = step.alpha
            alpha = fraction_text(numerator, denominator * size, 6)
            lines.append(
                f"subtree {index} alpha {alpha} leaves {len(step.tree.leaves())}"
                f" train_errors {step.tree.training_errors()}"
                f" validation_errors {self.validation_errors(step.tree)}"
            )
        selected = self.sequence[self.selected_index].tree
        lines.append(
            f"selected subtree {self.selected_index} leaves {len(selected.leaves())}"
            f" test {self.accuracy(selected, self.test)}"
        )
        return lines

    def bagging_lines(self):
        lines = [f"bagging trees {self.settings.bag_trees} seed {self.settings.bag_seed}"]
        for number, bag in enumerate(self.bags, 1):
            lines.append(
                f"bag {number} distinct {bag.distinct} leaves {len(bag.tree.leaves())}"
                f" oob {ratio_text(bag.correct, bag.out_of_bag)}"
            )
        voted = 0
        hits = 0
        for row, votes in zip(self.train, self.oob_votes):
            if sum(votes) > 0:
                voted += 1
                if majority(votes) == row.label:
                    hits += 1
        unvoted = len(self.train) - voted
        lines.append(f"oob accuracy {ratio_text(hits, voted)} unvoted {unvoted}")
        lines.extend(self.model_evaluation("bagging"))
        return lines

    def correctness(self, model):
        return [
            prediction == row.label
            for row, prediction in zip(self.test, self.predictions[model])
        ]

    def mcnemar_lines(self):
        lines = ["mcnemar pruned test"]
        pruned = self.correctness("pruned")
        for model in COMPARED_MODELS:
            other = self.correctness(model)
            pruned_only = sum(first and not second for first, second in zip(pruned, other))
            other_only = sum(second and not first for first, second in zip(pruned, other))
            disagreements = pruned_only + other_only
            squared = max(0, abs(pruned_only - other_only) - 1) ** 2
            if disagreements == 0:
                statistic = "0/1 0.0000"
            else:
                statistic = fraction_text(squared, disagreements)
            significant = MCNEMAR_SCALE * squared > MCNEMAR_CRITICAL * disagreements
            lines.append(
                f"versus {model} b {pruned_only} c {other_only} statistic {statistic}"
                f" significant {'yes' if significant else 'no'}"
            )
        return lines

    def auc_lines(self):
        labels = [row.label for row in self.test]
        lines = []
        for model in AUC_MODELS:
            scores = self.scores(model)
            parts = ["auc", model]
            values = []
            for label, name in enumerate(self.classes):
                wins, pairs = auc_counts(scores, labels, label)
                parts.extend((name, fraction_text(wins, pairs)))
                if pairs > 0:
                    values.append(wins / pairs)
            parts.extend(("macro", real_text(average(values)) if values else "-"))
            lines.append(" ".join(parts))
        return lines

    def learning_curve_lines(self):
        lines = ["learning_curve"]
        for size in self.settings.curve:
            grown = PrunedTree(self.builder.grow(self.train[:size]))
            pruned, decisions = reduced_error_pruning(grown.root, self.validation)
            lines.append(
                f"size {size} grown leaves {len(grown.leaves())}"
                f" test {self.accuracy(grown, self.test)}"
                f" pruned leaves {len(pruned.leaves())} test {self.accuracy(pruned, self.test)}"
            )
        return lines

    def evaluation_file(self):
        return join_sections([
            self.data_lines(),
            [self.summary_line("grown", self.grown), self.summary_line("pruned", self.pruned)],
            self.model_evaluation("grown"),
            self.model_evaluation("pruned"),
            self.routing_lines(),
            self.cross_validation_lines(),
            self.depth_lines(),
            self.cost_complexity_lines(),
            self.bagging_lines(),
            self.mcnemar_lines(),
            self.auc_lines(),
            self.learning_curve_lines(),
        ])

    def impurity_lines(self, title, tree):
        size = len(self.attributes)
        importance = [0.0] * size
        splits = [0] * size
        for node in tree.internal_nodes():
            index = node.split.attribute.index
            importance[index] += impurity_decrease(
                node.counts, node.left.counts, node.right.counts
            )
            splits[index] += 1
        total = 0.0
        for value in importance:
            total += value
        shares = [value / total if total != 0 else 0.0 for value in importance]
        order = sorted(range(size), key=lambda index: -round(shares[index], 4))
        lines = [f"impurity {title}"]
        for rank, index in enumerate(order, 1):
            decrease = importance[index] / len(self.train)
            lines.append(
                f"{rank} {self.attributes[index].name} decrease {real_text(decrease)}"
                f" share {real_text(shares[index])} splits {splits[index]}"
            )
        return lines

    def permutation_lines(self):
        generator = Minstd(self.settings.permutation_seed)
        repeats = self.settings.permutation_repeats
        size = len(self.test)
        base = self.pruned.correct_count(self.test)
        results = []
        for attribute in self.attributes:
            counts = []
            for _ in range(repeats):
                values = [row.value(attribute) for row in self.test]
                for position in range(size, 1, -1):
                    other = generator.draw() % position
                    values[position - 1], values[other] = values[other], values[position - 1]
                rows = [with_value(row, attribute, value) for row, value in zip(self.test, values)]
                counts.append(self.pruned.correct_count(rows))
            results.append(Permutation(attribute, counts, repeats * base - sum(counts)))
        results.sort(key=lambda result: -result.drop)
        lines = [
            f"permutation pruned test repeats {repeats} seed {self.settings.permutation_seed}"
            f" base {ratio_text(base, size)}"
        ]
        for rank, result in enumerate(results, 1):
            lines.append(
                f"{rank} {result.attribute.name} correct {counts_text(result.counts)}"
                f" drop {fraction_text(result.drop, repeats * size)}"
            )
        return lines

    def importance_file(self):
        return join_sections([
            self.impurity_lines("grown", self.grown),
            self.impurity_lines("pruned", self.pruned),
            self.permutation_lines(),
        ])


def write_lines(name, lines):
    with open(os.path.join(OUTPUT_DIRECTORY, name), "w") as file:
        file.write("\n".join(lines) + "\n")


def main():
    analysis = Analysis(load_dataset(INPUT_DIRECTORY))
    os.makedirs(OUTPUT_DIRECTORY, exist_ok=True)
    write_lines("tree.txt", analysis.tree_file())
    write_lines("pruned_tree.txt", analysis.pruned_tree_file())
    write_lines("predictions.csv", analysis.predictions_file())
    write_lines("rules.txt", analysis.rules_file())
    write_lines("evaluation.txt", analysis.evaluation_file())
    write_lines("importance.txt", analysis.importance_file())


if __name__ == "__main__":
    main()
