import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeSet;
import java.util.stream.Collectors;

final class Minstd {
    private long state;
    Minstd(long seed) { state = seed; }
    long draw() { state = 48271L * state % 2147483647L; return state; }
}

final class Condition {
    final Attribute attribute;
    int lower = -1, upper = Integer.MAX_VALUE, equal = -1;
    final Set<Integer> excluded = new TreeSet<>();
    Condition(Attribute attribute) { this.attribute = attribute; }
    void add(Split split, boolean left) {
        if (attribute.integer()) {
            if (left) upper = Math.min(upper, split.point());
            else lower = Math.max(lower, split.point());
        } else if (left) equal = split.point();
        else excluded.add(split.point());
    }
    String text() {
        String name = attribute.name();
        if (attribute.integer()) {
            if (lower >= 0 && upper < Integer.MAX_VALUE) return Split.halfText(lower) + " < " + name + " <= " + Split.halfText(upper);
            return lower >= 0 ? name + " > " + Split.halfText(lower) : name + " <= " + Split.halfText(upper);
        }
        if (equal >= 0) return name + " = " + attribute.values().get(equal);
        List<String> names = excluded.stream().map(attribute.values()::get).toList();
        return names.size() == 1 ? name + " != " + names.getFirst() : name + " not in {" + String.join(",", names) + "}";
    }
    boolean holds(Row row) {
        int value = row.value(attribute);
        if (value < 0) return false;
        if (attribute.integer()) return (lower < 0 || 2 * value > lower) && 2 * value <= upper;
        return equal >= 0 ? value == equal : !excluded.contains(value);
    }
}

final class Rule {
    final int number;
    final Node leaf;
    final List<Condition> conditions;
    List<Condition> general;
    final List<String> removed = new ArrayList<>();
    Rule(int number, Node leaf, List<Condition> conditions) {
        this.number = number;
        this.leaf = leaf;
        this.conditions = conditions;
        general = new ArrayList<>(conditions);
    }
}

record RuleStep(Split split, boolean left) {}
record DepthResult(int depth, PrunedTree tree, int cvCorrect) {}
record Bag(PrunedTree tree, int distinct, int outOfBag, int correct) {}
record Permutation(Attribute attribute, int[] counts, int drop) {}

final class Analysis {
    final Dataset data;
    final List<Attribute> attributes;
    final List<String> classes;
    final Settings settings;
    final List<Row> train, validation, test;
    final TreeBuilder builder;
    final PrunedTree grown, pruned;
    final List<Decision> decisions;
    final List<Rule> rules = new ArrayList<>();
    final int[] bounds;
    final List<PrunedTree> foldTrees = new ArrayList<>();
    final List<DepthResult> depthResults = new ArrayList<>();
    final DepthResult selectedDepth;
    final List<SequenceTree> sequence;
    final int selectedIndex;
    final List<Bag> bags = new ArrayList<>();
    final int[][] oobVotes, testVotes;
    final Map<String, List<Integer>> predictions = new HashMap<>();

    Analysis(Dataset data) {
        this.data = data;
        attributes = data.attributes(); classes = data.classes(); settings = data.settings();
        train = data.train(); validation = data.validation(); test = data.test();
        builder = new TreeBuilder(attributes, classes.size(), settings);
        grown = new PrunedTree(builder.grow(train));
        PruningResult result = Pruning.reducedError(grown.root, validation);
        pruned = result.tree(); decisions = result.decisions();
        collectRules(pruned.root, List.of());
        rules.forEach(this::generalize);
        bounds = new int[settings.folds() + 1];
        for (int fold = 0; fold <= settings.folds(); fold++) bounds[fold] = fold * train.size() / settings.folds();
        for (int fold = 1; fold <= settings.folds(); fold++) {
            List<Row> training = new ArrayList<>(train.subList(0, bounds[fold - 1]));
            training.addAll(train.subList(bounds[fold], train.size()));
            foldTrees.add(new PrunedTree(builder.grow(training)));
        }
        DepthResult selected = null;
        for (int depth = 0; depth <= settings.maxDepth(); depth++) {
            int cv = 0;
            for (int fold = 1; fold <= settings.folds(); fold++) cv += limited(foldTrees.get(fold - 1), depth).correct(foldRows(fold));
            DepthResult item = new DepthResult(depth, limited(grown, depth), cv);
            depthResults.add(item);
            if (selected == null || cv > selected.cvCorrect()) selected = item;
        }
        selectedDepth = selected;
        sequence = Pruning.costComplexity(grown.root);
        int index = 0;
        for (int i = 1; i < sequence.size(); i++)
            if (validationErrors(sequence.get(i).tree()) <= validationErrors(sequence.get(index).tree())) index = i;
        selectedIndex = index;
        oobVotes = new int[train.size()][classes.size()];
        testVotes = new int[test.size()][classes.size()];
        bagging();
        Map<String, PrunedTree> models = Map.of("grown", grown, "pruned", pruned, "depth", selectedDepth.tree(),
            "cost_complexity", sequence.get(selectedIndex).tree());
        models.forEach((name, tree) -> predictions.put(name, test.stream().map(tree::predict).toList()));
        predictions.put("bagging", Arrays.stream(testVotes).map(Impurity::majority).toList());
    }

