import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;

public final class Main {
    static final String[] MODELS = {"multinomial", "bernoulli", "complement", "rocchio", "vote"};
    record Document(String name, int label, Tokenizer tokens) {}
    record FoldSummary(int training, int validation, int candidates, int vocabulary) {}
    record CrossRun(int[] predictions, Evaluation evaluation, int[] foldCorrect) {}
    record Ratio(long numerator, long denominator, int term) {}

    static List<String> read(String name) throws IOException {
        return Files.readAllLines(Path.of("input", name), StandardCharsets.US_ASCII);
    }

    static int hundredths(String text) {
        String[] parts = text.split("\\.");
        return Integer.parseInt(parts[0]) * 100 + Integer.parseInt(parts[1]);
    }

    static String hundredthsText(int value) { return String.format(Locale.ROOT, "%d.%02d", value / 100, value % 100); }
    static String real(double value) { return Evaluation.real(value); }
    static String proportion(long a, long b) { return Evaluation.proportion(a, b); }
    static String csv(Object... values) { return String.join(",", Arrays.stream(values).map(Object::toString).toList()); }
    static String integers(int[] values) { return String.join(" ", Arrays.stream(values).mapToObj(Integer::toString).toList()); }
    static String fields(Evaluation evaluation) { return csv(evaluation.correct, real(evaluation.microF1), real(evaluation.macroF1)); }

    static List<String> joinParts(List<List<String>> parts) {
        List<String> lines = new ArrayList<>();
        for (List<String> part : parts) { if (!lines.isEmpty()) lines.add(""); lines.addAll(part); }
        return lines;
    }

    static void sortRatios(List<Ratio> entries) {
        entries.sort((first, second) -> {
            int comparison = Long.compare(second.numerator * first.denominator, first.numerator * second.denominator);
            return comparison != 0 ? comparison : Integer.compare(first.term, second.term);
        });
    }

    static final class Settings {
        final int[] alphas, curve, sizes, thresholds, lengths;
        final int minDf, features, top, iterations, weight, resamples;
        final long seed;
        final boolean bigrams;

        Settings(List<String> lines) {
            Map<String, String[]> values = new HashMap<>();
            for (String line : lines) { String[] parts = line.split(" "); values.put(parts[0], Arrays.copyOfRange(parts, 1, parts.length)); }
            alphas = Arrays.stream(values.get("ALPHAS")).mapToInt(Main::hundredths).toArray();
            minDf = Integer.parseInt(values.get("MIN_DF")[0]);
            features = Integer.parseInt(values.get("FEATURES")[0]);
            bigrams = values.get("BIGRAMS")[0].equals("yes");
            top = Integer.parseInt(values.get("TOP")[0]);
            curve = Arrays.stream(values.get("CURVE")).mapToInt(Integer::parseInt).toArray();
            sizes = Arrays.stream(values.get("SIZES")).mapToInt(Integer::parseInt).toArray();
            thresholds = Arrays.stream(values.get("THRESHOLDS")).mapToInt(Main::hundredths).toArray();
            lengths = Arrays.stream(values.get("LENGTHS")).mapToInt(Integer::parseInt).toArray();
            iterations = Integer.parseInt(values.get("EM_ITERATIONS")[0]);
            weight = hundredths(values.get("EM_WEIGHT")[0]);
            resamples = Integer.parseInt(values.get("BOOTSTRAP")[0]);
            seed = Long.parseLong(values.get("BOOTSTRAP")[1]);
        }
    }

    static final class Training {
        final boolean bigrams;
        final Vocabulary vocabulary;
        final TrainingCounts counts;
        final Rocchio rocchio;
        final NaiveBayes[] models = new NaiveBayes[3];

        Training(List<Document> documents, boolean bigrams, int classes, int minDf, int size) {
            this.bigrams = bigrams;
            List<List<String>> sequences = documents.stream().map(document -> document.tokens.terms(bigrams)).toList();
            int[] labels = documents.stream().mapToInt(Document::label).toArray();
            vocabulary = new Vocabulary(sequences, labels, classes, minDf, size);
            List<int[]> encoded = sequences.stream().map(vocabulary::encode).toList();
            counts = new TrainingCounts(encoded, labels, classes, vocabulary.size());
            rocchio = new Rocchio(encoded, labels, classes, vocabulary.frequencies);
        }

