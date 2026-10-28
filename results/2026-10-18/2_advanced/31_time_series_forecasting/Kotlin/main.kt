import java.nio.file.Files
import java.nio.file.Path
import java.util.Locale
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.ln
import kotlin.math.sqrt

private val methods = listOf("naive", "snaive", "drift", "ses", "holt", "damped", "hw_add", "hw_mult", "decomp_add", "decomp_mult", "ar")
private fun real(value: Double): String = SeriesIo.real(value)
private fun reals(values: DoubleArray): String = values.joinToString(" ") {
    real(it)
}
private fun squares(values: DoubleArray): Double {
    var total = 0.0;
    for (value in values) total += value * value;
    return total
}
private fun rmse(values: DoubleArray): Double = sqrt(squares(values) / values.size)
private class Model(val name: String, val values: DoubleArray, val season: Int) {
    var errors = DoubleArray(0);
    var seasonal = DoubleArray(0);
    var differenced = DoubleArray(0);
    var coefficients = DoubleArray(0);
    var variances = DoubleArray(4);
    var aic = DoubleArray(0);
    var acf = DoubleArray(0);
    var partial = DoubleArray(0)
    var alpha = 0.0;
    var beta = 0.0;
    var gamma = 0.0;
    var phi = 1.0;
    var intercept = 0.0;
    var slope = 0.0;
    var mean = 0.0;
    var sigma2 = 0.0
    var kind = "";
    var smooth: SmoothRun? = null;
    var members = mutableListOf<Model>()
    fun decomp(time: Int): Double {
        val base = intercept + slope * (time + 1);
        return if (name == "decomp_add") base + seasonal[time % season] else base * seasonal[time % season]
    }
    fun forecast(origin: Int, steps: Int): DoubleArray {
        val result = DoubleArray(steps)
        if (name == "combo") {
            for (member in members) {
                val predicted = member.forecast(origin, steps);
                for (k in 0 until steps) result[k] += predicted[k]
            };
            for (k in 0 until steps) result[k] /= members.size;
            return result
        }
        if (name == "ar") return Autoregression.forecast(values, differenced, kind, mean, coefficients, origin, steps, season)
        val state = smooth
        if (state != null) return Smoothing.forecast(name, state.states[origin], origin, steps, season, phi)
        for (k in 0 until steps) result[k] = when (name) {
            "naive" -> values[origin - 1];
            "snaive" -> values[origin - season + k % season];
            "drift" -> values[origin - 1] + (k + 1) * ((values[origin - 1] - values[0]) / (origin - 1));
            else -> decomp(origin + k)
        }
        return result
    }
    fun lines(): List<String> {
        val suffix = " rmse ${real(rmse(errors))} residuals ${errors.size}"
        if (name == "naive" || name == "snaive") return listOf(name + suffix)
        if (name == "drift") return listOf("$name slope ${real(slope)}$suffix")
        if (name == "ar") return listOf("ar variance none ${real(variances[0])} first ${real(variances[1])} seasonal ${real(variances[2])} both ${real(variances[3])}", "ar difference $kind n ${differenced.size} mean ${real(mean)} order ${coefficients.size} sigma2 ${real(sigma2)}$suffix", "ar aic ${reals(aic)}", "ar coefficients ${if (coefficients.isEmpty()) "none" else reals(coefficients)}")
        if (name.startsWith("decomp_")) return listOf("$name intercept ${real(intercept)} slope ${real(slope)}$suffix", "$name seasonal ${reals(seasonal)}")
        val state = smooth!!.states.last();
        var line = "$name alpha ${real(alpha)}"
        if (name != "ses") line += " beta ${real(beta)}"
        if (name == "damped") line += " phi ${real(phi)}"
        if (name.startsWith("hw_")) line += " gamma ${real(gamma)}"
        line += "$suffix level ${real(state.level)}"
        if (name != "ses") line += " slope ${real(state.slope)}"
        if (!name.startsWith("hw_")) return listOf(line)
        val rotated = DoubleArray(season) {
            state.components[(values.size + it) % season]
        }
        return listOf(line, "$name seasonal ${reals(rotated)}")
    }
}
private fun fit(name: String, values: DoubleArray, settings: SeriesIo): Model {
    val season = settings.integer("season");
    val count = values.size;
    val model = Model(name, values, season)
    if (name == "naive" || name == "snaive" || name == "drift") {
        val lag = if (name == "snaive") season else 1;
        model.slope = if (name == "drift") (values[count - 1] - values[0]) / (count - 1) else 0.0;
        model.errors = DoubleArray(count - lag) {
            t -> values[t + lag] - values[t] - model.slope
        };
        return model
    }
    if (name.startsWith("decomp_")) {
        val decomposition = Decomposition(values, season);
        model.seasonal = if (name == "decomp_add") decomposition.additive else decomposition.multiplicative;
        val adjusted = DoubleArray(count) {
            if (name == "decomp_add") values[it] - model.seasonal[it % season] else values[it] / model.seasonal[it % season]
        };
        val line = Decomposition.regression(adjusted);
        model.intercept = line[0];
        model.slope = line[1];
        model.errors = DoubleArray(count) {
            values[it] - model.decomp(it)
        };
        return model
    }
    if (name == "ar") {
        var smallest = Double.POSITIVE_INFINITY
        for ((i, kind) in Autoregression.kinds.withIndex()) {
            val differenced = Autoregression.difference(values, season, kind);
            val correlations = Autoregression.correlations(differenced, 0);
            model.variances[i] = correlations.variance;
            if (correlations.variance < smallest) {
                smallest = correlations.variance;
                model.kind = kind;
                model.differenced = differenced
            }
        }
        val correlations = Autoregression.correlations(model.differenced, settings.integer("max_lag"));
        val durbin = Autoregression.durbin(correlations.acf);
        model.mean = correlations.mean;
        model.acf = correlations.acf;
        model.partial = durbin.partial
        model.aic = DoubleArray(settings.integer("max_ar") + 1) {
            model.differenced.size * ln(correlations.variance * durbin.variances[it]) + 2 * it
        }
        val order = model.aic.indices.minBy {
            model.aic[it]
        };
        model.coefficients = durbin.coefficients[order];
        model.sigma2 = correlations.variance * durbin.variances[order];
        model.errors = Autoregression.residuals(model.differenced, model.mean, model.coefficients);
        return model
    }
    var best = Double.POSITIVE_INFINITY;
    val betas = if (name == "ses") doubleArrayOf(0.0) else settings.candidates("beta");
    val gammas = if (name.startsWith("hw_")) settings.candidates("gamma") else doubleArrayOf(0.0);
    val phis = if (name == "damped") settings.candidates("phi") else doubleArrayOf(1.0)
    for (alpha in settings.candidates("alpha")) for (beta in betas) for (gamma in gammas) for (phi in phis) {
        val result = Smoothing.recurse(name, values, season, alpha, beta, gamma, phi);
        val score = squares(result.errors);
        if (score < best) {
            best = score;
            model.alpha = alpha;
            model.beta = beta;
            model.gamma = gamma;
            model.phi = phi;
            model.smooth = result;
            model.errors = result.errors
        }
    }
    return model
}
private data class CrossValidation(val counts: IntArray, val sigma: DoubleArray, val mae: DoubleArray, val rmse: Double)
private fun cv(model: Model, settings: SeriesIo): CrossValidation {
    val horizon = settings.integer("horizon");
    val counts = IntArray(horizon);
    val squared = DoubleArray(horizon);
    val absolute = DoubleArray(horizon)
    for (origin in settings.integer("cv_start") until model.values.size) {
        val predictions = model.forecast(origin, minOf(horizon, model.values.size - origin));
        for (k in predictions.indices) {
            val error = model.values[origin + k] - predictions[k];
            counts[k]++;
            squared[k] += error * error;
            absolute[k] += abs(error)
        }
    }
    val sigma = DoubleArray(horizon) {
        sqrt(squared[it] / counts[it])
    };
    val mae = DoubleArray(horizon) {
        absolute[it] / counts[it]
    };
    var total = 0.0;
    var count = 0
    for (k in 0 until settings.integer("holdout")) {
        total += squared[k];
        count += counts[k]
    }
    return CrossValidation(counts, sigma, mae, sqrt(total / count))
}
private fun intervals(predicted: DoubleArray, sigma: DoubleArray, coefficients: DoubleArray, multipliers: DoubleArray? = null): Array<DoubleArray> = Array(predicted.size) {
    k ->
    val value = predicted[k];
    val low = coefficients[0] * sigma[k];
    val high = coefficients[1] * sigma[k];
    val multiplier = multipliers?.get(k) ?: 1.0
    doubleArrayOf(value * multiplier, (value - low) * multiplier, (value + low) * multiplier, (value - high) * multiplier, (value + high) * multiplier)
}
private class Analysis(val data: SeriesData, val settings: SeriesIo) {
    val season = settings.integer("season");
    val horizon = settings.integer("horizon");
    val holdout = settings.integer("holdout");
    val n = data.raw.size;
    val trainingCount = n - holdout
    val values = data.raw.map {
        it.toDouble()
    }.toDoubleArray();
    val cleaned: DoubleArray;
    val actual: DoubleArray;
    val training: DoubleArray;
    val scores = DoubleArray(n)
    val decomposition: Decomposition;
    val outliers = BooleanArray(n)
    val eventKinds = linkedMapOf<String, MutableList<Int>>();
    val lifts = mutableMapOf<String, Double>();
    val future = mutableListOf<String>()
    val models = mutableListOf<Model>();
    val validations = mutableListOf<CrossValidation>();
    val holdoutRows = mutableListOf<Array<DoubleArray>>();
    val metrics = mutableListOf<Accuracy>();
    val combination = mutableListOf<Model>()
    val ranks: IntArray;
    val best: Model;
    val finalModel: Model;
    val bestIndex: Int;
    val futureRows: Array<DoubleArray>;
    val strengthTrend: Double;
    val strengthSeasonal: Double
    init {
        var left = 0
        while (left < n - 1) {
            var right = left + 1;
            while (data.raw[right] < 0) right++;
            for (t in left + 1 until right) values[t] = values[left] + (values[right] - values[left]) * (t - left) / (right - left);
            left = right
        }
        decomposition = Decomposition(values, season);
        val residuals = decomposition.residualAdd.copyOfRange(decomposition.half, n - decomposition.half);
        val average = residuals.sum() / residuals.size;
        val deviation = sqrt(Decomposition.variance(residuals));
        cleaned = values.copyOf()
        for (t in 0 until n) {
            val event = data.events[data.periods[t]];
            if (event != null) eventKinds.getOrPut(event) {
                mutableListOf()
            }.add(t);
            if (t >= decomposition.half && t < n - decomposition.half && event == null && data.raw[t] >= 0 && abs(decomposition.residualAdd[t] - average) > settings.number("outlier") * deviation) {
                outliers[t] = true;
                scores[t] = (decomposition.residualAdd[t] - average) / deviation
            };
            if (event != null || outliers[t]) cleaned[t] = decomposition.trend[t] + decomposition.additive[t % season]
        }
        for ((kind, times) in eventKinds) {
            var total = 0.0;
            for (t in times) total += values[t] / (decomposition.trend[t] + decomposition.additive[t % season]);
            lifts[kind] = total / times.size
        }
        val trendResidual = DoubleArray(residuals.size) {
            i -> decomposition.trend[i + decomposition.half] + residuals[i]
        };
        val seasonalResidual = DoubleArray(residuals.size) {
            i -> decomposition.additive[(i + decomposition.half) % season] + residuals[i]
        };
        val variance = Decomposition.variance(residuals);
        strengthTrend = maxOf(0.0, 1 - variance / Decomposition.variance(trendResidual));
        strengthSeasonal = maxOf(0.0, 1 - variance / Decomposition.variance(seasonalResidual))
        training = cleaned.copyOf(trainingCount);
        actual = values.copyOfRange(trainingCount, n)
        for (name in methods) {
            val model = fit(name, training, settings);
            models.add(model);
            validations.add(cv(model, settings))
        }
        val selected = methods.indices.sortedWith(compareBy<Int> {
            validations[it].rmse
        }.thenBy {
            it
        }).take(settings.integer("combo")).toSet()
        for (i in methods.indices) if (i in selected) combination.add(models[i])
        val combo = Model("combo", training, season);
        combo.members = combination;
        models.add(combo);
        validations.add(cv(combo, settings))
        for (i in models.indices) {
            val predicted = models[i].forecast(trainingCount, holdout);
            holdoutRows.add(intervals(predicted, validations[i].sigma, settings.candidates("interval")));
            metrics.add(Evaluation.accuracy(actual, predicted, Evaluation.scale(training, season)))
        }
        val order = Evaluation.ranking(metrics);
        ranks = IntArray(models.size);
        for ((i, index) in order.withIndex()) ranks[index] = i + 1;
        bestIndex = order.first();
        best = models[bestIndex]
        finalModel = if (best.name == "combo") Model("combo", cleaned, season).also {
            model -> for (member in combination) model.members.add(fit(member.name, cleaned, settings))
        } else fit(best.name, cleaned, settings)
        var period = data.periods.last();
        val multipliers = DoubleArray(horizon)
        for (k in 0 until horizon) {
            period = SeriesIo.nextMonth(period);
            future.add(period);
            val event = data.events[period];
            multipliers[k] = if (event == null) 1.0 else lifts.getValue(event)
        }
        val finalCv = cv(finalModel, settings);
        futureRows = intervals(finalModel.forecast(n, horizon), finalCv.sigma, settings.candidates("interval"), multipliers)
    }
    fun decompositionLines(): List<String> = (0 until n).map {
        t -> val flag = data.events[data.periods[t]] ?: if (data.raw[t] < 0) "missing" else if (outliers[t]) "outlier" else "ok";
        "${data.name},${data.periods[t]},${real(values[t])},${real(cleaned[t])},${real(decomposition.trend[t])},${real(decomposition.additive[t % season])},${real(decomposition.residualAdd[t])},${real(decomposition.multiplicative[t % season])},${real(decomposition.residualMult[t])},$flag"
    }
    fun modelLines(): List<String> {
        val lines = mutableListOf("series ${data.name}", "data observations $n train $trainingCount holdout $holdout missing ${data.raw.count { it < 0 }} outliers ${outliers.count { it }} events ${data.periods.count { it in data.events }}")
        for ((kind, times) in eventKinds) lines.add("event $kind occurrences ${times.size} lift ${real(lifts.getValue(kind))}")
        for (t in 0 until n) if (outliers[t]) lines.add("outlier ${data.periods[t]} value ${real(values[t])} expected ${real(cleaned[t])} score ${real(scores[t])}")
        lines.add("strength trend ${real(strengthTrend)} seasonal ${real(strengthSeasonal)}");
        for (i in methods.indices) lines.addAll(models[i].lines());
        lines.add("combo members ${combination.joinToString(" ") { it.name }}");
        lines.add("best ${best.name} rmse ${real(metrics[bestIndex].rmse)}")
        if (best.name == "combo") for (member in finalModel.members) for (line in member.lines()) lines.add("final $line") else for (line in finalModel.lines()) lines.add("final $line")
        return lines
    }
    fun forecastLines(): List<String> {
        val lines = mutableListOf<String>()
        for (i in models.indices) for (t in 0 until holdout) lines.add("${data.name},holdout,${models[i].name},${data.periods[trainingCount + t]},${data.raw[trainingCount + t]},${csv(holdoutRows[i][t])}")
        for (k in 0 until horizon) lines.add("${data.name},future,${best.name},${future[k]},NA,${csv(futureRows[k])}")
        return lines
    }
    fun accuracyLines(): List<String> {
        val lines = mutableListOf<String>()
        for (i in models.indices) {
            val metric = metrics[i];
            val rows = holdoutRows[i];
            var cover80 = 0;
            var cover95 = 0;
            var winkler80 = 0.0;
            var winkler95 = 0.0
            for (t in 0 until holdout) {
                if (actual[t] >= rows[t][1] && actual[t] <= rows[t][2]) cover80++;
                if (actual[t] >= rows[t][3] && actual[t] <= rows[t][4]) cover95++;
                winkler80 += Evaluation.winkler(actual[t], rows[t][1], rows[t][2], 10.0);
                winkler95 += Evaluation.winkler(actual[t], rows[t][3], rows[t][4], 40.0)
            }
            val values = doubleArrayOf(metric.me, metric.mae, metric.rmse, metric.mape, metric.smape, metric.mase, 100 * (metrics.first().mae - metric.mae) / metrics.first().mae, validations[i].rmse)
            lines.add("${data.name},${models[i].name},${csv(values)},$cover80,$cover95,${real(winkler80 / holdout)},${real(winkler95 / holdout)},${ranks[i]}")
        }
        return lines
    }
    fun cvLines(): List<String> {
        val lines = mutableListOf<String>()
        for (i in models.indices) for (k in 0 until horizon) {
            val cv = validations[i];
            lines.add("${data.name},${models[i].name},${k + 1},${cv.counts[k]},${real(cv.mae[k])},${real(cv.sigma[k])}")
        }
        return lines
    }
    fun correlogramLines(): List<String> {
        val ar = models[10];
        val band = 2 / sqrt(ar.differenced.size.toDouble());
        val lines = mutableListOf("series ${data.name} difference ${ar.kind} n ${ar.differenced.size} band ${real(band)}")
        for (label in listOf("acf", "pacf")) {
            val correlations = if (label == "acf") ar.acf else ar.partial;
            for (k in 1 until correlations.size) lines.add(String.format(Locale.ROOT, "%s %2d %7s [%s]%s", label, k, real(correlations[k]), correlationBar(correlations[k], band), if (abs(correlations[k]) > band) " *" else ""))
        }
        for (method in methods.indices) {
            val model = models[method];
            val errors = model.errors;
            val count = errors.size;
            val mean = errors.sum() / count;
            var s2 = 0.0;
            var s3 = 0.0;
            var s4 = 0.0;
            var dw = 0.0
            for (i in errors.indices) {
                val delta = errors[i] - mean;
                s2 += delta * delta;
                s3 += delta * delta * delta;
                s4 += delta * delta * delta * delta;
                if (i > 0) dw += (errors[i] - errors[i - 1]) * (errors[i] - errors[i - 1])
            }
            val m2 = s2 / count;
            val skew = s3 / count / (m2 * sqrt(m2));
            val kurtosis = s4 / count / (m2 * m2) - 3;
            val jb = count / 6.0 * (skew * skew + kurtosis * kurtosis / 4)
            lines.add("residuals ${model.name} n $count mean ${real(mean)} sd ${real(sqrt(s2 / (count - 1)))} dw ${real(dw / squares(errors))} skewness ${real(skew)} kurtosis ${real(kurtosis)} jb ${real(jb)}")
            var line = "ljung_box ${model.name}"
            for (token in settings.settings.getValue("ljung_box")) {
                val lag = token.toInt();
                val result = Autoregression.ljung(errors, lag);
                line += " lag $lag q ${real(result[0])} p ${real(result[1])}"
            }
            lines.add(line)
        }
        return lines
    }
    fun chartLines(): List<String> {
        val rows = holdoutRows[bestIndex].toList() + futureRows;
        val periods = data.periods.drop(trainingCount) + future;
        var low = Double.POSITIVE_INFINITY;
        var high = Double.NEGATIVE_INFINITY
        for (i in rows.indices) {
            low = minOf(low, rows[i][3]);
            high = maxOf(high, rows[i][4]);
            if (i < holdout) {
                low = minOf(low, actual[i]);
                high = maxOf(high, actual[i])
            }
        }
        val lines = mutableListOf("chart ${data.name} method ${best.name}", "scale low ${real(low)} high ${real(high)}")
        for (i in rows.indices) {
            val cells = CharArray(61) {
                ' '
            };
            val row = rows[i];
            for (c in column(row[3], low, high)..column(row[4], low, high)) cells[c] = '-';
            for (c in column(row[1], low, high)..column(row[2], low, high)) cells[c] = '=';
            cells[column(row[0], low, high)] = 'o';
            if (i < holdout) cells[column(actual[i], low, high)] = '*';
            lines.add("${periods[i]} |${cells.concatToString()}|")
        }
        var peak = 0.0;
        for (value in decomposition.multiplicative) peak = maxOf(peak, abs(value - 1));
        lines.add("profile peak ${real(peak)}")
        for (j in 0 until season) {
            val value = decomposition.multiplicative[j];
            val length = floor(abs(value - 1) / peak * 30 + 0.5).toInt();
            val cells = CharArray(61) {
                ' '
            };
            cells[30] = '|';
            if (value > 1) for (c in 31..30 + length) cells[c] = '#' else if (value < 1) for (c in 30 - length until 30) cells[c] = '#';
            lines.add(String.format(Locale.ROOT, "season %2d %s [%s]", j + 1, real(value), cells.concatToString()))
        }
        return lines
    }
    fun planLines(): List<String> {
        val group = data.lead + data.review;
        val start = settings.integer("cv_start");
        val origins = n - group - start + 1;
        var squares = 0.0
        for (origin in start..n - group) {
            val predicted = finalModel.forecast(origin, group);
            var error = 0.0;
            for (k in 0 until group) error += cleaned[origin + k] - predicted[k];
            squares += error * error
        }
        val safety = data.service * sqrt(squares / origins);
        val lines = mutableListOf("series ${data.name} method ${best.name}", "policy on_hand ${data.onHand} lead_time ${data.lead} review ${data.review} service ${real(data.service)} safety_stock ${real(safety)}")
        val end = (horizon - group) / data.review * data.review + group;
        var outstanding = 0;
        var orders = 0;
        var ordered = 0;
        var shorts = 0;
        val arrivals = IntArray(horizon + data.lead + 1);
        var stock = data.onHand.toDouble();
        var lowest = Double.POSITIVE_INFINITY;
        var totalStock = 0.0
        for (k in 0 until end) {
            val receipt = arrivals[k];
            stock += receipt;
            outstanding -= receipt
            if (k % data.review == 0 && k + group <= horizon) {
                val position = stock + outstanding;
                var target = 0.0;
                for (j in k until k + group) target += futureRows[j][0];
                target += safety;
                val quantity = maxOf(0, ceil(target - position).toInt());
                if (quantity > 0) {
                    orders++;
                    ordered += quantity;
                    arrivals[k + data.lead] += quantity;
                    outstanding += quantity
                };
                lines.add("review ${future[k]} position ${real(position)} target ${real(target)} order $quantity")
            }
            stock -= futureRows[k][0];
            val status = if (stock < 0) "short" else if (stock < safety) "low" else "ok";
            if (stock < 0) shorts++;
            lowest = minOf(lowest, stock);
            totalStock += stock
            lines.add("period ${future[k]} demand ${real(futureRows[k][0])} receipt $receipt on_hand ${real(stock)} status $status")
        }
        lines.add("summary orders $orders ordered $ordered short_periods $shorts lowest ${real(lowest)} average ${real(totalStock / end)}")
        val years = sortedMapOf<String, YearTotals>()
        for (t in 0 until n) {
            val year = years.getOrPut(data.periods[t].take(4)) {
                YearTotals()
            };
            year.actualMonths++;
            year.actual += values[t]
        }
        for (k in 0 until horizon) {
            val year = years.getOrPut(future[k].take(4)) {
                YearTotals()
            };
            year.forecastMonths++;
            year.forecast += futureRows[k][0]
        }
        var previous: YearTotals? = null
        for ((label, year) in years) {
            val total = year.actual + year.forecast;
            val prev = previous
            val growth = if (prev != null && prev.actualMonths + prev.forecastMonths == 12 && year.actualMonths + year.forecastMonths == 12) real(100 * (total - (prev.actual + prev.forecast)) / (prev.actual + prev.forecast)) else "NA"
            lines.add("year $label actual_months ${year.actualMonths} actual ${real(year.actual)} forecast_months ${year.forecastMonths} forecast ${real(year.forecast)} total ${real(total)} growth $growth")
            previous = year
        }
        return lines
    }
}
private class YearTotals {
    var actualMonths = 0;
    var forecastMonths = 0;
    var actual = 0.0;
    var forecast = 0.0
}
private fun csv(values: DoubleArray): String = values.joinToString(",") {
    real(it)
}
private fun column(value: Double, low: Double, high: Double): Int = floor((value - low) / (high - low) * 60 + 0.5).toInt()
private fun correlationBar(value: Double, band: Double): String {
    val cells = CharArray(41) {
        ' '
    };
    val length = floor(abs(value) * 20 + 0.5).toInt();
    val limit = floor(band * 20 + 0.5).toInt();
    cells[20 - limit] = ':';
    cells[20 + limit] = ':';
    cells[20] = '|'
    if (value > 0) for (c in 21..20 + length) cells[c] = '#' else if (value < 0) for (c in 20 - length until 20) cells[c] = '#'
    return cells.concatToString()
}
fun main() {
    val settings = SeriesIo();
    val decomposition = mutableListOf("series,period,value,cleaned,trend,seasonal_add,residual_add,seasonal_mult,residual_mult,flag");
    val models = mutableListOf<String>();
    val forecasts = mutableListOf("series,stage,method,period,actual,forecast,lo80,hi80,lo95,hi95");
    val accuracy = mutableListOf("series,method,me,mae,rmse,mape,smape,mase,fva,cv_rmse,cover80,cover95,winkler80,winkler95,rank");
    val crossValidation = mutableListOf("series,method,step,origins,mae,rmse");
    val correlogram = mutableListOf<String>();
    val chart = mutableListOf<String>();
    val plan = mutableListOf<String>()
    for (data in settings.series) {
        val analysis = Analysis(data, settings);
        decomposition.addAll(analysis.decompositionLines());
        models.addAll(analysis.modelLines());
        forecasts.addAll(analysis.forecastLines());
        accuracy.addAll(analysis.accuracyLines());
        crossValidation.addAll(analysis.cvLines());
        correlogram.addAll(analysis.correlogramLines());
        chart.addAll(analysis.chartLines());
        plan.addAll(analysis.planLines())
    }
    Files.createDirectories(Path.of("output"));
    SeriesIo.write("decomposition.csv", decomposition);
    SeriesIo.write("models.txt", models);
    SeriesIo.write("forecasts.csv", forecasts);
    SeriesIo.write("accuracy.csv", accuracy);
    SeriesIo.write("cv.csv", crossValidation);
    SeriesIo.write("correlogram.txt", correlogram);
    SeriesIo.write("chart.txt", chart);
    SeriesIo.write("plan.txt", plan)
}