    static String ratio(long numerator, long denominator) { return Evaluation.ratio(numerator, denominator); }
    static String fraction(long numerator, long denominator) { return Evaluation.fraction(numerator, denominator); }
    static String real(double value) { return Evaluation.real(value); }
    static String countsText(int[] counts) { return Main.countsText(counts); }
    String accuracy(PrunedTree tree, List<Row> rows) { return ratio(tree.correct(rows), rows.size()); }
    int validationErrors(PrunedTree tree) { return validation.size() - tree.correct(validation); }
    List<Row> foldRows(int fold) { return train.subList(bounds[fold - 1], bounds[fold]); }

    PrunedTree limited(PrunedTree tree, int depth) {
        Set<Integer> cut = new HashSet<>();
        for (Node node : tree.internalNodes()) if (node.depth == depth) cut.add(node.number);
        return new PrunedTree(tree.root, cut);
    }

    void bagging() {
        Minstd generator = new Minstd(settings.bagSeed());
        for (int b = 0; b < settings.bagTrees(); b++) {
            List<Row> sample = new ArrayList<>();
            Set<Integer> sampled = new HashSet<>();
            for (int i = 0; i < train.size(); i++) {
                int index = (int) (generator.draw() % train.size());
                sampled.add(index); sample.add(train.get(index));
            }
            PrunedTree tree = new PrunedTree(builder.grow(sample));
            int outOfBag = 0, correct = 0;
            for (int i = 0; i < train.size(); i++)
                if (!sampled.contains(i)) {
                    outOfBag++;
                    int prediction = tree.predict(train.get(i));
                    oobVotes[i][prediction]++;
                    if (prediction == train.get(i).label()) correct++;
                }
            bags.add(new Bag(tree, sampled.size(), outOfBag, correct));
            for (int i = 0; i < test.size(); i++) testVotes[i][tree.predict(test.get(i))]++;
        }
    }

    void collectRules(Node node, List<RuleStep> steps) {
        if (pruned.isLeaf(node)) {
            List<Condition> conditions = new ArrayList<>();
            for (Attribute attribute : attributes) {
                List<RuleStep> related = steps.stream().filter(step -> step.split().attribute().index() == attribute.index()).toList();
                if (!related.isEmpty()) {
                    Condition condition = new Condition(attribute);
                    related.forEach(step -> condition.add(step.split(), step.left()));
                    conditions.add(condition);
                }
            }
            rules.add(new Rule(rules.size() + 1, node, conditions));
            return;
        }
        List<RuleStep> left = new ArrayList<>(steps), right = new ArrayList<>(steps);
        left.add(new RuleStep(node.split, true)); right.add(new RuleStep(node.split, false));
        collectRules(node.left, left); collectRules(node.right, right);
    }

    int[] coverage(List<Condition> conditions, List<Row> rows, int label) {
        int hits = 0, covered = 0;
        for (Row row : rows)
            if (conditions.stream().allMatch(condition -> condition.holds(row))) {
                covered++;
                if (row.label() == label) hits++;
            }
        return new int[] {hits, covered};
    }

