script_args <- grep("^--file=", commandArgs(), value = TRUE)
source_dir <- if (length(script_args)) dirname(sub("^--file=", "", script_args[1L])) else "R"
for (unit in c("dataset", "scaling", "neighbors", "validation", "report")) source(file.path(source_dir, paste0(unit, ".R")))

build_grid <- function(settings) {
  models <- list()
  for (k in settings$K_VALUES) for (metric in settings$METRICS) for (weighting in settings$WEIGHTINGS) for (scaling in settings$SCALINGS) models[[length(models) + 1L]] <- model_record(k, metric, weighting, scaling)
  models
}

correct_count <- function(predictions, rows) sum(vapply(seq_along(rows), function(index) predictions[[index]]$label == rows[[index]]$label, logical(1L)))
prediction_errors <- function(predictions, rows) vapply(seq_along(rows), function(index) predictions[[index]]$estimate - rows[[index]]$target, numeric(1L))
best_classifier <- function(results) results[[which.max(vapply(results, function(result) result$correct, integer(1L)))]]
best_regressor <- function(results) results[[which.min(vapply(results, function(result) four_decimal(result$rmse), numeric(1L)))]]
id_order <- function(rows) rows[order(vapply(rows, function(row) row$id, character(1L)), method = "radix")]

cross_validate <- function(models, rows, count, features) {
  predictions <- lapply(models, function(model) vector("list", length(rows)))
  spaces <- unique(vapply(models, function(model) paste(model$scaling, model$metric, sep = "/"), character(1L)))
  for (fold in stratified_folds(rows, count)) {
    training <- rows[!seq_along(rows) %in% fold]
    queries <- rows[fold]
    for (space in spaces) {
      fields <- strsplit(space, "/", fixed = TRUE)[[1L]]
      orders <- neighbor_orders(training, queries, fields[1L], fields[2L], features)
      for (index in seq_along(models)) {
        model <- models[[index]]
        if (model$scaling != fields[1L] || model$metric != fields[2L]) next
        for (position in seq_along(fold)) predictions[[index]][[fold[position]]] <- prediction_from_order(orders[[position]], model$k, model$weighting)
      }
    }
  }
  lapply(seq_along(models), function(index) {
    predicted <- predictions[[index]]
    hits <- vapply(seq_along(rows), function(position) predicted[[position]]$label == rows[[position]]$label, logical(1L))
    list(model = models[[index]], predictions = predicted, hits = hits, correct = sum(hits), rmse = rmse(prediction_errors(predicted, rows)))
  })
}

label_counts <- function(rows, labels) paste(vapply(labels, function(label) paste(label, sum(vapply(rows, function(row) row$label == label, logical(1L)))), character(1L)), collapse = " ")
join_parts <- function(parts) unlist(lapply(seq_along(parts), function(index) c(if (index > 1L) "", parts[[index]])), use.names = FALSE)

evaluation_lines <- function(rows, predictions, labels) {
  matrix <- matrix(0L, length(labels), length(labels), dimnames = list(labels, labels))
  for (index in seq_along(rows)) matrix[rows[[index]]$label, predictions[[index]]$label] <- matrix[rows[[index]]$label, predictions[[index]]$label] + 1L
  lines <- paste("true\\predicted", paste(labels, collapse = " "))
  for (label in labels) lines <- c(lines, paste(label, paste(matrix[label, ], collapse = " ")))
  totals <- numeric(3L)
  valued <- integer(3L)
  for (label in labels) {
    hits <- matrix[label, label]
    predicted <- sum(matrix[, label])
    actual <- sum(matrix[label, ])
    numerators <- c(hits, hits, 2L * hits)
    denominators <- c(predicted, actual, predicted + actual)
    for (index in seq_len(3L)) if (denominators[index] > 0L) {
      totals[index] <- totals[index] + numerators[index] / denominators[index]
      valued[index] <- valued[index] + 1L
    }
    lines <- c(lines, paste("class", label, "precision", fraction_text(hits, predicted), "recall", fraction_text(hits, actual), "f1", fraction_text(2L * hits, predicted + actual), "support", actual))
  }
  averages <- vapply(seq_len(3L), function(index) if (valued[index]) fixed(totals[index] / valued[index]) else "-", character(1L))
  c(lines, paste("macro precision", averages[1L], "recall", averages[2L], "f1", averages[3L]))
}

