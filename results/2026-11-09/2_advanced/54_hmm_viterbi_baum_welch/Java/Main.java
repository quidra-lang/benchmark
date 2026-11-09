import java.util.*;
import java.io.IOException;

public final class Main {
    record Sequence(String name, String role, int[] observations, int[] truth) {}
    record BwRecord(double loglik, double heldout, double maximum, boolean violation) {}
    record VtRecord(double logprob, double loglik, int changed) {}
    record Composition(double rich, double motif, boolean island) {}
    static final class Cv {
        String candidate;
        int correct, positions;
        int[] foldCorrect, foldPositions, foldRecords;
        int[][] matrix;
    }
    static ModelIo.Model initial;
    static ModelIo.Model[] models = new ModelIo.Model[4];
    static Map<String, String[]> params;
    static List<Sequence> sequences = new ArrayList<>(), train = new ArrayList<>(), test = new ArrayList<>();
    static List<String> rejections = new ArrayList<>();
    static int sequenceRejected, labeledRejected, segmentState, bestHeldout, vtIterations;
    static boolean vtConverged;
    static List<BwRecord> bwTrace = new ArrayList<>();
    static List<VtRecord> vtTrace = new ArrayList<>();
    static List<Cv> candidates = new ArrayList<>();
    static Cv selected;
    static Inference.Decoding[][] unlabeledDecoded, testDecoded, trainDecoded;
    static int[][] testCorrect = new int[4][2];
    static List<String> decodingLines = new ArrayList<>(), segmentLines = new ArrayList<>();
    static int integer(String key) {
        return Integer.parseInt(params.get(key)[0]);
    }
    static double number(String key) {
        return Double.parseDouble(params.get(key)[0]);
    }
    static String word(String key) {
        return params.get(key)[0];
    }
    static String f(double value) {
        return ModelIo.f(value);
    }
    static int index(char[] values, char c) {
        for (int i = 0; i < values.length; i++)
            if (values[i] == c)
                return i;
        return -1;
    }
    static String observationError(String observed) {
        for (int t = 0; t < observed.length(); t++) {
            char c = observed.charAt(t);
            if (index(initial.symbols, c) < 0 && c != initial.missing)
                return "invalid symbol " + c + " at position " + (t + 1);
        }
        return null;
    }
    static String lengthError(String observed) {
        if (observed.length() < integer("min_sequence_length"))
            return "too short " + observed.length();
        int missing = 0;
        for (int i = 0; i < observed.length(); i++)
            if (observed.charAt(i) == initial.missing)
                missing++;
        return 100 * missing > integer("max_missing_percent") * observed.length()
            ? "too many missing " + missing
            : null;
    }
    static int[] observations(String text) {
        int[] result = new int[text.length()];
        for (int i = 0; i < text.length(); i++)
            result[i] = index(initial.symbols, text.charAt(i));
        return result;
    }
    static void validate(ModelIo.Data input) {
        Set<String> seen = new HashSet<>();
        for (int i = 0; i < input.sequences().size(); i++) {
            String[] words = input.sequences().get(i).split(" ");
            String name = words[0], observed = words[1].toUpperCase(Locale.ROOT);
            String error = !seen.add(name) ? "duplicate name" : observationError(observed);
            if (error == null)
                error = lengthError(observed);
            if (error != null) {
                sequenceRejected++;
                rejections.add("REJECT sequences.txt line " + (i + 1) + " " + name + " " + error);
            } else
                sequences.add(new Sequence(name, "", observations(observed), null));
        }
        seen.clear();
        for (int i = 0; i < input.labeled().size(); i += 2) {
            String[] words = input.labeled().get(i).split(" ");
            String name = words[0], role = words[1], observed = words[2].toUpperCase(Locale.ROOT),
                   labels = input.labeled().get(i + 1);
            String error = !seen.add(name) ? "duplicate name" : observationError(observed);
            if (error == null)
                for (int t = 0; t < labels.length(); t++)
                    if (index(initial.states, labels.charAt(t)) < 0) {
                        error = "invalid label " + labels.charAt(t) + " at position " + (t + 1);
                        break;
                    }
            if (error == null && observed.length() != labels.length())
                error = "length mismatch " + observed.length() + " " + labels.length();
            if (error == null)
                error = lengthError(observed);
            if (error != null) {
                labeledRejected++;
                rejections.add("REJECT labeled.txt line " + (i + 1) + " " + name + " " + error);
            } else {
                int[] truth = new int[labels.length()];
                for (int t = 0; t < truth.length; t++)
                    truth[t] = index(initial.states, labels.charAt(t));
                Sequence record = new Sequence(name, role, observations(observed), truth);
                (role.equals("TRAIN") ? train : test).add(record);
            }
        }
    }
    static List<int[]> observed(List<Sequence> records) {
        List<int[]> result = new ArrayList<>();
        for (Sequence record : records)
            result.add(record.observations());
        return result;
    }
    static List<Training.Pair> pairs(List<Sequence> records) {
        List<Training.Pair> result = new ArrayList<>();
        for (Sequence record : records)
            result.add(new Training.Pair(record.observations(), record.truth()));
        return result;
    }
    static double maximumChange(ModelIo.Model a, ModelIo.Model b) {
        double maximum = 0;
        for (int i = 0; i < a.states.length; i++) {
            maximum = Math.max(maximum, Math.abs(a.pi[i] - b.pi[i]));
            for (int j = 0; j < a.states.length; j++)
                maximum = Math.max(maximum, Math.abs(a.a[i][j] - b.a[i][j]));
            for (int c = 0; c < a.symbols.length; c++)
                maximum = Math.max(maximum, Math.abs(a.b[i][c] - b.b[i][c]));
        }
        return maximum;
    }
    static void baumWelch() {
        List<int[]> data = observed(sequences), heldout = observed(train);
        heldout.addAll(observed(test));
        ModelIo.Model model = initial;
        bwTrace.add(new BwRecord(Training.loglik(model, data), Training.loglik(model, heldout), 0, false));
        bestHeldout = 0;
        for (int t = 1; t <= integer("iterations"); t++) {
            ModelIo.Model next = Training.baumWelch(model, data, number("pseudocount"));
            double loglik = Training.loglik(next, data), held = Training.loglik(next, heldout),
                   previous = bwTrace.getLast().loglik();
            bwTrace.add(new BwRecord(loglik, held, maximumChange(model, next),
                                     loglik < previous - 0.000001 * Math.abs(previous)));
            if (held > bwTrace.get(bestHeldout).heldout())
                bestHeldout = t;
            model = next;
        }
        models[1] = model;
    }
    static List<int[]> viterbiPaths(ModelIo.Model model) {
        List<int[]> paths = new ArrayList<>();
        for (Sequence record : sequences)
            paths.add(Inference.viterbi(model, record.observations()).states());
        return paths;
    }
    static VtRecord viterbiRecord(ModelIo.Model model, int changed) {
        double logprob = 0;
        for (Sequence record : sequences)
            logprob += Inference.viterbi(model, record.observations()).logprob();
        return new VtRecord(logprob, Training.loglik(model, observed(sequences)), changed);
    }
    static void viterbiTraining() {
        ModelIo.Model model = initial;
        List<int[]> paths = viterbiPaths(model);
        vtTrace.add(viterbiRecord(model, -1));
        for (int t = 1; t <= integer("iterations"); t++) {
            List<Training.Pair> pairs = new ArrayList<>();
            for (int i = 0; i < sequences.size(); i++)
                pairs.add(new Training.Pair(sequences.get(i).observations(), paths.get(i)));
            model = Training.count(initial, pairs, number("pseudocount"), "VITERBI_TRAINING");
            List<int[]> next = viterbiPaths(model);
            int changes = 0;
            for (int i = 0; i < paths.size(); i++)
                changes += paths.get(i).length - Evaluation.correct(paths.get(i), next.get(i));
            vtTrace.add(viterbiRecord(model, changes));
            paths = next;
            vtIterations = t;
            if (changes == 0) {
                vtConverged = true;
                break;
            }
        }
        models[2] = model;
    }
    static void supervised() {
        int folds = integer("folds"), k = initial.states.length;
        for (String candidate : params.get("smoothing")) {
            Cv cv = new Cv();
            cv.candidate = candidate;
            cv.foldCorrect = new int[folds];
            cv.foldPositions = new int[folds];
            cv.foldRecords = new int[folds];
            cv.matrix = new int[k][k];
            for (int fold = 0; fold < folds; fold++) {
                List<Sequence> training = new ArrayList<>(), validation = new ArrayList<>();
                for (int i = 0; i < train.size(); i++)
                    (i % folds == fold ? validation : training).add(train.get(i));
                ModelIo.Model model =
                    Training.count(initial, pairs(training), Double.parseDouble(candidate), "SUPERVISED");
                for (Sequence record : validation) {
                    int[] path = Inference.viterbi(model, record.observations()).states();
                    int correct = Evaluation.correct(record.truth(), path);
                    cv.foldRecords[fold]++;
                    cv.foldPositions[fold] += path.length;
                    cv.foldCorrect[fold] += correct;
                    cv.positions += path.length;
                    cv.correct += correct;
                    Evaluation.accumulate(cv.matrix, record.truth(), path);
                }
            }
            candidates.add(cv);
            if (selected == null || cv.correct > selected.correct)
                selected = cv;
        }
        models[3] =
            Training.count(initial, pairs(train), Double.parseDouble(selected.candidate), "SUPERVISED");
    }
    static Inference.Decoding[][] decode(List<Sequence> records) {
        Inference.Decoding[][] result = new Inference.Decoding[4][records.size()];
        for (int m = 0; m < 4; m++)
            for (int i = 0; i < records.size(); i++)
                result[m][i] = Inference.decode(models[m], records.get(i).observations());
        return result;
    }
    static List<Evaluation.Interval> segments(int[] path) {
        List<Evaluation.Interval> result = new ArrayList<>();
        for (Evaluation.Run run : Evaluation.runs(path))
            if (run.state() == segmentState) {
                if (!result.isEmpty() && run.start() - result.getLast().end() - 1 <= integer("merge_gap")) {
                    Evaluation.Interval last = result.removeLast();
                    result.add(new Evaluation.Interval(last.start(), run.end()));
                } else
                    result.add(new Evaluation.Interval(run.start(), run.end()));
            }
        result.removeIf(interval -> interval.length() < integer("min_segment_length"));
        return result;
    }
    static List<Evaluation.Interval> truthRegions(int[] path) {
        List<Evaluation.Interval> result = new ArrayList<>();
        for (Evaluation.Run run : Evaluation.runs(path))
            if (run.state() == segmentState)
                result.add(new Evaluation.Interval(run.start(), run.end()));
        return result;
    }
    static Composition composition(int[] observations, Evaluation.Interval segment) {
        int n = 0, r = 0, q = 0, k1 = 0, k2 = 0;
        int first = index(initial.symbols, params.get("motif")[0].charAt(0)),
            second = index(initial.symbols, params.get("motif")[1].charAt(0));
        Set<Integer> rich = new HashSet<>();
        for (String symbol : params.get("rich_symbols"))
            rich.add(index(initial.symbols, symbol.charAt(0)));
        for (int t = segment.start() - 1; t < segment.end(); t++) {
            int value = observations[t];
            if (value < 0)
                continue;
            n++;
            if (rich.contains(value))
                r++;
            if (value == first)
                k1++;
            if (value == second)
                k2++;
            if (t + 1 < segment.end() && value == first && observations[t + 1] == second)
                q++;
        }
        boolean island = k1 * k2 > 0 && 100 * r >= integer("min_rich_percent") * n &&
                         100 * q * n >= integer("min_motif_percent") * k1 * k2;
        return new Composition(n == 0 ? Double.NaN : (double)r / n,
                               k1 * k2 == 0 ? Double.NaN : (double)(q * n) / (k1 * k2), island);
    }
    static int[] path(Inference.Decoding decoding, int decoder) {
        return decoder == 0 ? decoding.viterbi().states() : decoding.posterior();
    }
    static String states(int[] path) {
        StringBuilder text = new StringBuilder();
        for (int state : path)
            text.append(initial.states[state]);
        return text.toString();
    }
    static String symbols(int[] observations) {
        StringBuilder text = new StringBuilder();
        for (int symbol : observations)
            text.append(initial.symbols[symbol]);
        return text.toString();
    }
    static int positions(List<Sequence> records) {
        int total = 0;
        for (Sequence record : records)
            total += record.observations().length;
        return total;
    }
    static int missing(List<Sequence> records) {
        int total = 0;
        for (Sequence record : records)
            for (int symbol : record.observations())
                if (symbol < 0)
                    total++;
        return total;
    }
    static void block(List<String> out, String heading) {
        if (!out.isEmpty())
            out.add("");
        out.add(heading);
    }

