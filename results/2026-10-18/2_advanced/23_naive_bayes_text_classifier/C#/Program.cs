using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

static class Program
{
    static readonly string[] Models = { "multinomial", "bernoulli", "complement", "rocchio", "vote" };
    sealed record Document(string Name, int Label, Tokenizer Tokens);
    sealed record FoldSummary(int Training, int Validation, int Candidates, int Vocabulary);
    sealed record CrossRun(int[] Predictions, Evaluation Evaluation, int[] FoldCorrect);
    sealed record Ratio(long Numerator, long Denominator, int Term);

    static string[] Read(string name) => File.ReadAllLines(Path.Combine("input", name), Encoding.ASCII);
    static int Hundredths(string text) { string[] parts = text.Split('.'); return int.Parse(parts[0], CultureInfo.InvariantCulture) * 100 + int.Parse(parts[1], CultureInfo.InvariantCulture); }
    static string HundredthsText(int value) => (value / 100).ToString(CultureInfo.InvariantCulture) + "." + (value % 100).ToString("D2", CultureInfo.InvariantCulture);
    static string Real(double value) => Evaluation.Real(value);
    static string Proportion(long a, long b) => Evaluation.Proportion(a, b);
    static string Csv(params object[] values) => string.Join(",", values.Select(value => Convert.ToString(value, CultureInfo.InvariantCulture)));
    static string Fields(Evaluation evaluation) => Csv(evaluation.Correct, Real(evaluation.MicroF1), Real(evaluation.MacroF1));

    static List<string> JoinParts(List<List<string>> parts)
    {
        var lines = new List<string>();
        foreach (var part in parts) { if (lines.Count > 0) lines.Add(""); lines.AddRange(part); }
        return lines;
    }

    static void SortRatios(List<Ratio> entries) => entries.Sort((first, second) =>
    {
        int comparison = (second.Numerator * first.Denominator).CompareTo(first.Numerator * second.Denominator);
        return comparison != 0 ? comparison : first.Term.CompareTo(second.Term);
    });

    sealed class Settings
    {
        public int[] Alphas, Curve, Sizes, Thresholds, Lengths;
        public int MinDf, Features, Top, Iterations, Weight, Resamples;
        public long Seed;
        public bool Bigrams;

        public Settings(string[] lines)
        {
            var values = lines.Select(line => line.Split(' ')).ToDictionary(parts => parts[0], parts => parts.Skip(1).ToArray(), StringComparer.Ordinal);
            Alphas = values["ALPHAS"].Select(Hundredths).ToArray();
            MinDf = int.Parse(values["MIN_DF"][0], CultureInfo.InvariantCulture);
            Features = int.Parse(values["FEATURES"][0], CultureInfo.InvariantCulture);
            Bigrams = values["BIGRAMS"][0] == "yes";
            Top = int.Parse(values["TOP"][0], CultureInfo.InvariantCulture);
            Curve = values["CURVE"].Select(text => int.Parse(text, CultureInfo.InvariantCulture)).ToArray();
            Sizes = values["SIZES"].Select(text => int.Parse(text, CultureInfo.InvariantCulture)).ToArray();
            Thresholds = values["THRESHOLDS"].Select(Hundredths).ToArray();
            Lengths = values["LENGTHS"].Select(text => int.Parse(text, CultureInfo.InvariantCulture)).ToArray();
            Iterations = int.Parse(values["EM_ITERATIONS"][0], CultureInfo.InvariantCulture);
            Weight = Hundredths(values["EM_WEIGHT"][0]);
            Resamples = int.Parse(values["BOOTSTRAP"][0], CultureInfo.InvariantCulture);
            Seed = long.Parse(values["BOOTSTRAP"][1], CultureInfo.InvariantCulture);
        }
    }

    sealed class Training
    {
        readonly bool bigrams;
        public Vocabulary Vocabulary { get; }
        public TrainingCounts Counts { get; }
        public Rocchio Rocchio { get; }
        public NaiveBayes[] Models { get; } = new NaiveBayes[3];