        void train(int[] alphas) { for (int model = 0; model < 3; model++) models[model] = NaiveBayes.train(model, counts, alphas[model]); }
        int[] encode(Document document) { return vocabulary.encode(document.tokens.terms(bigrams)); }
        Prediction classify(int model, int[] sequence) { return model == 3 ? rocchio.predict(sequence) : models[model].predict(sequence); }
    }

    static final class Experiment {
        final Settings settings;
        final String[] classes;
        final int classCount;
        final List<Document> training = new ArrayList<>();
        final List<Document> tests = new ArrayList<>();
        final List<Document> unlabelled = new ArrayList<>();
        final int[] labelled;
        final int[] truths;
        final List<FoldSummary> folds = new ArrayList<>();
        final CrossRun[][] cvRuns = new CrossRun[4][];
        final CrossRun[] selectedRuns = new CrossRun[4];
        final int[] selected = new int[3];
        Training finalTraining;
        int[][] testSequences;
        Prediction[][] predictions;
        boolean[][] correct;

        Experiment() throws IOException {
            settings = new Settings(read("params.txt"));
            Set<String> stopwords = new HashSet<>(read("stopwords.txt"));
            List<String[]> rows = read("train.txt").stream().map(line -> line.split("\t", 2)).toList();
            classes = rows.stream().map(row -> row[0]).distinct().sorted().toArray(String[]::new);
            classCount = classes.length;
            Map<String, Integer> positions = new HashMap<>();
            for (int c = 0; c < classCount; c++) positions.put(classes[c], c);
            for (int i = 0; i < rows.size(); i++) training.add(new Document(Integer.toString(i + 1), positions.get(rows.get(i)[0]), new Tokenizer(rows.get(i)[1], stopwords)));
            for (String line : read("test.txt")) {
                String[] row = line.split("\t", 3);
                tests.add(new Document(row[0], row[1].equals("?") ? -1 : positions.get(row[1]), new Tokenizer(row[2], stopwords)));
            }
            for (String text : read("unlabelled.txt")) unlabelled.add(new Document(Integer.toString(unlabelled.size() + 1), -1, new Tokenizer(text, stopwords)));
            labelled = java.util.stream.IntStream.range(0, tests.size()).filter(i -> tests.get(i).label >= 0).toArray();
            truths = Arrays.stream(labelled).map(i -> tests.get(i).label).toArray();
        }

        void run() {
            crossValidate();
            for (int model = 0; model < 3; model++) {
                int best = 0;
                for (int i = 1; i < settings.alphas.length; i++) if (Evaluation.rounded(cvRuns[model][i].evaluation.macroF1) > Evaluation.rounded(cvRuns[model][best].evaluation.macroF1)) best = i;
                selected[model] = settings.alphas[best];
                selectedRuns[model] = cvRuns[model][best];
            }
            selectedRuns[3] = cvRuns[3][0];
            finalTraining = trained(training, settings.bigrams, settings.features);
            testSequences = tests.stream().map(finalTraining::encode).toArray(int[][]::new);
            predictions = new Prediction[5][tests.size()];
            for (int model = 0; model < 4; model++) for (int i = 0; i < tests.size(); i++) predictions[model][i] = finalTraining.classify(model, testSequences[i]);
            for (int i = 0; i < tests.size(); i++) {
                int[] votes = new int[classCount];
                for (int model = 0; model < 4; model++) votes[predictions[model][i].label]++;
                int winner = predictions[0][i].label;
                for (int model = 0; model < 4; model++) { int c = predictions[model][i].label; if (votes[c] > votes[winner]) winner = c; }
                predictions[4][i] = new Prediction(winner, votes[winner] / 4.0);
            }
            correct = new boolean[5][labelled.length];
            for (int model = 0; model < 5; model++) for (int i = 0; i < labelled.length; i++) correct[model][i] = predictions[model][labelled[i]].label == truths[i];
        }

        Training trained(List<Document> documents, boolean bigrams, int size) {
            Training result = new Training(documents, bigrams, classCount, settings.minDf, size);
            result.train(selected);
            return result;
        }