    Fraction laplace(List<Condition> conditions, int label) {
        int[] covered = coverage(conditions, validation, label);
        return new Fraction(covered[0] + 1, covered[1] + classes.size());
    }

    void generalize(Rule rule) {
        while (!rule.general.isEmpty()) {
            Fraction current = laplace(rule.general, rule.leaf.prediction), best = null;
            int bestIndex = -1;
            for (int i = 0; i < rule.general.size(); i++) {
                List<Condition> trial = new ArrayList<>(rule.general);
                trial.remove(i);
                Fraction value = laplace(trial, rule.leaf.prediction);
                if (best == null || value.compareTo(best) > 0) { best = value; bestIndex = i; }
            }
            if (current.compareTo(best) > 0) return;
            rule.removed.add(rule.general.remove(bestIndex).attribute.name());
        }
    }

    String conditionsText(List<Condition> conditions) {
        return conditions.isEmpty() ? "true" : String.join(" and ", conditions.stream().map(Condition::text).toList());
    }

    void nodeLines(PrunedTree tree, Node node, String condition, List<String> lines) {
        String line = "  ".repeat(node.depth) + node.number + " " + condition + " n " + node.size + " counts " + countsText(node.counts);
        lines.add(line + (tree.isLeaf(node) ? " leaf " + classes.get(node.prediction) : ""));
        if (!tree.isLeaf(node)) {
            nodeLines(tree, node.left, node.split.condition(true), lines);
            nodeLines(tree, node.right, node.split.condition(false), lines);
        }
    }

    List<String> treeLines(PrunedTree tree) {
        List<String> lines = new ArrayList<>();
        nodeLines(tree, tree.root, "root", lines);
        lines.add("");
        List<Node> nodes = tree.preorder(), leaves = tree.leaves();
        lines.add("nodes " + nodes.size() + " leaves " + leaves.size() + " depth " + tree.depth() + " errors " + ratio(tree.trainingErrors(), train.size()));
        for (int level = 0; level <= tree.depth(); level++) {
            int levelNodes = 0, levelLeaves = 0, rows = 0, errors = 0;
            for (Node node : nodes) if (node.depth == level) levelNodes++;
            for (Node node : leaves) if (node.depth == level) { levelLeaves++; rows += node.size; errors += node.errors; }
            lines.add("level " + level + " nodes " + levelNodes + " leaves " + levelLeaves + " rows " + rows + " errors " + errors);
        }
        return lines;
    }

    List<String> rootCandidates() {
        List<Candidate> candidates = new ArrayList<>();
        for (Attribute attribute : attributes) {
            Candidate candidate = builder.bestSplit(train, List.of(attribute));
            if (candidate != null) candidates.add(candidate);
        }
        candidates.sort((first, second) -> {
            int comparison = second.quality().compareTo(first.quality());
            return comparison != 0 ? comparison : Integer.compare(first.split().attribute().index(), second.split().attribute().index());
        });
        List<String> lines = new ArrayList<>(List.of("root candidates n " + train.size() + " counts " + countsText(grown.root.counts)));
        for (int i = 0; i < candidates.size(); i++) {
            Candidate candidate = candidates.get(i);
            Fraction value = candidate.quality();
            double gain = (double) value.numerator() / value.denominator() / train.size()
                - (double) Impurity.squareSum(grown.root.counts) / ((long) train.size() * train.size());
            lines.add((i + 1) + " " + candidate.split().condition(true) + " left " + candidate.leftSize() + " right "
                + candidate.rightSize() + " gain " + Evaluation.real(gain, 6));
        }
        return lines;
    }

    List<String> surrogateLines() {
        List<String> lines = new ArrayList<>(List.of("surrogates"));
        for (Node node : grown.internalNodes()) {
            List<String> listed = node.surrogates.stream().map(surrogate -> surrogate.split().condition(true) + " "
                + (surrogate.left() ? "left" : "right") + " " + surrogate.score() + "/" + node.size).toList();
            lines.add("node " + node.number + " split " + node.split.condition(true) + " default " + (node.defaultLeft ? "left" : "right")
                + " surrogates " + (listed.isEmpty() ? "none" : String.join(" ; ", listed)));
        }
        return lines;
    }