        public Training(List<Document> documents, bool bigrams, int classes, int minDf, int size)
        {
            this.bigrams = bigrams;
            var sequences = documents.Select(document => document.Tokens.Terms(bigrams)).ToList();
            int[] labels = documents.Select(document => document.Label).ToArray();
            Vocabulary = new Vocabulary(sequences, labels, classes, minDf, size);
            var encoded = sequences.Select(Vocabulary.Encode).ToList();
            Counts = new TrainingCounts(encoded, labels, classes, Vocabulary.Size);
            Rocchio = new Rocchio(encoded, labels, classes, Vocabulary.Frequencies);
        }

        public void Train(int[] alphas) { for (int model = 0; model < 3; model++) Models[model] = NaiveBayes.Train(model, Counts, alphas[model]); }
        public int[] Encode(Document document) => Vocabulary.Encode(document.Tokens.Terms(bigrams));
        public Prediction Classify(int model, int[] sequence) => model == 3 ? Rocchio.Predict(sequence) : Models[model].Predict(sequence);
    }

    sealed class Experiment
    {
        readonly Settings settings;
        readonly string[] classes;
        readonly int classCount;
        readonly List<Document> training = new();
        readonly List<Document> tests = new();
        readonly List<Document> unlabelled = new();
        readonly int[] labelled;
        readonly int[] truths;
        readonly List<FoldSummary> folds = new();
        readonly CrossRun[][] cvRuns = new CrossRun[4][];
        readonly CrossRun[] selectedRuns = new CrossRun[4];
        readonly int[] selected = new int[3];
        Training finalTraining = null!;
        int[][] testSequences = null!;
        Prediction[][] predictions = null!;
        bool[][] correct = null!;

        public Experiment()
        {
            settings = new Settings(Read("params.txt"));
            var stopwords = new HashSet<string>(Read("stopwords.txt"), StringComparer.Ordinal);
            var rows = Read("train.txt").Select(line => line.Split('\t', 2)).ToArray();
            classes = rows.Select(row => row[0]).Distinct(StringComparer.Ordinal).OrderBy(name => name, StringComparer.Ordinal).ToArray();
            classCount = classes.Length;
            var positions = classes.Select((name, index) => (name, index)).ToDictionary(pair => pair.name, pair => pair.index, StringComparer.Ordinal);
            for (int i = 0; i < rows.Length; i++) training.Add(new Document((i + 1).ToString(CultureInfo.InvariantCulture), positions[rows[i][0]], new Tokenizer(rows[i][1], stopwords)));
            foreach (string line in Read("test.txt"))
            {
                string[] row = line.Split('\t', 3);
                tests.Add(new Document(row[0], row[1] == "?" ? -1 : positions[row[1]], new Tokenizer(row[2], stopwords)));
            }
            foreach (string text in Read("unlabelled.txt")) unlabelled.Add(new Document((unlabelled.Count + 1).ToString(CultureInfo.InvariantCulture), -1, new Tokenizer(text, stopwords)));
            labelled = Enumerable.Range(0, tests.Count).Where(i => tests[i].Label >= 0).ToArray();
            truths = labelled.Select(i => tests[i].Label).ToArray();
        }

        public void Run()
        {
            CrossValidate();
            for (int model = 0; model < 3; model++)
            {
                int best = 0;
                for (int i = 1; i < settings.Alphas.Length; i++) if (Evaluation.Rounded(cvRuns[model][i].Evaluation.MacroF1) > Evaluation.Rounded(cvRuns[model][best].Evaluation.MacroF1)) best = i;
                selected[model] = settings.Alphas[best];
                selectedRuns[model] = cvRuns[model][best];
            }
            selectedRuns[3] = cvRuns[3][0];
            finalTraining = Trained(training, settings.Bigrams, settings.Features);
            testSequences = tests.Select(finalTraining.Encode).ToArray();
            predictions = Enumerable.Range(0, 5).Select(_ => new Prediction[tests.Count]).ToArray();
            for (int model = 0; model < 4; model++) for (int i = 0; i < tests.Count; i++) predictions[model][i] = finalTraining.Classify(model, testSequences[i]);
            for (int i = 0; i < tests.Count; i++)
            {
                int[] votes = new int[classCount];
                for (int model = 0; model < 4; model++) votes[predictions[model][i].Label]++;
                int winner = predictions[0][i].Label;
                for (int model = 0; model < 4; model++) { int c = predictions[model][i].Label; if (votes[c] > votes[winner]) winner = c; }
                predictions[4][i] = new Prediction(winner, votes[winner] / 4.0);
            }
            correct = Enumerable.Range(0, 5).Select(_ => new bool[labelled.Length]).ToArray();
            for (int model = 0; model < 5; model++) for (int i = 0; i < labelled.Length; i++) correct[model][i] = predictions[model][labelled[i]].Label == truths[i];
        }