        String alphaText(int model) { return model < 3 ? hundredthsText(selected[model]) : "-"; }

        CrossRun crossRun(int[] predicted) {
            int[] trueLabels = training.stream().mapToInt(Document::label).toArray();
            int[] hits = new int[5];
            for (int i = 0; i < predicted.length; i++) if (predicted[i] == trueLabels[i]) hits[i % 5]++;
            return new CrossRun(predicted, new Evaluation(classCount, trueLabels, predicted), hits);
        }

        void crossValidate() {
            int count = training.size();
            int[][][] nb = new int[3][settings.alphas.length][count];
            int[] rocchio = new int[count];
            for (int fold = 0; fold < 5; fold++) {
                List<Document> members = new ArrayList<>();
                List<Integer> held = new ArrayList<>();
                for (int i = 0; i < count; i++) { if (i % 5 == fold) held.add(i); else members.add(training.get(i)); }
                Training fit = new Training(members, settings.bigrams, classCount, settings.minDf, settings.features);
                folds.add(new FoldSummary(members.size(), held.size(), fit.vocabulary.candidateCount, fit.vocabulary.size()));
                List<int[]> sequences = held.stream().map(i -> fit.encode(training.get(i))).toList();
                for (int model = 0; model < 3; model++) for (int a = 0; a < settings.alphas.length; a++) {
                    NaiveBayes classifier = NaiveBayes.train(model, fit.counts, settings.alphas[a]);
                    for (int i = 0; i < held.size(); i++) nb[model][a][held.get(i)] = classifier.predict(sequences.get(i)).label;
                }
                for (int i = 0; i < held.size(); i++) rocchio[held.get(i)] = fit.rocchio.predict(sequences.get(i)).label;
            }
            for (int model = 0; model < 3; model++) {
                cvRuns[model] = new CrossRun[settings.alphas.length];
                for (int a = 0; a < settings.alphas.length; a++) cvRuns[model][a] = crossRun(nb[model][a]);
            }
            cvRuns[3] = new CrossRun[]{crossRun(rocchio)};
        }

        Evaluation[] testEvaluations(Training fit) {
            List<int[]> sequences = Arrays.stream(labelled).mapToObj(i -> fit.encode(tests.get(i))).toList();
            Evaluation[] results = new Evaluation[4];
            for (int model = 0; model < 4; model++) {
                int[] predicted = new int[labelled.length];
                for (int i = 0; i < predicted.length; i++) predicted[i] = fit.classify(model, sequences.get(i)).label;
                results[model] = new Evaluation(classCount, truths, predicted);
            }
            return results;
        }

        List<String> vocabularyLines() {
            Vocabulary vocabulary = finalTraining.vocabulary;
            List<String> lines = new ArrayList<>();
            lines.add("documents " + training.size() + " terms " + vocabulary.termCount + " candidates " + vocabulary.candidateCount + " vocabulary " + vocabulary.size());
            for (int i = 0; i < vocabulary.ranking.size(); i++) {
                Vocabulary.RankedTerm entry = vocabulary.ranking.get(i);
                lines.add((i + 1) + " " + entry.term() + " " + entry.frequency() + " " + real(entry.score()) + " " + classes[entry.bestClass()]);
            }
            return lines;
        }

        List<String> cvLines() {
            List<String> lines = new ArrayList<>(List.of("model,alpha,correct,accuracy,macro_f1,selected"));
            for (int model = 0; model < 3; model++) for (int a = 0; a < settings.alphas.length; a++) lines.add(MODELS[model] + "," + hundredthsText(settings.alphas[a]) + "," + fields(cvRuns[model][a].evaluation) + "," + (selected[model] == settings.alphas[a] ? "yes" : "no"));
            lines.add("rocchio,-," + fields(cvRuns[3][0].evaluation) + ",yes");
            return lines;
        }

        List<String> predictionLines() {
            List<String> lines = new ArrayList<>(List.of("id,model,label,score"));
            for (int i = 0; i < tests.size(); i++) for (int model = 0; model < 5; model++) lines.add(csv(tests.get(i).name, MODELS[model], classes[predictions[model][i].label], real(predictions[model][i].score)));
            return lines;
        }