reliability_lines <- function(rows, predictions, bounds) {
  lowers <- c(0, bounds)
  counts <- hits <- integer(length(lowers))
  shares <- numeric(length(lowers))
  for (index in seq_along(rows)) {
    prediction <- predictions[[index]]
    bin <- sum(bounds <= prediction$share) + 1L
    counts[bin] <- counts[bin] + 1L
    hits[bin] <- hits[bin] + as.integer(prediction$label == rows[[index]]$label)
    shares[bin] <- shares[bin] + prediction$share
  }
  vapply(seq_along(lowers), function(index) {
    prefix <- paste("bin", fixed(lowers[index], 2L), "rows", counts[index])
    if (!counts[index]) prefix else paste(prefix, "correct", ratio_text(hits[index], counts[index]), "share", fixed(shares[index] / counts[index]))
  }, character(1L))
}

leave_one_out_parts <- function(a) {
  model <- a$classifier$model
  by_k <- lapply(a$settings$K_VALUES, function(k) vector("list", length(a$train)))
  estimates <- numeric(length(a$train))
  for (index in seq_along(a$train)) {
    training <- a$train[-index]
    query <- a$train[index]
    neighbors <- neighbor_orders(training, query, model$scaling, model$metric, a$features)[[1L]]
    for (position in seq_along(a$settings$K_VALUES)) by_k[[position]][[index]] <- prediction_from_order(neighbors, a$settings$K_VALUES[position], model$weighting)
    estimates[index] <- predict_rows(a$regressor$model, training, query, a$features)[[1L]]$estimate
  }
  selected <- by_k[[match(model$k, a$settings$K_VALUES)]]
  errors <- which(!vapply(seq_along(a$train), function(index) selected[[index]]$label == a$train[[index]]$label, logical(1L)))
  class_errors <- vapply(a$labels, function(label) paste(label, sum(vapply(a$train[errors], function(row) row$label == label, logical(1L)))), character(1L))
  classifier <- c(paste("leave_one_out classifier", model_text(model)), paste("errors", ratio_text(length(errors), length(a$train))), paste("class_errors", paste(class_errors, collapse = " ")))
  errors <- errors[order(vapply(a$train[errors], function(row) row$id, character(1L)), method = "radix")]
  for (index in errors) classifier <- c(classifier, paste(a$train[[index]]$id, "true", a$train[[index]]$label, "predicted", selected[[index]]$label, "share", fixed(selected[[index]]$share)))
  residuals <- estimates - vapply(a$train, function(row) row$target, numeric(1L))
  regressor <- c(paste("leave_one_out regressor", model_text(a$regressor$model)), paste("rmse", fixed(rmse(residuals)), "mae", fixed(mae(residuals))), paste("largest", a$settings$TOP, "residuals"))
  ranking <- order(-four_decimal(abs(residuals)), vapply(a$train, function(row) row$id, character(1L)), method = "radix")
  for (index in head(ranking, a$settings$TOP)) regressor <- c(regressor, paste(a$train[[index]]$id, "target", fixed(a$train[[index]]$target), "estimate", fixed(estimates[index]), "residual", fixed(residuals[index])))
  per_k <- paste0("leave_one_out by k metric=", model$metric, " weighting=", model$weighting, " scaling=", model$scaling)
  for (position in seq_along(a$settings$K_VALUES)) per_k <- c(per_k, paste0("k=", a$settings$K_VALUES[position], " correct ", ratio_text(correct_count(by_k[[position]], a$train), length(a$train)), " rmse ", fixed(rmse(prediction_errors(by_k[[position]], a$train)))))
  list(classifier, regressor, per_k)
}