        Training Trained(List<Document> documents, bool bigrams, int size)
        {
            var result = new Training(documents, bigrams, classCount, settings.MinDf, size);
            result.Train(selected);
            return result;
        }

        string AlphaText(int model) => model < 3 ? HundredthsText(selected[model]) : "-";

        CrossRun MakeCrossRun(int[] predicted)
        {
            int[] trueLabels = training.Select(document => document.Label).ToArray();
            int[] hits = new int[5];
            for (int i = 0; i < predicted.Length; i++) if (predicted[i] == trueLabels[i]) hits[i % 5]++;
            return new CrossRun(predicted, new Evaluation(classCount, trueLabels, predicted), hits);
        }

        void CrossValidate()
        {
            int count = training.Count;
            int[][][] nb = Enumerable.Range(0, 3).Select(model => settings.Alphas.Select(alpha => new int[count]).ToArray()).ToArray();
            int[] rocchio = new int[count];
            for (int fold = 0; fold < 5; fold++)
            {
                var members = new List<Document>();
                var held = new List<int>();
                for (int i = 0; i < count; i++) { if (i % 5 == fold) held.Add(i); else members.Add(training[i]); }
                var fit = new Training(members, settings.Bigrams, classCount, settings.MinDf, settings.Features);
                folds.Add(new FoldSummary(members.Count, held.Count, fit.Vocabulary.CandidateCount, fit.Vocabulary.Size));
                var sequences = held.Select(i => fit.Encode(training[i])).ToArray();
                for (int model = 0; model < 3; model++) for (int a = 0; a < settings.Alphas.Length; a++)
                {
                    var classifier = NaiveBayes.Train(model, fit.Counts, settings.Alphas[a]);
                    for (int i = 0; i < held.Count; i++) nb[model][a][held[i]] = classifier.Predict(sequences[i]).Label;
                }
                for (int i = 0; i < held.Count; i++) rocchio[held[i]] = fit.Rocchio.Predict(sequences[i]).Label;
            }
            for (int model = 0; model < 3; model++) cvRuns[model] = nb[model].Select(MakeCrossRun).ToArray();
            cvRuns[3] = new[] { MakeCrossRun(rocchio) };
        }

        Evaluation[] TestEvaluations(Training fit)
        {
            int[][] sequences = labelled.Select(i => fit.Encode(tests[i])).ToArray();
            var results = new Evaluation[4];
            for (int model = 0; model < 4; model++)
            {
                int[] predicted = sequences.Select(sequence => fit.Classify(model, sequence).Label).ToArray();
                results[model] = new Evaluation(classCount, truths, predicted);
            }
            return results;
        }

        List<string> VocabularyLines()
        {
            var vocabulary = finalTraining.Vocabulary;
            var lines = new List<string> { $"documents {training.Count} terms {vocabulary.TermCount} candidates {vocabulary.CandidateCount} vocabulary {vocabulary.Size}" };
            for (int i = 0; i < vocabulary.Ranking.Count; i++)
            {
                var entry = vocabulary.Ranking[i];
                lines.Add($"{i + 1} {entry.Term} {entry.Frequency} {Real(entry.Score)} {classes[entry.BestClass]}");
            }
            return lines;
        }

        List<string> CvLines()
        {
            var lines = new List<string> { "model,alpha,correct,accuracy,macro_f1,selected" };
            for (int model = 0; model < 3; model++) for (int a = 0; a < settings.Alphas.Length; a++) lines.Add($"{Models[model]},{HundredthsText(settings.Alphas[a])},{Fields(cvRuns[model][a].Evaluation)},{(selected[model] == settings.Alphas[a] ? "yes" : "no")}");
            lines.Add("rocchio,-," + Fields(cvRuns[3][0].Evaluation) + ",yes");
            return lines;
        }

