import java.nio.charset.StandardCharsets
import java.nio.file.Files
import java.nio.file.Path
import java.util.Locale
import kotlin.math.abs
import kotlin.math.ln
import kotlin.math.max

private val models = listOf("multinomial", "bernoulli", "complement", "rocchio", "vote")
private data class Document(val name: String, val label: Int, val tokens: Tokenizer)
private data class FoldSummary(val training: Int, val validation: Int, val candidates: Int, val vocabulary: Int)
private data class CrossRun(val predictions: IntArray, val evaluation: Evaluation, val foldCorrect: IntArray)
private data class Ratio(val numerator: Long, val denominator: Long, val term: Int)

private fun readLines(name: String): List<String> = Files.readAllLines(Path.of("input", name), StandardCharsets.US_ASCII)
private fun hundredths(text: String): Int {
    val parts = text.split('.')
    return parts[0].toInt() * 100 + parts[1].toInt()
}
private fun hundredthsText(value: Int): String = String.format(Locale.ROOT, "%d.%02d", value / 100, value % 100)
private fun csv(vararg values: Any): String = values.joinToString(",")
private fun evaluationFields(evaluation: Evaluation): String = csv(evaluation.correct, realText(evaluation.microF1), realText(evaluation.macroF1))

private fun joinParts(parts: List<List<String>>): List<String> {
    val lines = mutableListOf<String>()
    for (part in parts) { if (lines.isNotEmpty()) lines.add(""); lines.addAll(part) }
    return lines
}

private fun rankedRatios(entries: List<Ratio>): List<Ratio> = entries.sortedWith { first, second ->
    val comparison = (second.numerator * first.denominator).compareTo(first.numerator * second.denominator)
    if (comparison != 0) comparison else first.term.compareTo(second.term)
}

private class Settings(lines: List<String>) {
    private val values = lines.associate { line -> val parts = line.split(' '); parts[0] to parts.drop(1) }
    val alphas = values.getValue("ALPHAS").map(::hundredths).toIntArray()
    val minDf = values.getValue("MIN_DF")[0].toInt()
    val features = values.getValue("FEATURES")[0].toInt()
    val bigrams = values.getValue("BIGRAMS")[0] == "yes"
    val top = values.getValue("TOP")[0].toInt()
    val curve = values.getValue("CURVE").map(String::toInt).toIntArray()
    val sizes = values.getValue("SIZES").map(String::toInt).toIntArray()
    val thresholds = values.getValue("THRESHOLDS").map(::hundredths).toIntArray()
    val lengths = values.getValue("LENGTHS").map(String::toInt).toIntArray()
    val iterations = values.getValue("EM_ITERATIONS")[0].toInt()
    val weight = hundredths(values.getValue("EM_WEIGHT")[0])
    val resamples = values.getValue("BOOTSTRAP")[0].toInt()
    val seed = values.getValue("BOOTSTRAP")[1].toLong()
}

private class Training(documents: List<Document>, val bigrams: Boolean, classes: Int, minDf: Int, size: Int) {
    val vocabulary: Vocabulary
    val counts: TrainingCounts
    val rocchio: Rocchio
    lateinit var classifiers: Array<NaiveBayes>

    init {
        val sequences = documents.map { it.tokens.terms(bigrams) }
        val labels = documents.map { it.label }.toIntArray()
        vocabulary = Vocabulary(sequences, labels, classes, minDf, size)
        val encoded = sequences.map(vocabulary::encode)
        counts = TrainingCounts(encoded, labels, classes, vocabulary.size)
        rocchio = Rocchio(encoded, labels, classes, vocabulary.frequencies)
    }

    fun train(alphas: IntArray) { classifiers = Array(3) { NaiveBayes.train(it, counts, alphas[it]) } }
    fun encode(document: Document): IntArray = vocabulary.encode(document.tokens.terms(bigrams))
    fun classify(model: Int, sequence: IntArray): Prediction = if (model == 3) rocchio.predict(sequence) else classifiers[model].predict(sequence)
}

