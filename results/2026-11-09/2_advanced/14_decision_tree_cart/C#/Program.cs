#nullable enable
using System;
using System.IO;
using System.Linq;
using System.Text;
using System.Collections.Generic;
using static Evaluation;

sealed class Minstd
{
    private long state;
    public Minstd(long seed) { state = seed; }
    public long Draw() { state = 48271L * state % 2147483647L; return state; }
}

sealed class Condition
{
    public Attribute Attribute { get; }
    private int lower = -1, upper = int.MaxValue, equal = -1;
    private readonly SortedSet<int> excluded = new();
    public Condition(Attribute attribute) { Attribute = attribute; }
    public void Add(Split split, bool left)
    {
        if (Attribute.Integer)
        {
            if (left) upper = Math.Min(upper, split.Point);
            else lower = Math.Max(lower, split.Point);
        }
        else if (left) equal = split.Point;
        else excluded.Add(split.Point);
    }
    public string Text()
    {
        string name = Attribute.Name;
        if (Attribute.Integer)
        {
            if (lower >= 0 && upper < int.MaxValue) return $"{Split.HalfText(lower)} < {name} <= {Split.HalfText(upper)}";
            return lower >= 0 ? $"{name} > {Split.HalfText(lower)}" : $"{name} <= {Split.HalfText(upper)}";
        }
        if (equal >= 0) return $"{name} = {Attribute.Values[equal]}";
        List<string> names = excluded.Select(index => Attribute.Values[index]).ToList();
        return names.Count == 1 ? $"{name} != {names[0]}" : name + " not in {" + string.Join(",", names) + "}";
    }
    public bool Holds(Row row)
    {
        int value = row.Value(Attribute);
        if (value < 0) return false;
        if (Attribute.Integer) return (lower < 0 || 2 * value > lower) && 2 * value <= upper;
        return equal >= 0 ? value == equal : !excluded.Contains(value);
    }
}

sealed class Rule
{
    public int Number { get; }
    public Node Leaf { get; }
    public List<Condition> Conditions { get; }
    public List<Condition> General { get; }
    public List<string> Removed { get; } = new();
    public Rule(int number, Node leaf, List<Condition> conditions)
    {
        Number = number; Leaf = leaf; Conditions = conditions; General = conditions.ToList();
    }
}

sealed record RuleStep(Split Split, bool Left);
sealed record DepthResult(int Depth, PrunedTree Tree, int CvCorrect);
sealed record Bag(PrunedTree Tree, int Distinct, int OutOfBag, int Correct);
sealed record Permutation(Attribute Attribute, int[] Counts, int Drop);

sealed class Analysis
{
    private readonly Dataset data;
    private readonly List<Attribute> attributes;
    private readonly List<string> classes;
    private readonly Settings settings;
    private readonly List<Row> train, validation, test;
    private readonly TreeBuilder builder;
    public PrunedTree Grown { get; }
    public PrunedTree Pruned { get; }
    private readonly List<Decision> decisions;
    private readonly List<Rule> rules = new();
    private readonly int[] bounds;
    private readonly List<PrunedTree> foldTrees = new();
    private readonly List<DepthResult> depthResults = new();
    private readonly DepthResult selectedDepth;
    private readonly List<SequenceTree> sequence;
    private readonly int selectedIndex;
    private readonly List<Bag> bags = new();
    private readonly int[][] oobVotes, testVotes;
    private readonly Dictionary<string, List<int>> predictions = new(StringComparer.Ordinal);