nested_part <- function(a) {
  lines <- paste("nested_cross_validation folds", a$settings$FOLDS)
  estimates <- numeric(length(a$train))
  total <- 0L
  for (number in seq_along(a$folds)) {
    fold <- a$folds[[number]]
    inner <- a$train[!seq_along(a$train) %in% fold]
    validation <- a$train[fold]
    results <- cross_validate(a$grid, inner, a$settings$FOLDS, a$features)
    classifier <- best_classifier(results)
    regressor <- best_regressor(results)
    predicted <- predict_rows(classifier$model, inner, validation, a$features)
    correct <- correct_count(predicted, validation)
    total <- total + correct
    predicted <- predict_rows(regressor$model, inner, validation, a$features)
    estimates[fold] <- vapply(predicted, function(prediction) prediction$estimate, numeric(1L))
    lines <- c(lines, paste("fold", number, "classifier", model_text(classifier$model), "inner", fixed(classifier$correct / length(inner)), "outer", ratio_text(correct, length(fold))),
               paste("fold", number, "regressor", model_text(regressor$model), "inner", fixed(regressor$rmse), "outer", fixed(rmse(prediction_errors(predicted, validation)))))
  }
  c(lines, paste("nested accuracy", ratio_text(total, length(a$train)), "rmse", fixed(rmse(estimates - vapply(a$train, function(row) row$target, numeric(1L))))))
}

feature_selection_part <- function(a) {
  model <- a$classifier$model
  current <- selected <- a$features
  selected_correct <- a$classifier$correct
  lines <- c(paste("feature_selection", model_text(model)), paste("start features", paste(a$feature_names[current], collapse = " "), "correct", ratio_text(selected_correct, length(a$train))))
  step <- 0L
  while (length(current) >= 3L) {
    step <- step + 1L
    candidates <- vapply(current, function(feature) cross_validate(list(model), a$train, a$settings$FOLDS, setdiff(current, feature))[[1L]]$correct, integer(1L))
    removed <- current[which.max(candidates)]
    correct <- max(candidates)
    listing <- paste(paste(a$feature_names[current], candidates), collapse = " ")
    current <- setdiff(current, removed)
    lines <- c(lines, paste("step", step, "remove", a$feature_names[removed], "correct", ratio_text(correct, length(a$train)), "candidates", listing))
    if (correct >= selected_correct) {
      selected <- current
      selected_correct <- correct
    }
  }
  predicted <- predict_rows(model, a$train, a$labelled, selected)
  c(lines, paste("selected features", paste(a$feature_names[selected], collapse = " "), "correct", ratio_text(selected_correct, length(a$train))), paste("selected test", ratio_text(correct_count(predicted, a$labelled), length(a$labelled))))
}