private class Experiment {
    private val settings = Settings(readLines("params.txt"))
    private val classes: List<String>
    private val classCount: Int
    private val training: List<Document>
    private val tests: List<Document>
    private val unlabelled: List<Document>
    private val labelled: IntArray
    private val truths: IntArray
    private val folds = mutableListOf<FoldSummary>()
    private val cvRuns = Array(4) { emptyList<CrossRun>() }
    private lateinit var selectedRuns: Array<CrossRun>
    private val selected = IntArray(3)
    private lateinit var finalTraining: Training
    private lateinit var testSequences: Array<IntArray>
    private lateinit var predictions: Array<Array<Prediction>>
    private lateinit var correct: Array<BooleanArray>

    init {
        val stopwords = readLines("stopwords.txt").toSet()
        val rows = readLines("train.txt").map { it.split('\t', limit = 2) }
        classes = rows.map { it[0] }.distinct().sorted()
        classCount = classes.size
        val positions = classes.withIndex().associate { it.value to it.index }
        training = rows.mapIndexed { i, row -> Document((i + 1).toString(), positions.getValue(row[0]), Tokenizer(row[1], stopwords)) }
        tests = readLines("test.txt").map {
            val row = it.split('\t', limit = 3)
            Document(row[0], if (row[1] == "?") -1 else positions.getValue(row[1]), Tokenizer(row[2], stopwords))
        }
        unlabelled = readLines("unlabelled.txt").mapIndexed { i, text -> Document((i + 1).toString(), -1, Tokenizer(text, stopwords)) }
        labelled = tests.indices.filter { tests[it].label >= 0 }.toIntArray()
        truths = labelled.map { tests[it].label }.toIntArray()
    }

    fun run() {
        crossValidate()
        selectedRuns = Array(4) { model ->
            if (model == 3) cvRuns[model][0]
            else {
                var best = 0
                for (i in 1 until settings.alphas.size) if (rounded(cvRuns[model][i].evaluation.macroF1) > rounded(cvRuns[model][best].evaluation.macroF1)) best = i
                selected[model] = settings.alphas[best]
                cvRuns[model][best]
            }
        }
        finalTraining = trained(training, settings.bigrams, settings.features)
        testSequences = tests.map(finalTraining::encode).toTypedArray()
        val base = Array(4) { model -> Array(tests.size) { finalTraining.classify(model, testSequences[it]) } }
        predictions = Array(5) { model ->
            if (model < 4) base[model]
            else Array(tests.size) { i ->
                val votes = IntArray(classCount)
                for (m in 0 until 4) votes[base[m][i].label]++
                var winner = base[0][i].label
                for (m in 0 until 4) { val c = base[m][i].label; if (votes[c] > votes[winner]) winner = c }
                Prediction(winner, votes[winner] / 4.0)
            }
        }
        correct = Array(5) { model -> BooleanArray(labelled.size) { predictions[model][labelled[it]].label == truths[it] } }
    }

    private fun trained(documents: List<Document>, bigrams: Boolean, size: Int): Training =
        Training(documents, bigrams, classCount, settings.minDf, size).also { it.train(selected) }

    private fun alphaText(model: Int): String = if (model < 3) hundredthsText(selected[model]) else "-"

    private fun crossRun(predicted: IntArray): CrossRun {
        val trueLabels = training.map { it.label }.toIntArray()
        val hits = IntArray(5)
        for (i in predicted.indices) if (predicted[i] == trueLabels[i]) hits[i % 5]++
        return CrossRun(predicted, Evaluation(classCount, trueLabels, predicted), hits)
    }

    private fun crossValidate() {
        val count = training.size
        val nb = Array(3) { Array(settings.alphas.size) { IntArray(count) } }
        val rocchio = IntArray(count)
        for (fold in 0 until 5) {
            val members = training.filterIndexed { i, _ -> i % 5 != fold }
            val held = training.indices.filter { it % 5 == fold }
            val fit = Training(members, settings.bigrams, classCount, settings.minDf, settings.features)
            folds.add(FoldSummary(members.size, held.size, fit.vocabulary.candidateCount, fit.vocabulary.size))
            val sequences = held.map { fit.encode(training[it]) }
            for (model in 0 until 3) for (a in settings.alphas.indices) {
                val classifier = NaiveBayes.train(model, fit.counts, settings.alphas[a])
                for (i in held.indices) nb[model][a][held[i]] = classifier.predict(sequences[i]).label
            }
            for (i in held.indices) rocchio[held[i]] = fit.rocchio.predict(sequences[i]).label
        }
        for (model in 0 until 3) cvRuns[model] = nb[model].map(::crossRun)
        cvRuns[3] = listOf(crossRun(rocchio))
    }

