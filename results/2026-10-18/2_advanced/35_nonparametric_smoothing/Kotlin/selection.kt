object Selection {
    fun sum(values: DoubleArray): Double {
        var total = 0.0;
        for (value in values) total += value;
        return total
    }
    fun score(observed: DoubleArray, predicted: DoubleArray): Double {
        var total = 0.0;
        for (i in observed.indices) {
            if (predicted[i].isNaN()) return Double.NaN;
            val e = observed[i] - predicted[i];
            total += e * e
        };
        return total / observed.size
    }
    fun generalized(observed: DoubleArray, fitted: DoubleArray, edf: Double): Double {
        val tau = 1 - edf / observed.size;
        return score(observed,fitted) / (tau * tau)
    }
    fun choose(scores: DoubleArray): Int {
        var best = -1;
        for (i in scores.indices) if (!scores[i].isNaN() && (best < 0 || scores[i] < scores[best])) best = i;
        return best
    }
}
