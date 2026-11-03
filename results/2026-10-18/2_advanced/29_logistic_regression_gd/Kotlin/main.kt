import java.nio.charset.StandardCharsets
import java.nio.file.Files
import java.nio.file.Path
import kotlin.math.abs
import kotlin.math.exp
import kotlin.math.floor
import kotlin.math.ln
import kotlin.math.sqrt

private fun f(value: Double): String = Metrics.fixed(value, 4)
private fun six(value: Double): String = Metrics.fixed(value, 6)
private fun norm(values: DoubleArray): Double {
    var total = 0.0;
    for (value in values) total += value * value;
    return sqrt(total)
}
private fun reals(values: DoubleArray, places: Int): String = values.joinToString(" ") {
    Metrics.fixed(it, places)
}
private fun probabilities(weights: DoubleArray, vectors: Array<DoubleArray>): DoubleArray = vectors.map {
    Logistic.probability(Logistic.score(weights, it))
}.toDoubleArray()
private fun targets(rows: List<Example>, positive: Int): IntArray = rows.map {
    if (it.label == positive) 1 else 0
}.toIntArray()
private fun weights(checkpoints: List<Checkpoint>): DoubleArray = checkpoints.last().weights
private fun inverse(matrix: Array<DoubleArray>): Array<DoubleArray> {
    val lower = Optimizers.cholesky(matrix);
    val result = Array(matrix.size) {
        DoubleArray(matrix.size)
    }
    for (k in matrix.indices) {
        val unit = DoubleArray(matrix.size);
        unit[k] = 1.0;
        val solution = Optimizers.solve(lower, unit);
        for (j in matrix.indices) result[j][k] = solution[j]
    }
    return result
}
private fun original(weights: DoubleArray, statistics: Statistics): DoubleArray {
    val values = weights.copyOf();
    var adjustment = 0.0;
    for (j in 1 until values.size) {
        values[j] = weights[j] / statistics.deviations[j - 1];
        adjustment += values[j] * statistics.means[j - 1]
    };
    values[0] = weights[0] - adjustment;
    return values
}
private fun subset(rows: Array<DoubleArray>, indices: List<Int>, count: Int): Array<DoubleArray> = indices.map {
    rows[it].copyOf(count)
}.toTypedArray()
private fun subset(values: IntArray, indices: List<Int>): IntArray = indices.map {
    values[it]
}.toIntArray()
private fun first(rows: Array<DoubleArray>, count: Int): Array<DoubleArray> = rows.map {
    it.copyOf(count)
}.toTypedArray()
private data class CrossValidation(val lambda: Double, val folds: DoubleArray, val loss: Double, val probabilities: DoubleArray, val errors: Int)
private class Influence(weights: DoubleArray, vectors: Array<DoubleArray>, targets: IntArray, lambda: Double) {
    val matrix = inverse(Logistic.hessian(weights, vectors, lambda))
    val probabilities = DoubleArray(vectors.size)
    val leverages = DoubleArray(vectors.size)
    val residuals = DoubleArray(vectors.size)
    val distances = DoubleArray(vectors.size)
    val edf: Double
    val deviance = 2 * vectors.size * Logistic.average(weights, vectors, targets)
    val aic: Double
    val bic: Double
    init {
        val count = vectors.size;
        val size = weights.size
        for (i in vectors.indices) {
            val probability = Logistic.probability(Logistic.score(weights, vectors[i]));
            val variance = probability * (1 - probability);
            var quadratic = 0.0
            for (j in 0 until size) for (k in 0 until size) quadratic += vectors[i][j] * matrix[j][k] * vectors[i][k]
            val leverage = variance * quadratic / count;
            val pearson = (targets[i] - probability) / sqrt(variance)
            probabilities[i] = probability;
            leverages[i] = leverage;
            residuals[i] = pearson / sqrt(1 - leverage);
            distances[i] = pearson * pearson * leverage / (size * ((1 - leverage) * (1 - leverage)))
        }
        edf = leverages.sum();
        aic = deviance + 2 * edf;
        bic = deviance + ln(count.toDouble()) * edf
    }
}
private class Bin {
    var count = 0;
    var hits = 0;
    var total = 0.0
}
private fun bins(probabilities: DoubleArray, hits: IntArray): Array<Bin> {
    val bins = Array(10) {
        Bin()
    }
    for (i in probabilities.indices) {
        val bin = bins[minOf(9, floor(probabilities[i] * 10).toInt())];
        bin.count++;
        bin.total += probabilities[i];
        bin.hits += hits[i]
    }
    return bins
}
private fun binLines(bins: Array<Bin>, mean: String, rate: String): List<String> = bins.mapIndexed {
    k, bin -> "bin ${Metrics.fixed(k / 10.0, 1)}-${Metrics.fixed((k + 1) / 10.0, 1)} count ${bin.count} $mean ${if (bin.count == 0) "-" else f(bin.total / bin.count)} $rate ${Metrics.ratio(bin.hits, bin.count)}"
}
private fun calibrationError(bins: Array<Bin>, count: Int): Double {
    var total = 0.0;
    for (bin in bins) if (bin.count > 0) total += abs(bin.total - bin.hits);
    return total / count
}
private class Model(val name: String, val checkpoints: List<Checkpoint>, study: Study) {
    val weights = weights(checkpoints)
    val trainProbabilities = probabilities(weights, study.x)
    val testProbabilities = probabilities(weights, study.z)
    val roc = Metrics.roc(testProbabilities, study.testTargets)
}
private class Study(val data: Dataset) {
    val n = data.train.size;
    val m = data.test.size;
    val p = data.features.size;
    val d = data.names.size
    val positive = data.integer("POSITIVE", 0);
    val threshold = data.number("THRESHOLD", 0);
    val softLambda = data.number("SOFTMAX", 2)
    val labels = data.train.map {
        it.label
    }.toIntArray();
    val testLabels = data.test.map {
        it.label
    }.toIntArray();
    val classes = labels.max() + 1
    val trainTargets = targets(data.train, positive);
    val testTargets = targets(data.test, positive)
    val trainExpanded = data.expanded(data.train);
    val testExpanded = data.expanded(data.test);
    val statistics = Dataset.statistics(trainExpanded, p)
    val x = Dataset.standardize(trainExpanded, statistics, p);
    val z = Dataset.standardize(testExpanded, statistics, p)
    val lambdas = data.settings.getValue("LAMBDAS").map {
        it.toDouble()
    }.toDoubleArray()
    val crossValidations = lambdas.map {
        crossValidate(it, p)
    }
    val selected: CrossValidation
    val lambda: Double
    val oneSe: Double
    val standardError: Double
    val models: List<Model>
    val newton: Model
    val influence: Influence
    val softCheckpoints: List<SoftCheckpoint>
    val softWeights: Array<DoubleArray>
    val softProbabilities: Array<DoubleArray>
    val softPredictions: IntArray
    init {
        var best = crossValidations.first();
        for (result in crossValidations) if (result.loss <= best.loss) best = result
        selected = best;
        lambda = best.lambda
        val mean = best.folds.sum() / 5;
        var spread = 0.0;
        for (value in best.folds) spread += (value - mean) * (value - mean)
        standardError = sqrt(spread / 4) / sqrt(5.0);
        oneSe = crossValidations.filter {
            it.loss <= selected.loss + standardError
        }.maxOf {
            it.lambda
        }
        val gd = Model("gd", Optimizers.gd(x, trainTargets, lambda, data.number("GD", 0), data.integer("GD", 1)), this)
        val sgd = Model("sgd", Optimizers.sgd(x, trainTargets, lambda, data.number("SGD", 0),
             data.integer("SGD", 1), data.integer("SGD", 2), data.integer("SGD", 3)), this)
        newton = Model("newton", Optimizers.newton(x, trainTargets, lambda), this);
        models = listOf(gd, sgd, newton);
        influence = Influence(newton.weights, x, trainTargets, lambda)
        softCheckpoints = Softmax.train(x, labels, classes, softLambda, data.number("SOFTMAX", 0), data.integer("SOFTMAX", 1));
        softWeights = softCheckpoints.last().weights
        softProbabilities = Array(m) {
            Softmax.probabilities(softWeights, z[it])
        };
        softPredictions = IntArray(m) {
            Softmax.prediction(softProbabilities[it])
        }
    }
    fun crossValidate(lambda: Double, count: Int): CrossValidation {
        val folds = DoubleArray(5);
        val losses = DoubleArray(n);
        val probabilities = DoubleArray(n);
        var errors = 0
        for (fold in 0 until 5) {
            val training = (0 until n).filter {
                it % 5 != fold
            };
            val validation = (0 until n).filter {
                it % 5 == fold
            }
            val expanded = subset(trainExpanded, training, count);
            val local = Dataset.statistics(expanded, count);
            val vectors = Dataset.standardize(expanded, local, count);
            val weights = weights(Optimizers.newton(vectors, subset(trainTargets, training), lambda));
            var total = 0.0
            for (i in validation) {
                val score = Logistic.score(weights, Dataset.standardize(trainExpanded[i], local, count));
                losses[i] = Logistic.loss(score, trainTargets[i]);
                probabilities[i] = Logistic.probability(score);
                total += losses[i];
                if ((if (probabilities[i] >= threshold) 1 else 0) != trainTargets[i]) errors++
            }
            folds[fold] = total / validation.size
        }
        return CrossValidation(lambda, folds, losses.sum() / n, probabilities, errors)
    }
    fun vector(values: DoubleArray): DoubleArray = Dataset.standardize(data.expanded(values), statistics, p)
    fun correct(probabilities: DoubleArray, targets: IntArray): Int = Metrics.confusion(probabilities, targets, threshold).correct
    fun softCorrect(vectors: Array<DoubleArray>, labels: IntArray): Int = vectors.indices.count {
        Softmax.prediction(Softmax.probabilities(softWeights, vectors[it])) == labels[it]
    }
    fun terms(weights: DoubleArray): List<String> {
        val original = original(weights, statistics);
        return weights.indices.map {
            "term ${if (it == 0) "intercept" else data.features[it - 1]} standardized ${f(weights[it])} original ${f(original[it])}"
        }
    }
    fun weightLines(): List<String> {
        val parts = mutableListOf<List<String>>();
        val correlation = Array(p) {
            DoubleArray(p)
        }
        for (j in 0 until p) for (k in 0 until p) {
            var total = 0.0;
            for (row in x) total += row[j + 1] * row[k + 1];
            correlation[j][k] = total / (n - 1)
        }
        val inverse = inverse(correlation);
        var lines = mutableListOf("features $d degree ${data.integer("DEGREE", 0)} expanded $p", "standardization")
        for (j in 0 until p) lines.add("${data.features[j]} mean ${six(statistics.means[j])} sd ${six(statistics.deviations[j])} vif ${f(inverse[j][j])}")
        lines.add("correlation");
        for (row in correlation) lines.add(reals(row, 4));
        parts.add(lines)
        for (model in models) {
            lines = mutableListOf("model ${model.name} lambda ${f(lambda)}");
            lines.addAll(terms(model.weights));
            lines.add("norm ${f(sqrt(Logistic.penalty(model.weights)))}");
            if (model.name != "newton") lines.add("distance_to_newton ${six(norm(DoubleArray(p + 1) { model.weights[it] - newton.weights[it] }))}");
            parts.add(lines)
        }
        lines = mutableListOf("coefficients newton lambda ${f(lambda)}")
        for (j in 0..p) {
            val weight = newton.weights[j];
            val error = sqrt(influence.matrix[j][j] / n);
            lines.add("${if (j == 0) "intercept" else data.features[j - 1]} weight ${f(weight)} se ${f(error)} z ${f(weight / error)} lower ${f(weight - 1.96 * error)} upper ${f(weight + 1.96 * error)} odds_ratio ${f(exp(weight))}")
        };
        parts.add(lines)
        lines = mutableListOf("model softmax lambda ${f(softLambda)}");
        for (k in 0 until classes) {
            lines.add("class $k");
            lines.addAll(terms(softWeights[k]))
        };
        parts.add(lines)
        return join(parts)
    }
    fun traceLines(): List<String> {
        val lines = mutableListOf("optimizer,iteration,loss,gradient_norm,test_loss")
        for (model in models) for (checkpoint in model.checkpoints) lines.add("${model.name},${checkpoint.iteration},${six(Logistic.objective(checkpoint.weights, x, trainTargets, lambda))},${six(norm(Logistic.gradient(checkpoint.weights, x, trainTargets, lambda)))},${six(Logistic.average(checkpoint.weights, z, testTargets))}")
        for (checkpoint in softCheckpoints) {
            val gradient = Softmax.gradient(checkpoint.weights, x, labels, softLambda);
            var squares = 0.0;
            for (row in gradient) for (value in row) squares += value * value;
            lines.add("softmax,${checkpoint.iteration},${six(Softmax.objective(checkpoint.weights, x, labels, softLambda))},${six(sqrt(squares))},${six(Softmax.average(checkpoint.weights, z, testLabels))}")
        }
        return lines
    }
    fun predictionLines(): List<String> {
        val lines = mutableListOf("id,model,probability,predicted,actual")
        for (model in models) for (i in 0 until m) lines.add("${data.test[i].id},${model.name},${six(model.testProbabilities[i])},${if (model.testProbabilities[i] >= threshold) 1 else 0},${testTargets[i]}")
        for (i in 0 until m) lines.add("${data.test[i].id},softmax,${six(softProbabilities[i][softPredictions[i]])},${softPredictions[i]},${testLabels[i]}")
        return lines
    }
    fun rocLines(): List<String> {
        val lines = mutableListOf("model,threshold,tpr,fpr,precision");
        val positive = testTargets.sum();
        val negative = m - positive
        for (model in models) {
            lines.add("${model.name},inf,0.0000,0.0000,-");
            for (point in model.roc) lines.add("${model.name},${six(point.threshold)},${Metrics.ratio(point.tp, positive)},${Metrics.ratio(point.fp, negative)},${Metrics.ratio(point.tp, point.tp + point.fp)}")
        }
        return lines
    }
    fun dataPart(): List<String> {
        val trainCounts = IntArray(classes);
        val testCounts = IntArray(classes);
        for (label in labels) trainCounts[label]++;
        for (label in testLabels) testCounts[label]++
        return listOf("data train $n test $m base_features $d degree ${data.integer("DEGREE", 0)} features $p",
             "binary positive_class $positive train ${trainTargets.sum()}/$n test ${testTargets.sum()}/$m",
             "classes $classes train ${trainCounts.joinToString(" ")} test ${testCounts.joinToString(" ")}")
    }
    fun cvPart(): List<String> {
        val lines = mutableListOf("cross_validation folds 5 newton_iterations 10")
        for (result in crossValidations) lines.add("lambda ${f(result.lambda)} fold_loss ${reals(result.folds, 6)} cv_loss ${six(result.loss)} errors ${result.errors}/$n")
        lines.add("selected lambda ${f(lambda)} cv_loss ${six(selected.loss)} se ${six(standardError)} lambda_1se ${f(oneSe)}")
        val c = Metrics.confusion(selected.probabilities, trainTargets, threshold)
        lines.add("out_of_fold tp ${c.tp} fp ${c.fp} tn ${c.tn} fn ${c.fn} accuracy ${Metrics.ratio(c.correct, n)} auc ${Metrics.auc(selected.probabilities, trainTargets)}")
        return lines
    }
    fun lambdaPart(): List<String> {
        val lines = mutableListOf("lambda_path")
        for (lambda in lambdas) {
            val weights = weights(Optimizers.newton(x, trainTargets, lambda));
            lines.add("lambda ${f(lambda)} objective ${six(Logistic.objective(weights, x, trainTargets, lambda))} train_loss ${six(Logistic.average(weights, x, trainTargets))} test_loss ${six(Logistic.average(weights, z, testTargets))} train_accuracy ${Metrics.ratio(correct(probabilities(weights, x), trainTargets), n)} test_accuracy ${Metrics.ratio(correct(probabilities(weights, z), testTargets), m)} norm ${f(sqrt(Logistic.penalty(weights)))}")
        }
        return lines
    }
    fun degreePart(): List<String> {
        val lines = mutableListOf("degrees lambda ${f(lambda)}")
        for (degree in 1..data.integer("DEGREE", 0)) {
            val count = data.tuples.count {
                it.size <= degree
            };
            val train = first(x, count + 1);
            val test = first(z, count + 1);
            val weights = weights(Optimizers.newton(train, trainTargets, lambda));
            val influence = Influence(weights, train, trainTargets, lambda);
            val probabilities = probabilities(weights, test)
            lines.add("degree $degree features $count cv_loss ${six(crossValidate(lambda, count).loss)} train_loss ${six(Logistic.average(weights, train, trainTargets))} test_loss ${six(Logistic.average(weights, test, testTargets))} test_accuracy ${Metrics.ratio(correct(probabilities, testTargets), m)} auc ${Metrics.auc(probabilities, testTargets)} edf ${f(influence.edf)} aic ${f(influence.aic)} bic ${f(influence.bic)}")
        }
        return lines
    }
    fun learningPart(): List<String> {
        val lines = mutableListOf("learning_curve lambda ${f(lambda)}")
        for (k in 1..4) {
            val count = k * n / 4;
            val expanded = trainExpanded.take(count).toTypedArray();
            val targets = trainTargets.copyOf(count);
            val local = Dataset.statistics(expanded, p);
            val train = Dataset.standardize(expanded, local, p);
            val test = Dataset.standardize(testExpanded, local, p);
            val weights = weights(Optimizers.newton(train, targets, lambda));
            val probabilities = probabilities(weights, test);
            lines.add("size $count train_loss ${six(Logistic.average(weights, train, targets))} test_loss ${six(Logistic.average(weights, test, testTargets))} test_accuracy ${Metrics.ratio(correct(probabilities, testTargets), m)} auc ${Metrics.auc(probabilities, testTargets)}")
        }
        return lines
    }
    fun cost(point: RocPoint): Int = data.integer("COST", 0) * point.fp + data.integer("COST", 1) * (testTargets.sum() - point.tp)
    fun binaryPart(model: Model): List<String> {
        val c = Metrics.confusion(model.testProbabilities, testTargets, threshold);
        val positive = testTargets.sum();
        val negative = m - positive
        val lines = mutableListOf("model ${model.name} lambda ${f(lambda)}", "train correct ${correct(model.trainProbabilities, trainTargets)}/$n accuracy ${Metrics.ratio(correct(model.trainProbabilities, trainTargets), n)}",
             "test tp ${c.tp} fp ${c.fp} tn ${c.tn} fn ${c.fn}")
        lines.add("test accuracy ${Metrics.ratio(c.correct, m)} precision ${Metrics.ratio(c.tp, c.tp + c.fp)} recall ${Metrics.ratio(c.tp, c.tp + c.fn)} specificity ${Metrics.ratio(c.tn, c.tn + c.fp)} f1 ${Metrics.ratio(2 * c.tp, 2 * c.tp + c.fp + c.fn)}")
        var brier = 0.0;
        for (i in 0 until m) {
            val error = model.testProbabilities[i] - testTargets[i];
            brier += error * error
        }
        lines.add("log_loss ${six(Logistic.average(model.weights, z, testTargets))} brier ${six(brier / m)}")
        var ap = 0.0;
        var previous = 0;
        var youden = model.roc.first();
        var bestF1 = youden;
        var minCost = youden
        for (point in model.roc) {
            ap += ((point.tp - previous) * point.tp).toDouble() / (point.tp + point.fp);
            previous = point.tp
            if (point.tp * negative - point.fp * positive > youden.tp * negative - youden.fp * positive) youden = point
            if (point.tp.toLong() * (positive + bestF1.tp + bestF1.fp) > bestF1.tp.toLong() * (positive + point.tp + point.fp)) bestF1 = point
            if (cost(point) < cost(minCost)) minCost = point
        }
        lines.add("auc ${Metrics.auc(model.testProbabilities, testTargets)} average_precision ${f(ap / positive)}")
        lines.add("youden threshold ${six(youden.threshold)} tpr ${Metrics.ratio(youden.tp, positive)} fpr ${Metrics.ratio(youden.fp, negative)} j ${Metrics.ratio(youden.tp * negative - youden.fp * positive, positive * negative)}")
        lines.add("best_f1 threshold ${six(bestF1.threshold)} precision ${Metrics.ratio(bestF1.tp, bestF1.tp + bestF1.fp)} recall ${Metrics.ratio(bestF1.tp, positive)} f1 ${Metrics.ratio(2 * bestF1.tp, positive + bestF1.tp + bestF1.fp)}")
        lines.add("min_cost threshold ${six(minCost.threshold)} cost ${cost(minCost)} fp ${minCost.fp} fn ${positive - minCost.tp}")
        val bins = bins(model.testProbabilities, testTargets);
        lines.add("calibration");
        lines.addAll(binLines(bins, "mean_probability", "positive_rate"));
        var mce = 0.0;
        var hl = 0.0;
        var groups = 0
        for (bin in bins) if (bin.count > 0) {
            groups++;
            mce = maxOf(mce, abs(bin.total / bin.count - bin.hits.toDouble() / bin.count));
            hl += (bin.hits - bin.total) * (bin.hits - bin.total) / (bin.total * (1 - bin.total / bin.count))
        }
        lines.add("ece ${f(calibrationError(bins, m))} mce ${f(mce)} hosmer_lemeshow ${f(hl)} groups $groups");
        lines.add("gains");
        val order = Metrics.order(model.testProbabilities, true)
        for (g in 1..10) {
            val size = g * m / 10;
            var hits = 0;
            for (i in 0 until size) hits += testTargets[order[i]];
            lines.add("decile $g rows $size positives $hits gain ${Metrics.ratio(hits, positive)} lift ${Metrics.ratio(hits * m, size * positive)}")
        }
        return lines
    }
    fun comparisonPart(): List<String> {
        val lines = mutableListOf<String>()
        for ((a, b) in listOf(models[0] to models[1], models[0] to models[2], models[1] to models[2])) {
            var same = 0;
            var first = 0;
            var second = 0
            for (i in 0 until m) {
                val pa = if (a.testProbabilities[i] >= threshold) 1 else 0;
                val pb = if (b.testProbabilities[i] >= threshold) 1 else 0;
                if (pa == pb) same++ else if (pa == testTargets[i]) first++ else second++
            }
            val difference = abs(first - second) - 1;
            lines.add("agreement ${a.name} ${b.name} same $same/$m only_first $first only_second $second mcnemar ${Metrics.ratio(difference * difference, first + second)}")
        }
        return lines
    }
    fun slope(original: DoubleArray, values: DoubleArray, base: Int): Double {
        var total = 0.0
        for (j in 0 until p) {
            var occurrences = 0;
            var removed = false;
            var product = 1.0;
            for (index in data.tuples[j]) {
                if (index == base) occurrences++;
                if (index == base && !removed) removed = true else product *= values[index]
            };
            if (occurrences > 0) total += original[j + 1] * (occurrences * product)
        }
        return total
    }
    fun diagnosticsPart(): List<String> {
        val lines = mutableListOf("diagnostics newton lambda ${f(lambda)}");
        val positiveRate = trainTargets.sum().toDouble() / n;
        val nullLoss = -(positiveRate * ln(positiveRate) + (1 - positiveRate) * ln(1 - positiveRate));
        val loss = Logistic.average(newton.weights, x, trainTargets)
        lines.add("fit null_loss ${six(nullLoss)} train_loss ${six(loss)} mcfadden_r2 ${f(1 - loss / nullLoss)} deviance ${f(influence.deviance)} edf ${f(influence.edf)} aic ${f(influence.aic)} bic ${f(influence.bic)}")
        val order = Metrics.order(influence.probabilities, false);
        val groups = mutableListOf<String>();
        var hl = 0.0
        for (g in 1..10) {
            val start = (g - 1) * n / 10;
            val end = g * n / 10;
            var observed = 0;
            var expected = 0.0;
            for (i in start until end) {
                observed += trainTargets[order[i]];
                expected += influence.probabilities[order[i]]
            };
            hl += (observed - expected) * (observed - expected) / (expected * (1 - expected / (end - start)));
            groups.add("group $g rows ${end - start} observed $observed expected ${f(expected)}")
        }
        lines.add("hosmer_lemeshow_train groups 10 statistic ${f(hl)}");
        lines.addAll(groups);
        lines.add("newton_iterations")
        for (t in 1..10) {
            val weights = newton.checkpoints[t - 1].weights;
            val gradient = Logistic.gradient(weights, x, trainTargets, lambda);
            val step = Optimizers.solve(Optimizers.cholesky(Logistic.hessian(weights, x, lambda)), gradient);
            var total = 0.0;
            for (j in 0..p) total += gradient[j] * step[j];
            lines.add("iteration $t objective ${six(Logistic.objective(weights, x, trainTargets, lambda))} gradient_norm ${six(norm(gradient))} step_norm ${six(norm(step))} predicted_decrease ${six(total / 2)}")
        }
        val original = original(newton.weights, statistics);
        val means = statistics.means.copyOf(d);
        val atMean = Logistic.probability(Logistic.score(newton.weights, vector(means)))
        for (k in 0 until d) {
            var total = 0.0;
            for (i in 0 until n) total += influence.probabilities[i] * (1 - influence.probabilities[i]) * slope(original, data.train[i].values, k);
            lines.add("marginal ${data.names[k]} average ${f(total / n)} at_mean ${f(atMean * (1 - atMean) * slope(original, means, k))}")
        }
        for (k in 1..9) {
            val c = Metrics.confusion(newton.testProbabilities, testTargets, k / 10.0);
            lines.add("cut 0.$k positive ${c.tp + c.fp} tp ${c.tp} fp ${c.fp} precision ${Metrics.ratio(c.tp, c.tp + c.fp)} recall ${Metrics.ratio(c.tp, c.tp + c.fn)} accuracy ${Metrics.ratio(c.correct, m)}")
        }
        val distances = DoubleArray(m) {
            abs(newton.testProbabilities[it] - threshold)
        }
        for (i in Metrics.order(distances, true).filter {
            (if (newton.testProbabilities[it] >= threshold) 1 else 0) != testTargets[it]
        }.take(5)) lines.add("error ${data.test[i].id} actual ${testTargets[i]} probability ${six(newton.testProbabilities[i])}")
        val random = Minstd(data.integer("BOOTSTRAP", 1));
        val count = data.integer("BOOTSTRAP", 0);
        val aucs = mutableListOf<Fraction>();
        val values = DoubleArray(count)
        for (b in 0 until count) {
            val probabilities = DoubleArray(m);
            val targets = IntArray(m);
            for (i in 0 until m) {
                val index = random.draw() % m;
                probabilities[i] = newton.testProbabilities[index];
                targets[i] = testTargets[index]
            };
            val auc = Metrics.auc(probabilities, targets);
            aucs.add(auc);
            values[b] = auc.value
        }
        val mean = values.sum() / count;
        var squares = 0.0;
        for (value in values) squares += (value - mean) * (value - mean)
        aucs.sortWith {
            a, b -> (a.numerator * b.denominator).compareTo(b.numerator * a.denominator)
        }
        lines.add("bootstrap resamples $count seed ${data.integer("BOOTSTRAP", 1)} auc_mean ${f(mean)} auc_sd ${f(sqrt(squares / (count - 1)))} lower ${aucs[count / 40]} upper ${aucs[count - count / 40 - 1]}")
        val large = influence.residuals.count {
            abs(it) > 2
        };
        lines.add("influence effective_parameters ${f(influence.edf)} large_residuals $large")
        for (i in Metrics.order(influence.distances, true).take(5)) lines.add("cook ${data.train[i].id} actual ${trainTargets[i]} probability ${f(influence.probabilities[i])} leverage ${f(influence.leverages[i])} residual ${f(influence.residuals[i])} distance ${f(influence.distances[i])}")
        return lines
    }
    fun importancePart(): List<String> {
        val repeats = data.integer("PERMUTATION", 0);
        val random = Minstd(data.integer("PERMUTATION", 1));
        val baseline = Logistic.average(newton.weights, z, testTargets);
        val auc = Metrics.auc(newton.testProbabilities, testTargets)
        val lines = mutableListOf("importance repeats $repeats seed ${data.integer("PERMUTATION", 1)}",
             "baseline log_loss ${six(baseline)} auc $auc softmax_accuracy ${Metrics.ratio(softCorrect(z, testLabels), m)}")
        for (k in 0 until d) {
            var loss = 0.0;
            var numerators = 0L;
            var correct = 0
            repeat(repeats) {
                val order = IntArray(m) {
                    it
                };
                random.shuffle(order)
                val vectors = Array(m) {
                    i -> val values = data.test[i].values.copyOf();
                    values[k] = data.test[order[i]].values[k];
                    vector(values)
                }
                loss += Logistic.average(newton.weights, vectors, testTargets);
                numerators += Metrics.auc(probabilities(newton.weights, vectors), testTargets).numerator;
                correct += softCorrect(vectors, testLabels)
            }
            lines.add("feature ${data.names[k]} log_loss_increase ${six(loss / repeats - baseline)} auc ${Fraction(numerators, repeats * auc.denominator)} softmax_accuracy ${Metrics.ratio(correct, repeats * m)}")
        }
        return lines
    }
    fun minimums(): DoubleArray {
        val values = data.train.first().values.copyOf();
        for (row in data.train) for (j in 0 until d) values[j] = minOf(values[j], row.values[j]);
        return values
    }
    fun maximums(): DoubleArray {
        val values = data.train.first().values.copyOf();
        for (row in data.train) for (j in 0 until d) values[j] = maxOf(values[j], row.values[j]);
        return values
    }
    fun profilePart(): List<String> {
        val lines = mutableListOf("profiles");
        val low = minimums();
        val high = maximums()
        for (k in 0 until d) for (g in 0..4) {
            val values = statistics.means.copyOf(d);
            values[k] = low[k] + (high[k] - low[k]) * g / 4;
            val vector = vector(values);
            lines.add("profile ${data.names[k]} value ${f(values[k])} newton ${f(Logistic.probability(Logistic.score(newton.weights, vector)))} softmax ${reals(Softmax.probabilities(softWeights, vector), 4)}")
        }
        return lines
    }
    fun softmaxPart(): List<String> {
        val table = Array(classes) {
            IntArray(classes)
        };
        val rows = IntArray(classes);
        val columns = IntArray(classes);
        val hits = IntArray(m);
        val confidence = DoubleArray(m);
        val binary = DoubleArray(m);
        var correct = 0;
        var binaryAgreement = 0;
        var brier = 0.0;
        var binaryLoss = 0.0
        for (i in 0 until m) {
            val label = testLabels[i];
            val prediction = softPredictions[i];
            table[label][prediction]++;
            rows[label]++;
            columns[prediction]++
            if (label == prediction) {
                correct++;
                hits[i] = 1
            }
            confidence[i] = softProbabilities[i][prediction];
            binary[i] = softProbabilities[i][positive];
            binaryLoss += -ln(if (testTargets[i] == 1) binary[i] else 1 - binary[i])
            if ((binary[i] >= threshold) == (newton.testProbabilities[i] >= threshold)) binaryAgreement++
            var total = 0.0;
            for (k in 0 until classes) {
                val error = softProbabilities[i][k] - if (label == k) 1.0 else 0.0;
                total += error * error
            };
            brier += total
        }
        val lines = mutableListOf("softmax classes $classes lambda ${f(softLambda)} iterations ${data.integer("SOFTMAX", 1)}", "confusion")
        for (row in table) lines.add(row.joinToString(" "))
        var expected = 0L
        for (k in 0 until classes) {
            val scores = DoubleArray(m) {
                softProbabilities[it][k]
            };
            val targets = IntArray(m) {
                if (testLabels[it] == k) 1 else 0
            };
            lines.add("class $k precision ${Metrics.ratio(table[k][k], columns[k])} recall ${Metrics.ratio(table[k][k], rows[k])} f1 ${Metrics.ratio(2 * table[k][k], columns[k] + rows[k])} auc ${Metrics.auc(scores, targets)}");
            expected += rows[k] * columns[k]
        }
        lines.add("accuracy ${Metrics.ratio(correct, m)} kappa ${Metrics.ratio(m.toLong() * correct - expected, m.toLong() * m - expected)}")
        lines.add("log_loss ${six(Softmax.average(softWeights, z, testLabels))} brier ${six(brier / m)}")
        lines.add("binary_view positive_class $positive auc ${Metrics.auc(binary, testTargets)} log_loss ${six(binaryLoss / m)} accuracy ${Metrics.ratio(correct(binary, testTargets), m)} agreement_with_newton $binaryAgreement/$m")
        val bins = bins(confidence, hits);
        lines.add("confidence");
        lines.addAll(binLines(bins, "mean_confidence", "accuracy"));
        lines.add("ece ${f(calibrationError(bins, m))}")
        return lines
    }
    fun ovrPart(): List<String> {
        val lines = mutableListOf("one_vs_rest lambda ${f(softLambda)} newton_iterations 10");
        val scores = Array(classes) {
            DoubleArray(m)
        }
        for (k in 0 until classes) {
            val binaryTargets = targets(data.train, k);
            val weights = weights(Optimizers.newton(x, binaryTargets, softLambda));
            scores[k] = probabilities(weights, z);
            lines.add("class $k objective ${six(Logistic.objective(weights, x, binaryTargets, softLambda))} auc ${Metrics.auc(scores[k], targets(data.test, k))}")
        }
        var correct = 0;
        var agreement = 0
        for (i in 0 until m) {
            val best = (0 until classes).maxBy {
                scores[it][i]
            };
            if (best == testLabels[i]) correct++;
            if (best == softPredictions[i]) agreement++
        }
        lines.add("accuracy ${Metrics.ratio(correct, m)} agreement_with_softmax $agreement/$m")
        return lines
    }
    fun mapPart(): List<String> {
        val width = data.integer("MAP", 0);
        val height = data.integer("MAP", 1);
        val low = minimums();
        val high = maximums();
        val cells = IntArray(classes);
        val classMap = mutableListOf<String>();
        val probabilityMap = mutableListOf<String>()
        for (r in 0 until height) {
            val classRow = StringBuilder();
            val probabilityRow = StringBuilder()
            for (c in 0 until width) {
                val values = statistics.means.copyOf(d);
                values[0] = low[0] + (c + 0.5) * (high[0] - low[0]) / width;
                values[1] = high[1] - (r + 0.5) * (high[1] - low[1]) / height;
                val vector = vector(values);
                val prediction = Softmax.prediction(Softmax.probabilities(softWeights, vector));
                classRow.append(prediction);
                cells[prediction]++;
                probabilityRow.append(minOf(9, floor(Logistic.probability(Logistic.score(newton.weights, vector)) * 10).toInt()))
            }
            classMap.add(classRow.toString());
            probabilityMap.add(probabilityRow.toString())
        }
        val lines = mutableListOf("map ${data.names[0]} ${data.names[1]} width $width height $height", "softmax_classes");
        lines.addAll(classMap);
        lines.add("cells ${cells.joinToString(" ")}");
        lines.add("newton_probability");
        lines.addAll(probabilityMap)
        return lines
    }
    fun evaluationLines(): List<String> {
        val parts = mutableListOf(dataPart(), cvPart(), lambdaPart(), degreePart(), learningPart())
        for (model in models) parts.add(binaryPart(model))
        parts.add(comparisonPart());
        parts.add(diagnosticsPart());
        parts.add(importancePart());
        parts.add(profilePart());
        parts.add(softmaxPart());
        parts.add(ovrPart());
        parts.add(mapPart())
        return join(parts)
    }
}
private fun join(parts: List<List<String>>): List<String> {
    val lines = mutableListOf<String>();
    for (part in parts) {
        if (lines.isNotEmpty()) lines.add("");
        lines.addAll(part)
    };
    return lines
}
private fun write(name: String, lines: List<String>) {
    Files.writeString(Path.of("output", name), lines.joinToString("\n", postfix = "\n"), StandardCharsets.US_ASCII)
}
fun main() {
    val study = Study(Dataset());
    Files.createDirectories(Path.of("output"))
    write("weights.txt", study.weightLines());
    write("loss_trace.csv", study.traceLines());
    write("predictions.csv", study.predictionLines());
    write("evaluation.txt", study.evaluationLines());
    write("roc.csv", study.rocLines())
}