    List<String> prunedTreeFile() {
        List<String> lines = new ArrayList<>(List.of("reduced_error_pruning validation " + validation.size()));
        int count = 0;
        for (Decision decision : decisions) {
            if (decision.pruned()) count++;
            lines.add("node " + decision.node().number + " depth " + decision.node().depth + " rows " + decision.rows()
                + " leaf " + decision.leafError() + " subtree " + decision.subtreeError() + " " + (decision.pruned() ? "pruned" : "kept"));
        }
        lines.add("examined " + decisions.size() + " pruned " + count + " kept " + (decisions.size() - count));
        return Main.sections(List.of(lines, treeLines(pruned)));
    }

    List<String> predictionsFile() {
        List<String> lines = new ArrayList<>(List.of("id,predicted,actual,grown,leaf,path,missing"));
        for (Row row : test) {
            Route route = pruned.route(row);
            String path = route.path().stream().map(node -> Integer.toString(node.number)).collect(Collectors.joining("-"));
            long missing = route.steps().stream().filter(step -> !step.method().equals("primary")).count();
            lines.add(row.id() + "," + classes.get(route.leaf().prediction) + "," + classes.get(row.label()) + ","
                + classes.get(grown.predict(row)) + "," + route.leaf().number + "," + path + "," + missing);
        }
        return lines;
    }

    List<String> rulesFile() {
        List<String> original = new ArrayList<>(List.of("rules " + rules.size()));
        List<String> generalized = new ArrayList<>(List.of("generalized " + rules.size()));
        Map<Integer, Integer> ruleNumbers = new HashMap<>();
        for (Rule rule : rules) {
            ruleNumbers.put(rule.leaf.number, rule.number);
            List<Row> reached = test.stream().filter(row -> pruned.leafOf(row) == rule.leaf).toList();
            long hits = reached.stream().filter(row -> row.label() == rule.leaf.prediction).count();
            original.add("rule " + rule.number + " node " + rule.leaf.number + " if " + conditionsText(rule.conditions)
                + " then " + classes.get(rule.leaf.prediction) + " train " + ratio(rule.leaf.counts[rule.leaf.prediction], rule.leaf.size)
                + " test " + ratio(hits, reached.size()));
            int[] validationCoverage = coverage(rule.general, validation, rule.leaf.prediction);
            int[] testCoverage = coverage(rule.general, test, rule.leaf.prediction);
            generalized.add("general " + rule.number + " if " + conditionsText(rule.general) + " then " + classes.get(rule.leaf.prediction)
                + " removed " + (rule.removed.isEmpty() ? "none" : String.join(",", rule.removed))
                + " laplace " + fraction(validationCoverage[0] + 1, validationCoverage[1] + classes.size())
                + " validation " + validationCoverage[0] + "/" + validationCoverage[1] + " test " + testCoverage[0] + "/" + testCoverage[1]);
        }
        List<Row> wrong = test.stream().filter(row -> pruned.predict(row) != row.label()).toList();
        List<String> errors = new ArrayList<>(List.of("misclassified " + wrong.size()));
        for (Row row : wrong) {
            Route route = pruned.route(row);
            List<String> explanation = route.steps().stream().map(step -> step.node().split.condition(step.left())
                + (step.method().equals("primary") ? "" : " [" + step.method() + "]")).toList();
            errors.add(row.id() + " actual " + classes.get(row.label()) + " predicted " + classes.get(route.leaf().prediction)
                + " rule " + ruleNumbers.get(route.leaf().number) + " path " + (explanation.isEmpty() ? "root" : String.join("; ", explanation)));
        }
        return Main.sections(List.of(original, generalized, errors));
    }

