read_examples <- function(path) {
    lines <- strsplit(readLines(path), ",", fixed = TRUE)
    names <- lines[[1L]][-c(1L, length(lines[[1L]]))]
    rows <- lapply(
        lines[-1L],
        function(fields) list(
            id = fields[1L],
            values = as.numeric(fields[-c(1L, length(fields))]),
            label = as.integer(tail(fields, 1L))
        )
    )
    list(names = names, rows = rows)
}
read_inputs <- function() {
    train <- read_examples("input/train.csv")
    test <- read_examples("input/test.csv")
    entries <- list()
    for (fields in strsplit(
        readLines("input/params.txt"),
        " ",
        fixed = TRUE
    )) entries[[fields[1L]]] <- fields[-1L]
    integer <- function(key, i = 1L) as.integer(entries[[key]][i])
    real <- function(key, i = 1L) as.numeric(entries[[key]][i])
    settings <- list(positive = integer("POSITIVE"), degree = integer("DEGREE"), threshold = real("THRESHOLD"), lambdas = as.numeric(entries$LAMBDAS),
        gd_rate = real("GD"), gd_iterations = integer("GD", 2L), sgd_rate = real("SGD"), batch_size = integer("SGD", 2L), epochs = integer("SGD", 3L), sgd_seed = integer(
            "SGD",
            4L
        ),
        softmax_rate = real("SOFTMAX"), softmax_iterations = integer("SOFTMAX", 2L), softmax_lambda = real("SOFTMAX", 3L), bootstrap_count = integer("BOOTSTRAP"), bootstrap_seed = integer(
            "BOOTSTRAP",
            2L
        ),
        permutation_count = integer("PERMUTATION"), permutation_seed = integer(
            "PERMUTATION",
            2L
        ), map_width = integer("MAP"), map_height = integer("MAP", 2L), cost_fp = integer("COST"), cost_fn = integer("COST", 2L))
    list(names = train$names, train = train$rows, test = test$rows, settings = settings)
}
expansion_tuples <- function(base_count, degree) {
    tuples <- list()
    append_tuples <- function(prefix, remaining, first) {
        if (remaining == 0L) tuples[[length(tuples) + 1L]] <<- prefix else for (index in seq.int(first, base_count)) append_tuples(
            c(prefix, index),
            remaining - 1L,
            index
        )
    }
    for (k in seq_len(degree)) append_tuples(integer(), k, 1L)
    tuples
}
expanded_names <- function(names, tuples) vapply(
    tuples,
    function(indices) paste(names[indices], collapse = "*"),
    ""
)
expanded_values <- function(tuples, values) vapply(tuples, function(indices) {
    product <- values[indices[1L]]
    for (index in indices[-1L]) product <- product * values[index]
    product
}, 0)
compute_statistics <- function(rows, count) {
    means <- deviations <- numeric(count)
    for (j in seq_len(count)) {
        total <- 0
        for (row in rows) total <- total + row[j]
        mean <- total / length(rows)
        squares <- 0
        for (row in rows) squares <- squares + (row[j] - mean) * (row[j] - mean)
        means[j] <- mean
        deviations[j] <- sqrt(squares / (length(rows) - 1L))
    }
    list(means = means, deviations = deviations)
}
standardize <- function(values, statistics, count) c(
    1,
    (values[seq_len(count)] - statistics$means[seq_len(count)]) / statistics$deviations[seq_len(count)]
)
