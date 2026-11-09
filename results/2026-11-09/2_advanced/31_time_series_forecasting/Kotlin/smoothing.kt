data class SmoothState(val level: Double, val slope: Double, val components: DoubleArray)
data class SmoothRun(val errors: DoubleArray, val states: List<SmoothState>)
object Smoothing {
    fun recurse(name: String, values: DoubleArray, season: Int, alpha: Double, beta: Double, gamma: Double, phi: Double): SmoothRun {
        val seasonal = name.startsWith("hw_");
        var level = values[0];
        var slope = if (name == "ses") 0.0 else (values[season] - values[0]) / season;
        val components = DoubleArray(season)
        if (seasonal) {
            var first = 0.0;
            var second = 0.0;
            for (t in 0 until season) first += values[t];
            for (t in season until 2 * season) second += values[t];
            level = first / season;
            slope = (second / season - level) / season;
            for (j in 0 until season) components[j] = if (name == "hw_add") values[j] - level else values[j] / level
        }
        val states = mutableListOf<SmoothState>();
        val errors = DoubleArray(values.size)
        for (t in values.indices) {
            states.add(SmoothState(level, slope, components.copyOf()));
            val observed = values[t];
            val predicted: Double;
            val nextLevel: Double;
            val nextSlope: Double
            if (name == "ses") {
                predicted = level;
                nextLevel = alpha * observed + (1 - alpha) * level;
                nextSlope = slope
            }
            else if (seasonal) {
                val position = t % season;
                val previous = components[position];
                val base = level + slope;
                if (name == "hw_add") {
                    predicted = base + previous;
                    nextLevel = alpha * (observed - previous) + (1 - alpha) * base;
                    components[position] = gamma * (observed - base) + (1 - gamma) * previous
                } else {
                    predicted = base * previous;
                    nextLevel = alpha * (observed / previous) + (1 - alpha) * base;
                    components[position] = gamma * (observed / base) + (1 - gamma) * previous
                };
                nextSlope = beta * (nextLevel - level) + (1 - beta) * slope
            }
            else {
                predicted = level + phi * slope;
                nextLevel = alpha * observed + (1 - alpha) * predicted;
                nextSlope = beta * (nextLevel - level) + (1 - beta) * phi * slope
            }
            errors[t] = observed - predicted;
            level = nextLevel;
            slope = nextSlope
        }
        states.add(SmoothState(level, slope, components.copyOf()));
        return SmoothRun(errors, states)
    }
    fun forecast(name: String, state: SmoothState, origin: Int, steps: Int, season: Int, phi: Double): DoubleArray {
        val result = DoubleArray(steps);
        var power = phi;
        var accumulated = 0.0
        for (k in 1..steps) if (name == "ses") result[k - 1] = state.level else if (name == "holt" || name == "damped") {
            accumulated += power;
            result[k - 1] = state.level + accumulated * state.slope;
            power *= phi
        } else {
            val base = state.level + k * state.slope;
            val component = state.components[(origin + k - 1) % season];
            result[k - 1] = if (name == "hw_add") base + component else base * component
        }
        return result
    }
}