    List<String> dataLines() {
        List<String> lines = new ArrayList<>(List.of("data train " + train.size() + " validation " + validation.size() + " test " + test.size()
            + " attributes " + attributes.size() + " classes " + classes.size() + " target " + data.target()));
        int[] training = Impurity.counts(train, classes.size()), valid = Impurity.counts(validation, classes.size()), testing = Impurity.counts(test, classes.size());
        for (int k = 0; k < classes.size(); k++) lines.add("class " + classes.get(k) + " train " + training[k] + " validation " + valid[k] + " test " + testing[k]);
        lines.add("missing validation " + validation.stream().mapToInt(Row::missingCount).sum() + " test " + test.stream().mapToInt(Row::missingCount).sum());
        for (Attribute attribute : attributes) lines.add("missing " + attribute.name() + " validation "
            + validation.stream().filter(row -> row.value(attribute) < 0).count() + " test " + test.stream().filter(row -> row.value(attribute) < 0).count());
        return lines;
    }

    String summary(String name, PrunedTree tree) {
        return name + " nodes " + tree.preorder().size() + " leaves " + tree.leaves().size() + " depth " + tree.depth()
            + " train " + accuracy(tree, train) + " validation " + accuracy(tree, validation) + " test " + accuracy(tree, test);
    }
    List<String> modelEvaluation(String model) { return Evaluation.classification(model + " test", classes, test, predictions.get(model)); }

    List<String> routingLines() {
        Map<Integer, int[]> tally = new HashMap<>();
        grown.preorder().forEach(node -> tally.put(node.number, new int[3]));
        List<String> methods = List.of("primary", "surrogate", "default");
        for (Row row : test) for (Step step : pruned.route(row).steps()) tally.get(step.node().number)[methods.indexOf(step.method())]++;
        List<String> lines = new ArrayList<>(List.of("routing pruned test"));
        for (Node node : pruned.internalNodes()) {
            int[] counts = tally.get(node.number);
            lines.add("node " + node.number + " rows " + Arrays.stream(counts).sum() + " primary " + counts[0] + " surrogate " + counts[1] + " default " + counts[2]);
        }
        for (boolean complete : List.of(true, false)) {
            List<Row> rows = test.stream().filter(row -> (row.missingCount() == 0) == complete).toList();
            lines.add((complete ? "complete" : "incomplete") + " rows " + rows.size() + " correct " + accuracy(pruned, rows));
        }
        return lines;
    }

    List<String> crossValidationLines() {
        List<String> lines = new ArrayList<>(List.of("cross_validation folds " + settings.folds()));
        int total = 0;
        for (int fold = 1; fold <= settings.folds(); fold++) {
            List<Row> rows = foldRows(fold);
            PrunedTree tree = foldTrees.get(fold - 1);
            int correct = tree.correct(rows);
            total += correct;
            lines.add("fold " + fold + " rows " + (bounds[fold - 1] + 1) + "-" + bounds[fold] + " leaves " + tree.leaves().size() + " correct " + ratio(correct, rows.size()));
        }
        lines.add("cv accuracy " + ratio(total, train.size()));
        return lines;
    }

    List<String> depthLines() {
        List<String> lines = new ArrayList<>(List.of("depth_selection"));
        for (DepthResult result : depthResults) lines.add("depth " + result.depth() + " leaves " + result.tree().leaves().size()
            + " cv " + ratio(result.cvCorrect(), train.size()) + " train " + accuracy(result.tree(), train)
            + " validation " + accuracy(result.tree(), validation) + " test " + accuracy(result.tree(), test));
        lines.add("selected depth " + selectedDepth.depth() + " leaves " + selectedDepth.tree().leaves().size() + " test " + accuracy(selectedDepth.tree(), test));
        return lines;
    }

    List<String> complexityLines() {
        List<String> lines = new ArrayList<>(List.of("cost_complexity"));
        for (int i = 0; i < sequence.size(); i++) {
            SequenceTree step = sequence.get(i);
            lines.add("subtree " + i + " alpha " + Evaluation.fraction(step.alpha().numerator(), step.alpha().denominator() * train.size(), 6)
                + " leaves " + step.tree().leaves().size() + " train_errors " + step.tree().trainingErrors() + " validation_errors " + validationErrors(step.tree()));
        }
        PrunedTree tree = sequence.get(selectedIndex).tree();
        lines.add("selected subtree " + selectedIndex + " leaves " + tree.leaves().size() + " test " + accuracy(tree, test));
        return lines;
    }