metrics_lines <- function(a) {
  train_count <- length(a$train)
  classifier <- a$classifier
  regressor <- a$regressor
  classifier_summary <- function(result) paste(model_text(result$model), "correct", ratio_text(result$correct, train_count), "rmse", fixed(result$rmse))
  regressor_summary <- function(result) paste(model_text(result$model), "rmse", fixed(result$rmse), "correct", ratio_text(result$correct, train_count))
  parts <- list(c(paste("data train", train_count, "test", length(a$test), "labelled", length(a$labelled), "targets", length(a$targeted), "features", length(a$features), "classes", length(a$labels)), paste("classes", label_counts(a$train, a$labels))))
  for (method in a$settings$SCALINGS) {
    scaling <- compute_scaling(a$train, method)
    lines <- paste("scaling", method)
    for (feature in a$features) lines <- c(lines, paste(a$feature_names[feature], "center", fixed(scaling$centers[feature], 6L), "scale", fixed(scaling$scales[feature], 6L)))
    parts[[length(parts) + 1L]] <- lines
  }
  lines <- paste("folds", a$settings$FOLDS)
  for (number in seq_along(a$folds)) lines <- c(lines, paste("fold", number, "size", length(a$folds[[number]]), label_counts(a$train[a$folds[[number]]], a$labels)))
  parts[[length(parts) + 1L]] <- lines
  parts[[length(parts) + 1L]] <- c(paste("grid", length(a$grid)), paste("best_classifier", classifier_summary(classifier)), paste("best_regressor", regressor_summary(regressor)))
  accuracy <- order(-vapply(a$results, function(result) result$correct, integer(1L)), seq_along(a$results))
  error <- order(vapply(a$results, function(result) four_decimal(result$rmse), numeric(1L)), seq_along(a$results))
  for (kind in c("accuracy", "rmse")) {
    ranking <- head(if (kind == "accuracy") accuracy else error, a$settings$TOP)
    lines <- paste("top", a$settings$TOP, "by", kind)
    for (rank in seq_along(ranking)) lines <- c(lines, paste(rank, if (kind == "accuracy") classifier_summary(a$results[[ranking[rank]]]) else regressor_summary(a$results[[ranking[rank]]])))
    parts[[length(parts) + 1L]] <- lines
  }
  groups <- list(k = a$settings$K_VALUES, metric = a$settings$METRICS, weighting = a$settings$WEIGHTINGS, scaling = a$settings$SCALINGS)
  for (item in names(groups)) {
    lines <- paste("best per", item)
    for (value in groups[[item]]) {
      results <- Filter(function(result) result$model[[item]] == value, a$results)
      chosen_classifier <- best_classifier(results)
      chosen_regressor <- best_regressor(results)
      lines <- c(lines, paste(paste0(item, "=", value), "classifier", model_text(chosen_classifier$model), "accuracy", fixed(chosen_classifier$correct / train_count), "regressor", model_text(chosen_regressor$model), "rmse", fixed(chosen_regressor$rmse)))
    }
    parts[[length(parts) + 1L]] <- lines
  }
  lines <- "classifier folds"
  for (number in seq_along(a$folds)) lines <- c(lines, paste("fold", number, "correct", ratio_text(sum(classifier$hits[a$folds[[number]]]), length(a$folds[[number]]))))
  parts[[length(parts) + 1L]] <- lines
  lines <- "regressor folds"
  for (number in seq_along(a$folds)) {
    fold <- a$folds[[number]]
    lines <- c(lines, paste("fold", number, "size", length(fold), "rmse", fixed(rmse(prediction_errors(regressor$predictions[fold], a$train[fold])))))
  }
  parts[[length(parts) + 1L]] <- lines
  parts[[length(parts) + 1L]] <- c("cross_validation classes", evaluation_lines(a$train, classifier$predictions, a$labels))
  parts[[length(parts) + 1L]] <- c("cross_validation reliability", reliability_lines(a$train, classifier$predictions, a$settings$BINS))
  lines <- "mcnemar"
  for (metric in a$settings$METRICS) {
    comparison <- best_classifier(Filter(function(result) result$model$metric == metric, a$results))
    only_selected <- sum(classifier$hits & !comparison$hits)
    only_comparison <- sum(comparison$hits & !classifier$hits)
    disagreements <- only_selected + only_comparison
    base <- max(0L, abs(only_selected - only_comparison) - 1L)
    numerator <- base * base
    statistic <- if (disagreements) fraction_text(numerator, disagreements) else "0/1 0.0000"
    lines <- c(lines, paste(model_text(comparison$model), "b", only_selected, "c", only_comparison, "statistic", statistic, "significant", if (1000 * numerator > 3841 * disagreements) "yes" else "no"))
  }
  parts[[length(parts) + 1L]] <- lines
  parts <- c(parts, leave_one_out_parts(a), list(nested_part(a)), list(feature_selection_part(a)))
  labelled_predictions <- a$test_predictions[a$labelled_indices]
  parts[[length(parts) + 1L]] <- c(paste("test classification", model_text(classifier$model)), paste("labelled", length(a$labelled), "correct", ratio_text(correct_count(labelled_predictions, a$labelled), length(a$labelled))), evaluation_lines(a$labelled, labelled_predictions, a$labels))
  parts[[length(parts) + 1L]] <- c("test reliability", reliability_lines(a$labelled, labelled_predictions, a$settings$BINS))
  margins <- vapply(a$test_predictions, function(prediction) prediction$share - prediction$runner_share, numeric(1L))
  lines <- paste("uncertain", a$settings$TOP, "test rows")
  for (index in head(order(four_decimal(margins), seq_along(a$test)), a$settings$TOP)) {
    row <- a$test[[index]]
    prediction <- a$test_predictions[[index]]
    lines <- c(lines, paste(row$id, "predicted", prediction$label, "share", fixed(prediction$share), "runner_up", prediction$runner_up, "share", fixed(prediction$runner_share), "margin", fixed(margins[index]), "true", if (nzchar(row$label)) row$label else "-"))
  }
  parts[[length(parts) + 1L]] <- lines
  estimates <- a$test_estimates[a$targeted_indices]
  errors <- estimates - vapply(a$targeted, function(row) row$target, numeric(1L))
  lines <- c(paste("test regression", model_text(regressor$model)), paste("targets", length(a$targeted), "rmse", fixed(rmse(errors)), "mae", fixed(mae(errors)), "r2", fixed(r_squared(errors, vapply(a$targeted, function(row) row$target, numeric(1L))))))
  for (label in a$labels) {
    chosen <- vapply(a$targeted, function(row) row$label == label, logical(1L))
    lines <- c(lines, paste("class", label, "targets", sum(chosen), "rmse", if (any(chosen)) fixed(rmse(errors[chosen])) else "-"))
  }
  parts[[length(parts) + 1L]] <- lines
  lines <- "misclassified test rows"
  count <- 0L
  for (index in a$labelled_indices) {
    row <- a$test[[index]]
    prediction <- a$test_predictions[[index]]
    if (prediction$label == row$label) next
    count <- count + 1L
    lines <- c(lines, paste(row$id, "true", row$label, "predicted", prediction$label, "share", fixed(prediction$share)))
    for (neighbor in prediction$neighbors) lines <- c(lines, paste0("  ", neighbor$row$id, " ", neighbor$row$label, " ", fixed(neighbor$distance)))
  }
  parts[[length(parts) + 1L]] <- c(lines, paste("count", count))
  join_parts(parts)
}

