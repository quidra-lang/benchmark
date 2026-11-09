class Decomposition(values: DoubleArray, season: Int) {
    val count = values.size;
    val half = season / 2
    val trend = DoubleArray(count) {
        Double.NaN
    };
    val residualAdd = DoubleArray(count) {
        Double.NaN
    };
    val residualMult = DoubleArray(count) {
        Double.NaN
    }
    val additive = DoubleArray(season);
    val multiplicative = DoubleArray(season)
    init {
        val counts = IntArray(season)
        for (t in half until count - half) {
            var total = 0.5 * values[t - half];
            for (i in t - half + 1 until t + half) total += values[i];
            total += 0.5 * values[t + half];
            trend[t] = total / season;
            val position = t % season;
            additive[position] += values[t] - trend[t];
            multiplicative[position] += values[t] / trend[t];
            counts[position]++
        }
        for (j in 0 until season) {
            additive[j] /= counts[j];
            multiplicative[j] /= counts[j]
        }
        val addMean = additive.sum() / season;
        val multMean = multiplicative.sum() / season
        for (j in 0 until season) {
            additive[j] -= addMean;
            multiplicative[j] /= multMean
        }
        for (t in half until count - half) {
            residualAdd[t] = values[t] - trend[t] - additive[t % season];
            residualMult[t] = values[t] / (trend[t] * multiplicative[t % season])
        }
    }
    companion object {
        fun variance(values: DoubleArray): Double {
            val mean = values.sum() / values.size;
            var total = 0.0;
            for (value in values) total += (value - mean) * (value - mean);
            return total / (values.size - 1)
        }
        fun regression(values: DoubleArray): DoubleArray {
            val count = values.size;
            val center = (count + 1) / 2.0;
            val average = values.sum() / count;
            var numerator = 0.0;
            var denominator = 0.0;
            for (t in values.indices) {
                numerator += (t + 1 - center) * (values[t] - average);
                denominator += (t + 1 - center) * (t + 1 - center)
            };
            val slope = numerator / denominator;
            return doubleArrayOf(average - slope * center, slope)
        }
    }
}