        List<string> PredictionLines()
        {
            var lines = new List<string> { "id,model,label,score" };
            for (int i = 0; i < tests.Count; i++) for (int model = 0; model < 5; model++) lines.Add(Csv(tests[i].Name, Models[model], classes[predictions[model][i].Label], Real(predictions[model][i].Score)));
            return lines;
        }

        List<string> CurveLines()
        {
            var lines = new List<string> { "size,vocabulary,model,correct,accuracy,macro_f1" };
            foreach (int size in settings.Curve)
            {
                Training fit = Trained(training.Take(size).ToList(), settings.Bigrams, settings.Features);
                Evaluation[] evaluations = TestEvaluations(fit);
                for (int model = 0; model < 4; model++) lines.Add(Csv(size, fit.Vocabulary.Size, Models[model]) + "," + Fields(evaluations[model]));
            }
            return lines;
        }

        List<string> FeatureLines()
        {
            var lines = new List<string> { "terms,features,vocabulary,model,correct,accuracy,macro_f1" };
            foreach (bool bigrams in new[] { false, true }) foreach (int size in settings.Sizes)
            {
                Training fit = Trained(training, bigrams, size);
                Evaluation[] evaluations = TestEvaluations(fit);
                for (int model = 0; model < 4; model++) lines.Add(Csv(bigrams ? "bigrams" : "unigrams", size, fit.Vocabulary.Size, Models[model]) + "," + Fields(evaluations[model]));
            }
            return lines;
        }

        string ClassCounts(int[] counts) => string.Join(" ", classes.Select((name, c) => name + " " + counts[c]));

        List<string> DataPart()
        {
            var vocabulary = finalTraining.Vocabulary;
            var lines = new List<string> { $"documents train {training.Count} test {tests.Count} labelled {labelled.Length} unlabelled {unlabelled.Count} classes {classCount}" };
            int[] trainCounts = new int[classCount], testCounts = new int[classCount];
            foreach (var document in training) trainCounts[document.Label]++;
            foreach (int truth in truths) testCounts[truth]++;
            for (int c = 0; c < classCount; c++) lines.Add($"class {classes[c]} train {trainCounts[c]} test {testCounts[c]}");
            int raw = 0, stop = 0, shortWords = 0, kept = 0, bigramCount = 0;
            var terms = new HashSet<string>(StringComparer.Ordinal);
            foreach (var document in training)
            {
                Tokenizer tokens = document.Tokens;
                raw += tokens.RawCount; stop += tokens.StopwordCount; shortWords += tokens.ShortCount; kept += tokens.Words.Count;
                if (settings.Bigrams) bigramCount += tokens.Bigrams.Count;
                terms.UnionWith(tokens.Terms(settings.Bigrams));
            }
            int distinctBigrams = terms.Count(term => term.Contains('_'));
            lines.Add($"train_tokens raw {raw} stopwords {stop} short {shortWords} unigrams {kept} bigrams {bigramCount}");
            lines.Add($"train_terms unigrams {terms.Count - distinctBigrams} bigrams {distinctBigrams} candidates {vocabulary.CandidateCount} vocabulary {vocabulary.Size}");
            int total = 0, inVocabulary = 0;
            var oov = new Dictionary<string, int>(StringComparer.Ordinal);
            for (int i = 0; i < tests.Count; i++)
            {
                total += tests[i].Tokens.Terms(settings.Bigrams).Count; inVocabulary += testSequences[i].Length;
                foreach (string word in tests[i].Tokens.Words) if (!vocabulary.Index.ContainsKey(word)) oov[word] = oov.GetValueOrDefault(word) + 1;
            }
            lines.Add($"test_terms total {total} in_vocabulary {inVocabulary}");
            var tail = new List<string> { "test_oov" };
            foreach (var entry in oov.OrderByDescending(entry => entry.Value).ThenBy(entry => entry.Key, StringComparer.Ordinal).Take(settings.Top)) tail.Add(entry.Key + " " + entry.Value);
            lines.Add(string.Join(" ", tail));
            return lines;
        }

