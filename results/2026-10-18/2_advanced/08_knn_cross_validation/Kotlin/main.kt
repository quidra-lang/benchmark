import kotlin.math.abs

data class CrossValidation(val model: Model, val rows: List<Row>, val predictions: List<Prediction>) {
    val hits = predictions.zip(rows) { prediction, row -> prediction.label == row.label }
    val correct = hits.count { it }
    val rmse = rmse(predictions.zip(rows) { prediction, row -> prediction.estimate - row.target!! })
}
fun crossValidate(models: List<Model>, rows: List<Row>, folds: Int, features: List<Int>): List<CrossValidation> {
    val predictions = models.map { MutableList<Prediction?>(rows.size) { null } }
    val spaces = models.map { it.scaling to it.metric }.distinct()
    for (fold in stratifiedFolds(rows, folds)) {
        val training = foldTraining(rows, fold)
        val queries = fold.map { rows[it] }
        for ((scaling, metric) in spaces) {
            val orders = neighborOrders(training, queries, scaling, metric, features)
            for ((number, model) in models.withIndex()) if (model.scaling == scaling && model.metric == metric) for ((position, index) in fold.withIndex()) predictions[number][index] = predictionFromOrder(orders[position], model.k, model.weighting)
        }
    }
    return models.mapIndexed { index, model -> CrossValidation(model, rows, predictions[index].map { it!! }) }
}
fun bestClassifier(results: List<CrossValidation>) = results.indices.minWith(compareBy({ -results[it].correct }, { it })).let { results[it] }
fun bestRegressor(results: List<CrossValidation>) = results.indices.minWith(compareBy({ fourDecimal(results[it].rmse) }, { it })).let { results[it] }
fun correctCount(predictions: List<Prediction>, rows: List<Row>) = predictions.zip(rows).count { (prediction, row) -> prediction.label == row.label }
fun labelCounts(rows: List<Row>, labels: List<String>) = labels.joinToString(" ") { label -> "$label ${rows.count { it.label == label }}" }
fun evaluationLines(pairs: List<Pair<String, String>>, labels: List<String>): List<String> {
    val matrix = List(labels.size) { IntArray(labels.size) }
    for ((truth, prediction) in pairs) matrix[labels.indexOf(truth)][labels.indexOf(prediction)]++
    val lines = mutableListOf("true\\predicted " + labels.joinToString(" "))
    for ((index, label) in labels.withIndex()) lines += "$label " + matrix[index].joinToString(" ")
    val totals = DoubleArray(3)
    val valued = IntArray(3)
    for ((index, label) in labels.withIndex()) {
        val hits = matrix[index][index]
        val predicted = matrix.sumOf { it[index] }
        val actual = matrix[index].sum()
        val metrics = listOf(hits to predicted, hits to actual, 2 * hits to predicted + actual)
        for ((position, metric) in metrics.withIndex()) if (metric.second > 0) { totals[position] += metric.first.toDouble() / metric.second.toDouble(); valued[position]++ }
        lines += "class $label precision ${fraction(hits, predicted)} recall ${fraction(hits, actual)} f1 ${fraction(2 * hits, predicted + actual)} support $actual"
    }
    val averages = totals.indices.map { if (valued[it] == 0) "-" else fixed(totals[it] / valued[it].toDouble()) }
    lines += "macro precision ${averages[0]} recall ${averages[1]} f1 ${averages[2]}"
    return lines
}
fun reliabilityLines(pairs: List<Pair<Prediction, String>>, bounds: List<Double>): List<String> {
    val lower = listOf(0.0) + bounds
    val counts = IntArray(lower.size)
    val hits = IntArray(lower.size)
    val shares = DoubleArray(lower.size)
    for ((prediction, truth) in pairs) {
        val bin = bounds.count { it <= prediction.share }
        counts[bin]++
        if (prediction.label == truth) hits[bin]++
        shares[bin] += prediction.share
    }
    return lower.indices.map { index -> "bin ${fixed(lower[index], 2)} rows ${counts[index]}" + if (counts[index] == 0) "" else " correct ${ratio(hits[index], counts[index])} share ${fixed(shares[index] / counts[index].toDouble())}" }
}
class ClassifierSpace(val model: Model, train: List<Row>, test: List<Row>) {
    val gaps: Map<String, Map<String, Double>>
    init {
        val features = train[0].values.indices.toList()
        val scaling = computeScaling(train, model.scaling)
        val references = train.map { scaling.transform(it.values, features) }
        gaps = (train + test).associate { query -> val vector = scaling.transform(query.values, features); query.id to train.mapIndexed { index, row -> row.id to distance(vector, references[index], model.metric) }.toMap() }
    }
    fun order(query: Row, rows: List<Row>) = sortNeighbors(rows.map { Neighbor(gaps.getValue(query.id).getValue(it.id), it) })
    fun vote(query: Row, rows: List<Row>, k: Int) = vote(order(query, rows).take(k), model.weighting)
    fun nearestLabel(query: Row, rows: List<Row>) = order(query, rows)[0].row.label!!
}
fun wilsonEditing(space: ClassifierSpace, rows: List<Row>, editK: Int): Pair<List<Row>, List<List<Pair<Row, Vote>>>> {
    var current = rows
    val passes = mutableListOf<List<Pair<Row, Vote>>>()
    while (true) {
        val removed = current.mapNotNull { row -> val result = space.vote(row, current.filter { it.id != row.id }, editK); if (result.label != row.label) row to result else null }
        passes += removed
        if (removed.isEmpty()) return current to passes
        val ids = removed.map { it.first.id }.toSet()
        current = current.filter { it.id !in ids }
    }
}
fun hartCondensing(space: ClassifierSpace, rows: List<Row>): Pair<List<Row>, Int> {
    val store = mutableListOf(rows[0])
    val stored = mutableSetOf(rows[0].id)
    var scans = 0
    while (true) {
        scans++
        var added = false
        for (row in rows) if (row.id !in stored && space.nearestLabel(row, store) != row.label) { store += row; stored += row.id; added = true }
        if (!added) return store.sortedBy { it.id } to scans
    }
}

