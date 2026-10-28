import kotlin.math.exp

data class Correlations(val mean: Double, val variance: Double, val acf: DoubleArray)
data class Durbin(val coefficients: Array<DoubleArray>, val partial: DoubleArray, val variances: DoubleArray)
object Autoregression {
    val kinds = listOf("none", "first", "seasonal", "both")
    fun offset(kind: String, season: Int): Int = when (kind) {
        "none" -> 0;
        "first" -> 1;
        "seasonal" -> season;
        else -> season + 1
    }
    fun difference(values: DoubleArray, season: Int, kind: String): DoubleArray {
        val offset = offset(kind, season);
        return DoubleArray(values.size - offset) {
            i -> val t = i + offset;
            when (kind) {
                "none" -> values[t];
                "first" -> values[t] - values[t - 1];
                "seasonal" -> values[t] - values[t - season];
                else -> (values[t] - values[t - 1]) - (values[t - season] - values[t - season - 1])
            }
        }
    }
    fun correlations(values: DoubleArray, maximum: Int): Correlations {
        val mean = values.sum() / values.size;
        val centered = DoubleArray(values.size) {
            values[it] - mean
        };
        var variance = 0.0;
        for (value in centered) variance += value * value;
        variance /= values.size
        val acf = DoubleArray(maximum + 1);
        acf[0] = 1.0
        for (lag in 1..maximum) {
            var total = 0.0;
            for (i in 0 until values.size - lag) total += centered[i] * centered[i + lag];
            acf[lag] = total / values.size / variance
        }
        return Correlations(mean, variance, acf)
    }
    fun durbin(correlations: DoubleArray): Durbin {
        val count = correlations.size;
        val coefficients = Array(count) {
            DoubleArray(it)
        };
        val partial = DoubleArray(count);
        val variances = DoubleArray(count);
        variances[0] = 1.0
        for (order in 1 until count) {
            val previous = coefficients[order - 1];
            var correction = 0.0;
            for (j in 1 until order) correction += previous[j - 1] * correlations[order - j];
            val theta = (correlations[order] - correction) / variances[order - 1];
            val current = coefficients[order];
            for (j in 1 until order) current[j - 1] = previous[j - 1] - theta * previous[order - j - 1];
            current[order - 1] = theta;
            partial[order] = theta;
            variances[order] = variances[order - 1] * (1 - theta * theta)
        }
        return Durbin(coefficients, partial, variances)
    }
    fun residuals(values: DoubleArray, mean: Double, coefficients: DoubleArray): DoubleArray = DoubleArray(values.size - coefficients.size) {
        position -> val i = position + coefficients.size;
        var total = 0.0;
        for (j in 1..coefficients.size) total += coefficients[j - 1] * (values[i - j] - mean);
        values[i] - mean - total
    }
    fun forecast(values: DoubleArray, differenced: DoubleArray, kind: String, mean: Double, coefficients: DoubleArray, origin: Int, steps: Int, season: Int): DoubleArray {
        val count = origin - offset(kind, season);
        val transformed = differenced.copyOf(count + steps);
        val extended = values.copyOf(origin + steps);
        val result = DoubleArray(steps)
        for (k in 0 until steps) {
            var total = 0.0;
            for (j in 1..coefficients.size) total += coefficients[j - 1] * (transformed[count + k - j] - mean);
            var predicted = mean + total;
            transformed[count + k] = predicted;
            val position = origin + k;
            when (kind) {
                "first" -> predicted += extended[position - 1];
                "seasonal" -> predicted += extended[position - season];
                "both" -> predicted = predicted + extended[position - 1] + extended[position - season] - extended[position - season - 1]
            };
            extended[position] = predicted;
            result[k] = predicted
        }
        return result
    }
    fun ljung(errors: DoubleArray, lag: Int): DoubleArray {
        val correlations = correlations(errors, lag).acf;
        val count = errors.size;
        var total = 0.0;
        for (k in 1..lag) total += correlations[k] * correlations[k] / (count - k);
        val q = count * (count + 2.0) * total;
        val x = q / 2;
        var term = 1.0;
        var terms = 1.0;
        for (i in 1 until lag / 2) {
            term = term * x / i;
            terms += term
        };
        return doubleArrayOf(q, exp(-x) * terms)
    }
}