classifier_space <- function(a) {
  scaling <- compute_scaling(a$train, a$classifier$model$scaling)
  references <- lapply(a$train, function(row) transform_values(scaling, row$values, a$features))
  train_ids <- vapply(a$train, function(row) row$id, character(1L))
  gaps <- list()
  for (row in c(a$train, a$test)) {
    vector <- transform_values(scaling, row$values, a$features)
    gaps[[row$id]] <- setNames(vapply(references, function(reference) distance(vector, reference, a$classifier$model$metric), numeric(1L)), train_ids)
  }
  gaps
}

space_order <- function(space, query, rows) sort_neighbors(lapply(rows, function(row) list(distance = unname(space[[query$id]][row$id]), row = row)))
space_vote <- function(a, space, query, rows, k) vote(head(space_order(space, query, rows), k), a$classifier$model$weighting)
nearest_label <- function(space, query, rows) space_order(space, query, rows)[[1L]]$row$label

wilson_editing <- function(a, space, rows) {
  current <- rows
  passes <- list()
  repeat {
    removals <- list()
    for (row in current) {
      others <- Filter(function(other) other$id != row$id, current)
      prediction <- space_vote(a, space, row, others, a$settings$EDIT_K)
      if (prediction$label != row$label) removals[[length(removals) + 1L]] <- list(row = row, prediction = prediction)
    }
    passes[[length(passes) + 1L]] <- removals
    if (!length(removals)) return(list(rows = current, passes = passes))
    removed <- vapply(removals, function(removal) removal$row$id, character(1L))
    current <- Filter(function(row) !row$id %in% removed, current)
  }
}