        List<string> FoldsPart()
        {
            var lines = new List<string> { "folds 5" };
            for (int i = 0; i < 5; i++) { var fold = folds[i]; lines.Add($"fold {i + 1} train {fold.Training} validate {fold.Validation} candidates {fold.Candidates} vocabulary {fold.Vocabulary}"); }
            return lines;
        }

        List<string> SelectionPart()
        {
            var lines = new List<string> { "selection" };
            for (int model = 0; model < 4; model++)
            {
                CrossRun run = selectedRuns[model];
                lines.Add($"{Models[model]} alpha {AlphaText(model)} correct {Proportion(run.Evaluation.Correct, run.Evaluation.Total)} macro_f1 {Real(run.Evaluation.MacroF1)} folds {string.Join(" ", run.FoldCorrect)}");
            }
            return lines;
        }

        List<string> CrossValidationPart(int model)
        {
            var lines = new List<string> { $"cross_validation {Models[model]} alpha {AlphaText(model)}" };
            lines.AddRange(selectedRuns[model].Evaluation.Lines(classes));
            return lines;
        }

        List<string> TestPart(int model)
        {
            int[] predicted = labelled.Select(i => predictions[model][i].Label).ToArray();
            var evaluation = new Evaluation(classCount, truths, predicted);
            var lines = new List<string> { $"test {Models[model]} alpha {AlphaText(model)}", $"labelled {labelled.Length} correct {Proportion(evaluation.Correct, labelled.Length)}" };
            if (model < 4)
            {
                int topTwo = 0;
                for (int i = 0; i < labelled.Length; i++) { int[] order = predictions[model][labelled[i]].Ranking; if (truths[i] == order[0] || truths[i] == order[1]) topTwo++; }
                lines.Add("top2 " + Proportion(topTwo, labelled.Length));
            }
            lines.AddRange(evaluation.Lines(classes));
            return lines;
        }

        List<string> ProbabilityPart(int model)
        {
            int length = settings.Thresholds.Length;
            int[] rows = new int[length + 1], hits = new int[length + 1], accepted = new int[length], acceptedHits = new int[length];
            double[] sums = new double[length + 1];
            double loss = 0.0, brier = 0.0;
            for (int i = 0; i < labelled.Length; i++)
            {
                Prediction prediction = predictions[model][labelled[i]];
                loss += Math.Log(prediction.Normalizer) - (prediction.Scores[truths[i]] - prediction.Scores[prediction.Label]);
                double squares = 0.0;
                for (int c = 0; c < classCount; c++) { double delta = prediction.Probabilities[c] - (c == truths[i] ? 1.0 : 0.0); squares += delta * delta; }
                brier += squares;
                int bucket = 0;
                for (int t = 0; t < length; t++) if (prediction.Score >= settings.Thresholds[t] / 100.0) { bucket++; accepted[t]++; if (correct[model][i]) acceptedHits[t]++; }
                rows[bucket]++; sums[bucket] += prediction.Score; if (correct[model][i]) hits[bucket]++;
            }
            var lines = new List<string> { $"probability {Models[model]} alpha {AlphaText(model)}", $"log_loss {Real(loss / labelled.Length)} brier {Real(brier / labelled.Length)}" };
            for (int bucket = 0; bucket <= length; bucket++)
            {
                string line = $"bin {HundredthsText(bucket == 0 ? 0 : settings.Thresholds[bucket - 1])} rows {rows[bucket]}";
                if (rows[bucket] > 0) line += $" correct {Proportion(hits[bucket], rows[bucket])} mean {Real(sums[bucket] / rows[bucket])}";
                lines.Add(line);
            }
            for (int t = 0; t < length; t++) lines.Add($"threshold {HundredthsText(settings.Thresholds[t])} covered {Proportion(accepted[t], labelled.Length)} correct {(accepted[t] == 0 ? "-" : Proportion(acceptedHits[t], accepted[t]))}");
            return lines;
        }