        List<String> curveLines() {
            List<String> lines = new ArrayList<>(List.of("size,vocabulary,model,correct,accuracy,macro_f1"));
            for (int size : settings.curve) {
                Training fit = trained(training.subList(0, size), settings.bigrams, settings.features);
                Evaluation[] evaluations = testEvaluations(fit);
                for (int model = 0; model < 4; model++) lines.add(csv(size, fit.vocabulary.size(), MODELS[model]) + "," + fields(evaluations[model]));
            }
            return lines;
        }

        List<String> featureLines() {
            List<String> lines = new ArrayList<>(List.of("terms,features,vocabulary,model,correct,accuracy,macro_f1"));
            for (boolean bigrams : new boolean[]{false, true}) for (int size : settings.sizes) {
                Training fit = trained(training, bigrams, size);
                Evaluation[] evaluations = testEvaluations(fit);
                for (int model = 0; model < 4; model++) lines.add(csv(bigrams ? "bigrams" : "unigrams", size, fit.vocabulary.size(), MODELS[model]) + "," + fields(evaluations[model]));
            }
            return lines;
        }

        String classCounts(int[] counts) {
            StringJoiner result = new StringJoiner(" ");
            for (int c = 0; c < classCount; c++) result.add(classes[c] + " " + counts[c]);
            return result.toString();
        }

        List<String> dataPart() {
            Vocabulary vocabulary = finalTraining.vocabulary;
            List<String> lines = new ArrayList<>();
            lines.add("documents train " + training.size() + " test " + tests.size() + " labelled " + labelled.length + " unlabelled " + unlabelled.size() + " classes " + classCount);
            int[] trainCounts = new int[classCount], testCounts = new int[classCount];
            for (Document document : training) trainCounts[document.label]++;
            for (int truth : truths) testCounts[truth]++;
            for (int c = 0; c < classCount; c++) lines.add("class " + classes[c] + " train " + trainCounts[c] + " test " + testCounts[c]);
            int raw = 0, stop = 0, shortWords = 0, kept = 0, bigramCount = 0;
            Set<String> terms = new HashSet<>();
            for (Document document : training) {
                Tokenizer tokens = document.tokens;
                raw += tokens.rawCount; stop += tokens.stopwordCount; shortWords += tokens.shortCount; kept += tokens.words.size();
                if (settings.bigrams) bigramCount += tokens.bigrams.size();
                terms.addAll(tokens.terms(settings.bigrams));
            }
            long distinctBigrams = terms.stream().filter(term -> term.contains("_")).count();
            lines.add("train_tokens raw " + raw + " stopwords " + stop + " short " + shortWords + " unigrams " + kept + " bigrams " + bigramCount);
            lines.add("train_terms unigrams " + (terms.size() - distinctBigrams) + " bigrams " + distinctBigrams + " candidates " + vocabulary.candidateCount + " vocabulary " + vocabulary.size());
            int total = 0, inVocabulary = 0;
            Map<String, Integer> oov = new HashMap<>();
            for (int i = 0; i < tests.size(); i++) {
                total += tests.get(i).tokens.terms(settings.bigrams).size(); inVocabulary += testSequences[i].length;
                for (String word : tests.get(i).tokens.words) if (!vocabulary.index.containsKey(word)) oov.merge(word, 1, Integer::sum);
            }
            lines.add("test_terms total " + total + " in_vocabulary " + inVocabulary);
            List<String> ranked = new ArrayList<>(oov.keySet());
            ranked.sort(Comparator.<String>comparingInt(oov::get).reversed().thenComparing(Comparator.naturalOrder()));
            StringJoiner tail = new StringJoiner(" "); tail.add("test_oov");
            for (String word : ranked.subList(0, Math.min(settings.top, ranked.size()))) tail.add(word + " " + oov.get(word));
            lines.add(tail.toString());
            return lines;
        }

        List<String> foldsPart() {
            List<String> lines = new ArrayList<>(List.of("folds 5"));
            for (int i = 0; i < 5; i++) { FoldSummary fold = folds.get(i); lines.add("fold " + (i + 1) + " train " + fold.training + " validate " + fold.validation + " candidates " + fold.candidates + " vocabulary " + fold.vocabulary); }
            return lines;
        }

