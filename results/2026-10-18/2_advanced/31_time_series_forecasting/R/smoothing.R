smoothing_recurse <- function(name, values, season, parameters) {
    alpha <- parameters$alpha
    beta <- if (is.null(parameters$beta)) 0 else parameters$beta
    phi <- if (is.null(parameters$phi)) 1 else parameters$phi
    gamma <- if (is.null(parameters$gamma)) 0 else parameters$gamma
    seasonal <- name %in% c("hw_add", "hw_mult")
    if (seasonal) {
        level <- ordered_sum(values[seq_len(season)]) / season
        slope <- (ordered_sum(values[seq.int(season + 1L, 2L * season)]) / season - level) / season
        components <- if (name == "hw_add") values[seq_len(season)] - level else values[seq_len(season)] / level
    } else {
        level <- values[1L]
        slope <- if (name == "ses") 0 else (values[season + 1L] - values[1L]) / season
        components <- NULL
    }
    states <- list()
    errors <- numeric(length(values))
    for (t in seq_along(values)) {
        observed <- values[t]
        states[[t]] <- list(level = level, slope = slope, components = components)
        if (name == "ses") {
            predicted <- level
            next_level <- alpha * observed + (1 - alpha) * level
            next_slope <- slope
        } else if (seasonal) {
            position <- (t - 1L) %% season + 1L
            previous <- components[position]
            base <- level + slope
            if (name == "hw_add") {
                predicted <- base + previous
                next_level <- alpha * (observed - previous) + (1 - alpha) * base
                components[position] <- gamma * (observed - base) + (1 - gamma) * previous
            } else {
                predicted <- base * previous
                next_level <- alpha * (observed / previous) + (1 - alpha) * base
                components[position] <- gamma * (observed / base) + (1 - gamma) * previous
            }
            next_slope <- beta * (next_level - level) + (1 - beta) * slope
        } else {
            predicted <- level + phi * slope
            next_level <- alpha * observed + (1 - alpha) * predicted
            next_slope <- beta * (next_level - level) + (1 - beta) * phi * slope
        }
        errors[t] <- observed - predicted
        level <- next_level
        slope <- next_slope
    }
    states[[length(values) + 1L]] <- list(level = level, slope = slope, components = components)
    list(errors = errors, states = states)
}
smoothing_forecast <- function(name, state, parameters, origin, steps, season) {
    level <- state$level
    slope <- state$slope
    components <- state$components
    if (name == "ses") return(rep(level, steps))
    result <- numeric(steps)
    if (name %in% c("holt", "damped")) {
        phi <- if (is.null(parameters$phi)) 1 else parameters$phi
        power <- phi
        accumulated <- 0
        for (step in seq_len(steps)) {
            accumulated <- accumulated + power
            result[step] <- level + accumulated * slope
            power <- power * phi
        }
    } else for (step in seq_len(steps)) {
        component <- components[(origin + step - 1L) %% season + 1L]
        base <- level + step * slope
        result[step] <- if (name == "hw_add") base + component else base * component
    }
    result
}