        List<string> LengthsPart()
        {
            int[] rows = new int[settings.Lengths.Length + 1];
            int[][] hits = Enumerable.Range(0, 5).Select(_ => new int[rows.Length]).ToArray();
            for (int i = 0; i < labelled.Length; i++)
            {
                int bucket = 0;
                foreach (int boundary in settings.Lengths) if (testSequences[labelled[i]].Length >= boundary) bucket++;
                rows[bucket]++;
                for (int model = 0; model < 5; model++) if (correct[model][i]) hits[model][bucket]++;
            }
            var lines = new List<string> { "lengths" };
            for (int bucket = 0; bucket < rows.Length; bucket++)
            {
                string line = $"length {(bucket == 0 ? 0 : settings.Lengths[bucket - 1])} rows {rows[bucket]}";
                if (rows[bucket] > 0) for (int model = 0; model < 5; model++) line += " " + Models[model] + " " + Proportion(hits[model][bucket], rows[bucket]);
                lines.Add(line);
            }
            return lines;
        }

        List<string> ComparisonPart()
        {
            var lines = new List<string> { "comparison" };
            for (int first = 0; first < 4; first++) for (int second = first + 1; second < 4; second++)
            {
                int agree = 0, b = 0, c = 0;
                for (int i = 0; i < tests.Count; i++) if (predictions[first][i].Label == predictions[second][i].Label) agree++;
                for (int i = 0; i < labelled.Length; i++) { if (correct[first][i] && !correct[second][i]) b++; if (correct[second][i] && !correct[first][i]) c++; }
                long delta = Math.Max(0, Math.Abs(b - c) - 1);
                string statistic = Evaluation.Fraction(b + c == 0 ? 0 : delta * delta, b + c == 0 ? 1 : b + c);
                lines.Add($"{Models[first]} {Models[second]} agree {Proportion(agree, tests.Count)} b {b} c {c} statistic {statistic}");
            }
            int[] errors = new int[5];
            for (int i = 0; i < labelled.Length; i++) { int wrong = 0; for (int model = 0; model < 4; model++) if (!correct[model][i]) wrong++; errors[wrong]++; }
            lines.Add("errors " + string.Join(" ", errors.Select((count, i) => i + " " + count)));
            return lines;
        }

        List<string> BootstrapPart()
        {
            int count = labelled.Length, repetitions = settings.Resamples;
            long state = settings.Seed;
            int[][] totals = Enumerable.Range(0, 5).Select(_ => new int[repetitions]).ToArray();
            for (int r = 0; r < repetitions; r++) for (int draw = 0; draw < count; draw++)
            {
                state = 48271 * state % 2147483647;
                int chosen = (int)(state % count);
                for (int model = 0; model < 5; model++) if (correct[model][chosen]) totals[model][r]++;
            }
            var lines = new List<string> { $"bootstrap resamples {repetitions} seed {settings.Seed}" };
            int tail = repetitions / 40;
            for (int model = 0; model < 5; model++)
            {
                int[] ordered = totals[model].OrderBy(value => value).ToArray();
                long sum = ordered.Sum(value => (long)value);
                lines.Add($"{Models[model]} mean {Real((double)sum / ((long)repetitions * count))} low {Proportion(ordered[tail], count)} high {Proportion(ordered[repetitions - 1 - tail], count)}");
            }
            for (int first = 0; first < 4; first++) for (int second = first + 1; second < 4; second++)
            {
                int wins = 0, ties = 0, losses = 0;
                for (int r = 0; r < repetitions; r++) { if (totals[first][r] > totals[second][r]) wins++; else if (totals[first][r] == totals[second][r]) ties++; else losses++; }
                lines.Add($"pair {Models[first]} {Models[second]} wins {wins} ties {ties} losses {losses}");
            }
            return lines;
        }

        List<string> HardPart()
        {
            var hard = new List<int>();
            int[] counts = new int[classCount];
            for (int i = 0; i < training.Count; i++)
            {
                bool allWrong = true;
                for (int model = 0; model < 4; model++) if (selectedRuns[model].Predictions[i] == training[i].Label) allWrong = false;
                if (allWrong) { hard.Add(i); counts[training[i].Label]++; }
            }
            var lines = new List<string> { $"hard_documents {hard.Count} {ClassCounts(counts)}" };
            foreach (int i in hard.Take(settings.Top))
            {
                string names = string.Join(" ", Enumerable.Range(0, 4).Select(model => classes[selectedRuns[model].Predictions[i]]));
                lines.Add($"{training[i].Name} true {classes[training[i].Label]} predicted {names}");
            }
            return lines;
        }

