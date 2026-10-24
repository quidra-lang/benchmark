categories <- c('VFR', 'MVFR', 'IFR', 'LIFR')
covers <- function(f, o) {
    h <- o$time - o$time %% 60L
    f$time <= o$time && f$start <= h && h < f$finish
}

select_taf <- function(forecasts, o) {
    chosen <- NULL
    for (f in forecasts) if (covers(f, o) && (is.null(chosen) || f$time >= chosen$time)) chosen <- f
    chosen
}

compare_forecasts <- function(observations, forecasts) {
    table <- matrix(0L, 4L, 4L)
    selected <- list()
    missing <- 0L
    temporary_hits <- 0L
    for (o in observations) {
        f <- select_taf(forecasts, o)
        if (is.null(f)) {
            missing <- missing + 1L
            next
        }
        states <- f$hours[[as.character(o$time - o$time %% 60L)]]
        category <- states$state$category
        possible <- c(category, vapply(states$temporary, function(c) c$state$category, ''))
        i <- match(category, categories)
        j <- match(o$state$category, categories)
        table[i, j] <- table[i, j] + 1L
        if (o$state$category %in% possible) temporary_hits <- temporary_hits + 1L
        selected[[length(selected) + 1L]] <- list(observation = o, states = states, possible = possible)
    }
    rows <- vapply(seq_len(4L), function(i) sum(table[i, ]), 0L)
    columns <- vapply(seq_len(4L), function(i) sum(table[, i]), 0L)
    n <- sum(rows)
    hits <- sum(diag(table))
    expected <- sum(rows * columns)
    list(table = table, rows = rows, columns = columns, total = n, hits = hits, temporary_hits = temporary_hits,
    no_forecast = missing, selected = selected, skill = c(n * hits - expected, n * n - expected),
    pod = lapply(seq_len(4L), function(i) c(table[i, i], columns[i])),
    far = lapply(seq_len(4L), function(i) c(rows[i] - table[i, i], rows[i])))
}