        List<String> selectionPart() {
            List<String> lines = new ArrayList<>(List.of("selection"));
            for (int model = 0; model < 4; model++) { CrossRun run = selectedRuns[model]; lines.add(MODELS[model] + " alpha " + alphaText(model) + " correct " + proportion(run.evaluation.correct, run.evaluation.total) + " macro_f1 " + real(run.evaluation.macroF1) + " folds " + integers(run.foldCorrect)); }
            return lines;
        }

        List<String> crossValidationPart(int model) {
            List<String> lines = new ArrayList<>(List.of("cross_validation " + MODELS[model] + " alpha " + alphaText(model)));
            lines.addAll(selectedRuns[model].evaluation.lines(classes));
            return lines;
        }

        List<String> testPart(int model) {
            int[] predicted = Arrays.stream(labelled).map(i -> predictions[model][i].label).toArray();
            Evaluation evaluation = new Evaluation(classCount, truths, predicted);
            List<String> lines = new ArrayList<>(List.of("test " + MODELS[model] + " alpha " + alphaText(model), "labelled " + labelled.length + " correct " + proportion(evaluation.correct, labelled.length)));
            if (model < 4) {
                int topTwo = 0;
                for (int i = 0; i < labelled.length; i++) { int[] order = predictions[model][labelled[i]].ranking; if (truths[i] == order[0] || truths[i] == order[1]) topTwo++; }
                lines.add("top2 " + proportion(topTwo, labelled.length));
            }
            lines.addAll(evaluation.lines(classes));
            return lines;
        }

        List<String> probabilityPart(int model) {
            int length = settings.thresholds.length;
            int[] rows = new int[length + 1], hits = new int[length + 1], accepted = new int[length], acceptedHits = new int[length];
            double[] sums = new double[length + 1];
            double loss = 0.0, brier = 0.0;
            for (int i = 0; i < labelled.length; i++) {
                Prediction prediction = predictions[model][labelled[i]];
                loss += Math.log(prediction.normalizer) - (prediction.scores[truths[i]] - prediction.scores[prediction.label]);
                double squares = 0.0;
                for (int c = 0; c < classCount; c++) { double delta = prediction.probabilities[c] - (c == truths[i] ? 1.0 : 0.0); squares += delta * delta; }
                brier += squares;
                int bucket = 0;
                for (int t = 0; t < length; t++) if (prediction.score >= settings.thresholds[t] / 100.0) { bucket++; accepted[t]++; if (correct[model][i]) acceptedHits[t]++; }
                rows[bucket]++; sums[bucket] += prediction.score; if (correct[model][i]) hits[bucket]++;
            }
            List<String> lines = new ArrayList<>(List.of("probability " + MODELS[model] + " alpha " + alphaText(model), "log_loss " + real(loss / labelled.length) + " brier " + real(brier / labelled.length)));
            for (int bucket = 0; bucket <= length; bucket++) {
                String line = "bin " + hundredthsText(bucket == 0 ? 0 : settings.thresholds[bucket - 1]) + " rows " + rows[bucket];
                if (rows[bucket] > 0) line += " correct " + proportion(hits[bucket], rows[bucket]) + " mean " + real(sums[bucket] / rows[bucket]);
                lines.add(line);
            }
            for (int t = 0; t < length; t++) lines.add("threshold " + hundredthsText(settings.thresholds[t]) + " covered " + proportion(accepted[t], labelled.length) + " correct " + (accepted[t] == 0 ? "-" : proportion(acceptedHits[t], accepted[t])));
            return lines;
        }

        List<String> lengthsPart() {
            int[] rows = new int[settings.lengths.length + 1];
            int[][] hits = new int[5][rows.length];
            for (int i = 0; i < labelled.length; i++) {
                int bucket = 0;
                for (int boundary : settings.lengths) if (testSequences[labelled[i]].length >= boundary) bucket++;
                rows[bucket]++;
                for (int model = 0; model < 5; model++) if (correct[model][i]) hits[model][bucket]++;
            }
            List<String> lines = new ArrayList<>(List.of("lengths"));
            for (int bucket = 0; bucket < rows.length; bucket++) {
                String line = "length " + (bucket == 0 ? 0 : settings.lengths[bucket - 1]) + " rows " + rows[bucket];
                if (rows[bucket] > 0) for (int model = 0; model < 5; model++) line += " " + MODELS[model] + " " + proportion(hits[model][bucket], rows[bucket]);
                lines.add(line);
            }
            return lines;
        }