    static List<String> evaluationReport() {
        List<String> out = new ArrayList<>();
        int k = initial.states.length;
        for (int m = 0; m < 4; m++)
            for (int decoder = 0; decoder < 2; decoder++) {
                block(out, "EVALUATION " + models[m].name + " " + (decoder == 0 ? "VITERBI" : "POSTERIOR"));
                int[][] matrix = new int[k][k];
                int[] regions = new int[4], boundaries = new int[4], bins = new int[10],
                      binCorrect = new int[10], recordCorrect = new int[test.size()];
                for (int r = 0; r < test.size(); r++) {
                    Sequence record = test.get(r);
                    Inference.Decoding decoding = testDecoded[m][r];
                    int[] prediction = path(decoding, decoder);
                    recordCorrect[r] = Evaluation.correct(record.truth(), prediction);
                    testCorrect[m][decoder] += recordCorrect[r];
                    Evaluation.accumulate(matrix, record.truth(), prediction);
                    int[] rc = Evaluation.regions(segments(prediction), truthRegions(record.truth())),
                          bc = Evaluation.boundaryMatches(prediction, record.truth(),
                                                          integer("boundary_tolerance"));
                    for (int j = 0; j < 4; j++) {
                        regions[j] += rc[j];
                        boundaries[j] += bc[j];
                    }
                    if (decoder == 1)
                        for (int t = 0; t < prediction.length; t++) {
                            int bin = Math.min(9, (int)Math.floor(10 * decoding.confidence()[t]));
                            bins[bin]++;
                            if (prediction[t] == record.truth()[t])
                                binCorrect[bin]++;
                        }
                }
                out.addAll(Evaluation.matrix(initial.states, matrix));
                out.addAll(Evaluation.metrics(initial.states, matrix));
                out.add("REGIONS " + initial.states[segmentState] + " predicted " + regions[0] + " true " +
                        regions[1] + " precision " + Evaluation.fraction(regions[2], regions[0]) +
                        " recall " + Evaluation.fraction(regions[3], regions[1]));
                out.add("BOUNDARIES predicted " + boundaries[0] + " true " + boundaries[1] + " precision " +
                        Evaluation.fraction(boundaries[2], boundaries[0]) + " recall " +
                        Evaluation.fraction(boundaries[3], boundaries[1]));
                if (decoder == 1)
                    for (int bin = 0; bin < 10; bin++)
                        if (bins[bin] > 0)
                            out.add("CALIBRATION 0." + bin + "-" + (bin == 9 ? "1.0" : "0." + (bin + 1)) +
                                    " positions " + bins[bin] + " correct " + binCorrect[bin] + " accuracy " +
                                    Evaluation.fraction(binCorrect[bin], bins[bin]));
                for (int r = 0; r < test.size(); r++)
                    out.add("RECORD " + test.get(r).name() + " length " + test.get(r).observations().length +
                            " correct " + recordCorrect[r]);
            }
        int folds = integer("folds");
        block(out, "CROSS_VALIDATION folds " + folds);
        for (Cv candidate : candidates)
            out.add("SMOOTHING " + candidate.candidate + " positions " + candidate.positions + " correct " +
                    candidate.correct + " accuracy " +
                    Evaluation.fraction(candidate.correct, candidate.positions));
        out.add("SELECTED " + selected.candidate);
        for (int fold = 0; fold < folds; fold++)
            out.add("FOLD " + (fold + 1) + " records " + selected.foldRecords[fold] + " positions " +
                    selected.foldPositions[fold] + " correct " + selected.foldCorrect[fold] + " accuracy " +
                    Evaluation.fraction(selected.foldCorrect[fold], selected.foldPositions[fold]));
        out.addAll(Evaluation.matrix(initial.states, selected.matrix));
        out.addAll(Evaluation.metrics(initial.states, selected.matrix));
        block(out, "LEARNING_CURVE");
        for (int count = 1; count <= train.size(); count++) {
            ModelIo.Model model = Training.count(initial, pairs(train.subList(0, count)),
                                                 Double.parseDouble(selected.candidate), "SUPERVISED");
            int correct = 0;
            for (Sequence record : test)
                correct += Evaluation.correct(record.truth(),
                                              Inference.viterbi(model, record.observations()).states());
            out.add("RECORDS " + count + " correct " + correct + " accuracy " +
                    Evaluation.fraction(correct, positions(test)));
        }
        return out;
    }
    static void annotate() {
        segmentLines.add(
            "sequence,decoder,start,end,length,mean_posterior,support,rich_fraction,motif_ratio,island");
        Sampler.Random random = new Sampler.Random(integer("posterior_seed"));
        int samples = integer("posterior_samples");
        ModelIo.Model model = models[1];
        for (int r = 0; r < sequences.size(); r++) {
            Sequence record = sequences.get(r);
            Inference.Decoding decoding = unlabeledDecoded[1][r];
            List<int[]> paths = new ArrayList<>();
            int segmentTotal = 0;
            for (int sample = 0; sample < samples; sample++) {
                int[] path = Sampler.posterior(model, decoding.fb().forward(), random);
                paths.add(path);
                segmentTotal += segments(path).size();
            }
            int differences = record.observations().length -
                              Evaluation.correct(decoding.viterbi().states(), decoding.posterior()),
                uncertain = 0;
            char[] confident = states(decoding.posterior()).toCharArray(),
                   imputed = new char[record.observations().length];
            for (int t = 0; t < record.observations().length; t++) {
                if (decoding.confidence()[t] < number("confidence")) {
                    uncertain++;
                    confident[t] = '.';
                }
                if (record.observations()[t] >= 0)
                    imputed[t] = initial.symbols[record.observations()[t]];
                else {
                    double[] probabilities = new double[initial.symbols.length];
                    for (int c = 0; c < probabilities.length; c++)
                        for (int i = 0; i < initial.states.length; i++)
                            probabilities[c] += decoding.fb().gamma()[t][i] * model.b[i][c];
                    imputed[t] = Character.toLowerCase(initial.symbols[Inference.maximum(probabilities)]);
                }
            }
            decodingLines.add("SEQUENCE " + record.name() + " length " + record.observations().length +
                              " loglik " + f(decoding.fb().loglik()) + " viterbi " +
                              f(decoding.viterbi().logprob()) + " differences " + differences +
                              " uncertain " + uncertain + " expected_segments " +
                              f((double)segmentTotal / samples));
            decodingLines.add("VITERBI " + states(decoding.viterbi().states()));
            decodingLines.add("POSTERIOR " + states(decoding.posterior()));
            decodingLines.add("CONFIDENT " + new String(confident));
            decodingLines.add("IMPUTED " + new String(imputed));
            for (int decoder = 0; decoder < 2; decoder++)
                for (Evaluation.Interval segment : segments(path(decoding, decoder))) {
                    double sum = 0;
                    for (int t = segment.start() - 1; t < segment.end(); t++)
                        sum += decoding.fb().gamma()[t][segmentState];
                    int support = 0;
                    for (int[] sample : paths) {
                        int count = 0;
                        for (int t = segment.start() - 1; t < segment.end(); t++)
                            if (sample[t] == segmentState)
                                count++;
                        if (2 * count > segment.length())
                            support++;
                    }
                    Composition composition = composition(record.observations(), segment);
                    segmentLines.add(record.name() + "," + (decoder == 0 ? "viterbi" : "posterior") + "," +
                                     segment.start() + "," + segment.end() + "," + segment.length() + "," +
                                     f(sum / segment.length()) + "," + support + "," + f(composition.rich()) +
                                     "," + f(composition.motif()) + "," +
                                     (composition.island() ? "yes" : "no"));
                }
        }
    }
    static List<String> samples() {
        List<String> out = new ArrayList<>();
        Sampler.Random random = new Sampler.Random(integer("sample_seed"));
        int viterbiCorrect = 0, posteriorCorrect = 0, total = 0;
        for (int number = 1; number <= integer("sample_count"); number++) {
            Sampler.Synthetic sample = Sampler.synthetic(models[1], integer("sample_length"), random);
            Inference.Decoding decoding = Inference.decode(models[1], sample.observations());
            int vc = Evaluation.correct(sample.states(), decoding.viterbi().states()),
                pc = Evaluation.correct(sample.states(), decoding.posterior());
            viterbiCorrect += vc;
            posteriorCorrect += pc;
            total += sample.states().length;
            out.add("SAMPLE " + number + " loglik " + f(decoding.fb().loglik()) + " viterbi " +
                    f(decoding.viterbi().logprob()) + " viterbi_correct " + vc + " posterior_correct " + pc);
            out.add("STATES " + states(sample.states()));
            out.add("SYMBOLS " + symbols(sample.observations()));
            out.add("VITERBI " + states(decoding.viterbi().states()));
            out.add("POSTERIOR " + states(decoding.posterior()));
        }
        out.add("TOTAL positions " + total + " viterbi_accuracy " +
                Evaluation.fraction(viterbiCorrect, total) + " posterior_accuracy " +
                Evaluation.fraction(posteriorCorrect, total));
        return out;
    }
    static List<String> baumTraceReport() {
        List<String> out = new ArrayList<>(List.of("iteration,loglik,heldout,change,max_change,status"));
        for (int t = 0; t < bwTrace.size(); t++) {
            BwRecord row = bwTrace.get(t);
            out.add(t + "," + f(row.loglik()) + "," + f(row.heldout()) + "," +
                    (t == 0 ? ",,"
                            : f(row.loglik() - bwTrace.get(t - 1).loglik()) + "," +
                                  ModelIo.real(row.maximum(), 6) + "," +
                                  (row.violation() ? "violation" : "ok")));
        }
        return out;
    }
    static List<String> viterbiTraceReport() {
        List<String> out = new ArrayList<>(List.of("iteration,logprob,loglik,changed"));
        for (int t = 0; t < vtTrace.size(); t++) {
            VtRecord row = vtTrace.get(t);
            out.add(t + "," + f(row.logprob()) + "," + f(row.loglik()) + "," +
                    (t == 0 ? "" : Integer.toString(row.changed())));
        }
        return out;
    }

