for (file in c("dataset", "logistic", "optimizers", "softmax", "metrics")) source(paste0(file, ".R"))

vector_length <- function(values) sqrt(ordered_sum(values * values))
final_weights <- function(checkpoints) tail(checkpoints, 1L)[[1L]]$weights
model_probabilities <- function(w, x) vapply(x, function(v) probability(score(w, v)), 0)
predict <- function(probabilities, threshold) as.integer(probabilities >= threshold)
count_equal <- function(a, b) sum(a == b)
softmax_correct <- function(w, x, labels) count_equal(
    vapply(x, function(v) predicted_class(softmax_probabilities(w, v)), 0L),
    labels
)
line_text <- function(...) paste(c(...), collapse = " ")
make_data <- function(names, train, test, settings) {
    tuples <- expansion_tuples(length(names), settings$degree)
    feature_names <- expanded_names(names, tuples)
    feature_count <- length(tuples)
    train_expanded <- lapply(train, function(row) expanded_values(tuples, row$values))
    test_expanded <- lapply(test, function(row) expanded_values(tuples, row$values))
    overall <- compute_statistics(train_expanded, feature_count)
    train_vectors <- lapply(train_expanded, standardize, statistics = overall, count = feature_count)
    test_vectors <- lapply(test_expanded, standardize, statistics = overall, count = feature_count)
    train_labels <- vapply(train, function(row) row$label, 0L)
    test_labels <- vapply(test, function(row) row$label, 0L)
    list(names = names, train = train, test = test, settings = settings, tuples = tuples, feature_names = feature_names, feature_count = feature_count,
        degree_counts = vapply(
            seq_len(settings$degree),
            function(degree) sum(lengths(tuples) <= degree),
            0L
        ), classes = max(train_labels) + 1L,
        train_expanded = train_expanded, test_expanded = test_expanded, overall = overall, train_vectors = train_vectors, test_vectors = test_vectors, train_labels = train_labels, test_labels = test_labels,
        train_targets = as.integer(train_labels == settings$positive), test_targets = as.integer(test_labels == settings$positive), mean_values = overall$means[seq_along(names)])
}
data_vector <- function(data, values) standardize(
    expanded_values(data$tuples, values),
    data$overall,
    data$feature_count
)
evaluate <- function(w, x, y, threshold) {
    probabilities <- model_probabilities(w, x)
    predictions <- predict(probabilities, threshold)
    list(
        probabilities = probabilities,
        predictions = predictions,
        loss = average_loss(w, x, y),
        correct = count_equal(predictions, y),
        auc = auc(probabilities, y)
    )
}
binary_model <- function(name, checkpoints, data) {
    w <- final_weights(checkpoints)
    train <- evaluate(w, data$train_vectors, data$train_targets, data$settings$threshold)
    test <- evaluate(w, data$test_vectors, data$test_targets, data$settings$threshold)
    list(
        name = name,
        checkpoints = checkpoints,
        weights = w,
        train = train,
        test = test,
        roc = roc_points(test$probabilities, data$test_targets)
    )
}
inverse_matrix <- function(matrix) {
    count <- nrow(matrix)
    lower <- cholesky_lower(matrix)
    result <- matrix(0, count, count)
    for (k in seq_len(count)) {
        unit <- numeric(count)
        unit[k] <- 1
        result[, k] <- solve_lower(lower, unit)
    }
    result
}
influence <- function(w, x, y, lambda) {
    dimension <- length(w)
    n <- length(x)
    matrix <- inverse_matrix(hessian(w, x, lambda))
    probabilities <- leverages <- residuals <- distances <- numeric(n)
    for (i in seq_along(x)) {
        v <- x[[i]]
        pi <- probability(score(w, v))
        variance <- pi * (1 - pi)
        quadratic <- 0
        for (j in seq_len(dimension)) for (k in seq_len(dimension)) quadratic <- quadratic + v[j] * matrix[
            j,
            k
        ] * v[k]
        leverage <- variance * quadratic / n
        pearson <- (y[i] - pi) / sqrt(variance)
        probabilities[i] <- pi
        leverages[i] <- leverage
        residuals[i] <- pearson / sqrt(1 - leverage)
        distances[i] <- pearson * pearson * leverage / (dimension * ((1 - leverage) * (1 - leverage)))
    }
    edf <- ordered_sum(leverages)
    deviance <- 2 * n * average_loss(w, x, y)
    list(
        matrix = matrix,
        probabilities = probabilities,
        leverages = leverages,
        residuals = residuals,
        distances = distances,
        edf = edf,
        deviance = deviance,
        aic = deviance + 2 * edf,
        bic = deviance + log(n) * edf
    )
}
original_units <- function(w, statistics) {
    scaled <- w[-1L] / statistics$deviations[seq_len(length(w) - 1L)]
    shift <- ordered_sum(scaled * statistics$means[seq_along(scaled)])
    c(w[1L] - shift, scaled)
}
cross_validate <- function(data, lambda, count) {
    n <- length(data$train)
    losses <- probabilities <- numeric(n)
    fold_losses <- numeric(5L)
    errors <- 0L
    for (fold in seq.int(0L, 4L)) {
        fitting <- which((seq_len(n) - 1L) %% 5L != fold)
        checking <- which((seq_len(n) - 1L) %% 5L == fold)
        statistics <- compute_statistics(data$train_expanded[fitting], count)
        x <- lapply(data$train_expanded[fitting], standardize, statistics = statistics, count = count)
        w <- final_weights(newton_method(x, data$train_targets[fitting], lambda))
        total <- 0
        for (i in checking) {
            u <- score(w, standardize(data$train_expanded[[i]], statistics, count))
            losses[i] <- logistic_loss(u, data$train_targets[i])
            probabilities[i] <- probability(u)
            total <- total + losses[i]
            errors <- errors + as.integer(as.integer(probabilities[i] >= data$settings$threshold) != data$train_targets[i])
        }
        fold_losses[fold + 1L] <- total / length(checking)
    }
    list(
        lambda = lambda,
        fold_losses = fold_losses,
        loss = ordered_sum(losses) / n,
        probabilities = probabilities,
        errors = errors
    )
}
select_lambda <- function(results) {
    best <- results[[1L]]
    for (result in results) if (result$loss <= best$loss) best <- result
    mean <- ordered_sum(best$fold_losses) / 5
    se <- sqrt(ordered_sum((best$fold_losses - mean) * (best$fold_losses - mean)) / 4) / sqrt(5)
    one_se <- max(vapply(
        Filter(function(result) result$loss <= best$loss + se, results),
        function(result) result$lambda,
        0
    ))
    list(best = best, se = se, one_se = one_se)
}
bin_index <- function(value) min(9L, as.integer(floor(value * 10)))
bin_range <- function(index) paste0(fixed(index / 10, 1L), "-", fixed((index + 1L) / 10, 1L))
fill_bins <- function(values, hits) {
    counts <- successes <- integer(10L)
    totals <- numeric(10L)
    for (i in seq_along(values)) {
        bin <- bin_index(values[i]) + 1L
        counts[bin] <- counts[bin] + 1L
        totals[bin] <- totals[bin] + values[i]
        successes[bin] <- successes[bin] + hits[i]
    }
    list(counts = counts, totals = totals, hits = successes)
}
bin_lines <- function(bins, mean_label, rate_label) vapply(seq_len(10L), function(i) {
    mean <- if (bins$counts[i] == 0L) "-" else fixed(bins$totals[i] / bins$counts[i])
    line_text(
        "bin",
        bin_range(i - 1L),
        "count",
        bins$counts[i],
        mean_label,
        mean,
        rate_label,
        ratio(bins$hits[i], bins$counts[i])
    )
}, "")
calibration_error <- function(
    bins,
    n
) ordered_sum(abs(bins$totals[bins$counts > 0L] - bins$hits[bins$counts > 0L])) / n
calibration_lines <- function(probabilities, targets) {
    bins <- fill_bins(probabilities, targets)
    filled <- which(bins$counts > 0L)
    mce <- max(c(0, abs(bins$totals[filled] / bins$counts[filled] - bins$hits[filled] / bins$counts[filled])))
    statistic <- ordered_sum(vapply(
        filled,
        function(i) (bins$hits[i] - bins$totals[i]) ^ 2 / (bins$totals[i] * (1 - bins$totals[i] / bins$counts[i])),
        0
    ))
    c(
        "calibration",
        bin_lines(bins, "mean_probability", "positive_rate"),
        line_text(
            "ece",
            fixed(calibration_error(bins, length(targets))),
            "mce",
            fixed(mce),
            "hosmer_lemeshow",
            fixed(statistic),
            "groups",
            length(filled)
        )
    )
}
gains_lines <- function(probabilities, targets) {
    n <- length(targets)
    pos <- sum(targets)
    order <- order(-probabilities, seq_along(probabilities))
    lines <- "gains"
    for (decile in seq_len(10L)) {
        rows <- (decile * n) %/% 10L
        hits <- sum(targets[order[seq_len(rows)]])
        lines <- c(
            lines,
            line_text(
                "decile",
                decile,
                "rows",
                rows,
                "positives",
                hits,
                "gain",
                ratio(hits, pos),
                "lift",
                ratio(hits * n, rows * pos)
            )
        )
    }
    lines
}
term_lines <- function(data, w) {
    original <- original_units(w, data$overall)
    names <- c("intercept", data$feature_names)
    vapply(
        seq_along(w),
        function(j) line_text("term", names[j], "standardized", fixed(w[j]), "original", fixed(original[j])),
        ""
    )
}
weights_parts <- function(data, models, multi, inf, lambda) {
    n <- length(data$train)
    p <- data$feature_count
    correlation <- matrix(0, p, p)
    for (j in seq_len(p)) for (k in seq_len(p)) correlation[j, k] <- ordered_sum(vapply(
        data$train_vectors,
        function(v) v[j + 1L] * v[k + 1L],
        0
    )) / (n - 1L)
    inflation <- inverse_matrix(correlation)
    lines <- c(
        line_text("features", length(data$names), "degree", data$settings$degree, "expanded", p),
        "standardization"
    )
    add <- function(...) lines <<- c(lines, line_text(...))
    for (j in seq_len(p)) add(
        data$feature_names[j],
        "mean",
        fixed(data$overall$means[j], 6L),
        "sd",
        fixed(data$overall$deviations[j], 6L),
        "vif",
        fixed(inflation[j, j])
    )
    add("correlation")
    for (j in seq_len(p)) add(vapply(correlation[j, ], fixed, ""))
    parts <- list(lines)
    nw <- models[[3L]]$weights
    for (model in models) {
        lines <- c(
            line_text("model", model$name, "lambda", fixed(lambda)),
            term_lines(data, model$weights),
            line_text("norm", fixed(vector_length(model$weights[-1L])))
        )
        if (model$name != "newton") add("distance_to_newton", fixed(vector_length(model$weights - nw), 6L))
        parts <- c(parts, list(lines))
    }
    lines <- line_text("coefficients", "newton", "lambda", fixed(lambda))
    names <- c("intercept", data$feature_names)
    for (j in seq_along(nw)) {
        w <- nw[j]
        se <- sqrt(inf$matrix[j, j] / n)
        add(
            names[j],
            "weight",
            fixed(w),
            "se",
            fixed(se),
            "z",
            fixed(w / se),
            "lower",
            fixed(w - 1.96 * se),
            "upper",
            fixed(w + 1.96 * se),
            "odds_ratio",
            fixed(exp(w))
        )
    }
    parts <- c(parts, list(lines))
    lines <- line_text("model", "softmax", "lambda", fixed(data$settings$softmax_lambda))
    for (k in seq_along(multi$weights)) {
        add("class", k - 1L)
        lines <- c(lines, term_lines(data, multi$weights[[k]]))
    }
    c(parts, list(lines))
}
loss_trace_lines <- function(data, models, multi, lambda) {
    lines <- "optimizer,iteration,loss,gradient_norm,test_loss"
    for (model in models) for (checkpoint in model$checkpoints) {
        w <- checkpoint$weights
        value <- objective(w, data$train_vectors, data$train_targets, lambda)
        norm <- vector_length(gradient(w, data$train_vectors, data$train_targets, lambda))
        test_loss <- average_loss(w, data$test_vectors, data$test_targets)
        lines <- c(
            lines,
            paste(
                model$name,
                checkpoint$iteration,
                fixed(value, 6L),
                fixed(norm, 6L),
                fixed(test_loss, 6L),
                sep = ","
            )
        )
    }
    for (checkpoint in multi$checkpoints) {
        w <- checkpoint$weights
        value <- softmax_objective(w, data$train_vectors, data$train_labels, data$settings$softmax_lambda)
        gradients <- softmax_gradient(w, data$train_vectors, data$train_labels, data$settings$softmax_lambda)
        norm <- vector_length(unlist(gradients, use.names = FALSE))
        test_loss <- softmax_average_loss(w, data$test_vectors, data$test_labels)
        lines <- c(
            lines,
            paste(
                "softmax",
                checkpoint$iteration,
                fixed(value, 6L),
                fixed(norm, 6L),
                fixed(test_loss, 6L),
                sep = ","
            )
        )
    }
    lines
}
prediction_lines <- function(data, models, multi) {
    lines <- "id,model,probability,predicted,actual"
    for (model in models) for (i in seq_along(data$test)) lines <- c(
        lines,
        paste(
            data$test[[i]]$id,
            model$name,
            fixed(model$test$probabilities[i], 6L),
            model$test$predictions[i],
            data$test_targets[i],
            sep = ","
        )
    )
    for (i in seq_along(data$test)) {
        predicted <- multi$test_predictions[i]
        confidence <- multi$test_probabilities[[i]][predicted + 1L]
        lines <- c(
            lines,
            paste(
                data$test[[i]]$id,
                "softmax",
                fixed(confidence, 6L),
                predicted,
                data$test[[i]]$label,
                sep = ","
            )
        )
    }
    lines
}
roc_lines <- function(data, models) {
    pos <- sum(data$test_targets)
    neg <- length(data$test) - pos
    lines <- "model,threshold,tpr,fpr,precision"
    for (model in models) {
        lines <- c(lines, paste0(model$name, ",inf,0.0000,0.0000,-"))
        for (point in model$roc) lines <- c(
            lines,
            paste(
                model$name,
                fixed(point$threshold, 6L),
                ratio(point$tp, pos),
                ratio(point$fp, neg),
                ratio(point$tp, point$tp + point$fp),
                sep = ","
            )
        )
    }
    lines
}
data_part <- function(data) {
    n <- length(data$train)
    m <- length(data$test)
    k <- data$classes
    train <- vapply(seq.int(0L, k - 1L), function(c) sum(data$train_labels == c), 0L)
    test <- vapply(seq.int(0L, k - 1L), function(c) sum(data$test_labels == c), 0L)
    c(line_text("data", "train", n, "test", m, "base_features", length(data$names), "degree", data$settings$degree, "features", data$feature_count),
      line_text(
          "binary",
          "positive_class",
          data$settings$positive,
          "train",
          paste(sum(data$train_targets), n, sep = "/"),
          "test",
          paste(sum(data$test_targets), m, sep = "/")
      ),
      line_text("classes", k, "train", train, "test", test))
}
validation_part <- function(data, results, selection) {
    n <- length(data$train)
    lines <- "cross_validation folds 5 newton_iterations 10"
    add <- function(...) lines <<- c(lines, line_text(...))
    for (result in results) add(
        "lambda",
        fixed(result$lambda),
        "fold_loss",
        vapply(result$fold_losses, fixed, "", places = 6L),
        "cv_loss",
        fixed(result$loss, 6L),
        "errors",
        paste(result$errors, n, sep = "/")
    )
    best <- selection$best
    add(
        "selected",
        "lambda",
        fixed(best$lambda),
        "cv_loss",
        fixed(best$loss, 6L),
        "se",
        fixed(selection$se, 6L),
        "lambda_1se",
        fixed(selection$one_se)
    )
    c <- confusion(predict(best$probabilities, data$settings$threshold), data$train_targets)
    add(
        "out_of_fold",
        "tp",
        c$tp,
        "fp",
        c$fp,
        "tn",
        c$tn,
        "fn",
        c$fn,
        "accuracy",
        ratio(c$tp + c$tn, n),
        "auc",
        fraction(auc(best$probabilities, data$train_targets))
    )
    lines
}
lambda_path_part <- function(data) {
    lines <- "lambda_path"
    for (lambda in data$settings$lambdas) {
        w <- final_weights(newton_method(data$train_vectors, data$train_targets, lambda))
        train <- evaluate(w, data$train_vectors, data$train_targets, data$settings$threshold)
        test <- evaluate(w, data$test_vectors, data$test_targets, data$settings$threshold)
        lines <- c(
            lines,
            line_text(
                "lambda",
                fixed(lambda),
                "objective",
                fixed(objective(w, data$train_vectors, data$train_targets, lambda), 6L),
                "train_loss",
                fixed(train$loss, 6L),
                "test_loss",
                fixed(test$loss, 6L),
                "train_accuracy",
                ratio(train$correct, length(data$train)),
                "test_accuracy",
                ratio(test$correct, length(data$test)),
                "norm",
                fixed(vector_length(w[-1L]))
            )
        )
    }
    lines
}
degree_part <- function(data, lambda) {
    lines <- line_text("degrees", "lambda", fixed(lambda))
    for (degree in seq_along(data$degree_counts)) {
        q <- data$degree_counts[degree]
        x <- lapply(data$train_vectors, function(v) v[seq_len(q + 1L)])
        z <- lapply(data$test_vectors, function(v) v[seq_len(q + 1L)])
        w <- final_weights(newton_method(x, data$train_targets, lambda))
        cv <- cross_validate(data, lambda, q)
        train <- evaluate(w, x, data$train_targets, data$settings$threshold)
        test <- evaluate(w, z, data$test_targets, data$settings$threshold)
        inf <- influence(w, x, data$train_targets, lambda)
        lines <- c(
            lines,
            line_text(
                "degree",
                degree,
                "features",
                q,
                "cv_loss",
                fixed(cv$loss, 6L),
                "train_loss",
                fixed(train$loss, 6L),
                "test_loss",
                fixed(test$loss, 6L),
                "test_accuracy",
                ratio(test$correct, length(data$test)),
                "auc",
                fraction(test$auc),
                "edf",
                fixed(inf$edf),
                "aic",
                fixed(inf$aic),
                "bic",
                fixed(inf$bic)
            )
        )
    }
    lines
}
learning_part <- function(data, lambda) {
    lines <- line_text("learning_curve", "lambda", fixed(lambda))
    for (k in seq_len(4L)) {
        n <- (k * length(data$train)) %/% 4L
        statistics <- compute_statistics(data$train_expanded[seq_len(n)], data$feature_count)
        x <- lapply(
            data$train_expanded[seq_len(n)],
            standardize,
            statistics = statistics,
            count = data$feature_count
        )
        z <- lapply(data$test_expanded, standardize, statistics = statistics, count = data$feature_count)
        y <- data$train_targets[seq_len(n)]
        w <- final_weights(newton_method(x, y, lambda))
        train <- evaluate(w, x, y, data$settings$threshold)
        test <- evaluate(w, z, data$test_targets, data$settings$threshold)
        lines <- c(
            lines,
            line_text(
                "size",
                n,
                "train_loss",
                fixed(train$loss, 6L),
                "test_loss",
                fixed(test$loss, 6L),
                "test_accuracy",
                ratio(test$correct, length(data$test)),
                "auc",
                fraction(test$auc)
            )
        )
    }
    lines
}
cost_of <- function(point, pos, settings) settings$cost_fp * point$fp + settings$cost_fn * (pos - point$tp)
binary_part <- function(data, model, lambda) {
    y <- data$test_targets
    m <- length(y)
    pos <- sum(y)
    neg <- m - pos
    c <- confusion(model$test$predictions, y)
    tp <- c$tp
    fp <- c$fp
    tn <- c$tn
    fn <- c$fn
    brier <- ordered_sum((model$test$probabilities - y) * (model$test$probabilities - y)) / m
    youden <- model$roc[[which.max(vapply(model$roc, function(point) point$tp * neg - point$fp * pos, 0L))]]
    best_f1 <- model$roc[[1L]]
    for (point in model$roc) if (point$tp * (pos + best_f1$tp + best_f1$fp) > best_f1$tp * (pos + point$tp + point$fp)) best_f1 <- point
    cheapest <- model$roc[[which.min(vapply(
        model$roc,
        function(point) cost_of(point, pos, data$settings),
        0L
    ))]]
    total <- 0
    previous <- 0L
    for (point in model$roc) {
        total <- total + (point$tp - previous) * point$tp / (point$tp + point$fp)
        previous <- point$tp
    }
    lines <- line_text("model", model$name, "lambda", fixed(lambda))
    add <- function(...) lines <<- c(lines, line_text(...))
    add(
        "train",
        "correct",
        paste(model$train$correct, length(data$train), sep = "/"),
        "accuracy",
        ratio(model$train$correct, length(data$train))
    )
    add("test", "tp", tp, "fp", fp, "tn", tn, "fn", fn)
    add(
        "test",
        "accuracy",
        ratio(tp + tn, m),
        "precision",
        ratio(tp, tp + fp),
        "recall",
        ratio(tp, tp + fn),
        "specificity",
        ratio(tn, tn + fp),
        "f1",
        ratio(2L * tp, 2L * tp + fp + fn)
    )
    add("log_loss", fixed(model$test$loss, 6L), "brier", fixed(brier, 6L))
    add("auc", fraction(model$test$auc), "average_precision", fixed(total / pos))
    add(
        "youden",
        "threshold",
        fixed(youden$threshold, 6L),
        "tpr",
        ratio(youden$tp, pos),
        "fpr",
        ratio(youden$fp, neg),
        "j",
        ratio(youden$tp * neg - youden$fp * pos, pos * neg)
    )
    add(
        "best_f1",
        "threshold",
        fixed(best_f1$threshold, 6L),
        "precision",
        ratio(best_f1$tp, best_f1$tp + best_f1$fp),
        "recall",
        ratio(best_f1$tp, pos),
        "f1",
        ratio(2L * best_f1$tp, pos + best_f1$tp + best_f1$fp)
    )
    add(
        "min_cost",
        "threshold",
        fixed(cheapest$threshold, 6L),
        "cost",
        cost_of(cheapest, pos, data$settings),
        "fp",
        cheapest$fp,
        "fn",
        pos - cheapest$tp
    )
    c(lines, calibration_lines(model$test$probabilities, y), gains_lines(model$test$probabilities, y))
}
comparison_part <- function(data, models) {
    lines <- character()
    n <- length(data$test)
    for (pair in list(c(1L, 2L), c(1L, 3L), c(2L, 3L))) {
        first <- models[[pair[1L]]]
        second <- models[[pair[2L]]]
        x <- first$test$predictions
        z <- second$test$predictions
        y <- data$test_targets
        only_first <- sum(x == y & z != y)
        only_second <- sum(z == y & x != y)
        gap <- abs(only_first - only_second) - 1L
        lines <- c(
            lines,
            line_text(
                "agreement",
                first$name,
                second$name,
                "same",
                paste(count_equal(x, z), n, sep = "/"),
                "only_first",
                only_first,
                "only_second",
                only_second,
                "mcnemar",
                ratio(gap * gap, only_first + only_second)
            )
        )
    }
    lines
}
slope <- function(tuples, original, values, base) {
    total <- 0
    for (j in seq_along(tuples)) {
        indices <- tuples[[j]]
        occurrences <- sum(indices == base)
        if (occurrences == 0L) next
        remaining <- indices[-match(base, indices)]
        product <- 1
        for (index in remaining) product <- product * values[index]
        total <- total + original[j + 1L] * (occurrences * product)
    }
    total
}
diagnostics_part <- function(data, model, inf, lambda) {
    n <- length(data$train)
    m <- length(data$test)
    base_rate <- sum(data$train_targets) / n
    null_loss <- -(base_rate * log(base_rate) + (1 - base_rate) * log(1 - base_rate))
    lines <- line_text("diagnostics", "newton", "lambda", fixed(lambda))
    add <- function(...) lines <<- c(lines, line_text(...))
    add(
        "fit",
        "null_loss",
        fixed(null_loss, 6L),
        "train_loss",
        fixed(model$train$loss, 6L),
        "mcfadden_r2",
        fixed(1 - model$train$loss / null_loss),
        "deviance",
        fixed(inf$deviance),
        "edf",
        fixed(inf$edf),
        "aic",
        fixed(inf$aic),
        "bic",
        fixed(inf$bic)
    )
    order <- order(inf$probabilities, seq_along(inf$probabilities))
    statistic <- 0
    groups <- character()
    for (group in seq_len(10L)) {
        members <- order[seq.int(((group - 1L) * n) %/% 10L + 1L, (group * n) %/% 10L)]
        observed <- sum(data$train_targets[members])
        expected <- ordered_sum(inf$probabilities[members])
        statistic <- statistic + (observed - expected) * (observed - expected) / (expected * (1 - expected / length(members)))
        groups <- c(
            groups,
            line_text(
                "group",
                group,
                "rows",
                length(members),
                "observed",
                observed,
                "expected",
                fixed(expected)
            )
        )
    }
    add("hosmer_lemeshow_train", "groups", 10L, "statistic", fixed(statistic))
    lines <- c(lines, groups)
    add("newton_iterations")
    for (t in seq_len(10L)) {
        w <- model$checkpoints[[t]]$weights
        direction <- newton_direction(w, data$train_vectors, data$train_targets, lambda)
        decrease <- ordered_sum(direction$gradient * direction$step) / 2
        add(
            "iteration",
            t,
            "objective",
            fixed(objective(w, data$train_vectors, data$train_targets, lambda), 6L),
            "gradient_norm",
            fixed(vector_length(direction$gradient), 6L),
            "step_norm",
            fixed(vector_length(direction$step), 6L),
            "predicted_decrease",
            fixed(decrease, 6L)
        )
    }
    original <- original_units(model$weights, data$overall)
    centre <- probability(score(model$weights, data_vector(data, data$mean_values)))
    for (base in seq_along(data$names)) {
        total <- ordered_sum(vapply(
            seq_along(data$train),
            function(i) inf$probabilities[i] * (1 - inf$probabilities[i]) * slope(
                data$tuples,
                original,
                data$train[[i]]$values,
                base
            ),
            0
        ))
        at_mean <- centre * (1 - centre) * slope(data$tuples, original, data$mean_values, base)
        add("marginal", data$names[base], "average", fixed(total / n), "at_mean", fixed(at_mean))
    }
    for (cut in seq_len(9L)) {
        matrix <- confusion(predict(model$test$probabilities, cut / 10), data$test_targets)
        add(
            "cut",
            paste0("0.", cut),
            "positive",
            matrix$tp + matrix$fp,
            "tp",
            matrix$tp,
            "fp",
            matrix$fp,
            "precision",
            ratio(matrix$tp, matrix$tp + matrix$fp),
            "recall",
            ratio(matrix$tp, matrix$tp + matrix$fn),
            "accuracy",
            ratio(matrix$tp + matrix$tn, m)
        )
    }
    wrong <- which(model$test$predictions != data$test_targets)
    wrong <- wrong[order(-abs(model$test$probabilities[wrong] - data$settings$threshold), wrong)]
    for (i in head(wrong, 5L)) add(
        "error",
        data$test[[i]]$id,
        "actual",
        data$test_targets[i],
        "probability",
        fixed(model$test$probabilities[i], 6L)
    )
    rng <- minstd(data$settings$bootstrap_seed)
    resamples <- data$settings$bootstrap_count
    samples <- lapply(seq_len(resamples), function(b) {
        picks <- vapply(seq_len(m), function(i) draw(rng) %% m + 1L, 0L)
        auc(model$test$probabilities[picks], data$test_targets[picks])
    })
    values <- vapply(samples, function(sample) sample[1L] / sample[2L], 0)
    mean <- ordered_sum(values) / resamples
    sd <- sqrt(ordered_sum((values - mean) * (values - mean)) / (resamples - 1L))
    ordered <- samples[order(values, seq_along(values))]
    tail <- resamples %/% 40L
    add(
        "bootstrap",
        "resamples",
        resamples,
        "seed",
        data$settings$bootstrap_seed,
        "auc_mean",
        fixed(mean),
        "auc_sd",
        fixed(sd),
        "lower",
        fraction(ordered[[tail + 1L]]),
        "upper",
        fraction(ordered[[resamples - tail]])
    )
    add("influence", "effective_parameters", fixed(inf$edf), "large_residuals", sum(abs(inf$residuals) > 2))
    order <- order(-inf$distances, seq_along(inf$distances))
    for (i in head(order, 5L)) add(
        "cook",
        data$train[[i]]$id,
        "actual",
        data$train_targets[i],
        "probability",
        fixed(inf$probabilities[i]),
        "leverage",
        fixed(inf$leverages[i]),
        "residual",
        fixed(inf$residuals[i]),
        "distance",
        fixed(inf$distances[i])
    )
    lines
}
importance_part <- function(data, model, multi) {
    settings <- data$settings
    m <- length(data$test)
    repeats <- settings$permutation_count
    base_auc <- model$test$auc[1L]
    denominator <- model$test$auc[2L]
    baseline_correct <- count_equal(multi$test_predictions, data$test_labels)
    lines <- c(
        line_text("importance", "repeats", repeats, "seed", settings$permutation_seed),
        line_text(
            "baseline",
            "log_loss",
            fixed(model$test$loss, 6L),
            "auc",
            fraction(base_auc, denominator),
            "softmax_accuracy",
            ratio(baseline_correct, m)
        )
    )
    rng <- minstd(settings$permutation_seed)
    for (base in seq_along(data$names)) {
        losses <- numeric(repeats)
        auc_total <- correct_total <- 0L
        for (t in seq_len(repeats)) {
            order <- shuffle_order(seq_len(m), rng)
            vectors <- lapply(seq_len(m), function(j) {
                values <- data$test[[j]]$values
                values[base] <- data$test[[order[j]]]$values[base]
                data_vector(data, values)
            })
            losses[t] <- average_loss(model$weights, vectors, data$test_targets)
            auc_total <- auc_total + auc(model_probabilities(model$weights, vectors), data$test_targets)[1L]
            correct_total <- correct_total + softmax_correct(multi$weights, vectors, data$test_labels)
        }
        increase <- ordered_sum(losses) / repeats - model$test$loss
        lines <- c(
            lines,
            line_text(
                "feature",
                data$names[base],
                "log_loss_increase",
                fixed(increase, 6L),
                "auc",
                fraction(auc_total, repeats * denominator),
                "softmax_accuracy",
                ratio(correct_total, repeats * m)
            )
        )
    }
    lines
}
profile_part <- function(data, model, multi) {
    lines <- "profiles"
    for (base in seq_along(data$names)) {
        column <- vapply(data$train, function(row) row$values[base], 0)
        lo <- min(column)
        hi <- max(column)
        for (step in seq.int(0L, 4L)) {
            values <- data$mean_values
            values[base] <- lo + (hi - lo) * step / 4
            vector <- data_vector(data, values)
            pi <- probability(score(model$weights, vector))
            listed <- vapply(softmax_probabilities(multi$weights, vector), fixed, "")
            lines <- c(
                lines,
                line_text(
                    "profile",
                    data$names[base],
                    "value",
                    fixed(values[base]),
                    "newton",
                    fixed(pi),
                    "softmax",
                    listed
                )
            )
        }
    }
    lines
}
softmax_part <- function(data, multi, newton) {
    settings <- data$settings
    m <- length(data$test)
    k <- data$classes
    table <- matrix(0L, k, k)
    for (i in seq_len(m)) table[data$test_labels[i] + 1L, multi$test_predictions[i] + 1L] <- table[
        data$test_labels[i] + 1L,
        multi$test_predictions[i] + 1L
    ] + 1L
    rows <- rowSums(table)
    columns <- colSums(table)
    lines <- c(
        line_text(
            "softmax",
            "classes",
            k,
            "lambda",
            fixed(settings$softmax_lambda),
            "iterations",
            settings$softmax_iterations
        ),
        "confusion"
    )
    add <- function(...) lines <<- c(lines, line_text(...))
    for (i in seq_len(k)) add(table[i, ])
    for (c in seq.int(0L, k - 1L)) {
        scores <- vapply(multi$test_probabilities, function(v) v[c + 1L], 0)
        targets <- as.integer(data$test_labels == c)
        hits <- table[c + 1L, c + 1L]
        add(
            "class",
            c,
            "precision",
            ratio(hits, columns[c + 1L]),
            "recall",
            ratio(hits, rows[c + 1L]),
            "f1",
            ratio(2L * hits, columns[c + 1L] + rows[c + 1L]),
            "auc",
            fraction(auc(scores, targets))
        )
    }
    diagonal <- sum(diag(table))
    chance <- sum(rows * columns)
    add("accuracy", ratio(diagonal, m), "kappa", ratio(m * diagonal - chance, m * m - chance))
    squares <- vapply(
        seq_len(m),
        function(i) ordered_sum((multi$test_probabilities[[i]] - as.integer(seq.int(
            0L,
            k - 1L
        ) == data$test_labels[i])) ^ 2),
        0
    )
    brier <- ordered_sum(squares) / m
    add(
        "log_loss",
        fixed(softmax_average_loss(multi$weights, data$test_vectors, data$test_labels), 6L),
        "brier",
        fixed(brier, 6L)
    )
    scores <- vapply(multi$test_probabilities, function(v) v[settings$positive + 1L], 0)
    binary_loss <- ordered_sum(vapply(
        seq_len(m),
        function(i) -log(if (data$test_targets[i] == 1L) scores[i] else 1 - scores[i]),
        0
    )) / m
    predictions <- predict(scores, settings$threshold)
    add(
        "binary_view",
        "positive_class",
        settings$positive,
        "auc",
        fraction(auc(scores, data$test_targets)),
        "log_loss",
        fixed(binary_loss, 6L),
        "accuracy",
        ratio(count_equal(predictions, data$test_targets), m),
        "agreement_with_newton",
        paste(count_equal(predictions, newton$test$predictions), m, sep = "/")
    )
    confidences <- vapply(
        seq_len(m),
        function(i) multi$test_probabilities[[i]][multi$test_predictions[i] + 1L],
        0
    )
    bins <- fill_bins(confidences, as.integer(multi$test_predictions == data$test_labels))
    add("confidence")
    lines <- c(lines, bin_lines(bins, "mean_confidence", "accuracy"))
    add("ece", fixed(calibration_error(bins, m)))
    lines
}
one_vs_rest_part <- function(data, multi) {
    lambda <- data$settings$softmax_lambda
    m <- length(data$test)
    lines <- line_text("one_vs_rest", "lambda", fixed(lambda), "newton_iterations", 10L)
    probabilities <- list()
    for (k in seq.int(0L, data$classes - 1L)) {
        y <- as.integer(data$train_labels == k)
        z <- as.integer(data$test_labels == k)
        w <- final_weights(newton_method(data$train_vectors, y, lambda))
        test <- evaluate(w, data$test_vectors, z, data$settings$threshold)
        lines <- c(
            lines,
            line_text(
                "class",
                k,
                "objective",
                fixed(objective(w, data$train_vectors, y, lambda), 6L),
                "auc",
                fraction(test$auc)
            )
        )
        probabilities <- c(probabilities, list(test$probabilities))
    }
    predictions <- vapply(
        seq_len(m),
        function(j) which.max(vapply(probabilities, function(v) v[j], 0)) - 1L,
        0L
    )
    c(
        lines,
        line_text(
            "accuracy",
            ratio(count_equal(predictions, data$test_labels), m),
            "agreement_with_softmax",
            paste(count_equal(predictions, multi$test_predictions), m, sep = "/")
        )
    )
}
map_part <- function(data, model, multi) {
    width <- data$settings$map_width
    height <- data$settings$map_height
    x <- vapply(data$train, function(row) row$values[1L], 0)
    y <- vapply(data$train, function(row) row$values[2L], 0)
    lo_x <- min(x)
    hi_x <- max(x)
    lo_y <- min(y)
    hi_y <- max(y)
    cells <- integer(data$classes)
    class_rows <- probability_rows <- character()
    for (r in seq.int(0L, height - 1L)) {
        class_row <- probability_row <- character()
        for (c in seq.int(0L, width - 1L)) {
            values <- data$mean_values
            values[1L] <- lo_x + (c + 0.5) * (hi_x - lo_x) / width
            values[2L] <- hi_y - (r + 0.5) * (hi_y - lo_y) / height
            vector <- data_vector(data, values)
            predicted <- predicted_class(softmax_probabilities(multi$weights, vector))
            cells[predicted + 1L] <- cells[predicted + 1L] + 1L
            class_row <- c(class_row, as.character(predicted))
            probability_row <- c(
                probability_row,
                as.character(bin_index(probability(score(model$weights, vector))))
            )
        }
        class_rows <- c(class_rows, paste(class_row, collapse = ""))
        probability_rows <- c(probability_rows, paste(probability_row, collapse = ""))
    }
    c(
        line_text("map", data$names[1L], data$names[2L], "width", width, "height", height),
        "softmax_classes",
        class_rows,
        line_text("cells", cells),
        "newton_probability",
        probability_rows
    )
}
join_parts <- function(parts) {
    lines <- character()
    for (part in parts) {
        if (length(lines)) lines <- c(lines, "")
        lines <- c(lines, part)
    }
    lines
}
main <- function() {
    options(scipen = 999)
    data <- do.call(make_data, read_inputs())
    settings <- data$settings
    results <- lapply(settings$lambdas, function(lambda) cross_validate(data, lambda, data$feature_count))
    selection <- select_lambda(results)
    lambda <- selection$best$lambda
    x <- data$train_vectors
    y <- data$train_targets
    gd <- gradient_descent(x, y, lambda, settings$gd_rate, settings$gd_iterations)
    sgd <- stochastic_gradient_descent(
        x,
        y,
        lambda,
        settings$sgd_rate,
        settings$batch_size,
        settings$epochs,
        settings$sgd_seed
    )
    newton <- binary_model("newton", newton_method(x, y, lambda), data)
    models <- list(binary_model("gd", gd, data), binary_model("sgd", sgd, data), newton)
    checkpoints <- softmax_train(
        x,
        data$train_labels,
        data$classes,
        settings$softmax_lambda,
        settings$softmax_rate,
        settings$softmax_iterations
    )
    w <- final_weights(checkpoints)
    probabilities <- lapply(data$test_vectors, function(v) softmax_probabilities(w, v))
    multi <- list(
        weights = w,
        checkpoints = checkpoints,
        test_probabilities = probabilities,
        test_predictions = vapply(probabilities, predicted_class, 0L)
    )
    inf <- influence(newton$weights, x, y, lambda)
    parts <- list(
        data_part(data),
        validation_part(data, results, selection),
        lambda_path_part(data),
        degree_part(data, lambda),
        learning_part(data, lambda)
    )
    parts <- c(
        parts,
        lapply(models, function(model) binary_part(data, model, lambda)),
        list(
            comparison_part(data, models),
            diagnostics_part(data, newton, inf, lambda),
            importance_part(data, newton, multi),
            profile_part(data, newton, multi),
            softmax_part(data, multi, newton),
            one_vs_rest_part(data, multi),
            map_part(data, newton, multi)
        )
    )
    outputs <- list(
        "weights.txt" = join_parts(weights_parts(data, models, multi, inf, lambda)),
        "loss_trace.csv" = loss_trace_lines(data, models, multi, lambda),
        "predictions.csv" = prediction_lines(data, models, multi),
        "evaluation.txt" = join_parts(parts),
        "roc.csv" = roc_lines(data, models)
    )
    dir.create("output", showWarnings = FALSE)
    for (name in names(outputs)) writeLines(outputs[[name]], file.path("output", name), useBytes = TRUE)
}
main()
