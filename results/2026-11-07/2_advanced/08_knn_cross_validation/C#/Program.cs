global using System;
global using System.Collections.Generic;
global using System.IO;
global using System.Linq;
using System.Globalization;
using static Report;
using static Validation;

sealed class CrossValidation
{
    public Model Model;
    public List<Prediction> Predictions;
    public bool[] Hits;
    public int Correct;
    public double Error;
    public CrossValidation(Model model, List<Row> rows, List<Prediction> predictions)
    {
        Model = model; Predictions = predictions;
        Hits = predictions.Select((prediction, index) => prediction.Result.Label == rows[index].Label).ToArray(); Correct = Hits.Count(hit => hit);
        Error = Rmse(predictions.Select((prediction, index) => prediction.Estimate - rows[index].Target!.Value).ToList());
    }
}
sealed class ClassifierSpace
{
    readonly Model model;
    readonly Dictionary<string, List<Neighbor>> orders;
    public ClassifierSpace(Model model, List<Row> train, List<Row> test, List<int> features)
    {
        this.model = model; List<Row> queries = train.Concat(test).ToList();
        var found = Orders(train, queries, model.Scaling, model.Metric, features);
        orders = queries.Select((query, j) => (query.Id, Order: found[j])).ToDictionary(pair => pair.Id, pair => pair.Order, StringComparer.Ordinal);
    }
    public List<Neighbor> Order(Row query, List<Row> rows)
    {
        HashSet<string> included = new(rows.Select(row => row.Id), StringComparer.Ordinal); return orders[query.Id].Where(neighbor => included.Contains(neighbor.Row.Id)).ToList();
    }
    public Vote Predict(Row query, List<Row> rows, int k) => Neighbors.Vote(Order(query, rows).Take(k).ToList(), model.Weighting);
}