class Experiment(val data: Dataset) {
    val featureNames = data.features
    val features = featureNames.indices.toList()
    val train = data.train
    val test = data.test
    val settings = data.settings
    val labels = train.map { it.label!! }.distinct().sorted()
    val labelled = test.filter { it.label != null }
    val targeted = test.filter { it.target != null }
    val grid = settings.ks.flatMap { k -> settings.metrics.flatMap { metric -> settings.weightings.flatMap { weighting -> settings.scalings.map { Model(k, metric, weighting, it) } } } }
    val folds = stratifiedFolds(train, settings.folds)
    val results = crossValidate(grid, train, settings.folds, features)
    val classifier = bestClassifier(results)
    val regressor = bestRegressor(results)
    val testPredictions = predictRows(classifier.model, train, test, features)
    val testEstimates = predictRows(regressor.model, train, test, features).map { it.estimate }
    val labelledPredictions = test.zip(testPredictions).filter { it.first.label != null }
    fun names(features: List<Int>) = features.joinToString(" ") { featureNames[it] }
    fun trainRatio(count: Int) = ratio(count, train.size)
    fun classifierSummary(result: CrossValidation) = "${result.model.notation()} correct ${trainRatio(result.correct)} rmse ${fixed(result.rmse)}"
    fun regressorSummary(result: CrossValidation) = "${result.model.notation()} rmse ${fixed(result.rmse)} correct ${trainRatio(result.correct)}"
    fun gridTable() = listOf("k,metric,weighting,scaling,correct,accuracy,rmse") + results.map { "${it.model.k},${it.model.metric},${it.model.weighting},${it.model.scaling},${it.correct},${fixed(it.correct.toDouble() / train.size.toDouble())},${fixed(it.rmse)}" }
    fun predictionTable() = listOf("id,label,vote_share,estimate") + test.indices.map { "${test[it].id},${testPredictions[it].label},${fixed(testPredictions[it].share)},${fixed(testEstimates[it])}" }
    fun dataPart() = listOf("data train ${train.size} test ${test.size} labelled ${labelled.size} targets ${targeted.size} features ${features.size} classes ${labels.size}", "classes ${labelCounts(train, labels)}")
    fun scalingPart(method: String): List<String> { val scaling = computeScaling(train, method); return listOf("scaling $method") + featureNames.indices.map { "${featureNames[it]} center ${fixed(scaling.centers[it], 6)} scale ${fixed(scaling.scales[it], 6)}" } }
    fun foldsPart() = listOf("folds ${settings.folds}") + folds.mapIndexed { index, fold -> "fold ${index + 1} size ${fold.size} ${labelCounts(fold.map { train[it] }, labels)}" }
    fun selectionPart() = listOf("grid ${grid.size}", "best_classifier ${classifierSummary(classifier)}", "best_regressor ${regressorSummary(regressor)}")
    fun topPart(accuracy: Boolean): List<String> {
        val ordered = results.indices.sortedWith(if (accuracy) compareBy({ -results[it].correct }, { it }) else compareBy({ fourDecimal(results[it].rmse) }, { it }))
        return listOf("top ${settings.top} by ${if (accuracy) "accuracy" else "rmse"}") + ordered.take(settings.top).mapIndexed { rank, index -> "${rank + 1} ${if (accuracy) classifierSummary(results[index]) else regressorSummary(results[index])}" }
    }
    fun bestPerItemParts(): List<List<String>> {
        val values = listOf("k" to settings.ks.map(Int::toString), "metric" to settings.metrics, "weighting" to settings.weightings, "scaling" to settings.scalings)
        return values.map { (item, entries) -> listOf("best per $item") + entries.map { value ->
            val selected = results.filter { result -> when (item) { "k" -> result.model.k.toString(); "metric" -> result.model.metric; "weighting" -> result.model.weighting; else -> result.model.scaling } == value }
            val first = bestClassifier(selected)
            val second = bestRegressor(selected)
            "$item=$value classifier ${first.model.notation()} accuracy ${fixed(first.correct.toDouble() / train.size.toDouble())} regressor ${second.model.notation()} rmse ${fixed(second.rmse)}"
        } }
    }
    fun classifierFoldsPart() = listOf("classifier folds") + folds.mapIndexed { number, fold -> "fold ${number + 1} correct ${ratio(fold.count { classifier.hits[it] }, fold.size)}" }
    fun regressorFoldsPart() = listOf("regressor folds") + folds.mapIndexed { number, fold -> "fold ${number + 1} size ${fold.size} rmse ${fixed(rmse(fold.map { regressor.predictions[it].estimate - train[it].target!! }))}" }
    fun mcnemarPart(): List<String> {
        val lines = mutableListOf("mcnemar")
        for (metric in settings.metrics) {
            val comparison = bestClassifier(results.filter { it.model.metric == metric })
            val b = train.indices.count { classifier.hits[it] && !comparison.hits[it] }
            val c = train.indices.count { comparison.hits[it] && !classifier.hits[it] }
            val difference = maxOf(0, abs(b - c) - 1)
            val numerator = difference * difference
            lines += "${comparison.model.notation()} b $b c $c statistic ${if (b + c == 0) "0/1 0.0000" else fraction(numerator, b + c)} significant ${if (1000 * numerator > 3841 * (b + c)) "yes" else "no"}"
        }
        return lines
    }
    fun leaveOneOutParts(): List<List<String>> {
        val model = classifier.model
        val byK = settings.ks.associateWith { mutableListOf<Prediction>() }
        val estimates = mutableListOf<Double>()
        for ((index, row) in train.withIndex()) {
            val others = train.filterIndexed { other, _ -> other != index }
            val order = neighborOrders(others, listOf(row), model.scaling, model.metric, features)[0]
            for (k in settings.ks) byK.getValue(k) += predictionFromOrder(order, k, model.weighting)
            estimates += predictRows(regressor.model, others, listOf(row), features)[0].estimate
        }
        val predictions = byK.getValue(model.k)
        val errors = train.zip(predictions).filter { (row, prediction) -> row.label != prediction.label }.sortedBy { it.first.id }
        val first = mutableListOf("leave_one_out classifier ${model.notation()}", "errors ${trainRatio(errors.size)}", "class_errors " + labels.joinToString(" ") { label -> "$label ${errors.count { it.first.label == label }}" })
        for ((row, prediction) in errors) first += "${row.id} true ${row.label} predicted ${prediction.label} share ${fixed(prediction.share)}"
        val residuals = train.indices.map { estimates[it] - train[it].target!! }
        val second = mutableListOf("leave_one_out regressor ${regressor.model.notation()}", "rmse ${fixed(rmse(residuals))} mae ${fixed(mae(residuals))}", "largest ${settings.top} residuals")
        for (index in train.indices.sortedWith(compareBy({ -fourDecimal(abs(residuals[it])) }, { train[it].id })).take(settings.top)) second += "${train[index].id} target ${fixed(train[index].target!!)} estimate ${fixed(estimates[index])} residual ${fixed(residuals[index])}"
        val third = mutableListOf("leave_one_out by k metric=${model.metric} weighting=${model.weighting} scaling=${model.scaling}")
        for (k in settings.ks) { val predictions = byK.getValue(k); third += "k=$k correct ${trainRatio(correctCount(predictions, train))} rmse ${fixed(rmse(predictions.zip(train) { prediction, row -> prediction.estimate - row.target!! }))}" }
        return listOf(first, second, third)
    }
    fun nestedPart(): List<String> {
        val lines = mutableListOf("nested_cross_validation folds ${settings.folds}")
        val estimates = DoubleArray(train.size)
        var correct = 0
        for ((number, fold) in folds.withIndex()) {
            val training = foldTraining(train, fold)
            val queries = fold.map { train[it] }
            val results = crossValidate(grid, training, settings.folds, features)
            val first = bestClassifier(results)
            val second = bestRegressor(results)
            val predictions = predictRows(first.model, training, queries, features)
            val hits = correctCount(predictions, queries)
            correct += hits
            val predicted = predictRows(second.model, training, queries, features)
            for ((position, index) in fold.withIndex()) estimates[index] = predicted[position].estimate
            lines += "fold ${number + 1} classifier ${first.model.notation()} inner ${fixed(first.correct.toDouble() / training.size.toDouble())} outer ${ratio(hits, fold.size)}"
            lines += "fold ${number + 1} regressor ${second.model.notation()} inner ${fixed(second.rmse)} outer ${fixed(rmse(predicted.zip(queries) { prediction, row -> prediction.estimate - row.target!! }))}"
        }
        lines += "nested accuracy ${trainRatio(correct)} rmse ${fixed(rmse(train.indices.map { estimates[it] - train[it].target!! }))}"
        return lines
    }
    fun featureSelectionPart(): List<String> {
        val model = classifier.model
        var current = features
        var selected = current
        var selectedCorrect = classifier.correct
        val lines = mutableListOf("feature_selection ${model.notation()}", "start features ${names(current)} correct ${trainRatio(classifier.correct)}")
        var step = 0
        while (current.size >= 3) {
            step++
            val candidates = current.map { feature -> feature to crossValidate(listOf(model), train, settings.folds, current.filter { it != feature })[0].correct }
            val chosen = candidates.indices.minWith(compareBy({ -candidates[it].second }, { it })).let { candidates[it] }
            current = current.filter { it != chosen.first }
            lines += "step $step remove ${featureNames[chosen.first]} correct ${trainRatio(chosen.second)} candidates " + candidates.joinToString(" ") { "${featureNames[it.first]} ${it.second}" }
            if (chosen.second >= selectedCorrect) { selected = current; selectedCorrect = chosen.second }
        }
        val predictions = predictRows(model, train, labelled, selected)
        lines += "selected features ${names(selected)} correct ${trainRatio(selectedCorrect)}"
        lines += "selected test ${ratio(correctCount(predictions, labelled), labelled.size)}"
        return lines
    }
    fun testClassificationPart(): List<String> {
        val pairs = labelledPredictions.map { (row, prediction) -> row.label!! to prediction.label }
        return listOf("test classification ${classifier.model.notation()}", "labelled ${labelled.size} correct ${ratio(pairs.count { it.first == it.second }, labelled.size)}") + evaluationLines(pairs, labels)
    }
    fun uncertainPart(): List<String> {
        val margins = testPredictions.map { it.share - it.runnerShare }
        return listOf("uncertain ${settings.top} test rows") + test.indices.sortedWith(compareBy({ fourDecimal(margins[it]) }, { it })).take(settings.top).map { index -> val row = test[index]; val prediction = testPredictions[index]; "${row.id} predicted ${prediction.label} share ${fixed(prediction.share)} runner_up ${prediction.runner ?: "-"} share ${fixed(prediction.runnerShare)} margin ${fixed(margins[index])} true ${row.label ?: "-"}" }
    }
    fun testRegressionPart(): List<String> {
        val pairs = test.zip(testEstimates).filter { it.first.target != null }
        val errors = pairs.map { it.second - it.first.target!! }
        val lines = mutableListOf("test regression ${regressor.model.notation()}", "targets ${pairs.size} rmse ${fixed(rmse(errors))} mae ${fixed(mae(errors))} r2 ${fixed(rSquared(errors, pairs.map { it.first.target!! }))}")
        for (label in labels) { val selected = pairs.filter { it.first.label == label }.map { it.second - it.first.target!! }; lines += "class $label targets ${selected.size} rmse ${if (selected.isEmpty()) "-" else fixed(rmse(selected))}" }
        return lines
    }
    fun misclassifiedPart(): List<String> {
        val lines = mutableListOf("misclassified test rows")
        var count = 0
        for ((row, prediction) in labelledPredictions) if (row.label != prediction.label) { count++; lines += "${row.id} true ${row.label} predicted ${prediction.label} share ${fixed(prediction.share)}"; for (neighbor in prediction.nearest) lines += "  ${neighbor.row.id} ${neighbor.row.label} ${fixed(neighbor.distance)}" }
        lines += "count $count"
        return lines
    }
    fun metricsReport(): List<String> {
        val parts = mutableListOf(dataPart())
        parts += settings.scalings.map(::scalingPart)
        parts += listOf(foldsPart(), selectionPart(), topPart(true), topPart(false))
        parts += bestPerItemParts()
        parts += listOf(classifierFoldsPart(), regressorFoldsPart(), listOf("cross_validation classes") + evaluationLines(train.zip(classifier.predictions) { row, prediction -> row.label!! to prediction.label }, labels), listOf("cross_validation reliability") + reliabilityLines(train.zip(classifier.predictions) { row, prediction -> prediction to row.label!! }, settings.bins), mcnemarPart())
        parts += leaveOneOutParts()
        parts += listOf(nestedPart(), featureSelectionPart(), testClassificationPart(), listOf("test reliability") + reliabilityLines(labelledPredictions.map { it.second to it.first.label!! }, settings.bins), uncertainPart(), testRegressionPart(), misclassifiedPart())
        return joinParts(parts)
    }
    fun learningCurveTable(): List<String> {
        val lines = mutableListOf("n,train_size,correct,accuracy,rmse")
        for (limit in settings.curve) {
            val taken = labels.associateWith { 0 }.toMutableMap()
            val rows = train.filter { row -> val label = row.label!!; val count = taken.getValue(label); if (count < limit) { taken[label] = count + 1; true } else false }
            val predictions = predictRows(classifier.model, rows, labelled, features)
            val correct = correctCount(predictions, labelled)
            val estimates = predictRows(regressor.model, rows, targeted, features)
            lines += "$limit,${rows.size},$correct,${fixed(correct.toDouble() / labelled.size.toDouble())},${fixed(rmse(estimates.zip(targeted) { prediction, row -> prediction.estimate - row.target!! }))}"
        }
        return lines
    }
    fun prototypesReport(): List<String> {
        val space = ClassifierSpace(classifier.model, train, test)
        val ordered = train.sortedBy { it.id }
        val (edited, passes) = wilsonEditing(space, ordered, settings.editK)
        val (condensed, originalScans) = hartCondensing(space, ordered)
        val (editedCondensed, editedScans) = hartCondensing(space, edited)
        val editing = mutableListOf("editing k=${settings.editK}")
        for ((number, removed) in passes.withIndex()) { editing += "pass ${number + 1} removed ${removed.size}"; for ((row, vote) in removed) editing += "  ${row.id} true ${row.label} predicted ${vote.label} share ${fixed(vote.share)}" }
        editing += "edited size ${edited.size} removed ${train.size - edited.size}"
        val sets = listOf("original" to ordered, "edited" to edited, "condensed" to condensed, "edited_condensed" to editedCondensed).map { (name, rows) ->
            val knn = labelled.count { space.vote(it, rows, classifier.model.k).label == it.label }
            val nearest = labelled.count { space.nearestLabel(it, rows) == it.label }
            "set $name size ${rows.size} ${labelCounts(rows, labels)} knn ${ratio(knn, labelled.size)} 1nn ${ratio(nearest, labelled.size)}"
        }
        val borders = mutableListOf("borders")
        var total = 0
        for (label in labels) {
            val members = ordered.filter { it.label == label }
            var count = 0
            var same = 0.0
            var other = 0.0
            for (row in members) { val order = space.order(row, ordered.filter { it.id != row.id }); if (order[0].row.label != label) count++; same += order.first { it.row.label == label }.distance; other += order.first { it.row.label != label }.distance }
            total += count
            borders += "class $label size ${members.size} border $count same ${fixed(same / members.size.toDouble())} other ${fixed(other / members.size.toDouble())}"
        }
        borders += "border total ${trainRatio(total)}"
        val occurrences = train.associate { it.id to 0 }.toMutableMap()
        for (prediction in testPredictions) for (neighbor in prediction.nearest) occurrences[neighbor.row.id] = occurrences.getValue(neighbor.row.id) + 1
        val hubs = mutableListOf("hubs k=${classifier.model.k} queries ${test.size}")
        for (row in train.sortedWith(compareBy({ -occurrences.getValue(it.id) }, { it.id })).take(settings.top)) hubs += "${row.id} ${row.label} ${occurrences.getValue(row.id)}"
        hubs += "anti_hubs ${occurrences.values.count { it == 0 }}"
        return joinParts(listOf(listOf("space ${classifier.model.notation()}"), editing, listOf("condensing original scans $originalScans size ${condensed.size}", "condensing edited scans $editedScans size ${editedCondensed.size}"), sets, listOf("prototypes condensed") + condensed.map { it.id }.chunked(10).map { it.joinToString(" ") }, listOf("prototypes edited_condensed") + editedCondensed.map { it.id }.chunked(10).map { it.joinToString(" ") }, borders, hubs))
    }
    fun write() { for ((name, lines) in listOf("cv_grid.csv" to gridTable(), "predictions.csv" to predictionTable(), "metrics.txt" to metricsReport(), "learning_curve.csv" to learningCurveTable(), "prototypes.txt" to prototypesReport())) writeLines(name, lines) }
}
fun main() { Experiment(readDataset()).write() }