hart_condensing <- function(space, rows) {
  store <- rows[1L]
  stored <- rows[[1L]]$id
  scans <- 0L
  repeat {
    scans <- scans + 1L
    added <- FALSE
    for (row in rows) {
      if (row$id %in% stored) next
      if (nearest_label(space, row, store) != row$label) {
        store[[length(store) + 1L]] <- row
        stored <- c(stored, row$id)
        added <- TRUE
      }
    }
    if (!added) return(list(rows = id_order(store), scans = scans))
  }
}

id_lines <- function(rows) {
  ids <- vapply(rows, function(row) row$id, character(1L))
  vapply(seq.int(1L, length(ids), by = 10L), function(first) paste(ids[seq.int(first, min(first + 9L, length(ids)))], collapse = " "), character(1L))
}

prototypes_lines <- function(a) {
  space <- classifier_space(a)
  ordered <- id_order(a$train)
  edited <- wilson_editing(a, space, ordered)
  condensed <- hart_condensing(space, ordered)
  edited_condensed <- hart_condensing(space, edited$rows)
  parts <- list(paste("space", model_text(a$classifier$model)))
  lines <- paste0("editing k=", a$settings$EDIT_K)
  for (number in seq_along(edited$passes)) {
    removals <- edited$passes[[number]]
    lines <- c(lines, paste("pass", number, "removed", length(removals)))
    for (removal in removals) lines <- c(lines, paste0("  ", removal$row$id, " true ", removal$row$label, " predicted ", removal$prediction$label, " share ", fixed(removal$prediction$share)))
  }
  parts[[length(parts) + 1L]] <- c(lines, paste("edited size", length(edited$rows), "removed", length(a$train) - length(edited$rows)))
  parts[[length(parts) + 1L]] <- c(paste("condensing original scans", condensed$scans, "size", length(condensed$rows)), paste("condensing edited scans", edited_condensed$scans, "size", length(edited_condensed$rows)))
  sets <- list(original = ordered, edited = edited$rows, condensed = condensed$rows, edited_condensed = edited_condensed$rows)
  lines <- character()
  for (name in names(sets)) {
    rows <- sets[[name]]
    knn <- nearest <- 0L
    for (query in a$labelled) {
      if (space_vote(a, space, query, rows, a$classifier$model$k)$label == query$label) knn <- knn + 1L
      if (nearest_label(space, query, rows) == query$label) nearest <- nearest + 1L
    }
    lines <- c(lines, paste("set", name, "size", length(rows), label_counts(rows, a$labels), "knn", ratio_text(knn, length(a$labelled)), "1nn", ratio_text(nearest, length(a$labelled))))
  }
  parts[[length(parts) + 1L]] <- lines
  parts[[length(parts) + 1L]] <- c("prototypes condensed", id_lines(condensed$rows))
  parts[[length(parts) + 1L]] <- c("prototypes edited_condensed", id_lines(edited_condensed$rows))
  lines <- "borders"
  total <- 0L
  for (label in a$labels) {
    members <- Filter(function(row) row$label == label, ordered)
    borders <- 0L
    same_total <- other_total <- 0
    for (query in members) {
      neighbors <- space_order(space, query, Filter(function(row) row$id != query$id, ordered))
      same <- Filter(function(neighbor) neighbor$row$label == label, neighbors)[[1L]]$distance
      other <- Filter(function(neighbor) neighbor$row$label != label, neighbors)[[1L]]$distance
      if (neighbors[[1L]]$row$label != label) borders <- borders + 1L
      same_total <- same_total + same
      other_total <- other_total + other
    }
    total <- total + borders
    lines <- c(lines, paste("class", label, "size", length(members), "border", borders, "same", fixed(same_total / length(members)), "other", fixed(other_total / length(members))))
  }
  parts[[length(parts) + 1L]] <- c(lines, paste("border total", ratio_text(total, length(a$train))))
  occurrences <- setNames(integer(length(a$train)), vapply(a$train, function(row) row$id, character(1L)))
  for (prediction in a$test_predictions) for (neighbor in prediction$neighbors) occurrences[neighbor$row$id] <- occurrences[neighbor$row$id] + 1L
  hub_order <- order(-occurrences, names(occurrences), method = "radix")
  lines <- paste0("hubs k=", a$classifier$model$k, " queries ", length(a$test))
  for (index in head(hub_order, a$settings$TOP)) lines <- c(lines, paste(a$train[[index]]$id, a$train[[index]]$label, occurrences[index]))
  parts[[length(parts) + 1L]] <- c(lines, paste("anti_hubs", sum(occurrences == 0L)))
  join_parts(parts)
}