    private fun testEvaluations(fit: Training): List<Evaluation> {
        val sequences = labelled.map { fit.encode(tests[it]) }
        return (0 until 4).map { model -> Evaluation(classCount, truths, sequences.map { fit.classify(model, it).label }.toIntArray()) }
    }

    private fun vocabularyLines(): List<String> {
        val vocabulary = finalTraining.vocabulary
        val lines = mutableListOf("documents ${training.size} terms ${vocabulary.termCount} candidates ${vocabulary.candidateCount} vocabulary ${vocabulary.size}")
        for ((i, entry) in vocabulary.ranking.withIndex()) lines.add("${i + 1} ${entry.term} ${entry.frequency} ${realText(entry.score)} ${classes[entry.bestClass]}")
        return lines
    }

    private fun cvLines(): List<String> {
        val lines = mutableListOf("model,alpha,correct,accuracy,macro_f1,selected")
        for (model in 0 until 3) for (a in settings.alphas.indices) {
            val chosen = if (selected[model] == settings.alphas[a]) "yes" else "no"
            lines.add("${models[model]},${hundredthsText(settings.alphas[a])},${evaluationFields(cvRuns[model][a].evaluation)},$chosen")
        }
        lines.add("rocchio,-,${evaluationFields(cvRuns[3][0].evaluation)},yes")
        return lines
    }

    private fun predictionLines(): List<String> {
        val lines = mutableListOf("id,model,label,score")
        for (i in tests.indices) for (model in models.indices) lines.add(csv(tests[i].name, models[model], classes[predictions[model][i].label], realText(predictions[model][i].score)))
        return lines
    }

    private fun curveLines(): List<String> {
        val lines = mutableListOf("size,vocabulary,model,correct,accuracy,macro_f1")
        for (size in settings.curve) {
            val fit = trained(training.take(size), settings.bigrams, settings.features)
            val evaluations = testEvaluations(fit)
            for (model in 0 until 4) lines.add(csv(size, fit.vocabulary.size, models[model]) + "," + evaluationFields(evaluations[model]))
        }
        return lines
    }

    private fun featureLines(): List<String> {
        val lines = mutableListOf("terms,features,vocabulary,model,correct,accuracy,macro_f1")
        for (bigrams in listOf(false, true)) for (size in settings.sizes) {
            val fit = trained(training, bigrams, size)
            val evaluations = testEvaluations(fit)
            for (model in 0 until 4) lines.add(csv(if (bigrams) "bigrams" else "unigrams", size, fit.vocabulary.size, models[model]) + "," + evaluationFields(evaluations[model]))
        }
        return lines
    }

    private fun classCounts(counts: IntArray): String = classes.indices.joinToString(" ") { "${classes[it]} ${counts[it]}" }