    List<String> baggingLines() {
        List<String> lines = new ArrayList<>(List.of("bagging trees " + settings.bagTrees() + " seed " + settings.bagSeed()));
        for (int i = 0; i < bags.size(); i++) {
            Bag bag = bags.get(i);
            lines.add("bag " + (i + 1) + " distinct " + bag.distinct() + " leaves " + bag.tree().leaves().size() + " oob " + ratio(bag.correct(), bag.outOfBag()));
        }
        int voted = 0, hits = 0;
        for (int i = 0; i < train.size(); i++) if (Arrays.stream(oobVotes[i]).sum() > 0) {
            voted++;
            if (Impurity.majority(oobVotes[i]) == train.get(i).label()) hits++;
        }
        lines.add("oob accuracy " + ratio(hits, voted) + " unvoted " + (train.size() - voted));
        lines.addAll(modelEvaluation("bagging"));
        return lines;
    }

    List<String> mcnemarLines() {
        List<String> lines = new ArrayList<>(List.of("mcnemar pruned test"));
        for (String model : List.of("grown", "depth", "cost_complexity", "bagging")) {
            int b = 0, c = 0;
            for (int i = 0; i < test.size(); i++) {
                boolean first = predictions.get("pruned").get(i) == test.get(i).label(), second = predictions.get(model).get(i) == test.get(i).label();
                if (first && !second) b++;
                if (second && !first) c++;
            }
            long difference = Math.max(0, Math.abs(b - c) - 1), squared = difference * difference;
            String statistic = b + c == 0 ? "0/1 0.0000" : fraction(squared, b + c);
            lines.add("versus " + model + " b " + b + " c " + c + " statistic " + statistic + " significant "
                + (1000 * squared > 3841L * (b + c) ? "yes" : "no"));
        }
        return lines;
    }

    Fraction[][] scores(String model) {
        Fraction[][] scores = new Fraction[test.size()][classes.size()];
        for (int i = 0; i < test.size(); i++) {
            Node leaf = model.equals("bagging") ? null : (model.equals("grown") ? grown : pruned).leafOf(test.get(i));
            for (int k = 0; k < classes.size(); k++) scores[i][k] = leaf == null
                ? new Fraction(testVotes[i][k], settings.bagTrees()) : new Fraction(leaf.counts[k], leaf.size);
        }
        return scores;
    }

    List<String> aucLines() {
        List<String> lines = new ArrayList<>();
        for (String model : List.of("grown", "pruned", "bagging")) {
            Fraction[][] scores = scores(model);
            List<String> parts = new ArrayList<>(List.of("auc", model));
            double total = 0;
            int available = 0;
            for (int k = 0; k < classes.size(); k++) {
                long wins = 0, positive = 0;
                for (int i = 0; i < test.size(); i++) if (test.get(i).label() == k) {
                    positive++;
                    for (int j = 0; j < test.size(); j++) if (test.get(j).label() != k) {
                        int comparison = scores[i][k].compareTo(scores[j][k]);
                        if (comparison > 0) wins += 2;
                        else if (comparison == 0) wins++;
                    }
                }
                long denominator = 2 * positive * (test.size() - positive);
                parts.add(classes.get(k)); parts.add(fraction(wins, denominator));
                if (denominator > 0) { total += (double) wins / denominator; available++; }
            }
            parts.add("macro"); parts.add(available == 0 ? "-" : real(total / available));
            lines.add(String.join(" ", parts));
        }
        return lines;
    }

    List<String> learningLines() {
        List<String> lines = new ArrayList<>(List.of("learning_curve"));
        for (int size : settings.curve()) {
            PrunedTree grown = new PrunedTree(builder.grow(train.subList(0, size)));
            PrunedTree pruned = Pruning.reducedError(grown.root, validation).tree();
            lines.add("size " + size + " grown leaves " + grown.leaves().size() + " test " + accuracy(grown, test)
                + " pruned leaves " + pruned.leaves().size() + " test " + accuracy(pruned, test));
        }
        return lines;
    }

    List<String> evaluationFile() {
        return Main.sections(List.of(dataLines(), List.of(summary("grown", grown), summary("pruned", pruned)),
            modelEvaluation("grown"), modelEvaluation("pruned"), routingLines(), crossValidationLines(), depthLines(),
            complexityLines(), baggingLines(), mcnemarLines(), aucLines(), learningLines()));
    }