sealed class Experiment
{
    readonly Input data;
    readonly Settings s;
    readonly List<Row> train, test, labelled, targeted;
    readonly List<string> labels;
    readonly List<int> features;
    readonly List<Model> grid = [];
    readonly List<List<int>> folds;
    readonly List<CrossValidation> results;
    readonly CrossValidation classifier, regressor;
    readonly List<Prediction> testPredictions, testEstimates;
    public Experiment(Input input)
    {
        data = input; s = input.Settings; train = input.Train; test = input.Test;
        labelled = test.Where(row => row.Label != null).ToList(); targeted = test.Where(row => row.Target.HasValue).ToList();
        labels = train.Select(row => row.Label!).Distinct(StringComparer.Ordinal).Order(StringComparer.Ordinal).ToList(); features = Enumerable.Range(0, data.Features.Length).ToList();
        foreach (int k in s.Ks) foreach (string metric in s.Metrics) foreach (string weighting in s.Weightings) foreach (string scaling in s.Scalings) grid.Add(new(k, metric, weighting, scaling));
        folds = Folds(train, s.Folds); results = CrossValidate(grid, train, s.Folds, features); classifier = BestClassifier(results); regressor = BestRegressor(results);
        testPredictions = Predict(classifier.Model, train, test, features); testEstimates = Predict(regressor.Model, train, test, features);
    }
    static string RowText(params object[] values) => string.Join(" ", values);
    static List<string> Parts(List<List<string>> sections)
    {
        List<string> lines = []; foreach (List<string> section in sections) { if (lines.Count > 0) lines.Add(""); lines.AddRange(section); } return lines;
    }
    static int CorrectCount(List<Prediction> predictions, List<Row> rows) => predictions.Where((prediction, index) => prediction.Result.Label == rows[index].Label).Count();
    static List<double> Errors(List<Prediction> predictions, List<Row> rows) => predictions.Select((prediction, index) => prediction.Estimate - rows[index].Target!.Value).ToList();
    static List<CrossValidation> CrossValidate(List<Model> models, List<Row> rows, int foldCount, List<int> features)
    {
        Prediction[][] predictions = models.Select(_ => new Prediction[rows.Count]).ToArray();
        var spaces = models.Select(model => (model.Scaling, model.Metric)).Distinct().ToList();
        foreach (List<int> fold in Folds(rows, foldCount))
        {
            List<Row> training = Without(rows, fold), queries = Selected(rows, fold);
            foreach (var space in spaces)
            {
                var orders = Orders(training, queries, space.Scaling, space.Metric, features);
                for (int m = 0; m < models.Count; m++) if (models[m].Scaling == space.Scaling && models[m].Metric == space.Metric)
                    for (int j = 0; j < fold.Count; j++) predictions[m][fold[j]] = FromOrder(orders[j], models[m].K, models[m].Weighting);
            }
        }
        return models.Select((model, j) => new CrossValidation(model, rows, predictions[j].ToList())).ToList();
    }
    static CrossValidation BestClassifier(IEnumerable<CrossValidation> results) => results.OrderByDescending(result => result.Correct).First();
    static CrossValidation BestRegressor(IEnumerable<CrossValidation> results) => results.OrderBy(result => FourDecimal(result.Error)).First();
    string LabelCounts(IEnumerable<Row> rows)
    {
        Dictionary<string, int> counts = rows.GroupBy(row => row.Label!, StringComparer.Ordinal).ToDictionary(group => group.Key, group => group.Count(), StringComparer.Ordinal);
        return string.Join(" ", labels.Select(label => RowText(label, counts.GetValueOrDefault(label))));
    }
    string Names(List<int> chosen) => string.Join(" ", chosen.Select(feature => data.Features[feature]));
    string TrainRatio(int count) => Ratio(count, train.Count);
    string Summary(CrossValidation result, bool regression) => regression ? RowText(result.Model.Notation, "rmse", Fixed(result.Error), "correct", TrainRatio(result.Correct)) : RowText(result.Model.Notation, "correct", TrainRatio(result.Correct), "rmse", Fixed(result.Error));
    List<string> Evaluation(List<Row> rows, List<Prediction> predictions)
    {
        int size = labels.Count; int[,] matrix = new int[size, size];
        for (int j = 0; j < rows.Count; j++) matrix[labels.IndexOf(rows[j].Label!), labels.IndexOf(predictions[j].Result.Label)]++;
        List<string> lines = ["true\\predicted " + string.Join(" ", labels)];
        for (int a = 0; a < size; a++) lines.Add(labels[a] + " " + string.Join(" ", Enumerable.Range(0, size).Select(b => matrix[a, b])));
        double[] totals = new double[3]; int[] valued = new int[3];
        for (int c = 0; c < size; c++)
        {
            int predicted = 0, actual = 0, hit = matrix[c, c];
            for (int j = 0; j < size; j++) { predicted += matrix[j, c]; actual += matrix[c, j]; }
            (int Numerator, int Denominator)[] metrics = [(hit, predicted), (hit, actual), (2 * hit, predicted + actual)];
            for (int j = 0; j < 3; j++) if (metrics[j].Denominator != 0) { totals[j] += (double)metrics[j].Numerator / metrics[j].Denominator; valued[j]++; }
            lines.Add(RowText("class", labels[c], "precision", Fraction(hit, predicted), "recall", Fraction(hit, actual), "f1", Fraction(2 * hit, predicted + actual), "support", actual));
        }
        string Mean(int index) => valued[index] == 0 ? "-" : Fixed(totals[index] / valued[index]);
        lines.Add(RowText("macro precision", Mean(0), "recall", Mean(1), "f1", Mean(2))); return lines;
    }
    List<string> Reliability(List<Row> rows, List<Prediction> predictions)
    {
        double[] lowers = [0, ..s.Bins], shares = new double[s.Bins.Length + 1]; int[] counts = new int[lowers.Length], hits = new int[lowers.Length];
        for (int j = 0; j < rows.Count; j++)
        {
            int bin = s.Bins.Count(bound => bound <= predictions[j].Result.Share); counts[bin]++;
            if (predictions[j].Result.Label == rows[j].Label) hits[bin]++; shares[bin] += predictions[j].Result.Share;
        }
        return Enumerable.Range(0, lowers.Length).Select(j => counts[j] == 0 ? RowText("bin", Fixed(lowers[j], 2), "rows 0") : RowText("bin", Fixed(lowers[j], 2), "rows", counts[j], "correct", Ratio(hits[j], counts[j]), "share", Fixed(shares[j] / counts[j]))).ToList();
    }
    List<Prediction> LabelledPredictions() => testPredictions.Where((_, index) => test[index].Label != null).ToList();
    List<List<string>> LeaveOneOut()
    {
        Model model = classifier.Model; Dictionary<int, List<Prediction>> byK = s.Ks.ToDictionary(k => k, _ => new List<Prediction>()); List<Prediction> estimates = [];
        for (int j = 0; j < train.Count; j++)
        {
            List<Row> others = Without(train, [j]); var order = Orders(others, [train[j]], model.Scaling, model.Metric, features)[0];
            foreach (int k in s.Ks) byK[k].Add(FromOrder(order, k, model.Weighting)); estimates.Add(Predict(regressor.Model, others, [train[j]], features)[0]);
        }
        List<Prediction> predictions = byK[model.K]; List<int> failed = Enumerable.Range(0, train.Count).Where(j => predictions[j].Result.Label != train[j].Label).ToList();
        List<string> classification = [RowText("leave_one_out classifier", model.Notation), RowText("errors", TrainRatio(failed.Count)), "class_errors " + LabelCounts(failed.Select(j => train[j]))];
        foreach (int j in failed.OrderBy(j => train[j].Id, StringComparer.Ordinal)) classification.Add(RowText(train[j].Id, "true", train[j].Label!, "predicted", predictions[j].Result.Label, "share", Fixed(predictions[j].Result.Share)));
        List<double> residuals = Errors(estimates, train);
        List<int> ranked = Enumerable.Range(0, train.Count).OrderByDescending(j => FourDecimal(Math.Abs(residuals[j]))).ThenBy(j => train[j].Id, StringComparer.Ordinal).ToList();
        List<string> regression = [RowText("leave_one_out regressor", regressor.Model.Notation), RowText("rmse", Fixed(Rmse(residuals)), "mae", Fixed(Mae(residuals))), RowText("largest", s.Top, "residuals")];
        foreach (int j in ranked.Take(s.Top)) regression.Add(RowText(train[j].Id, "target", Fixed(train[j].Target!.Value), "estimate", Fixed(estimates[j].Estimate), "residual", Fixed(residuals[j])));
        List<string> perK = [RowText("leave_one_out by k metric=" + model.Metric, "weighting=" + model.Weighting, "scaling=" + model.Scaling)];
        foreach (int k in s.Ks) perK.Add(RowText("k=" + k, "correct", TrainRatio(CorrectCount(byK[k], train)), "rmse", Fixed(Rmse(Errors(byK[k], train)))));
        return [classification, regression, perK];
    }
    List<string> Nested()
    {
        List<string> lines = [RowText("nested_cross_validation folds", s.Folds)]; double[] estimates = new double[train.Count]; int correct = 0;
        for (int f = 0; f < folds.Count; f++)
        {
            List<Row> inner = Without(train, folds[f]), queries = Selected(train, folds[f]); var innerResults = CrossValidate(grid, inner, s.Folds, features);
            CrossValidation c = BestClassifier(innerResults), r = BestRegressor(innerResults);
            var predictions = Predict(c.Model, inner, queries, features); var predictedEstimates = Predict(r.Model, inner, queries, features);
            int hits = CorrectCount(predictions, queries); correct += hits;
            for (int j = 0; j < queries.Count; j++) estimates[folds[f][j]] = predictedEstimates[j].Estimate;
            lines.Add(RowText("fold", f + 1, "classifier", c.Model.Notation, "inner", Fixed((double)c.Correct / inner.Count), "outer", Ratio(hits, queries.Count)));
            lines.Add(RowText("fold", f + 1, "regressor", r.Model.Notation, "inner", Fixed(r.Error), "outer", Fixed(Rmse(Errors(predictedEstimates, queries)))));
        }
        List<double> residuals = estimates.Select((estimate, j) => estimate - train[j].Target!.Value).ToList();
        lines.Add(RowText("nested accuracy", TrainRatio(correct), "rmse", Fixed(Rmse(residuals)))); return lines;
    }
    List<string> FeatureSelection()
    {
        Model model = classifier.Model; List<int> current = [..features], chosen = [..features]; int chosenCount = classifier.Correct, step = 0;
        List<string> lines = [RowText("feature_selection", model.Notation), RowText("start features", Names(current), "correct", TrainRatio(chosenCount))];
        while (current.Count >= 3)
        {
            int remove = current[0], maximum = -1; List<string> candidates = [];
            foreach (int feature in current)
            {
                int count = CrossValidate([model], train, s.Folds, current.Where(other => other != feature).ToList())[0].Correct;
                candidates.Add(RowText(data.Features[feature], count)); if (count > maximum) { maximum = count; remove = feature; }
            }
            current.Remove(remove); lines.Add(RowText("step", ++step, "remove", data.Features[remove], "correct", TrainRatio(maximum), "candidates", string.Join(" ", candidates)));
            if (maximum >= chosenCount) { chosen = [..current]; chosenCount = maximum; }
        }
        int testCorrect = CorrectCount(Predict(model, train, labelled, chosen), labelled);
        lines.Add(RowText("selected features", Names(chosen), "correct", TrainRatio(chosenCount))); lines.Add(RowText("selected test", Ratio(testCorrect, labelled.Count))); return lines;
    }
    List<string> MetricsReport()
    {
        List<List<string>> sections = [[RowText("data train", train.Count, "test", test.Count, "labelled", labelled.Count, "targets", targeted.Count, "features", features.Count, "classes", labels.Count), "classes " + LabelCounts(train)]];
        foreach (string method in s.Scalings)
        {
            Scaling scaling = Scaling.Compute(train, method); List<string> lines = [RowText("scaling", method)];
            foreach (int feature in features) lines.Add(RowText(data.Features[feature], "center", Fixed(scaling.Centers[feature], 6), "scale", Fixed(scaling.Scales[feature], 6))); sections.Add(lines);
        }
        List<string> foldLines = [RowText("folds", s.Folds)];
        for (int f = 0; f < folds.Count; f++) foldLines.Add(RowText("fold", f + 1, "size", folds[f].Count, LabelCounts(Selected(train, folds[f])))); sections.Add(foldLines);
        sections.Add([RowText("grid", grid.Count), "best_classifier " + Summary(classifier, false), "best_regressor " + Summary(regressor, true)]);
        foreach (bool regression in new[] { false, true })
        {
            var ranking = regression ? results.OrderBy(result => FourDecimal(result.Error)) : results.OrderByDescending(result => result.Correct);
            List<string> lines = [RowText("top", s.Top, "by", regression ? "rmse" : "accuracy")];
            lines.AddRange(ranking.Take(s.Top).Select((result, rank) => RowText(rank + 1, Summary(result, regression)))); sections.Add(lines);
        }
        for (int item = 0; item < 4; item++)
        {
            string name = item == 0 ? "k" : item == 1 ? "metric" : item == 2 ? "weighting" : "scaling";
            IEnumerable<string> values = item == 0 ? s.Ks.Select(k => k.ToString()) : item == 1 ? s.Metrics : item == 2 ? s.Weightings : s.Scalings;
            List<string> lines = ["best per " + name];
            foreach (string value in values)
            {
                string Attribute(Model model) => item == 0 ? model.K.ToString() : item == 1 ? model.Metric : item == 2 ? model.Weighting : model.Scaling;
                var chosen = results.Where(result => Attribute(result.Model) == value).ToList(); CrossValidation c = BestClassifier(chosen), r = BestRegressor(chosen);
                lines.Add(RowText(name + "=" + value, "classifier", c.Model.Notation, "accuracy", Fixed((double)c.Correct / train.Count), "regressor", r.Model.Notation, "rmse", Fixed(r.Error)));
            }
            sections.Add(lines);
        }
        List<string> classifierFolds = ["classifier folds"], regressorFolds = ["regressor folds"];
        for (int f = 0; f < folds.Count; f++)
        {
            int correct = folds[f].Count(index => classifier.Hits[index]); List<double> residuals = folds[f].Select(index => regressor.Predictions[index].Estimate - train[index].Target!.Value).ToList();
            classifierFolds.Add(RowText("fold", f + 1, "correct", Ratio(correct, folds[f].Count)));
            regressorFolds.Add(RowText("fold", f + 1, "size", folds[f].Count, "rmse", Fixed(Rmse(residuals))));
        }
        sections.Add(classifierFolds); sections.Add(regressorFolds);
        sections.Add(["cross_validation classes", ..Evaluation(train, classifier.Predictions)]); sections.Add(["cross_validation reliability", ..Reliability(train, classifier.Predictions)]);
        List<string> mcnemar = ["mcnemar"];
        foreach (string metric in s.Metrics)
        {
            CrossValidation comparison = BestClassifier(results.Where(result => result.Model.Metric == metric)); int b = 0, c = 0;
            for (int j = 0; j < train.Count; j++) { if (classifier.Hits[j] && !comparison.Hits[j]) b++; if (comparison.Hits[j] && !classifier.Hits[j]) c++; }
            int adjusted = Math.Max(0, Math.Abs(b - c) - 1), numerator = adjusted * adjusted;
            mcnemar.Add(RowText(comparison.Model.Notation, "b", b, "c", c, "statistic", b + c == 0 ? "0/1 0.0000" : Fraction(numerator, b + c), "significant", 1000 * numerator > 3841 * (b + c) ? "yes" : "no"));
        }
        sections.Add(mcnemar); sections.AddRange(LeaveOneOut()); sections.Add(Nested()); sections.Add(FeatureSelection());
        List<Prediction> labelledResults = LabelledPredictions();
        sections.Add([RowText("test classification", classifier.Model.Notation), RowText("labelled", labelled.Count, "correct", Ratio(CorrectCount(labelledResults, labelled), labelled.Count)), ..Evaluation(labelled, labelledResults)]);
        sections.Add(["test reliability", ..Reliability(labelled, labelledResults)]);
        double[] margins = testPredictions.Select(prediction => prediction.Result.Share - prediction.Result.RunnerShare).ToArray();
        List<string> uncertain = [RowText("uncertain", s.Top, "test rows")];
        foreach (int j in Enumerable.Range(0, test.Count).OrderBy(j => FourDecimal(margins[j])).Take(s.Top))
        {
            Vote v = testPredictions[j].Result;
            uncertain.Add(RowText(test[j].Id, "predicted", v.Label, "share", Fixed(v.Share), "runner_up", v.Runner ?? "-", "share", Fixed(v.RunnerShare), "margin", Fixed(margins[j]), "true", test[j].Label ?? "-"));
        }
        sections.Add(uncertain);
        List<int> targetIndices = Enumerable.Range(0, test.Count).Where(j => test[j].Target.HasValue).ToList();
        List<double> targetErrors = targetIndices.Select(j => testEstimates[j].Estimate - test[j].Target!.Value).ToList(), targets = targetIndices.Select(j => test[j].Target!.Value).ToList();
        List<string> regressionLines = [RowText("test regression", regressor.Model.Notation), RowText("targets", targets.Count, "rmse", Fixed(Rmse(targetErrors)), "mae", Fixed(Mae(targetErrors)), "r2", Fixed(RSquared(targetErrors, targets)))];
        foreach (string label in labels)
        {
            List<double> classErrors = targetIndices.Where(j => test[j].Label == label).Select(j => testEstimates[j].Estimate - test[j].Target!.Value).ToList();
            regressionLines.Add(RowText("class", label, "targets", classErrors.Count, "rmse", classErrors.Count == 0 ? "-" : Fixed(Rmse(classErrors))));
        }
        sections.Add(regressionLines);
        List<string> mistakes = ["misclassified test rows"]; int count = 0;
        for (int j = 0; j < test.Count; j++) if (test[j].Label != null && testPredictions[j].Result.Label != test[j].Label)
        {
            count++; Vote v = testPredictions[j].Result; mistakes.Add(RowText(test[j].Id, "true", test[j].Label!, "predicted", v.Label, "share", Fixed(v.Share)));
            foreach (Neighbor neighbor in testPredictions[j].Neighbors) mistakes.Add("  " + RowText(neighbor.Row.Id, neighbor.Row.Label!, Fixed(neighbor.Distance)));
        }
        mistakes.Add(RowText("count", count)); sections.Add(mistakes); return Parts(sections);
    }
    List<string> LearningCurve()
    {
        List<string> lines = ["n,train_size,correct,accuracy,rmse"];
        foreach (int limit in s.Curve)
        {
            Dictionary<string, int> taken = new(StringComparer.Ordinal); List<Row> chosen = [];
            foreach (Row row in train) if (taken.GetValueOrDefault(row.Label!) < limit) { taken[row.Label!] = taken.GetValueOrDefault(row.Label!) + 1; chosen.Add(row); }
            int correct = CorrectCount(Predict(classifier.Model, chosen, labelled, features), labelled);
            double error = Rmse(Errors(Predict(regressor.Model, chosen, targeted, features), targeted));
            lines.Add(string.Join(",", limit, chosen.Count, correct, Fixed((double)correct / labelled.Count), Fixed(error)));
        }
        return lines;
    }
    static (List<Row> Rows, int Scans) Condense(ClassifierSpace space, List<Row> rows)
    {
        List<Row> store = [rows[0]]; HashSet<string> stored = new(StringComparer.Ordinal) { rows[0].Id }; int scans = 0;
        while (true)
        {
            scans++; bool added = false;
            foreach (Row row in rows) if (!stored.Contains(row.Id) && space.Order(row, store)[0].Row.Label != row.Label) { store.Add(row); stored.Add(row.Id); added = true; }
            if (!added) break;
        }
        return (store.OrderBy(row => row.Id, StringComparer.Ordinal).ToList(), scans);
    }
    static List<string> IdLines(List<Row> rows) => rows.Chunk(10).Select(group => string.Join(" ", group.Select(row => row.Id))).ToList();
    List<string> Prototypes()
    {
        Model model = classifier.Model; ClassifierSpace space = new(model, train, test, features);
        List<Row> ordered = train.OrderBy(row => row.Id, StringComparer.Ordinal).ToList(), edited = [..ordered];
        List<string> editing = [RowText("editing k=" + s.EditK)]; int pass = 0;
        while (true)
        {
            List<(Row Row, Vote Result)> removals = [];
            foreach (Row row in edited)
            {
                Vote result = space.Predict(row, edited.Where(other => other.Id != row.Id).ToList(), s.EditK);
                if (result.Label != row.Label) removals.Add((row, result));
            }
            editing.Add(RowText("pass", ++pass, "removed", removals.Count));
            foreach (var removal in removals) editing.Add("  " + RowText(removal.Row.Id, "true", removal.Row.Label!, "predicted", removal.Result.Label, "share", Fixed(removal.Result.Share)));
            if (removals.Count == 0) break;
            HashSet<string> removed = new(removals.Select(removal => removal.Row.Id), StringComparer.Ordinal); edited.RemoveAll(row => removed.Contains(row.Id));
        }
        editing.Add(RowText("edited size", edited.Count, "removed", train.Count - edited.Count));
        var condensed = Condense(space, ordered); var editedCondensed = Condense(space, edited);
        List<List<string>> sections = [[RowText("space", model.Notation)], editing, [RowText("condensing original scans", condensed.Scans, "size", condensed.Rows.Count), RowText("condensing edited scans", editedCondensed.Scans, "size", editedCondensed.Rows.Count)]];
        List<Row>[] sets = [ordered, edited, condensed.Rows, editedCondensed.Rows]; string[] setNames = ["original", "edited", "condensed", "edited_condensed"]; List<string> setLines = [];
        for (int j = 0; j < sets.Length; j++)
        {
            int knn = 0, one = 0;
            foreach (Row row in labelled) { if (space.Predict(row, sets[j], model.K).Label == row.Label) knn++; if (space.Order(row, sets[j])[0].Row.Label == row.Label) one++; }
            setLines.Add(RowText("set", setNames[j], "size", sets[j].Count, LabelCounts(sets[j]), "knn", Ratio(knn, labelled.Count), "1nn", Ratio(one, labelled.Count)));
        }
        sections.Add(setLines); sections.Add(["prototypes condensed", ..IdLines(condensed.Rows)]); sections.Add(["prototypes edited_condensed", ..IdLines(editedCondensed.Rows)]);
        List<string> borders = ["borders"]; int total = 0;
        foreach (string label in labels)
        {
            int count = 0, boundary = 0; double same = 0, other = 0;
            foreach (Row row in ordered.Where(row => row.Label == label))
            {
                count++; var order = space.Order(row, ordered.Where(reference => reference.Id != row.Id).ToList()); if (order[0].Row.Label != label) boundary++;
                same += order.First(neighbor => neighbor.Row.Label == label).Distance; other += order.First(neighbor => neighbor.Row.Label != label).Distance;
            }
            total += boundary; borders.Add(RowText("class", label, "size", count, "border", boundary, "same", Fixed(same / count), "other", Fixed(other / count)));
        }
        borders.Add(RowText("border total", TrainRatio(total))); sections.Add(borders);
        Dictionary<string, int> occurrences = train.ToDictionary(row => row.Id, _ => 0, StringComparer.Ordinal);
        foreach (Prediction prediction in testPredictions) foreach (Neighbor neighbor in prediction.Neighbors) occurrences[neighbor.Row.Id]++;
        List<string> hubs = [RowText("hubs k=" + model.K, "queries", test.Count)];
        foreach (Row row in ordered.OrderByDescending(row => occurrences[row.Id]).Take(s.Top)) hubs.Add(RowText(row.Id, row.Label!, occurrences[row.Id]));
        hubs.Add(RowText("anti_hubs", occurrences.Values.Count(value => value == 0))); sections.Add(hubs); return Parts(sections);
    }
    public void Write()
    {
        List<string> gridLines = ["k,metric,weighting,scaling,correct,accuracy,rmse"];
        foreach (CrossValidation result in results)
        {
            Model model = result.Model; gridLines.Add(string.Join(",", model.K, model.Metric, model.Weighting, model.Scaling, result.Correct, Fixed((double)result.Correct / train.Count), Fixed(result.Error)));
        }
        List<string> predictions = ["id,label,vote_share,estimate"];
        for (int j = 0; j < test.Count; j++) predictions.Add(string.Join(",", test[j].Id, testPredictions[j].Result.Label, Fixed(testPredictions[j].Result.Share), Fixed(testEstimates[j].Estimate)));
        Report.Write("cv_grid.csv", gridLines); Report.Write("predictions.csv", predictions); Report.Write("metrics.txt", MetricsReport()); Report.Write("learning_curve.csv", LearningCurve()); Report.Write("prototypes.txt", Prototypes());
    }
}
static class Program
{
    static void Main() { CultureInfo.CurrentCulture = CultureInfo.InvariantCulture; new Experiment(Dataset.Read()).Write(); }
}