    record Statistics(int[] counts, int[] runs, int positions) {}
    static Statistics statistics(List<int[]> paths) {
        int k = initial.states.length;
        int[] counts = new int[k], runs = new int[k];
        int positions = 0;
        for (int[] path : paths) {
            positions += path.length;
            for (int state : path)
                counts[state]++;
            for (Evaluation.Run run : Evaluation.runs(path))
                runs[run.state()]++;
        }
        return new Statistics(counts, runs, positions);
    }
    static List<int[]> truthPaths(List<Sequence> records) {
        List<int[]> paths = new ArrayList<>();
        for (Sequence record : records)
            paths.add(record.truth());
        return paths;
    }
    static void truthStatistics(List<String> out, String role, List<Sequence> records) {
        Statistics stats = statistics(truthPaths(records));
        for (int i = 0; i < initial.states.length; i++)
            out.add("TRUTH " + role + " " + initial.states[i] + " occupancy " +
                    f((double)stats.counts()[i] / stats.positions()) + " mean_run " +
                    f(stats.runs()[i] == 0 ? Double.NaN : (double)stats.counts()[i] / stats.runs()[i]));
    }
    static double[] stationary(ModelIo.Model model) {
        int k = model.states.length;
        double[][] system = new double[k][k + 1];
        for (int row = 0; row < k - 1; row++)
            for (int column = 0; column < k; column++)
                system[row][column] = model.a[column][row] - (row == column ? 1 : 0);
        for (int column = 0; column < k; column++)
            system[k - 1][column] = 1;
        system[k - 1][k] = 1;
        for (int column = 0; column < k; column++) {
            int pivot = column;
            for (int row = column + 1; row < k; row++)
                if (Math.abs(system[row][column]) > Math.abs(system[pivot][column]))
                    pivot = row;
            double[] swap = system[column];
            system[column] = system[pivot];
            system[pivot] = swap;
            double scale = system[column][column];
            for (int c = column; c <= k; c++)
                system[column][c] /= scale;
            for (int row = 0; row < k; row++)
                if (row != column) {
                    double value = system[row][column];
                    for (int c = column; c <= k; c++)
                        system[row][c] -= value * system[column][c];
                }
        }
        double[] result = new double[k];
        for (int i = 0; i < k; i++)
            result[i] = system[i][k];
        return result;
    }
    record Alignment(int[] mapping, int correct) {}
    static void permutations(int[][] matrix, int depth, int[] current, boolean[] used, int[] best,
                             int[] greatest) {
        int k = current.length;
        if (depth == k) {
            int count = 0;
            for (int j = 0; j < k; j++)
                count += matrix[current[j]][j];
            if (count > greatest[0]) {
                greatest[0] = count;
                System.arraycopy(current, 0, best, 0, k);
            }
            return;
        }
        for (int i = 0; i < k; i++)
            if (!used[i]) {
                used[i] = true;
                current[depth] = i;
                permutations(matrix, depth + 1, current, used, best, greatest);
                used[i] = false;
            }
    }
    static Alignment alignment(int m) {
        int k = initial.states.length;
        int[][] matrix = new int[k][k];
        for (int r = 0; r < train.size(); r++)
            Evaluation.accumulate(matrix, train.get(r).truth(), trainDecoded[m][r].viterbi().states());
        int[] best = new int[k], greatest = {-1};
        permutations(matrix, 0, new int[k], new boolean[k], best, greatest);
        return new Alignment(best, greatest[0]);
    }
    static List<String> report() {
        List<String> out = new ArrayList<>();
        out.add("INPUT");
        int total = positions(sequences), missing = missing(sequences), observed = total - missing;
        out.add("SEQUENCES accepted " + sequences.size() + " rejected " + sequenceRejected + " positions " +
                total + " missing " + missing);
        out.add("LABELED train " + train.size() + " test " + test.size() + " rejected " + labeledRejected +
                " positions " + (positions(train) + positions(test)) + " missing " +
                (missing(train) + missing(test)));
        out.addAll(rejections);
        int[] symbols = new int[initial.symbols.length];
        for (Sequence record : sequences)
            for (int symbol : record.observations())
                if (symbol >= 0)
                    symbols[symbol]++;
        String composition = "COMPOSITION";
        for (int c = 0; c < symbols.length; c++)
            composition += " " + initial.symbols[c] + " " + f((double)symbols[c] / observed);
        out.add(composition);
        truthStatistics(out, "TRAIN", train);
        truthStatistics(out, "TEST", test);
        int violations = 0;
        for (BwRecord row : bwTrace)
            if (row.violation())
                violations++;
        block(out, "TRAINING BAUM_WELCH iterations " + integer("iterations") + " initial_loglik " +
                       f(bwTrace.getFirst().loglik()) + " final_loglik " + f(bwTrace.getLast().loglik()) +
                       " violations " + violations + " best_heldout_iteration " + bestHeldout);
        out.add("TRAINING VITERBI_TRAINING iterations " + vtIterations + " converged " +
                (vtConverged ? "yes" : "no"));
        out.add("TRAINING SUPERVISED smoothing " + selected.candidate);
        int[] preference = new int[4];
        for (int r = 0; r < sequences.size(); r++) {
            int best = 0;
            for (int m = 1; m < 4; m++)
                if (unlabeledDecoded[m][r].fb().loglik() > unlabeledDecoded[best][r].fb().loglik())
                    best = m;
            preference[best]++;
        }
        String line = "PREFERENCE";
        for (int m = 0; m < 4; m++)
            line += " " + models[m].name + " " + preference[m];
        out.add(line);
        for (int a = 0; a < 4; a++)
            for (int b = a + 1; b < 4; b++) {
                int correct = 0;
                for (int r = 0; r < sequences.size(); r++)
                    correct += Evaluation.correct(unlabeledDecoded[a][r].viterbi().states(),
                                                  unlabeledDecoded[b][r].viterbi().states());
                out.add("AGREEMENT " + models[a].name + " " + models[b].name + " " +
                        Evaluation.fraction(correct, total));
            }
        for (int decoder = 0; decoder < 2; decoder++) {
            int best = 0;
            for (int m = 1; m < 4; m++)
                if (testCorrect[m][decoder] > testCorrect[best][decoder])
                    best = m;
            out.add("BEST " + (decoder == 0 ? "VITERBI" : "POSTERIOR") + " " + models[best].name +
                    " accuracy " + Evaluation.fraction(testCorrect[best][decoder], positions(test)));
        }
        for (int m = 0; m < 4; m++) {
            ModelIo.Model model = models[m];
            block(out, "MODEL " + model.name);
            double loglik = 0, testLoglik = 0;
            List<int[]> paths = new ArrayList<>();
            int count = 0, length = 0, islands = 0;
            for (int r = 0; r < sequences.size(); r++) {
                Inference.Decoding decoding = unlabeledDecoded[m][r];
                loglik += decoding.fb().loglik();
                int[] path = decoding.viterbi().states();
                paths.add(path);
                for (Evaluation.Interval segment : segments(path)) {
                    count++;
                    length += segment.length();
                    if (composition(sequences.get(r).observations(), segment).island())
                        islands++;
                }
            }
            for (int r = 0; r < test.size(); r++)
                testLoglik += testDecoded[m][r].fb().loglik();
            out.add("LOGLIK unlabeled " + f(loglik) + " per_symbol " + f(loglik / observed) + " test " +
                    f(testLoglik));
            out.add("SEGMENTS count " + count + " mean_length " +
                    f(count == 0 ? Double.NaN : (double)length / count) + " islands " + islands);
            Alignment alignment = alignment(m);
            line = "ALIGNMENT";
            for (int i = 0; i < initial.states.length; i++)
                line += " " + initial.states[i] + "=" + initial.states[alignment.mapping()[i]];
            out.add(line + " agreement " + Evaluation.fraction(alignment.correct(), positions(train)));
            Statistics stats = statistics(paths);
            double[] stationary = stationary(model);
            for (int i = 0; i < initial.states.length; i++)
                out.add("STATE " + initial.states[i] + " stationary " + f(stationary[i]) + " duration " +
                        f(1 / (1 - model.a[i][i])) + " occupancy " +
                        f((double)stats.counts()[i] / stats.positions()) + " mean_run " +
                        f(stats.runs()[i] == 0 ? Double.NaN : (double)stats.counts()[i] / stats.runs()[i]));
        }
        return out;
    }
    public static void main(String[] args) throws IOException {
        ModelIo.Data data = ModelIo.read();
        initial = data.model();
        params = data.params();
        models[0] = initial;
        segmentState = index(initial.states, word("segment_state").charAt(0));
        validate(data);
        baumWelch();
        viterbiTraining();
        supervised();
        unlabeledDecoded = decode(sequences);
        testDecoded = decode(test);
        trainDecoded = decode(train);
        List<String> evaluation = evaluationReport();
        annotate();
        List<String> trained = new ArrayList<>();
        for (int m = 1; m < 4; m++) {
            if (!trained.isEmpty())
                trained.add("");
            trained.addAll(ModelIo.format(models[m]));
        }
        ModelIo.write("trained_model.txt", trained);
        ModelIo.write("loglik_trace.csv", baumTraceReport());
        ModelIo.write("viterbi_trace.csv", viterbiTraceReport());
        ModelIo.write("decodings.txt", decodingLines);
        ModelIo.write("segments.csv", segmentLines);
        ModelIo.write("samples.txt", samples());
        ModelIo.write("evaluation.txt", evaluation);
        ModelIo.write("report.txt", report());
    }
}