        List<String> comparisonPart() {
            List<String> lines = new ArrayList<>(List.of("comparison"));
            for (int first = 0; first < 4; first++) for (int second = first + 1; second < 4; second++) {
                int agree = 0, b = 0, c = 0;
                for (int i = 0; i < tests.size(); i++) if (predictions[first][i].label == predictions[second][i].label) agree++;
                for (int i = 0; i < labelled.length; i++) { if (correct[first][i] && !correct[second][i]) b++; if (correct[second][i] && !correct[first][i]) c++; }
                long delta = Math.max(0, Math.abs(b - c) - 1);
                String statistic = Evaluation.fraction(b + c == 0 ? 0 : delta * delta, b + c == 0 ? 1 : b + c);
                lines.add(MODELS[first] + " " + MODELS[second] + " agree " + proportion(agree, tests.size()) + " b " + b + " c " + c + " statistic " + statistic);
            }
            int[] errors = new int[5];
            for (int i = 0; i < labelled.length; i++) { int wrong = 0; for (int model = 0; model < 4; model++) if (!correct[model][i]) wrong++; errors[wrong]++; }
            StringJoiner line = new StringJoiner(" "); line.add("errors");
            for (int i = 0; i < 5; i++) line.add(i + " " + errors[i]);
            lines.add(line.toString());
            return lines;
        }

        List<String> bootstrapPart() {
            int count = labelled.length, repetitions = settings.resamples;
            long state = settings.seed;
            int[][] totals = new int[5][repetitions];
            for (int r = 0; r < repetitions; r++) for (int draw = 0; draw < count; draw++) {
                state = 48271 * state % 2147483647;
                int chosen = (int) (state % count);
                for (int model = 0; model < 5; model++) if (correct[model][chosen]) totals[model][r]++;
            }
            List<String> lines = new ArrayList<>(List.of("bootstrap resamples " + repetitions + " seed " + settings.seed));
            int tail = repetitions / 40;
            for (int model = 0; model < 5; model++) {
                int[] ordered = totals[model].clone(); Arrays.sort(ordered);
                long sum = 0; for (int value : ordered) sum += value;
                lines.add(MODELS[model] + " mean " + real((double) sum / ((long) repetitions * count)) + " low " + proportion(ordered[tail], count) + " high " + proportion(ordered[repetitions - 1 - tail], count));
            }
            for (int first = 0; first < 4; first++) for (int second = first + 1; second < 4; second++) {
                int wins = 0, ties = 0, losses = 0;
                for (int r = 0; r < repetitions; r++) { if (totals[first][r] > totals[second][r]) wins++; else if (totals[first][r] == totals[second][r]) ties++; else losses++; }
                lines.add("pair " + MODELS[first] + " " + MODELS[second] + " wins " + wins + " ties " + ties + " losses " + losses);
            }
            return lines;
        }

        List<String> hardPart() {
            List<Integer> hard = new ArrayList<>();
            int[] counts = new int[classCount];
            for (int i = 0; i < training.size(); i++) {
                boolean allWrong = true;
                for (int model = 0; model < 4; model++) if (selectedRuns[model].predictions[i] == training.get(i).label) allWrong = false;
                if (allWrong) { hard.add(i); counts[training.get(i).label]++; }
            }
            List<String> lines = new ArrayList<>(List.of("hard_documents " + hard.size() + " " + classCounts(counts)));
            for (int i : hard.subList(0, Math.min(settings.top, hard.size()))) {
                StringJoiner names = new StringJoiner(" "); for (int model = 0; model < 4; model++) names.add(classes[selectedRuns[model].predictions[i]]);
                lines.add(training.get(i).name + " true " + classes[training.get(i).label] + " predicted " + names);
            }
            return lines;
        }