    public Analysis(Dataset data)
    {
        this.data = data; attributes = data.Attributes; classes = data.Classes; settings = data.Settings;
        train = data.Train; validation = data.Validation; test = data.Test;
        builder = new TreeBuilder(attributes, classes.Count, settings);
        Grown = new PrunedTree(builder.Grow(train));
        PruningResult result = Pruning.ReducedError(Grown.Root, validation);
        Pruned = result.Tree; decisions = result.Decisions;
        CollectRules(Pruned.Root, new List<RuleStep>());
        rules.ForEach(Generalize);
        bounds = Enumerable.Range(0, settings.Folds + 1).Select(fold => fold * train.Count / settings.Folds).ToArray();
        for (int fold = 1; fold <= settings.Folds; fold++)
        {
            List<Row> training = train.Take(bounds[fold - 1]).Concat(train.Skip(bounds[fold])).ToList();
            foldTrees.Add(new PrunedTree(builder.Grow(training)));
        }
        for (int depth = 0; depth <= settings.MaxDepth; depth++)
        {
            int correct = 0;
            for (int fold = 1; fold <= settings.Folds; fold++) correct += Limited(foldTrees[fold - 1], depth).Correct(FoldRows(fold));
            depthResults.Add(new DepthResult(depth, Limited(Grown, depth), correct));
        }
        selectedDepth = depthResults.OrderByDescending(item => item.CvCorrect).ThenBy(item => item.Depth).First();
        sequence = Pruning.CostComplexity(Grown.Root);
        selectedIndex = 0;
        for (int i = 1; i < sequence.Count; i++)
            if (ValidationErrors(sequence[i].Tree) <= ValidationErrors(sequence[selectedIndex].Tree)) selectedIndex = i;
        oobVotes = Enumerable.Range(0, train.Count).Select(_ => new int[classes.Count]).ToArray();
        testVotes = Enumerable.Range(0, test.Count).Select(_ => new int[classes.Count]).ToArray();
        Bagging();
        var models = new Dictionary<string, PrunedTree>(StringComparer.Ordinal)
        {
            ["grown"] = Grown, ["pruned"] = Pruned, ["depth"] = selectedDepth.Tree,
            ["cost_complexity"] = sequence[selectedIndex].Tree
        };
        foreach (var model in models) predictions[model.Key] = test.Select(model.Value.Predict).ToList();
        predictions["bagging"] = testVotes.Select(Impurity.Majority).ToList();
    }

    private static string CountsText(IEnumerable<int> counts) => string.Join(" ", counts);
    private string Accuracy(PrunedTree tree, List<Row> rows) => Ratio(tree.Correct(rows), rows.Count);
    private int ValidationErrors(PrunedTree tree) => validation.Count - tree.Correct(validation);
    private List<Row> FoldRows(int fold) => train.GetRange(bounds[fold - 1], bounds[fold] - bounds[fold - 1]);
    private static PrunedTree Limited(PrunedTree tree, int depth) =>
        new(tree.Root, tree.InternalNodes().Where(node => node.Depth == depth).Select(node => node.Number));

    private void Bagging()
    {
        var generator = new Minstd(settings.BagSeed);
        for (int b = 0; b < settings.BagTrees; b++)
        {
            var sample = new List<Row>();
            var sampled = new HashSet<int>();
            for (int i = 0; i < train.Count; i++)
            {
                int index = (int)(generator.Draw() % train.Count);
                sampled.Add(index); sample.Add(train[index]);
            }
            var tree = new PrunedTree(builder.Grow(sample));
            int outOfBag = 0, correct = 0;
            for (int i = 0; i < train.Count; i++)
                if (!sampled.Contains(i))
                {
                    outOfBag++;
                    int prediction = tree.Predict(train[i]);
                    oobVotes[i][prediction]++;
                    if (prediction == train[i].Label) correct++;
                }
            bags.Add(new Bag(tree, sampled.Count, outOfBag, correct));
            for (int i = 0; i < test.Count; i++) testVotes[i][tree.Predict(test[i])]++;
        }
    }

    private void CollectRules(Node node, List<RuleStep> steps)
    {
        if (Pruned.IsLeaf(node))
        {
            var conditions = new List<Condition>();
            foreach (Attribute attribute in attributes)
            {
                List<RuleStep> related = steps.Where(step => step.Split.Attribute.Index == attribute.Index).ToList();
                if (related.Count == 0) continue;
                var condition = new Condition(attribute);
                related.ForEach(step => condition.Add(step.Split, step.Left));
                conditions.Add(condition);
            }
            rules.Add(new Rule(rules.Count + 1, node, conditions));
            return;
        }
        CollectRules(node.Left, steps.Append(new RuleStep(node.Split!, true)).ToList());
        CollectRules(node.Right, steps.Append(new RuleStep(node.Split!, false)).ToList());
    }