learning_curve_lines <- function(a) {
  lines <- "n,train_size,correct,accuracy,rmse"
  for (limit in a$settings$CURVE) {
    counts <- setNames(integer(length(a$labels)), a$labels)
    rows <- list()
    for (row in a$train) if (counts[row$label] < limit) {
      counts[row$label] <- counts[row$label] + 1L
      rows[[length(rows) + 1L]] <- row
    }
    predicted <- predict_rows(a$classifier$model, rows, a$labelled, a$features)
    correct <- correct_count(predicted, a$labelled)
    estimated <- predict_rows(a$regressor$model, rows, a$targeted, a$features)
    lines <- c(lines, paste(limit, length(rows), correct, fixed(correct / length(a$labelled)), fixed(rmse(prediction_errors(estimated, a$targeted))), sep = ","))
  }
  lines
}

run_experiment <- function(data) {
  a <- new.env(parent = emptyenv())
  a$feature_names <- data$features
  a$features <- seq_along(data$features)
  a$train <- data$train
  a$test <- data$test
  a$settings <- data$settings
  a$labels <- sort(unique(vapply(a$train, function(row) row$label, character(1L))), method = "radix")
  a$labelled_indices <- which(vapply(a$test, function(row) nzchar(row$label), logical(1L)))
  a$targeted_indices <- which(vapply(a$test, function(row) !is.na(row$target), logical(1L)))
  a$labelled <- a$test[a$labelled_indices]
  a$targeted <- a$test[a$targeted_indices]
  a$grid <- build_grid(a$settings)
  a$folds <- stratified_folds(a$train, a$settings$FOLDS)
  a$results <- cross_validate(a$grid, a$train, a$settings$FOLDS, a$features)
  a$classifier <- best_classifier(a$results)
  a$regressor <- best_regressor(a$results)
  a$test_predictions <- predict_rows(a$classifier$model, a$train, a$test, a$features)
  a$test_estimates <- vapply(predict_rows(a$regressor$model, a$train, a$test, a$features), function(prediction) prediction$estimate, numeric(1L))
  a
}

main <- function() {
  a <- run_experiment(read_dataset())
  grid <- c("k,metric,weighting,scaling,correct,accuracy,rmse", vapply(a$results, function(result) {
    model <- result$model
    paste(model$k, model$metric, model$weighting, model$scaling, result$correct, fixed(result$correct / length(a$train)), fixed(result$rmse), sep = ",")
  }, character(1L)))
  predictions <- c("id,label,vote_share,estimate", vapply(seq_along(a$test), function(index) paste(a$test[[index]]$id, a$test_predictions[[index]]$label, fixed(a$test_predictions[[index]]$share), fixed(a$test_estimates[index]), sep = ","), character(1L)))
  outputs <- list("cv_grid.csv" = grid, "predictions.csv" = predictions, "metrics.txt" = metrics_lines(a), "learning_curve.csv" = learning_curve_lines(a), "prototypes.txt" = prototypes_lines(a))
  dir.create("output", showWarnings = FALSE)
  for (name in names(outputs)) write_lines(name, outputs[[name]])
}

main()
