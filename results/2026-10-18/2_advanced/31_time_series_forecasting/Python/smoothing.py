"""Exponential-smoothing state recursions and forecasts from saved origins."""

from decomposition import total


def recurse(name, values, season, parameters):
    alpha = parameters["alpha"]
    beta = parameters.get("beta", 0.0)
    phi = parameters.get("phi", 1.0)
    gamma = parameters.get("gamma", 0.0)
    seasonal = name in ("hw_add", "hw_mult")
    if seasonal:
        level = total(values[:season]) / season
        slope = (total(values[season:2 * season]) / season - level) / season
        components = ([value - level for value in values[:season]] if name == "hw_add"
                      else [value / level for value in values[:season]])
    else:
        level = values[0]
        slope = 0.0 if name == "ses" else (values[season] - values[0]) / season
        components = None
    states = []
    errors = []
    for t, observed in enumerate(values):
        states.append((level, slope, None if components is None else components.copy()))
        if name == "ses":
            predicted = level
            next_level = alpha * observed + (1 - alpha) * level
            next_slope = slope
        elif seasonal:
            position = t % season
            previous = components[position]
            base = level + slope
            if name == "hw_add":
                predicted = base + previous
                next_level = alpha * (observed - previous) + (1 - alpha) * base
                components[position] = gamma * (observed - base) + (1 - gamma) * previous
            else:
                predicted = base * previous
                next_level = alpha * (observed / previous) + (1 - alpha) * base
                components[position] = gamma * (observed / base) + (1 - gamma) * previous
            next_slope = beta * (next_level - level) + (1 - beta) * slope
        else:
            predicted = level + phi * slope
            next_level = alpha * observed + (1 - alpha) * predicted
            next_slope = beta * (next_level - level) + (1 - beta) * phi * slope
        errors.append(observed - predicted)
        level, slope = next_level, next_slope
    states.append((level, slope, None if components is None else components.copy()))
    return errors, states


def forecast(name, state, parameters, origin, steps, season):
    level, slope, components = state
    if name == "ses":
        return [level] * steps
    if name in ("holt", "damped"):
        phi = parameters.get("phi", 1.0)
        power = phi
        accumulated = 0.0
        result = []
        for _ in range(steps):
            accumulated += power
            result.append(level + accumulated * slope)
            power *= phi
        return result
    result = []
    for step in range(1, steps + 1):
        component = components[(origin + step - 1) % season]
        base = level + step * slope
        result.append(base + component if name == "hw_add" else base * component)
    return result