        List<string> UncertainPart()
        {
            var order = Enumerable.Range(0, tests.Count).OrderBy(i => Evaluation.Rounded(predictions[0][i].Margin)).ThenBy(i => i).Take(settings.Top).ToArray();
            var lines = new List<string> { "uncertain multinomial " + order.Length };
            foreach (int i in order)
            {
                Document document = tests[i]; Prediction prediction = predictions[0][i];
                lines.Add($"{document.Name} predicted {classes[prediction.Label]} runner_up {classes[prediction.Ranking[1]]} margin {Real(prediction.Margin)} posterior {Real(prediction.Score)} true {(document.Label < 0 ? "?" : classes[document.Label])}");
            }
            return lines;
        }

        List<string> MisclassifiedPart()
        {
            int[] wrong = labelled.Where(i => predictions[0][i].Label != tests[i].Label).ToArray();
            var lines = new List<string> { "misclassified multinomial " + wrong.Length };
            foreach (int i in wrong)
            {
                Document document = tests[i]; Prediction prediction = predictions[0][i];
                lines.Add($"{document.Name} true {classes[document.Label]} predicted {classes[prediction.Label]} posterior {Real(prediction.Score)}");
                var entries = new List<Ratio>();
                int[] frequencies = new int[finalTraining.Vocabulary.Size];
                foreach (int term in testSequences[i]) frequencies[term]++;
                foreach (int term in Vocabulary.FirstOccurrences(testSequences[i])) entries.Add(new Ratio(100 * finalTraining.Counts.Occurrences[prediction.Label][term] + selected[0], 100 * finalTraining.Counts.Occurrences[document.Label][term] + selected[0], term));
                SortRatios(entries);
                foreach (Ratio entry in entries.Take(3))
                {
                    int term = entry.Term;
                    double evidence = finalTraining.Models[0].Weights[prediction.Label][term] - finalTraining.Models[0].Weights[document.Label][term];
                    lines.Add($"  {finalTraining.Vocabulary.Terms[term]} count {frequencies[term]} evidence {Real(evidence)}");
                }
            }
            return lines;
        }

        NaiveBayes Maximization(Prediction[] posteriors, int[][] sequences)
        {
            TrainingCounts counts = finalTraining.Counts;
            int size = counts.VocabularySize;
            double[][] occurrences = counts.Occurrences.Select(row => row.Select(value => (double)value).ToArray()).ToArray();
            double[] documents = counts.Documents.Select(value => (double)value).ToArray();
            double weight = settings.Weight / 100.0;
            for (int i = 0; i < sequences.Length; i++)
            {
                int[] frequencies = new int[size]; foreach (int term in sequences[i]) frequencies[term]++;
                int[] terms = Vocabulary.FirstOccurrences(sequences[i]);
                for (int c = 0; c < classCount; c++)
                {
                    double share = weight * posteriors[i].Probabilities[c]; documents[c] += share;
                    foreach (int term in terms) occurrences[c][term] += share * frequencies[term];
                }
            }
            double[][] weights = Enumerable.Range(0, classCount).Select(_ => new double[size]).ToArray();
            double[] priors = new double[classCount];
            double scale = training.Count + (long)settings.Weight * unlabelled.Count / 100.0;
            for (int c = 0; c < classCount; c++)
            {
                double total = 0.0; foreach (double value in occurrences[c]) total += value;
                for (int t = 0; t < size; t++) weights[c][t] = NaiveBayes.SmoothedLog(occurrences[c][t], total, selected[0], size);
                priors[c] = Math.Log(documents[c] / scale);
            }
            return new NaiveBayes(0, priors, new double[classCount], weights);
        }