    private fun dataPart(): List<String> {
        val vocabulary = finalTraining.vocabulary
        val lines = mutableListOf("documents train ${training.size} test ${tests.size} labelled ${labelled.size} unlabelled ${unlabelled.size} classes $classCount")
        val trainCounts = IntArray(classCount)
        val testCounts = IntArray(classCount)
        for (document in training) trainCounts[document.label]++
        for (truth in truths) testCounts[truth]++
        for (c in classes.indices) lines.add("class ${classes[c]} train ${trainCounts[c]} test ${testCounts[c]}")
        var raw = 0
        var stop = 0
        var shortWords = 0
        var kept = 0
        var bigramCount = 0
        val terms = mutableSetOf<String>()
        for (document in training) {
            val tokens = document.tokens
            raw += tokens.rawCount; stop += tokens.stopwordCount; shortWords += tokens.shortCount; kept += tokens.words.size
            if (settings.bigrams) bigramCount += tokens.bigrams.size
            terms.addAll(tokens.terms(settings.bigrams))
        }
        val distinctBigrams = terms.count { '_' in it }
        lines.add("train_tokens raw $raw stopwords $stop short $shortWords unigrams $kept bigrams $bigramCount")
        lines.add("train_terms unigrams ${terms.size - distinctBigrams} bigrams $distinctBigrams candidates ${vocabulary.candidateCount} vocabulary ${vocabulary.size}")
        var total = 0
        var inVocabulary = 0
        val oov = mutableMapOf<String, Int>()
        for (i in tests.indices) {
            total += tests[i].tokens.terms(settings.bigrams).size; inVocabulary += testSequences[i].size
            for (word in tests[i].tokens.words) if (word !in vocabulary.index) oov[word] = oov.getOrDefault(word, 0) + 1
        }
        lines.add("test_terms total $total in_vocabulary $inVocabulary")
        val ranked = oov.keys.sortedWith(compareByDescending<String> { oov.getValue(it) }.thenBy { it })
        val tail = mutableListOf("test_oov")
        for (word in ranked.take(settings.top)) tail.add("$word ${oov.getValue(word)}")
        lines.add(tail.joinToString(" "))
        return lines
    }

    private fun foldsPart(): List<String> {
        val lines = mutableListOf("folds 5")
        for ((i, fold) in folds.withIndex()) lines.add("fold ${i + 1} train ${fold.training} validate ${fold.validation} candidates ${fold.candidates} vocabulary ${fold.vocabulary}")
        return lines
    }

    private fun selectionPart(): List<String> {
        val lines = mutableListOf("selection")
        for (model in 0 until 4) {
            val run = selectedRuns[model]
            lines.add("${models[model]} alpha ${alphaText(model)} correct ${proportionText(run.evaluation.correct, run.evaluation.total)} macro_f1 ${realText(run.evaluation.macroF1)} folds ${run.foldCorrect.joinToString(" ")}")
        }
        return lines
    }

    private fun crossValidationPart(model: Int): List<String> =
        listOf("cross_validation ${models[model]} alpha ${alphaText(model)}") + selectedRuns[model].evaluation.lines(classes)

    private fun testPart(model: Int): List<String> {
        val predicted = labelled.map { predictions[model][it].label }.toIntArray()
        val evaluation = Evaluation(classCount, truths, predicted)
        val lines = mutableListOf("test ${models[model]} alpha ${alphaText(model)}", "labelled ${labelled.size} correct ${proportionText(evaluation.correct, labelled.size)}")
        if (model < 4) {
            var topTwo = 0
            for (i in labelled.indices) { val order = predictions[model][labelled[i]].ranking; if (truths[i] == order[0] || truths[i] == order[1]) topTwo++ }
            lines.add("top2 ${proportionText(topTwo, labelled.size)}")
        }
        lines.addAll(evaluation.lines(classes))
        return lines
    }

    private fun probabilityPart(model: Int): List<String> {
        val length = settings.thresholds.size
        val rows = IntArray(length + 1)
        val hits = IntArray(length + 1)
        val accepted = IntArray(length)
        val acceptedHits = IntArray(length)
        val sums = DoubleArray(length + 1)
        var loss = 0.0
        var brier = 0.0
        for (i in labelled.indices) {
            val prediction = predictions[model][labelled[i]]
            loss += ln(prediction.normalizer) - (prediction.scores[truths[i]] - prediction.scores[prediction.label])
            var squares = 0.0
            for (c in classes.indices) { val delta = prediction.probabilities[c] - if (c == truths[i]) 1.0 else 0.0; squares += delta * delta }
            brier += squares
            var bucket = 0
            for (t in 0 until length) if (prediction.score >= settings.thresholds[t] / 100.0) { bucket++; accepted[t]++; if (correct[model][i]) acceptedHits[t]++ }
            rows[bucket]++; sums[bucket] += prediction.score; if (correct[model][i]) hits[bucket]++
        }
        val lines = mutableListOf("probability ${models[model]} alpha ${alphaText(model)}", "log_loss ${realText(loss / labelled.size)} brier ${realText(brier / labelled.size)}")
        for (bucket in 0..length) {
            var line = "bin ${hundredthsText(if (bucket == 0) 0 else settings.thresholds[bucket - 1])} rows ${rows[bucket]}"
            if (rows[bucket] > 0) line += " correct ${proportionText(hits[bucket], rows[bucket])} mean ${realText(sums[bucket] / rows[bucket])}"
            lines.add(line)
        }
        for (t in 0 until length) {
            val precise = if (accepted[t] == 0) "-" else proportionText(acceptedHits[t], accepted[t])
            lines.add("threshold ${hundredthsText(settings.thresholds[t])} covered ${proportionText(accepted[t], labelled.size)} correct $precise")
        }
        return lines
    }

