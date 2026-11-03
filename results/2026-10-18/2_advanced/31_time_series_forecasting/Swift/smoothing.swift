struct SmoothingParameters {
    let alpha: Double
    let beta: Double
    let gamma: Double
    let phi: Double
}

struct SmoothingState {
    let level: Double
    let slope: Double
    let seasonal: [Double]
}

func smoothingRecursion(
    _ name: String, _ values: [Double], _ season: Int, _ parameters: SmoothingParameters
) -> ([Double], [SmoothingState]) {
    let alpha = parameters.alpha
    let beta = parameters.beta
    let gamma = parameters.gamma
    let phi = parameters.phi
    let seasonal = name == "hw_add" || name == "hw_mult"
    var level: Double
    var slope: Double
    var components: [Double] = []
    if seasonal {
        level = total(values.prefix(season)) / Double(season)
        slope = (total(values[season..<(2 * season)]) / Double(season) - level) / Double(season)
        components = values.prefix(season).map { name == "hw_add" ? $0 - level : $0 / level }
    } else {
        level = values[0]
        slope = name == "ses" ? 0 : (values[season] - values[0]) / Double(season)
    }
    var states: [SmoothingState] = []
    var errors: [Double] = []
    for (t, observed) in values.enumerated() {
        states.append(SmoothingState(level: level, slope: slope, seasonal: components))
        let predicted: Double
        let nextLevel: Double
        let nextSlope: Double
        if name == "ses" {
            predicted = level
            nextLevel = alpha * observed + (1 - alpha) * level
            nextSlope = slope
        } else if seasonal {
            let j = t % season
            let previous = components[j]
            let base = level + slope
            if name == "hw_add" {
                predicted = base + previous
                nextLevel = alpha * (observed - previous) + (1 - alpha) * base
                components[j] = gamma * (observed - base) + (1 - gamma) * previous
            } else {
                predicted = base * previous
                nextLevel = alpha * (observed / previous) + (1 - alpha) * base
                components[j] = gamma * (observed / base) + (1 - gamma) * previous
            }
            nextSlope = beta * (nextLevel - level) + (1 - beta) * slope
        } else {
            predicted = level + phi * slope
            nextLevel = alpha * observed + (1 - alpha) * predicted
            nextSlope = beta * (nextLevel - level) + (1 - beta) * phi * slope
        }
        errors.append(observed - predicted)
        level = nextLevel
        slope = nextSlope
    }
    states.append(SmoothingState(level: level, slope: slope, seasonal: components))
    return (errors, states)
}

func smoothingForecast(
    _ name: String, _ state: SmoothingState, _ parameters: SmoothingParameters,
    _ origin: Int, _ steps: Int, _ season: Int
) -> [Double] {
    if name == "ses" {
        return [Double](repeating: state.level, count: steps)
    }
    if name == "holt" || name == "damped" {
        var power = parameters.phi
        var accumulated = 0.0
        var result: [Double] = []
        for _ in 0..<steps {
            accumulated += power
            result.append(state.level + accumulated * state.slope)
            power *= parameters.phi
        }
        return result
    }
    return (1...steps).map { step in
        let component = state.seasonal[(origin + step - 1) % season]
        let base = state.level + Double(step) * state.slope
        return name == "hw_add" ? base + component : base * component
    }
}
