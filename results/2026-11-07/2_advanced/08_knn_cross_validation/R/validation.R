model_record <- function(k, metric, weighting, scaling) list(k = k, metric = metric, weighting = weighting, scaling = scaling)
model_text <- function(model) paste0("k=", model$k, " metric=", model$metric, " weighting=", model$weighting, " scaling=", model$scaling)

stratified_folds <- function(rows, count) {
  ordered <- order(vapply(rows, function(row) row$label, character(1L)), vapply(rows, function(row) row$id, character(1L)), method = "radix")
  folds <- vector("list", count)
  for (position in seq_along(ordered)) {
    fold <- (position - 1L) %% count + 1L
    folds[[fold]] <- c(folds[[fold]], ordered[position])
  }
  lapply(folds, sort)
}

neighbor_orders <- function(training, queries, method, metric, features) {
  scaling <- compute_scaling(training, method)
  references <- lapply(training, function(row) list(values = transform_values(scaling, row$values, features), row = row))
  lapply(queries, function(query) neighbor_order(transform_values(scaling, query$values, features), references, metric))
}

prediction_from_order <- function(order, k, weighting) {
  nearest <- head(order, k)
  prediction <- vote(nearest, weighting)
  prediction$estimate <- estimate(nearest, weighting)
  prediction$neighbors <- nearest
  prediction
}

predict_rows <- function(model, training, queries, features) lapply(neighbor_orders(training, queries, model$scaling, model$metric, features), prediction_from_order, k = model$k, weighting = model$weighting)
rmse <- function(errors) sqrt(real_sum(errors * errors) / length(errors))
mae <- function(errors) real_sum(abs(errors)) / length(errors)
r_squared <- function(errors, targets) {
  mean <- real_sum(targets) / length(targets)
  1 - real_sum(errors * errors) / real_sum((targets - mean) * (targets - mean))
}