    private fun lengthsPart(): List<String> {
        val rows = IntArray(settings.lengths.size + 1)
        val hits = Array(5) { IntArray(rows.size) }
        for (i in labelled.indices) {
            var bucket = 0
            for (boundary in settings.lengths) if (testSequences[labelled[i]].size >= boundary) bucket++
            rows[bucket]++
            for (model in models.indices) if (correct[model][i]) hits[model][bucket]++
        }
        val lines = mutableListOf("lengths")
        for (bucket in rows.indices) {
            var line = "length ${if (bucket == 0) 0 else settings.lengths[bucket - 1]} rows ${rows[bucket]}"
            if (rows[bucket] > 0) for (model in models.indices) line += " ${models[model]} ${proportionText(hits[model][bucket], rows[bucket])}"
            lines.add(line)
        }
        return lines
    }

    private fun comparisonPart(): List<String> {
        val lines = mutableListOf("comparison")
        for (first in 0 until 4) for (second in first + 1 until 4) {
            var agree = 0
            var b = 0
            var c = 0
            for (i in tests.indices) if (predictions[first][i].label == predictions[second][i].label) agree++
            for (i in labelled.indices) { if (correct[first][i] && !correct[second][i]) b++; if (correct[second][i] && !correct[first][i]) c++ }
            val delta = max(0, abs(b - c) - 1).toLong()
            val statistic = fractionText(if (b + c == 0) 0L else delta * delta, if (b + c == 0) 1L else (b + c).toLong())
            lines.add("${models[first]} ${models[second]} agree ${proportionText(agree, tests.size)} b $b c $c statistic $statistic")
        }
        val errors = IntArray(5)
        for (i in labelled.indices) { var wrong = 0; for (model in 0 until 4) if (!correct[model][i]) wrong++; errors[wrong]++ }
        lines.add("errors " + errors.indices.joinToString(" ") { "$it ${errors[it]}" })
        return lines
    }

    private fun bootstrapPart(): List<String> {
        val count = labelled.size
        val repetitions = settings.resamples
        var state = settings.seed
        val totals = Array(5) { IntArray(repetitions) }
        for (r in 0 until repetitions) for (draw in 0 until count) {
            state = 48271 * state % 2147483647
            val chosen = (state % count).toInt()
            for (model in models.indices) if (correct[model][chosen]) totals[model][r]++
        }
        val lines = mutableListOf("bootstrap resamples $repetitions seed ${settings.seed}")
        val tail = repetitions / 40
        for (model in models.indices) {
            val ordered = totals[model].sorted()
            val sum = ordered.sumOf { it.toLong() }
            lines.add("${models[model]} mean ${realText(sum.toDouble() / (repetitions.toLong() * count))} low ${proportionText(ordered[tail], count)} high ${proportionText(ordered[repetitions - 1 - tail], count)}")
        }
        for (first in 0 until 4) for (second in first + 1 until 4) {
            var wins = 0
            var ties = 0
            var losses = 0
            for (r in 0 until repetitions) { if (totals[first][r] > totals[second][r]) wins++ else if (totals[first][r] == totals[second][r]) ties++ else losses++ }
            lines.add("pair ${models[first]} ${models[second]} wins $wins ties $ties losses $losses")
        }
        return lines
    }