    private (int Hits, int Covered) Coverage(List<Condition> conditions, List<Row> rows, int label)
    {
        int hits = 0, covered = 0;
        foreach (Row row in rows)
            if (conditions.All(condition => condition.Holds(row)))
            {
                covered++;
                if (row.Label == label) hits++;
            }
        return (hits, covered);
    }
    private Fraction Laplace(List<Condition> conditions, int label)
    {
        var coverage = Coverage(conditions, validation, label);
        return new Fraction(coverage.Hits + 1, coverage.Covered + classes.Count);
    }
    private void Generalize(Rule rule)
    {
        while (rule.General.Count > 0)
        {
            Fraction current = Laplace(rule.General, rule.Leaf.Prediction);
            Fraction? best = null;
            int bestIndex = -1;
            for (int i = 0; i < rule.General.Count; i++)
            {
                List<Condition> trial = rule.General.ToList();
                trial.RemoveAt(i);
                Fraction value = Laplace(trial, rule.Leaf.Prediction);
                if (best is null || value.CompareTo(best.Value) > 0) { best = value; bestIndex = i; }
            }
            if (current.CompareTo(best!.Value) > 0) return;
            rule.Removed.Add(rule.General[bestIndex].Attribute.Name);
            rule.General.RemoveAt(bestIndex);
        }
    }
    private static string ConditionsText(List<Condition> conditions) =>
        conditions.Count == 0 ? "true" : string.Join(" and ", conditions.Select(condition => condition.Text()));

    private void NodeLines(PrunedTree tree, Node node, string condition, List<string> lines)
    {
        string line = new string(' ', 2 * node.Depth) + $"{node.Number} {condition} n {node.Size} counts {CountsText(node.Counts)}";
        lines.Add(line + (tree.IsLeaf(node) ? $" leaf {classes[node.Prediction]}" : ""));
        if (!tree.IsLeaf(node))
        {
            NodeLines(tree, node.Left, node.Split!.Condition(true), lines);
            NodeLines(tree, node.Right, node.Split.Condition(false), lines);
        }
    }

    public List<string> TreeLines(PrunedTree tree)
    {
        var lines = new List<string>();
        NodeLines(tree, tree.Root, "root", lines);
        lines.Add("");
        List<Node> nodes = tree.Preorder(), leaves = tree.Leaves();
        lines.Add($"nodes {nodes.Count} leaves {leaves.Count} depth {tree.Depth} errors {Ratio(tree.TrainingErrors, train.Count)}");
        for (int level = 0; level <= tree.Depth; level++)
        {
            List<Node> levelLeaves = leaves.Where(node => node.Depth == level).ToList();
            lines.Add($"level {level} nodes {nodes.Count(node => node.Depth == level)} leaves {levelLeaves.Count} rows {levelLeaves.Sum(node => node.Size)} errors {levelLeaves.Sum(node => node.Errors)}");
        }
        return lines;
    }

    public List<string> RootCandidates()
    {
        List<Candidate> candidates = attributes.Select(attribute => builder.BestSplit(train, new List<Attribute> { attribute }))
            .OfType<Candidate>().OrderByDescending(candidate => candidate.Quality).ThenBy(candidate => candidate.Split.Attribute.Index).ToList();
        var lines = new List<string> { $"root candidates n {train.Count} counts {CountsText(Grown.Root.Counts)}" };
        for (int i = 0; i < candidates.Count; i++)
        {
            Candidate candidate = candidates[i];
            double gain = (double)candidate.Quality.Numerator / candidate.Quality.Denominator / train.Count
                - (double)Impurity.SquareSum(Grown.Root.Counts) / ((long)train.Count * train.Count);
            lines.Add($"{i + 1} {candidate.Split.Condition(true)} left {candidate.LeftSize} right {candidate.RightSize} gain {Real(gain, 6)}");
        }
        return lines;
    }