    List<String> impurityLines(String title, PrunedTree tree) {
        double[] importance = new double[attributes.size()], shares = new double[attributes.size()];
        int[] splits = new int[attributes.size()];
        for (Node node : tree.internalNodes()) {
            int index = node.split.attribute().index();
            importance[index] += Impurity.decrease(node.counts, node.left.counts, node.right.counts);
            splits[index]++;
        }
        double total = 0;
        for (double value : importance) total += value;
        List<Integer> order = new ArrayList<>();
        for (int i = 0; i < attributes.size(); i++) { shares[i] = total == 0 ? 0 : importance[i] / total; order.add(i); }
        order.sort(Comparator.<Integer>comparingLong(i -> Math.round(shares[i] * 10000)).reversed().thenComparingInt(i -> i));
        List<String> lines = new ArrayList<>(List.of("impurity " + title));
        for (int rank = 0; rank < order.size(); rank++) {
            int i = order.get(rank);
            lines.add((rank + 1) + " " + attributes.get(i).name() + " decrease " + real(importance[i] / train.size())
                + " share " + real(shares[i]) + " splits " + splits[i]);
        }
        return lines;
    }

    List<String> permutationLines() {
        Minstd generator = new Minstd(settings.permutationSeed());
        int repeats = settings.repeats(), base = pruned.correct(test);
        List<Permutation> results = new ArrayList<>();
        for (Attribute attribute : attributes) {
            int[] counts = new int[repeats];
            for (int repeat = 0; repeat < repeats; repeat++) {
                int[] values = test.stream().mapToInt(row -> row.value(attribute)).toArray();
                for (int position = test.size(); position > 1; position--) {
                    int other = (int) (generator.draw() % position), temporary = values[position - 1];
                    values[position - 1] = values[other]; values[other] = temporary;
                }
                List<Row> rows = new ArrayList<>();
                for (int i = 0; i < test.size(); i++) rows.add(test.get(i).withValue(attribute, values[i]));
                counts[repeat] = pruned.correct(rows);
            }
            results.add(new Permutation(attribute, counts, repeats * base - Arrays.stream(counts).sum()));
        }
        results.sort(Comparator.comparingInt(Permutation::drop).reversed().thenComparingInt(result -> result.attribute().index()));
        List<String> lines = new ArrayList<>(List.of("permutation pruned test repeats " + repeats + " seed " + settings.permutationSeed() + " base " + ratio(base, test.size())));
        for (int i = 0; i < results.size(); i++) {
            Permutation result = results.get(i);
            lines.add((i + 1) + " " + result.attribute().name() + " correct " + countsText(result.counts()) + " drop " + fraction(result.drop(), repeats * test.size()));
        }
        return lines;
    }
}

public final class Main {
    static String countsText(int[] counts) { return Arrays.stream(counts).mapToObj(Integer::toString).collect(Collectors.joining(" ")); }
    static List<String> sections(List<List<String>> sections) {
        List<String> lines = new ArrayList<>();
        for (List<String> section : sections) { if (!lines.isEmpty()) lines.add(""); lines.addAll(section); }
        return lines;
    }
    public static void main(String[] args) throws IOException {
        Analysis analysis = new Analysis(Dataset.load("input"));
        Files.createDirectories(Path.of("output"));
        Map<String, List<String>> files = Map.of("tree.txt", sections(List.of(analysis.rootCandidates(), analysis.treeLines(analysis.grown), analysis.surrogateLines())),
            "pruned_tree.txt", analysis.prunedTreeFile(), "predictions.csv", analysis.predictionsFile(), "rules.txt", analysis.rulesFile(),
            "evaluation.txt", analysis.evaluationFile(), "importance.txt", sections(List.of(analysis.impurityLines("grown", analysis.grown),
                analysis.impurityLines("pruned", analysis.pruned), analysis.permutationLines())));
        for (var entry : files.entrySet()) Files.writeString(Path.of("output", entry.getKey()), String.join("\n", entry.getValue()) + "\n", StandardCharsets.US_ASCII);
    }
}
