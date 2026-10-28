import java.nio.file.*;
import java.util.*;

public final class Main {
    static Dataset.Data data;
    static Dataset.Settings settings;
    static List<Dataset.Image> train, validation;
    static int classes;
    static String real(double x, int digits) {
        return Evaluation.real(x, digits);
    }
    static String ints(int[] values) {
        List<String> text = new ArrayList<>();
        for (int value : values)
            text.add(Integer.toString(value));
        return String.join(" ", text);
    }
    static String reals(double[] values, int digits) {
        List<String> text = new ArrayList<>();
        for (double value : values)
            text.add(real(value, digits));
        return String.join(" ", text);
    }
    static int[] order(int size) {
        int[] result = new int[size];
        for (int i = 0; i < size; i++)
            result[i] = i;
        return result;
    }
    static final class Summary {
        double loss;
        int correct;
        List<Network.Pass> passes = new ArrayList<>();
        boolean[] correctness;
    }
    static Summary evaluate(Network net, double[] theta, List<Dataset.Image> images) {
        Summary result = new Summary();
        result.correctness = new boolean[images.size()];
        for (int i = 0; i < images.size(); i++) {
            Network.Pass pass = net.forward(theta, images.get(i));
            result.passes.add(pass);
            result.loss += pass.loss();
            result.correctness[i] = Evaluation.prediction(pass.scores()) == images.get(i).label();
            if (result.correctness[i])
                result.correct++;
        }
        result.loss /= images.size();
        return result;
    }
    static double[] meanGradient(Network net, double[] theta, List<Dataset.Image> images) {
        double[] sum = new double[theta.length];
        for (Dataset.Image image : images) {
            double[] gradient = net.backward(theta, net.forward(theta, image)).gradient();
            for (int p = 0; p < sum.length; p++)
                sum[p] += gradient[p];
        }
        for (int p = 0; p < sum.length; p++)
            sum[p] /= images.size();
        return sum;
    }
    static List<String> gradientChecks() {
        List<String> lines = new ArrayList<>();
        for (Network net : data.networks()) {
            int[] order = order(train.size());
            new Dataset.Generator(settings.seed).shuffle(order);
            List<Dataset.Image> batch = new ArrayList<>();
            List<String> ids = new ArrayList<>();
            for (int i = 0; i < Math.min(settings.batch, order.length); i++) {
                Dataset.Image image = train.get(order[i]);
                batch.add(image);
                ids.add(image.id());
            }
            double[] theta = net.initial.clone(), gradient = meanGradient(net, theta, batch);
            int[][] counts = new int[net.layers][2];
            int checked = 0;
            boolean passed = true;
            for (int p = 0; p < theta.length; p += settings.stride) {
                double original = theta[p];
                theta[p] = original + 0.00001;
                double plus = evaluate(net, theta, batch).loss;
                theta[p] = original - 0.00001;
                double minus = evaluate(net, theta, batch).loss;
                theta[p] = original;
                double numeric = (plus - minus) / (2 * 0.00001),
                       error = Math.abs(gradient[p] - numeric) /
                               Math.max(1, Math.abs(gradient[p]) + Math.abs(numeric));
                if (!(error < 0.000001))
                    passed = false;
                checked++;
                for (int l = 0; l < net.layers; l++)
                    if (p >= net.starts[l] && p < net.biases[l] + net.units[l])
                        counts[l][net.weight[p] ? 0 : 1]++;
            }
            if (!lines.isEmpty())
                lines.add("");
            lines.add("network " + net.name);
            lines.add("parameters " + net.parameters);
            lines.add("batch " + String.join(" ", ids));
            for (int l = 0; l < net.layers; l++)
                lines.add("layer " + (l + 1) + " weights " + counts[l][0] + " biases " + counts[l][1]);
            lines.add("checked " + checked);
            lines.add("result " + (passed ? "PASS" : "FAIL"));
        }
        return lines;
    }
    record Epoch(int number, double rate, double magnitude, Summary train, Summary validation,
                 boolean improved) {}
    record Noise(int rate, List<Dataset.Image> images, int flipped) {}
    static final class Result {
        int index, bestEpoch, bestCorrect, updates;
        Dataset.Run run;
        Network network;
        double[] theta;
        double bestLoss;
        String stop;
        List<Epoch> epochs = new ArrayList<>();
        Summary test;
        int[] predictions;
        int[][] confusion;
    }
    static Result fit(Dataset.Run run, int index) {
        Result result = new Result();
        result.run = run;
        result.index = index;
        for (Network net : data.networks())
            if (net.name.equals(run.network()))
                result.network = net;
        Network net = result.network;
        double[] theta = net.initial.clone();
        Optimizers.State optimizer = new Optimizers.State(run, theta.length);
        Dataset.Generator generator = new Dataset.Generator(settings.seed);
        int[] order = order(train.size());
        int wait = 0;
        for (int e = 1; e <= settings.epochs; e++) {
            double eta = Optimizers.rate(run, settings, e);
            generator.shuffle(order);
            double magnitude = 0;
            int batches = 0;
            for (int first = 0; first < order.length; first += settings.batch) {
                List<Dataset.Image> batch = new ArrayList<>();
                for (int i = first; i < Math.min(order.length, first + settings.batch); i++)
                    batch.add(train.get(order[i]));
                double[] gradient = meanGradient(net, theta, batch);
                double squares = 0;
                for (int p = 0; p < theta.length; p++) {
                    if (net.weight[p])
                        gradient[p] += run.lambda() * theta[p];
                    squares += gradient[p] * gradient[p];
                }
                magnitude += Math.sqrt(squares);
                batches++;
                optimizer.update(theta, gradient, eta);
                result.updates++;
            }
            Summary training = evaluate(net, theta, train), valid = evaluate(net, theta, validation);
            boolean improved = e == 1 || valid.loss < result.bestLoss;
            if (improved) {
                result.bestLoss = valid.loss;
                result.bestEpoch = e;
                result.bestCorrect = valid.correct;
                result.theta = theta.clone();
                wait = 0;
            } else
                wait++;
            result.epochs.add(new Epoch(e, eta, magnitude / batches, training, valid, improved));
            if (wait >= settings.patience) {
                result.stop = "early";
                break;
            }
            if (e == settings.epochs)
                result.stop = "max_epochs";
        }
        result.test = evaluate(net, result.theta, data.test());
        result.predictions = new int[data.test().size()];
        for (int i = 0; i < result.predictions.length; i++)
            result.predictions[i] = Evaluation.prediction(result.test.passes.get(i).scores());
        result.confusion = Evaluation.confusion(data.test(), result.test.passes, classes);
        return result;
    }
    static List<Noise> noise() {
        List<Noise> result = new ArrayList<>();
        for (int rate : settings.noise) {
            Dataset.Generator generator = new Dataset.Generator(settings.seed);
            List<Dataset.Image> images = new ArrayList<>();
            int flipped = 0;
            for (Dataset.Image image : data.test()) {
                char[] pixels = image.pixels().toCharArray();
                for (int p = 0; p < pixels.length; p++)
                    if (generator.draw() % 100 < rate) {
                        pixels[p] = pixels[p] == '0' ? '1' : '0';
                        flipped++;
                    }
                images.add(Dataset.image(image.id(), image.label(), new String(pixels)));
            }
            result.add(new Noise(rate, images, flipped));
        }
        return result;
    }
    static List<String> dataSummary() {
        int pixels = data.width() * data.height();
        int[] training = new int[classes], valid = new int[classes], testing = new int[classes],
              ink = new int[classes];
        int[][] black = new int[classes][pixels], levels = new int[classes][pixels];
        for (Dataset.Image image : train) {
            int k = image.label();
            training[k]++;
            for (int p = 0; p < pixels; p++)
                if (image.pixels().charAt(p) == '1') {
                    ink[k]++;
                    black[k][p]++;
                }
        }
        for (Dataset.Image image : validation)
            valid[image.label()]++;
        for (Dataset.Image image : data.test())
            testing[image.label()]++;
        List<String> lines =
            new ArrayList<>(List.of("data", "train " + train.size() + " validation " + validation.size() +
                                                " test " + data.test().size() + " pixels " + pixels));
        for (int k = 0; k < classes; k++) {
            lines.add("class " + k + " train " + training[k] + " validation " + valid[k] + " test " +
                      testing[k] + " ink " + Evaluation.ratio(ink[k], training[k]));
            for (int p = 0; p < pixels; p++)
                levels[k][p] = training[k] == 0 ? 0 : Math.min(9, 10 * black[k][p] / training[k]);
        }
        lines.add("mean_images " + ints(order(classes)));
        lines.addAll(Evaluation.maps(levels, data.width(), data.height()));
        return lines;
    }
    static List<String> evaluateRun(Result result, List<Noise> noise) {
        Network net = result.network;
        int total = data.test().size(), top2 = 0;
        double correctConfidence = 0, wrongConfidence = 0;
        for (int i = 0; i < total; i++) {
            Network.Pass pass = result.test.passes.get(i);
            int predicted = result.predictions[i], label = data.test().get(i).label();
            if (predicted == label || Evaluation.second(pass.scores(), predicted) == label)
                top2++;
            if (predicted == label)
                correctConfidence += pass.scores()[predicted];
            else
                wrongConfidence += pass.scores()[predicted];
        }
        int events = 0, rows = 0, never = 0;
        for (int i = 0; i < train.size(); i++) {
            int count = 0;
            boolean learned = false;
            for (int e = 0; e < result.epochs.size(); e++) {
                boolean correct = result.epochs.get(e).train().correctness[i];
                if (correct)
                    learned = true;
                if (e > 0 && result.epochs.get(e - 1).train().correctness[i] && !correct)
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
            norms[l] = Math.sqrt(norm);
            changes[l] = Math.sqrt(change);
        }
        int correct = result.test.correct;
        List<String> lines = new ArrayList<>(List.of(
            "run " + result.run.name() + " network " + net.name + " optimizer " + result.run.optimizer(),
            "epochs " + result.epochs.size() + " best_epoch " + result.bestEpoch + " stop " + result.stop +
                " updates " + result.updates,
            "best_val_loss " + real(result.bestLoss, 6) + " best_val_acc " +
                Evaluation.ratio(result.bestCorrect, validation.size()) + " correct " + result.bestCorrect +
                "/" + validation.size(),
            "test_loss " + real(result.test.loss, 6) + " test_acc " + Evaluation.ratio(correct, total) +
                " correct " + correct + "/" + total,
            "top2_acc " + Evaluation.ratio(top2, total) + " correct " + top2 + "/" + total,
            "confidence correct " + (correct == 0 ? "-" : real(correctConfidence / correct, 4)) + " wrong " +
                (correct == total ? "-" : real(wrongConfidence / (total - correct), 4)),
            "forgetting events " + events + " rows " + rows + " never_learned " + never,
            "weight_norms " + reals(norms, 4), "weight_changes " + reals(changes, 4), "curve"));
        double maximum = 0;
        for (Epoch epoch : result.epochs) {
            maximum = Math.max(maximum, epoch.train().loss);
            maximum = Math.max(maximum, epoch.validation().loss);
        }
        for (Epoch epoch : result.epochs) {
            int ct = (int)Math.floor(39 * epoch.train().loss / maximum + 0.5),
                cv = (int)Math.floor(39 * epoch.validation().loss / maximum + 0.5);
            char[] curve = new char[40];
            Arrays.fill(curve, ' ');
            curve[ct] = 't';
            curve[cv] = ct == cv ? '*' : 'v';
            lines.add(String.format(Locale.ROOT, "%2d", epoch.number()) + " |" + new String(curve) + "|" +
                      (epoch.number() == result.bestEpoch ? " best" : ""));
        }
        lines.add("confusion");
        lines.addAll(Evaluation.confusionLines(result.confusion));
        lines.add("calibration");
        int[] bins = new int[settings.bins], hits = new int[settings.bins];
        double[] confidence = new double[settings.bins];
        for (int i = 0; i < total; i++) {
            double c = result.test.passes.get(i).scores()[result.predictions[i]];
            int bin = Math.min(settings.bins - 1, (int)Math.floor(c * settings.bins));
            bins[bin]++;
            confidence[bin] += c;
            if (result.predictions[i] == data.test().get(i).label())
                hits[bin]++;
        }
        double ece = 0;
        for (int b = 0; b < settings.bins; b++) {
            String mean = "-";
            if (bins[b] > 0) {
                double average = confidence[b] / bins[b];
                mean = real(average, 4);
                ece += ((double)bins[b] / total) * Math.abs((double)hits[b] / bins[b] - average);
            }
            lines.add("bin " + (b + 1) + " " + real((double)b / settings.bins, 2) + " " +
                      real((b + 1.0) / settings.bins, 2) + " count " + bins[b] + " accuracy " +
                      Evaluation.ratio(hits[b], bins[b]) + " confidence " + mean);
        }
        lines.add("ece " + real(ece, 4));
        int[] classCount = new int[classes];
        for (Dataset.Image image : data.test())
            classCount[image.label()]++;
        for (int l = 0; l < net.layers - 1; l++) {
            int units = net.units[l];
            double[][] means = new double[classes][units];
            int[] zeros = new int[units], preferred = new int[units];
            for (int i = 0; i < total; i++)
                for (int j = 0; j < units; j++) {
                    double value = result.test.passes.get(i).a()[l + 1][j];
                    means[data.test().get(i).label()][j] += value;
                    if (value == 0)
                        zeros[j]++;
                }
            lines.add("hidden " + (l + 1) + " " + net.activations[l] + " units " + units);
            for (int k = 0; k < classes; k++) {
                if (classCount[k] > 0)
                    for (int j = 0; j < units; j++)
                        means[k][j] /= classCount[k];
                lines.add("class " + k + " mean " + (classCount[k] == 0 ? "-" : reals(means[k], 4)));
            }
            for (int j = 0; j < units; j++) {
                int chosen = -1;
                for (int k = 0; k < classes; k++)
                    if (classCount[k] > 0 && (chosen < 0 || means[k][j] > means[chosen][j]))
                        chosen = k;
                preferred[j] = chosen;
            }
            lines.add("preferred " + ints(preferred));
            if (net.activations[l].equals("RELU"))
                lines.add("zero_counts " + ints(zeros));
        }
        List<Integer> weights = new ArrayList<>();
        for (int p = 0; p < net.parameters; p++)
            if (net.weight[p])
                weights.add(p);
        weights.sort((a, b) -> {
            int c = Double.compare(Math.abs(result.theta[a]), Math.abs(result.theta[b]));
            return c != 0 ? c : Integer.compare(a, b);
        });
        lines.add("pruning");
        for (int q : settings.prune) {
            int removed = q * net.weights / 100;
            double[] theta = result.theta.clone();
            for (int i = 0; i < removed; i++)
                theta[weights.get(i)] = 0;
            Summary pruned = evaluate(net, theta, data.test());
            lines.add("prune " + q + " removed " + removed + " correct " + pruned.correct + " test_acc " +
                      Evaluation.ratio(pruned.correct, total) + " test_loss " + real(pruned.loss, 6));
        }
        lines.add("noise");
        for (Noise noisy : noise) {
            Summary evaluated = evaluate(net, result.theta, noisy.images());
            lines.add("noise " + noisy.rate() + " correct " + evaluated.correct + " test_acc " +
                      Evaluation.ratio(evaluated.correct, total));
        }
        String misclassified = "misclassified " + (total - correct);
        for (int i = 0; i < total; i++)
            if (result.predictions[i] != data.test().get(i).label())
                misclassified += " " + data.test().get(i).id();
        lines.add(misclassified);
        return lines;
    }

    record Confused(int actual, int predicted, int count) {}
    static List<String> comparison(List<Result> results, List<Noise> noise) {
        List<Result> ranked = new ArrayList<>(results);
        ranked.sort((a, b) -> {
            int c = Integer.compare(b.test.correct, a.test.correct);
            if (c == 0)
                c = Double.compare(a.bestLoss, b.bestLoss);
            return c != 0 ? c : Integer.compare(a.index, b.index);
        });
        Result top = ranked.get(0);
        int total = data.test().size();
        List<String> lines = new ArrayList<>(List.of("comparison"));
        for (int i = 0; i < ranked.size(); i++) {
            Result result = ranked.get(i);
            lines.add("rank " + (i + 1) + " " + result.run.name() + " correct " + result.test.correct +
                      " test_acc " + Evaluation.ratio(result.test.correct, total) + " best_val_loss " +
                      real(result.bestLoss, 6) + " test_loss " + real(result.test.loss, 6) + " best_epoch " +
                      result.bestEpoch + " epochs " + result.epochs.size() + " updates " + result.updates);
        }
        lines.add("agreement");
        for (Result a : results) {
            String text = a.run.name();
            for (Result b : results) {
                int count = 0;
                for (int i = 0; i < total; i++)
                    if (a.predictions[i] == b.predictions[i])
                        count++;
                text += " " + count;
            }
            lines.add(text);
        }
        lines.add("mcnemar " + top.run.name());
        for (Result result : ranked)
            if (result != top) {
                int b = 0, c = 0;
                for (int i = 0; i < total; i++) {
                    boolean first = top.predictions[i] == data.test().get(i).label(),
                            second = result.predictions[i] == data.test().get(i).label();
                    if (first && !second)
                        b++;
                    if (second && !first)
                        c++;
                }
                int difference = Math.max(Math.abs(b - c) - 1, 0), numerator = difference * difference,
                    denominator = b + c;
                lines.add("vs " + result.run.name() + " b " + b + " c " + c + " chi2 " +
                          (denominator == 0 ? "0.0000" : Evaluation.ratio(numerator, denominator)) +
                          " significant " + (numerator * 1000 > 3841 * denominator ? "yes" : "no"));
            }
        int[] ensemble = new int[total];
        int ensembleCorrect = 0, fixed = 0, broken = 0;
        for (int i = 0; i < total; i++) {
            int[] votes = new int[classes];
            for (Result result : results)
                votes[result.predictions[i]]++;
            int most = 0;
            for (int count : votes)
                most = Math.max(most, count);
            for (Result result : ranked)
                if (votes[result.predictions[i]] == most) {
                    ensemble[i] = result.predictions[i];
                    break;
                }
            boolean correct = ensemble[i] == data.test().get(i).label(),
                    topCorrect = top.predictions[i] == data.test().get(i).label();
            if (correct)
                ensembleCorrect++;
            if (correct && !topCorrect)
                fixed++;
            if (!correct && topCorrect)
                broken++;
        }
        lines.add("ensemble correct " + ensembleCorrect + "/" + total + " test_acc " +
                  Evaluation.ratio(ensembleCorrect, total) + " fixed " + fixed + " broken " + broken);
        List<Result> soft = new ArrayList<>();
        for (Result result : results)
            if (result.network.activations[result.network.layers - 1].equals("SOFTMAX"))
                soft.add(result);
        if (soft.isEmpty())
            lines.add("soft_ensemble none");
        else {
            int correct = 0;
            for (int i = 0; i < total; i++) {
                double[] scores = new double[classes];
                for (Result result : soft)
                    for (int k = 0; k < classes; k++)
                        scores[k] += result.test.passes.get(i).scores()[k];
                for (int k = 0; k < classes; k++)
                    scores[k] /= soft.size();
                if (Evaluation.prediction(scores) == data.test().get(i).label())
                    correct++;
            }
            lines.add("soft_ensemble runs " + soft.size() + " correct " + correct + "/" + total +
                      " test_acc " + Evaluation.ratio(correct, total));
        }
        for (Noise noisy : noise)
            lines.add("noise " + noisy.rate() + " flipped " + noisy.flipped());
        int[][] aggregate = new int[classes][classes];
        for (Result result : results)
            for (int y = 0; y < classes; y++)
                for (int predicted = 0; predicted < classes; predicted++)
                    aggregate[y][predicted] += result.confusion[y][predicted];
        List<Confused> confused = new ArrayList<>();
        for (int y = 0; y < classes; y++)
            for (int predicted = 0; predicted < classes; predicted++)
                if (y != predicted && aggregate[y][predicted] > 0)
                    confused.add(new Confused(y, predicted, aggregate[y][predicted]));
        confused.sort((a, b) -> {
            int c = Integer.compare(b.count(), a.count());
            if (c == 0)
                c = Integer.compare(a.actual(), b.actual());
            return c != 0 ? c : Integer.compare(a.predicted(), b.predicted());
        });
        lines.add("confused_pairs");
        for (int i = 0; i < Math.min(5, confused.size()); i++) {
            Confused pair = confused.get(i);
            lines.add(pair.actual() + " as " + pair.predicted() + " count " + pair.count());
        }
        lines.add("");
        lines.add("saliency " + top.run.name());
        lines.add("classes " + ints(order(classes)));
        int pixels = data.width() * data.height();
        double[][] means = new double[classes][pixels];
        int[] counts = new int[classes];
        int[][] levels = new int[classes][pixels];
        for (int i = 0; i < total; i++) {
            int label = data.test().get(i).label();
            counts[label]++;
            double[] gradient = top.network.backward(top.theta, top.test.passes.get(i)).input();
            for (int p = 0; p < pixels; p++)
                means[label][p] += Math.abs(gradient[p]);
        }
        for (int k = 0; k < classes; k++) {
            double maximum = 0;
            if (counts[k] > 0)
                for (int p = 0; p < pixels; p++) {
                    means[k][p] /= counts[k];
                    maximum = Math.max(maximum, means[k][p]);
                }
            if (maximum > 0)
                for (int p = 0; p < pixels; p++)
                    levels[k][p] = Math.min(9, (int)Math.floor(10 * means[k][p] / maximum));
        }
        lines.addAll(Evaluation.maps(levels, data.width(), data.height()));
        lines.add("");
        lines.add("hardest_training_examples " + top.run.name());
        Summary training = evaluate(top.network, top.theta, train);
        List<Integer> hardest = new ArrayList<>();
        for (int i = 0; i < train.size(); i++)
            hardest.add(i);
        hardest.sort((a, b) -> {
            int c = Double.compare(training.passes.get(b).loss(), training.passes.get(a).loss());
            return c != 0 ? c : Integer.compare(a, b);
        });
        for (int j = 0; j < Math.min(5, hardest.size()); j++) {
            int i = hardest.get(j);
            Dataset.Image image = train.get(i);
            Network.Pass pass = training.passes.get(i);
            lines.add(image.id() + " label " + image.label() + " predicted " +
                      Evaluation.prediction(pass.scores()) + " loss " + real(pass.loss(), 6));
        }
        lines.add("");
        lines.add("misclassified_examples " + top.run.name());
        for (int i = 0; i < total; i++)
            if (top.predictions[i] != data.test().get(i).label()) {
                Dataset.Image image = data.test().get(i);
                Network.Pass pass = top.test.passes.get(i);
                String predictions = "";
                for (Result result : results)
                    predictions += " " + result.predictions[i];
                lines.add(image.id() + " label " + image.label() + " predicted " + top.predictions[i] +
                          " confidence " + real(pass.scores()[top.predictions[i]], 4) + " true_score " +
                          real(pass.scores()[image.label()], 4) + " runs" + predictions + " ensemble " +
                          ensemble[i]);
                int nearest = 0, minimum = Integer.MAX_VALUE;
                for (int j = 0; j < data.train().size(); j++) {
                    int distance = 0;
                    String pixelsText = data.train().get(j).pixels();
                    for (int p = 0; p < pixels; p++)
                        if (image.pixels().charAt(p) != pixelsText.charAt(p))
                            distance++;
                    if (distance < minimum) {
                        minimum = distance;
                        nearest = j;
                    }
                }
                Dataset.Image neighbor = data.train().get(nearest);
                lines.add("nearest " + neighbor.id() + " label " + neighbor.label() + " distance " + minimum);
                lines.addAll(Evaluation.image(image, data.width(), data.height()));
            }
        return lines;
    }
    static List<String> trainingLog(List<Result> results) {
        List<String> lines =
            new ArrayList<>(List.of("run,epoch,lr,grad_norm,train_loss,train_acc,val_loss,val_acc,improved"));
        for (Result result : results)
            for (Epoch e : result.epochs)
                lines.add(result.run.name() + "," + e.number() + "," + real(e.rate(), 6) + "," +
                          real(e.magnitude(), 4) + "," + real(e.train().loss, 6) + "," +
                          Evaluation.ratio(e.train().correct, train.size()) + "," +
                          real(e.validation().loss, 6) + "," +
                          Evaluation.ratio(e.validation().correct, validation.size()) + "," +
                          (e.improved() ? 1 : 0));
        return lines;
    }
    static List<String> weights(List<Result> results) {
        List<String> lines = new ArrayList<>();
        for (Result result : results) {
            if (!lines.isEmpty())
                lines.add("");
            Network net = result.network;
            lines.add("RUN " + result.run.name() + " NETWORK " + net.name + " EPOCH " + result.bestEpoch);
            for (int l = 0; l < net.layers; l++) {
                int previous = l == 0 ? net.inputs : net.units[l - 1], units = net.units[l];
                lines.add("LAYER " + (l + 1) + " " + units + " " + previous);
                for (int j = 0; j < units; j++) {
                    String row = "W";
                    for (int i = 0; i < previous; i++)
                        row += " " + real(result.theta[net.starts[l] + j * previous + i], 4);
                    lines.add(row);
                }
                String biases = "B";
                for (int j = 0; j < units; j++)
                    biases += " " + real(result.theta[net.biases[l] + j], 4);
                lines.add(biases);
            }
        }
        return lines;
    }
    static List<String> predictions(List<Result> results) {
        List<String> lines = new ArrayList<>(List.of("run,id,label,predicted,confidence"));
        for (Result result : results)
            for (int i = 0; i < data.test().size(); i++) {
                Dataset.Image image = data.test().get(i);
                int predicted = result.predictions[i];
                lines.add(result.run.name() + "," + image.id() + "," + image.label() + "," + predicted + "," +
                          real(result.test.passes.get(i).scores()[predicted], 4));
            }
        return lines;
    }
    static void write(String name, List<String> lines) throws Exception {
        Files.createDirectories(Path.of("output"));
        Files.writeString(Path.of("output", name), String.join("\n", lines) + "\n");
    }
    public static void main(String[] args) throws Exception {
        data = Dataset.read();
        settings = data.settings();
        classes = data.networks().get(0).classes;
        int count = data.train().size(), training = count - count / 5;
        train = new ArrayList<>(data.train().subList(0, training));
        validation = new ArrayList<>(data.train().subList(training, count));
        List<String> checks = gradientChecks();
        List<Result> results = new ArrayList<>();
        for (int i = 0; i < settings.runs.size(); i++)
            results.add(fit(settings.runs.get(i), i));
        List<Noise> noise = noise();
        List<String> evaluation = dataSummary();
        evaluation.add("");
        for (Result result : results) {
            evaluation.addAll(evaluateRun(result, noise));
            evaluation.add("");
        }
        evaluation.addAll(comparison(results, noise));
        write("gradient_check.txt", checks);
        write("training_log.csv", trainingLog(results));
        write("final_weights.txt", weights(results));
        write("predictions.csv", predictions(results));
        write("evaluation.txt", evaluation);
    }
}