    public List<string> SurrogateLines()
    {
        var lines = new List<string> { "surrogates" };
        foreach (Node node in Grown.InternalNodes())
        {
            List<string> listed = node.Surrogates.Select(surrogate => $"{surrogate.Split.Condition(true)} {(surrogate.Left ? "left" : "right")} {surrogate.Score}/{node.Size}").ToList();
            lines.Add($"node {node.Number} split {node.Split!.Condition(true)} default {(node.DefaultLeft ? "left" : "right")} surrogates "
                + (listed.Count == 0 ? "none" : string.Join(" ; ", listed)));
        }
        return lines;
    }

    public List<string> PrunedTreeFile()
    {
        var lines = new List<string> { $"reduced_error_pruning validation {validation.Count}" };
        foreach (Decision decision in decisions)
            lines.Add($"node {decision.Node.Number} depth {decision.Node.Depth} rows {decision.Rows} leaf {decision.LeafError} subtree {decision.SubtreeError} {(decision.Pruned ? "pruned" : "kept")}");
        int count = decisions.Count(decision => decision.Pruned);
        lines.Add($"examined {decisions.Count} pruned {count} kept {decisions.Count - count}");
        return Program.Sections(lines, TreeLines(Pruned));
    }

    public List<string> PredictionsFile()
    {
        var lines = new List<string> { "id,predicted,actual,grown,leaf,path,missing" };
        foreach (Row row in test)
        {
            Route route = Pruned.Route(row);
            string path = string.Join("-", route.Path.Select(node => node.Number));
            int missing = route.Steps.Count(step => step.Method != "primary");
            lines.Add($"{row.Id},{classes[route.Leaf.Prediction]},{classes[row.Label]},{classes[Grown.Predict(row)]},{route.Leaf.Number},{path},{missing}");
        }
        return lines;
    }

    public List<string> RulesFile()
    {
        var original = new List<string> { $"rules {rules.Count}" };
        var generalized = new List<string> { $"generalized {rules.Count}" };
        var ruleNumbers = new Dictionary<int, int>();
        foreach (Rule rule in rules)
        {
            ruleNumbers[rule.Leaf.Number] = rule.Number;
            List<Row> reached = test.Where(row => ReferenceEquals(Pruned.LeafOf(row), rule.Leaf)).ToList();
            int hits = reached.Count(row => row.Label == rule.Leaf.Prediction);
            original.Add($"rule {rule.Number} node {rule.Leaf.Number} if {ConditionsText(rule.Conditions)} then {classes[rule.Leaf.Prediction]} train {Ratio(rule.Leaf.Counts[rule.Leaf.Prediction], rule.Leaf.Size)} test {Ratio(hits, reached.Count)}");
            var valid = Coverage(rule.General, validation, rule.Leaf.Prediction);
            var testing = Coverage(rule.General, test, rule.Leaf.Prediction);
            string removed = rule.Removed.Count == 0 ? "none" : string.Join(",", rule.Removed);
            generalized.Add($"general {rule.Number} if {ConditionsText(rule.General)} then {classes[rule.Leaf.Prediction]} removed {removed} laplace {Fraction(valid.Hits + 1, valid.Covered + classes.Count)} validation {valid.Hits}/{valid.Covered} test {testing.Hits}/{testing.Covered}");
        }
        List<Row> wrong = test.Where(row => Pruned.Predict(row) != row.Label).ToList();
        var errors = new List<string> { $"misclassified {wrong.Count}" };
        foreach (Row row in wrong)
        {
            Route route = Pruned.Route(row);
            List<string> explanation = route.Steps.Select(step => step.Node.Split!.Condition(step.Left)
                + (step.Method == "primary" ? "" : $" [{step.Method}]")).ToList();
            string path = explanation.Count == 0 ? "root" : string.Join("; ", explanation);
            errors.Add($"{row.Id} actual {classes[row.Label]} predicted {classes[route.Leaf.Prediction]} rule {ruleNumbers[route.Leaf.Number]} path {path}");
        }
        return Program.Sections(original, generalized, errors);
    }