        List<String> uncertainPart() {
            List<Integer> order = new ArrayList<>(); for (int i = 0; i < tests.size(); i++) order.add(i);
            order.sort(Comparator.<Integer>comparingLong(i -> Evaluation.rounded(predictions[0][i].margin)).thenComparingInt(i -> i));
            int count = Math.min(settings.top, tests.size());
            List<String> lines = new ArrayList<>(List.of("uncertain multinomial " + count));
            for (int i : order.subList(0, count)) {
                Document document = tests.get(i); Prediction prediction = predictions[0][i];
                lines.add(document.name + " predicted " + classes[prediction.label] + " runner_up " + classes[prediction.ranking[1]] + " margin " + real(prediction.margin) + " posterior " + real(prediction.score) + " true " + (document.label < 0 ? "?" : classes[document.label]));
            }
            return lines;
        }

        List<String> misclassifiedPart() {
            List<Integer> wrong = Arrays.stream(labelled).filter(i -> predictions[0][i].label != tests.get(i).label).boxed().toList();
            List<String> lines = new ArrayList<>(List.of("misclassified multinomial " + wrong.size()));
            for (int i : wrong) {
                Document document = tests.get(i); Prediction prediction = predictions[0][i];
                lines.add(document.name + " true " + classes[document.label] + " predicted " + classes[prediction.label] + " posterior " + real(prediction.score));
                List<Ratio> entries = new ArrayList<>();
                int[] frequencies = new int[finalTraining.vocabulary.size()];
                for (int term : testSequences[i]) frequencies[term]++;
                for (int term : Vocabulary.firstOccurrences(testSequences[i])) entries.add(new Ratio(100 * finalTraining.counts.occurrences[prediction.label][term] + selected[0], 100 * finalTraining.counts.occurrences[document.label][term] + selected[0], term));
                sortRatios(entries);
                for (Ratio entry : entries.subList(0, Math.min(3, entries.size()))) {
                    int term = entry.term;
                    double evidence = finalTraining.models[0].weights[prediction.label][term] - finalTraining.models[0].weights[document.label][term];
                    lines.add("  " + finalTraining.vocabulary.terms[term] + " count " + frequencies[term] + " evidence " + real(evidence));
                }
            }
            return lines;
        }

        NaiveBayes maximization(Prediction[] posteriors, int[][] sequences) {
            TrainingCounts counts = finalTraining.counts;
            int size = counts.vocabularySize;
            double[][] occurrences = new double[classCount][size];
            double[] documents = new double[classCount];
            for (int c = 0; c < classCount; c++) { documents[c] = counts.documents[c]; for (int t = 0; t < size; t++) occurrences[c][t] = counts.occurrences[c][t]; }
            double weight = settings.weight / 100.0;
            for (int i = 0; i < sequences.length; i++) {
                int[] frequencies = new int[size]; for (int term : sequences[i]) frequencies[term]++;
                int[] terms = Vocabulary.firstOccurrences(sequences[i]);
                for (int c = 0; c < classCount; c++) {
                    double share = weight * posteriors[i].probabilities[c]; documents[c] += share;
                    for (int term : terms) occurrences[c][term] += share * frequencies[term];
                }
            }
            double[][] weights = new double[classCount][size];
            double[] priors = new double[classCount];
            double scale = training.size() + (long) settings.weight * unlabelled.size() / 100.0;
            for (int c = 0; c < classCount; c++) {
                double total = 0.0; for (double value : occurrences[c]) total += value;
                for (int t = 0; t < size; t++) weights[c][t] = NaiveBayes.smoothedLog(occurrences[c][t], total, selected[0], size);
                priors[c] = Math.log(documents[c] / scale);
            }
            return new NaiveBayes(0, priors, new double[classCount], weights);
        }