    private fun hardPart(): List<String> {
        val hard = mutableListOf<Int>()
        val counts = IntArray(classCount)
        for (i in training.indices) {
            if ((0 until 4).all { selectedRuns[it].predictions[i] != training[i].label }) { hard.add(i); counts[training[i].label]++ }
        }
        val lines = mutableListOf("hard_documents ${hard.size} ${classCounts(counts)}")
        for (i in hard.take(settings.top)) {
            val names = (0 until 4).joinToString(" ") { classes[selectedRuns[it].predictions[i]] }
            lines.add("${training[i].name} true ${classes[training[i].label]} predicted $names")
        }
        return lines
    }

    private fun uncertainPart(): List<String> {
        val order = tests.indices.sortedWith(compareBy<Int> { rounded(predictions[0][it].margin) }.thenBy { it }).take(settings.top)
        val lines = mutableListOf("uncertain multinomial ${order.size}")
        for (i in order) {
            val document = tests[i]
            val prediction = predictions[0][i]
            val truth = if (document.label < 0) "?" else classes[document.label]
            lines.add("${document.name} predicted ${classes[prediction.label]} runner_up ${classes[prediction.ranking[1]]} margin ${realText(prediction.margin)} posterior ${realText(prediction.score)} true $truth")
        }
        return lines
    }

    private fun misclassifiedPart(): List<String> {
        val wrong = labelled.filter { predictions[0][it].label != tests[it].label }
        val lines = mutableListOf("misclassified multinomial ${wrong.size}")
        for (i in wrong) {
            val document = tests[i]
            val prediction = predictions[0][i]
            lines.add("${document.name} true ${classes[document.label]} predicted ${classes[prediction.label]} posterior ${realText(prediction.score)}")
            val frequencies = IntArray(finalTraining.vocabulary.size)
            for (term in testSequences[i]) frequencies[term]++
            val entries = firstOccurrences(testSequences[i]).map { term ->
                Ratio(100 * finalTraining.counts.occurrences[prediction.label][term] + selected[0], 100 * finalTraining.counts.occurrences[document.label][term] + selected[0], term)
            }
            for (entry in rankedRatios(entries).take(3)) {
                val term = entry.term
                val evidence = finalTraining.classifiers[0].weights[prediction.label][term] - finalTraining.classifiers[0].weights[document.label][term]
                lines.add("  ${finalTraining.vocabulary.terms[term]} count ${frequencies[term]} evidence ${realText(evidence)}")
            }
        }
        return lines
    }

    private fun maximization(posteriors: Array<Prediction>, sequences: Array<IntArray>): NaiveBayes {
        val counts = finalTraining.counts
        val size = counts.vocabularySize
        val occurrences = Array(classCount) { c -> DoubleArray(size) { counts.occurrences[c][it].toDouble() } }
        val documents = DoubleArray(classCount) { counts.documents[it].toDouble() }
        val weight = settings.weight / 100.0
        for (i in sequences.indices) {
            val frequencies = IntArray(size)
            for (term in sequences[i]) frequencies[term]++
            val terms = firstOccurrences(sequences[i])
            for (c in classes.indices) {
                val share = weight * posteriors[i].probabilities[c]
                documents[c] += share
                for (term in terms) occurrences[c][term] += share * frequencies[term]
            }
        }
        val weights = Array(classCount) { DoubleArray(size) }
        val priors = DoubleArray(classCount)
        val scale = training.size + settings.weight.toLong() * unlabelled.size / 100.0
        for (c in classes.indices) {
            var total = 0.0
            for (value in occurrences[c]) total += value
            for (t in 0 until size) weights[c][t] = NaiveBayes.smoothedLog(occurrences[c][t], total, selected[0], size)
            priors[c] = ln(documents[c] / scale)
        }
        return NaiveBayes(0, priors, DoubleArray(classCount), weights)
    }

