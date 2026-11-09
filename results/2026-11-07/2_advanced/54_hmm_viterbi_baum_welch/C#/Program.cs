using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Program {
    public record Sequence(string name, string role, int[] observations, int[] truth) {
    }
    public record BwRecord(double loglik, double heldout, double maximum, bool violation) {
    }
    public record VtRecord(double logprob, double loglik, int changed) {
    }
    public record Composition(double rich, double motif, bool island) {
    }
    public sealed class Cv {
        public string candidate;
        public int correct, positions;
        public int[] foldCorrect, foldPositions, foldRecords;
        public int[][] matrix;
    }
    public static ModelIo.Model initial;
    public static ModelIo.Model[] models = new ModelIo.Model[4];
    public static Dictionary<string, string[]> settings;
    public static List<Sequence> sequences = new(), train = new(), test = new();
    public static List<string> rejections = new();
    public static int sequenceRejected, labeledRejected, segmentState, bestHeldout, vtIterations;
    public static bool vtConverged;
    public static List<BwRecord> bwTrace = new();
    public static List<VtRecord> vtTrace = new();
    public static List<Cv> candidates = new();
    public static Cv selected;
    public static Inference.Decoding[][] unlabeledDecoded, testDecoded, trainDecoded;
    public static int[][] testCorrect = Enumerable.Range(0, 4)
                                            .Select(
                                                _ => new int[2])
                                            .ToArray();
    public static List<string> decodingLines = new(), segmentLines = new();
    public static int Integer(string key) {
        return int.Parse(settings[key][0]);
    }
    public static double Number(string key) {
        return double.Parse(settings[key][0]);
    }
    public static string Word(string key) {
        return settings[key][0];
    }
    public static string F(double value) {
        return ModelIo.F(value);
    }
    public static int Index(char[] values, char c) {
        for (int i = 0; i < values.Length; i++)
            if (values[i] == c)
                return i;
        return -1;
    }
    public static string ObservationError(string observed) {
        for (int t = 0; t < observed.Length; t++) {
            char c = observed[t];
            if (Index(initial.symbols, c) < 0 && c != initial.missing)
                return "invalid symbol " + c + " at position " + (t + 1);
        }
        return null;
    }
    public static string LengthError(string observed) {
        if (observed.Length < Integer("min_sequence_length"))
            return "too short " + observed.Length;
        int missing = 0;
        for (int i = 0; i < observed.Length; i++)
            if (observed[i] == initial.missing)
                missing++;
        return 100 * missing > Integer("max_missing_percent") * observed.Length
                   ? "too many missing " + missing
                   : null;
    }
    public static int[] Observations(string text) {
        int[] result = new int[text.Length];
        for (int i = 0; i < text.Length; i++)
            result[i] = Index(initial.symbols, text[i]);
        return result;
    }
    public static void Validate(ModelIo.Data input) {
        HashSet<string> seen = new();
        for (int i = 0; i < input.sequences.Count; i++) {
            string[] words = input.sequences[i].Split(' ');
            string name = words[0], observed = words[1].ToUpperInvariant();
            string error = !seen.Add(name) ? "duplicate name" : ObservationError(observed);
            if (error == null)
                error = LengthError(observed);
            if (error != null) {
                sequenceRejected++;
                rejections.Add("REJECT sequences.txt line " + (i + 1) + " " + name + " " + error);
            } else
                sequences.Add(new Sequence(name, "", Observations(observed), null));
        }
        seen.Clear();
        for (int i = 0; i < input.labeled.Count; i += 2) {
            string[] words = input.labeled[i].Split(' ');
            string name = words[0], role = words[1], observed = words[2].ToUpperInvariant(),
                   labels = input.labeled[i + 1];
            string error = !seen.Add(name) ? "duplicate name" : ObservationError(observed);
            if (error == null)
                for (int t = 0; t < labels.Length; t++)
                    if (Index(initial.states, labels[t]) < 0) {
                        error = "invalid label " + labels[t] + " at position " + (t + 1);
                        break;
                    }
            if (error == null && observed.Length != labels.Length)
                error = "length mismatch " + observed.Length + " " + labels.Length;
            if (error == null)
                error = LengthError(observed);
            if (error != null) {
                labeledRejected++;
                rejections.Add("REJECT labeled.txt line " + (i + 1) + " " + name + " " + error);
            } else {
                int[] truth = new int[labels.Length];
                for (int t = 0; t < truth.Length; t++)
                    truth[t] = Index(initial.states, labels[t]);
                Sequence record = new Sequence(name, role, Observations(observed), truth);
                (role.Equals("TRAIN") ? train : test).Add(record);
            }
        }
    }
    public static List<int[]> Observed(List<Sequence> records) {
        List<int[]> result = new();
        foreach (Sequence record in records)
            result.Add(record.observations);
        return result;
    }
    public static List<Training.Pair> Pairs(List<Sequence> records) {
        List<Training.Pair> result = new();
        foreach (Sequence record in records)
            result.Add(new Training.Pair(record.observations, record.truth));
        return result;
    }
    public static double MaximumChange(ModelIo.Model a, ModelIo.Model b) {
        double maximum = 0;
        for (int i = 0; i < a.states.Length; i++) {
            maximum = Math.Max(maximum, Math.Abs(a.pi[i] - b.pi[i]));
            for (int j = 0; j < a.states.Length; j++)
                maximum = Math.Max(maximum, Math.Abs(a.a[i][j] - b.a[i][j]));
            for (int c = 0; c < a.symbols.Length; c++)
                maximum = Math.Max(maximum, Math.Abs(a.b[i][c] - b.b[i][c]));
        }
        return maximum;
    }
    public static void BaumWelch() {
        List<int[]> data = Observed(sequences), heldout = Observed(train);
        heldout.AddRange(Observed(test));
        ModelIo.Model model = initial;
        bwTrace.Add(new BwRecord(Training.Loglik(model, data), Training.Loglik(model, heldout), 0, false));
        bestHeldout = 0;
        for (int t = 1; t <= Integer("iterations"); t++) {
            ModelIo.Model next = Training.BaumWelch(model, data, Number("pseudocount"));
            double loglik = Training.Loglik(next, data), held = Training.Loglik(next, heldout),
                   previous = bwTrace[^1].loglik;
            bwTrace.Add(new BwRecord(loglik, held, MaximumChange(model, next),
                                     loglik < previous - 0.000001 * Math.Abs(previous)));
            if (held > bwTrace[bestHeldout].heldout)
                bestHeldout = t;
            model = next;
        }
        models[1] = model;
    }
    public static List<int[]> ViterbiPaths(ModelIo.Model model) {
        List<int[]> paths = new();
        foreach (Sequence record in sequences)
            paths.Add(Inference.Viterbi(model, record.observations).states);
        return paths;
    }
    public static VtRecord ViterbiRecord(ModelIo.Model model, int changed) {
        double logprob = 0;
        foreach (Sequence record in sequences)
            logprob += Inference.Viterbi(model, record.observations).logprob;
        return new VtRecord(logprob, Training.Loglik(model, Observed(sequences)), changed);
    }
    public static void ViterbiTraining() {
        ModelIo.Model model = initial;
        List<int[]> paths = ViterbiPaths(model);
        vtTrace.Add(ViterbiRecord(model, -1));
        for (int t = 1; t <= Integer("iterations"); t++) {
            List<Training.Pair> pairs = new();
            for (int i = 0; i < sequences.Count; i++)
                pairs.Add(new Training.Pair(sequences[i].observations, paths[i]));
            model = Training.Count(initial, pairs, Number("pseudocount"), "VITERBI_TRAINING");
            List<int[]> next = ViterbiPaths(model);
            int changes = 0;
            for (int i = 0; i < paths.Count; i++)
                changes += paths[i].Length - Evaluation.Correct(paths[i], next[i]);
            vtTrace.Add(ViterbiRecord(model, changes));
            paths = next;
            vtIterations = t;
            if (changes == 0) {
                vtConverged = true;
                break;
            }
        }
        models[2] = model;
    }
    public static void Supervised() {
        int folds = Integer("folds"), k = initial.states.Length;
        foreach (string candidate in settings["smoothing"]) {
            Cv cv = new Cv();
            cv.candidate = candidate;
            cv.foldCorrect = new int[folds];
            cv.foldPositions = new int[folds];
            cv.foldRecords = new int[folds];
            cv.matrix = Enumerable.Range(0, k)
                            .Select(
                                _ => new int[k])
                            .ToArray();
            for (int fold = 0; fold < folds; fold++) {
                List<Sequence> training = new(), validation = new();
                for (int i = 0; i < train.Count; i++)
                    (i % folds == fold ? validation : training).Add(train[i]);
                ModelIo.Model model =
                    Training.Count(initial, Pairs(training), double.Parse(candidate), "SUPERVISED");
                foreach (Sequence record in validation) {
                    int[] path = Inference.Viterbi(model, record.observations).states;
                    int correct = Evaluation.Correct(record.truth, path);
                    cv.foldRecords[fold]++;
                    cv.foldPositions[fold] += path.Length;
                    cv.foldCorrect[fold] += correct;
                    cv.positions += path.Length;
                    cv.correct += correct;
                    Evaluation.Accumulate(cv.matrix, record.truth, path);
                }
            }
            candidates.Add(cv);
            if (selected == null || cv.correct > selected.correct)
                selected = cv;
        }
        models[3] = Training.Count(initial, Pairs(train), double.Parse(selected.candidate), "SUPERVISED");
    }
    public static Inference.Decoding[][] Decode(List<Sequence> records) {
        Inference.Decoding[][] result = Enumerable.Range(0, 4)
                                            .Select(
                                                _ => new Inference.Decoding[records.Count])
                                            .ToArray();
        for (int m = 0; m < 4; m++)
            for (int i = 0; i < records.Count; i++)
                result[m][i] = Inference.Decode(models[m], records[i].observations);
        return result;
    }
    public static List<Evaluation.Interval> Segments(int[] path) {
        List<Evaluation.Interval> result = new();
        foreach (Evaluation.Run run in Evaluation.Runs(path))
            if (run.state == segmentState) {
                if (result.Count != 0 && run.start - result[^1].end - 1 <= Integer("merge_gap")) {
                    Evaluation.Interval last = result[^1];
                    result.RemoveAt(result.Count - 1);
                    result.Add(new Evaluation.Interval(last.start, run.end));
                } else
                    result.Add(new Evaluation.Interval(run.start, run.end));
            }
        result.RemoveAll(interval => interval.Length() < Integer("min_segment_length"));
        return result;
    }
    public static List<Evaluation.Interval> TruthRegions(int[] path) {
        List<Evaluation.Interval> result = new();
        foreach (Evaluation.Run run in Evaluation.Runs(path))
            if (run.state == segmentState)
                result.Add(new Evaluation.Interval(run.start, run.end));
        return result;
    }
    public static Composition JudgeComposition(int[] observations, Evaluation.Interval segment) {
        int n = 0, r = 0, q = 0, k1 = 0, k2 = 0;
        int first = Index(initial.symbols, settings["motif"][0][0]),
            second = Index(initial.symbols, settings["motif"][1][0]);
        HashSet<int> rich = new();
        foreach (string symbol in settings["rich_symbols"])
            rich.Add(Index(initial.symbols, symbol[0]));
        for (int t = segment.start - 1; t < segment.end; t++) {
            int value = observations[t];
            if (value < 0)
                continue;
            n++;
            if (rich.Contains(value))
                r++;
            if (value == first)
                k1++;
            if (value == second)
                k2++;
            if (t + 1 < segment.end && value == first && observations[t + 1] == second)
                q++;
        }
        bool island = k1 * k2 > 0 && 100 * r >= Integer("min_rich_percent") * n &&
                      100 * q * n >= Integer("min_motif_percent") * k1 * k2;
        return new Composition(n == 0 ? double.NaN : (double)r / n,
                               k1 * k2 == 0 ? double.NaN : (double)(q * n) / (k1 * k2), island);
    }
    public static int[] Path(Inference.Decoding decoding, int decoder) {
        return decoder == 0 ? decoding.viterbi.states : decoding.posterior;
    }
    public static string States(int[] path) {
        StringBuilder text = new StringBuilder();
        foreach (int state in path)
            text.Append(initial.states[state]);
        return text.ToString();
    }
    public static string Symbols(int[] observations) {
        StringBuilder text = new StringBuilder();
        foreach (int symbol in observations)
            text.Append(initial.symbols[symbol]);
        return text.ToString();
    }
    public static int Positions(List<Sequence> records) {
        int total = 0;
        foreach (Sequence record in records)
            total += record.observations.Length;
        return total;
    }
    public static int Missing(List<Sequence> records) {
        int total = 0;
        foreach (Sequence record in records)
            foreach (int symbol in record.observations)
                if (symbol < 0)
                    total++;
        return total;
    }
    public static void Block(List<string> output, string heading) {
        if (output.Count != 0)
            output.Add("");
        output.Add(heading);
    }

    public static List<string> EvaluationReport() {
        List<string> output = new();
        int k = initial.states.Length;
        for (int m = 0; m < 4; m++)
            for (int decoder = 0; decoder < 2; decoder++) {
                Block(output,
                      "EVALUATION " + models[m].name + " " + (decoder == 0 ? "VITERBI" : "POSTERIOR"));
                int[][] matrix = Enumerable.Range(0, k)
                                     .Select(
                                         _ => new int[k])
                                     .ToArray();
                int[] regions = new int[4], boundaries = new int[4], bins = new int[10],
                      binCorrect = new int[10], recordCorrect = new int[test.Count];
                for (int r = 0; r < test.Count; r++) {
                    Sequence record = test[r];
                    Inference.Decoding decoding = testDecoded[m][r];
                    int[] prediction = Path(decoding, decoder);
                    recordCorrect[r] = Evaluation.Correct(record.truth, prediction);
                    testCorrect[m][decoder] += recordCorrect[r];
                    Evaluation.Accumulate(matrix, record.truth, prediction);
                    int[] rc = Evaluation.Regions(Segments(prediction), TruthRegions(record.truth)),
                          bc = Evaluation.BoundaryMatches(prediction, record.truth,
                                                          Integer("boundary_tolerance"));
                    for (int j = 0; j < 4; j++) {
                        regions[j] += rc[j];
                        boundaries[j] += bc[j];
                    }
                    if (decoder == 1)
                        for (int t = 0; t < prediction.Length; t++) {
                            int bin = Math.Min(9, (int)Math.Floor(10 * decoding.confidence[t]));
                            bins[bin]++;
                            if (prediction[t] == record.truth[t])
                                binCorrect[bin]++;
                        }
                }
                output.AddRange(Evaluation.Matrix(initial.states, matrix));
                output.AddRange(Evaluation.Metrics(initial.states, matrix));
                output.Add("REGIONS " + initial.states[segmentState] + " predicted " + regions[0] + " true " +
                           regions[1] + " precision " + Evaluation.Fraction(regions[2], regions[0]) +
                           " recall " + Evaluation.Fraction(regions[3], regions[1]));
                output.Add("BOUNDARIES predicted " + boundaries[0] + " true " + boundaries[1] +
                           " precision " + Evaluation.Fraction(boundaries[2], boundaries[0]) + " recall " +
                           Evaluation.Fraction(boundaries[3], boundaries[1]));
                if (decoder == 1)
                    for (int bin = 0; bin < 10; bin++)
                        if (bins[bin] > 0)
                            output.Add("CALIBRATION 0." + bin + "-" + (bin == 9 ? "1.0" : "0." + (bin + 1)) +
                                       " positions " + bins[bin] + " correct " + binCorrect[bin] +
                                       " accuracy " + Evaluation.Fraction(binCorrect[bin], bins[bin]));
                for (int r = 0; r < test.Count; r++)
                    output.Add("RECORD " + test[r].name + " length " + test[r].observations.Length +
                               " correct " + recordCorrect[r]);
            }
        int folds = Integer("folds");
        Block(output, "CROSS_VALIDATION folds " + folds);
        foreach (Cv candidate in candidates)
            output.Add("SMOOTHING " + candidate.candidate + " positions " + candidate.positions +
                       " correct " + candidate.correct + " accuracy " +
                       Evaluation.Fraction(candidate.correct, candidate.positions));
        output.Add("SELECTED " + selected.candidate);
        for (int fold = 0; fold < folds; fold++)
            output.Add("FOLD " + (fold + 1) + " records " + selected.foldRecords[fold] + " positions " +
                       selected.foldPositions[fold] + " correct " + selected.foldCorrect[fold] +
                       " accuracy " +
                       Evaluation.Fraction(selected.foldCorrect[fold], selected.foldPositions[fold]));
        output.AddRange(Evaluation.Matrix(initial.states, selected.matrix));
        output.AddRange(Evaluation.Metrics(initial.states, selected.matrix));
        Block(output, "LEARNING_CURVE");
        for (int count = 1; count <= train.Count; count++) {
            ModelIo.Model model = Training.Count(initial, Pairs(train.GetRange(0, count - (0))),
                                                 double.Parse(selected.candidate), "SUPERVISED");
            int correct = 0;
            foreach (Sequence record in test)
                correct +=
                    Evaluation.Correct(record.truth, Inference.Viterbi(model, record.observations).states);
            output.Add("RECORDS " + count + " correct " + correct + " accuracy " +
                       Evaluation.Fraction(correct, Positions(test)));
        }
        return output;
    }
    public static void Annotate() {
        segmentLines.Add(
            "sequence,decoder,start,end,length,mean_posterior,support,rich_fraction,motif_ratio,island");
        Sampler.Random random = new Sampler.Random(Integer("posterior_seed"));
        int samples = Integer("posterior_samples");
        ModelIo.Model model = models[1];
        for (int r = 0; r < sequences.Count; r++) {
            Sequence record = sequences[r];
            Inference.Decoding decoding = unlabeledDecoded[1][r];
            List<int[]> paths = new();
            int segmentTotal = 0;
            for (int sample = 0; sample < samples; sample++) {
                int[] path = Sampler.Posterior(model, decoding.fb.forward, random);
                paths.Add(path);
                segmentTotal += Segments(path).Count;
            }
            int differences = record.observations.Length -
                              Evaluation.Correct(decoding.viterbi.states, decoding.posterior),
                uncertain = 0;
            char[] confident = States(decoding.posterior).ToCharArray(),
                   imputed = new char[record.observations.Length];
            for (int t = 0; t < record.observations.Length; t++) {
                if (decoding.confidence[t] < Number("confidence")) {
                    uncertain++;
                    confident[t] = '.';
                }
                if (record.observations[t] >= 0)
                    imputed[t] = initial.symbols[record.observations[t]];
                else {
                    double[] probabilities = new double[initial.symbols.Length];
                    for (int c = 0; c < probabilities.Length; c++)
                        for (int i = 0; i < initial.states.Length; i++)
                            probabilities[c] += decoding.fb.gamma[t][i] * model.b[i][c];
                    imputed[t] = char.ToLowerInvariant(initial.symbols[Inference.Maximum(probabilities)]);
                }
            }
            decodingLines.Add("SEQUENCE " + record.name + " length " + record.observations.Length +
                              " loglik " + F(decoding.fb.loglik) + " viterbi " + F(decoding.viterbi.logprob) +
                              " differences " + differences + " uncertain " + uncertain +
                              " expected_segments " + F((double)segmentTotal / samples));
            decodingLines.Add("VITERBI " + States(decoding.viterbi.states));
            decodingLines.Add("POSTERIOR " + States(decoding.posterior));
            decodingLines.Add("CONFIDENT " + new string(confident));
            decodingLines.Add("IMPUTED " + new string(imputed));
            for (int decoder = 0; decoder < 2; decoder++)
                foreach (Evaluation.Interval segment in Segments(Path(decoding, decoder))) {
                    double sum = 0;
                    for (int t = segment.start - 1; t < segment.end; t++)
                        sum += decoding.fb.gamma[t][segmentState];
                    int support = 0;
                    foreach (int[] sample in paths) {
                        int count = 0;
                        for (int t = segment.start - 1; t < segment.end; t++)
                            if (sample[t] == segmentState)
                                count++;
                        if (2 * count > segment.Length())
                            support++;
                    }
                    Composition composition = JudgeComposition(record.observations, segment);
                    segmentLines.Add(record.name + "," + (decoder == 0 ? "viterbi" : "posterior") + "," +
                                     segment.start + "," + segment.end + "," + segment.Length() + "," +
                                     F(sum / segment.Length()) + "," + support + "," + F(composition.rich) +
                                     "," + F(composition.motif) + "," + (composition.island ? "yes" : "no"));
                }
        }
    }
    public static List<string> Samples() {
        List<string> output = new();
        Sampler.Random random = new Sampler.Random(Integer("sample_seed"));
        int viterbiCorrect = 0, posteriorCorrect = 0, total = 0;
        for (int number = 1; number <= Integer("sample_count"); number++) {
            Sampler.Synthetic sample = Sampler.GenerateSynthetic(models[1], Integer("sample_length"), random);
            Inference.Decoding decoding = Inference.Decode(models[1], sample.observations);
            int vc = Evaluation.Correct(sample.states, decoding.viterbi.states),
                pc = Evaluation.Correct(sample.states, decoding.posterior);
            viterbiCorrect += vc;
            posteriorCorrect += pc;
            total += sample.states.Length;
            output.Add("SAMPLE " + number + " loglik " + F(decoding.fb.loglik) + " viterbi " +
                       F(decoding.viterbi.logprob) + " viterbi_correct " + vc + " posterior_correct " + pc);
            output.Add("STATES " + States(sample.states));
            output.Add("SYMBOLS " + Symbols(sample.observations));
            output.Add("VITERBI " + States(decoding.viterbi.states));
            output.Add("POSTERIOR " + States(decoding.posterior));
        }
        output.Add("TOTAL positions " + total + " viterbi_accuracy " +
                   Evaluation.Fraction(viterbiCorrect, total) + " posterior_accuracy " +
                   Evaluation.Fraction(posteriorCorrect, total));
        return output;
    }
    public static List<string> BaumTraceReport() {
        List<string> output = new(["iteration,loglik,heldout,change,max_change,status"]);
        for (int t = 0; t < bwTrace.Count; t++) {
            BwRecord row = bwTrace[t];
            output.Add(t + "," + F(row.loglik) + "," + F(row.heldout) + "," +
                       (t == 0 ? ",,"
                               : F(row.loglik - bwTrace[t - 1].loglik) + "," + ModelIo.Real(row.maximum, 6) +
                                     "," + (row.violation ? "violation" : "ok")));
        }
        return output;
    }
    public static List<string> ViterbiTraceReport() {
        List<string> output = new(["iteration,logprob,loglik,changed"]);
        for (int t = 0; t < vtTrace.Count; t++) {
            VtRecord row = vtTrace[t];
            output.Add(t + "," + F(row.logprob) + "," + F(row.loglik) + "," +
                       (t == 0 ? "" : Convert.ToString(row.changed)));
        }
        return output;
    }

    public record Statistics(int[] counts, int[] runs, int positions) {
    }
    public static Statistics PathStatistics(List<int[]> paths) {
        int k = initial.states.Length;
        int[] counts = new int[k], runs = new int[k];
        int positions = 0;
        foreach (int[] path in paths) {
            positions += path.Length;
            foreach (int state in path)
                counts[state]++;
            foreach (Evaluation.Run run in Evaluation.Runs(path))
                runs[run.state]++;
        }
        return new Statistics(counts, runs, positions);
    }
    public static List<int[]> TruthPaths(List<Sequence> records) {
        List<int[]> paths = new();
        foreach (Sequence record in records)
            paths.Add(record.truth);
        return paths;
    }
    public static void TruthStatistics(List<string> output, string role, List<Sequence> records) {
        Statistics stats = PathStatistics(TruthPaths(records));
        for (int i = 0; i < initial.states.Length; i++)
            output.Add("TRUTH " + role + " " + initial.states[i] + " occupancy " +
                       F((double)stats.counts[i] / stats.positions) + " mean_run " +
                       F(stats.runs[i] == 0 ? double.NaN : (double)stats.counts[i] / stats.runs[i]));
    }
    public static double[] Stationary(ModelIo.Model model) {
        int k = model.states.Length;
        double[][] system = Enumerable.Range(0, k)
                                .Select(
                                    _ => new double[k + 1])
                                .ToArray();
        for (int row = 0; row < k - 1; row++)
            for (int column = 0; column < k; column++)
                system[row][column] = model.a[column][row] - (row == column ? 1 : 0);
        for (int column = 0; column < k; column++)
            system[k - 1][column] = 1;
        system[k - 1][k] = 1;
        for (int column = 0; column < k; column++) {
            int pivot = column;
            for (int row = column + 1; row < k; row++)
                if (Math.Abs(system[row][column]) > Math.Abs(system[pivot][column]))
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
    public record Alignment(int[] mapping, int correct) {
    }
    public static void Permutations(int[][] matrix, int depth, int[] current, bool[] used, int[] best,
                                    int[] greatest) {
        int k = current.Length;
        if (depth == k) {
            int count = 0;
            for (int j = 0; j < k; j++)
                count += matrix[current[j]][j];
            if (count > greatest[0]) {
                greatest[0] = count;
                Array.Copy(current, 0, best, 0, k);
            }
            return;
        }
        for (int i = 0; i < k; i++)
            if (!used[i]) {
                used[i] = true;
                current[depth] = i;
                Permutations(matrix, depth + 1, current, used, best, greatest);
                used[i] = false;
            }
    }
    public static Alignment FindAlignment(int m) {
        int k = initial.states.Length;
        int[][] matrix = Enumerable.Range(0, k)
                             .Select(
                                 _ => new int[k])
                             .ToArray();
        for (int r = 0; r < train.Count; r++)
            Evaluation.Accumulate(matrix, train[r].truth, trainDecoded[m][r].viterbi.states);
        int[] best = new int[k], greatest = { -1 };
        Permutations(matrix, 0, new int[k], new bool[k], best, greatest);
        return new Alignment(best, greatest[0]);
    }
    public static List<string> Report() {
        List<string> output = new();
        output.Add("INPUT");
        int total = Positions(sequences), missing = Missing(sequences), observed = total - missing;
        output.Add("SEQUENCES accepted " + sequences.Count + " rejected " + sequenceRejected + " positions " +
                   total + " missing " + missing);
        output.Add("LABELED train " + train.Count + " test " + test.Count + " rejected " + labeledRejected +
                   " positions " + (Positions(train) + Positions(test)) + " missing " +
                   (Missing(train) + Missing(test)));
        output.AddRange(rejections);
        int[] symbols = new int[initial.symbols.Length];
        foreach (Sequence record in sequences)
            foreach (int symbol in record.observations)
                if (symbol >= 0)
                    symbols[symbol]++;
        string composition = "COMPOSITION";
        for (int c = 0; c < symbols.Length; c++)
            composition += " " + initial.symbols[c] + " " + F((double)symbols[c] / observed);
        output.Add(composition);
        TruthStatistics(output, "TRAIN", train);
        TruthStatistics(output, "TEST", test);
        int violations = 0;
        foreach (BwRecord row in bwTrace)
            if (row.violation)
                violations++;
        Block(output, "TRAINING BAUM_WELCH iterations " + Integer("iterations") + " initial_loglik " +
                          F(bwTrace[0].loglik) + " final_loglik " + F(bwTrace[^1].loglik) + " violations " +
                          violations + " best_heldout_iteration " + bestHeldout);
        output.Add("TRAINING VITERBI_TRAINING iterations " + vtIterations + " converged " +
                   (vtConverged ? "yes" : "no"));
        output.Add("TRAINING SUPERVISED smoothing " + selected.candidate);
        int[] preference = new int[4];
        for (int r = 0; r < sequences.Count; r++) {
            int best = 0;
            for (int m = 1; m < 4; m++)
                if (unlabeledDecoded[m][r].fb.loglik > unlabeledDecoded[best][r].fb.loglik)
                    best = m;
            preference[best]++;
        }
        string line = "PREFERENCE";
        for (int m = 0; m < 4; m++)
            line += " " + models[m].name + " " + preference[m];
        output.Add(line);
        for (int a = 0; a < 4; a++)
            for (int b = a + 1; b < 4; b++) {
                int correct = 0;
                for (int r = 0; r < sequences.Count; r++)
                    correct += Evaluation.Correct(unlabeledDecoded[a][r].viterbi.states,
                                                  unlabeledDecoded[b][r].viterbi.states);
                output.Add("AGREEMENT " + models[a].name + " " + models[b].name + " " +
                           Evaluation.Fraction(correct, total));
            }
        for (int decoder = 0; decoder < 2; decoder++) {
            int best = 0;
            for (int m = 1; m < 4; m++)
                if (testCorrect[m][decoder] > testCorrect[best][decoder])
                    best = m;
            output.Add("BEST " + (decoder == 0 ? "VITERBI" : "POSTERIOR") + " " + models[best].name +
                       " accuracy " + Evaluation.Fraction(testCorrect[best][decoder], Positions(test)));
        }
        for (int m = 0; m < 4; m++) {
            ModelIo.Model model = models[m];
            Block(output, "MODEL " + model.name);
            double loglik = 0, testLoglik = 0;
            List<int[]> paths = new();
            int count = 0, length = 0, islands = 0;
            for (int r = 0; r < sequences.Count; r++) {
                Inference.Decoding decoding = unlabeledDecoded[m][r];
                loglik += decoding.fb.loglik;
                int[] path = decoding.viterbi.states;
                paths.Add(path);
                foreach (Evaluation.Interval segment in Segments(path)) {
                    count++;
                    length += segment.Length();
                    if (JudgeComposition(sequences[r].observations, segment).island)
                        islands++;
                }
            }
            for (int r = 0; r < test.Count; r++)
                testLoglik += testDecoded[m][r].fb.loglik;
            output.Add("LOGLIK unlabeled " + F(loglik) + " per_symbol " + F(loglik / observed) + " test " +
                       F(testLoglik));
            output.Add("SEGMENTS count " + count + " mean_length " +
                       F(count == 0 ? double.NaN : (double)length / count) + " islands " + islands);
            Alignment alignment = FindAlignment(m);
            line = "ALIGNMENT";
            for (int i = 0; i < initial.states.Length; i++)
                line += " " + initial.states[i] + "=" + initial.states[alignment.mapping[i]];
            output.Add(line + " agreement " + Evaluation.Fraction(alignment.correct, Positions(train)));
            Statistics stats = PathStatistics(paths);
            double[] stationary = Stationary(model);
            for (int i = 0; i < initial.states.Length; i++)
                output.Add("STATE " + initial.states[i] + " stationary " + F(stationary[i]) + " duration " +
                           F(1 / (1 - model.a[i][i])) + " occupancy " +
                           F((double)stats.counts[i] / stats.positions) + " mean_run " +
                           F(stats.runs[i] == 0 ? double.NaN : (double)stats.counts[i] / stats.runs[i]));
        }
        return output;
    }
    public static void Main(string[] args) {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        ModelIo.Data data = ModelIo.Read();
        initial = data.model;
        settings = data.settings;
        models[0] = initial;
        segmentState = Index(initial.states, Word("segment_state")[0]);
        Validate(data);
        BaumWelch();
        ViterbiTraining();
        Supervised();
        unlabeledDecoded = Decode(sequences);
        testDecoded = Decode(test);
        trainDecoded = Decode(train);
        List<string> evaluation = EvaluationReport();
        Annotate();
        List<string> trained = new();
        for (int m = 1; m < 4; m++) {
            if (trained.Count != 0)
                trained.Add("");
            trained.AddRange(ModelIo.Format(models[m]));
        }
        ModelIo.Write("trained_model.txt", trained);
        ModelIo.Write("loglik_trace.csv", BaumTraceReport());
        ModelIo.Write("viterbi_trace.csv", ViterbiTraceReport());
        ModelIo.Write("decodings.txt", decodingLines);
        ModelIo.Write("segments.csv", segmentLines);
        ModelIo.Write("samples.txt", Samples());
        ModelIo.Write("evaluation.txt", evaluation);
        ModelIo.Write("report.txt", Report());
    }
}