    private List<string> DataLines()
    {
        var lines = new List<string> { $"data train {train.Count} validation {validation.Count} test {test.Count} attributes {attributes.Count} classes {classes.Count} target {data.Target}" };
        int[] training = Impurity.Counts(train, classes.Count), valid = Impurity.Counts(validation, classes.Count), testing = Impurity.Counts(test, classes.Count);
        for (int k = 0; k < classes.Count; k++) lines.Add($"class {classes[k]} train {training[k]} validation {valid[k]} test {testing[k]}");
        lines.Add($"missing validation {validation.Sum(row => row.MissingCount)} test {test.Sum(row => row.MissingCount)}");
        foreach (Attribute attribute in attributes)
            lines.Add($"missing {attribute.Name} validation {validation.Count(row => row.Value(attribute) < 0)} test {test.Count(row => row.Value(attribute) < 0)}");
        return lines;
    }
    private string Summary(string name, PrunedTree tree) => $"{name} nodes {tree.Preorder().Count} leaves {tree.Leaves().Count} depth {tree.Depth} train {Accuracy(tree, train)} validation {Accuracy(tree, validation)} test {Accuracy(tree, test)}";
    private List<string> ModelEvaluation(string model) => Evaluation.Classification(model + " test", classes, test, predictions[model]);

    private List<string> RoutingLines()
    {
        Dictionary<int, int[]> tallies = Grown.Preorder().ToDictionary(node => node.Number, _ => new int[3]);
        string[] methods = { "primary", "surrogate", "default" };
        foreach (Row row in test)
            foreach (Step step in Pruned.Route(row).Steps) tallies[step.Node.Number][Array.IndexOf(methods, step.Method)]++;
        var lines = new List<string> { "routing pruned test" };
        foreach (Node node in Pruned.InternalNodes())
        {
            int[] counts = tallies[node.Number];
            lines.Add($"node {node.Number} rows {counts.Sum()} primary {counts[0]} surrogate {counts[1]} default {counts[2]}");
        }
        foreach (bool complete in new[] { true, false })
        {
            List<Row> rows = test.Where(row => (row.MissingCount == 0) == complete).ToList();
            lines.Add($"{(complete ? "complete" : "incomplete")} rows {rows.Count} correct {Accuracy(Pruned, rows)}");
        }
        return lines;
    }