    private fun semiSupervisedPart(): List<String> {
        val sequences = unlabelled.map(finalTraining::encode).toTypedArray()
        var model = finalTraining.classifiers[0]
        var previous: IntArray? = null
        val lines = mutableListOf("semi_supervised multinomial alpha ${alphaText(0)} weight ${hundredthsText(settings.weight)} unlabelled ${unlabelled.size}")
        for (iteration in 0..settings.iterations) {
            val posteriors = Array(sequences.size) { model.predict(sequences[it]) }
            val assignments = IntArray(sequences.size) { posteriors[it].label }
            val assigned = IntArray(classCount)
            var changed = 0
            for (i in assignments.indices) { assigned[assignments[i]]++; if (previous != null && previous[i] != assignments[i]) changed++ }
            val predicted = labelled.map { model.predict(testSequences[it]).label }.toIntArray()
            val evaluation = Evaluation(classCount, truths, predicted)
            val changeText = if (previous == null) "-" else changed.toString()
            lines.add("iteration $iteration correct ${proportionText(evaluation.correct, evaluation.total)} macro_f1 ${realText(evaluation.macroF1)} changed $changeText assigned ${classCounts(assigned)}")
            if (iteration < settings.iterations) model = maximization(posteriors, sequences)
            previous = assignments
        }
        return lines
    }

    private fun metricsLines(): List<String> {
        val parts = mutableListOf(dataPart(), foldsPart(), selectionPart())
        for (model in 0 until 4) parts.add(crossValidationPart(model))
        for (model in models.indices) parts.add(testPart(model))
        for (model in 0 until 3) parts.add(probabilityPart(model))
        parts.add(lengthsPart()); parts.add(comparisonPart()); parts.add(bootstrapPart()); parts.add(hardPart()); parts.add(uncertainPart()); parts.add(misclassifiedPart()); parts.add(semiSupervisedPart())
        return joinParts(parts)
    }

    private fun topFeatureLines(): List<String> {
        val parts = mutableListOf<List<String>>()
        val counts = finalTraining.counts
        val size = counts.vocabularySize
        for (model in 0 until 2) {
            val table = if (model == 0) counts.occurrences else counts.containing
            val totals = if (model == 0) counts.totals else counts.documents
            val overall = if (model == 0) counts.total else counts.documentTotal.toLong()
            val outcomes = if (model == 0) size else 2
            val termTotals = LongArray(size)
            for (t in 0 until size) for (c in classes.indices) termTotals[t] += table[c][t]
            parts.add(listOf("model ${models[model]} alpha ${alphaText(model)} vocabulary $size top ${settings.top}"))
            for (c in classes.indices) {
                val total = totals[c]
                val other = overall - total
                val lines = mutableListOf("class ${classes[c]} total $total other $other")
                val entries = (0 until size).map { t -> Ratio(100 * table[c][t] + selected[model], 100 * (termTotals[t] - table[c][t]) + selected[model], t) }
                for ((rank, entry) in rankedRatios(entries).take(settings.top).withIndex()) {
                    val term = entry.term
                    val count = table[c][term]
                    val otherCount = termTotals[term] - count
                    val odds = NaiveBayes.smoothedLog(count, total, selected[model], outcomes) - NaiveBayes.smoothedLog(otherCount, other, selected[model], outcomes)
                    lines.add("${rank + 1} ${finalTraining.vocabulary.terms[term]} $count $otherCount ${realText(odds)}")
                }
                parts.add(lines)
            }
        }
        return joinParts(parts)
    }

    fun writeOutputs() {
        Files.createDirectories(Path.of("output"))
        val files = linkedMapOf(
            "vocabulary.txt" to vocabularyLines(), "cv_results.csv" to cvLines(), "predictions.csv" to predictionLines(),
            "learning_curve.csv" to curveLines(), "feature_study.csv" to featureLines(), "metrics.txt" to metricsLines(), "top_features.txt" to topFeatureLines()
        )
        for ((name, lines) in files) Files.writeString(Path.of("output", name), lines.joinToString("\n") + "\n", StandardCharsets.US_ASCII)
    }
}

fun main() {
    val experiment = Experiment()
    experiment.run()
    experiment.writeOutputs()
}