        List<string> SemiSupervisedPart()
        {
            int[][] sequences = unlabelled.Select(finalTraining.Encode).ToArray();
            NaiveBayes model = finalTraining.Models[0];
            int[]? previous = null;
            var lines = new List<string> { $"semi_supervised multinomial alpha {AlphaText(0)} weight {HundredthsText(settings.Weight)} unlabelled {unlabelled.Count}" };
            for (int iteration = 0; iteration <= settings.Iterations; iteration++)
            {
                Prediction[] posteriors = sequences.Select(model.Predict).ToArray();
                int[] assignments = posteriors.Select(posterior => posterior.Label).ToArray();
                int[] assigned = new int[classCount];
                int changed = 0;
                for (int i = 0; i < assignments.Length; i++) { assigned[assignments[i]]++; if (previous != null && previous[i] != assignments[i]) changed++; }
                int[] predicted = labelled.Select(i => model.Predict(testSequences[i]).Label).ToArray();
                var evaluation = new Evaluation(classCount, truths, predicted);
                lines.Add($"iteration {iteration} correct {Proportion(evaluation.Correct, evaluation.Total)} macro_f1 {Real(evaluation.MacroF1)} changed {(previous == null ? "-" : changed.ToString(CultureInfo.InvariantCulture))} assigned {ClassCounts(assigned)}");
                if (iteration < settings.Iterations) model = Maximization(posteriors, sequences);
                previous = assignments;
            }
            return lines;
        }

        List<string> MetricsLines()
        {
            var parts = new List<List<string>> { DataPart(), FoldsPart(), SelectionPart() };
            for (int model = 0; model < 4; model++) parts.Add(CrossValidationPart(model));
            for (int model = 0; model < 5; model++) parts.Add(TestPart(model));
            for (int model = 0; model < 3; model++) parts.Add(ProbabilityPart(model));
            parts.Add(LengthsPart()); parts.Add(ComparisonPart()); parts.Add(BootstrapPart()); parts.Add(HardPart()); parts.Add(UncertainPart()); parts.Add(MisclassifiedPart()); parts.Add(SemiSupervisedPart());
            return JoinParts(parts);
        }

        List<string> TopFeatureLines()
        {
            var parts = new List<List<string>>();
            TrainingCounts counts = finalTraining.Counts;
            int size = counts.VocabularySize;
            for (int model = 0; model < 2; model++)
            {
                long[][] table = model == 0 ? counts.Occurrences : counts.Containing;
                long[] totals = model == 0 ? counts.Totals : counts.Documents;
                long overall = model == 0 ? counts.Total : counts.DocumentTotal;
                int outcomes = model == 0 ? size : 2;
                long[] termTotals = new long[size];
                for (int t = 0; t < size; t++) for (int c = 0; c < classCount; c++) termTotals[t] += table[c][t];
                parts.Add(new List<string> { $"model {Models[model]} alpha {AlphaText(model)} vocabulary {size} top {settings.Top}" });
                for (int c = 0; c < classCount; c++)
                {
                    long total = totals[c], other = overall - total;
                    var lines = new List<string> { $"class {classes[c]} total {total} other {other}" };
                    var entries = new List<Ratio>();
                    for (int t = 0; t < size; t++) entries.Add(new Ratio(100 * table[c][t] + selected[model], 100 * (termTotals[t] - table[c][t]) + selected[model], t));
                    SortRatios(entries);
                    for (int rank = 0; rank < Math.Min(settings.Top, size); rank++)
                    {
                        int term = entries[rank].Term;
                        long count = table[c][term], otherCount = termTotals[term] - count;
                        double odds = NaiveBayes.SmoothedLog(count, total, selected[model], outcomes) - NaiveBayes.SmoothedLog(otherCount, other, selected[model], outcomes);
                        lines.Add($"{rank + 1} {finalTraining.Vocabulary.Terms[term]} {count} {otherCount} {Real(odds)}");
                    }
                    parts.Add(lines);
                }
            }
            return JoinParts(parts);
        }

        public void WriteOutputs()
        {
            Directory.CreateDirectory("output");
            var files = new Dictionary<string, List<string>>
            {
                ["vocabulary.txt"] = VocabularyLines(), ["cv_results.csv"] = CvLines(), ["predictions.csv"] = PredictionLines(),
                ["learning_curve.csv"] = CurveLines(), ["feature_study.csv"] = FeatureLines(), ["metrics.txt"] = MetricsLines(), ["top_features.txt"] = TopFeatureLines()
            };
            foreach (var entry in files) File.WriteAllText(Path.Combine("output", entry.Key), string.Join("\n", entry.Value) + "\n", Encoding.ASCII);
        }
    }

    static void Main()
    {
        var experiment = new Experiment();
        experiment.Run();
        experiment.WriteOutputs();
    }
}