    private List<string> CrossValidationLines()
    {
        var lines = new List<string> { $"cross_validation folds {settings.Folds}" };
        int total = 0;
        for (int fold = 1; fold <= settings.Folds; fold++)
        {
            List<Row> rows = FoldRows(fold);
            PrunedTree tree = foldTrees[fold - 1];
            int correct = tree.Correct(rows);
            total += correct;
            lines.Add($"fold {fold} rows {bounds[fold - 1] + 1}-{bounds[fold]} leaves {tree.Leaves().Count} correct {Ratio(correct, rows.Count)}");
        }
        lines.Add($"cv accuracy {Ratio(total, train.Count)}");
        return lines;
    }
    private List<string> DepthLines()
    {
        var lines = new List<string> { "depth_selection" };
        foreach (DepthResult result in depthResults)
            lines.Add($"depth {result.Depth} leaves {result.Tree.Leaves().Count} cv {Ratio(result.CvCorrect, train.Count)} train {Accuracy(result.Tree, train)} validation {Accuracy(result.Tree, validation)} test {Accuracy(result.Tree, test)}");
        lines.Add($"selected depth {selectedDepth.Depth} leaves {selectedDepth.Tree.Leaves().Count} test {Accuracy(selectedDepth.Tree, test)}");
        return lines;
    }
    private List<string> ComplexityLines()
    {
        var lines = new List<string> { "cost_complexity" };
        for (int i = 0; i < sequence.Count; i++)
        {
            SequenceTree step = sequence[i];
            lines.Add($"subtree {i} alpha {Fraction(step.Alpha.Numerator, step.Alpha.Denominator * train.Count, 6)} leaves {step.Tree.Leaves().Count} train_errors {step.Tree.TrainingErrors} validation_errors {ValidationErrors(step.Tree)}");
        }
        PrunedTree tree = sequence[selectedIndex].Tree;
        lines.Add($"selected subtree {selectedIndex} leaves {tree.Leaves().Count} test {Accuracy(tree, test)}");
        return lines;
    }
    private List<string> BaggingLines()
    {
        var lines = new List<string> { $"bagging trees {settings.BagTrees} seed {settings.BagSeed}" };
        for (int i = 0; i < bags.Count; i++)
        {
            Bag bag = bags[i];
            lines.Add($"bag {i + 1} distinct {bag.Distinct} leaves {bag.Tree.Leaves().Count} oob {Ratio(bag.Correct, bag.OutOfBag)}");
        }
        int voted = 0, hits = 0;
        for (int i = 0; i < train.Count; i++)
            if (oobVotes[i].Sum() > 0)
            {
                voted++;
                if (Impurity.Majority(oobVotes[i]) == train[i].Label) hits++;
            }
        lines.Add($"oob accuracy {Ratio(hits, voted)} unvoted {train.Count - voted}");
        lines.AddRange(ModelEvaluation("bagging"));
        return lines;
    }
    private List<string> McnemarLines()
    {
        var lines = new List<string> { "mcnemar pruned test" };
        foreach (string model in new[] { "grown", "depth", "cost_complexity", "bagging" })
        {
            int b = 0, c = 0;
            for (int i = 0; i < test.Count; i++)
            {
                bool first = predictions["pruned"][i] == test[i].Label, second = predictions[model][i] == test[i].Label;
                if (first && !second) b++;
                if (second && !first) c++;
            }
            long difference = Math.Max(0, Math.Abs(b - c) - 1), squared = difference * difference;
            string statistic = b + c == 0 ? "0/1 0.0000" : Fraction(squared, b + c);
            lines.Add($"versus {model} b {b} c {c} statistic {statistic} significant {(1000 * squared > 3841L * (b + c) ? "yes" : "no")}");
        }
        return lines;
    }
    private Fraction[][] Scores(string model)
    {
        var scores = new Fraction[test.Count][];
        for (int i = 0; i < test.Count; i++)
        {
            Node? leaf = model == "bagging" ? null : (model == "grown" ? Grown : Pruned).LeafOf(test[i]);
            scores[i] = Enumerable.Range(0, classes.Count).Select(k => leaf is null
                ? new Fraction(testVotes[i][k], settings.BagTrees) : new Fraction(leaf.Counts[k], leaf.Size)).ToArray();
        }
        return scores;
    }
    private List<string> AucLines()
    {
        var lines = new List<string>();
        foreach (string model in new[] { "grown", "pruned", "bagging" })
        {
            Fraction[][] scores = Scores(model);
            var parts = new List<string> { "auc", model };
            double total = 0;
            int available = 0;
            for (int k = 0; k < classes.Count; k++)
            {
                long wins = 0, positive = 0;
                for (int i = 0; i < test.Count; i++)
                    if (test[i].Label == k)
                    {
                        positive++;
                        for (int j = 0; j < test.Count; j++)
                            if (test[j].Label != k)
                            {
                                int comparison = scores[i][k].CompareTo(scores[j][k]);
                                if (comparison > 0) wins += 2;
                                else if (comparison == 0) wins++;
                            }
                    }
                long denominator = 2 * positive * (test.Count - positive);
                parts.Add(classes[k]); parts.Add(Fraction(wins, denominator));
                if (denominator > 0) { total += (double)wins / denominator; available++; }
            }
            parts.Add("macro"); parts.Add(available == 0 ? "-" : Real(total / available));
            lines.Add(string.Join(" ", parts));
        }
        return lines;
    }
    private List<string> LearningLines()
    {
        var lines = new List<string> { "learning_curve" };
        foreach (int size in settings.Curve)
        {
            var grown = new PrunedTree(builder.Grow(train.Take(size).ToList()));
            PrunedTree pruned = Pruning.ReducedError(grown.Root, validation).Tree;
            lines.Add($"size {size} grown leaves {grown.Leaves().Count} test {Accuracy(grown, test)} pruned leaves {pruned.Leaves().Count} test {Accuracy(pruned, test)}");
        }
        return lines;
    }
    public List<string> EvaluationFile() => Program.Sections(DataLines(), new List<string> { Summary("grown", Grown), Summary("pruned", Pruned) },
        ModelEvaluation("grown"), ModelEvaluation("pruned"), RoutingLines(), CrossValidationLines(), DepthLines(),
        ComplexityLines(), BaggingLines(), McnemarLines(), AucLines(), LearningLines());