        List<String> semiSupervisedPart() {
            int[][] sequences = unlabelled.stream().map(finalTraining::encode).toArray(int[][]::new);
            NaiveBayes model = finalTraining.models[0];
            int[] previous = null;
            List<String> lines = new ArrayList<>(List.of("semi_supervised multinomial alpha " + alphaText(0) + " weight " + hundredthsText(settings.weight) + " unlabelled " + unlabelled.size()));
            for (int iteration = 0; iteration <= settings.iterations; iteration++) {
                Prediction[] posteriors = new Prediction[sequences.length];
                int[] assignments = new int[sequences.length], assigned = new int[classCount];
                int changed = 0;
                for (int i = 0; i < sequences.length; i++) { posteriors[i] = model.predict(sequences[i]); assignments[i] = posteriors[i].label; assigned[assignments[i]]++; if (previous != null && previous[i] != assignments[i]) changed++; }
                int[] predicted = new int[labelled.length];
                for (int i = 0; i < labelled.length; i++) predicted[i] = model.predict(testSequences[labelled[i]]).label;
                Evaluation evaluation = new Evaluation(classCount, truths, predicted);
                lines.add("iteration " + iteration + " correct " + proportion(evaluation.correct, evaluation.total) + " macro_f1 " + real(evaluation.macroF1) + " changed " + (previous == null ? "-" : Integer.toString(changed)) + " assigned " + classCounts(assigned));
                if (iteration < settings.iterations) model = maximization(posteriors, sequences);
                previous = assignments;
            }
            return lines;
        }

        List<String> metricsLines() {
            List<List<String>> parts = new ArrayList<>(List.of(dataPart(), foldsPart(), selectionPart()));
            for (int model = 0; model < 4; model++) parts.add(crossValidationPart(model));
            for (int model = 0; model < 5; model++) parts.add(testPart(model));
            for (int model = 0; model < 3; model++) parts.add(probabilityPart(model));
            parts.add(lengthsPart()); parts.add(comparisonPart()); parts.add(bootstrapPart()); parts.add(hardPart()); parts.add(uncertainPart()); parts.add(misclassifiedPart()); parts.add(semiSupervisedPart());
            return joinParts(parts);
        }

        List<String> topFeatureLines() {
            List<List<String>> parts = new ArrayList<>();
            TrainingCounts counts = finalTraining.counts;
            int size = counts.vocabularySize;
            for (int model = 0; model < 2; model++) {
                long[][] table = model == 0 ? counts.occurrences : counts.containing;
                long[] totals = model == 0 ? counts.totals : counts.documents;
                long overall = model == 0 ? counts.total : counts.documentTotal;
                int outcomes = model == 0 ? size : 2;
                long[] termTotals = new long[size];
                for (int t = 0; t < size; t++) for (int c = 0; c < classCount; c++) termTotals[t] += table[c][t];
                parts.add(List.of("model " + MODELS[model] + " alpha " + alphaText(model) + " vocabulary " + size + " top " + settings.top));
                for (int c = 0; c < classCount; c++) {
                    long total = totals[c], other = overall - total;
                    List<String> lines = new ArrayList<>(List.of("class " + classes[c] + " total " + total + " other " + other));
                    List<Ratio> entries = new ArrayList<>();
                    for (int t = 0; t < size; t++) entries.add(new Ratio(100 * table[c][t] + selected[model], 100 * (termTotals[t] - table[c][t]) + selected[model], t));
                    sortRatios(entries);
                    for (int rank = 0; rank < Math.min(settings.top, size); rank++) {
                        int term = entries.get(rank).term;
                        long count = table[c][term], otherCount = termTotals[term] - count;
                        double odds = NaiveBayes.smoothedLog(count, total, selected[model], outcomes) - NaiveBayes.smoothedLog(otherCount, other, selected[model], outcomes);
                        lines.add((rank + 1) + " " + finalTraining.vocabulary.terms[term] + " " + count + " " + otherCount + " " + real(odds));
                    }
                    parts.add(lines);
                }
            }
            return joinParts(parts);
        }

        void writeOutputs() throws IOException {
            Files.createDirectories(Path.of("output"));
            Map<String, List<String>> files = new LinkedHashMap<>();
            files.put("vocabulary.txt", vocabularyLines()); files.put("cv_results.csv", cvLines()); files.put("predictions.csv", predictionLines());
            files.put("learning_curve.csv", curveLines()); files.put("feature_study.csv", featureLines()); files.put("metrics.txt", metricsLines()); files.put("top_features.txt", topFeatureLines());
            for (var entry : files.entrySet()) Files.writeString(Path.of("output", entry.getKey()), String.join("\n", entry.getValue()) + "\n", StandardCharsets.US_ASCII);
        }
    }

    public static void main(String[] args) throws IOException {
        Experiment experiment = new Experiment();
        experiment.run();
        experiment.writeOutputs();
    }
}
