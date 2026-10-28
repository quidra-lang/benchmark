using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Program {
    public static Dataset.Data data;
    public static Dataset.Settings settings;
    public static List<Dataset.Image> train, validation;
    public static int classes;
    public static string Real(double x, int digits) {
        return Evaluation.Real(x, digits);
    }
    public static string Ints(int[] values) {
        List<string> text = new();
        foreach (int value in values)
            text.Add(Convert.ToString(value));
        return string.Join(" ", text);
    }
    public static string Reals(double[] values, int digits) {
        List<string> text = new();
        foreach (double value in values)
            text.Add(Real(value, digits));
        return string.Join(" ", text);
    }
    public static int[] Order(int size) {
        int[] result = new int[size];
        for (int i = 0; i < size; i++)
            result[i] = i;
        return result;
    }
    public sealed class Summary {
        public double loss;
        public int correct;
        public List<Network.Pass> passes = new();
        public bool[] correctness;
    }
    public static Summary Evaluate(Network net, double[] theta, List<Dataset.Image> images) {
        Summary result = new Summary();
        result.correctness = new bool[images.Count];
        for (int i = 0; i < images.Count; i++) {
            Network.Pass pass = net.Forward(theta, images[i]);
            result.passes.Add(pass);
            result.loss += pass.loss;
            result.correctness[i] = Evaluation.Prediction(pass.scores) == images[i].label;
            if (result.correctness[i])
                result.correct++;
        }
        result.loss /= images.Count;
        return result;
    }
    public static double[] MeanGradient(Network net, double[] theta, List<Dataset.Image> images) {
        double[] sum = new double[theta.Length];
        foreach (Dataset.Image image in images) {
            double[] gradient = net.Backward(theta, net.Forward(theta, image)).gradient;
            for (int p = 0; p < sum.Length; p++)
                sum[p] += gradient[p];
        }
        for (int p = 0; p < sum.Length; p++)
            sum[p] /= images.Count;
        return sum;
    }
    public static List<string> GradientChecks() {
        List<string> lines = new();
        foreach (Network net in data.networks) {
            int[] order = Order(train.Count);
            new Dataset.Generator(settings.seed).Shuffle(order);
            List<Dataset.Image> batch = new();
            List<string> ids = new();
            for (int i = 0; i < Math.Min(settings.batch, order.Length); i++) {
                Dataset.Image image = train[order[i]];
                batch.Add(image);
                ids.Add(image.id);
            }
            double[] theta = net.initial.ToArray(), gradient = MeanGradient(net, theta, batch);
            int[][] counts = Enumerable.Range(0, net.layers)
                                 .Select(
                                     _ => new int[2])
                                 .ToArray();
            int checkedCount = 0;
            bool passed = true;
            for (int p = 0; p < theta.Length; p += settings.stride) {
                double original = theta[p];
                theta[p] = original + 0.00001;
                double plus = Evaluate(net, theta, batch).loss;
                theta[p] = original - 0.00001;
                double minus = Evaluate(net, theta, batch).loss;
                theta[p] = original;
                double numeric = (plus - minus) / (2 * 0.00001),
                       error = Math.Abs(gradient[p] - numeric) /
                               Math.Max(1, Math.Abs(gradient[p]) + Math.Abs(numeric));
                if (!(error < 0.000001))
                    passed = false;
                checkedCount++;
                for (int l = 0; l < net.layers; l++)
                    if (p >= net.starts[l] && p < net.biases[l] + net.units[l])
                        counts[l][net.weight[p] ? 0 : 1]++;
            }
            if (lines.Count != 0)
                lines.Add("");
            lines.Add("network " + net.name);
            lines.Add("parameters " + net.parameters);
            lines.Add("batch " + string.Join(" ", ids));
            for (int l = 0; l < net.layers; l++)
                lines.Add("layer " + (l + 1) + " weights " + counts[l][0] + " biases " + counts[l][1]);
            lines.Add("checked " + checkedCount);
            lines.Add("result " + (passed ? "PASS" : "FAIL"));
        }
        return lines;
    }
    public record Epoch(int number, double rate, double magnitude, Summary train, Summary validation,
                        bool improved) {
    }
    public record Noise(int rate, List<Dataset.Image> images, int flipped) {
    }
    public sealed class Result {
        public int index, bestEpoch, bestCorrect, updates;
        public Dataset.Run run;
        public Network network;
        public double[] theta;
        public double bestLoss;
        public string stop;
        public List<Epoch> epochs = new();
        public Summary test;
        public int[] predictions;
        public int[][] confusion;
    }
    public static Result Fit(Dataset.Run run, int index) {
        Result result = new Result();
        result.run = run;
        result.index = index;
        foreach (Network candidateNet in data.networks)
            if (candidateNet.name.Equals(run.network))
                result.network = candidateNet;
        Network net = result.network;
        double[] theta = net.initial.ToArray();
        Optimizers.State optimizer = new Optimizers.State(run, theta.Length);
        Dataset.Generator generator = new Dataset.Generator(settings.seed);
        int[] order = Order(train.Count);
        int wait = 0;
        for (int e = 1; e <= settings.epochs; e++) {
            double eta = Optimizers.Rate(run, settings, e);
            generator.Shuffle(order);
            double magnitude = 0;
            int batches = 0;
            for (int first = 0; first < order.Length; first += settings.batch) {
                List<Dataset.Image> batch = new();
                for (int i = first; i < Math.Min(order.Length, first + settings.batch); i++)
                    batch.Add(train[order[i]]);
                double[] gradient = MeanGradient(net, theta, batch);
                double squares = 0;
                for (int p = 0; p < theta.Length; p++) {
                    if (net.weight[p])
                        gradient[p] += run.lambda * theta[p];
                    squares += gradient[p] * gradient[p];
                }
                magnitude += Math.Sqrt(squares);
                batches++;
                optimizer.Update(theta, gradient, eta);
                result.updates++;
            }
            Summary training = Evaluate(net, theta, train), valid = Evaluate(net, theta, validation);
            bool improved = e == 1 || valid.loss < result.bestLoss;
            if (improved) {
                result.bestLoss = valid.loss;
                result.bestEpoch = e;
                result.bestCorrect = valid.correct;
                result.theta = theta.ToArray();
                wait = 0;
            } else
                wait++;
            result.epochs.Add(new Epoch(e, eta, magnitude / batches, training, valid, improved));
            if (wait >= settings.patience) {
                result.stop = "early";
                break;
            }
            if (e == settings.epochs)
                result.stop = "max_epochs";
        }
        result.test = Evaluate(net, result.theta, data.test);
        result.predictions = new int[data.test.Count];
        for (int i = 0; i < result.predictions.Length; i++)
            result.predictions[i] = Evaluation.Prediction(result.test.passes[i].scores);
        result.confusion = Evaluation.Confusion(data.test, result.test.passes, classes);
        return result;
    }
    public static List<Noise> BuildNoise() {
        List<Noise> result = new();
        foreach (int rate in settings.noise) {
            Dataset.Generator generator = new Dataset.Generator(settings.seed);
            List<Dataset.Image> images = new();
            int flipped = 0;
            foreach (Dataset.Image image in data.test) {
                char[] pixels = image.pixels.ToCharArray();
                for (int p = 0; p < pixels.Length; p++)
                    if (generator.Draw() % 100 < rate) {
                        pixels[p] = pixels[p] == '0' ? '1' : '0';
                        flipped++;
                    }
                images.Add(Dataset.CreateImage(image.id, image.label, new string(pixels)));
            }
            result.Add(new Noise(rate, images, flipped));
        }
        return result;
    }
    public static List<string> DataSummary() {
        int pixels = data.width * data.height;
        int[] training = new int[classes], valid = new int[classes], testing = new int[classes],
              ink = new int[classes];
        int[][] black = Enumerable.Range(0, classes)
                            .Select(
                                _ => new int[pixels])
                            .ToArray(),
                levels = Enumerable.Range(0, classes)
                             .Select(
                                 _ => new int[pixels])
                             .ToArray();
        foreach (Dataset.Image image in train) {
            int k = image.label;
            training[k]++;
            for (int p = 0; p < pixels; p++)
                if (image.pixels[p] == '1') {
                    ink[k]++;
                    black[k][p]++;
                }
        }
        foreach (Dataset.Image image in validation)
            valid[image.label]++;
        foreach (Dataset.Image image in data.test)
            testing[image.label]++;
        List<string> lines = new([
            "data", "train " + train.Count + " validation " + validation.Count + " test " + data.test.Count +
                        " pixels " + pixels
        ]);
        for (int k = 0; k < classes; k++) {
            lines.Add("class " + k + " train " + training[k] + " validation " + valid[k] + " test " +
                      testing[k] + " ink " + Evaluation.Ratio(ink[k], training[k]));
            for (int p = 0; p < pixels; p++)
                levels[k][p] = training[k] == 0 ? 0 : Math.Min(9, 10 * black[k][p] / training[k]);
        }
        lines.Add("mean_images " + Ints(Order(classes)));
        lines.AddRange(Evaluation.Maps(levels, data.width, data.height));
        return lines;
    }
    public static List<string> EvaluateRun(Result result, List<Noise> noise) {
        Network net = result.network;
        int total = data.test.Count, top2 = 0;
        double correctConfidence = 0, wrongConfidence = 0;
        for (int i = 0; i < total; i++) {
            Network.Pass pass = result.test.passes[i];
            int predicted = result.predictions[i], label = data.test[i].label;
            if (predicted == label || Evaluation.Second(pass.scores, predicted) == label)
                top2++;
            if (predicted == label)
                correctConfidence += pass.scores[predicted];
            else
                wrongConfidence += pass.scores[predicted];
        }
        int events = 0, rows = 0, never = 0;
        for (int i = 0; i < train.Count; i++) {
            int count = 0;
            bool learned = false;
            for (int e = 0; e < result.epochs.Count; e++) {
                bool wasCorrect = result.epochs[e].train.correctness[i];
                if (wasCorrect)
                    learned = true;
                if (e > 0 && result.epochs[e - 1].train.correctness[i] && !wasCorrect)
                    count++;
            }
            events += count;
            if (count > 0)
                rows++;
            if (!learned)
                never++;
        }
        double[] norms = new double[net.layers], changes = new double[net.layers];
        for (int l = 0; l < net.layers; l++) {
            double norm = 0, change = 0;
            for (int p = net.starts[l]; p < net.biases[l]; p++) {
                norm += result.theta[p] * result.theta[p];
                double delta = result.theta[p] - net.initial[p];
                change += delta * delta;
            }
            norms[l] = Math.Sqrt(norm);
            changes[l] = Math.Sqrt(change);
        }
        int correct = result.test.correct;
        List<string> lines = new([
            "run " + result.run.name + " network " + net.name + " optimizer " + result.run.optimizer,
            "epochs " + result.epochs.Count + " best_epoch " + result.bestEpoch + " stop " + result.stop +
                " updates " + result.updates,
            "best_val_loss " + Real(result.bestLoss, 6) + " best_val_acc " +
                Evaluation.Ratio(result.bestCorrect, validation.Count) + " correct " + result.bestCorrect +
                "/" + validation.Count,
            "test_loss " + Real(result.test.loss, 6) + " test_acc " + Evaluation.Ratio(correct, total) +
                " correct " + correct + "/" + total,
            "top2_acc " + Evaluation.Ratio(top2, total) + " correct " + top2 + "/" + total,
            "confidence correct " + (correct == 0 ? "-" : Real(correctConfidence / correct, 4)) + " wrong " +
                (correct == total ? "-" : Real(wrongConfidence / (total - correct), 4)),
            "forgetting events " + events + " rows " + rows + " never_learned " + never,
            "weight_norms " + Reals(norms, 4), "weight_changes " + Reals(changes, 4), "curve"
        ]);
        double maximum = 0;
        foreach (Epoch epoch in result.epochs) {
            maximum = Math.Max(maximum, epoch.train.loss);
            maximum = Math.Max(maximum, epoch.validation.loss);
        }
        foreach (Epoch epoch in result.epochs) {
            int ct = (int)Math.Floor(39 * epoch.train.loss / maximum + 0.5),
                cv = (int)Math.Floor(39 * epoch.validation.loss / maximum + 0.5);
            char[] curve = new char[40];
            Array.Fill(curve, ' ');
            curve[ct] = 't';
            curve[cv] = ct == cv ? '*' : 'v';
            lines.Add(epoch.number.ToString(CultureInfo.InvariantCulture).PadLeft(2) + " |" +
                      new string(curve) + "|" + (epoch.number == result.bestEpoch ? " best" : ""));
        }
        lines.Add("confusion");
        lines.AddRange(Evaluation.ConfusionLines(result.confusion));
        lines.Add("calibration");
        int[] bins = new int[settings.bins], hits = new int[settings.bins];
        double[] confidence = new double[settings.bins];
        for (int i = 0; i < total; i++) {
            double c = result.test.passes[i].scores[result.predictions[i]];
            int bin = Math.Min(settings.bins - 1, (int)Math.Floor(c * settings.bins));
            bins[bin]++;
            confidence[bin] += c;
            if (result.predictions[i] == data.test[i].label)
                hits[bin]++;
        }
        double ece = 0;
        for (int b = 0; b < settings.bins; b++) {
            string mean = "-";
            if (bins[b] > 0) {
                double average = confidence[b] / bins[b];
                mean = Real(average, 4);
                ece += ((double)bins[b] / total) * Math.Abs((double)hits[b] / bins[b] - average);
            }
            lines.Add("bin " + (b + 1) + " " + Real((double)b / settings.bins, 2) + " " +
                      Real((b + 1.0) / settings.bins, 2) + " count " + bins[b] + " accuracy " +
                      Evaluation.Ratio(hits[b], bins[b]) + " confidence " + mean);
        }
        lines.Add("ece " + Real(ece, 4));
        int[] classCount = new int[classes];
        foreach (Dataset.Image image in data.test)
            classCount[image.label]++;
        for (int l = 0; l < net.layers - 1; l++) {
            int units = net.units[l];
            double[][] means = Enumerable.Range(0, classes)
                                   .Select(
                                       _ => new double[units])
                                   .ToArray();
            int[] zeros = new int[units], preferred = new int[units];
            for (int i = 0; i < total; i++)
                for (int j = 0; j < units; j++) {
                    double value = result.test.passes[i].a[l + 1][j];
                    means[data.test[i].label][j] += value;
                    if (value == 0)
                        zeros[j]++;
                }
            lines.Add("hidden " + (l + 1) + " " + net.activations[l] + " units " + units);
            for (int k = 0; k < classes; k++) {
                if (classCount[k] > 0)
                    for (int j = 0; j < units; j++)
                        means[k][j] /= classCount[k];
                lines.Add("class " + k + " mean " + (classCount[k] == 0 ? "-" : Reals(means[k], 4)));
            }
            for (int j = 0; j < units; j++) {
                int chosen = -1;
                for (int k = 0; k < classes; k++)
                    if (classCount[k] > 0 && (chosen < 0 || means[k][j] > means[chosen][j]))
                        chosen = k;
                preferred[j] = chosen;
            }
            lines.Add("preferred " + Ints(preferred));
            if (net.activations[l].Equals("RELU"))
                lines.Add("zero_counts " + Ints(zeros));
        }
        List<int> weights = new();
        for (int p = 0; p < net.parameters; p++)
            if (net.weight[p])
                weights.Add(p);
        weights.Sort((a, b) => {
            int c = (Math.Abs(result.theta[a])).CompareTo(Math.Abs(result.theta[b]));
            return c != 0 ? c : (a).CompareTo(b);
        });
        lines.Add("pruning");
        foreach (int q in settings.prune) {
            int removed = q * net.weights / 100;
            double[] theta = result.theta.ToArray();
            for (int i = 0; i < removed; i++)
                theta[weights[i]] = 0;
            Summary pruned = Evaluate(net, theta, data.test);
            lines.Add("prune " + q + " removed " + removed + " correct " + pruned.correct + " test_acc " +
                      Evaluation.Ratio(pruned.correct, total) + " test_loss " + Real(pruned.loss, 6));
        }
        lines.Add("noise");
        foreach (Noise noisy in noise) {
            Summary evaluated = Evaluate(net, result.theta, noisy.images);
            lines.Add("noise " + noisy.rate + " correct " + evaluated.correct + " test_acc " +
                      Evaluation.Ratio(evaluated.correct, total));
        }
        string misclassified = "misclassified " + (total - correct);
        for (int i = 0; i < total; i++)
            if (result.predictions[i] != data.test[i].label)
                misclassified += " " + data.test[i].id;
        lines.Add(misclassified);
        return lines;
    }

    public record Confused(int actual, int predicted, int count) {
    }
    public static List<string> Comparison(List<Result> results, List<Noise> noise) {
        List<Result> ranked = new(results);
        ranked.Sort((a, b) => {
            int c = (b.test.correct).CompareTo(a.test.correct);
            if (c == 0)
                c = (a.bestLoss).CompareTo(b.bestLoss);
            return c != 0 ? c : (a.index).CompareTo(b.index);
        });
        Result top = ranked[0];
        int total = data.test.Count;
        List<string> lines = new(["comparison"]);
        for (int i = 0; i < ranked.Count; i++) {
            Result result = ranked[i];
            lines.Add("rank " + (i + 1) + " " + result.run.name + " correct " + result.test.correct +
                      " test_acc " + Evaluation.Ratio(result.test.correct, total) + " best_val_loss " +
                      Real(result.bestLoss, 6) + " test_loss " + Real(result.test.loss, 6) + " best_epoch " +
                      result.bestEpoch + " epochs " + result.epochs.Count + " updates " + result.updates);
        }
        lines.Add("agreement");
        foreach (Result a in results) {
            string text = a.run.name;
            foreach (Result b in results) {
                int count = 0;
                for (int i = 0; i < total; i++)
                    if (a.predictions[i] == b.predictions[i])
                        count++;
                text += " " + count;
            }
            lines.Add(text);
        }
        lines.Add("mcnemar " + top.run.name);
        foreach (Result result in ranked)
            if (result != top) {
                int b = 0, c = 0;
                for (int i = 0; i < total; i++) {
                    bool first = top.predictions[i] == data.test[i].label,
                         second = result.predictions[i] == data.test[i].label;
                    if (first && !second)
                        b++;
                    if (second && !first)
                        c++;
                }
                int difference = Math.Max(Math.Abs(b - c) - 1, 0), numerator = difference * difference,
                    denominator = b + c;
                lines.Add("vs " + result.run.name + " b " + b + " c " + c + " chi2 " +
                          (denominator == 0 ? "0.0000" : Evaluation.Ratio(numerator, denominator)) +
                          " significant " + (numerator * 1000 > 3841 * denominator ? "yes" : "no"));
            }
        int[] ensemble = new int[total];
        int ensembleCorrect = 0, fixedCount = 0, broken = 0;
        for (int i = 0; i < total; i++) {
            int[] votes = new int[classes];
            foreach (Result result in results)
                votes[result.predictions[i]]++;
            int most = 0;
            foreach (int count in votes)
                most = Math.Max(most, count);
            foreach (Result result in ranked)
                if (votes[result.predictions[i]] == most) {
                    ensemble[i] = result.predictions[i];
                    break;
                }
            bool correct = ensemble[i] == data.test[i].label,
                 topCorrect = top.predictions[i] == data.test[i].label;
            if (correct)
                ensembleCorrect++;
            if (correct && !topCorrect)
                fixedCount++;
            if (!correct && topCorrect)
                broken++;
        }
        lines.Add("ensemble correct " + ensembleCorrect + "/" + total + " test_acc " +
                  Evaluation.Ratio(ensembleCorrect, total) + " fixed " + fixedCount + " broken " + broken);
        List<Result> soft = new();
        foreach (Result result in results)
            if (result.network.activations[result.network.layers - 1].Equals("SOFTMAX"))
                soft.Add(result);
        if (soft.Count == 0)
            lines.Add("soft_ensemble none");
        else {
            int correct = 0;
            for (int i = 0; i < total; i++) {
                double[] scores = new double[classes];
                foreach (Result result in soft)
                    for (int k = 0; k < classes; k++)
                        scores[k] += result.test.passes[i].scores[k];
                for (int k = 0; k < classes; k++)
                    scores[k] /= soft.Count;
                if (Evaluation.Prediction(scores) == data.test[i].label)
                    correct++;
            }
            lines.Add("soft_ensemble runs " + soft.Count + " correct " + correct + "/" + total +
                      " test_acc " + Evaluation.Ratio(correct, total));
        }
        foreach (Noise noisy in noise)
            lines.Add("noise " + noisy.rate + " flipped " + noisy.flipped);
        int[][] aggregate = Enumerable.Range(0, classes)
                                .Select(
                                    _ => new int[classes])
                                .ToArray();
        foreach (Result result in results)
            for (int y = 0; y < classes; y++)
                for (int predicted = 0; predicted < classes; predicted++)
                    aggregate[y][predicted] += result.confusion[y][predicted];
        List<Confused> confused = new();
        for (int y = 0; y < classes; y++)
            for (int predicted = 0; predicted < classes; predicted++)
                if (y != predicted && aggregate[y][predicted] > 0)
                    confused.Add(new Confused(y, predicted, aggregate[y][predicted]));
        confused.Sort((a, b) => {
            int c = (b.count).CompareTo(a.count);
            if (c == 0)
                c = (a.actual).CompareTo(b.actual);
            return c != 0 ? c : (a.predicted).CompareTo(b.predicted);
        });
        lines.Add("confused_pairs");
        for (int i = 0; i < Math.Min(5, confused.Count); i++) {
            Confused pair = confused[i];
            lines.Add(pair.actual + " as " + pair.predicted + " count " + pair.count);
        }
        lines.Add("");
        lines.Add("saliency " + top.run.name);
        lines.Add("classes " + Ints(Order(classes)));
        int pixels = data.width * data.height;
        double[][] means = Enumerable.Range(0, classes)
                               .Select(
                                   _ => new double[pixels])
                               .ToArray();
        int[] counts = new int[classes];
        int[][] levels = Enumerable.Range(0, classes)
                             .Select(
                                 _ => new int[pixels])
                             .ToArray();
        for (int i = 0; i < total; i++) {
            int label = data.test[i].label;
            counts[label]++;
            double[] gradient = top.network.Backward(top.theta, top.test.passes[i]).input;
            for (int p = 0; p < pixels; p++)
                means[label][p] += Math.Abs(gradient[p]);
        }
        for (int k = 0; k < classes; k++) {
            double maximum = 0;
            if (counts[k] > 0)
                for (int p = 0; p < pixels; p++) {
                    means[k][p] /= counts[k];
                    maximum = Math.Max(maximum, means[k][p]);
                }
            if (maximum > 0)
                for (int p = 0; p < pixels; p++)
                    levels[k][p] = Math.Min(9, (int)Math.Floor(10 * means[k][p] / maximum));
        }
        lines.AddRange(Evaluation.Maps(levels, data.width, data.height));
        lines.Add("");
        lines.Add("hardest_training_examples " + top.run.name);
        Summary training = Evaluate(top.network, top.theta, train);
        List<int> hardest = new();
        for (int i = 0; i < train.Count; i++)
            hardest.Add(i);
        hardest.Sort((a, b) => {
            int c = (training.passes[b].loss).CompareTo(training.passes[a].loss);
            return c != 0 ? c : (a).CompareTo(b);
        });
        for (int j = 0; j < Math.Min(5, hardest.Count); j++) {
            int i = hardest[j];
            Dataset.Image image = train[i];
            Network.Pass pass = training.passes[i];
            lines.Add(image.id + " label " + image.label + " predicted " +
                      Evaluation.Prediction(pass.scores) + " loss " + Real(pass.loss, 6));
        }
        lines.Add("");
        lines.Add("misclassified_examples " + top.run.name);
        for (int i = 0; i < total; i++)
            if (top.predictions[i] != data.test[i].label) {
                Dataset.Image image = data.test[i];
                Network.Pass pass = top.test.passes[i];
                string predictions = "";
                foreach (Result result in results)
                    predictions += " " + result.predictions[i];
                lines.Add(image.id + " label " + image.label + " predicted " + top.predictions[i] +
                          " confidence " + Real(pass.scores[top.predictions[i]], 4) + " true_score " +
                          Real(pass.scores[image.label], 4) + " runs" + predictions + " ensemble " +
                          ensemble[i]);
                int nearest = 0, minimum = int.MaxValue;
                for (int j = 0; j < data.train.Count; j++) {
                    int distance = 0;
                    string pixelsText = data.train[j].pixels;
                    for (int p = 0; p < pixels; p++)
                        if (image.pixels[p] != pixelsText[p])
                            distance++;
                    if (distance < minimum) {
                        minimum = distance;
                        nearest = j;
                    }
                }
                Dataset.Image neighbor = data.train[nearest];
                lines.Add("nearest " + neighbor.id + " label " + neighbor.label + " distance " + minimum);
                lines.AddRange(Evaluation.Image(image, data.width, data.height));
            }
        return lines;
    }
    public static List<string> TrainingLog(List<Result> results) {
        List<string> lines = new(["run,epoch,lr,grad_norm,train_loss,train_acc,val_loss,val_acc,improved"]);
        foreach (Result result in results)
            foreach (Epoch e in result.epochs)
                lines.Add(result.run.name + "," + e.number + "," + Real(e.rate, 6) + "," +
                          Real(e.magnitude, 4) + "," + Real(e.train.loss, 6) + "," +
                          Evaluation.Ratio(e.train.correct, train.Count) + "," + Real(e.validation.loss, 6) +
                          "," + Evaluation.Ratio(e.validation.correct, validation.Count) + "," +
                          (e.improved ? 1 : 0));
        return lines;
    }
    public static List<string> Weights(List<Result> results) {
        List<string> lines = new();
        foreach (Result result in results) {
            if (lines.Count != 0)
                lines.Add("");
            Network net = result.network;
            lines.Add("RUN " + result.run.name + " NETWORK " + net.name + " EPOCH " + result.bestEpoch);
            for (int l = 0; l < net.layers; l++) {
                int previous = l == 0 ? net.inputs : net.units[l - 1], units = net.units[l];
                lines.Add("LAYER " + (l + 1) + " " + units + " " + previous);
                for (int j = 0; j < units; j++) {
                    string row = "W";
                    for (int i = 0; i < previous; i++)
                        row += " " + Real(result.theta[net.starts[l] + j * previous + i], 4);
                    lines.Add(row);
                }
                string biases = "B";
                for (int j = 0; j < units; j++)
                    biases += " " + Real(result.theta[net.biases[l] + j], 4);
                lines.Add(biases);
            }
        }
        return lines;
    }
    public static List<string> Predictions(List<Result> results) {
        List<string> lines = new(["run,id,label,predicted,confidence"]);
        foreach (Result result in results)
            for (int i = 0; i < data.test.Count; i++) {
                Dataset.Image image = data.test[i];
                int predicted = result.predictions[i];
                lines.Add(result.run.name + "," + image.id + "," + image.label + "," + predicted + "," +
                          Real(result.test.passes[i].scores[predicted], 4));
            }
        return lines;
    }
    public static void Write(string name, List<string> lines) {
        Directory.CreateDirectory(Path.Combine("output"));
        File.WriteAllText(Path.Combine("output", name), string.Join("\n", lines) + "\n");
    }
    public static void Main(string[] args) {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        data = Dataset.Read();
        settings = data.settings;
        classes = data.networks[0].classes;
        int count = data.train.Count, training = count - count / 5;
        train = new(data.train.GetRange(0, training - (0)));
        validation = new(data.train.GetRange(training, count - (training)));
        List<string> checks = GradientChecks();
        List<Result> results = new();
        for (int i = 0; i < settings.runs.Count; i++)
            results.Add(Fit(settings.runs[i], i));
        List<Noise> noise = BuildNoise();
        List<string> evaluation = DataSummary();
        evaluation.Add("");
        foreach (Result result in results) {
            evaluation.AddRange(EvaluateRun(result, noise));
            evaluation.Add("");
        }
        evaluation.AddRange(Comparison(results, noise));
        Write("gradient_check.txt", checks);
        Write("training_log.csv", TrainingLog(results));
        Write("final_weights.txt", Weights(results));
        Write("predictions.csv", Predictions(results));
        Write("evaluation.txt", evaluation);
    }
}
