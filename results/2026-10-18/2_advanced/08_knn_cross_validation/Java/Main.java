import java.io.IOException;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeMap;
import java.util.stream.IntStream;

public final class Main {
    static String row(Object... parts) { return String.join(" ", Arrays.stream(parts).map(Object::toString).toList()); }
    static String fixed(double value) { return Report.fixed(value); }
    static String fixed(double value, int places) { return Report.fixed(value, places); }
    static double fourDecimal(double value) { return Report.fourDecimal(value); }
    static String ratio(int numerator, int denominator) { return Report.ratio(numerator, denominator); }
    static String fraction(int numerator, int denominator) { return Report.fraction(numerator, denominator); }
    static double rmse(List<Double> errors) { return Validation.rmse(errors); }
    static double mae(List<Double> errors) { return Validation.mae(errors); }
    static List<Prediction> predict(Model model, List<Row> training, List<Row> queries, List<Integer> features) { return Validation.predict(model, training, queries, features); }
    static List<Integer> indices(int count) { return IntStream.range(0, count).boxed().toList(); }
    static List<String> parts(List<List<String>> sections) {
        List<String> lines = new ArrayList<>(); for (List<String> section : sections) { if (!lines.isEmpty()) lines.add(""); lines.addAll(section); } return lines;
    }
    static int correctCount(List<Prediction> predictions, List<Row> rows) {
        int correct = 0; for (int j = 0; j < rows.size(); j++) if (predictions.get(j).result().label().equals(rows.get(j).label())) correct++; return correct;
    }
    static List<Double> errors(List<Prediction> predictions, List<Row> rows) { return IntStream.range(0, rows.size()).mapToObj(j -> predictions.get(j).estimate() - rows.get(j).target()).toList(); }
    static final class CrossValidation {
        final Model model;
        final List<Prediction> predictions;
        final boolean[] hits;
        final int correct;
        final double error;
        CrossValidation(Model model, List<Row> rows, List<Prediction> predictions) {
            this.model = model; this.predictions = predictions; hits = new boolean[rows.size()]; int count = 0;
            for (int j = 0; j < rows.size(); j++) { hits[j] = predictions.get(j).result().label().equals(rows.get(j).label()); if (hits[j]) count++; }
            correct = count; error = rmse(errors(predictions, rows));
        }
    }
    record ModelSpace(String scaling, String metric) {}
    static List<CrossValidation> crossValidate(List<Model> models, List<Row> rows, int foldCount, List<Integer> features) {
        Prediction[][] predictions = new Prediction[models.size()][rows.size()];
        List<ModelSpace> spaces = models.stream().map(model -> new ModelSpace(model.scaling(), model.metric())).distinct().toList();
        for (List<Integer> fold : Validation.folds(rows, foldCount)) {
            List<Row> training = Validation.without(rows, fold), queries = Validation.selected(rows, fold);
            for (ModelSpace space : spaces) {
                var orders = Validation.orders(training, queries, space.scaling, space.metric, features);
                for (int m = 0; m < models.size(); m++) if (models.get(m).scaling().equals(space.scaling) && models.get(m).metric().equals(space.metric))
                    for (int j = 0; j < fold.size(); j++) predictions[m][fold.get(j)] = Validation.fromOrder(orders.get(j), models.get(m).k(), models.get(m).weighting());
            }
        }
        return IntStream.range(0, models.size()).mapToObj(j -> new CrossValidation(models.get(j), rows, Arrays.asList(predictions[j]))).toList();
    }
    static CrossValidation bestClassifier(List<CrossValidation> results) {
        CrossValidation best = results.getFirst(); for (CrossValidation result : results) if (result.correct > best.correct) best = result; return best;
    }
    static CrossValidation bestRegressor(List<CrossValidation> results) {
        CrossValidation best = results.getFirst(); for (CrossValidation result : results) if (fourDecimal(result.error) < fourDecimal(best.error)) best = result; return best;
    }
    static final class ClassifierSpace {
        final Model model;
        final Map<String, List<Neighbor>> orders = new HashMap<>();
        ClassifierSpace(Model model, List<Row> train, List<Row> test, List<Integer> features) {
            this.model = model; List<Row> queries = new ArrayList<>(train); queries.addAll(test);
            var found = Validation.orders(train, queries, model.scaling(), model.metric(), features);
            for (int j = 0; j < queries.size(); j++) orders.put(queries.get(j).id(), found.get(j));
        }
        List<Neighbor> order(Row query, List<Row> rows) {
            Set<String> included = new HashSet<>(rows.stream().map(Row::id).toList()); return orders.get(query.id()).stream().filter(neighbor -> included.contains(neighbor.row().id())).toList();
        }
        Vote predict(Row query, List<Row> rows, int k) { List<Neighbor> found = order(query, rows); return Neighbors.vote(found.subList(0, Math.min(k, found.size())), model.weighting()); }
    }
    static final class Experiment {
        final Input data;
        final Settings s;
        final List<Row> train, test, labelled, targeted;
        final List<String> labels;
        final List<Integer> features;
        final List<Model> grid = new ArrayList<>();
        final List<List<Integer>> folds;
        final List<CrossValidation> results;
        final CrossValidation classifier, regressor;
        final List<Prediction> testPredictions, testEstimates;
        Experiment(Input data) {
            this.data = data; s = data.settings(); train = data.train(); test = data.test();
            labelled = test.stream().filter(row -> row.label() != null).toList(); targeted = test.stream().filter(row -> row.target() != null).toList();
            labels = train.stream().map(Row::label).distinct().sorted().toList(); features = indices(data.features().size());
            for (int k : s.ks()) for (String metric : s.metrics()) for (String weighting : s.weightings()) for (String scaling : s.scalings()) grid.add(new Model(k, metric, weighting, scaling));
            folds = Validation.folds(train, s.folds()); results = crossValidate(grid, train, s.folds(), features); classifier = bestClassifier(results); regressor = bestRegressor(results);
            testPredictions = predict(classifier.model, train, test, features); testEstimates = predict(regressor.model, train, test, features);
        }
        String labelCounts(List<Row> rows) {
            Map<String, Integer> counts = new TreeMap<>(); for (Row row : rows) counts.merge(row.label(), 1, Integer::sum);
            return String.join(" ", labels.stream().map(label -> row(label, counts.getOrDefault(label, 0))).toList());
        }
        String names(List<Integer> chosen) { return String.join(" ", chosen.stream().map(data.features()::get).toList()); }
        String trainRatio(int correct) { return ratio(correct, train.size()); }
        String summary(CrossValidation result, boolean regression) { return regression ? row(result.model.notation(), "rmse", fixed(result.error), "correct", trainRatio(result.correct)) : row(result.model.notation(), "correct", trainRatio(result.correct), "rmse", fixed(result.error)); }
        List<String> evaluation(List<Row> rows, List<Prediction> predictions) {
            int size = labels.size(); int[][] matrix = new int[size][size];
            for (int j = 0; j < rows.size(); j++) matrix[labels.indexOf(rows.get(j).label())][labels.indexOf(predictions.get(j).result().label())]++;
            List<String> lines = new ArrayList<>(List.of("true\\predicted " + String.join(" ", labels)));
            for (int a = 0; a < size; a++) lines.add(labels.get(a) + " " + String.join(" ", Arrays.stream(matrix[a]).mapToObj(Integer::toString).toList()));
            double[] totals = new double[3]; int[] valued = new int[3];
            for (int c = 0; c < size; c++) {
                int predicted = 0, actual = 0, hit = matrix[c][c];
                for (int j = 0; j < size; j++) { predicted += matrix[j][c]; actual += matrix[c][j]; }
                int[][] metrics = {{hit, predicted}, {hit, actual}, {2 * hit, predicted + actual}};
                for (int j = 0; j < 3; j++) if (metrics[j][1] != 0) { totals[j] += (double)metrics[j][0] / metrics[j][1]; valued[j]++; }
                lines.add(row("class", labels.get(c), "precision", fraction(hit, predicted), "recall", fraction(hit, actual), "f1", fraction(2 * hit, predicted + actual), "support", actual));
            }
            lines.add(row("macro precision", valued[0] == 0 ? "-" : fixed(totals[0] / valued[0]), "recall", valued[1] == 0 ? "-" : fixed(totals[1] / valued[1]), "f1", valued[2] == 0 ? "-" : fixed(totals[2] / valued[2]))); return lines;
        }
        List<String> reliability(List<Row> rows, List<Prediction> predictions) {
            List<Double> lowers = new ArrayList<>(List.of(0.0)); lowers.addAll(s.bins()); int[] counts = new int[lowers.size()], hits = new int[lowers.size()]; double[] shares = new double[lowers.size()];
            for (int j = 0; j < rows.size(); j++) {
                int bin = 0; for (double bound : s.bins()) if (bound <= predictions.get(j).result().share()) bin++;
                counts[bin]++; if (predictions.get(j).result().label().equals(rows.get(j).label())) hits[bin]++; shares[bin] += predictions.get(j).result().share();
            }
            List<String> lines = new ArrayList<>();
            for (int j = 0; j < lowers.size(); j++) lines.add(counts[j] == 0 ? row("bin", fixed(lowers.get(j), 2), "rows 0") : row("bin", fixed(lowers.get(j), 2), "rows", counts[j], "correct", ratio(hits[j], counts[j]), "share", fixed(shares[j] / counts[j]))); return lines;
        }
        List<Prediction> labelledPredictions() { return IntStream.range(0, test.size()).filter(j -> test.get(j).label() != null).mapToObj(testPredictions::get).toList(); }
        List<List<String>> leaveOneOut() {
            Model model = classifier.model; Map<Integer, List<Prediction>> byK = new LinkedHashMap<>(); for (int k : s.ks()) byK.put(k, new ArrayList<>()); List<Prediction> estimates = new ArrayList<>();
            for (int j = 0; j < train.size(); j++) {
                List<Row> others = Validation.without(train, List.of(j)); var order = Validation.orders(others, List.of(train.get(j)), model.scaling(), model.metric(), features).getFirst();
                for (int k : s.ks()) byK.get(k).add(Validation.fromOrder(order, k, model.weighting())); estimates.add(predict(regressor.model, others, List.of(train.get(j)), features).getFirst());
            }
            List<Prediction> predictions = byK.get(model.k()); List<Integer> failed = indices(train.size()).stream().filter(j -> !predictions.get(j).result().label().equals(train.get(j).label())).toList();
            List<String> classification = new ArrayList<>(List.of(row("leave_one_out classifier", model.notation()), row("errors", trainRatio(failed.size())), "class_errors " + labelCounts(Validation.selected(train, failed))));
            for (int j : failed.stream().sorted(Comparator.comparing(j -> train.get(j).id())).toList()) classification.add(row(train.get(j).id(), "true", train.get(j).label(), "predicted", predictions.get(j).result().label(), "share", fixed(predictions.get(j).result().share())));
            List<Double> residuals = errors(estimates, train); List<Integer> ranked = indices(train.size()).stream().sorted(Comparator.<Integer>comparingDouble(j -> fourDecimal(Math.abs(residuals.get(j)))).reversed().thenComparing(j -> train.get(j).id())).toList();
            List<String> regression = new ArrayList<>(List.of(row("leave_one_out regressor", regressor.model.notation()), row("rmse", fixed(rmse(residuals)), "mae", fixed(mae(residuals))), row("largest", s.top(), "residuals")));
            for (int j : ranked.stream().limit(s.top()).toList()) regression.add(row(train.get(j).id(), "target", fixed(train.get(j).target()), "estimate", fixed(estimates.get(j).estimate()), "residual", fixed(residuals.get(j))));
            List<String> perK = new ArrayList<>(List.of(row("leave_one_out by k metric=" + model.metric(), "weighting=" + model.weighting(), "scaling=" + model.scaling())));
            for (int k : s.ks()) perK.add(row("k=" + k, "correct", trainRatio(correctCount(byK.get(k), train)), "rmse", fixed(rmse(errors(byK.get(k), train)))));
            return List.of(classification, regression, perK);
        }
        List<String> nested() {
            List<String> lines = new ArrayList<>(List.of(row("nested_cross_validation folds", s.folds()))); double[] estimates = new double[train.size()]; int correct = 0;
            for (int f = 0; f < folds.size(); f++) {
                List<Row> inner = Validation.without(train, folds.get(f)), queries = Validation.selected(train, folds.get(f)); var innerResults = crossValidate(grid, inner, s.folds(), features);
                CrossValidation c = bestClassifier(innerResults), r = bestRegressor(innerResults); var predictions = predict(c.model, inner, queries, features); var predictedEstimates = predict(r.model, inner, queries, features);
                int hits = correctCount(predictions, queries); correct += hits;
                for (int j = 0; j < queries.size(); j++) estimates[folds.get(f).get(j)] = predictedEstimates.get(j).estimate();
                lines.add(row("fold", f + 1, "classifier", c.model.notation(), "inner", fixed((double)c.correct / inner.size()), "outer", ratio(hits, queries.size())));
                lines.add(row("fold", f + 1, "regressor", r.model.notation(), "inner", fixed(r.error), "outer", fixed(rmse(errors(predictedEstimates, queries)))));
            }
            List<Double> residuals = indices(train.size()).stream().map(j -> estimates[j] - train.get(j).target()).toList();
            lines.add(row("nested accuracy", trainRatio(correct), "rmse", fixed(rmse(residuals)))); return lines;
        }
        List<String> featureSelection() {
            Model model = classifier.model; List<Integer> current = new ArrayList<>(features), chosen = new ArrayList<>(features); int chosenCount = classifier.correct, step = 0;
            List<String> lines = new ArrayList<>(List.of(row("feature_selection", model.notation()), row("start features", names(current), "correct", trainRatio(chosenCount))));
            while (current.size() >= 3) {
                int remove = current.getFirst(), maximum = -1; List<String> candidates = new ArrayList<>();
                for (int feature : current) {
                    int count = crossValidate(List.of(model), train, s.folds(), current.stream().filter(other -> other != feature).toList()).getFirst().correct;
                    candidates.add(row(data.features().get(feature), count)); if (count > maximum) { maximum = count; remove = feature; }
                }
                current.remove(Integer.valueOf(remove)); lines.add(row("step", ++step, "remove", data.features().get(remove), "correct", trainRatio(maximum), "candidates", String.join(" ", candidates)));
                if (maximum >= chosenCount) { chosen = new ArrayList<>(current); chosenCount = maximum; }
            }
            int testCorrect = correctCount(predict(model, train, labelled, chosen), labelled);
            lines.add(row("selected features", names(chosen), "correct", trainRatio(chosenCount))); lines.add(row("selected test", ratio(testCorrect, labelled.size()))); return lines;
        }
        List<String> metricsReport() {
            List<List<String>> sections = new ArrayList<>();
            sections.add(List.of(row("data train", train.size(), "test", test.size(), "labelled", labelled.size(), "targets", targeted.size(), "features", features.size(), "classes", labels.size()), "classes " + labelCounts(train)));
            for (String method : s.scalings()) {
                Scaling scaling = Scaling.compute(train, method); List<String> lines = new ArrayList<>(List.of(row("scaling", method)));
                for (int feature : features) lines.add(row(data.features().get(feature), "center", fixed(scaling.centers()[feature], 6), "scale", fixed(scaling.scales()[feature], 6))); sections.add(lines);
            }
            List<String> foldLines = new ArrayList<>(List.of(row("folds", s.folds())));
            for (int f = 0; f < folds.size(); f++) foldLines.add(row("fold", f + 1, "size", folds.get(f).size(), labelCounts(Validation.selected(train, folds.get(f))))); sections.add(foldLines);
            sections.add(List.of(row("grid", grid.size()), "best_classifier " + summary(classifier, false), "best_regressor " + summary(regressor, true)));
            for (boolean regression : new boolean[]{false, true}) {
                Comparator<CrossValidation> order = regression ? Comparator.comparingDouble(result -> fourDecimal(result.error)) : Comparator.<CrossValidation>comparingInt(result -> result.correct).reversed();
                List<CrossValidation> ranked = results.stream().sorted(order).limit(s.top()).toList(); List<String> lines = new ArrayList<>(List.of(row("top", s.top(), "by", regression ? "rmse" : "accuracy")));
                for (int j = 0; j < ranked.size(); j++) lines.add(row(j + 1, summary(ranked.get(j), regression))); sections.add(lines);
            }
            for (int item = 0; item < 4; item++) {
                String name = item == 0 ? "k" : item == 1 ? "metric" : item == 2 ? "weighting" : "scaling";
                List<String> values = item == 0 ? s.ks().stream().map(Object::toString).toList() : item == 1 ? s.metrics() : item == 2 ? s.weightings() : s.scalings();
                List<String> lines = new ArrayList<>(List.of("best per " + name));
                for (String value : values) {
                    List<CrossValidation> chosen = new ArrayList<>();
                    for (CrossValidation result : results) { Model m = result.model; String current = item == 0 ? Integer.toString(m.k()) : item == 1 ? m.metric() : item == 2 ? m.weighting() : m.scaling(); if (current.equals(value)) chosen.add(result); }
                    CrossValidation c = bestClassifier(chosen), r = bestRegressor(chosen);
                    lines.add(row(name + "=" + value, "classifier", c.model.notation(), "accuracy", fixed((double)c.correct / train.size()), "regressor", r.model.notation(), "rmse", fixed(r.error)));
                }
                sections.add(lines);
            }
            List<String> classifierFolds = new ArrayList<>(List.of("classifier folds")), regressorFolds = new ArrayList<>(List.of("regressor folds"));
            for (int f = 0; f < folds.size(); f++) {
                int correct = 0; List<Double> residuals = new ArrayList<>();
                for (int index : folds.get(f)) { if (classifier.hits[index]) correct++; residuals.add(regressor.predictions.get(index).estimate() - train.get(index).target()); }
                classifierFolds.add(row("fold", f + 1, "correct", ratio(correct, folds.get(f).size()))); regressorFolds.add(row("fold", f + 1, "size", folds.get(f).size(), "rmse", fixed(rmse(residuals))));
            }
            sections.add(classifierFolds); sections.add(regressorFolds);
            List<String> cvClasses = new ArrayList<>(List.of("cross_validation classes")); cvClasses.addAll(evaluation(train, classifier.predictions)); sections.add(cvClasses);
            List<String> cvReliability = new ArrayList<>(List.of("cross_validation reliability")); cvReliability.addAll(reliability(train, classifier.predictions)); sections.add(cvReliability);
            List<String> mcnemar = new ArrayList<>(List.of("mcnemar"));
            for (String metric : s.metrics()) {
                CrossValidation comparison = bestClassifier(results.stream().filter(result -> result.model.metric().equals(metric)).toList()); int b = 0, c = 0;
                for (int j = 0; j < train.size(); j++) { if (classifier.hits[j] && !comparison.hits[j]) b++; if (comparison.hits[j] && !classifier.hits[j]) c++; }
                int adjusted = Math.max(0, Math.abs(b - c) - 1), numerator = adjusted * adjusted;
                mcnemar.add(row(comparison.model.notation(), "b", b, "c", c, "statistic", b + c == 0 ? "0/1 0.0000" : fraction(numerator, b + c), "significant", 1000 * numerator > 3841 * (b + c) ? "yes" : "no"));
            }
            sections.add(mcnemar); sections.addAll(leaveOneOut()); sections.add(nested()); sections.add(featureSelection());
            List<Prediction> labelledResults = labelledPredictions(); List<String> classification = new ArrayList<>(List.of(row("test classification", classifier.model.notation()), row("labelled", labelled.size(), "correct", ratio(correctCount(labelledResults, labelled), labelled.size()))));
            classification.addAll(evaluation(labelled, labelledResults)); sections.add(classification);
            List<String> testReliability = new ArrayList<>(List.of("test reliability")); testReliability.addAll(reliability(labelled, labelledResults)); sections.add(testReliability);
            double[] margins = testPredictions.stream().mapToDouble(prediction -> prediction.result().share() - prediction.result().runnerShare()).toArray();
            List<String> uncertain = new ArrayList<>(List.of(row("uncertain", s.top(), "test rows")));
            for (int j : indices(test.size()).stream().sorted(Comparator.comparingDouble(j -> fourDecimal(margins[j]))).limit(s.top()).toList()) {
                Vote v = testPredictions.get(j).result();
                uncertain.add(row(test.get(j).id(), "predicted", v.label(), "share", fixed(v.share()), "runner_up", v.runner() == null ? "-" : v.runner(), "share", fixed(v.runnerShare()), "margin", fixed(margins[j]), "true", test.get(j).label() == null ? "-" : test.get(j).label()));
            }
            sections.add(uncertain);
            List<Integer> targetIndices = indices(test.size()).stream().filter(j -> test.get(j).target() != null).toList();
            List<Double> targetErrors = targetIndices.stream().map(j -> testEstimates.get(j).estimate() - test.get(j).target()).toList(), targets = targetIndices.stream().map(j -> test.get(j).target()).toList();
            List<String> regressionLines = new ArrayList<>(List.of(row("test regression", regressor.model.notation()), row("targets", targets.size(), "rmse", fixed(rmse(targetErrors)), "mae", fixed(mae(targetErrors)), "r2", fixed(Validation.rSquared(targetErrors, targets)))));
            for (String label : labels) {
                List<Double> classErrors = targetIndices.stream().filter(j -> label.equals(test.get(j).label())).map(j -> testEstimates.get(j).estimate() - test.get(j).target()).toList();
                regressionLines.add(row("class", label, "targets", classErrors.size(), "rmse", classErrors.isEmpty() ? "-" : fixed(rmse(classErrors))));
            }
            sections.add(regressionLines);
            List<String> mistakes = new ArrayList<>(List.of("misclassified test rows")); int count = 0;
            for (int j = 0; j < test.size(); j++) if (test.get(j).label() != null && !testPredictions.get(j).result().label().equals(test.get(j).label())) {
                count++; Vote v = testPredictions.get(j).result(); mistakes.add(row(test.get(j).id(), "true", test.get(j).label(), "predicted", v.label(), "share", fixed(v.share())));
                for (Neighbor neighbor : testPredictions.get(j).neighbors()) mistakes.add("  " + row(neighbor.row().id(), neighbor.row().label(), fixed(neighbor.distance())));
            }
            mistakes.add(row("count", count)); sections.add(mistakes); return parts(sections);
        }
        List<String> learningCurve() {
            List<String> lines = new ArrayList<>(List.of("n,train_size,correct,accuracy,rmse"));
            for (int limit : s.curve()) {
                Map<String, Integer> taken = new TreeMap<>(); List<Row> chosen = new ArrayList<>();
                for (Row row : train) if (taken.getOrDefault(row.label(), 0) < limit) { taken.merge(row.label(), 1, Integer::sum); chosen.add(row); }
                int correct = correctCount(predict(classifier.model, chosen, labelled, features), labelled); double error = rmse(errors(predict(regressor.model, chosen, targeted, features), targeted));
                lines.add(String.join(",", Integer.toString(limit), Integer.toString(chosen.size()), Integer.toString(correct), fixed((double)correct / labelled.size()), fixed(error)));
            }
            return lines;
        }
        record Condensed(List<Row> rows, int scans) {}
        static Condensed condense(ClassifierSpace space, List<Row> rows) {
            List<Row> store = new ArrayList<>(List.of(rows.getFirst())); Set<String> stored = new HashSet<>(List.of(rows.getFirst().id())); int scans = 0;
            while (true) {
                scans++; boolean added = false;
                for (Row row : rows) if (!stored.contains(row.id()) && !space.order(row, store).getFirst().row().label().equals(row.label())) { store.add(row); stored.add(row.id()); added = true; }
                if (!added) break;
            }
            return new Condensed(store.stream().sorted(Comparator.comparing(Row::id)).toList(), scans);
        }
        static List<String> idLines(List<Row> rows) {
            List<String> lines = new ArrayList<>(); for (int start = 0; start < rows.size(); start += 10) lines.add(String.join(" ", rows.subList(start, Math.min(start + 10, rows.size())).stream().map(Row::id).toList())); return lines;
        }
        List<String> prototypes() {
            Model model = classifier.model; ClassifierSpace space = new ClassifierSpace(model, train, test, features);
            List<Row> ordered = train.stream().sorted(Comparator.comparing(Row::id)).toList(), edited = new ArrayList<>(ordered);
            List<String> editing = new ArrayList<>(List.of(row("editing k=" + s.editK()))); int pass = 0;
            while (true) {
                record Removal(Row row, Vote result) {}
                List<Removal> removals = new ArrayList<>();
                for (Row row : edited) {
                    Vote result = space.predict(row, edited.stream().filter(other -> !other.id().equals(row.id())).toList(), s.editK());
                    if (!result.label().equals(row.label())) removals.add(new Removal(row, result));
                }
                editing.add(row("pass", ++pass, "removed", removals.size()));
                for (Removal removal : removals) editing.add("  " + row(removal.row.id(), "true", removal.row.label(), "predicted", removal.result.label(), "share", fixed(removal.result.share())));
                if (removals.isEmpty()) break;
                Set<String> removed = new HashSet<>(removals.stream().map(removal -> removal.row.id()).toList()); edited.removeIf(row -> removed.contains(row.id()));
            }
            editing.add(row("edited size", edited.size(), "removed", train.size() - edited.size())); Condensed condensed = condense(space, ordered), editedCondensed = condense(space, edited);
            List<List<String>> sections = new ArrayList<>(); sections.add(List.of(row("space", model.notation()))); sections.add(editing);
            sections.add(List.of(row("condensing original scans", condensed.scans, "size", condensed.rows.size()), row("condensing edited scans", editedCondensed.scans, "size", editedCondensed.rows.size())));
            List<List<Row>> sets = List.of(ordered, edited, condensed.rows, editedCondensed.rows); String[] setNames = {"original", "edited", "condensed", "edited_condensed"}; List<String> setLines = new ArrayList<>();
            for (int j = 0; j < sets.size(); j++) {
                int knn = 0, one = 0;
                for (Row row : labelled) { if (space.predict(row, sets.get(j), model.k()).label().equals(row.label())) knn++; if (space.order(row, sets.get(j)).getFirst().row().label().equals(row.label())) one++; }
                setLines.add(row("set", setNames[j], "size", sets.get(j).size(), labelCounts(sets.get(j)), "knn", ratio(knn, labelled.size()), "1nn", ratio(one, labelled.size())));
            }
            sections.add(setLines); List<String> ids = new ArrayList<>(List.of("prototypes condensed")); ids.addAll(idLines(condensed.rows)); sections.add(ids);
            ids = new ArrayList<>(List.of("prototypes edited_condensed")); ids.addAll(idLines(editedCondensed.rows)); sections.add(ids);
            List<String> borders = new ArrayList<>(List.of("borders")); int total = 0;
            for (String label : labels) {
                int count = 0, boundary = 0; double same = 0, other = 0;
                for (Row row : ordered) if (row.label().equals(label)) {
                    count++; var order = space.order(row, ordered.stream().filter(reference -> !reference.id().equals(row.id())).toList()); if (!order.getFirst().row().label().equals(label)) boundary++;
                    same += order.stream().filter(neighbor -> neighbor.row().label().equals(label)).findFirst().orElseThrow().distance(); other += order.stream().filter(neighbor -> !neighbor.row().label().equals(label)).findFirst().orElseThrow().distance();
                }
                total += boundary; borders.add(row("class", label, "size", count, "border", boundary, "same", fixed(same / count), "other", fixed(other / count)));
            }
            borders.add(row("border total", trainRatio(total))); sections.add(borders);
            Map<String, Integer> occurrences = new TreeMap<>(); train.forEach(row -> occurrences.put(row.id(), 0));
            for (Prediction prediction : testPredictions) for (Neighbor neighbor : prediction.neighbors()) occurrences.merge(neighbor.row().id(), 1, Integer::sum);
            List<String> hubs = new ArrayList<>(List.of(row("hubs k=" + model.k(), "queries", test.size())));
            for (Row row : ordered.stream().sorted(Comparator.<Row>comparingInt(row -> occurrences.get(row.id())).reversed().thenComparing(Row::id)).limit(s.top()).toList()) hubs.add(row(row.id(), row.label(), occurrences.get(row.id())));
            hubs.add(row("anti_hubs", occurrences.values().stream().filter(value -> value == 0).count())); sections.add(hubs); return parts(sections);
        }
        void write() throws IOException {
            List<String> gridLines = new ArrayList<>(List.of("k,metric,weighting,scaling,correct,accuracy,rmse"));
            for (CrossValidation result : results) { Model m = result.model; gridLines.add(String.join(",", Integer.toString(m.k()), m.metric(), m.weighting(), m.scaling(), Integer.toString(result.correct), fixed((double)result.correct / train.size()), fixed(result.error))); }
            List<String> predictions = new ArrayList<>(List.of("id,label,vote_share,estimate"));
            for (int j = 0; j < test.size(); j++) predictions.add(String.join(",", test.get(j).id(), testPredictions.get(j).result().label(), fixed(testPredictions.get(j).result().share()), fixed(testEstimates.get(j).estimate())));
            Report.write("cv_grid.csv", gridLines); Report.write("predictions.csv", predictions); Report.write("metrics.txt", metricsReport()); Report.write("learning_curve.csv", learningCurve()); Report.write("prototypes.txt", prototypes());
        }
    }
    public static void main(String[] args) throws IOException { new Experiment(Dataset.read()).write(); }
}