    public List<string> ImpurityLines(string title, PrunedTree tree)
    {
        var importance = new double[attributes.Count];
        var splits = new int[attributes.Count];
        foreach (Node node in tree.InternalNodes())
        {
            int index = node.Split!.Attribute.Index;
            importance[index] += Impurity.Decrease(node.Counts, node.Left.Counts, node.Right.Counts);
            splits[index]++;
        }
        double total = 0;
        foreach (double value in importance) total += value;
        double[] shares = importance.Select(value => total == 0 ? 0 : value / total).ToArray();
        List<int> order = Enumerable.Range(0, attributes.Count).OrderByDescending(i => Math.Round(shares[i], 4))
            .ThenBy(i => i).ToList();
        var lines = new List<string> { $"impurity {title}" };
        for (int rank = 0; rank < order.Count; rank++)
        {
            int i = order[rank];
            lines.Add($"{rank + 1} {attributes[i].Name} decrease {Real(importance[i] / train.Count)} share {Real(shares[i])} splits {splits[i]}");
        }
        return lines;
    }
    public List<string> PermutationLines()
    {
        var generator = new Minstd(settings.PermutationSeed);
        int repeats = settings.Repeats, baseCorrect = Pruned.Correct(test);
        var results = new List<Permutation>();
        foreach (Attribute attribute in attributes)
        {
            var counts = new int[repeats];
            for (int repeat = 0; repeat < repeats; repeat++)
            {
                int[] values = test.Select(row => row.Value(attribute)).ToArray();
                for (int position = test.Count; position > 1; position--)
                {
                    int other = (int)(generator.Draw() % position);
                    (values[position - 1], values[other]) = (values[other], values[position - 1]);
                }
                List<Row> rows = test.Select((row, index) => row.WithValue(attribute, values[index])).ToList();
                counts[repeat] = Pruned.Correct(rows);
            }
            results.Add(new Permutation(attribute, counts, repeats * baseCorrect - counts.Sum()));
        }
        results = results.OrderByDescending(result => result.Drop).ThenBy(result => result.Attribute.Index).ToList();
        var lines = new List<string> { $"permutation pruned test repeats {repeats} seed {settings.PermutationSeed} base {Ratio(baseCorrect, test.Count)}" };
        for (int i = 0; i < results.Count; i++)
        {
            Permutation result = results[i];
            lines.Add($"{i + 1} {result.Attribute.Name} correct {CountsText(result.Counts)} drop {Fraction(result.Drop, repeats * test.Count)}");
        }
        return lines;
    }
}

static class Program
{
    public static List<string> Sections(params List<string>[] sections)
    {
        var lines = new List<string>();
        foreach (List<string> section in sections)
        {
            if (lines.Count > 0) lines.Add("");
            lines.AddRange(section);
        }
        return lines;
    }
    public static void Main()
    {
        var analysis = new Analysis(Dataset.Load("input"));
        Directory.CreateDirectory("output");
        var files = new Dictionary<string, List<string>>(StringComparer.Ordinal)
        {
            ["tree.txt"] = Sections(analysis.RootCandidates(), analysis.TreeLines(analysis.Grown), analysis.SurrogateLines()),
            ["pruned_tree.txt"] = analysis.PrunedTreeFile(), ["predictions.csv"] = analysis.PredictionsFile(),
            ["rules.txt"] = analysis.RulesFile(), ["evaluation.txt"] = analysis.EvaluationFile(),
            ["importance.txt"] = Sections(analysis.ImpurityLines("grown", analysis.Grown), analysis.ImpurityLines("pruned", analysis.Pruned), analysis.PermutationLines())
        };
        foreach (var file in files) File.WriteAllText(Path.Combine("output", file.Key), string.Join("\n", file.Value) + "\n", new UTF8Encoding(false));
    }
}
